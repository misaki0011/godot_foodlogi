"""Generate the small set of block-style glTF props the game still needs.

The original Kenney asset pack was deleted from the repo, so every block and
prop here is procedurally rebuilt as a simple, low-poly, vertex-colored mesh
-- no textures needed.

Art direction: the board is a slab of chocolate. Every terrain and route tile
is a FLAT square plate with a chamfered rim, so two neighbours meet in a
shallow V groove and the map reads as a bar of chocolate squares rather than
as a field of chunky cubes. Nothing on a tile is modelled any more (no grass
caps, no corner tufts, no cobbles) -- the tiles are plain colour, and all the
visual interest on open ground comes from the separate vegetation props
scattered over it (see build_tree_round and friends), the same way the
reference art puts trees and bushes on otherwise-featureless tiles.

Every block is authored at its real, final 2.0 x 2.0 world-space footprint
-- matching the GridMap's cell_size exactly -- so it can be placed with
position alone and no scale transform anywhere in the pipeline.

Terrain tiles keep their top face at local y = TILE_TOP_Y (1.0), which is the
one number the rest of the game is built around: TerrainRenderer places a
block at map_to_local(cell), and Main/NodeSpawner put everything that stands
on a tile at map_to_local(cell) + (0, 1, 0). Changing a tile's thickness is
therefore only ever allowed to move its BOTTOM.

Vegetation props are authored origin-at-base (y = 0 is the bottom of the
trunk/planter), so they can be dropped straight onto that same surface.

Every mesh gets an explicit matte (non-metallic, fully rough) material --
without one, Godot's glTF import falls back to a shinier default that
picks up visible reflections/banding from the editor's sky, which reads as
a "weird texture" despite there being no texture in this pipeline at all.

Run with: uv run --python .venv tools/asset_gen/generate_blocks.py
"""

from __future__ import annotations

import math

import numpy as np
import trimesh

WOOD_LIGHT = (168, 122, 78, 255)
WOOD_DARK = (107, 74, 42, 255)
CHEST_BASE = (122, 91, 63, 255)
CHEST_LID = (94, 67, 45, 255)
METAL_BAND = (150, 150, 158, 255)
LATCH_GOLD = (201, 162, 39, 255)

# ---------------------------------------------------------------- tile shape
#
# A tile is three stacked pieces:
#
#   PLATE   the light, flat, coloured top face -- the chocolate square itself.
#   BODY    a chamfered block in the tile's DARKER shade, a touch wider than
#           the plate and a touch shorter, so a dark rim shows all the way
#           around the plate and the chamfer falls away from it.
#   SKIRT   a plain, full-footprint block under the body.
#
# The rim is not decoration, it is the grid line. Two neighbouring tiles put
# their rims together and the seam between them reads as a dark groove, the
# same job the old baked-in border strip did -- and, like that strip, it has to
# come from COLOUR rather than from the chamfer's own shading, because shadows
# are a desktop-only luxury here (DayCycle.shadows_available()). A groove that
# only exists as a shadow leaves the whole board a single flat green sheet on
# web and mobile.
#
# The plate also stands TILE_PLATE_LIP proud of the body rather than flush with
# it. Flush would put two large coplanar faces in the same place and the two
# would z-fight across the entire map.
#
# The skirt is what stops the chamfer from becoming a hole. The body is only
# its full 2.0 width across a band at its middle -- above and below that the
# chamfer pulls it in -- so if the piece under it were inset too, two
# neighbouring tiles would leave a gap at the bottom of the groove that the
# camera can see straight through. A full-width skirt closes it.
TILE_FOOTPRINT = 2.0
TILE_TOP_Y = 1.0  # must match Main/NodeSpawner's +1.0 surface offset
TILE_BODY_THICKNESS = 0.30
TILE_SKIRT_THICKNESS = 0.34
TILE_CHAMFER = 0.07
TILE_PLATE_INSET = 0.09  # per side; with the chamfer this is the visible groove half-width
TILE_PLATE_LIP = 0.02
TILE_PLATE_THICKNESS = 0.06

