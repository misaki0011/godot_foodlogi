"""Generate the small set of block-style glTF props the game still needs.

The original Kenney asset pack was deleted from the repo, so every block and
prop here is procedurally rebuilt as a simple, low-poly, vertex-colored mesh
-- no textures needed. Terrain and route-tile blocks use a chunky,
Animal-Crossing-inspired look (a distinct capped/inset top layer plus small
detail bumps) instead of a single flat-colored cube.

Every block shares one convention: a 1.0 x 1.0 local footprint, matched to
one GridMap cell (terrain blocks get GridMap's automatic cell_size scale;
route-tile blocks get the same XZ scale applied explicitly in main.gd) so
tiles sit flush against their neighbors with no visible gap. Each tile's top
face has a thin border baked in at the true edge instead, so adjacent tiles'
borders meet and read as a continuous grid line across the map.

Every mesh gets an explicit matte (non-metallic, fully rough) material --
without one, Godot's glTF import falls back to a shinier default that
picks up visible reflections/banding from the editor's sky, which reads as
a "weird texture" despite there being no texture in this pipeline at all.

Run with: uv run --python .venv tools/asset_gen/generate_blocks.py
"""

from __future__ import annotations

import numpy as np
import trimesh

WOOD_LIGHT = (168, 122, 78, 255)
WOOD_DARK = (107, 74, 42, 255)
CHEST_BASE = (122, 91, 63, 255)
CHEST_LID = (94, 67, 45, 255)
METAL_BAND = (150, 150, 158, 255)
LATCH_GOLD = (201, 162, 39, 255)

# Terrain (GridMap cell content, 1x1 local footprint -- GridMap scales this
# up by its cell_size at placement time).
DIRT_SIDE = (150, 116, 74, 255)
DIRT_BOTTOM = (117, 89, 56, 255)
GRASS_CAP = (128, 197, 104, 255)
GRASS_TUFT = (104, 173, 84, 255)
WATER_SIDE = (86, 138, 176, 255)
WATER_BOTTOM = (66, 111, 148, 255)
WATER_CAP = (150, 215, 232, 255)
WATER_RIPPLE = (203, 238, 245, 255)

# Route tiles (main.gd applies the same XZ cell_size scale as terrain, but
# keeps their authored height in final world-space meters).
DIRT_ROAD_BASE = (181, 148, 100, 255)
DIRT_ROAD_PATH = (201, 172, 122, 255)
PAVED_BASE = (142, 138, 132, 255)
PAVED_STONE = (176, 172, 164, 255)
MAIN_BASE = (90, 80, 68, 255)
MAIN_STRIPE = (223, 208, 168, 255)

GRID_LINE_COLOR = (96, 100, 82, 255)
GRID_LINE_THICKNESS = 0.03


def _box(extents, translation, color) -> trimesh.Trimesh:
    mesh = trimesh.creation.box(extents=extents)
    mesh.apply_translation(translation)
    mesh.visual.vertex_colors = np.tile(color, (len(mesh.vertices), 1))
    return mesh


