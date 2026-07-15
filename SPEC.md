# Food Logistics Puzzle Game - Design Spec

**Version:** 0.3  
**Working title:** Fresh Routes  
**Genre:** Cozy logistics / routing puzzle / light management  
**Target platform:** PC / Steam (MVP prototype: browser)  
**Core player actions:** Draw routes, place storage, let hubs form automatically  
**Explicitly out of scope:** Vehicle management, cooking simulation, staff management, complex traffic simulation

---

## 0. Changelog

### v0.2 → v0.3 — Routing and inspection playtest

The next playtest clarified how junction construction, pathfinding, and delivery feedback should work. These rules supersede conflicting v0.2 text elsewhere in the document:

1. **Route placement is atomic when it creates a hub.** If a newly placed route would create a 3+ connection junction, the required Small Hub must form in the same action. If the player cannot afford the route plus hub, or the connected network is already at its 2-hub cap, the route placement is cancelled. No route tile is created and no money is deducted.
2. **Only settlements are delivery destinations.** Food sources produce food but never receive deliveries. A route finder may start at the selected source and end at a settlement, but it may not pass through any other source or settlement as an intermediate shortcut.
3. **Distribution remains demand-pull.** A source's full daily production does not automatically travel to its first hub. Only amounts assigned to settlement demand enter the network. Unassigned supply remains at the source and consumes no route capacity.
4. **Hub hover information shows actual last-day flow.** Each hub reports its upkeep, adjacent-route discount, and the last delivery split by source, food, and outgoing direction or route. Percentages are calculated within each source-food amount routed through that hub.
5. **Every settlement has a delivery-result popup.** Hovering a village, town, or city shows the last simulated day's requested, delivered, rejected, freshness, and supplying-source results. Clicking still opens the larger per-food checklist.
6. **Pending-hub junction tiles are removed.** Because hub-requiring placement is atomic, the game no longer leaves an unaffordable or over-cap 3-way junction as a plain route with a dashed warning. The attempted placement is rejected instead.

### v0.1 → v0.2 — MVP playtest

The MVP was built and played. A few systems changed shape once they hit an actual grid — mostly to fix the "just connect everything, done" problem that a static, unlimited network allows. These are real deviations from v0.1, not just tuning:

1. **Hubs form automatically, not by manual placement.** Any tile where a route meets 3+ connections — other routes, storage, hubs, a food source, or a settlement — auto-upgrades into a Small Hub and auto-charges its build cost. The player no longer selects a "place hub" tool. See §4.4.
2. **Hubs are capped per connected road network.** Each connected network (routes physically joined together, including through the nodes they touch) can support at most **2 hubs**. A 3rd+ qualifying junction is still buildable, but stays a plain, capacity-limited route tile — it just never gets the hub bonus. This is the change that actually created the "one connected mega-network vs. several smaller ones" decision the original spec's Pillar 2.3 wanted. See §4.4.
3. **Route capacity is the primary bottleneck, not upkeep alone.** Dirt/Paved/Main capacities were tightened (100/250/500 → 60/160/400) so that a settlement's combined demand routinely exceeds a single tile's throughput, forcing upgrades, parallel routes, or hubs rather than letting the player fully solve the map with one thin path. See §4.1.
4. **Daily demand wobbles ±15–20%.** A network that exactly cleared capacity yesterday can get squeezed today. This keeps the puzzle live day over day instead of going static once "solved." See §12.
5. **Win condition replaced with an endless efficiency-score chase.** Rather than a one-time "clear the region" checklist, the player now tracks a daily 0–100 grade score, an all-time best, and a rolling 7-day average. The goal becomes "make it cleaner," matching §18's Core Fun Test better than a binary finish line. See §12.
6. **Strict one-source-one-food rule.** Farm originally produced both grain and vegetables. It was split into Farm (grain) and a new source, Garden (vegetables), so every source maps to exactly one food. See §4.7.
7. **Congestion and junction status are persistent map markers, not just tooltips.** Tiles running at 90%+ or 100%+ of capacity show a "!" glyph after each simulated day; junctions waiting on hub funds or blocked by the network cap show a dashed marker. Hovering any of these still gives the full explanation. See §10.5.
8. **Settlements are clickable for a per-food fulfillment checklist.** Tapping a settlement shows ✓ / ◐ / ✗ per requested food, with delivered/requested amounts and average freshness, pulled from the last simulated day.
9. **Map grid enlarged to 21×14 (was 17×10)**, with 2 extra tiles of empty margin on every edge, to give the player room to build genuinely separate networks — which now matters because hub budget is per-network.

Everything else in this document (freshness bands, storage roles, food set, satisfaction scoring) held up as originally scoped and is unchanged.

---

## 1. High-Level Concept

The player builds a regional food delivery network between food sources and settlements. Food loses freshness while traveling. The player draws efficient routes, places storage buildings to preserve freshness, and uses hubs to reduce route upkeep.

The game should feel like a clean, cozy logistics puzzle rather than a transport-management simulator.

### One-sentence pitch

> Draw food routes across a cozy region, use storage to keep food fresh, and form efficient hubs to feed villages, towns, and cities.

### Core fantasy

The player is not a driver, chef, or factory worker. The player is a regional food network planner who keeps communities fed by designing smart supply routes.

---

