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
# Near-white, and a long way off PLAZA_TOP: pitched anywhere near the plaza's
# own grey the blocks merge into the ground they stand on and the City loses
# its skyline entirely.
TOWER_WALL = (245, 247, 250, 255)
TOWER_WALL_ALT = (230, 235, 242, 255)
TOWER_CAP = (152, 148, 158, 255)
WINDOW = (104, 136, 168, 255)
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

## Window grid on a tower's front wall. PITCH is one storey; MARGIN is how far
## the top row sits below the roof. Rows come out of the building's height, so
## storeys stay the same size whatever the tower.
WINDOW_SIZE = 0.16
WINDOW_PITCH = 0.34
WINDOW_MARGIN = 0.26
## A house gets one window beside its door, a little larger than a tower pane:
## there is exactly one of them, so it has to carry the lit-at-night read on
## its own where a tower has a whole grid doing it.
HOUSE_WINDOW_SIZE = 0.19


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


def _window(cx, cy, z_front, width=WINDOW_SIZE, height=WINDOW_SIZE * 0.8):
    """One pane, standing just proud of a front wall.

    Windows are kept in their OWN geometry all the way through (see
    _settlement_scene): they are the one part of a settlement that has to be
    addressable at runtime, because they light up at night."""
    return _box((width, height, 0.04), (cx, cy, z_front), WINDOW)


def _house(x, z, width, depth, wall_height, roof_height, wall_color, roof_color):
    """A pitched-roof house standing on the plaza: rounded walls, a hip roof
    overhanging them a little, and a door with a window beside it on the FRONT.
    Returns (body parts, window parts).

    Front means +Z, and that is not arbitrary -- the game camera is pitched
    down 60 degrees looking along -Z, so +Z is the only wall it can ever see.
    A door on any other face is a door nobody will find, and the same goes for
    a window that is supposed to be seen lit.

    The door sits off-centre with the window beside it rather than the two
    being symmetric about the middle. Symmetry would read as two doors or two
    windows at map distance, where neither shape resolves; an offset pair
    reads as a frontage.

    The roof overhang is what stops the roof from reading as a lid: at this
    camera angle the roof is most of what is visible, and an eave line
    separating it from the wall is the only thing that says the two are
    different parts."""
    base = PLAZA_TOP_Y
    front = z + depth / 2
    body = _chamfered_box(
        (width, wall_height, depth), (x, base + wall_height / 2, z), wall_color, 0.05
    )
    body.append(
        _pyramid(
            width + 0.16,
            depth + 0.16,
            roof_height,
            (x, base + wall_height, z),
            roof_color,
        )
    )
    body.append(
        _box(
            (width * 0.28, wall_height * 0.55, 0.05),
            (x - width * 0.19, base + wall_height * 0.275, front),
            DOOR,
        )
    )
    windows = [
        _window(
            x + width * 0.24,
            base + wall_height * 0.56,
            front,
            width=HOUSE_WINDOW_SIZE,
            height=HOUSE_WINDOW_SIZE * 0.85,
        )
    ]
    return body, windows


def _tower_windows(x, z_front, base_y, width, height):
    """A grid of windows on a tower's front (+Z) wall -- the only wall the
    camera sees, same as a house's door.

    Rows are derived from the building's height rather than passed in, so a
    tall block gets more of them and the storeys stay the same size on every
    tower. That is what makes three blocks of different heights read as three
    buildings rather than as one block scaled three ways."""
    rows = max(1, int((height - WINDOW_MARGIN) / WINDOW_PITCH))
    panes = []
    for row in range(rows):
        y = base_y + height - WINDOW_MARGIN - row * WINDOW_PITCH
        for col in (-1, 1):
            panes.append(_window(x + col * width * 0.22, y, z_front))
    return panes


def _tower(x, z, width, depth, height, wall_color):
    """A flat-roofed block with windows -- the taller, plainer buildings that
    separate a City from a cluster of houses. Returns (body parts, window
    parts).

    Capped in slate rather than roof red, so a City still reads as red-roofed
    without being five identical red pyramids. The walls are near-white on
    purpose: pitched anywhere near the plaza's own grey they merge into the
    ground they stand on and the City loses its skyline."""
    base = PLAZA_TOP_Y
    body = _chamfered_box(
        (width, height, depth), (x, base + height / 2, z), wall_color, 0.05
    )
    body.append(
        _box((width + 0.07, 0.05, depth + 0.07), (x, base + height + 0.01, z), TOWER_CAP)
    )
    return body, _tower_windows(x, z + depth / 2, base, width, height)


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


