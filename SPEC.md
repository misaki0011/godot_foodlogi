# Food Logistics Puzzle Game - Design Spec

**Version:** 0.1  
**Working title:** Fresh Routes  
**Genre:** Cozy logistics / routing puzzle / light management  
**Target platform:** PC / Steam  
**Core player actions:** Draw routes, place storage, place hubs  
**Explicitly out of scope:** Vehicle management, cooking simulation, staff management, complex traffic simulation

---

## 1. High-Level Concept

The player builds a regional food delivery network between food sources and settlements. Food loses freshness while traveling. The player draws efficient routes, places storage buildings to preserve freshness, and uses hubs to reduce route upkeep.

The game should feel like a clean, cozy logistics puzzle rather than a transport-management simulator.

### One-sentence pitch

> Draw food routes across a cozy region, use storage to keep food fresh, and build hubs to feed villages, towns, and cities efficiently.

### Core fantasy

The player is not a driver, chef, or factory worker. The player is a regional food network planner who keeps communities fed by designing smart supply routes.

---

## 2. Design Pillars

### 2.1 Simple inputs, deep outcomes

The player only needs a few actions:

1. Draw a route.
2. Place storage on or near a route.
3. Place a hub to organize and reduce network cost.
4. Upgrade or remove route infrastructure.

Depth comes from food freshness, storage choice, route length, hub placement, terrain, and settlement demand.

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
- Add hubs.
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
| Dirt route | 100 food | 1.0x |
| Paved route | 250 food | 1.6x |
| Main route | 500 food | 2.5x |

Capacity creates meaningful hub and route upgrade decisions without needing vehicles.

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

A hub is not primarily for freshness. It is for network organization and cost reduction.

### Hub purpose

- Combine routes from multiple sources.
- Split routes to multiple settlements.
- Reduce upkeep on connected route segments.
- Increase network capacity.
- Encourage regional planning.

### Basic hub rule

Route segments connected to a hub receive an upkeep discount, but the hub itself has daily upkeep.

```text
hub_adjusted_route_upkeep = connected_route_upkeep * (1 - hub_discount)
net_savings = route_discount_savings - hub_daily_upkeep
```

The UI should show net hub savings clearly.

Example:

```text
Small Hub
Route savings: 95/day
Hub upkeep: 40/day
Net savings: +55/day
```

### Suggested hub levels

| Hub type | Build cost | Daily upkeep | Link capacity | Route discount | Flow capacity |
|---|---:|---:|---:|---:|---:|
| Small Hub | 150 | 25 | 4 links | 15% | 250 food/day |
| Regional Hub | 350 | 60 | 8 links | 25% | 600 food/day |
| Central Hub | 800 | 140 | 14 links | 35% | 1,400 food/day |

### Hub placement decision

A hub should usually become worthwhile when it serves 3 or more routes or when it shortens several long routes.

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

The hub network should have lower upkeep if the hub is well placed.

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
| Farm | Grain, vegetables |
| Bakery | Bread |
| Dairy | Milk |
| Harbor | Seafood |
| Freezer Plant | Frozen food |
| Orchard | Fruit |

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

### 10.4 Hub placement UI

When placing a hub, show expected savings.

```text
Small Hub Preview

Connected routes: 4
Route savings: 95/day
Hub upkeep: 25/day
Net savings: +70/day
Capacity: 250 food/day
```

### 10.5 Problem indicators

Use simple icons:

| Icon | Meaning |
|---|---|
| Clock | Late or slow supply |
| Leaf | Freshness problem |
| Snowflake | Cold storage needed |
| Box | Storage full |
| Network node | Hub overloaded |
| Coin | High upkeep |
| Trash | Food waste |

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

- 4 food sources (Farm, Bakery, Dairy, Harbor)
- 5 settlements
- 1 river or terrain obstacle
- 1 city/town as a late objective

### MVP food

- Grain
- Bread
- Vegetables
- Milk
- Seafood

### MVP buildings

- Route
- Normal Storage
- Cool Storage
- Freeze Storage
- Small Hub
- Regional Hub

### MVP systems

- Route drawing
- Route upkeep
- Freshness decay
- Storage preservation
- Hub discount
- Settlement demand
- Daily report
- Basic upgrades

### MVP win condition

The player clears the region by maintaining:

```text
Average settlement happiness: 80%+
Average food freshness: 70%+
Profit: positive for 3 consecutive days
Waste: below 20%
```

### MVP implementation values

The first playable version uses a finite starting balance of 1,500. The player
draws cardinal, tile-based route segments between any two nodes. Food is then
assigned automatically across the network, preferring the path with the best
predicted delivered freshness and using upkeep as the tie-breaker.

Source supply per day is Farm (80 grain, 90 vegetables), Bakery (80 bread),
Dairy (75 milk), and Harbor (55 seafood). Food value/decay per tile is Grain
(3/0.5), Bread (5/1.5), Vegetables (6/2.5), Milk (8/4), and Seafood (10/6).

Route construction costs 8 per tile before terrain modifiers. Dirt route upkeep
is 2 per tile/day before terrain, route-level, and hub modifiers. Crossing a
river automatically constructs a bridge for an additional 40. Basic upgrades
are Dirt -> Paved -> Main routes and Small -> Regional hubs. Storage types are
separate buildings rather than an upgrade chain.

The first playable version has no save persistence, delivery animation,
chapter tutorial sequence, Central Hub, source upgrades, or random events.

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
Every hub has a visible net savings indicator.
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

Each day can simulate in this order:

1. Generate settlement demand.
2. Calculate available source supply.
3. Assign food flows along player routes.
4. Apply route capacity limits.
5. Apply freshness loss along each route segment.
6. Apply storage preservation effects when food passes storage.
7. Apply hub upkeep discounts.
8. Deliver food to settlements.
9. Calculate income, upkeep, waste, and satisfaction.
10. Show daily report.

---

## 18. Core Fun Test

The prototype is successful if the player naturally thinks:

```text
This direct route works, but it is expensive.
Maybe I should place a hub here.

This milk arrives too spoiled.
Maybe I should route it through Cool Storage.

Freeze Storage saves the seafood, but the upkeep is too high.
Maybe I need a shorter route.

My network works, but I can make it cleaner tomorrow.
```

If the player has these thoughts, the core is working.

---

## 19. Final Core Statement

The game is about building the cheapest and cleanest food supply network that still delivers fresh food.

The three main decisions are:

```text
Where should routes go?
Where should storage be placed?
Where should hubs organize the network?
```

The main puzzle is:

> Feed every settlement with the right food, at the right freshness, for the lowest sustainable upkeep.
