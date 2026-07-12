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
| TERR-02 | MVP region layout | Done | P0 | TERR-01 | Map contains 4 food sources, 5 settlements, 1 river obstacle, and 1 late-objective city/town, matching the finalized §12 MVP. | §12, §11 |
| TERR-03 | Node markers on terrain | Done | P0 | TERR-01, CORE-01 | Each node placement spawns a type-tinted marker (source/settlement/storage/hub) positioned exactly on its grid cell. | §16 |
| TERR-04 | Terrain cost/decay modifiers | Done | P1 | TERR-01, ROUTE-02 | Each terrain type applies its cost multiplier and freshness decay multiplier to any route segment crossing it (Plains normal, Forest low-cost/more decay, Mountain high-cost/more decay, River bridge-required, Snow medium-high cost/more decay for fresh foods). | §8 |
| TERR-05 | River bridge requirement | Done | P2 | TERR-04 | Drawing across a River cell automatically purchases a bridge; unaffordable crossings are rejected. | §8 |
| ROUTE-01 | Route drawing input | Done | P0 | TERR-01 | Player can draw a cardinal tile route between any two nodes with mouse or touch; the tile path is stored as a RouteSegment. | §4.1, §2.1 |
| ROUTE-02 | Route upkeep calculation | Done | P0 | ROUTE-01 | route_upkeep = length * base_route_cost * terrain_cost_multiplier, recalculated whenever the route or level changes. | §4.1 |
| ROUTE-03 | Route freshness loss calculation | Done | P0 | ROUTE-01 | freshness_loss = length * food_decay_rate * terrain_decay_multiplier, applied per food type traveling the route. | §4.1 |
| ROUTE-04 | Route capacity & levels | Done | P1 | ROUTE-01 | Dirt/Paved/Main route levels expose distinct capacity (100/250/500 food/day) and upkeep multiplier (1.0x/1.6x/2.5x). | §4.1 |
| ROUTE-05 | Route reroute/upgrade/remove | Done | P1 | ROUTE-01, ROUTE-04 | Player can replace routes by removing/refunding them and can upgrade them to higher levels. | §2.1, §3.4 |
| ROUTE-06 | Route drawing preview UI | Done | P1 | ROUTE-01, ROUTE-02, ROUTE-03 | While drawing, UI shows live length, construction cost, upkeep, and expected freshness per food type. | §10.2 |
| FRESH-01 | Freshness value tracking | Done | P0 | CORE-03 | Every simulated food flow tracks freshness from 0-100% as it travels. | §4.2 |
| FRESH-02 | Freshness-to-reward mapping | Done | P0 | FRESH-01 | Delivered freshness maps to payment tier: 90-100% bonus, 60-89% normal, 40-59% reduced, 1-39% possible rejection, 0% spoiled. | §4.2 |
| FRESH-03 | Freshness estimate tooltip | Planned | P1 | FRESH-01, ROUTE-06 | Hovering a route shows expected freshness at destination, route upkeep, storage protection, and predicted settlement result. | §4.2 |
| STOR-01 | Normal Storage building | Done | P0 | ROUTE-01 | Placeable Normal Storage: cost 80, upkeep 10/day, capacity 150, protection distance 4 tiles, 0.70x loss multiplier while protected. | §4.3.1 |
| STOR-02 | Cool Storage building | Done | P0 | ROUTE-01 | Placeable Cool Storage: cost 180, upkeep 35/day, capacity 100, protection distance 8 tiles, 0.35x loss multiplier while protected. | §4.3.2 |
| STOR-03 | Freeze Storage building | Done | P0 | ROUTE-01 | Placeable Freeze Storage: cost 400, upkeep 80/day, capacity 70, protection distance 14 tiles, 0.10x loss multiplier while protected. | §4.3.3 |
| STOR-04 | Storage preservation behavior | Done | P0 | STOR-01, STOR-02, STOR-03, FRESH-01 | Storage never restores freshness and applies reduced decay for its protection distance after food leaves. | §4.3.4 |
| STOR-05 | Freeze-sensitive food penalties | Done | P1 | STOR-03, FOOD-01 | Bread, milk, and vegetables receive their finalized MVP quality penalties when frozen; seafood and grain do not. | §4.3.3 |
| STOR-06 | Storage/food incompatibility handling | Done | P1 | STOR-04, FOOD-01 | Storage compatibility and food-specific penalties are data-driven and applied during routing. | §4.3.4 |
| STOR-07 | Storage placement preview UI | Planned | P1 | STOR-01, STOR-02, STOR-03 | Placing storage shows per-food expected freshness gain, daily upkeep, and estimated net value. | §10.3 |
| HUB-01 | Small Hub building | Done | P0 | CORE-05 | Placeable Small Hub: cost 150, upkeep 25/day, 4 links, 15% route discount, 250 food/day flow capacity. | §4.4 |
| HUB-02 | Regional Hub building | Done | P1 | HUB-01 | Small Hubs can upgrade to Regional: total cost 350, upkeep 60/day, 8 links, 25% route discount, 600 food/day flow capacity. | §4.4 |
| HUB-03 | Central Hub building | Planned | P2 | HUB-01 | Placeable Central Hub: cost 800, upkeep 140/day, 14 links, 35% route discount, 1,400 food/day flow capacity. | §4.4 |
| HUB-04 | Hub route-discount calculation | Done | P0 | HUB-01, ROUTE-02 | hub_adjusted_route_upkeep = connected_route_upkeep * (1 - hub_discount); savings and upkeep are shown separately. | §4.4 |
| HUB-05 | Hub savings preview UI | Planned | P1 | HUB-04 | Placing a hub shows connected route count, route savings/day, hub upkeep/day, net savings/day, and flow capacity. | §10.4 |
| HUB-06 | Combined cold-hub buildings | Backlog | P3 | HUB-01, STOR-02, STOR-03 | Cool Hub, Freeze Hub, and Regional Cold Distribution Center combine storage preservation and hub discount as later-game upgrades, not starting buildings. | §4.5 |
| FOOD-01 | Food type data & MVP food set | Done | P0 | CORE-04 | Grain, Bread, Vegetables, Milk, and Seafood have value, decay, category, storage preference, freeze penalty, and minimum freshness data. | §4.6 |
| FOOD-02 | Food source buildings | Done | P0 | TERR-02 | Farm supplies Grain/Vegetables, Bakery Bread, Dairy Milk, and Harbor Seafood at 100% starting freshness. | §4.7 |
| FOOD-03 | Source upgrade levels | Planned | P2 | FOOD-02 | Upgrading a source's level increases its daily supply. | §4.7 |
| SETT-01 | Settlement types | Done | P0 | TERR-02 | Village, Town, City, Mountain Village, and Coastal Town have distinct demand, freshness, and price profiles. | §4.8 |
| SETT-02 | Settlement demand data | Done | P0 | CORE-06 | Each settlement exposes requested foods, amount, minimum freshness, bonus freshness, and price modifier. | §4.8 |
| SETT-03 | Settlement satisfaction scoring | Done | P1 | SETT-02, FRESH-02 | Satisfaction combines weighted demand fulfillment and freshness quality. | §4.8 |
| LOOP-01 | Planning phase overview panel | Done | P0 | ROUTE-01, STOR-01, HUB-01, SETT-02 | Player can review supply, demand, route/storage/hub upkeep, hub savings, and route freshness previews before ending the day. | §3.1 |
| LOOP-02 | Daily delivery simulation | Done | P0 | ROUTE-03, STOR-04, HUB-04, SETT-02 | Running a day executes deterministic demand, supply, path, capacity, freshness, storage, hub, delivery, economy, and satisfaction calculations. | §17, §3.2 |
| LOOP-03 | Delivery animation | Planned | P2 | LOOP-02 | Food packets visibly move along routes with freshness icons updating during the delivery phase. | §3.2 |
| LOOP-04 | Daily report screen | Done | P0 | LOOP-02 | End-of-day report shows deliveries, freshness, waste, all upkeep, hub savings, happiness, profit, grade, and win progress. | §3.3 |
| LOOP-05 | Upgrade phase | Done | P1 | LOOP-04, ECON-02 | Profit funds Dirt/Paved/Main route upgrades and Small/Regional Hub upgrades during planning. | §3.4 |
| LOOP-06 | MVP win condition check | Done | P0 | LOOP-04, SETT-03 | Region clears when average settlement happiness >= 80%, average freshness >= 70%, profit positive for 3 consecutive days, and waste < 20%. | §12 |
| ECON-01 | Delivery income calculation | Done | P0 | FRESH-02, SETT-01 | Income uses delivered amount, food value, freshness multiplier, and settlement price modifier. | §9 |
| ECON-02 | Daily profit calculation | Done | P0 | ECON-01, ROUTE-02, STOR-01, HUB-01 | Profit subtracts route, storage, hub, and spoilage costs and updates available funds. | §9 |
| FEED-01 | Hub savings report breakdown | Planned | P1 | HUB-04, LOOP-04 | Report lists each hub's savings individually and a total hub savings figure. | §7.3 |
| FEED-02 | Storage value report breakdown | Planned | P1 | STOR-04, LOOP-04 | Report lists food preserved/spoilage prevented per storage building, including storage cost tradeoffs. | §7.4 |
| FEED-03 | Network efficiency grade | Done | P1 | ECON-02, SETT-03 | Overall S/A/B/C/D grade combines freshness, waste, settlement satisfaction, and profitability. | §7.5 |
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