class _Settlement:
    """Accumulates a settlement's two geometries as its buildings are added.

    They stay separate all the way to the file because the windows have to be
    addressable at runtime -- NodeMarker turns their emission up as night falls
    (see DayCycle.window_glow), and a mesh merged into the walls has no way to
    light up on its own."""

    def __init__(self, width, depth):
        self.body = _plaza(width, depth)
        self.windows = []

    def add(self, built):
        body, windows = built
        self.body += body
        self.windows += windows

    def add_body(self, parts):
        self.body += parts

    def scene(self):
        return _settlement_scene(self.body, self.windows)


def build_settlement_village() -> trimesh.Scene:
    """Village: one house and a tree on a 1x1 plaza. Origin at the centre of
    the footprint, on the terrain surface."""
    width = 2.0 - 2 * PLAZA_INSET
    place = _Settlement(width, width)
    place.add(_house(-0.30, 0.08, 0.86, 0.72, 0.46, 0.40, HOUSE_WALL, SETTLEMENT_ROOF))
    place.add_body(_settlement_tree(0.52, -0.34))
    return place.scene()


def build_settlement_town() -> trimesh.Scene:
    """Town: three houses on a 2x1 plaza. Origin at the centre of the
    footprint, on the terrain surface.

    The three are staggered in depth and differ in size and roof shade rather
    than being a row of identical boxes -- at this camera angle a rank of three
    matching silhouettes reads as one long building."""
    place = _Settlement(4.0 - 2 * PLAZA_INSET, 2.0 - 2 * PLAZA_INSET)
    place.add(_house(-1.16, 0.16, 0.88, 0.74, 0.46, 0.40, HOUSE_WALL, SETTLEMENT_ROOF))
    place.add(_house(0.04, -0.24, 0.80, 0.68, 0.54, 0.44, HOUSE_WALL_ALT, SETTLEMENT_ROOF_DARK))
    place.add(_house(1.16, 0.20, 0.92, 0.76, 0.42, 0.38, HOUSE_WALL, SETTLEMENT_ROOF))
    return place.scene()


def build_settlement_city() -> trimesh.Scene:
    """City: three houses across the front and three taller blocks behind them,
    on a 2x2 plaza. Origin at the centre of the footprint, on the terrain
    surface.

    Houses forward and blocks behind, rather than mixed: the camera looks down
    the +Z axis, so anything at the back is partly hidden by whatever is in
    front of it, and putting the tall things there is what gives the cluster a
    skyline instead of a jumble. The front row is the Town's own row of three
    houses, which is what makes a City read as a Town that grew rather than as
    an unrelated place. Nothing exceeds SETTLEMENT_MAX_HEIGHT."""
    width = 4.0 - 2 * PLAZA_INSET
    place = _Settlement(width, width)
    place.add(_tower(-1.04, -1.02, 0.78, 0.78, 1.16, TOWER_WALL))
    place.add(_tower(0.06, -1.16, 0.70, 0.70, 1.42, TOWER_WALL_ALT))
    place.add(_tower(1.12, -0.88, 0.74, 0.74, 0.94, TOWER_WALL))
    place.add(_house(-1.16, 0.82, 0.90, 0.76, 0.50, 0.42, HOUSE_WALL, SETTLEMENT_ROOF))
    place.add(_house(0.02, 1.04, 0.82, 0.72, 0.46, 0.40, HOUSE_WALL_ALT, SETTLEMENT_ROOF_DARK))
    place.add(_house(1.18, 0.80, 0.88, 0.74, 0.52, 0.44, HOUSE_WALL, SETTLEMENT_ROOF))
    return place.scene()


## The glTF node names a settlement's two geometries import under. Godot names
## each MeshInstance3D after its glTF node, so these are the names
## NodeMarker.WINDOWS_NODE looks the panes up by at runtime -- changing one
## means changing both.
SETTLEMENT_BODY_NODE = "body"
SETTLEMENT_WINDOWS_NODE = "windows"


def _matte(mesh: trimesh.Trimesh) -> trimesh.Trimesh:
    # An explicit matte, non-metallic material -- without one, Godot's glTF
    # import falls back to a shinier default that visibly reflects the
    # editor's sky on these flat-shaded faces.
    mesh.visual.material = trimesh.visual.material.PBRMaterial(
        baseColorFactor=[255, 255, 255, 255], metallicFactor=0.0, roughnessFactor=1.0
    )
    return mesh