# Route plates sit ON a terrain tile and are much thinner, so they get a
# smaller chamfer and a tighter rim -- at the terrain's numbers there would be
# almost no flat band left in the middle for one route tile to meet the next
# across.
ROUTE_CHAMFER = 0.05
ROUTE_PLATE_INSET = 0.07
ROUTE_PLATE_LIP = 0.02
ROUTE_PLATE_THICKNESS = 0.06

# Terrain (2x2 world-space footprint, placed with position only, no scale).
GRASS_TOP = (166, 197, 114, 255)
GRASS_SIDE = (114, 144, 74, 255)
WATER_TOP = (124, 194, 212, 255)
WATER_SIDE = (78, 140, 166, 255)
WATER_RIPPLE = (196, 232, 240, 255)

# Route tiles (2x2 world-space footprint too; height is a thin plate on top of
# the terrain, authored directly in world-space meters and mirrored by
# Main.ROUTE_LEVEL_HEIGHTS). The three tiers read as sand -> orange decking ->
# dark plum, which is the reference art's own tile palette.
DIRT_ROAD_TOP = (233, 219, 178, 255)
DIRT_ROAD_SIDE = (184, 166, 122, 255)
PAVED_TOP = (232, 166, 84, 255)
PAVED_SIDE = (180, 116, 48, 255)
MAIN_TOP = (92, 62, 96, 255)
MAIN_SIDE = (60, 38, 64, 255)
MAIN_STRIPE = (214, 200, 216, 255)

# Vegetation.
TRUNK_WARM = (150, 96, 74, 255)
TRUNK_DARK = (118, 78, 58, 255)
LEAF_MID = (124, 168, 84, 255)
LEAF_LIGHT = (152, 194, 106, 255)
LEAF_DARK = (106, 152, 80, 255)
FLOWER = (246, 240, 226, 255)
# Plum rather than the reference art's terracotta. Red is spoken for on this
# map -- it is the colour of an unfilled order, an over-congested tile and a
# settlement in need (see MarkerColors and Main.GRADE_COLORS) -- and a field of
# small red dots scattered over the ground reads as a board covered in
# warnings from the game's own camera height.
PLANTER_CLAY = (124, 86, 138, 255)
PLANTER_RIM = (150, 110, 164, 255)


def _box(extents, translation, color) -> trimesh.Trimesh:
    mesh = trimesh.creation.box(extents=extents)
    mesh.apply_translation(translation)
    mesh.visual.vertex_colors = np.tile(color, (len(mesh.vertices), 1))
    return mesh


def _chamfered_box(extents, translation, color, chamfer) -> list[trimesh.Trimesh]:
    """A box with every edge cut back, built as three overlapping boxes.

    Concatenation is not a boolean union, so the interior faces stay in the
    mesh -- they are simply never visible on an opaque, vertex-coloured solid,
    and this keeps the whole pipeline to axis-aligned boxes with no CSG
    dependency. The silhouette is what matters: the corners are gone, so the
    plate reads as a moulded chocolate square instead of a hard-edged slab.
    """
    w, h, d = extents
    c = chamfer
    return [
        _box((w, h - 2 * c, d - 2 * c), translation, color),
        _box((w - 2 * c, h, d - 2 * c), translation, color),
        _box((w - 2 * c, h - 2 * c, d), translation, color),
    ]


def _plated_block(top_y, body_thickness, chamfer, inset, lip, plate_thickness, top_color, side_color):
    """The shared PLATE-over-BODY sandwich described in the tile-shape comment:
    a chamfered block in the dark shade, with the light top face inset and
    raised on it. `top_y` is where the finished top face lands."""
    body_top = top_y - lip
    parts = _chamfered_box(
        (TILE_FOOTPRINT, body_thickness, TILE_FOOTPRINT),
        (0, body_top - body_thickness / 2, 0),
        side_color,
        chamfer,
    )
    plate = TILE_FOOTPRINT - 2 * inset
    parts.append(
        _box(
            (plate, plate_thickness, plate),
            (0, top_y - plate_thickness / 2, 0),
            top_color,
        )
    )
    return parts