## 2. Design Pillars

### 2.1 Simple inputs, deep outcomes

The player only needs a few actions:

1. Draw a route.
2. Place storage on an existing route.
3. Create junctions that automatically form hubs.
4. Upgrade or remove route and hub infrastructure.

Depth comes from food freshness, storage choice, route length, hub-forming junctions, terrain, and settlement demand.

### 2.2 Food freshness is the main pressure

Routes are not only about connection. They affect quality.

Long route = lower freshness.  
Poor storage = more spoilage.  
Good storage = higher value delivery.  
Bad routing = waste and unhappy settlements.

### 2.3 Hubs create elegant networks

The game should encourage players to avoid many expensive direct routes. Hubs should reward shared regional networks.

Bad but allowed:

```text
Farm -> Village A
Farm -> Village B
Farm -> Village C
Farm -> Town D
```

Better:

```text
Farm -> Hub -> Village A
            -> Village B
            -> Village C
            -> Town D
```

### 2.4 Storage preserves, but does not repair

Storage should not magically restore bad food. It preserves food quality and slows future freshness loss.

If food reaches storage at 65% freshness, it leaves storage at 65% freshness, not 100%.

### 2.5 No vehicle complexity

There are no vehicle types. The route itself represents automatic delivery capacity. Storage and hubs replace vehicle complexity.

Instead of choosing a refrigerated van, the player makes a route pass through Cool Storage.  
Instead of choosing a larger truck, the player upgrades a hub or route capacity.

---

## 3. Core Gameplay Loop

### 3.1 Planning phase

The player checks:

- Food sources and available supply.
- Settlement demand.
- Expected freshness at each destination.
- Route upkeep.
- Storage upkeep.
- Hub savings.

The player then edits the network:

- Draw new routes.
- Reroute existing routes.
- Add storage.
- Create hub-forming junctions.
- Upgrade infrastructure.

### 3.2 Delivery simulation phase

The day runs automatically. Food travels along routes, freshness changes, storage effects apply, and settlements receive deliveries.

The player should be able to watch:

- Food packets moving along routes.
- Freshness icons changing.
- Hubs combining and splitting deliveries.
- Storage buildings preserving food.
- Settlements becoming satisfied or unhappy.

### 3.3 Report phase

At the end of the day, the player receives a clear summary:

```text
Daily Report

Food delivered: 320
Average freshness: 84%
Spoiled food: 7%
Route upkeep: 1,200
Storage upkeep: 450
Hub savings: 600
Settlement happiness: A-
Profit: 3,400
Network efficiency: B+
```

The report should show why smart routing mattered.

### 3.4 Upgrade phase

The player spends profit or reputation to unlock:

- New food sources.
- New settlements.
- Storage upgrades.
- Hub upgrades.
- New regions.
- Route improvements.

---

## 4. Core Systems

---

# 4.1 Route System

Routes connect nodes on the map.

A node can be:

- Food Source
- Settlement
- Storage
- Hub
- Optional landmark or special building

### Route properties

Each route segment has:

| Property | Description |
|---|---|
| Length | Number of map tiles or path units |
| Upkeep | Daily maintenance cost |
| Freshness loss | How much food quality drops while traveling |
| Capacity | Amount of food that can pass per day |
| Terrain modifiers | Optional cost or freshness penalties |

### Basic rule

```text
Longer route = more upkeep + more freshness loss
```

### Suggested route formula

```text
route_upkeep = length * base_route_cost * terrain_cost_multiplier
freshness_loss = length * food_decay_rate * terrain_decay_multiplier
```

### Route capacity

To keep the game simple, route capacity should exist but remain readable.

Example:

| Route level | Capacity/day | Upkeep multiplier |
|---|---:|---:|
| Dirt route | 60 food | 1.0x |
| Paved route | 160 food | 1.6x |
| Main route | 400 food | 2.5x |

Capacity creates meaningful hub and route upgrade decisions without needing vehicles. In playtesting, capacity needed to be tight enough that a single settlement's combined demand could exceed one dirt tile's throughput — otherwise capacity never became a real constraint on a small map (see Changelog §0.3).

### Transactional route placement (added in v0.3)

A route-building click is evaluated before it changes the map. The game calculates the complete cost and topology result, including any Small Hub that the new tile would require.

```text
required_cost = route_tile_cost + optional_bridge_cost + optional_auto_hub_cost
```

The route is established only when all resulting rules are valid:

- The tile is empty and adjacent to the existing network or a node.
- The player can afford the complete required cost.
- If the tile creates a 3+ connection junction, a Small Hub can form immediately.
- The connected network will not exceed its 2-hub cap.

If any check fails, the action is cancelled atomically:

```text
No route tile created.
No hub created.
No treasury deducted.
```

This prevents a visually valid branch from existing when the required hub could not be created.

---

# 4.2 Food Freshness System

Every food item or food batch has a freshness value.

```text
100% = perfect
70-99% = good
40-69% = poor but sellable
1-39% = low value or rejected by strict settlements
0% = spoiled
```

### Freshness affects reward

| Delivered freshness | Result |
|---|---|
| 90-100% | Bonus payment and happiness |
| 60-89% | Normal payment |
| 40-59% | Reduced payment |
| 1-39% | Possible rejection by picky settlements |
| 0% | Spoiled and wasted |