def _named_scene(parts_by_name) -> trimesh.Scene:
    """A model as several NAMED geometries rather than one merged mesh.

    Most things here export as a single mesh, because nothing needs a part of
    them picked out later. Two kinds do, and both need Godot to be able to FIND
    the part: a settlement's windows light up at night, and a storage or hub's
    roof takes its type colour. A glTF scene with named geometries imports as
    one MeshInstance3D per name, which is exactly that handle."""
    return trimesh.Scene(
        {name: _matte(trimesh.util.concatenate(parts)) for name, parts in parts_by_name.items()}
    )


def _settlement_scene(body_parts, window_parts) -> trimesh.Scene:
    return _named_scene(
        {SETTLEMENT_BODY_NODE: body_parts, SETTLEMENT_WINDOWS_NODE: window_parts}
    )


# ------------------------------------------------------------------ sources
#
# A source is a 2x1 yard -- the same rounded plaza a settlement stands on --
# with one PRODUCE MODEL on it per unit of daily output: one to begin with,
# and one more for every upgrade (see GameBalance.SOURCE_UPGRADE_MAX).
#
# The produce models are the food glyphs from the chips, in three dimensions.
# That is the whole point of them: FoodGlyphs' rule is that shape carries a
# food's identity and the SAME silhouette appears everywhere the food does, so
# the mark on a settlement's chip is the mark on the source that fills it.
# Colours follow the glyphs too, food colour and all -- which is why the carrot
# is green rather than orange, exactly as it is on every chip.
#
# Each is authored origin-at-base and fits inside one slot of the yard's 3x2
# grid, so SourceMarker can drop them onto fixed positions with no scaling.
GRAIN_COLOR = (217, 195, 106, 255)  # == GameBalance.food_types() colours
GRAIN_STALK = (186, 166, 88, 255)
BREAD_COLOR = (200, 154, 91, 255)
BREAD_SLASH = (226, 192, 142, 255)
VEG_COLOR = (111, 168, 90, 255)
VEG_TUFT = (78, 132, 62, 255)
MILK_COLOR = (237, 239, 230, 255)
MILK_CAP = (108, 136, 168, 255)
SEAFOOD_COLOR = (91, 143, 168, 255)
SEAFOOD_FIN = (72, 118, 142, 255)
SEAFOOD_EYE = (44, 58, 72, 255)

## Produce is authored at a comfortable hand-size and then blown up to fill its
## slot on the yard. These are STYLISED GLYPHS made physical, not props at
## life scale -- a realistically-sized loaf on a 2x1 yard is a dot from the
## game camera, which is the same failure the chip glyphs hit at strip size.
## One factor rather than 30 retuned numbers, so the shapes stay readable in
## the source and the slot budget is a single thing to check.
FOOD_MODEL_SCALE = 1.7
## The slot pitch on SourceMarker's 3x2 grid, which nothing may overflow.
FOOD_SLOT_WIDTH = 1.10
FOOD_SLOT_DEPTH = 0.80


def _cylinder_x(radius, length, translation, color, sections=10) -> trimesh.Trimesh:
    """A cylinder lying along X -- the loaf's dome. trimesh builds them Z-up,
    so this is the same one-place rotation as _cylinder, a quarter turn the
    other way."""
    mesh = trimesh.creation.cylinder(radius=radius, height=length, sections=sections)
    mesh.apply_transform(trimesh.transformations.rotation_matrix(math.pi / 2, (0, 1, 0)))
    mesh.apply_translation(translation)
    mesh.visual.vertex_colors = np.tile(color, (len(mesh.vertices), 1))
    return mesh


def build_food_grain() -> trimesh.Trimesh:
    """An ear of wheat: a thin stalk under a lens -- pointed at both ends,
    widest in the middle -- exactly the envelope FoodGlyphs._GRAIN draws, and
    for its reason: anything that tapers to a trunk reads as a conifer, so the
    ear must not widen downward into its stem."""
    parts = [_cylinder(0.03, 0.24, (0, 0.12, 0), GRAIN_STALK, sections=6)]
    # Widths up then down: the lens. Slab heights are equal so the taper is
    # carried entirely by the silhouette rather than by spacing.
    for i, width in enumerate([0.11, 0.19, 0.21, 0.16, 0.09]):
        y = 0.24 + 0.075 * i + 0.0375
        parts += _chamfered_box((width, 0.075, width * 0.75), (0, y, 0), GRAIN_COLOR, width * 0.16)
    return _produce(trimesh.util.concatenate(parts))


