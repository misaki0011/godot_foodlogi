@tool
class_name NodeMarker
extends Node3D

## Shared behavior for all node/tile marker scenes. Per-type scenes provide
## their own visual mesh(es) under a child named "Visual"; this script just
## tints them. Used both for fixed source/settlement nodes (setup) and for
## player-built storage/hub grid tiles (apply_tint). No marker shows name
## text on the map: sources/settlements get speech bubbles instead
## (node_spawner.gd, main.gd), and storage/hub are distinguishable by tint
## and hover tooltip.

@export var node_data: NodeData

## Whether this marker's art carries its OWN palette and must be left alone.
##
## The tint below flattens every mesh under "Visual" to a single colour, which
## is exactly right for a marker whose whole job is to be one colour (a
## storage, a hub, the old settlement pole) and destroys one built out of
## several -- a settlement's cream walls, red roofs, stone plaza and green
## tree would all come out the same red. Set on the settlement marker scenes;
## they keep MarkerColors.SETTLEMENT_COLOR on their roofs themselves, so the
## map does not lose the colour that means "somewhere food goes".
@export var self_coloured := false

## ---------- lit windows (LOOP-08) ----------
##
## A settlement's glTF ships its window panes as their own named geometry, so
## Godot imports them as a MeshInstance3D of their own (see
## generate_blocks.py's _settlement_scene). That separation exists purely so
## the panes can be lit: a mesh merged into the walls has no way to glow
## without the walls glowing with it.
##
## The light is EMISSION on that one mesh rather than a real light source. Five
## settlements' worth of OmniLight3Ds would be five more lights for a renderer
## that is already the compatibility backend on a phone browser, to light
## nothing but themselves -- these windows are meant to be seen, not to cast.
const WINDOWS_NODE := "windows"
## Daylight glass, and the lamp behind it. Emission is ADDED to the lit albedo,
## so the pane reads as cold glass by day and warms right through to lamplight
## as the multiplier comes up -- one material covering both, with only the
## energy animating.
const WINDOW_GLASS_COLOR := Color("6888A8")
## Deliberately a saturated amber at a modest multiplier rather than a pale
## cream at a big one. Emission is added to the lit colour and then clipped, so
## a near-white lamp pushed hard clips on all three channels and the windows
## come out white -- which reads as a hole in the wall, not as a light on.
const WINDOW_LIT_COLOR := Color("FFC062")
const WINDOW_MAX_EMISSION := 1.15

var _window_mesh: MeshInstance3D
var _window_material: StandardMaterial3D
## Whether the lookup has already run. Most markers have no window mesh at all
## (a source, a hub, a storage), and without this the miss would re-walk their
## whole subtree on every frame of the day clock.
var _windows_resolved := false

func setup(data: NodeData, tint: Color) -> void:
	node_data = data
	if not self_coloured:
		_tint_recursive_root(tint)

## Lights this marker's windows, 0 (broad daylight) to 1 (fully dark). A marker
## whose art has no separate window mesh -- a source, a hub, a storage -- has
## nothing to light and quietly does nothing, so the caller can sweep every
## marker without asking what kind each one is.
func set_window_glow(amount: float) -> void:
	if not _windows_resolved:
		_windows_resolved = true
		_window_mesh = _find_windows(self)
		if _window_mesh != null:
			# The panes come in vertex-coloured like everything else; an override
			# is what lets one flat colour take an emission that follows the clock.
			_window_material = StandardMaterial3D.new()
			_window_material.albedo_color = WINDOW_GLASS_COLOR
			_window_material.emission_enabled = true
			_window_material.emission = WINDOW_LIT_COLOR
			_window_mesh.material_override = _window_material
	if _window_material == null:
		return
	_window_material.emission_energy_multiplier = clampf(amount, 0.0, 1.0) * WINDOW_MAX_EMISSION

func _find_windows(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and node.name == WINDOWS_NODE:
		return node
	for child in node.get_children():
		var found := _find_windows(child)
		if found:
			return found
	return null

func apply_tint(color: Color) -> void:
	_tint_recursive_root(color)

func _tint_recursive_root(tint: Color) -> void:
	var visual := get_node_or_null("Visual")
	if visual:
		_tint_recursive(visual, tint)

func _tint_recursive(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		node.material_override = mat
	for child in node.get_children():
		_tint_recursive(child, color)