def _tile_parts(top_color, side_color) -> list[trimesh.Trimesh]:
    """A terrain tile: the plate/body sandwich with its top face landing
    exactly on TILE_TOP_Y, over a full-footprint skirt."""
    parts = _plated_block(
        TILE_TOP_Y,
        TILE_BODY_THICKNESS,
        TILE_CHAMFER,
        TILE_PLATE_INSET,
        TILE_PLATE_LIP,
        TILE_PLATE_THICKNESS,
        top_color,
        side_color,
    )
    skirt_top = TILE_TOP_Y - TILE_PLATE_LIP - TILE_BODY_THICKNESS
    parts.append(
        _box(
            (TILE_FOOTPRINT, TILE_SKIRT_THICKNESS, TILE_FOOTPRINT),
            (0, skirt_top - TILE_SKIRT_THICKNESS / 2, 0),
            side_color,
        )
    )
    return parts


def _route_parts(height, top_color, side_color) -> list[trimesh.Trimesh]:
    """A route plate, origin at its own mid-height (Main._add_route_block
    places it at surface + height/2), built the same way as a terrain tile so
    a road and the ground it crosses read as the same kind of object.

    No skirt: the plate is only ~0.22 tall and already sits on a terrain tile,
    so there is nothing underneath for the camera to see into."""
    return _plated_block(
        height / 2,
        height - ROUTE_PLATE_LIP,
        ROUTE_CHAMFER,
        ROUTE_PLATE_INSET,
        ROUTE_PLATE_LIP,
        ROUTE_PLATE_THICKNESS,
        top_color,
        side_color,
    )


def _cylinder(radius, height, translation, color, sections=8) -> trimesh.Trimesh:
    """A Y-up cylinder centred on `translation`. trimesh builds cylinders
    Z-up, so this rotates it into the game's Y-up world once, here, rather
    than leaving every caller to remember."""
    mesh = trimesh.creation.cylinder(radius=radius, height=height, sections=sections)
    mesh.apply_transform(trimesh.transformations.rotation_matrix(math.pi / 2, (1, 0, 0)))
    mesh.apply_translation(translation)
    mesh.visual.vertex_colors = np.tile(color, (len(mesh.vertices), 1))
    return mesh


def _leaf(extents, translation, color, yaw, tilt) -> trimesh.Trimesh:
    """One of the small leaves that poke out of a canopy. Yaw spins it around
    the plant, tilt lifts its outer end -- together they are what stop four
    identical sprigs from reading as a mechanical cross."""
    mesh = trimesh.creation.box(extents=extents)
    mesh.apply_transform(trimesh.transformations.rotation_matrix(tilt, (0, 0, 1)))
    mesh.apply_transform(trimesh.transformations.rotation_matrix(yaw, (0, 1, 0)))
    mesh.apply_translation(translation)
    mesh.visual.vertex_colors = np.tile(color, (len(mesh.vertices), 1))
    return mesh


def _sprigs(count, radius, y, color, size=(0.30, 0.05, 0.13), tilt=0.45, phase=0.0):
    """`count` leaves arranged around a canopy at height `y`."""
    parts = []
    for i in range(count):
        yaw = phase + i * (2 * math.pi / count)
        parts.append(
            _leaf(
                size,
                (math.cos(yaw) * radius, y, -math.sin(yaw) * radius),
                color,
                yaw,
                tilt,
            )
        )
    return parts


def build_crate() -> trimesh.Trimesh:
    """A simple wooden crate: a main cube with darker corner posts and a
    horizontal mid-band, echoing the look of the original Block_Crate."""
    parts = [_box((1.0, 1.0, 1.0), (0, 0, 0), WOOD_LIGHT)]
    post = 0.08
    for dx in (-1, 1):
        for dz in (-1, 1):
            x = dx * (0.5 - post / 2)
            z = dz * (0.5 - post / 2)
            parts.append(_box((post, 1.02, post), (x, 0, z), WOOD_DARK))
    parts.append(_box((1.02, 0.14, 1.02), (0, 0, 0), WOOD_DARK))
    return trimesh.util.concatenate(parts)


def build_chest() -> trimesh.Trimesh:
    """A closed chest: a wide base, a slightly narrower lid, a metal band,
    and a small gold latch, echoing the look of the original Chest_Closed."""
    parts = [
        _box((0.9, 0.55, 0.6), (0, 0.275, 0), CHEST_BASE),
        _box((0.92, 0.28, 0.62), (0, 0.69, 0), CHEST_LID),
        _box((0.94, 0.08, 0.64), (0, 0.55, 0), METAL_BAND),
        _box((0.1, 0.16, 0.05), (0, 0.45, 0.31), LATCH_GOLD),
    ]
    return trimesh.util.concatenate(parts)


