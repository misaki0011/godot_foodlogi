class_name MarkerColors

const NODE_TYPE_COLORS := {
	GameEnums.NodeType.SOURCE: Color(0.85, 0.65, 0.2),
	GameEnums.NodeType.SETTLEMENT: Color(0.35, 0.8, 0.4),
	GameEnums.NodeType.STORAGE: Color(0.3, 0.75, 0.85),
	GameEnums.NodeType.HUB: Color(0.75, 0.35, 0.75),
}

const STORAGE_TYPE_COLORS := {
	GameEnums.StorageType.NORMAL: Color(0.82, 0.72, 0.55),
	GameEnums.StorageType.COOL: Color(0.3, 0.75, 0.95),
	GameEnums.StorageType.FREEZE: Color(0.85, 0.95, 1.0),
}

const HUB_TYPE_COLORS := {
	GameEnums.HubType.SMALL: Color(0.75, 0.35, 0.75),
	GameEnums.HubType.REGIONAL: Color(0.55, 0.2, 0.75),
	GameEnums.HubType.CENTRAL: Color(0.35, 0.05, 0.55),
}

const SETTLEMENT_TYPE_COLORS := {
	GameEnums.SettlementType.VILLAGE: Color(0.55, 0.85, 0.4),
	GameEnums.SettlementType.TOWN: Color(0.95, 0.85, 0.3),
	GameEnums.SettlementType.CITY: Color(0.95, 0.7, 0.15),
	GameEnums.SettlementType.MOUNTAIN_VILLAGE: Color(0.6, 0.6, 0.65),
	GameEnums.SettlementType.COASTAL_TOWN: Color(0.3, 0.6, 0.85),
}

## Picks the most specific color available for a node: its linked
## StorageData/HubData subtype color when present, else the node-type color.
static func color_for(node_data: NodeData) -> Color:
	if node_data.linked_resource is StorageData:
		var storage: StorageData = node_data.linked_resource
		return STORAGE_TYPE_COLORS.get(storage.storage_type, NODE_TYPE_COLORS[GameEnums.NodeType.STORAGE])
	if node_data.linked_resource is HubData:
		var hub: HubData = node_data.linked_resource
		return HUB_TYPE_COLORS.get(hub.hub_type, NODE_TYPE_COLORS[GameEnums.NodeType.HUB])
	if node_data.linked_resource is SettlementData:
		var settlement: SettlementData = node_data.linked_resource
		return SETTLEMENT_TYPE_COLORS.get(settlement.settlement_type, NODE_TYPE_COLORS[GameEnums.NodeType.SETTLEMENT])
	return NODE_TYPE_COLORS.get(node_data.node_type, Color.WHITE)