def build_food_bread() -> trimesh.Trimesh:
    """A loaf: flat base, domed top (FoodGlyphs._loaf). The dome is a cylinder
    lying along X with its lower half buried in the base, which is the cheapest
    honest way to get a smooth crown out of primitives."""
    parts = [
        _chamfered_box((0.46, 0.13, 0.30), (0, 0.065, 0), BREAD_COLOR, 0.045),
        _cylinder_x(0.15, 0.42, (0, 0.15, 0), BREAD_COLOR),
        _box((0.30, 0.03, 0.05), (0, 0.29, 0), BREAD_SLASH),
    ]
    return _produce(trimesh.util.concatenate(parts))


def build_food_vegetables() -> trimesh.Trimesh:
    """A carrot: a root tapering DOWNWARD to a point under a chunky tuft.

    Green, not orange -- the chips fill every glyph with its food's own colour
    and vegetables are green there, so an orange carrot here would break the
    one rule that makes the glyphs learnable. The tuft is one chunky mass
    rather than three thin fronds, the same fix FoodGlyphs._VEG_TUFT needed."""
    root = trimesh.creation.cone(radius=0.15, height=0.40, sections=8)
    # Cone builds apex at +Z; a quarter turn puts the apex DOWN, then it is
    # lifted so the point just touches the ground.
    root.apply_transform(trimesh.transformations.rotation_matrix(math.pi / 2, (1, 0, 0)))
    root.apply_translation((0, 0.40, 0))
    root.visual.vertex_colors = np.tile(VEG_COLOR, (len(root.vertices), 1))
    parts = [root]
    parts += _chamfered_box((0.20, 0.16, 0.18), (0, 0.47, 0), VEG_TUFT, 0.05)
    parts += _sprigs(3, 0.10, 0.58, VEG_TUFT, size=(0.17, 0.05, 0.09), tilt=0.9, phase=0.5)
    return _produce(trimesh.util.concatenate(parts))


def build_food_milk() -> trimesh.Trimesh:
    """A bottle: square shoulders, a necked top, a cap (FoodGlyphs._MILK).

    The cap is the one part that is NOT the food's colour: milk is very nearly
    white and a white cap on a white bottle loses the neck entirely, which is
    the silhouette's whole distinguishing feature."""
    parts = _chamfered_box((0.26, 0.30, 0.26), (0, 0.15, 0), MILK_COLOR, 0.05)
    parts += _chamfered_box((0.13, 0.14, 0.13), (0, 0.36, 0), MILK_COLOR, 0.03)
    parts.append(_box((0.16, 0.05, 0.16), (0, 0.45, 0), MILK_CAP))
    return _produce(trimesh.util.concatenate(parts))


def build_food_seafood() -> trimesh.Trimesh:
    """A fish, lying along X: a tapered body with a forked tail and an eye
    (FoodGlyphs._SEAFOOD). Lying rather than standing -- a fish balanced on its
    tail reads as a trophy, and the glyph it has to match is horizontal."""
    parts = _chamfered_box((0.40, 0.20, 0.15), (0.05, 0.12, 0), SEAFOOD_COLOR, 0.05)
    parts.append(_box((0.06, 0.11, 0.04), (0.22, 0.14, 0.06), SEAFOOD_EYE))
    # The tail is two fins meeting at the body rather than one slab, which is
    # what makes it fork instead of reading as a rudder.
    for side in (1, -1):
        parts.append(
            _leaf((0.18, 0.04, 0.10), (-0.22, 0.12 + side * 0.05, 0), SEAFOOD_FIN, 0.0, side * 0.55)
        )
    parts.append(_box((0.10, 0.09, 0.03), (0.02, 0.24, 0), SEAFOOD_FIN))
    return _produce(trimesh.util.concatenate(parts))


