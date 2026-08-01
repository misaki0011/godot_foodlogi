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
trunk, or of the bush itself -- a bush sits straight on the grass with
nothing underneath it), so they can be dropped onto that same surface.

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
# Main.ROUTE_LEVEL_HEIGHTS). The three tiers read as plain sand -> orange
# decking -> the same deck in dark umber.
DIRT_ROAD_TOP = (233, 219, 178, 255)
DIRT_ROAD_SIDE = (184, 166, 122, 255)
PAVED_TOP = (232, 166, 84, 255)
PAVED_SIDE = (180, 116, 48, 255)
# Main is Paved's own deck a long way down the value ramp, not a new hue: the
# tier that matters most has to be the one that reads first at map distance,
# and value separates far better than hue does at this camera height.
MAIN_TOP = (146, 92, 40, 255)
MAIN_SIDE = (98, 58, 24, 255)

# Vegetation.
TRUNK_WARM = (150, 96, 74, 255)
TRUNK_DARK = (118, 78, 58, 255)
LEAF_MID = (124, 168, 84, 255)
LEAF_LIGHT = (152, 194, 106, 255)
LEAF_DARK = (106, 152, 80, 255)
FLOWER = (246, 240, 226, 255)

# Bushes. Lighter than a tree's canopy so a bush is not read as a tree that
# failed to grow, but clearly more saturated than GRASS_TOP -- a bush pitched
# between the two ends up almost exactly the tile's own colour and disappears
# into the ground it stands on. The sprouting leaves are a yellower green
# again, which is what carries the shape at map distance.
BUSH_BODY = (142, 184, 96, 255)
BUSH_LEAF = (206, 222, 108, 255)
BUSH_LEAF_ALT = (168, 202, 96, 255)
BUSH_CHAMFER_RATIO = 0.16  # of the block's smallest side; see _bush for the ceiling on this
BUSH_LEAF_LENGTH = 0.38
BUSH_LEAF_WIDTH = 0.18
BUSH_LEAF_SPREAD = 0.75  # rosette radius as a share of a leaf's own reach; keeps leaves from merging
BUSH_LEAF_TILT = 1.02  # radians from horizontal -- nearly upright, so leaves sprout rather than fan

# ------------------------------------------------------------- settlements
#
# A settlement is a little PLACE standing on a rounded plaza that covers its
# whole grid footprint (1x1 Village, 2x1 Town, 2x2 City -- see NodeData.size).
# The plaza is not decoration: those cells are unbuildable, and covering them
# exactly is what tells the player so, which is the job the old one-marker-
# per-cell pole used to do.
#
# Roofs are MarkerColors.SETTLEMENT_COLOR, the same red every settlement has
# always been drawn in and the colour the established-route overlay marks a
# delivery destination with (Main.ESTABLISHED_END_COLOR). Keeping it on the
# roofs is what lets these carry their own palette without the map losing the
# one colour that means "somewhere food goes".
#
# The plaza is a neutral GREY stone, not a sand: a warm plaza is very close to
# DIRT_ROAD_TOP, and a settlement whose ground reads as road surface loses the
# distinction between the place and the route arriving at it.
SETTLEMENT_ROOF = (196, 87, 58, 255)  # == MarkerColors.SETTLEMENT_COLOR
SETTLEMENT_ROOF_DARK = (156, 66, 44, 255)
HOUSE_WALL = (242, 233, 214, 255)
HOUSE_WALL_ALT = (224, 210, 186, 255)
TOWER_WALL = (212, 217, 224, 255)
TOWER_WALL_ALT = (192, 200, 210, 255)
TOWER_CAP = (152, 148, 158, 255)
DOOR = (122, 96, 74, 255)
PLAZA_TOP = (202, 198, 192, 255)
PLAZA_SIDE = (148, 145, 140, 255)

## Plaza geometry. INSET is per side, off the footprint's true edge, so the
## tile groove still runs round the outside of a settlement and the place
## reads as standing ON the grid rather than as replacing part of it.
PLAZA_INSET = 0.15
PLAZA_BODY_THICKNESS = 0.16
PLAZA_CHAMFER = 0.07
PLAZA_PLATE_INSET = 0.11
PLAZA_LIP = 0.02
PLAZA_PLATE_THICKNESS = 0.05
PLAZA_TOP_Y = PLAZA_BODY_THICKNESS + PLAZA_LIP  # what the buildings stand on