### Freshness should be predictable

When the player hovers over a route, the UI should estimate freshness at destination.

Example tooltip:

```text
Vegetables to Hill Town
Expected freshness: 76%
Route upkeep: 120/day
Storage protection: Cool Storage, 8 tiles
Settlement result: Normal payment
```

---

# 4.3 Storage System

Storage buildings preserve food freshness. There are three storage types:

1. Normal Storage
2. Cool Storage
3. Freeze Storage

The storage types should not simply be weak, medium, and strong. Each should have a role.

---

## 4.3.1 Normal Storage

Cheap general-purpose storage.

### Best for

- Grain
- Rice
- Potatoes
- Bread
- Canned food
- Some vegetables

### Effects

- Pauses freshness loss while food is stored.
- Gives minor protection after food leaves.
- Low upkeep.
- High capacity.

### Suggested values

| Stat | Value |
|---|---:|
| Build cost | 80 |
| Daily upkeep | 10 |
| Capacity | 150 food |
| Protection distance | 4 tiles |
| Freshness loss multiplier during protection | 0.70x |

---

## 4.3.2 Cool Storage

Medium-cost storage for fresh and chilled foods.

### Best for

- Vegetables
- Fruit
- Milk
- Cheese
- Eggs
- Short-distance seafood

### Effects

- Pauses freshness loss while food is stored.
- Gives strong short-to-mid-distance protection after food leaves.
- Medium upkeep.
- Medium capacity.

### Suggested values

| Stat | Value |
|---|---:|
| Build cost | 180 |
| Daily upkeep | 35 |
| Capacity | 100 food |
| Protection distance | 8 tiles |
| Freshness loss multiplier during protection | 0.35x |

---

## 4.3.3 Freeze Storage

Expensive storage for long-distance preservation and highly perishable foods.

### Best for

- Meat
- Seafood
- Ice cream
- Frozen meals
- Emergency stock
- Long-distance supply chains

### Effects

- Pauses freshness loss while food is stored.
- Gives very strong protection after food leaves.
- High upkeep.
- Lower capacity.
- Some foods suffer a quality penalty when frozen.

### Suggested values

| Stat | Value |
|---|---:|
| Build cost | 400 |
| Daily upkeep | 80 |
| Capacity | 70 food |
| Protection distance | 14 tiles |
| Freshness loss multiplier during protection | 0.10x |

### Freeze-sensitive food rule

Some foods dislike freezing.

| Food | Freeze result |
|---|---|
| Seafood | Good |
| Meat | Good |
| Ice cream | Required |
| Bread | Minor quality penalty |
| Fresh vegetables | Texture penalty |
| Salad | Cannot freeze |
| Milk | Quality penalty |

This prevents Freeze Storage from being the best answer for everything.

---

## 4.3.4 Storage behavior rule

When food passes through storage:

1. Freshness loss pauses while inside storage.
2. Food leaves with the same freshness it entered with.
3. Food receives a temporary preservation effect.
4. If the food is incompatible with the storage type, apply a penalty or block the route.

Example:

```text
Vegetables enter Cool Storage at 78% freshness.
Vegetables leave Cool Storage at 78% freshness.
For the next 8 tiles, freshness loss is reduced to 35% of normal.
```

Important rule:

```text
Storage preserves freshness. It does not restore freshness.
```

---

# 4.4 Hub System

Hubs reduce route upkeep and make large networks efficient.

A hub is not primarily for freshness. It is for network organization, flow visibility, capacity, and cost reduction.

### Hub purpose

- Combine routes from multiple sources.
- Split source food toward multiple settlements.
- Reduce upkeep on adjacent route segments.
- Increase junction flow capacity.
- Encourage regional planning.

### Automatic hub formation

A Small Hub is required on any newly built route tile that would have 3 or more connections. Connections include adjacent routes, storage, hubs, food sources, and settlements.

The hub and route placement are one atomic construction action:

1. Preview the newly created junction.
2. Determine the connected network and current hub count.
3. Calculate route, bridge, and Small Hub construction cost.
4. Build both the route and hub only if the complete action is valid.

If the player cannot afford the complete action, the route is not placed. If the connected network is already at the hub cap, the route is not placed. There is no pending plain-route junction and no later automatic conversion.

```text
hub_adjusted_route_upkeep = adjacent_route_upkeep * (1 - hub_discount)
net_savings = route_discount_savings - hub_daily_upkeep
```

### Hub cap per connected network

Each connected road network can support at most **2 hubs**. A network includes all joined route, storage, and hub tiles. Nodes may connect tiles for delivery access, but source and settlement nodes are terminal endpoints for flow and cannot be used as transit shortcuts.

- An attempted third hub-forming junction is rejected before construction.
- The player receives a clear explanation that the network has reached its hub cap.
- No construction cost is charged for the rejected action.
- The player can reroute, keep networks separate, or remove an existing hub-bearing branch before trying again.
- Existing networks created by older versions or imported data should be validated separately; the MVP does not need migration logic.

This preserves the topology decision: keep networks physically separate to receive independent hub budgets, or merge them and accept a maximum of 2 hubs.

### Suggested hub levels

