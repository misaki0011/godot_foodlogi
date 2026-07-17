"""Generate the small set of block-style glTF props the game still needs.

The original Kenney asset pack was deleted from the repo, so every block and
prop here is procedurally rebuilt as a simple, low-poly, vertex-colored mesh
-- no textures needed. Terrain and route-tile blocks use a chunky,
Animal-Crossing-inspired look (a distinct capped/inset top layer plus small
detail bumps) instead of a single flat-colored cube, so tiles read as
individual toy-like blocks rather than a flat color underneath the camera.

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

# Terrain (GridMap cell content, unit cube -- GridMap scales this up by its
# cell_size at placement time, same as the flat cubes it replaces).
DIRT_SIDE = (150, 116, 74, 255)
DIRT_BOTTOM = (117, 89, 56, 255)
GRASS_CAP = (128, 197, 104, 255)
GRASS_TUFT = (104, 173, 84, 255)
WATER_SIDE = (86, 138, 176, 255)
WATER_BOTTOM = (66, 111, 148, 255)
WATER_CAP = (150, 215, 232, 255)
WATER_RIPPLE = (203, 238, 245, 255)

# Route tiles (world-space slabs main.gd lays on top of the terrain, sized
# directly in meters -- no extra runtime scale needed).
DIRT_ROAD_BASE = (181, 148, 100, 255)
DIRT_ROAD_PATH = (201, 172, 122, 255)
PAVED_BASE = (142, 138, 132, 255)
PAVED_STONE = (176, 172, 164, 255)
MAIN_BASE = (90, 80, 68, 255)
MAIN_STRIPE = (223, 208, 168, 255)


def _box(extents, translation, color) -> trimesh.Trimesh:
    mesh = trimesh.creation.box(extents=extents)
    mesh.apply_translation(translation)
    mesh.visual.vertex_colors = np.tile(color, (len(mesh.vertices), 1))
    return mesh


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
    """Chunky grass-over-dirt cube: a dirt base with a slightly overhanging
    grass cap and four little corner tufts, instead of a flat two-tone
    split, so it reads as a toy block rather than a painted cube."""
    parts = [
        _box((1.0, 0.68, 1.0), (0, -0.16, 0), DIRT_SIDE),
        _box((1.0, 0.06, 1.0), (0, -0.47, 0), DIRT_BOTTOM),
        _box((1.03, 0.34, 1.03), (0, 0.33, 0), GRASS_CAP),
    ]
    tuft = 0.16
    for dx in (-1, 1):
        for dz in (-1, 1):
            x = dx * 0.32
            z = dz * 0.32
            parts.append(_box((tuft, 0.12, tuft), (x, 0.55, z), GRASS_TUFT))
    return trimesh.util.concatenate(parts)


def build_river_block() -> trimesh.Trimesh:
    """Chunky water cube: a darker basin with a bright cap and two pale
    ripple strips, echoing Animal Crossing's cute, high-contrast water."""
    parts = [
        _box((1.0, 0.68, 1.0), (0, -0.16, 0), WATER_SIDE),
        _box((1.0, 0.06, 1.0), (0, -0.47, 0), WATER_BOTTOM),
        _box((1.03, 0.3, 1.03), (0, 0.35, 0), WATER_CAP),
        _box((0.6, 0.02, 0.1), (-0.15, 0.51, -0.2), WATER_RIPPLE),
        _box((0.5, 0.02, 0.1), (0.18, 0.51, 0.22), WATER_RIPPLE),
    ]
    return trimesh.util.concatenate(parts)


def build_dirt_road_block() -> trimesh.Trimesh:
    """A worn dirt path slab: a tan base with a lighter, slightly inset
    tread strip down the middle."""
    parts = [
        _box((1.55, 0.22, 1.55), (0, 0, 0), DIRT_ROAD_BASE),
        _box((1.15, 0.05, 1.55), (0, 0.135, 0), DIRT_ROAD_PATH),
    ]
    return trimesh.util.concatenate(parts)


def build_paved_road_block() -> trimesh.Trimesh:
    """A paved road slab: a grey base topped with four individually raised
    cobblestone pavers (small gaps between them) instead of a flat color,
    so it actually reads as *paving* rather than a generic grey box."""
    parts = [_box((1.55, 0.22, 1.55), (0, 0, 0), PAVED_BASE)]
    stone = 0.68
    gap_offset = stone / 2 + 0.03
    for dx in (-1, 1):
        for dz in (-1, 1):
            parts.append(
                _box((stone, 0.08, stone), (dx * gap_offset, 0.15, dz * gap_offset), PAVED_STONE)
            )
    return trimesh.util.concatenate(parts)


def build_main_road_block() -> trimesh.Trimesh:
    """A major road slab: a dark base with a pale painted center line, for
    the most-upgraded route tier."""
    parts = [
        _box((1.55, 0.24, 1.55), (0, 0, 0), MAIN_BASE),
        _box((0.16, 0.03, 1.3), (0, 0.135, 0), MAIN_STRIPE),
    ]
    return trimesh.util.concatenate(parts)


def export(mesh: trimesh.Trimesh, path: str) -> None:
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
