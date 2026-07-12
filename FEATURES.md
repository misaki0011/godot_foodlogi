# Fresh Routes — Features

Extracted from `SPEC.md`. Status reflects actual implementation state, not spec intent — update both files together when scope changes.

Status legend: **Done** (built and verified) · **In Progress** · **Planned** (MVP scope, not started) · **Backlog** (explicitly post-MVP per §13/§14).

| ID | Feature | Status | Priority | Depends on | Acceptance criteria | Spec |
| --- | --- | --- | --- | --- | --- | --- |
| CORE-01 | Node/GameEnums data model | Done | P0 | — | NodeData resource stores node_id, node_type (source/settlement/storage/hub), grid_position; GameEnums defines NodeType, StorageType, HubType, TerrainType, SettlementType. | §16 |
| CORE-02 | RouteSegment data model | Done | P0 | CORE-01 | RouteSegmentData resource stores route_id, from_node, to_node, length, terrain_profile, capacity, base_upkeep. | §16 |
| CORE-03 | FoodFlow data model | Done | P0 | CORE-01 | FoodFlowData resource stores flow_id, food_id, source_node, destination_node, path, amount_per_day, current_freshness. | §16 |
| CORE-04 | Storage data model | Done | P0 | CORE-01 | StorageData resource stores storage_id, storage_type, capacity, daily_upkeep, protection_distance, freshness_loss_multiplier, compatible_food_categories. | §16, §4.3 |
| CORE-05 | Hub data model | Done | P0 | CORE-01 | HubData resource stores hub_id, hub_type, link_capacity, flow_capacity, route_discount, daily_upkeep. | §16, §4.4 |
| CORE-06 | SettlementDemand data model | Done | P0 | CORE-01 | SettlementDemandData resource stores settlement_id, food_id, amount_required, minimum_freshness, bonus_freshness, overdelivery_tolerance. | §16, §4.8 |
| CORE-07 | Region map data (single source of truth) | Done | P0 | CORE-01 | MapData resource stores grid_size, terrain_rows, and node_placements; terrain renderer and node spawner both read the same instance. | §16 |
| TERR-01 | Terrain type rendering | Done | P0 | CORE-07 | Plains, Forest, Mountain, River, and Snow cells render with distinct block meshes (Grass / Grass+props / Stone / Ice / Snow) via GridMap. | §8 |
| TERR-02 | MVP region layout | Done | P0 | TERR-01 | Map contains 3 food sources, 5 settlements, 1 river obstacle, and 1 late-objective city/town, matching §11's example scenario. | §12, §11 |
| TERR-03 | Node markers on terrain | Done | P0 | TERR-01, CORE-01 | Each node placement spawns a type-tinted marker (source/settlement/storage/hub) positioned exactly on its grid cell. | §16 |
| TERR-04 | Terrain cost/decay modifiers | Planned | P1 | TERR-01, ROUTE-02 | Each terrain type applies its cost multiplier and freshness decay multiplier to any route segment crossing it (Plains normal, Forest low-cost/more decay, Mountain high-cost/more decay, River bridge-required, Snow medium-high cost/more decay for fresh foods). | §8 |
| TERR-05 | River bridge requirement | Planned | P2 | TERR-04 | Routes cannot cross a River cell without a bridge; river tiles act as chokepoints. | §8 |
| ROUTE-01 | Route drawing input | Planned | P0 | TERR-01 | Player can draw a route between two nodes by clicking/dragging across terrain cells; the route is stored as a RouteSegment. | §4.1, §2.1 |
| ROUTE-02 | Route upkeep calculation | Planned | P0 | ROUTE-01 | route_upkeep = length * base_route_cost * terrain_cost_multiplier, recalculated whenever the route or terrain changes. | §4.1 |
| ROUTE-03 | Route freshness loss calculation | Planned | P0 | ROUTE-01 | freshness_loss = length * food_decay_rate * terrain_decay_multiplier, applied per food type traveling the route. | §4.1 |
| ROUTE-04 | Route capacity & levels | Planned | P1 | ROUTE-01 | Dirt/Paved/Main route levels expose distinct capacity (100/250/500 food/day) and upkeep multiplier (1.0x/1.6x/2.5x); exceeding capacity is flagged. | §4.1 |
| ROUTE-05 | Route reroute/upgrade/remove | Planned | P1 | ROUTE-01, ROUTE-04 | Player can reroute, upgrade to a higher route level, or remove an existing route segment. | §2.1, §3.4 |
| ROUTE-06 | Route drawing preview UI | Planned | P1 | ROUTE-01, ROUTE-02, ROUTE-03 | While drawing, UI shows live length, upkeep, and expected freshness per food type, with a warning below minimum freshness. | §10.2 |
| FRESH-01 | Freshness value tracking | Planned | P0 | CORE-03 | Every FoodFlow carries a current_freshness value from 0-100% that decreases as it travels. | §4.2 |
| FRESH-02 | Freshness-to-reward mapping | Planned | P0 | FRESH-01 | Delivered freshness maps to payment tier: 90-100% bonus, 60-89% normal, 40-59% reduced, 1-39% possible rejection, 0% spoiled. | §4.2 |
| FRESH-03 | Freshness estimate tooltip | Planned | P1 | FRESH-01, ROUTE-06 | Hovering a route shows expected freshness at destination, route upkeep, storage protection, and predicted settlement result. | §4.2 |
| STOR-01 | Normal Storage building | Planned | P0 | ROUTE-01 | Placeable Normal Storage: cost 80, upkeep 10/day, capacity 150, protection distance 4 tiles, 0.70x loss multiplier while protected. | §4.3.1 |
| STOR-02 | Cool Storage building | Planned | P0 | ROUTE-01 | Placeable Cool Storage: cost 180, upkeep 35/day, capacity 100, protection distance 8 tiles, 0.35x loss multiplier while protected. | §4.3.2 |
| STOR-03 | Freeze Storage building | Planned | P0 | ROUTE-01 | Placeable Freeze Storage: cost 400, upkeep 80/day, capacity 70, protection distance 14 tiles, 0.10x loss multiplier while protected. | §4.3.3 |
| STOR-04 | Storage preservation behavior | Planned | P0 | STOR-01, STOR-02, STOR-03, FRESH-01 | Freshness loss pauses inside storage; food leaves at the same freshness it entered with (never restored), then gets reduced decay for its protection distance. | §4.3.4 |
| STOR-05 | Freeze-sensitive food penalties | Planned | P1 | STOR-03, FOOD-01 | Freezing applies the food-specific rule: seafood/meat good, ice cream required, bread/milk minor penalty, fresh vegetables texture penalty, salad cannot freeze. | §4.3.3 |
| STOR-06 | Storage/food incompatibility handling | Planned | P1 | STOR-04, FOOD-01 | Routing an incompatible food through a storage type applies its penalty or blocks the route, per compatible_food_categories. | §4.3.4 |
| STOR-07 | Storage placement preview UI | Planned | P1 | STOR-01, STOR-02, STOR-03 | Placing storage shows per-food expected freshness gain, daily upkeep, and estimated net value. | §10.3 |
| HUB-01 | Small Hub building | Planned | P0 | CORE-05 | Placeable Small Hub: cost 150, upkeep 25/day, 4 links, 15% route discount, 250 food/day flow capacity. Sample data instance already exists at `data/nodes/hub_small_1.tres`. | §4.4 |
| HUB-02 | Regional Hub building | Planned | P1 | HUB-01 | Placeable Regional Hub: cost 350, upkeep 60/day, 8 links, 25% route discount, 600 food/day flow capacity. | §4.4 |
| HUB-03 | Central Hub building | Planned | P2 | HUB-01 | Placeable Central Hub: cost 800, upkeep 140/day, 14 links, 35% route discount, 1,400 food/day flow capacity. | §4.4 |
| HUB-04 | Hub route-discount calculation | Planned | P0 | HUB-01, ROUTE-02 | hub_adjusted_route_upkeep = connected_route_upkeep * (1 - hub_discount); net_savings = route_discount_savings - hub_daily_upkeep. | §4.4 |
| HUB-05 | Hub savings preview UI | Planned | P1 | HUB-04 | Placing a hub shows connected route count, route savings/day, hub upkeep/day, net savings/day, and flow capacity. | §10.4 |
| HUB-06 | Combined cold-hub buildings | Backlog | P3 | HUB-01, STOR-02, STOR-03 | Cool Hub, Freeze Hub, and Regional Cold Distribution Center combine storage preservation and hub discount as later-game upgrades, not starting buildings. | §4.5 |
| FOOD-01 | Food type data & MVP food set | Planned | P0 | CORE-04 | Grain, Bread, Vegetables, Milk, and Seafood each have food_id, base_value, base_decay_per_tile, preferred_storage, allowed_storage, storage_penalty_rules, minimum_accepted_freshness. | §4.6 |
| FOOD-02 | Food source buildings | Planned | P0 | TERR-02 | Farm, Bakery, Dairy, Harbor, and Freezer Plant sources each produce their food type with a daily supply amount; food starts at 100% freshness unless modified. | §4.7 |
| FOOD-03 | Source upgrade levels | Planned | P2 | FOOD-02 | Upgrading a source's level increases its daily supply. | §4.7 |
| SETT-01 | Settlement types | Planned | P0 | TERR-02 | Village, Town, City, Mountain Village, and Coastal Town each have distinct demand size, freshness strictness, and profit tier. | §4.8 |
| SETT-02 | Settlement demand data | Planned | P0 | CORE-06 | Each settlement exposes requested_foods, demand_per_day, minimum_freshness, bonus_freshness, overdelivery_tolerance, special_trait. | §4.8 |
| SETT-03 | Settlement satisfaction scoring | Planned | P1 | SETT-02, FRESH-02 | satisfaction = demand_fulfillment_score + freshness_score - spoilage_penalty - underdelivery_penalty - overdelivery_penalty. | §4.8 |
| LOOP-01 | Planning phase overview panel | Planned | P0 | ROUTE-01, STOR-01, HUB-01, SETT-02 | Player can review supply, demand, expected freshness, route/storage upkeep, and hub savings before ending the day. | §3.1 |
| LOOP-02 | Daily delivery simulation | Planned | P0 | ROUTE-03, STOR-04, HUB-04, SETT-02 | Running a day executes §17's order: demand -> supply -> flow assignment -> capacity limits -> freshness loss -> storage effects -> hub discounts -> delivery -> income/upkeep/waste/satisfaction. | §17, §3.2 |
| LOOP-03 | Delivery animation | Planned | P2 | LOOP-02 | Food packets visibly move along routes with freshness icons updating during the delivery phase. | §3.2 |
| LOOP-04 | Daily report screen | Planned | P0 | LOOP-02 | End-of-day report shows food delivered, average freshness, spoiled %, route/storage upkeep, hub savings, settlement happiness, profit, and network efficiency grade. | §3.3 |
| LOOP-05 | Upgrade phase | Planned | P1 | LOOP-04, ECON-02 | Player can spend profit/reputation to unlock new sources, settlements, storage/hub upgrades, new regions, or route improvements. | §3.4 |
| LOOP-06 | MVP win condition check | Planned | P0 | LOOP-04, SETT-03 | Region clears when average settlement happiness >= 80%, average freshness >= 70%, profit positive for 3 consecutive days, and waste < 20%. | §12 |
| ECON-01 | Delivery income calculation | Planned | P0 | FRESH-02, SETT-01 | income = delivered_amount * food_base_value * freshness_multiplier * settlement_price_modifier, using the freshness multiplier table (1.25x/1.00x/0.60x/0.25x/0x). | §9 |
| ECON-02 | Daily profit calculation | Planned | P0 | ECON-01, ROUTE-02, STOR-01, HUB-01 | profit = food_income - route_upkeep - storage_upkeep - hub_upkeep - spoilage_cost, shown alongside settlement happiness and network efficiency (not as the sole score). | §9 |
| FEED-01 | Hub savings report breakdown | Planned | P1 | HUB-04, LOOP-04 | Report lists each hub's savings individually and a total hub savings figure. | §7.3 |
| FEED-02 | Storage value report breakdown | Planned | P1 | STOR-04, LOOP-04 | Report lists food preserved/spoilage prevented per storage building, including storage cost tradeoffs. | §7.4 |
| FEED-03 | Network efficiency grade | Planned | P1 | ECON-02, SETT-03 | Overall S/A/B/C/D grade computed from average freshness, waste, route upkeep, storage upkeep, hub savings, and settlement satisfaction. | §7.5 |
| UI-01 | Map view overlays | Planned | P0 | TERR-01, ROUTE-01 | Main map shows sources, settlements, routes, storage, hubs, food movement, congestion/capacity warnings, and freshness warnings simultaneously. | §10.1 |
| UI-02 | Problem indicator icons | Planned | P1 | UI-01 | Clock/leaf/snowflake/box/network-node/coin/trash icons appear on the map for their respective problem states. | §10.5 |
| PROG-01 | Chapter 1: Fresh Beginnings | Planned | P0 | ROUTE-02, FOOD-01, SETT-01 | Tutorial teaches basic routes, Grain/Bread, Villages, and route upkeep. | §6 |
| PROG-02 | Chapter 2: Freshness Matters | Planned | P1 | PROG-01, FRESH-01, STOR-01 | Introduces Vegetables, freshness decay, and Normal Storage. | §6 |
| PROG-03 | Chapter 3: Cool Chain | Planned | P1 | PROG-02, STOR-02 | Introduces Milk, Cool Storage, Towns, and higher freshness expectations. | §6 |
| PROG-04 | Chapter 4: Regional Networks | Planned | P1 | PROG-03, HUB-01, FEED-01 | Introduces hubs, branching networks, and the hub savings report. | §6 |
| PROG-05 | Chapter 5: Long Distance | Planned | P2 | PROG-04, STOR-03, FOOD-02 | Introduces Seafood, Freeze Storage, distant settlements, and higher spoilage risk. | §6 |
| PROG-06 | Chapter 6: City Supply | Planned | P2 | PROG-05, ROUTE-04, HUB-02 | Introduces Cities, higher route capacity needs, and hub/route upgrades. | §6 |
| EVT-01 | Festival Day event | Backlog | P3 | LOOP-02 | A settlement temporarily requests 3x bread and vegetables for one day, forecast in advance. | §14 |
| EVT-02 | Heat Wave event | Backlog | P3 | FRESH-01, STOR-02 | Freshness decays faster unless food passes through Cool Storage, forecast in advance. | §14 |
| EVT-03 | Snow Week event | Backlog | P3 | TERR-04 | Mountain routes cost more and fresh food decays faster, forecast in advance. | §14 |
| EVT-04 | Harbor Boom event | Backlog | P3 | FOOD-02 | Seafood supply increases but must be met quickly, forecast in advance. | §14 |
| EVT-05 | School Lunch Contract event | Backlog | P3 | LOOP-02 | A town requires bread and milk before noon for 5 consecutive days, forecast in advance. | §14 |

## Explicitly out of scope (§13)

Vehicle types, manual cooking, staff hiring, complex traffic AI, fuel systems, real-time driver scheduling, large city simulation, multiplayer. Not tracked as rows above — revisit only if SPEC.md changes.