| Hub type | Build cost | Daily upkeep | Link capacity | Route discount | Flow capacity |
|---|---:|---:|---:|---:|---:|
| Small Hub | 150 | 25 | 4 links | 15% | 250 food/day |
| Regional Hub | 350 | 60 | 8 links | 25% | 600 food/day |
| Central Hub | 800 | 140 | 14 links | 35% | 1,400 food/day |

In the MVP, a hub always forms as a Small Hub. Regional Hub is reached by manually upgrading an existing Small Hub and paying the cost difference. Central Hub is out of MVP scope.

### Hub last-delivery hover view (added in v0.3)

Hovering a hub shows compact operational information based on the most recently simulated day.

```text
Small Hub
Upkeep: 25/day
Discount on adjacent routes: 15%

Last delivery
Farm: Grain 38 → North 15 (39%) · South 23 (61%)
Bakery: Bread 20 → South 20 (100%)
```

Rules:

- The source total is the amount that actually passed through this hub, not the source's full production.
- Food is demand-pulled toward settlements; unused production remains at its source.
- Each source-food line is grouped separately.
- Outgoing branches use readable directions when unambiguous: North, South, East, or West.
- When a direction is insufficient, show the next settlement or route label, such as `East → Town D`.
- Percentages use the source-food total routed through that hub as the denominator and should sum to 100%, allowing for display rounding.
- Rejected deliveries that consumed capacity may be shown with a warning marker or a separate rejected amount.
- Before the first simulation, show `No deliveries routed through this hub yet.`

### Hub placement decision

A hub should usually become worthwhile when it serves 3 or more connections or when it organizes several long routes. The player does not place it manually; the player chooses whether to create the junction that requires it.

Direct route network:

```text
Farm -> Village A
Farm -> Village B
Farm -> Village C
Farm -> Town D
```

Hub network:

```text
Farm -> Hub -> Village A
            -> Village B
            -> Village C
            -> Town D
```

The hub network should have lower upkeep when the hub is well positioned, but the 2-hub cap and atomic formation rule prevent unlimited branching inside one connected network.

---

# 4.5 Difference Between Storage and Hub

Storage and hub buildings should have clearly different purposes.

| Building | Main purpose | Secondary purpose |
|---|---|---|
| Storage | Preserve freshness | Buffer food flow |
| Hub | Reduce route upkeep | Increase route organization and capacity |

Do not merge these systems too early. Keep them separate in the MVP.

Possible future combined buildings:

- Normal Hub
- Cool Hub
- Freeze Hub
- Regional Cold Distribution Center

These should be later upgrades, not core starting buildings.

---

# 4.6 Food Types

Food types should be broad and readable. Avoid too many ingredients.

### MVP food set

| Food | Freshness decay | Best storage | Notes |
|---|---:|---|---|
| Grain | Very low | Normal | Cheap, stable, good tutorial food |
| Bread | Low-medium | Normal | Better if delivered fresh, morning demand possible |
| Vegetables | Medium | Cool | Good first freshness puzzle |
| Milk | High | Cool | Strongly encourages Cool Storage |
| Seafood | Very high | Cool / Freeze | Teaches Freeze Storage |
| Frozen Food | Medium unless frozen | Freeze | Requires Freeze Storage for long routes |

### Food data fields

Each food should have:

```text
food_id
name
category
base_value
base_decay_per_tile
preferred_storage
allowed_storage
storage_penalty_rules
minimum_accepted_freshness
supply_source_type
```

Example:

```yaml
food_id: milk
name: Milk
category: chilled
base_value: 8
base_decay_per_tile: 4
preferred_storage: cool
allowed_storage: [cool, freeze]
storage_penalty_rules:
  freeze: -10 quality
minimum_accepted_freshness: 50
```

---

# 4.7 Food Sources

Food sources produce food each day.

Examples:

| Source | Produces |
|---|---|
| Farm | Grain |
| Garden | Vegetables |
| Bakery | Bread |
| Dairy | Milk |
| Harbor | Seafood |
| Freezer Plant | Frozen food |
| Orchard | Fruit |

**One source, one food (added in v0.2).** Farm originally produced both grain and vegetables. In practice this made the source side of the network less legible — the player couldn't reason about "Farm's route" as carrying one thing. Farm was split into Farm (grain only) and a new source, Garden (vegetables only). Every source in the MVP now maps to exactly one food.

### Source properties

| Property | Description |
|---|---|
| Output type | Food produced |
| Daily supply | Amount available per day |
| Source quality | Starting freshness |
| Upgrade level | Higher level produces more food |
| Region | Location and terrain context |

Suggested rule:

```text
Food starts at 100% freshness unless the source has a special modifier.
```

### Source routing role (clarified in v0.3)

Food sources are production endpoints only. They are not delivery destinations, relay nodes, or shortcuts between two parts of a road network.

Pathfinding rules:

- A delivery path starts at exactly one selected source.
- A delivery path ends at exactly one settlement.
- Only settlements may be selected as destinations.
- The path may not enter another source.
- The path may not pass through another settlement before reaching its selected destination.
- Routes, storage, and hubs may be used as intermediate path tiles.

### Demand-pull distribution

Daily production is available at the source, but only food assigned to settlement demand enters the network.

Example:

```text
Farm production: 80 grain
Connected settlement demand assigned today: 38 grain
Grain entering the route network: 38
Unused grain remaining at Farm: 42
```