def _produce(mesh: trimesh.Trimesh) -> trimesh.Trimesh:
    """Blows a produce model up to yard scale and checks it still fits its
    slot. The assertion is the point: the models are authored by eye and the
    slots are fixed, so the failure mode is a new food quietly overlapping its
    neighbour on a fully-upgraded source -- the one arrangement nobody looks
    at until it ships."""
    mesh.apply_scale(FOOD_MODEL_SCALE)
    size = mesh.extents
    assert size[0] <= FOOD_SLOT_WIDTH, f"produce is {size[0]:.2f} wide, slot is {FOOD_SLOT_WIDTH}"
    assert size[2] <= FOOD_SLOT_DEPTH, f"produce is {size[2]:.2f} deep, slot is {FOOD_SLOT_DEPTH}"
    return mesh


def build_source_base() -> trimesh.Trimesh:
    """A source's yard: the settlement plaza at 2x1. Deliberately the same
    stone rather than a colour of its own -- a source and a settlement are both
    PLACES standing on ground the player cannot build over, and what tells them
    apart is what stands on top: produce models against red roofs."""
    return trimesh.util.concatenate(
        _plaza(4.0 - 2 * PLAZA_INSET, 2.0 - 2 * PLAZA_INSET)
    )


# ------------------------------------------------ player-built structures
#
# Storage and hubs are TINTED at runtime by their type -- Normal against Cool
# storage, and the hub's own orange (MarkerColors) -- so unlike a settlement
# they cannot simply carry their own palette. They export as two named
# geometries instead: `body` keeps the colours authored here, and `tint` is the
# one mesh NodeMarker recolours.
#
# The roof is the tinted part in both cases, and that is the whole reason these
# read at all: the camera is pitched down 60 degrees, so a roof is the largest
# surface of any small building it can see. Tinting the walls instead would put
# the type colour on the sliver that is edge-on to the player.
STRUCT_WALL = (238, 232, 220, 255)
STRUCT_WALL_SHADE = (214, 206, 192, 255)
STRUCT_TRIM = (120, 110, 98, 255)
STRUCT_DOOR = (122, 96, 74, 255)

# Bridges. Both are stone-and-timber rather than painted, so a crossing reads
# as a structure the player built over something rather than as another tile.
BRIDGE_DECK_COLOR = (199, 183, 155, 255)
BRIDGE_RAIL_COLOR = (138, 119, 88, 255)
BRIDGE_PIER_COLOR = (160, 146, 124, 255)
RIVER_DECK_COLOR = (239, 231, 210, 255)
RIVER_STONE = (206, 198, 186, 255)
RIVER_STONE_DARK = (158, 150, 138, 255)

## Where a road-over-road bridge's deck sits. The ENDS are what the arch is
## for: a flat deck floating at one height reads as a slab parked in mid-air,
## while a span that springs from the tile edge and rises over the middle reads
## as something crossing. The peak must stay at Main.BRIDGE_DECK_HEIGHT, which
## is the height the established-route overlay lifts a crossing lane to.
## The ends cannot go lower: the deck is placed at the road SURFACE, and a
## route plate is 0.22 thick, so an arch springing from much under this is
## buried in the road it is supposed to be crossing. The rise therefore has to
## come from raising the peak rather than dropping the ends -- at a 60-degree
## camera a shallow arc foreshortens into a flat plank.
ARCH_END_Y = 0.30
ARCH_PEAK_Y = 0.78
ARCH_DECK_THICKNESS = 0.11
ARCH_WIDTH = 1.00
ARCH_SEGMENTS = 9

## The river crossing. Raised from the old flat 0.16 slab because an arch needs
## headroom to be an arch at all: at 0.16 there is no room under the deck for
## an opening, and the "bridge" is a painted strip.
RIVER_DECK_TOP = 0.30
RIVER_PIER_HEIGHT = 0.20


def _arch_y(x, half_length):
    """The deck's top surface at `x`, as a parabola from ARCH_END_Y at the ends
    to ARCH_PEAK_Y over the middle."""
    t = x / half_length
    return ARCH_END_Y + (ARCH_PEAK_Y - ARCH_END_Y) * (1.0 - t * t)


def _arch_run(length, width, thickness, color, drop=0.0):
    """A run of boxes following the arch, each tilted to the local slope.

    Segments overlap slightly (the 1.12) because a chain of tilted boxes meets
    at its corners, not its faces -- without the overlap the deck is a dotted
    line of wedges with daylight between them."""
    half = length / 2
    seg = length / ARCH_SEGMENTS
    parts = []
    for i in range(ARCH_SEGMENTS):
        x = -half + seg * (i + 0.5)
        top = _arch_y(x, half) - drop
        slope = (_arch_y(x + seg * 0.5, half) - _arch_y(x - seg * 0.5, half)) / seg
        box = trimesh.creation.box(extents=(seg * 1.12, thickness, width))
        box.apply_transform(trimesh.transformations.rotation_matrix(math.atan(slope), (0, 0, 1)))
        box.apply_translation((x, top - thickness / 2, 0))
        box.visual.vertex_colors = np.tile(color, (len(box.vertices), 1))
        parts.append(box)
    return parts