## Ceiling on how tall anything in a settlement may be. A settlement's order
## chips are bottom-anchored 3.1 above the tile surface and grow upward
## (Main._render_settlement_bubbles), so a building taller than this starts
## eating the column that says what the place wants.
SETTLEMENT_MAX_HEIGHT = 1.7


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


def _sprigs(count, radius, y, color, size=(0.30, 0.05, 0.13), tilt=0.45, phase=0.0, center=(0.0, 0.0)):
    """`count` leaves arranged around a canopy at height `y`, optionally about
    a point other than the prop's own axis (`center`, as x/z)."""
    parts = []
    for i in range(count):
        yaw = phase + i * (2 * math.pi / count)
        parts.append(
            _leaf(
                size,
                (center[0] + math.cos(yaw) * radius, y, center[1] - math.sin(yaw) * radius),
                color,
                yaw,
                tilt,
            )
        )
    return parts


def _bush(extents, leaf_clusters) -> trimesh.Trimesh:
    """A bush: one heavily rounded block sitting straight on the ground, with
    leaves sprouting out of the top of it.

    No pot, no plinth, nothing underneath -- a bush is a shape on the grass.

    The chamfer is a fixed FRACTION of the block's smallest side rather than a
    flat number, so a squat hedge and a tall shrub round off by the same
    amount visually. It cannot be pushed much past this: `_chamfered_box` is
    three overlapping boxes, and once the chamfer approaches a third of a side
    the full-width band in the middle vanishes and the union degenerates from
    a rounded block into a plus sign.

    Leaves stand nearly upright (`BUSH_LEAF_TILT`) instead of fanning out
    sideways the way a tree's do. Each is placed so its BASE sits just inside
    the top face and its tip clears it -- a leaf centred on the surface reads
    as lying on the bush rather than growing from it -- and the rosette is
    pushed out past that (`BUSH_LEAF_SPREAD`) so the leaves stay separate
    shapes instead of merging into one blob at map distance.
    """
    w, h, d = extents
    chamfer = min(w, h, d) * BUSH_CHAMFER_RATIO
    parts = _chamfered_box(extents, (0, h / 2, 0), BUSH_BODY, chamfer)
    for cluster in leaf_clusters:
        parts += _sprigs(
            cluster["count"],
            BUSH_LEAF_LENGTH * math.cos(BUSH_LEAF_TILT) * BUSH_LEAF_SPREAD,
            h + BUSH_LEAF_LENGTH * math.sin(BUSH_LEAF_TILT) / 2 - 0.03,
            cluster["color"],
            size=(BUSH_LEAF_LENGTH, 0.05, BUSH_LEAF_WIDTH),
            tilt=BUSH_LEAF_TILT,
            phase=cluster["phase"],
            center=cluster["center"],
        )
    return trimesh.util.concatenate(parts)


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


def _decked_road_block(height, top_color, side_color) -> trimesh.Trimesh:
    """A decking plate split into four panels by a darker seam running across
    both axes -- the shape the top two route tiers share.

    The seam is laid ON the top face rather than cut into it: the meshes here
    are concatenated, not booleaned, so there is nothing to subtract with. It
    is the only marking, and it is symmetric on both axes, so a decked tile
    stays rotation-agnostic like the plain Dirt one."""
    parts = _route_parts(height, top_color, side_color)
    top = height / 2
    parts.append(_box((1.82, 0.03, 0.1), (0, top, 0), side_color))
    parts.append(_box((0.1, 0.03, 1.82), (0, top, 0), side_color))
    return trimesh.util.concatenate(parts)


def build_paved_road_block() -> trimesh.Trimesh:
    """The middle route tier: an orange decking plate."""
    return _decked_road_block(0.22, PAVED_TOP, PAVED_SIDE)


def build_main_road_block() -> trimesh.Trimesh:
    """The top route tier: the Paved deck again, in a darker shade.

    Deliberately the same shape rather than a design of its own. The tiers are
    told apart by VALUE -- pale sand, mid orange, dark umber -- and reusing the
    deck is what makes the ramp read as one road getting more built-up rather
    than as three unrelated surfaces. It also keeps the top tier
    rotation-agnostic for free, which the old painted cross had to arrange for
    itself."""
    return _decked_road_block(0.24, MAIN_TOP, MAIN_SIDE)


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