The unused 42 does not consume route or hub capacity. A hub tooltip therefore reports `Grain 38`, not the source's production limit of 80.

---

# 4.8 Settlement Demand

Settlements request food. Each settlement has demand, freshness expectations, and reward behavior.

### Settlement types

| Settlement | Demand size | Freshness strictness | Profit | Role |
|---|---:|---:|---:|---|
| Village | Low | Low-medium | Low | Good for early routes |
| Town | Medium | Medium | Medium | Good for hubs |
| City | High | Medium-high | High | Tests capacity and efficiency |
| Mountain Village | Low | High for certain foods | Medium | Tests storage placement |
| Coastal Town | Medium | High for imported foods | Medium | Can produce seafood |

### Demand fields

```text
settlement_id
name
type
requested_foods
demand_per_day
minimum_freshness
bonus_freshness
underdelivery_penalty
overdelivery_tolerance
special_trait
```

Example:

```yaml
settlement_id: hill_town
name: Hill Town
type: town
requested_foods:
  bread: 40
  vegetables: 60
  milk: 30
minimum_freshness: 45
bonus_freshness: 85
overdelivery_tolerance: 15
special_trait: prefers_fresh_vegetables
```

### Delivery-result popup (added in v0.3)

Every settlement—village, town, or city—shows a popup when hovered. It summarizes the most recently simulated day without requiring the player to open the full report.

Suggested popup:

```text
Village A — Last delivery
Grain: 18 / 20 · 91% fresh · from Farm
Bread: 14 / 22 · 76% fresh · from Bakery
Rejected: 2 bread below minimum freshness
Status: Partial
```

The hover popup should show, per requested food:

- Requested amount.
- Accepted delivered amount.
- Average delivered freshness.
- Supplying source or sources.
- Rejected amount and reason when applicable.
- A readable status such as Complete, Partial, or Missing.

Clicking the settlement opens the larger checklist with ✓ / ◐ / ✗ per food and any extra detail. Before the first simulation, show that no delivery result exists yet.

### Satisfaction scoring

Settlement satisfaction should depend on:

- Amount delivered.
- Freshness delivered.
- Food type correctness.
- Waste or overdelivery.
- Consistency over multiple days.

Suggested formula:

```text
satisfaction = demand_fulfillment_score
             + freshness_score
             - spoilage_penalty
             - underdelivery_penalty
             - overdelivery_penalty
```

---

## 5. Player Goals

### 5.1 Short-term goals

- Connect a new food source to a settlement.
- Deliver food above minimum freshness.
- Reduce route upkeep.
- Prevent spoilage.
- Make a hub profitable.
- Serve a new settlement type.

### 5.2 Mid-term goals

- Build a regional hub network.
- Add the correct storage types to long routes.
- Serve cities without overloading routes.
- Balance expensive Freeze Storage against spoilage risk.
- Raise settlement happiness.

### 5.3 Long-term goals

- Unlock new regions.
- Feed all settlements efficiently.
- Build a low-waste network.
- Reach high network efficiency grades.
- Complete special supply contracts.

---

## 6. Progression Structure

The game should introduce systems gradually.

### Chapter 1: Fresh Beginnings

Introduces:

- Basic routes
- Grain and bread
- Villages
- Route upkeep

Player learns:

```text
Connect source to settlement. Longer routes cost more.
```

### Chapter 2: Freshness Matters

Introduces:

- Vegetables
- Freshness decay
- Normal Storage

Player learns:

```text
Food quality drops during travel. Storage helps preserve it.
```

### Chapter 3: Cool Chain

Introduces:

- Milk
- Cool Storage
- Towns
- Higher freshness expectations

Player learns:

```text
Some foods need better storage.
```

### Chapter 4: Regional Networks

Introduces:

- Hubs
- Branching networks
- Hub savings report

Player learns:

```text
Hubs reduce upkeep when serving multiple destinations.
```

### Chapter 5: Long Distance

Introduces:

- Seafood
- Freeze Storage
- Distant settlements
- Higher spoilage risk

Player learns:

```text
Freeze Storage is powerful but expensive. Use it carefully.
```

### Chapter 6: City Supply

Introduces:

- Cities
- Higher route capacity needs
- Hub upgrades
- Route upgrades

Player learns:

```text
Large demand requires organized networks, not many direct routes.
```

---

## 7. Efficiency Incentives

Players should be encouraged to make efficient lines through clear feedback and rewards.

### 7.1 Upkeep pressure

Every route tile costs money per day.

Direct routes are easy but expensive.

```text
Farm -> Village A
Farm -> Village B
Farm -> Village C
```

This should usually cost more than:

```text
Farm -> Hub -> Village A
            -> Village B
            -> Village C
```

### 7.2 Freshness pressure

Long routes reduce freshness.

Storage can help, but it costs money.

This creates the core question:

```text
Should I build a shorter expensive route, or a longer cheaper route with storage?
```

### 7.3 Hub savings feedback

The daily report must show hub savings clearly.

Example:

```text
Hub Savings

North Hub saved: 180
River Hub saved: 75
Unused Hub lost: -25
Total hub savings: 230
```

### 7.4 Storage value feedback

The daily report should show freshness preserved.

Example:

```text
Storage Report

Normal Storage preserved 34 food.
Cool Storage prevented 18 milk from spoiling.
Freeze Storage saved 22 seafood, but cost 80 upkeep.
```

### 7.5 Network efficiency grade

Calculate an overall grade based on:

- Average freshness
- Food waste
- Route upkeep
- Storage upkeep
- Hub savings
- Settlement satisfaction

Example grades:

```text
S: elegant, low waste, high freshness
A: efficient and profitable
B: functional with some waste
C: expensive or inconsistent
D: poor delivery quality
```

---

## 8. Terrain and Map Rules

Terrain should support routing decisions but not dominate the game.

### MVP terrain types

| Terrain | Cost effect | Freshness effect | Design purpose |
|---|---:|---:|---|
| Plains | Normal | Normal | Default |
| Forest | Low cost, winding paths | Slightly more decay | Cheap but longer |
| Mountain | High cost | More decay | Makes direct routes expensive |
| River | Bridge required | Normal | Creates chokepoints |
| Snow | Medium-high cost | More decay for fresh foods | Supports storage puzzles |

### Terrain example

```text
Direct mountain route:
Short, expensive, higher freshness loss.

Valley route:
Longer, cheaper, lower freshness loss.

Cool Storage route:
Extra building cost, better delivered quality.
```

---

## 9. Economy

The economy should be simple and readable.

### Income

Income comes from delivered food.

```text
income = delivered_amount * food_base_value * freshness_multiplier * settlement_price_modifier
```

### Freshness multiplier

| Freshness | Multiplier |
|---|---:|
| 90-100% | 1.25x |
| 60-89% | 1.00x |
| 40-59% | 0.60x |
| 1-39% | 0.25x or rejected |
| 0% | 0x |

### Expenses

Expenses include:

- Route upkeep
- Storage upkeep
- Hub upkeep
- Spoiled food penalty
- Optional construction debt or maintenance events

### Profit

```text
profit = food_income - route_upkeep - storage_upkeep - hub_upkeep - spoilage_cost
```

Profit should not be the only score. Settlement happiness and network efficiency matter too.

---

## 10. UI Requirements

### 10.1 Map view

The main screen should show:

- Food sources
- Settlements
- Routes
- Storage buildings
- Hubs
- Food movement
- Route congestion or capacity warnings
- Freshness warnings
- Hub last-delivery hover details
- Settlement last-delivery hover popups

### 10.2 Route drawing UI

When drawing a route, show predicted values:

```text
Route length: 18
Daily upkeep: 180
Expected vegetable freshness: 64%
Expected milk freshness: 28% - warning
Recommended: Add Cool Storage
```

### 10.3 Storage placement UI

When placing storage, show which food benefits.

```text
Cool Storage Preview

Vegetables: +18 expected freshness
Milk: +34 expected freshness
Bread: +4 expected freshness
Daily upkeep: 35
Estimated net value: +62/day
```

### 10.4 Hub information UI

Because hubs form automatically, the MVP does not need a manual hub-placement panel. Before route construction, the route preview should warn when the action requires a hub and show the complete cost.

```text
This junction requires a Small Hub
Route: 8
Small Hub: 150
Total: 158
Network hubs after build: 2 / 2
```

If the action is unaffordable or would exceed the hub cap, show the reason and do not establish the route.

After a day runs, hovering the hub shows:

```text
Small Hub
Upkeep: 25/day
Discount on adjacent routes: 15%

Last delivery
Farm: Grain 38 → North 15 (39%) · South 23 (61%)
Bakery: Bread 20 → South 20 (100%)
```

### 10.5 Problem indicators

Full-game aspirational icons:

| Icon | Meaning |
|---|---|
| Clock | Late or slow supply |
| Leaf | Freshness problem |
| Snowflake | Cold storage needed |
| Box | Storage full |
| Network node | Hub overloaded |
| Coin | High upkeep |
| Trash | Food waste |

MVP map indicators:

| Marker | Meaning |
|---|---|
| Orange `!` circle | Tile ran at 90–99% of capacity on the last simulated day |
| Red `!` circle | Tile reached capacity and capped deliveries on the last simulated day |
| Invalid-placement highlight | The proposed route cannot be built because its required hub is unaffordable or the network is at the 2-hub cap |

The v0.2 red and purple dashed pending-junction diamonds are removed in v0.3. Invalid hub-forming routes are rejected atomically instead of remaining on the map.

### 10.6 Settlement delivery popup

Hovering any settlement shows its last delivery result. Clicking it opens the full checklist. The popup must remain compact enough not to obscure the nearby route network and should be positioned inside the viewport.

Minimum fields:

```text
Settlement name
Food: delivered / requested · average freshness · source
Rejected or missing amount
Overall status
```

---

## 11. Example Scenario

### Map

```text
Vegetable Farm ----\
                    Small Hub ---- Village A
Bakery ------------/      \
                           \---- Town B ---- Cool Storage ---- City C
Dairy Farm ----------------/
```

### Problem

- Village A needs bread and vegetables.
- Town B needs bread, vegetables, and milk.
- City C needs milk and vegetables with high freshness.
- Dairy Farm is far from City C.
- Direct dairy-to-city route is expensive and milk spoils.

### Player solution