def build_bridge_arch() -> trimesh.Trimesh:
    """The road-over-road bridge: an arched span rising over the road it
    crosses, with rails following the arc and an abutment at each end.

    Authored along +X with its origin on the ROAD SURFACE, so Main places it at
    the tile position with no vertical offset and it grows up out of the road
    when it pops. Rotated a quarter turn when the deck runs along Z; the span
    is symmetric end to end, so one model serves both directions.

    The middle is deliberately left open. A bridge tile keeps its own road
    underneath and the whole point of the structure is that the player can see
    two roads there -- an arch with a filled belly would hide the one it is
    crossing, which is the thing it exists to advertise."""
    length = 2.0
    parts = _arch_run(length, ARCH_WIDTH, ARCH_DECK_THICKNESS, BRIDGE_DECK_COLOR)
    for side in (1, -1):
        rail_z = side * (ARCH_WIDTH / 2 - 0.05)
        for box in _arch_run(length, 0.12, 0.24, BRIDGE_RAIL_COLOR, drop=-0.16):
            box.apply_translation((0, 0, rail_z))
            parts.append(box)
    # Abutments: the span has to stand on something, and they also close the
    # end of the arch so it does not read as a ramp sawn off at the tile edge.
    for side in (1, -1):
        parts += _chamfered_box(
            (0.26, ARCH_END_Y, ARCH_WIDTH),
            (side * (length / 2 - 0.13), ARCH_END_Y / 2, 0),
            BRIDGE_PIER_COLOR,
            0.05,
        )
    return trimesh.util.concatenate(parts)


def build_river_bridge() -> trimesh.Trimesh:
    """The river crossing: a stone viaduct on two arched openings, with a
    balustrade down each side.

    Automatic rather than placed -- a route drawn onto the river column pays
    RIVER_BRIDGE_COST and gets this (TERR-05) -- so unlike the arch it is a
    piece of ROAD and its deck is flat and cream, continuous with the tiles
    either side. What makes it architectural is underneath: piers standing in
    the water and openings corbelled into arches between them.

    Authored along +X, origin at the terrain surface, and rotated a quarter
    turn where the crossing runs north-south."""
    length = 2.0
    width = 1.34
    parts = []
    # Three piers, so there are two openings for the water to run through.
    for x in (-0.78, 0.0, 0.78):
        parts += _chamfered_box(
            (0.30, RIVER_PIER_HEIGHT, width), (x, RIVER_PIER_HEIGHT / 2, 0), RIVER_STONE_DARK, 0.04
        )
    # Corbelled shoulders: two stepped blocks over each side of each opening,
    # which is what turns a square hole into something that reads as an arch at
    # this size. A true curve would cost far more geometry to say the same.
    for center in (-0.39, 0.39):
        for side in (1, -1):
            for step, (dx, dy, w) in enumerate([(0.10, 0.015, 0.16), (0.055, 0.05, 0.11)]):
                parts.append(
                    _box(
                        (w, 0.05, width),
                        (center + side * dx, RIVER_PIER_HEIGHT - 0.025 - dy + step * 0.0, 0),
                        RIVER_STONE_DARK,
                    )
                )
    # The deck: stone band under a cream road surface, so the crossing reads as
    # continuous with the road on either side rather than as a grey gap in it.
    parts += _chamfered_box(
        (length, 0.07, width), (0, RIVER_DECK_TOP - 0.055, 0), RIVER_STONE, 0.03
    )
    parts.append(_box((length, 0.04, width - 0.26), (0, RIVER_DECK_TOP - 0.02, 0), RIVER_DECK_COLOR))
    # Balustrades, with posts, along both edges.
    for side in (1, -1):
        z = side * (width / 2 - 0.06)
        parts += _chamfered_box((length, 0.13, 0.10), (0, RIVER_DECK_TOP + 0.065, z), RIVER_STONE, 0.03)
        for x in (-0.84, 0.0, 0.84):
            parts += _chamfered_box((0.14, 0.19, 0.15), (x, RIVER_DECK_TOP + 0.095, z), RIVER_STONE, 0.04)
    return trimesh.util.concatenate(parts)


