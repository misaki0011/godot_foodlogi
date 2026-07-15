class_name MarkerColors

## Matches fresh-routes-mvp.html's draw(): all sources share one color, all
## settlements share another; only storage/hub sub-types get distinct tints.

const SOURCE_COLOR := Color("8B6B3E")
const SETTLEMENT_COLOR := Color("C4573A")

static func node_color(node_data: NodeData) -> Color:
	return SOURCE_COLOR if node_data.node_type == GameEnums.NodeType.SOURCE else SETTLEMENT_COLOR

static func storage_color(stype: GameEnums.StorageType) -> Color:
	return GameBalance.STORAGE_TYPES[stype].color

static func hub_color(htype: GameEnums.HubType) -> Color:
	return GameBalance.HUB_TYPES[htype].color