def build_bush_square() -> trimesh.Trimesh:
    """A rounded cube of a bush, sitting straight on the grass, with a rosette
    of leaves sprouting out of the top. Origin at its base."""
    return _bush(
        (0.80, 0.76, 0.80),
        [
            {"count": 4, "phase": 0.35, "color": BUSH_LEAF, "center": (0.0, 0.0)},
            {"count": 2, "phase": 1.4, "color": BUSH_LEAF_ALT, "center": (0.09, -0.08)},
        ],
    )


def build_bush_rect() -> trimesh.Trimesh:
    """The same bush stretched into a rounded rectangular block -- a low hedge
    rather than a shrub. Origin at its base.

    Its leaves gather over ONE end rather than over the middle: a long block
    with a rosette centred on it reads as a shrub that happens to be wide,
    while an off-centre cluster reads as a hedge with one bushy end, which is
    what the reference art does and what tells the two props apart at map
    distance once they are both scattered over the same field."""
    return _bush(
        (1.18, 0.62, 0.74),
        [
            {"count": 4, "phase": 0.2, "color": BUSH_LEAF, "center": (-0.26, 0.0)},
            {"count": 2, "phase": 2.1, "color": BUSH_LEAF_ALT, "center": (0.12, 0.06)},
        ],
    )


def _pyramid(width, depth, height, translation, color) -> trimesh.Trimesh:
    """A pitched hip roof: a square pyramid, spun 45 degrees so its base edges
    run along the axes rather than its corners, then stretched to the house it
    caps. Base at the translation's y, apex `height` above it."""
    mesh = trimesh.creation.cone(radius=1.0 / math.sqrt(2), height=height, sections=4)
    mesh.apply_transform(trimesh.transformations.rotation_matrix(math.pi / 4, (0, 0, 1)))
    mesh.apply_transform(trimesh.transformations.rotation_matrix(-math.pi / 2, (1, 0, 0)))
    mesh.apply_scale([width, 1.0, depth])
    mesh.apply_translation(translation)
    mesh.visual.vertex_colors = np.tile(color, (len(mesh.vertices), 1))
    return mesh


def _plaza(width, depth) -> list[trimesh.Trimesh]:
    """The rounded slab a settlement stands on, spanning its whole footprint
    less PLAZA_INSET. Same plate-over-chamfered-body build as a terrain tile,
    so it reads as part of the same board."""
    body_top = PLAZA_TOP_Y - PLAZA_LIP
    parts = _chamfered_box(
        (width, PLAZA_BODY_THICKNESS, depth),
        (0, body_top - PLAZA_BODY_THICKNESS / 2, 0),
        PLAZA_SIDE,
        PLAZA_CHAMFER,
    )
    parts.append(
        _box(
            (width - 2 * PLAZA_PLATE_INSET, PLAZA_PLATE_THICKNESS, depth - 2 * PLAZA_PLATE_INSET),
            (0, PLAZA_TOP_Y - PLAZA_PLATE_THICKNESS / 2, 0),
            PLAZA_TOP,
        )
    )
    return parts


def _house(x, z, width, depth, wall_height, roof_height, wall_color, roof_color, door_side=-1):
    """A pitched-roof house standing on the plaza: rounded walls, a hip roof
    overhanging them a little, and a door so the building has a front.

    The overhang is what stops the roof from reading as a lid: at this camera
    angle the roof is most of what is visible, and an eave line separating it
    from the wall is the only thing that says the two are different parts."""
    base = PLAZA_TOP_Y
    parts = _chamfered_box(
        (width, wall_height, depth), (x, base + wall_height / 2, z), wall_color, 0.05
    )
    parts.append(
        _pyramid(
            width + 0.16,
            depth + 0.16,
            roof_height,
            (x, base + wall_height, z),
            roof_color,
        )
    )
    parts.append(
        _box(
            (width * 0.28, wall_height * 0.55, 0.05),
            (x, base + wall_height * 0.275, z + door_side * (depth / 2)),
            DOOR,
        )
    )
    return parts


def _tower(x, z, width, depth, height, wall_color):
    """A flat-roofed block -- the taller, plainer buildings that separate a
    City from a cluster of houses. Capped in slate rather than roof red, so a
    City still reads as red-roofed but is not five identical red pyramids."""
    base = PLAZA_TOP_Y
    parts = _chamfered_box(
        (width, height, depth), (x, base + height / 2, z), wall_color, 0.05
    )
    parts.append(
        _box((width + 0.07, 0.05, depth + 0.07), (x, base + height + 0.01, z), TOWER_CAP)
    )
    return parts


