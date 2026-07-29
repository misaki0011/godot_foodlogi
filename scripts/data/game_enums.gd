class_name GameEnums

enum NodeType { SOURCE, SETTLEMENT }

## How big a settlement is (DEV-04). Drives two things that belong together:
## how many demand lines it may ever hold (GameBalance.DEMAND_CAP) and how
## many tiles it stands on (DEV-02) -- a City is a bigger place in both
## senses. NodeData.kind stays a free-text display label; rules key off this.
enum SettlementType { VILLAGE, TOWN, CITY }
enum StorageType { NORMAL, COOL }
enum HubType { SMALL }
enum TerrainType { PLAINS, RIVER }