- Use Small Hub to reduce route upkeep for Village A and Town B.
- Place Cool Storage before City C to preserve milk.
- Route vegetables through the hub because they tolerate moderate travel.
- Avoid Freeze Storage because milk can be served with Cool Storage at lower cost.

### Result

```text
Average freshness: 82%
Hub savings: +90/day
Cool Storage prevented milk spoilage.
Profit increased by 18%.
```

---

## 12. MVP Scope

The first playable version should be small.

### MVP map

One region with:

- 21×14 tile grid (extended from an original 17×10 to give room for genuinely separate networks — see §0.9), with 2 tiles of empty margin on every edge around the playable layout.
- 5 food sources (Farm, Garden, Bakery, Dairy, Harbor) — one food each, see §4.7.
- 5 settlements (Village A, Village B, Village C, Town D, City E).
- 1 river running down the map as a terrain obstacle; any route tile built on it auto-constructs a bridge.
- City E is the late-game objective: highest demand, strictest minimum freshness (55%, vs. 35–45% for Villages/Town).

### MVP food

- Grain
- Bread
- Vegetables
- Milk
- Seafood

### MVP buildings

- Route (Dirt / Paved / Main)
- Normal Storage
- Cool Storage
- Freeze Storage
- Hub — forms automatically at 3-way junctions, always as a Small Hub (see §4.4). Regional Hub is a manual upgrade path from an existing Small Hub, not a placeable building in its own right.

### MVP systems

- Route drawing
- Route upkeep
- Route capacity (tight enough to be a routine bottleneck, not an edge case — see §4.1)
- Atomic automatic hub formation with a per-connected-network cap of 2 (see §4.4)
- Settlement-only delivery destinations; sources and non-target settlements cannot be transit nodes
- Demand-pull food assignment from sources to settlements
- Freshness decay
- Storage preservation
- Hub discount
- Settlement demand, with ±15–20% daily wobble
- Congestion markers and invalid-placement feedback on the map (see §10.5)
- Hub last-delivery split tooltip on hover
- Per-settlement delivery popup on hover and fulfillment checklist on click
- Daily report
- Basic upgrades

### MVP win condition (revised in v0.2)

v0.1 scoped a one-time clear condition:

```text
Average settlement happiness: 80%+
Average food freshness: 70%+
Profit: positive for 3 consecutive days
Waste: below 20%
```

This was replaced with an **endless efficiency-score chase**. Each day produces a 0–100 score (weighted from freshness, happiness, waste, and profit) and a letter grade (S/A/B/C/D). The player tracks:

- Today's grade
- Best-ever grade and score
- Rolling 7-day average score

There is no finish line. The daily demand wobble (§0.4) means a network that scored well once isn't guaranteed to score well again, so there is always a "can I make this cleaner" pull, which is a closer match to §18's Core Fun Test than a checklist that, once cleared, has nothing left to optimize.

### MVP implementation values

The first playable version uses a finite starting balance of 1,500. The player
draws cardinal, tile-based route segments outward from nodes or the existing
network. Food is assigned automatically using a demand-pull model. Every flow
starts at one food source and ends at one settlement, preferring the path with
the best predicted delivered freshness and using upkeep as the tie-breaker,
subject to route capacity. Other sources and all non-target settlements are
blocked as intermediate path vertices.

Source supply per day is Farm (80 grain), Garden (90 vegetables), Bakery (80
bread), Dairy (75 milk), and Harbor (55 seafood). Food value/decay per tile is
Grain (3/0.5), Bread (5/1.5), Vegetables (6/2.5), Milk (8/4), and Seafood
(10/6). Settlement demand for each food wobbles ±15–20% per day.

Route construction costs 8 per tile before terrain modifiers. Dirt route upkeep
is 2 per tile/day before terrain, route-level, and hub modifiers. Route
capacity is 60 (Dirt) / 160 (Paved) / 400 (Main) food/day. Crossing a river
automatically constructs a bridge for an additional 40. Basic upgrades are
Dirt -> Paved -> Main routes and (hub-upgrade only) Small -> Regional hubs.
Storage types are separate buildings rather than an upgrade chain.

A newly placed route tile that would have 3+ connections requires a Small Hub
for 150 in the same construction transaction. The complete action is accepted
only when the route, optional bridge, and required hub are affordable and the
connected network remains within its 2-hub cap. Otherwise the route placement
is cancelled with no map change and no treasury deduction (§4.4).

The first playable version has no save persistence, delivery animation,
chapter tutorial sequence, Central Hub, source upgrades, or random events. It
does retain last-day flow records in memory for hub and settlement popups.

---

## 13. Not MVP / Future Features

Avoid these until the core loop is fun.

### Avoid in MVP

- Vehicle types
- Manual cooking
- Staff hiring
- Complex traffic AI
- Fuel systems
- Real-time driver scheduling
- Large city simulation
- Too many food ingredients
- Multiplayer

### Future features

- Seasonal events
- Weather
- Festivals
- Contracts
- Export/import towns
- Combined cold hubs
- Special settlements
- Route disasters
- Cosmetic village growth
- Challenge maps
- Daily puzzle mode

---

## 14. Example Future Events

Events can create temporary routing puzzles.

### Festival Day

A settlement needs 3x bread and vegetables for one day.

### Heat Wave

Freshness decays faster unless food passes through Cool Storage.

### Snow Week