def build_grass_block() -> trimesh.Trimesh:
    """Open ground: one flat, plain sage-green chocolate square.

    Deliberately featureless. The chunky grass cap and the four corner tufts
    this used to carry are gone -- with a tree or a bush standing on roughly a
    third of these tiles (see TerrainRenderer's scatter), per-tile detail
    underneath them turned the ground into noise. A flat plate also means a
    route plate laid on top meets a genuinely flat surface, with the groove
    between tiles doing all the work of separating one cell from the next."""
    return trimesh.util.concatenate(_tile_parts(GRASS_TOP, GRASS_SIDE))


def build_river_block() -> trimesh.Trimesh:
    """The river column: the same flat plate in water blue, with two pale
    ripple strips inlaid just proud of the surface.

    The ripples sit only 0.015 above the top face on purpose -- a route
    crossing the river draws its own slab from TILE_TOP_Y upward (see
    Main.RIVER_CROSSING_HEIGHT), so anything taller here would poke through
    the crossing."""
    parts = _tile_parts(WATER_TOP, WATER_SIDE)
    parts.append(_box((1.1, 0.03, 0.18), (-0.28, TILE_TOP_Y, -0.42), WATER_RIPPLE))
    parts.append(_box((0.9, 0.03, 0.18), (0.34, TILE_TOP_Y, 0.44), WATER_RIPPLE))
    return trimesh.util.concatenate(parts)


def build_dirt_road_block() -> trimesh.Trimesh:
    """The first route tier: a plain sand-coloured plate.

    Flat and unmarked, so it reads exactly the same under any 90-degree
    rotation -- one design serves every route shape (straight or corner, any
    facing) and there is no separate corner mesh."""
    return trimesh.util.concatenate(_route_parts(0.22, DIRT_ROAD_TOP, DIRT_ROAD_SIDE))


def build_paved_road_block() -> trimesh.Trimesh:
    """The middle route tier: an orange decking plate, split into four panels
    by a darker seam running across both axes.

    The seam is laid ON the top face rather than cut into it -- the meshes
    here are concatenated, not booleaned, so there is nothing to subtract
    with. It is the only marking, and it is symmetric on both axes, so this
    stays rotation-agnostic like the other two tiers."""
    height = 0.22
    parts = _route_parts(height, PAVED_TOP, PAVED_SIDE)
    top = height / 2
    parts.append(_box((1.82, 0.03, 0.1), (0, top, 0), PAVED_SIDE))
    parts.append(_box((0.1, 0.03, 1.82), (0, top, 0), PAVED_SIDE))
    return trimesh.util.concatenate(parts)


def build_main_road_block() -> trimesh.Trimesh:
    """The top route tier: a dark plum plate with a pale painted cross.

    A cross (both axes, not a single directional centre line) reads the same
    under any 90-degree rotation -- same rotation-agnostic approach as the
    other two tiers."""
    height = 0.24
    parts = _route_parts(height, MAIN_TOP, MAIN_SIDE)
    top = height / 2
    parts.append(_box((0.2, 0.03, 1.78), (0, top, 0), MAIN_STRIPE))
    parts.append(_box((1.78, 0.03, 0.2), (0, top, 0), MAIN_STRIPE))
    return trimesh.util.concatenate(parts)


def build_tree_round() -> trimesh.Trimesh:
    """A broad round-topped tree: a short warm trunk under a chamfered cube
    canopy, with leaves poking out around its shoulders and a couple of pale
    blossoms on top. Origin at the base of the trunk."""
    trunk_height = 0.52
    canopy = 1.02
    canopy_center = trunk_height + canopy / 2 - 0.06
    parts = [_cylinder(0.11, trunk_height, (0, trunk_height / 2, 0), TRUNK_WARM)]
    parts += _chamfered_box((canopy, canopy, canopy), (0, canopy_center, 0), LEAF_MID, 0.24)
    parts += _sprigs(4, 0.56, canopy_center + 0.18, LEAF_LIGHT, phase=0.4)
    parts.append(_box((0.13, 0.06, 0.13), (0.18, canopy_center + canopy / 2 - 0.02, -0.12), FLOWER))
    parts.append(_box((0.11, 0.06, 0.11), (-0.2, canopy_center + canopy / 2 - 0.02, 0.16), FLOWER))
    return trimesh.util.concatenate(parts)


