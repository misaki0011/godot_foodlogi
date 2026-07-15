"""Generate the small set of block-style glTF props the game still needs.

The original Kenney asset pack was deleted from the repo. Terrain rendering
survives because resources/terrain/blocks.meshlib already has baked mesh
data, but two marker scenes (source_marker.tscn, storage_marker.tscn)
referenced external glTF files that no longer exist. This script
procedurally rebuilds just those two props as simple, low-poly, vertex
colored blocks -- no textures needed.

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
GRASS_TOP = (110, 173, 92, 255)
GRASS_SIDE = (137, 107, 66, 255)
ICE_TOP = (188, 224, 240, 255)
ICE_SIDE = (129, 175, 204, 255)


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


def _two_tone_cube(top_color, side_color) -> trimesh.Trimesh:
    """A unit cube with one color on top and another on the sides/bottom,
    since a MeshLibrary item is baked mesh geometry -- vertex colors survive
    the bake with no external texture file to go missing later."""
    box = trimesh.creation.box(extents=(1.0, 1.0, 1.0))
    colors = np.tile(side_color, (len(box.vertices), 1))
    top_mask = box.vertices[:, 1] > 0.49
    colors[top_mask] = top_color
    box.visual.vertex_colors = colors
    return box


def build_grass_block() -> trimesh.Trimesh:
    return _two_tone_cube(GRASS_TOP, GRASS_SIDE)


def build_ice_block() -> trimesh.Trimesh:
    return _two_tone_cube(ICE_TOP, ICE_SIDE)


def export(mesh: trimesh.Trimesh, path: str) -> None:
    mesh.export(path, file_type="glb")
    print(f"wrote {path} ({len(mesh.vertices)} verts, {len(mesh.faces)} faces)")


if __name__ == "__main__":
    export(build_crate(), "assets/Blocks/glTF/Block_Crate.glb")
    export(build_chest(), "assets/Environment/glTF/Chest_Closed.glb")
    export(build_grass_block(), "assets/Blocks/glTF/Block_Grass.glb")
    export(build_ice_block(), "assets/Blocks/glTF/Block_Ice.glb")