def build_storage() -> trimesh.Trimesh:
    """A warehouse: cream walls, a wide gabled roof, a loading door.

    Returns body/tint as a scene -- the ROOF is the tinted mesh, because it is
    the largest surface this camera can see on a building this small and the
    tint is what tells Normal storage from Cool (MarkerColors.storage_color).
    Authored origin-at-base so it stands on whatever road it is built over."""
    wall = 0.42
    parts = _chamfered_box((0.86, wall, 0.66), (0, wall / 2, 0), STRUCT_WALL, 0.05)
    parts.append(_box((0.24, wall * 0.6, 0.05), (0, wall * 0.3, 0.33), STRUCT_DOOR))
    parts.append(_box((0.90, 0.05, 0.70), (0, wall + 0.02, 0), STRUCT_TRIM))
    roof = [_pyramid(1.02, 0.82, 0.34, (0, wall + 0.04, 0), STRUCT_WALL_SHADE)]
    return _named_scene({"body": parts, "tint": roof})


def build_hub() -> trimesh.Trimesh:
    """A depot: a drum with a conical roof and a finial on top.

    Round rather than square on purpose -- a hub is the one player-built thing
    that is not a box, so it is separable from a storage at a glance even
    before the tint is read. Roof is the tinted mesh, same as a storage."""
    drum = 0.40
    parts = [_cylinder(0.34, drum, (0, drum / 2, 0), STRUCT_WALL, sections=10)]
    parts.append(_cylinder(0.38, 0.05, (0, drum + 0.01, 0), STRUCT_TRIM, sections=10))
    parts.append(_box((0.20, drum * 0.62, 0.05), (0, drum * 0.31, 0.33), STRUCT_DOOR))
    roof = [_cone(0.46, 0.34, (0, drum + 0.03, 0), STRUCT_WALL_SHADE, sections=10)]
    roof.append(_cylinder(0.05, 0.16, (0, drum + 0.42, 0), STRUCT_TRIM, sections=6))
    return _named_scene({"body": parts, "tint": roof})


def _cone(radius, height, translation, color, sections=8) -> trimesh.Trimesh:
    """A Y-up cone with its base at the translation's y and its apex above."""
    mesh = trimesh.creation.cone(radius=radius, height=height, sections=sections)
    mesh.apply_transform(trimesh.transformations.rotation_matrix(-math.pi / 2, (1, 0, 0)))
    mesh.apply_translation(translation)
    mesh.visual.vertex_colors = np.tile(color, (len(mesh.vertices), 1))
    return mesh


def export(mesh: trimesh.Trimesh, path: str) -> None:
    _matte(mesh)
    mesh.export(path, file_type="glb")
    print(f"wrote {path} ({len(mesh.vertices)} verts, {len(mesh.faces)} faces)")


def export_scene(scene: trimesh.Scene, path: str) -> None:
    scene.export(path, file_type="glb")
    counts = ", ".join(f"{name} {len(g.faces)}f" for name, g in scene.geometry.items())
    print(f"wrote {path} ({counts})")


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
    export_scene(build_settlement_village(), "assets/Environment/glTF/Settlement_Village.glb")
    export_scene(build_settlement_town(), "assets/Environment/glTF/Settlement_Town.glb")
    export_scene(build_settlement_city(), "assets/Environment/glTF/Settlement_City.glb")
    export(build_source_base(), "assets/Environment/glTF/Source_Base.glb")
    export(build_food_grain(), "assets/Environment/glTF/Food_Grain.glb")
    export(build_food_bread(), "assets/Environment/glTF/Food_Bread.glb")
    export(build_food_vegetables(), "assets/Environment/glTF/Food_Vegetables.glb")
    export(build_food_milk(), "assets/Environment/glTF/Food_Milk.glb")
    export(build_food_seafood(), "assets/Environment/glTF/Food_Seafood.glb")
    export_scene(build_storage(), "assets/Environment/glTF/Storage.glb")
    export_scene(build_hub(), "assets/Environment/glTF/Hub.glb")
    export(build_bridge_arch(), "assets/Environment/glTF/Bridge_Arch.glb")
    export(build_river_bridge(), "assets/Environment/glTF/Bridge_River.glb")
