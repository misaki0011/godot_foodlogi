class_name SettlementData
extends Resource

@export var settlement_id: String
@export var settlement_type: GameEnums.SettlementType
@export var price_modifier: float = 1.0
@export var demands: Array[SettlementDemandData] = []