def _grid_border_parts(footprint: float, top_y: float) -> list[trimesh.Trimesh]:
    """Four thin strips forming a frame flush with a tile's true edge (no
    inset), so two full-footprint tiles placed side by side have their
    strips touch and read as one continuous grid line, replacing the old
    gap-between-tiles look."""
    half = footprint / 2
    edge = half - GRID_LINE_THICKNESS / 2
    return [
        _box((footprint, 0.02, GRID_LINE_THICKNESS), (0, top_y, edge), GRID_LINE_COLOR),
        _box((footprint, 0.02, GRID_LINE_THICKNESS), (0, top_y, -edge), GRID_LINE_COLOR),
        _box((GRID_LINE_THICKNESS, 0.02, footprint), (edge, top_y, 0), GRID_LINE_COLOR),
        _box((GRID_LINE_THICKNESS, 0.02, footprint), (-edge, top_y, 0), GRID_LINE_COLOR),
    ]


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
    """Chunky grass-over-dirt cube: a dirt base with a flush (same-size,
    non-overhanging) grass cap and four little corner tufts, plus a grid
    border baked into the top edge.

    The dirt base is a deep plinth (not just a shallow slab) on purpose:
    the game camera looks down at a fixed ~60 degree angle, not straight
    down, so a shallow-based tile leaves a gap of empty space beneath its
    visible front face before the next row's tile begins -- the camera
    sees clean through to the sky background there. A shallow base looks
    fine from directly above but shows a real gap at this camera's actual
    angle; the plinth needs to reach deep enough that there's no empty
    space left for that camera angle to see into."""
    parts = [
        _box((1.0, 3.18, 1.0), (0, -1.41, 0), DIRT_SIDE),
        _box((1.0, 0.06, 1.0), (0, -2.97, 0), DIRT_BOTTOM),
        _box((1.0, 0.34, 1.0), (0, 0.33, 0), GRASS_CAP),
    ]
    tuft = 0.16
    for dx in (-1, 1):
        for dz in (-1, 1):
            x = dx * 0.32
            z = dz * 0.32
            parts.append(_box((tuft, 0.12, tuft), (x, 0.55, z), GRASS_TUFT))
    parts += _grid_border_parts(1.0, 0.502)
    return trimesh.util.concatenate(parts)


def build_river_block() -> trimesh.Trimesh:
    """Chunky water cube: a darker basin with a flush (same-size) bright
    cap, two pale ripple strips, and a grid border on top. Deep plinth for
    the same reason as build_grass_block()'s -- no gap-to-the-sky at the
    camera's actual viewing angle."""
    parts = [
        _box((1.0, 3.18, 1.0), (0, -1.41, 0), WATER_SIDE),
        _box((1.0, 0.06, 1.0), (0, -2.97, 0), WATER_BOTTOM),
        _box((1.0, 0.3, 1.0), (0, 0.35, 0), WATER_CAP),
        _box((0.6, 0.02, 0.1), (-0.15, 0.51, -0.2), WATER_RIPPLE),
        _box((0.5, 0.02, 0.1), (0.18, 0.51, 0.22), WATER_RIPPLE),
    ]
    parts += _grid_border_parts(1.0, 0.502)
    return trimesh.util.concatenate(parts)


def build_dirt_road_block() -> trimesh.Trimesh:
    """A worn dirt path slab: a tan base with a lighter, slightly inset
    tread strip down the middle, and a grid border on top. 1x1 local
    footprint (main.gd scales it to fill a cell, same as terrain); height
    stays authored directly in world-space meters."""
    parts = [
        _box((1.0, 0.22, 1.0), (0, 0, 0), DIRT_ROAD_BASE),
        _box((0.74, 0.05, 1.0), (0, 0.135, 0), DIRT_ROAD_PATH),
    ]
    parts += _grid_border_parts(1.0, 0.111)
    return trimesh.util.concatenate(parts)


def build_paved_road_block() -> trimesh.Trimesh:
    """A paved road slab: a grey base topped with four individually raised
    cobblestone pavers (small gaps between them) instead of a flat color,
    so it actually reads as *paving* rather than a generic grey box."""
    parts = [_box((1.0, 0.22, 1.0), (0, 0, 0), PAVED_BASE)]
    stone = 0.44
    gap_offset = stone / 2 + 0.02
    for dx in (-1, 1):
        for dz in (-1, 1):
            parts.append(
                _box((stone, 0.08, stone), (dx * gap_offset, 0.15, dz * gap_offset), PAVED_STONE)
            )
    parts += _grid_border_parts(1.0, 0.111)
    return trimesh.util.concatenate(parts)


def build_main_road_block() -> trimesh.Trimesh:
    """A major road slab: a dark base with a pale painted center line, for
    the most-upgraded route tier."""
    parts = [
        _box((1.0, 0.24, 1.0), (0, 0, 0), MAIN_BASE),
        _box((0.1, 0.03, 0.84), (0, 0.135, 0), MAIN_STRIPE),
    ]
    parts += _grid_border_parts(1.0, 0.121)
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