def _settlement_tree(x, z, scale=1.0):
    """A small tree for a Village's garden. Deliberately the same trunk and
    canopy language as the scattered Tree_Round, just smaller -- a settlement
    growing its own kind of tree would read as a different plant."""
    base = PLAZA_TOP_Y
    trunk_height = 0.30 * scale
    canopy = 0.56 * scale
    canopy_center = base + trunk_height + canopy / 2 - 0.04
    parts = [
        _cylinder(0.07 * scale, trunk_height, (x, base + trunk_height / 2, z), TRUNK_WARM)
    ]
    parts += _chamfered_box((canopy, canopy, canopy), (x, canopy_center, z), LEAF_MID, canopy * 0.16)
    parts += _sprigs(
        3,
        canopy * 0.5,
        canopy_center + canopy * 0.28,
        LEAF_LIGHT,
        size=(0.22 * scale, 0.045, 0.10 * scale),
        tilt=0.7,
        phase=0.6,
        center=(x, z),
    )
    return parts


def build_settlement_village() -> trimesh.Trimesh:
    """Village: one house and a tree on a 1x1 plaza. Origin at the centre of
    the footprint, on the terrain surface."""
    width = 2.0 - 2 * PLAZA_INSET
    parts = _plaza(width, width)
    parts += _house(-0.30, 0.08, 0.86, 0.72, 0.46, 0.40, HOUSE_WALL, SETTLEMENT_ROOF)
    parts += _settlement_tree(0.52, -0.34)
    return trimesh.util.concatenate(parts)


def build_settlement_town() -> trimesh.Trimesh:
    """Town: three houses on a 2x1 plaza. Origin at the centre of the
    footprint, on the terrain surface.

    The three are staggered in depth and differ in size and roof shade rather
    than being a row of identical boxes -- at this camera angle a rank of three
    matching silhouettes reads as one long building."""
    parts = _plaza(4.0 - 2 * PLAZA_INSET, 2.0 - 2 * PLAZA_INSET)
    parts += _house(-1.16, 0.16, 0.88, 0.74, 0.46, 0.40, HOUSE_WALL, SETTLEMENT_ROOF)
    parts += _house(0.04, -0.24, 0.80, 0.68, 0.54, 0.44, HOUSE_WALL_ALT, SETTLEMENT_ROOF_DARK, door_side=1)
    parts += _house(1.16, 0.20, 0.92, 0.76, 0.42, 0.38, HOUSE_WALL, SETTLEMENT_ROOF)
    return trimesh.util.concatenate(parts)


def build_settlement_city() -> trimesh.Trimesh:
    """City: two houses at the front and three taller blocks behind them, on a
    2x2 plaza. Origin at the centre of the footprint, on the terrain surface.

    Houses forward and blocks behind, rather than mixed: the camera looks down
    the +Z axis, so anything at the back is partly hidden by whatever is in
    front of it, and putting the tall things there is what gives the cluster a
    skyline instead of a jumble. Nothing exceeds SETTLEMENT_MAX_HEIGHT."""
    width = 4.0 - 2 * PLAZA_INSET
    parts = _plaza(width, width)
    parts += _tower(-1.02, -1.00, 0.78, 0.78, 1.16, TOWER_WALL)
    parts += _tower(0.06, -1.14, 0.70, 0.70, 1.42, TOWER_WALL_ALT)
    parts += _tower(1.10, -0.86, 0.74, 0.74, 0.94, TOWER_WALL)
    parts += _house(-0.86, 0.86, 0.92, 0.78, 0.50, 0.42, HOUSE_WALL, SETTLEMENT_ROOF)
    parts += _house(0.82, 1.02, 0.86, 0.74, 0.46, 0.40, HOUSE_WALL_ALT, SETTLEMENT_ROOF_DARK)
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
    export(build_bush_square(), "assets/Environment/glTF/Bush_Square.glb")
    export(build_bush_rect(), "assets/Environment/glTF/Bush_Rect.glb")
    export(build_settlement_village(), "assets/Environment/glTF/Settlement_Village.glb")
    export(build_settlement_town(), "assets/Environment/glTF/Settlement_Town.glb")
    export(build_settlement_city(), "assets/Environment/glTF/Settlement_City.glb")