Mountain routes cost more and fresh food decays faster.

### Harbor Boom

Seafood supply increases, but demand must be met quickly.

### School Lunch Contract

A town requires bread and milk before noon for 5 days.

Events should be forecast in advance so the player can plan.

---

## 15. Balancing Goals

### Direct routes should be good for nearby settlements

Players should not be forced to use hubs everywhere.

Good rule:

```text
For 1-2 close settlements, direct routes are fine.
For 3+ destinations or long-distance routes, hubs become efficient.
```

### Freeze Storage should be powerful but expensive

Freeze Storage should solve hard routes but hurt profit if overused.

Good rule:

```text
Freeze Storage is correct for seafood, meat, ice cream, and long-distance food.
Freeze Storage is wasteful for bread, grain, and short routes.
```

### Storage should not restore freshness

This keeps route design important.

Good rule:

```text
Bad route before storage still matters.
```

### Hubs should show visible savings

The player must feel rewarded for efficient network design.

Good rule:

```text
Every hub shows its discount and upkeep on hover, and every hub tile
shows what's actually splitting through it (which source, how much).
```

Since hubs auto-form, the visible reward comes from the complete-cost construction preview, the formation confirmation, and the last-delivery split shown on hover.

### Hub cap should feel like a real constraint, not an annoyance

Added in v0.2 and tightened in v0.3. A cap that is rarely reached does nothing, while a rejected build without a clear explanation feels arbitrary. The constraint should be strict but predictable, reversible, and free of accidental spending.

Good rule (revised in v0.3):

```text
A route that would require a hub beyond the network's cap is rejected.
The player sees the reason before or immediately after the attempted click,
loses no money, and can reroute or keep networks separate.
```

---

## 16. Technical Data Model Draft

This section is not final implementation, but it gives structure.

### Node

```yaml
node_id: string
node_type: source | settlement | storage | hub
position: [x, y]
```

### RouteSegment

```yaml
route_id: string
from_node: node_id
to_node: node_id
length: number
terrain_profile: list
capacity: number
base_upkeep: number
```

### FoodFlow

```yaml
flow_id: string
food_id: string
source_node: node_id
destination_node: node_id
path: list(route_id)
amount_per_day: number
current_freshness: number
```

### Storage

```yaml
storage_id: string
storage_type: normal | cool | freeze
capacity: number
daily_upkeep: number
protection_distance: number
freshness_loss_multiplier: number
compatible_food_categories: list
```

### Hub

```yaml
hub_id: string
hub_type: small | regional | central
link_capacity: number
flow_capacity: number
route_discount: number
daily_upkeep: number
```

### HubDeliverySplit

```yaml
hub_id: string
day: number
source_id: string
food_id: string
amount_through_hub: number
outgoing_splits:
  - direction_or_route: string
    amount: number
    percentage: number
    destination_ids: list
rejected_amount: number
```

### SettlementDeliveryResult

```yaml
settlement_id: string
day: number
food_id: string
requested: number
delivered: number
rejected: number
average_freshness: number
source_ids: list
status: complete | partial | missing
```

### SettlementDemand

```yaml
settlement_id: string
food_id: string
amount_required: number
minimum_freshness: number
bonus_freshness: number
overdelivery_tolerance: number
```

---

## 17. Simulation Order

Each day simulates in this order:

1. Generate settlement demand.
2. Calculate available source supply.
3. Create candidate flows whose start is a matching source and whose destination is a settlement requesting that food.
4. Find paths while blocking every other source and every non-target settlement as intermediate vertices.
5. Assign only the amount needed by settlement demand; unassigned production remains at the source.
6. Apply route, storage, and hub capacity limits.
7. Apply freshness loss along each path.
8. Apply storage preservation effects when food passes storage.
9. Record accepted and rejected deliveries.
10. Aggregate each hub's incoming source-food totals and outgoing branch splits.
11. Apply hub discounts and calculate route, storage, and hub upkeep.
12. Calculate income, waste, profit, settlement satisfaction, and efficiency score.
13. Store last-day hub and settlement delivery results for hover popups.
14. Show the daily report.

---

## 18. Core Fun Test

The prototype is successful if the player naturally thinks:

```text
This direct route works, but it is expensive.
Maybe a hub will form here once I connect a third path.

This new branch would require a third hub, so it cannot be built.
Should I reroute it or keep this network separate?

This milk arrives too spoiled.
Maybe I should route it through Cool Storage.

Freeze Storage saves the seafood, but the upkeep is too high.
Maybe I need a shorter route.

The hub says Farm grain split 39% north and 61% south.
Is that split using the route capacity the way I expected?

Village A is missing bread even though the roads look connected.
The popup should tell me whether the issue is supply, freshness, or capacity.

My network works, but I can make it cleaner tomorrow.
```

The player should be able to understand the network from visible delivery results rather than guessing from connections alone. If hub splits and settlement popups lead directly to a useful redesign decision, the feedback system is working.

---

## 19. Final Core Statement

The game is about building the cheapest and cleanest food supply network that still delivers fresh food.

The three main decisions are:

```text
Where should routes go?
Where should storage be placed?
Where should hub-forming junctions organize the network?
```

The main puzzle is:

> Feed every settlement with the right food, at the right freshness, for the lowest sustainable upkeep.