def build_tree_tall() -> trimesh.Trimesh:
    """A slimmer, taller tree in the darker green, so a scattered stand of
    trees is not all one silhouette. Origin at the base of the trunk."""
    trunk_height = 0.72
    canopy_w = 0.82
    canopy_h = 1.06
    canopy_center = trunk_height + canopy_h / 2 - 0.06
    parts = [_cylinder(0.10, trunk_height, (0, trunk_height / 2, 0), TRUNK_DARK)]
    parts += _chamfered_box((canopy_w, canopy_h, canopy_w), (0, canopy_center, 0), LEAF_DARK, 0.2)
    parts += _sprigs(3, 0.46, canopy_center + 0.3, LEAF_MID, tilt=0.6)
    return trimesh.util.concatenate(parts)


def build_bush_small() -> trimesh.Trimesh:
    """A low, wide bush -- the quiet filler between the trees, short enough
    that it never competes with a node marker for attention. Origin at its
    base."""
    height = 0.52
    width = 0.86
    parts = _chamfered_box((width, height, width), (0, height / 2, 0), LEAF_MID, 0.16)
    parts += _sprigs(3, 0.44, height - 0.1, LEAF_LIGHT, size=(0.26, 0.05, 0.11), phase=0.9)
    return trimesh.util.concatenate(parts)


def build_bush_planter() -> trimesh.Trimesh:
    """A bush in a clay planter, matching the potted plants dotted around the
    reference art. Origin at the bottom of the planter."""
    pot_height = 0.30
    bush_height = 0.56
    bush_center = pot_height + bush_height / 2 - 0.04
    parts = [
        _box((0.78, pot_height, 0.78), (0, pot_height / 2, 0), PLANTER_CLAY),
        _box((0.86, 0.08, 0.86), (0, pot_height - 0.02, 0), PLANTER_RIM),
    ]
    parts += _chamfered_box((0.68, bush_height, 0.68), (0, bush_center, 0), LEAF_LIGHT, 0.14)
    parts += _sprigs(4, 0.36, bush_center + 0.16, LEAF_MID, size=(0.24, 0.05, 0.1), phase=0.2)
    return trimesh.util.concatenate(parts)


def export(mesh: trimesh.Trimesh, path: str) -> None:
    # An explicit matte, non-metallic material -- without one, Godot's glTF
    # import falls back to a shinier default that visibly reflects the
    # editor's sky on these flat-shaded faces.
    mesh.visual.material = trimesh.visual.material.PBRMaterial(
        baseColorFactor=[255, 255, 255, 255], metallicFactor=0.0, roughnessFactor=1.0
    )
    mesh.export(path, file_type="glb")
    print(f"wrote {path} ({len(mesh.vertices)} verts, {len(mesh.faces)} faces)")


if __name__ == "__main__":
    export(build_crate(), "assets/Blocks/glTF/Block_Crate.glb")
    export(build_chest(), "assets/Environment/glTF/Chest_Closed.glb")
    export(build_grass_block(), "assets/Blocks/glTF/Block_Grass.glb")
    export(build_river_block(), "assets/Blocks/glTF/Block_Ice.glb")
    export(build_dirt_road_block(), "assets/Blocks/glTF/Block_Road_Dirt.glb")
    export(build_paved_road_block(), "assets/Blocks/glTF/Block_Road_Paved.glb")
    export(build_main_road_block(), "assets/Blocks/glTF/Block_Road_Main.glb")
    export(build_tree_round(), "assets/Environment/glTF/Tree_Round.glb")
    export(build_tree_tall(), "assets/Environment/glTF/Tree_Tall.glb")
    export(build_bush_small(), "assets/Environment/glTF/Bush_Small.glb")
    export(build_bush_planter(), "assets/Environment/glTF/Bush_Planter.glb")
