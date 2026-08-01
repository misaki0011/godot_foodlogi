class_name GameEnums

enum NodeType { SOURCE, SETTLEMENT }

## How big a settlement is (DEV-04). Drives two things that belong together:
## how many demand lines it may ever hold (GameBalance.DEMAND_CAP) and how
## many tiles it stands on (DEV-02) -- a City is a bigger place in both
## senses. NodeData.kind stays a free-text display label; rules key off this.
enum SettlementType { VILLAGE, TOWN, CITY }
enum StorageType { NORMAL, COOL }
enum HubType { SMALL }
## PLAINS and RIVER keep their values so authored data does not shift. SEA is
## the first terrain a route may never be built on at ANY price: a river is a
## §40 crossing (TERR-05), the sea is a wall. TERR-06 replaces the column-based
## lookup behind this with a per-cell grid and appends the rest.
enum TerrainType { PLAINS, RIVER, SEA }
