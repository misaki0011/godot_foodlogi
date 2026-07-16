# Fresh Routes — Features

Extracted from `SPEC.md`. Status reflects actual implementation state, not spec intent — update both files together when scope changes.

Status legend: **Done** (built and verified) · **In Progress** · **Planned** (MVP scope, not started) · **Backlog** (explicitly post-MVP per §13/§14).

The Godot build is a 3D-isometric port of `fresh-routes-mvp.html`, the reference prototype. Where the HTML differs from SPEC.md's exact wording, the port follows the HTML (see the note after the table).

| ID | Feature | Status | Priority | Depends on | Acceptance criteria | Spec |
| --- | --- | --- | --- | --- | --- | --- |
| CORE-01 | Node data model | Done | P0 | — | NodeData resource stores node_id, node_type (source/settlement), grid_position, plus source `produces` or settlement `demand`/`kind`/`min_freshness`/`bonus_freshness`. Storage/hub are grid-tile state (GameState.grid), not placed nodes. | §16 |
| CORE-07 | Region map data (single source of truth) | Done | P0 | CORE-01 | MapData resource stores grid_size (21x14), river_col (10), and node_placements; terrain renderer and node spawner both read the same instance. | §16, §12 |
| TERR-01 | Terrain rendering | Done | P0 | CORE-07 | Only two terrain kinds exist, matching the HTML MVP: open Plains and a single River column. Rendered via GridMap with Python-generated (vertex-colored, self-contained) block meshes. Forest/Mountain/Snow are full-game-only (§8) and not in MVP scope. | §12 |
| TERR-02 | MVP region layout | Done | P0 | TERR-01 | 21x14 grid, 5 food sources (Farm/Garden/Bakery/Dairy/Harbor, one food each), 5 settlements (Village A/B/C, Town D, City E), river at column 10, positions/supply/demand matching fresh-routes-mvp.html exactly. | §12, §11 |
| TERR-03 | Node markers on terrain | Done | P0 | TERR-01, CORE-01 | Each source/settlement spawns a type-tinted 3D marker positioned exactly on its grid cell. | §16 |
| TERR-04 | Terrain cost/decay modifiers | Backlog | P3 | TERR-01 | Per-terrain cost/decay multipliers (Forest/Mountain/Snow) are a full-game feature (§8), not in the HTML MVP or this port. Only the river bridge surcharge applies. | §8 |
| TERR-05 | River bridge requirement | Done | P1 | TERR-01 | Drawing a route tile onto the river column adds a flat §40 bridge surcharge to that tile's build cost automatically. | §12 |
| ROUTE-01 | Route drawing input | Done | P0 | TERR-01 | Each click places exactly one Dirt route tile adjacent to a node or existing built tile (no drag-path drawing), matching the HTML's single-tile-per-click model. | §4.1, §2.1 |
| ROUTE-02 | Route upkeep calculation | Done | P0 | ROUTE-01 | Per-tile upkeep = base upkeep (2) × route-level multiplier (1.0/1.6/2.5 for Dirt/Paved/Main), reduced by an adjacent hub's discount. No terrain upkeep multiplier in MVP scope (see TERR-04). | §4.1 |
| ROUTE-03 | Route freshness loss calculation | Done | P0 | ROUTE-01 | Each tile crossed reduces freshness by the food's per-tile decay rate, modified by any active storage protection. | §4.1 |
| ROUTE-04 | Route capacity & levels | Done | P1 | ROUTE-01 | Dirt/Paved/Main route levels expose 60/160/400 food/day capacity and 1.0x/1.6x/2.5x upkeep multiplier, matching SPEC v0.3 §4.1's tightened values. | §4.1 |
| ROUTE-05 | Route upgrade/bulldoze | Done | P1 | ROUTE-01, ROUTE-04 | A route tile can be upgraded Dirt→Paved→Main for a flat cost; bulldozing any built tile removes it with **no refund**, matching the HTML (this is a deviation from the old 50%-refund behavior). | §2.1, §3.4 |
| FRESH-01 | Freshness value tracking | Done | P0 | — | Every simulated delivery flow tracks freshness from 0-100% as it travels the path. | §4.2 |
| FRESH-02 | Freshness-to-reward mapping | Done | P0 | FRESH-01 | Delivered freshness maps to payment tier: 90-100% bonus (1.25x), 60-89% normal (1.0x), 40-59% reduced (0.6x), 1-39% heavily reduced (0.25x) and rejected below the settlement's minimum, 0% spoiled. | §4.2 |
| FRESH-03 | Freshness estimate tooltip | Planned | P2 | FRESH-01 | §4.2's live "expected freshness at destination" while drawing a route is not implemented; the hover tooltip shows route capacity/upkeep instead. Superseded in practice by the post-simulation hub/settlement hover popups (HUB-08, SETT-04). | §4.2 |
| STOR-01 | Normal Storage building | Done | P0 | ROUTE-01 | Buildable on an existing route tile: cost 80, upkeep 10/day, capacity 150, protection distance 4 tiles, 0.70x loss multiplier while protected. | §4.3.1 |
| STOR-02 | Cool Storage building | Done | P0 | ROUTE-01 | Cost 180, upkeep 35/day, capacity 100, protection distance 8 tiles, 0.35x loss multiplier while protected. | §4.3.2 |
| STOR-03 | Freeze Storage building | Done | P0 | ROUTE-01 | Cost 400, upkeep 80/day, capacity 70, protection distance 14 tiles, 0.10x loss multiplier while protected. | §4.3.3 |
| STOR-04 | Storage preservation behavior | Done | P0 | STOR-01, STOR-02, STOR-03, FRESH-01 | Storage never restores freshness; food leaves at the freshness it entered with, then decays at the reduced rate for the protection distance. | §4.3.4 |
| STOR-05 | Freeze-sensitive food penalties | Done | P1 | STOR-03, FOOD-01 | Freeze Storage applies a flat quality penalty per food if used anywhere on the route: Bread -4, Vegetables -8, Milk -10, Grain/Seafood 0. | §4.3.3 |
| STOR-06 | Storage/food compatibility | Backlog | P3 | STOR-04 | The HTML MVP has no storage/food allow-list — any food may pass through any storage type, with only the freeze penalty (STOR-05) differentiating outcomes. Category-based restriction is not in MVP scope. | §4.3.4 |
| STOR-07 | Storage placement preview UI | Planned | P1 | STOR-01, STOR-02, STOR-03 | §10.3's dedicated placement preview (per-food freshness gain, net value) is not implemented; the hover tooltip after placement shows upkeep/protection instead. | §10.3 |
| HUB-01 | Small Hub auto-formation | Done | P0 | CORE-01 | Any route tile reaching 3+ connections (adjacent routes/storage/hubs/sources/settlements) auto-builds a Small Hub (cost 150) in place, deducted from the treasury automatically. The player never places a hub directly. | §4.4 |
| HUB-02 | Regional Hub upgrade | Done | P1 | HUB-01 | An existing Small Hub can be clicked (with the "Upgrade to Regional Hub" tool) to upgrade for a flat §200, matching the 350-150 cost difference. | §4.4 |
| HUB-03 | Central Hub | Backlog | P3 | HUB-01 | Out of MVP scope per §4.4; `GameEnums.HubType` only defines SMALL/REGIONAL. | §4.4 |
| HUB-04 | Hub route-discount calculation | Done | P0 | HUB-01, ROUTE-02 | Any route tile directly adjacent to a hub gets its upkeep reduced by the hub's discount (15% Small / 25% Regional). | §4.4 |
| HUB-05 | Hub savings preview UI | Planned | P2 | HUB-04 | Since hubs auto-form rather than being manually placed, there is no pre-build savings preview; discount/upkeep are visible via the hub hover tooltip after formation. | §10.4 |
| HUB-06 | Hub cap per connected network | Done | P0 | HUB-01 | Each connected network (BFS over built tiles + adjacent nodes) can auto-form at most 2 hubs. A further 3-way junction stays a plain, capacity-limited route tile marked `hub_capped`, and no cost is charged for it. | §4.4 |
| HUB-07 | Hub last-delivery hover split | Done | P1 | HUB-01, LOOP-02 | Hovering a hub shows upkeep, discount, and the last simulated day's delivered amount grouped by source, with percentage split; shows a placeholder message before the first simulated day. | §4.4, §10.4 |
| HUB-08 | Combined cold-hub buildings | Backlog | P3 | HUB-01, STOR-02, STOR-03 | Cool Hub, Freeze Hub, Regional Cold Distribution Center are later-game upgrades, not MVP buildings. | §4.5 |
| FOOD-01 | Food type data & MVP food set | Done | P0 | — | Grain, Bread, Vegetables, Milk, Seafood each have base value, per-tile decay, and freeze penalty matching fresh-routes-mvp.html exactly. | §4.6 |
| FOOD-02 | Food source buildings | Done | P0 | TERR-02 | Farm (grain 80/day), Garden (vegetables 90/day), Bakery (bread 80/day), Dairy (milk 75/day), Harbor (seafood 55/day) — one food per source, 100% starting freshness. | §4.7 |
| FOOD-03 | Source upgrade levels | Backlog | P3 | FOOD-02 | Not in MVP scope. | §4.7 |
| SETT-01 | Settlement types | Done | P0 | TERR-02 | Village (Villages A/B/C), Town (Town D), City (City E, the late-game objective with the highest demand and strictest 55% minimum freshness). | §4.8, §12 |
| SETT-02 | Settlement demand data | Done | P0 | CORE-01 | Each settlement's demand per food wobbles ±15-25% per simulated day (`0.85 + rand()*0.4`, matching the HTML exactly) around its base amount. | §4.8, §0.4 |
| SETT-03 | Settlement satisfaction scoring | Done | P1 | SETT-02, FRESH-02 | Per-settlement satisfaction = 60%×fulfillment + 40%×(freshness / bonus_freshness) − 30%×waste rate, clamped 0-100. | §4.8 |
| SETT-04 | Settlement delivery popup | Done | P0 | SETT-02, LOOP-02 | Clicking a settlement (any tool) shows a ✓/◐/✗ checklist per requested food with delivered/requested amounts, average freshness, and rejected-amount reasons, pulled from the last simulated day. | §4.8, §10.6 |
| LOOP-01 | Planning-phase overview | Done | P0 | ROUTE-01, STOR-01, HUB-01, SETT-02 | Treasury, day counter, and the Efficiency Chase panel (best grade, best score, rolling 7-day average) are always visible while planning. | §3.1 |
| LOOP-02 | Daily delivery simulation | Done | P0 | ROUTE-03, STOR-04, HUB-04, SETT-02 | Running a day executes demand generation/wobble, demand-pull source assignment (best predicted freshness first via Dijkstra), route/storage/hub capacity limits, freshness, storage preservation, hub discounts, income/spoilage, and satisfaction — see §17. | §17, §3.2 |
| LOOP-03 | Delivery animation | Planned | P2 | LOOP-02 | Food packets visibly moving along routes during simulation is not implemented (matches the HTML, which also only shows a static last-run summary via hover). | §3.2 |
| LOOP-04 | Daily report screen | Done | P0 | LOOP-02 | End-of-day report shows income, route/storage/hub upkeep, spoilage, profit, average freshness, waste %, capacity-blocked warning, settlement happiness, per-settlement breakdown, and the efficiency grade/score. | §3.3 |
| LOOP-05 | Demand-pull food assignment | Done | P0 | LOOP-02 | Only the amount a settlement actually needs is pulled from a source; unassigned production stays at the source and consumes no route/hub capacity. | §4.7, §17 |
| LOOP-06 | Endless efficiency-score chase | Done | P0 | LOOP-04, SETT-03 | Replaces the old one-time win condition (SPEC v0.2 §0.5): each day produces a 0-100 score and an S/A/B/C/D grade; the player tracks today's grade, the best-ever grade/score, and a rolling 7-day average score. There is no finish line. | §12, §0.5 |
| ECON-01 | Delivery income calculation | Done | P0 | FRESH-02, SETT-01 | Income = delivered amount × food base value × freshness multiplier. | §9 |
| ECON-02 | Daily profit calculation | Done | P0 | ECON-01, ROUTE-02, STOR-01, HUB-01 | Profit subtracts route, storage, hub, and spoilage costs from income and updates the treasury. | §9 |
| FEED-01 | Hub savings report breakdown | Planned | P2 | HUB-04, LOOP-04 | The daily report shows aggregate hub upkeep but not a per-hub savings line item. | §7.3 |
| FEED-02 | Storage value report breakdown | Planned | P2 | STOR-04, LOOP-04 | The daily report shows aggregate storage upkeep but not per-storage food-preserved figures. | §7.4 |
| FEED-03 | Network efficiency grade | Done | P1 | ECON-02, SETT-03 | `score = freshness×0.35 + happiness×0.35 + (100-waste)×0.15 + clamp(profit/10,0,100)×0.15`; S ≥88, A ≥75, B ≥60, C ≥40, else D. | §7.5 |
| UI-01 | Map view overlays | Done | P0 | TERR-01, ROUTE-01 | Sources, settlements, routes (tinted by level), storage, hubs, congestion markers, hub/settlement hover info, and a per-settlement speech-bubble icon (food color + shortfall number) for any food still short of demand on the last simulated day are all visible together on the map. Animated food movement is not (see LOOP-03). | §10.1 |
| UI-02 | Congestion markers | Done | P1 | UI-01 | Orange marker for tiles that ran 90-99% of capacity on the last simulated day; red marker for tiles that hit capacity and capped deliveries. The full-game aspirational icon set (clock/leaf/snowflake/box/network-node/coin/trash) is out of MVP scope. | §10.5 |
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

## Known deviation from SPEC.md v0.3 text

SPEC.md v0.3 §0/§4.1/§4.4 describes **atomic** hub-forming route placement: if a new route tile would require a Small Hub the player can't afford, or the network is already at its hub cap, the whole placement (route + hub) should be rejected with no map change and no charge. `fresh-routes-mvp.html` — the reference this port follows — actually implements the earlier v0.2 behavior instead: the route tile is placed and charged immediately, and a separate `checkAutoHubs` pass afterward either auto-builds the hub, marks the tile `needsHub` (funds too low), or marks it `hub_capped` (network at cap) as a persistent marker. This port (HUB-01/HUB-06) matches the HTML's actual behavior, not the newer spec text. Worth reconciling SPEC.md and fresh-routes-mvp.html if the atomic-rejection rule is still wanted.

## Explicitly out of scope (§13)

Vehicle types, manual cooking, staff hiring, complex traffic AI, fuel systems, real-time driver scheduling, large city simulation, multiplayer. Not tracked as rows above — revisit only if SPEC.md changes.
