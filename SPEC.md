# Food Logistics Puzzle Game - Design Spec

**Version:** 0.4  
**Working title:** Fresh Routes  
**Genre:** Cozy logistics / routing puzzle / light management  
**Target platform:** PC / Steam (MVP prototype: browser)  
**Core player actions:** Draw routes (drag-only, starting from a source or hub, ending at a hub or settlement), place storage, build hubs on any route tile  
**Explicitly out of scope:** Vehicle management, cooking simulation, staff management, complex traffic simulation

---

## 0. Changelog

### v0.3 → v0.4 — Mobile/touch playtest support

The Godot port needed to be testable from a phone browser, which has no hover and no keyboard. These changes supersede conflicting v0.3 text on settlement popups and hover-only info:

1. **Sources and settlements show all info on tap, no dialog.** The two-tier design (hover popup + click-to-open full checklist) is replaced by a single tap/hover info tip: tapping (or hovering, on desktop) a source or settlement tile shows the same tip, and for settlements it includes the full last-delivery checklist that used to live in a separate popup. Tapping one of these tiles never attempts to build there, regardless of the active tool.
2. **A top-left map panel adds touch zoom/pan controls.** Since a touchscreen can't scroll-wheel-zoom or hold a key to drag-pan, a fixed on-screen panel provides +/− zoom buttons and a 4-direction pan pad for exploring the map, usable by mouse or touch. See §10.7.
3. **Route tiles render a directional shape.** A route tile auto-renders straight or L-corner from its real adjacency instead of always looking the same; when that shape is ambiguous (0-1 real connections) it defaults sensibly and the player can tap it to cycle through the valid options. See §4.1.
4. **Neither food sources nor settlements count toward hub-formation degree.** A route tile that only reaches "3 connections" because a node sits beside it is a plain pass-through, not a branching junction, so it neither requires a hub nor gets blocked by the network's hub cap on that basis. See §4.4.
5. **A Bubbles On/Off toggle joins the map control panel.** Hides or shows every source/settlement speech bubble at once, since a busy network can crowd many bubbles together. See §10.7.
6. **Route shape locking is now scoped to nodes only, and a hold-to-drag mode previews multi-tile paths.** Item 3's forcing rule now only applies to a tile adjacent to a source or settlement -- every other route tile is always tappable to any of the 6 shapes, defaulting sensibly until tapped. Separately, pressing and holding a buildable cell switches from single-tile tapping into a drag preview: a translucent line traces the path live (green if valid, red if not) without touching the map, and only builds the whole path, and only if it's fully valid, on release. See §4.1.
7. **A lone stub's default shape is direction-aware.** Item 6's "defaulting sensibly" previously meant an arbitrary fixed shape regardless of where a tile's one real neighbor (route or node) actually was, which could default to a corner touching neither real neighbor. It now considers the actual side of a single real route neighbor and/or an adjacent node together, defaulting to a straight tile when they're in line, the one corner touching both when they're perpendicular, and a corner touching the node's real side when there's no route neighbor at all. See §4.1.
8. **Route tile shape now ignores adjacent nodes entirely, and a fast drag no longer leaves gaps.** Two drawing-mode fixes. First, items 3/6/7 let an adjacent source or settlement force or bend a tile's shape, so a road always appeared to "connect" to the node it sat beside; a tile's shape is now derived purely from its real route/storage/hub neighbors, never from a node, and every route tile (including node-adjacent ones) is freely tappable to any of the 6 shapes. Second, dragging a route quickly used to skip the cells between two mouse-motion samples, leaving unbuilt holes in the middle of the path; the drag now fills in every orthogonal cell between samples so the traced path is always gap-free. See §4.1.
9. **Corner tiles now bend the correct way, and Route/Erase shortcuts join the map control panel.** Two fixes. First, the "se" (down-right) and "nw" (up-left) L-corner rotations were swapped, so a corner that should bend down-and-right rendered as up-and-left and vice versa; the yaw table now matches the counter-clockwise sense of the top-down camera. Second, the Draw Route and Bulldoze tools now also appear as compact buttons on the top-left control panel, so the most common build/erase actions are reachable without crossing to the right sidebar. See §4.1, §10.7.
10. **Sources/settlements count toward hub-formation degree again, and an established-route overlay is added.** Two changes. First, this reverses item 4: a hub is any tile where a delivery fans out to more than one path, so an adjacent food source or settlement DOES count toward a tile's 3-connection hub threshold — a road fed by a source that splits toward two directions now auto-forms a hub, regardless of the node beside it. Second, a bright gold line is continuously overlaid along every route tile that lies on a complete source→settlement path (dead-end stubs pruned out), so the player can see at a glance which roads actually link a source to a customer. See §4.4, §4.1.
11. **The hub cap is per road network, and no longer leaks across a shared node.** This refines item 2: a connected network for hub-cap and hub-formation purposes is now computed over road tiles ALONE, since a delivery can never pass through a source/settlement. Two road groups that touch only a shared node are separate networks, each with its own 2-hub budget — so building a junction on a small road hanging off a source is no longer wrongly blocked just because another road on that same source is already capped. (Together with item 10's node-counting, this is what made the false block visible.) See §4.4.
12. **Hubs form at completed-route forks, not from raw connection degree; route placement is never blocked by the cap.** This supersedes items 4/10's degree rules and the earlier "atomic route+hub placement" behaviour (§4.4). A Small Hub now auto-forms only where a *finished* delivery route branches: a tile that lies on an established source→settlement route AND has 3+ neighbours that are also on an established route. Adjacent sources/settlements no longer count (a node is a terminal endpoint, not a branch), so a straight road, an unfinished/isolated road, or a road merely sitting beside a source never forms a hub — fixing hubs that were appearing on straight roads next to sources. Because hubs form after the route is built, drawing roads is never blocked by the hub cap; an over-cap fork just stays a plain `hub_capped` tile. See §4.4, §4.1.
13. **Hubs mark completed-route split/merge points, and deliveries never transit a node.** Two changes. First, this refines item 12's fork rule: a hub is where a source's delivery splits toward multiple paths or where multiple sources converge, so on an *established* source→settlement route a tile counts a branch for each established-route neighbour AND each adjacent source/settlement node — a source beside a tile that also continues in 2+ road directions now forms a hub (the "established route" gate still keeps hubs off straight/unfinished roads). Second, delivery pathfinding no longer routes *through* a source or settlement: a node is only ever a path's start or end, never a transit shortcut, so grain can no longer reach a settlement by passing through another node in the middle. See §4.4, §4.7.
14. **Hub construction is now a manual, player-paid action, not automatic.** Two independently-drawn complete routes still merge into one road network the moment they touch (orthogonal adjacency is what defines a network, regardless of which route a tile was "meant" to belong to), and a touching tile that happens to qualify as a completed-route fork (item 13's rule) used to auto-build a Small Hub there and auto-charge the player, whether they wanted a hub at that spot or not -- this actively fought a common, entirely reasonable layout: two routes running side by side. The fork-detection and per-network hub cap are unchanged (still real constraints on connectivity), but building the hub itself is now the player's choice: a qualifying tile is flagged as a buildable junction instead of auto-converting, and a new Build Hub tool lets the player pay §150 to place a Small Hub there whenever they decide to. A junction in a network already at its hub cap is marked `hub_capped` and the Build Hub tool refuses it, exactly as the old auto-formation did. This reintroduces player-directed hub placement (reversing the v0.1→v0.2 decision) specifically to fix the auto-charge/auto-cap side effect of side-by-side routes. See §4.4.
15. **Connectivity is explicit, drag-only, and tap no longer creates a tile at all.** Item 14 fixed the *charge*, but two side-by-side routes still merged into one road network just by touching -- physical adjacency was, and always had been, the entire definition of "connected" (pathfinding, hub-cap networks, established routes, upkeep discount, route shape). This item removes that assumption everywhere: a `GameState.connections` edge, drawn only by the player dragging across a tile-tile or tile-node boundary, is now what connects two cells; sitting next to something never does. Concretely: (a) tapping a route tile only cycles its shape (or shows a hint on empty ground) -- creating a new tile is drag-only, starting from a press on an existing node or route tile and building/connecting every cell the drag crosses, releasing to commit the whole path atomically, same as before; (b) dragging across an *existing* tile or node (no new tile needed) is a free, explicit "connect" gesture -- this is how two separately-built roads, or a road and a node it happens to sit beside, get linked on purpose; (c) `SimulationEngine.build_graph`, `road_components`, `established_route_cells`, `hub_branch_count`, `route_shape`, and the hub upkeep-discount check all consult `state.connections` instead of raw grid/node adjacency. Bulldozing a tile removes every connection edge touching it. Other tools (storage, hub, upgrade, bulldoze) are unaffected -- they still act on a single existing route tile with one tap. See §2.1, §4.1, §4.4, §16.
16. **The established-route overlay marks its two ends distinctly.** The gold line from item 10 read as one uniform strand end to end; now the source end shows a green cone arrow pointing the direction delivery actually flows (source → first tile) and the settlement end shows a red bar instead of gold, so start and finish are readable at a glance without tracing the whole line. Purely visual -- no simulation or cost change. See §4.1.
17. **A hub can be built on any route tile, not just a flagged completed-route fork.** This drops item 12/13's "3+ branch, established-route" requirement entirely: the player draws a route, picks the Build Hub tool, and clicks any existing route tile -- straight, isolated, unfinished, it doesn't matter -- to place a Small Hub there for §150. The per-network cap (still 2 hubs, item 11) is the only remaining constraint, checked live against the tile's connected road network rather than a precomputed `junction`/`hub_capped` flag. This simplifies a rule that had grown through several revisions (items 4, 10, 12, 13) into something the player can reliably predict: any road, anywhere, up to two hubs per network. See §4.4.
18. **A route drag can only start from a source or a built hub.** Previously a drag could start from any existing node or route tile (item 15), letting the player extend a route from any point already on the map. Routes must now always trace back to a supply point: press-and-hold is only a valid drag anchor on a source node or a hub tile, never on a settlement or a plain route tile. See §4.1.
19. **A route drag must end at a hub or a settlement.** Item 18 fixed where a drag can start; this fixes where it can stop. Previously a drag could be released anywhere, including one tile short of the settlement it looked like it was reaching -- the tiles would look like one continuous road, but without a genuine connection to a node, the road was never established and silently carried no delivery, no overlay, and no hub eligibility at that end. Now the LAST cell of a drag must be a hub tile or a settlement node, or the whole path is rejected (nothing built, nothing charged), exactly like the affordability check. Together with item 18, every committed drag is therefore always a complete, genuinely connected route from a supply point (source or hub) to a delivery destination (hub or settlement) -- there's no way to end up with a route that only looks finished. See §4.1.
20. **A new route can never cross or reuse an already-built tile -- it only ever runs over empty ground between its two ends.** Item 15's "dragging across an existing tile is a free connect gesture" let a new drag pass through the MIDDLE of an unrelated existing route or storage tile, which reintroduced exactly the kind of implicit, easy-to-miss topology items 15/18/19 were trying to eliminate: a player could accidentally piggyback a new route on someone else's infrastructure without meaning to, or fail to notice their drag silently reused a tile rather than building its own. Now every cell strictly between a drag's start anchor (source/hub) and end anchor (hub/settlement) must be currently-empty ground; if the path crosses any other built tile or node along the way, the whole drag is rejected, same as an unaffordable or improperly-terminated one. Two routes can now only ever share infrastructure at a hub or settlement they were both dragged to end at -- never by physically overlapping a shared tile. See §4.1.
21. **Tap-to-cycle-shape is retired -- a route is built by a drag and a release, nothing else.** Item 6 (v0.3→v0.4) let the player tap a built route tile to cycle it through all 6 shapes, overriding the auto-derived default. With items 18-20 now guaranteeing every route is a clean, freestanding drag from a supply point to a delivery destination, the manual shape override added a degree of freedom the design no longer needs: a route tile's shape is always exactly the auto-derived default (see "Route tile directional shape" below) and nothing else. Tapping a route tile (or empty ground) with the route tool now only ever shows a hint that a drag is needed. `GameState.grid`'s `facing` override field and `SimulationEngine.is_shape_ambiguous`/`cycle_shape_facing` are removed entirely. See §4.1.
22. **A drag may also start or end on a route tile that isn't part of an established route yet.** Items 18-19 restricted a drag to start on a source/hub and end on a hub/settlement, which -- combined with item 20's "no crossing existing tiles" -- meant unfinished infrastructure (a route segment that doesn't yet reach both a source and a settlement, e.g. one built out from a hub that has no source connection yet) could only ever be picked up again at its own governing hub, never at any of its plain route tiles. This relaxes both ends: a drag may also start or end on a route tile that `SimulationEngine.established_route_cells` does NOT contain -- i.e. one that isn't currently part of a live, delivering path. An already-established route tile is unaffected and still only reachable through its own hub or settlement (never picked up mid-network) -- this exception exists purely so unfinished, not-yet-delivering infrastructure can be extended or joined piece by piece without forcing a hub at every waypoint. The interior-must-be-empty-ground rule (item 20) is unchanged: this only widens what counts as a valid START or END, not what a drag may cross through. See §4.1.
23. **One symmetric route tile design per level, usable in any direction.** Each route level (Dirt, Paved, Main) previously rendered a directional tread/stripe requiring a rotated mesh for "lr" vs. "ud", plus a dedicated L-shaped corner mesh (rotated four ways) wherever a tile bent -- this doubled the asset count per upgradeable level and made every route tile's appearance depend on a shape/facing computed from its real connections (see the now-removed "Route tile directional shape" system). Dirt and Main are redesigned to be radially symmetric, the same way Paved's four-cobblestone layout already was: Dirt uses a centered square worn-earth patch with four corner pebbles instead of a directional tread strip, and Main uses a painted cross (both axes) instead of a single center line. Because a symmetric mesh reads identically under any rotation, ONE mesh per level now covers every route shape and facing -- there is no corner variant, and nothing is rotated at render time. `SimulationEngine.route_shape()` and its shape-family/facing machinery are removed entirely; a route tile's rendering is now just `level -> mesh`. See §4.1.

24. **The day runs itself on a real-time clock.** A day is now a 60-second countdown shown in the top-right corner rather than a "Run the Day" click. The player keeps building while it drains; at 0:00 the day simulates, the calendar advances, and the next day's clock starts immediately, so planning and simulation are continuous instead of alternating around a button press. The clock can be paused (button or spacebar), run at 1x/2x/4x, or switched off entirely for the older manual loop, and a day can still be run early. Because a modal every 60 seconds would defeat the point, an auto-run day posts a small self-dismissing summary card (day, grade/score, profit, freshness, happiness) under the clock instead of the full-screen report; the full report stays one Report-button click away, and opening it freezes the clock so reading it never costs build time. See §3.5, §10.8.
25. **One left-hand control panel replaces the right sidebar.** The 300px build sidebar on the right edge is retired, and everything it carried -- treasury/day, the efficiency-chase numbers, every build tool, and the legend -- moves into the top-left map-controls panel, which becomes the game's single HUD panel. Two panels ate both edges of the screen and split related controls across them, which is why the most-used tools had to be duplicated on both (item 9/14's shortcuts); one panel gives the map back most of that width and makes each tool exist exactly once, with the day clock alone in the opposite corner. Tool buttons are now short and priced (e.g. "Cool §180"), with the full description in the tooltip and the hint bar, and the legend collapses. See §10.7.

26. **Bulldoze and Upgrade can be swept across many tiles in one drag.** Both were strictly one click per tile, which made clearing a bad run or upgrading a long road a repetitive series of taps -- and on a touchscreen, a series of taps that is easy to mis-hit. Either tool can now be dragged: every tile the pointer crosses is marked, and the tool is applied to all of them on release. The sweep starts on press with no hold threshold (unlike a route drag, it only ever touches tiles that already exist, and nothing happens until release, so there is no accidental-build risk to guard against), and a press released without moving is still the ordinary single-tile action. Route drawing is unchanged -- it traces a path with start/end rules, not a set of tiles. See §4.1.

27. **The established-route overlay is coloured per source, food by food.** The overlay was one gold line regardless of what travelled it, so telling the grain route from the milk route meant tracing it back by eye. Each source now gets its own lane in the colour of the food it produces, and where several sources' deliveries share a road their lanes run side by side down it -- a colour joins the road where its source does, and peels off exactly where their paths part. Route TILES keep their ordinary built colour (Dirt/Paved/Main brown); only the overlay carries source colour. All source *markers* share one colour (§16), so the food colour is what actually distinguishes one source from another, and it is the colour language the speech bubbles already use. The legend lists the mapping, built from the region's own sources. See §4.1.

28. **Freeze Storage and the Regional Hub upgrade are retired.** Both are removed from the build, not merely hidden: `GameEnums.StorageType` is down to NORMAL/COOL, `GameEnums.HubType` to SMALL, their entries in `GameBalance.STORAGE_TYPES`/`HUB_TYPES` and `HUB_REGIONAL_UPGRADE_COST` are deleted, `Main._do_upgrade_hub` and both tool buttons are gone, and with no freezer left to trigger it the freeze-penalty rule goes too -- `FoodData.freeze_penalty` and the penalty branch in `SimulationEngine.simulate_freshness` are deleted along with it. Storage is now Normal and Cool; a hub is always a Small Hub. The full-game material in §6, §8 and §11 still describes both (Freezer Plants, Frozen Food, Chapter 5's freeze chain, Regional Networks); treat those as post-MVP scope superseded by this item, not as descriptions of the current build. See §4.3, §4.4.

29. **The light follows the clock: one in-game day is one sun cycle, and it casts shadows.** A day now visibly runs dawn -> morning -> midday -> afternoon -> sunset -> dusk -> night -> dawn while the player builds, by driving the sun's angle, the sunlight's colour and strength, the shadow strength, and the sky/ambient tint off the day clock's phase. Shadows are switched on and the sun sweeps a full turn over the day, so they visibly travel and stretch -- short and tucked under objects at midday, long and raking at dawn and sunset, faint under moonlight. The clock panel reads the wall-clock time beside the day number ("Day 3 - 6:45 pm"), with the phase name on the line below. The cycle is continuous across the day rollover -- the first and last keyframes are the same moment, one turn of the sun apart -- so the sun comes back up exactly as the clock hits 0:00 rather than the sky snapping or the light spinning back. A stopped clock (paused, or manual mode) holds the light where it is, since time of day IS the day clock. Shadows are desktop-only: a phone browser drops the WebGL context outright when the GPU budget is overrun, and reducing the shadow map was not enough to stay inside it, so the web build runs the cycle without shadows while desktop keeps them at full quality. See §3.6.

30. **Source and settlement bubbles are told apart by shape and palette, and a settlement's status stops tinting its body.** Both bubbles were the same cream rounded box with dark text, so the only thing separating a source from a settlement was the freshness suffix. Colour could not take over the job either -- it already carries the food's identity, and a settlement's red/amber/green was painted across the bubble body, which forced every status to stay pale enough to read dark text on; red and green ended up at nearly the same lightness and were hard to tell apart at map distance. Sources are now dark slate signs on a post with white text, near-square corners and an outgoing-supply arrow, at 85% of a settlement's size; settlements keep the cream speech balloon with a triangular tail. Grey costs no colour meaning, being the one hue on the map that is neither a food nor a status, and it makes the food-coloured dot the brightest thing on a sign. A spent source fades in place (dim ink on the same dark body) rather than switching to grey, which is now the normal look. Settlement status moves onto the border, the tail, the bar and a ✕/!/✓ glyph sized as a peer of the food dot, so the three states are separable by shape alone for players who cannot separate the hues; the accents are fully saturated and differ in lightness as well. Red draws a static halo, never a pulse -- on day one every settlement is red. Green washes lighter and outlines thinner so settled towns recede, and a settlement whose every demanded food is green collapses to a single "All fresh" bubble. The status rule itself is one question asked twice: green is the full requested amount at the settlement's own `bonus_freshness` or above, amber is the full amount below it, red is anything short. `min_freshness` plays no part -- `SimulationEngine.run_day` rejects anything under it before it counts as delivered, so a bubble can never see an average below that line. The bar along a settlement bubble's bottom reads freshness, with a tick at that settlement's bonus threshold, since "78%" means nothing until you remember whether this town wanted 80 or 90. See §10.1, §16.

31. **A delivery only pays if the whole order arrived, and pays extra if it arrived fresh.** Income was banked cart by cart, so a settlement that got half its order still earned half the money and the map's red/amber/green bubbles were commentary rather than consequence. Per food line the rule is now the bubble: red pays nothing, amber pays the line, green pays the line plus `GameBalance.FRESHNESS_BONUS_RATE` (25%) again. A short order is not a partial sale -- the settlement went without, so the run earns nothing however fresh what did arrive happened to be. Green is judged against that settlement's own `bonus_freshness`, the same figure the satisfaction score divides by and the hover tip already quotes (80% at the villages, 85% at Town D, 90% at City E), so the threshold that turns a bubble green is the threshold that pays. The freshness *multiplier* on the line itself is unchanged. The day report breaks out both halves under Income -- the bonus earned, and what the incomplete orders cost -- so the rule is legible without reverse-engineering the profit line. Note this bites hardest early, when few lines are complete and most of the map is red; §9's tuning may need revisiting alongside it. See §9, §10.1. Satisfaction, waste and the efficiency grade are deliberately untouched.

32. **Bridges: a placed structure that lets one route cross another without joining it.** A drag could never cross an existing road at all (item 20), so a route that needed to get past one had to go around it or stop -- and the obvious fix, letting drags overlap freely, is exactly what turns a map into spaghetti. A bridge is instead a **placed structure**, built with its own tool onto one existing route tile carrying a straight through-run of road, the way a hub is: the road already there keeps running underneath, a raised deck spans it at right angles, and a later drag may run straight over the deck without the two routes ever becoming one network. Making it a purchase the player places and can see on the map, rather than a side effect of a wobbly drag, is what keeps crossings deliberate. Internally, connectivity stops being a property of a tile and becomes one of a `(tile, lane)` graph vertex: the lane you land on follows the direction you stepped in, and from either you may only leave the way you came in -- so `find_path`, `road_components` and `established_route_cells` keep the two roads apart with no second grid layer and no change to `GameState.connections`. Kept narrow on purpose (straight runs only, both landings on-map and not a node, no two bridges landing on each other, nothing else buildable on a bridge tile, no drag starting or stopping on one) and priced to lose to a detour: §60 to build, §6/day extra upkeep, 2x freshness decay to cross the deck, shared tile capacity, and a cap of 2 per connected road network. See §4.1.

33. **Bulldozing a hub or a bridge leaves its road behind.** Bulldoze erased whatever cell it was pointed at, connections and all -- right for a bare route tile, wrong for a hub, a storage building or a bridge, which are structures built *on top of* a route tile (item 35 extends this to storage). Clearing one now removes only the structure: the tile survives as a route tile with its connections intact, so the road keeps running through it instead of the network being split in half by an edit the player didn't ask for. The road comes back **at the level it already was** (Dirt/Paved/Main) rather than reset to dirt: paving is paid for separately from the structure, and binning it would be a second loss the player never asked for. A bridge tile carries its own level throughout; a hub cell replaces the route cell outright, so it now records the level it covered at build time in order to hand it back. A bridge additionally drops its **deck** connections while keeping the road beneath it (the deck being the road that ceases to exist), so the route that crossed over is cut at both ends; without that the two roads the crossing was keeping apart would silently merge into one network the moment it came down. The bulldoze sweep applies the same rule to every tile it crosses. See §4.1, §4.4.

34. **A hub renders as a building standing on its road.** A hub tile drew its marker *instead of* a road block, so the road visually disappeared under every junction -- the network looked broken exactly where it forked, and the Dirt/Paved/Main level the tile was upgraded to was invisible for as long as the hub stood there. The road is now drawn underneath and the hub stands on top of it, the same way a bridge already draws its road block plus a deck. This also makes item 33's bulldoze rule look like what it is: clearing a hub reveals the road that was under it all along, rather than a tile appearing out of nowhere. Visual only -- capacity, upkeep, pathfinding and the per-network hub cap are all untouched. See §4.4. (Item 35 gives storage the same treatment.)

35. **Storage gets the same treatment as a hub: drawn on its road, and handed back to it.** Storage was the last structure still replacing the route tile it was built on -- the road vanished under the building, the Dirt/Paved/Main level it covered was forgotten outright, and bulldozing it took the road away with it. A storage cell now records the level it covers at build time, draws that road underneath itself, and hands it back on a bulldoze, exactly as items 33/34 did for hubs. With this, every structure in the game follows one rule -- a building sits **on** a road, and removing the building reveals the road -- so there is no longer a special case to remember. See §4.1, §4.3.

36. **Demand opens one order at a time, instead of the whole region wanting food on day 1.** Every settlement demanded everything from the first day: twelve red bubbles on the opening screen (item 30 already had to rule out pulsing them, because on day one every settlement was red), and a happiness score averaged over five settlements the player could not possibly have connected yet — so the grade measured the calendar, not the network. A settlement's `demand` is now its *eventual* appetite, and `MapData.order_schedule` lists those lines in the order the region learns them; only the lines that have opened are simulated, scored or drawn. Nothing on the map appears or disappears — all five settlements and all five sources stand there from day 1, so the whole region is visible to plan against. What develops is the demand, and the road network the player draws to meet it. Deliberately **not** modelled as settlements growing: a village visibly becoming a city reads as a city-builder, and the thing that should grow in a logistics game is the network. The fiction is that a settlement starts *placing orders*, which is also why an order needs a reason to arrive — it opens only once the player is on top of the ones they already have (every settlement taking orders held 70% happiness for 2 consecutive days), with the schedule's `earliest_day` as a floor rather than a timer, at most one new order per rollover, and the streak spent on each one earned. A settlement with no open order draws no bubble at all; the one next in line gets a quiet countdown plaque two days out, so the player can lay the road before the order lands and its first day is green. A grey "later" plaque over all five settlements from day 1 would just be the same wall in another colour. See §6, §4.8, §10.1.

37. **The same network now gives the same day, and a settled settlement keeps its numbers.** Two changes with one goal: every figure on the map means something the player did. First, settlement demand no longer wobbles ±15-25% per simulated day (item 4's rule, ported from the HTML). That wobble was the only randomness in the whole simulation, and it made every number a moving target — a bubble read 18/20 one day and 23/23 the next off the same untouched road, so an improvement the player had just made was indistinguishable from noise, and the day report's grade drifted on its own. Freshness was already deterministic (`simulate_freshness` reads only the path), so with the wobble gone the guarantee is total: an unchanged network delivers an unchanged result, at an unchanged grade. Note what this costs — §18's endless-chase argument used to lean on the wobble to stop a "solved" network from staying solved; that pull now has to come from the region opening up (§6), which is what the order schedule already does. Second, the collapsed **"All fresh"** summary bubble is gone: a settlement whose every open order is green now keeps one bubble per food like any other. Collapsing hid exactly the numbers the player had worked to earn, and it was decluttering stacks that item 36 already made rare — a settlement usually has one or two open orders now, not three. Green still recedes on its own, washing lighter and outlining thinner than amber and red. See §10.1, §12, §18.

38. **The player chooses what the region asks for next.** Item 36 opened demand one line at a time but decided the order itself, from an authored schedule gated on a day floor plus a happiness streak -- and both gates were clocks, the streak merely a conditional one. Progression now answers only to delivery: **fill an order and two offers appear; pick one.** Idle for a hundred days and nothing opens; fill something and the choice is waiting immediately. `GameState.day` still drives the day clock, the sun and the report, and drives no progression at all. An order counts as filled when the whole requested amount arrives -- exactly the amber bubble, exactly the point the line starts paying -- with freshness beyond that deciding only how well the player is paid; `min_freshness` still bites implicitly, since spoiled cargo is rejected before it counts as delivered. Filled is latched, so a bad day cannot un-open an order. The two offers are drawn one **deepen** (another food for a settlement already served, reusing its road) and one **expand** (a first order somewhere new, a new road and new upkeep), because two draws from one bucket give a hollow choice while one of each is the standing tension of the genre. They ride as violet plaques on the settlements they would land on and are taken by tapping -- the map is what the decision needs (distance to a source, the river, existing roads), so a modal would cover the one thing worth seeing. The offer not taken goes back in the pool: with twelve lines on the map, discarding one per choice would hide half the content, and keeping it makes a mis-tap cost ordering rather than territory. Candidates are the easiest few remaining of each kind, ranked by a difficulty derived from the map itself (`MapData.difficulty_of`: freshness shortfall over distance to the nearest producing source) rather than authored -- which reproduces the old hand-written teaching order for free. The whole authored schedule is replaced by a single `opening_line`. Draws are seeded per run so a game replays identically, since item 37 left nothing else random. See §6, §4.8, §10.1.

39. **Three opening orders, and an offer that cannot be mistaken for a countdown.** Two playtest fixes to item 38. First, the map opened with a single order, which one short road from the Farm finished -- it taught the drag gesture and left nothing to weigh until the first offer arrived. It now opens with the three easiest lines (Village A's grain and bread, Village B's grain), so there is a real decision from the first minute -- which town first, whether one trunk road serves both -- while staying far short of the twelve-bubble wall. Second, an offer plaque read `Bread / 20/day`, and in the exact spot where the previous design printed `Day 3` that scanned as a duration: it was read as "wait 20 days", when nothing about an offer is a wait at all. It now reads the food name over `+20 · tap`. Per-day was never needed -- every quantity on this map is already per-day, a settlement bubble says `0/20` -- and the shorter lines also fix legibility, since more than about ten characters shrinks to the font floor at map zoom and turns to mush. See §6, §10.1.

40. **A new order opens itself; nothing waits on a tap.** Item 38 put two offers on the map when an order filled and had the player tap one, trading a deepen-or-expand decision for a hard stop: the whole region stalled behind a tap that had to be noticed and understood, and in play it was not -- the plaques were read as something to wait out rather than something to press. Filling an order now simply opens the next one, immediately and silently, announced by the same toast as before. The variety the choice provided is kept by alternating the two kinds of growth strictly (deepen, expand, deepen, ...) rather than rolling for them, since a run of one kind is exactly what makes progression feel arbitrary -- five expansions running leaves five half-served towns and no reason for any of them. `GameState.offers` and `pending_draws` are gone, along with the violet offer bubble, `Kind.SETTLEMENT_OFFER` and the tap handler; nothing on the map now needs pressing to advance the game. Note what this gives up: the deepen-or-expand call is the game's, not the player's. See §6, §10.1.

41. **A place takes up as much of the map as it is big.** Every source and settlement stood on exactly one tile, so a City and a hamlet were the same size on screen and cost the player the same room to route around. A node now carries a `size` footprint: villages and sources stay 1x1, **Town D is 2x1 and City E 2x2**. The whole footprint is unbuildable and a road may connect to any of its cells. The invariant that keeps this from touching the rest of the game is that `Main._nodes_by_pos` (and the engine's `nodes_by_pos`) hold **an entry per occupied cell**, so every cell-based rule -- hit-testing, build guards, the established-route overlay, the never-transit-a-node rule -- keeps working untouched. Two things genuinely had to change. Delivery pathfinding now leaves from ANY cell of its source and arrives at ANY cell of its destination, seeded with every origin cell at zero, since otherwise a 2x2 City's reachability would depend on which corner the map author wrote down; and the transit rule compares the NODE rather than the cell, so a delivery can cross between its own source's tiles without that counting as routing through somebody. Anything that iterates nodes now iterates node IDs: the bubble renderer walked cells, which would have drawn City E's whole stack four times, exactly on top of itself. Markers spawn per cell rather than per node, which is both the cheapest way to make a Town read as bigger and the honest way to show which tiles are taken -- bespoke Town/City meshes are the follow-up. Town D and City E were re-anchored one tile west (to 12,6 and 14,9) so their footprints do not sprawl toward Dairy and Harbor: growing toward a source would have quietly made those lines easier and re-ordered the progression, and this phase is meant to change what the map looks like, not how it plays. `MapData.validate()` now rejects overlapping and off-map footprints, since two nodes sharing a cell would make it resolve to whichever was placed last and hide the other from every build guard. See §12, §16.

42. **Sources can be upgraded, onto ground reserved for it from the start.** Supply was fixed forever, which left region 1 with a food it could never fully serve: vegetables are over-subscribed the moment every line opens -- Village B 25 + Village C 20 + Town D 30 + City E 35 = 110 against the Garden's 90 -- so no network however good could satisfy that demand. The **Upgrade tool** now works on a food source as well as a route: §300 doubles its daily output and widens it from 1x1 to 2x1 on the map. No upkeep, because it is capital rather than a subscription -- a per-day charge for *owning* a source would bleed the player for infrastructure rather than for running it, which is what route upkeep is already for. Reusing the existing Upgrade tool costs no new button and reads as what it is; and unlike the tap-to-accept offer that item 40 removed, this tap is not passive and unprompted, since the player has already chosen a tool that says "upgrade what I touch". **The ground each source would grow onto is reserved from day 1 and permanently unbuildable.** It is deliberately not a "keep it clear or lose the upgrade" rule: a player who paved over it on day 2 and discovered the cost on day 20 would have no way back. Because the cell is blocked rather than merely watched, it is drawn -- a flat translucent patch, since an invisible wall that eats a drag with an error reads as a bug. Each source's growth direction is authored (`NodeData.upgraded_origin`/`upgraded_size`) so the reserved cell sits AWAY from the map's interior, off the obvious lane between that source and its customers: expanding every source blindly east would have put Farm's reserved cell squarely on the road to Village A. `Main` now duplicates the map resource at load, since upgrading mutates NodeData and `load()` hands back a shared cached resource -- without the copy one run's upgrades would leak into the next and into the dev checks. `MapData.validate()` rejects reservations that overlap a node, run off the grid, or are claimed twice. See §4.7, §12.

43. **Sources are two tiles from the start, and nothing is "reserved" any more.** Item 42 held a cell beside each source for its upgrade to grow into, drew it as a translucent ghost, and refused to build on it. In play the ghost read as a strange empty square nobody could identify -- land the player cannot use is far clearer when it is visibly the building itself. Every source now simply **stands on its full 2x1 from day 1**, so the second tile is part of the source rather than ground held back for it, and the whole reservation apparatus is gone: `upgraded_origin`/`upgraded_size`, `reserved_cells()`, `Main._reserved_by_cell`, the special drag refusal and the ghost renderer all removed, along with the validation that policed them. The upgrade itself is unchanged in price and effect but no longer resizes anything -- it just doubles output, which the source's own bubble reports as "0/180" where it read "0/90". Sources are anchored so the footprint extends AWAY from the middle of the map, keeping the cell nearest each source's customers exactly where it was, so wider buildings cost the player no distance. The Garden is the one exception: extending it west put it on column 1 where its speech bubble ran off the edge of the view (TERR-02 keeps sources two tiles clear of the border for exactly that reason), so it extends east instead, which brings vegetables one tile closer to every customer. See §4.7, §12.

44. **A settlement's type now decides how much it can ever want.** Village/Town/City were a free-text `kind` label with no mechanical weight, so a "City" was a village that happened to be spelled differently. Each type now carries a **demand cap** -- Village 2, Town 4, City 5 -- alongside the footprint it already had from item 41, so size on the map and appetite on the ledger say the same thing. The cap is 5 rather than the 8 first proposed because there are only five foods in the game and a settlement cannot want the same one twice; City E wanting **all five** is what "the late objective" can actually mean. `GameEnums.SettlementType` and `NodeData.settlement_type` carry the rule, with `kind` demoted to a display label -- a cap keyed off free text is no rule at all. Nothing enforces the cap at runtime: the order book only ever opens lines that are already authored, so `MapData.validate()` is the whole enforcement, and it now rejects a settlement written past its type. Town D and City E were filled to their budgets, which is what makes the cap mean anything: **Town D gains grain (20) and City E gains grain (30) and bread (30)**, taking the region from 12 demand lines to 15. That is what turns source upgrades (item 42) from a single-purpose fix into an economy: grain goes to 85 against the Farm's 80 and bread to 95 against the Bakery's 80, so three of the five sources -- Farm, Bakery, Garden -- now have demand they cannot meet un-upgraded. Milk and seafood keep their slack; reaching them would mean raising an authored amount rather than adding a line, which is a balance decision rather than a structural one. See §4.8, §12.

45. **The region becomes the stage: region 1 is retired to a tutorial, and the main game is a roster of climates.** One region was always the MVP's scope, not the game's, and it has now taught everything it can -- every system in §4 is reachable on it, so the endless efficiency chase (item 0.2.5) is the only thing left to do there. The main game is a **roster of regions**, each unlocked by grading well on the last, each keeping its own best grade/score and its own treasury (a region is a run, not a save file the player carries between maps).
    What separates one region from another is deliberately **not** which city it depicts. The obvious model here is a map roster themed on cities, where each map's flavour is a street/coast/river silhouette; copying that would make this a city game with food trucks, and it also throws away the one axis this game has and that one does not -- **cargo that degrades, at rates that differ 12x across the food set** (grain 0.5/tile, seafood 6.0). So a region is a **landscape and a climate**, and the climate reaches into the freshness maths: `MapData.climate_decay_mult` scales every food's per-tile decay for the whole map, so the same five foods play differently region to region. A cold region is where seafood finally travels; a hot one is where cool storage stops being optional and short beats clever. Regions are named for the land, not the town (§12.1).
    Three supporting changes make the roster authorable. First, **terrain becomes a per-cell grid** rather than `river_col`, an int from which `get_terrain(x, _y)` derived a whole column while ignoring `y` entirely -- region 1's river is now authored into that grid like anything else, and `river_col` is retired (§8.1). Second, **§8's original terrain table is superseded**: it gave Mountain "high cost *and* more decay", which is strictly worse than plains in both terms, so no player would ever route through it -- that is a wall, and water is already the game's wall. Mountain is now expensive to build but **preserving** (cold air), which makes the short expensive path genuinely compete with the long cheap one; Snow keeps the cost and gains a **capacity** penalty, which is an axis no other terrain touches (§8.2). Third, a `BLOCKED` terrain gives a map author unbuildable non-water ground -- cliffs, and the walls that turn Oldwall's City into a gated funnel (§8.4).
    Region 1 itself is **unchanged in content**: same grid, same nodes, same demand, same opening lines. It is relabelled the tutorial region and its river is re-authored into the terrain grid, and nothing about how it plays moves. The §6 chapter list stays the full-game teaching order it always was; the roster is what actually delivers it, one region per lesson rather than one chapter per unlock. See §8, §12.1.

46. **A scripted tutorial stage, gated on doing rather than on pressing Next.** Item 45 labelled region 1 the tutorial, which was true of its difficulty and false of everything else: it teaches nothing. Nine build rules have accreted onto the route drag alone (items 15, 18-22) -- press and *hold* an anchor, and only a source, a hub or an unestablished tile; release only on a hub, a settlement or an unestablished tile; every cell between must be empty ground -- and a player meets all of them at once, on a map showing five sources, five settlements and a 60-second clock. **Millbrook** is a new, smaller region 0 that introduces them one at a time, and region 1 becomes the first free-play region rather than the tutorial (revising item 45's roster on that one point; the roster is otherwise unchanged).
    **Steps complete when the player does the thing, never on a tap.** Each of the nine steps names a condition over game state -- this road is established, this line filled, this line came in green, no tile is over capacity -- and ends the moment it holds. This is item 40's rule applied to teaching: that item deleted a tap-to-advance because the plaques "were read as something to wait out rather than something to press", and a Next button is the same object with a clearer label. It also means a step cannot be dismissed unread, and that the tutorial is impossible to desynchronise from the map, since the map *is* the progress bar.
    **The whole step machine is a read-only observer.** Every condition it needs is already tracked: `GameState.filled_lines` (already latched, item 38), `last_settlement_status`, `last_congestion`, `connections`, and `NodeData.upgraded`. No new simulation state, and nothing in `SimulationEngine` learns that a tutorial exists. Completion latches for the same reason `filled_lines` does -- bulldozing a step-1 road on step 7 must not throw the player back to step 1 -- but a broken condition on the *current* step re-shows its instruction, so a mistake made now is still corrected now.
    **It cannot be failed or lost.** There is no bankruptcy or loss condition anywhere in the build, so this costs nothing to guarantee. Tools are *revealed* step by step rather than disabled with an error, the clock stays off until the step that introduces it, and Bulldoze is available from step 1 as the escape hatch. It is skippable from region select and replayable afterwards, and skipping still unlocks region 1 -- a tutorial that gates content is a toll.
    Millbrook is authored so the lessons fall out of the map's own numbers rather than being narrated: milk to Village B lands **amber at 68%** on eight tiles, so the player succeeds and is shown that succeeding is not the ceiling; Cool Storage takes the same run to **89%** and green. Grain 65/day down one Dirt trunk against a 60 cap teaches capacity, and milk demand 45 against the Dairy's 40 teaches source upgrades -- two different foods, so "the road cannot carry it" and "the farm cannot make it" are never the same day's problem. `MapData.opening_lines` holds exactly one line here, not item 39's three: that argument was about a free-play map giving the player nothing to weigh, and a scripted tutorial supplies the weighing itself. The order book's deepen/expand alternation (item 40) is disabled on this map, since the step list decides what opens and when. See §12.2.

47. **The map's default layer is glyphs; the bubbles come back on hover or tap.** Every node floated a full balloon per open order, permanently -- and past a couple of orders that buries the thing the balloons are describing. A settlement drew one balloon per line, two to a row (`Main._bubble_column_offset`), so City E's five wrapped into three rows over its own footprint, beside Town D's four; the roads, terrain and route overlay underneath were what paid for it. At rest a node now draws a compact **glyph strip** -- one food silhouette per open order on a small dark plate, each carrying its ✕/!/✓ status mark -- and the full balloons, numbers and freshness bar and all, come back for whichever node the player is hovering or has tapped.
    **A food had no name on the map, only a colour, and colour could not do the job.** `set_settlement` took an icon colour and an amount and no food name at all, so a single coloured dot was the entire identity of five foods -- and the palette does not support that: milk (`#EDEFE6`) against the cream bubble body (`#F7F0DE`) is a contrast ratio of about **1.02:1**, meaning the milk dot was effectively invisible, and grain (`#D9C36A`) against bread (`#C89A5B`) are adjacent mid-golds. So shape takes over identity. Each food gets one silhouette -- **a wheat ear, a loaf, a carrot, a bottle, a fish** -- used everywhere that food appears, on the source sign and the settlement balloon as well as the strip, which is what makes it learnable rather than decorative: the mark on the Harbor's sign is the mark on City E's bubble. Every glyph is stroked as well as filled, and that stroke is what rescues milk: a near-white bottle on cream stays legible by its edge when its fill does not.
    **Severity decides the order.** Red, then amber, then green, ties broken by the shortfall as a fraction of what was asked for -- so a village 5 short of 10 outranks a city 5 short of 40, being the closer to failing. The leftmost glyph on a strip, and the first balloon in an expanded stack, is therefore always the line most worth acting on; before this the order was whatever the demand dictionary happened to iterate. This also extends item 30's existing language rather than inventing one, since green already recedes there by washing lighter and outlining thinner.
    **The strip is not interactive, and nothing new is.** Expansion rides the hover/tap that already opens the info tip (§10.6, §0.4.1) -- there is no new tap target, no picking against billboards, and no sub-rect hit-testing inside a baked texture. Bubbles have never had picking of any kind and still do not.
    **This is a collapse, which item 37 removed once, and it is a bigger one than that was -- so note honestly what it costs.** "All fresh" hid a settlement's numbers only when every line was green, which is to say it hid good news at the moment it was earned, and it hid it inconsistently while other settlements stayed loud. This hides the delivered/requested figures and the freshness bar at *every* node until one is inspected. Three things carry it. The status mark still gives the verdict -- green is the full amount at or above that settlement's own bonus freshness, which is the same question the bar's tick was answering. It is uniform, so no node is being singled out. And the **Bubbles control becomes three-state -- Glyphs / All / Off** -- so the old dense view is one click away for a player who wants every number on screen at once, which costs almost nothing because both renderers are the same scene. Mobile pays more than desktop here, since hover is free and a tap is deliberate; that asymmetry is real, and the All mode is the answer to it.
    A node with one open order draws a one-glyph strip, and sources -- one food each (item 0.2.6) -- always do. A source's strip carries no status mark: spent-versus-stocked is already said by the glyph fading, and a ✓ beside it would read as a delivery verdict a source never has. See §10.1, §16.

48. **Icons get four times bigger, a source is always its glyph, and a settlement's text tip is retired.** Three follow-ups to item 47, all from seeing it on a phone.
    **Size.** A one-glyph strip came to roughly ten screen pixels on a phone-width view of the whole region -- below the point at which any silhouette resolves, so the glyphs were unreadable in exactly the situation they exist for. `STRIP_GLYPH_RADIUS` goes from 19 to **76**. The increase is *native*, not a sprite scale: `setup_glyph_strip` now sizes the marker's SubViewport to fit its contents, so a bigger glyph is drawn at a bigger resolution and stays sharp rather than being a magnified small texture, and a one-glyph source stops carrying a texture wide enough for five. Gap and padding grow well under 4x deliberately -- at full 4x a five-order City would have spanned about four tiles, and keeping the spacing tight holds the widest strip near three while making the row read as one object instead of separate badges.
    **A source is always its big glyph.** The dark slate sign on a post is retired outright -- `set_source`, `_draw_source`, the outgoing-supply arrow, the stem/foot and the whole `SOURCE_*` palette are deleted, since nothing calls them once a source never expands. A source's identity is the food it makes, and a glyph says that faster and smaller than a sign printing "21/80". What that sign uniquely carried -- how much of today's produce has actually been drawn -- would otherwise have been lost, since the map glyph only distinguishes spent from stocked by going grey, so it moves to the source's hover tip as a "Drawn today: 21/80" line. The source tip stays for a second reason: it is where the player discovers source upgrades exist at all (item 42).
    **The settlement's detailed description is retired.** Hovering or tapping a settlement expanded its glyph strip into full balloons *and* opened a text panel repeating the same delivery in words -- the balloons already carry delivered/requested, the freshness percentage, and the bar ticked at that settlement's own bonus threshold, so the panel was saying it twice. `_settlement_tip_text` is deleted and a settlement no longer opens the tip at all; the balloons are the detail view. Sources, routes, storage, hubs and bridges keep their tips.
    Note what the text panel took with it, because the balloons do not carry all of it: the settlement's **`min_freshness`** (the reject threshold -- the bar still ticks `bonus_freshness`, which is the line that pays), the **"May order later"** list of demand lines not yet opened (item 36), and the **"N arrived too spoiled to accept"** rejection figure. The first is inferable from a rejected delivery, but the other two are genuinely gone from the map and now exist only in the day report. If the still-to-come list turns out to be load-bearing for planning, it wants somewhere better than a hover panel anyway. See §10.1, §10.6.

49. **One design language: a vertical column of status-coloured chips, expanding into balloons that share their palette.** Item 48's horizontal strip and item 30's cream balloon were two unrelated looks bolted together, and the strip had a shape problem besides.
    **The collapsed view is a vertical column of chips, one per open order.** Horizontal was wrong for the map: a five-order City spanned three-plus tiles sideways, straight across whichever neighbour sat beside it -- and settlements crowd each other horizontally far more than vertically, because the space *above* a node is usually empty map. Stacking downward costs nothing anyone else was using. Severity still orders them, so the **top** chip is the line most worth acting on.
    **A chip is a food glyph on a status-coloured background.** The colour is the point: red, amber and green are readable as a *background* at map distance in a way a corner badge never was. Note this is allowed here precisely because a chip carries **no text** -- item 30 kept status off the balloon body because a saturated ground under dark text forces every status pale enough to read on, which is exactly what made red and green converge. The tint is pulled 42% from slate toward the status colour, which keeps it dark enough that every food glyph holds its contrast: the worst cases are a green carrot on a green chip and gold grain on an amber one, and both survive on the strength of the glyph's light outline (item 47's stroke rule, earning its keep a second time). The ✕/!/✓ mark stays even though the background now says the same thing, because shape is the colourblind guarantee and it should not depend on hue at all.
    **The balloon takes the same palette.** It was cream with dark text; it is now the chip's dark, status-tinted ground with light text, so the thing a hover expands into is visibly the chip it grew from -- which is what "consistent" has to mean if one turns into the other. Inverting to light-on-dark is also what lets the tint be strong: the constraint item 30 was working around only exists for dark text. `BUBBLE_COLOR`, `STATUS_WASH_ALPHA` and `GREEN_WASH_ALPHA` are gone with the cream.
    **A source is a different object, by shape as well as colour.** A settlement chip is heavily rounded, status-tinted and carries a status mark; a source chip is **near-square, neutral slate, and carries no status anything** -- a source has no delivery to be judged on and must not look like it does. That reinstates the corner-radius language the retired balloon/sign pair used to carry (item 30), now as the only thing distinguishing two chips rather than two whole silhouettes. See §10.1, §16.

50. **Collapsed and expanded are one column at two widths.** The chips and the balloons were laid out by unrelated machinery -- chips as rows inside one baked texture, balloons as N separate world-space markers -- so their row pitches were computed in different units and could only be lined up by hand. Worse, the balloons' pitch had to fight the camera: at a -60 degree pitch a world-Y step buys only half its length in *screen* separation, which is the whole reason `CAMERA_VERTICAL_COMPENSATION` existed. **Both are now one baked texture**, and the compensation problem is deleted rather than managed -- `STACK_SPACING`, `COLUMN_SPACING`, `CAMERA_VERTICAL_COMPENSATION`, `WORLD_WIDTH`/`WORLD_HEIGHT` and `Main._bubble_column_offset` all go with it.
    **The layout rule is that nothing the eye tracks moves.** A row is the same height and sits at the same pitch in both states; the food glyph occupies the same leftmost square cell of a row either way; the status mark stays pinned to that cell rather than sliding to the far edge when the row widens. Expanding only *adds* -- the amount, the freshness percentage and the bar, in space a chip does not have. `BubbleCanvas.column_size(count, expanded)` deliberately returns the same height for both, so row *i* lands at the same screen height whichever state it is in, and the balloon column is nudged right by `column_x_shift()` -- exactly half the width it gained -- because the sprite is centre-anchored and widening it would otherwise slide every glyph left. The result reads as the chip unfurling to the right rather than one object being swapped for another, with no animation involved.
    **One tail per column, not one per row.** Five balloons meant five tails pointing at nothing in particular. The column now hangs a single tail, and it hangs from the *glyph cell's* centre rather than the panel's, so it keeps pointing at the node when an expanded panel widens. It takes the bottom row's colour, since it reads as part of that row; overall severity is already the top chip's job. Sources get no tail at all -- that is a settlement's tell, the way the post used to be a source's.
    **The expanded column is narrower than what it replaces.** Five orders used to occupy a 2x3 grid roughly 6.2 world units wide; one column is about 3.1 wide and 7.4 tall. Taller, but width is what costs on this map -- settlements crowd each other horizontally, and the space above a node is usually empty. The tallest case is a five-order City at roughly 3.7 tiles, and it is transient. If that proves too much in play the answer is an accordion, expanding only the row under the pointer -- which needs per-row hit-testing, the billboard-picking problem every version of this feature has deliberately avoided. See §10.1, §16.

51. **The freshness bar was unreadable, and reported as "freshness looks 0".** Two faults, both introduced by the redesign rather than by the bar's own logic. **Size:** `BAR_HEIGHT` stayed at the 9px it was authored at for the old 310x150 balloon while rows went 4x bigger and `pixel_size` dropped from 0.01 to 0.0072 -- leaving the bar about 28% *smaller on screen* than before the redesign, inside a row four times the size. It is now 24px. **Contrast:** item 49 inverted the palette to light-on-dark and flipped the bar's colours to translucent white without re-tuning them, leaving the track at 0.17 alpha and the not-yet-counting fill at 0.34 -- two near-identical washes, so a 90% bar looked like an empty one. The track is now a dark recess (black 0.30) cut into the tinted body, and the inert fill lifts to 0.58, which puts a real step between them. The dead `BAR_INSET` (superseded when the bar started taking an explicit rect) goes too.
    Worth recording what was *not* a bug, since it prompted the report: a line reading "25/30, 90% fresh" with a **red** ✕ is correct. Red means the order came up **short**, not spoiled -- and per §9 a short order pays nothing at all however fresh what arrived was, so that line earned zero. The freshness is still worth showing on a short line, because it says the route is fine and the shortfall is a supply or capacity problem rather than a distance one. But red beside "90% fresh" reads as a contradiction, and the row does not currently say by how much it fell short. See §10.1.

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

1. Draw a route (drag-only, starting from a source or a built hub and ending at a hub or a settlement).
2. Place storage on an existing route.
3. Build a hub on any existing route tile (v0.5 item 17: manual, capped at 2 per network).
4. Upgrade or remove route and hub infrastructure.

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

This full-screen report is shown at the end of a **manually** run day. A day the clock runs by itself (§3.5) posts a compact, self-dismissing summary card instead -- the auto-run loop can't stop for a dialog every day -- and this full report stays available on demand from the day clock panel (§10.8).

### 3.4 Upgrade phase

The player spends profit or reputation to unlock:

- New food sources.
- New settlements.
- Storage upgrades.
- Hub upgrades.
- New regions.
- Route improvements.

### 3.5 Day clock (added in v0.4 item 24)

The planning phase (§3.1) is not open-ended. Each day is a real-time countdown, and the simulation phase (§3.2) fires when it expires:

- **Day length:** 60 real-time seconds at 1x speed. The clock starts full on day 1 and restarts full after every simulated day, including one the player runs early.
- **Auto-run (default):** at 0:00 the day simulates itself, the day counter advances, and the next day's clock begins immediately. The player never has to press anything to keep the game moving, and can keep drawing routes, placing storage, building hubs, and bulldozing while the clock drains.
- **Speed:** 1x / 2x / 4x multipliers on the drain rate, for players who don't want to wait out a day they're happy with.
- **Pause:** holds the countdown indefinitely (spacebar or the Pause button). Building is still allowed while paused, which is the deliberate "stop the pressure and think" affordance.
- **Run early:** running the day by hand simulates it immediately and restarts the clock. Running early spends the rest of the day's build time -- it does not bank it.
- **Manual mode:** switching Auto off stops the clock entirely and restores the older loop, where a day only runs when the player asks and the blocking report's "Continue to next day" is what advances the calendar.

The clock is frozen while the full-screen report (§3.3) is open, so reading a report never costs the player build time.

### 3.6 Time-of-day lighting (added in v0.4 item 29)

The day clock also drives the light, so one in-game day is one full sun cycle rather than a fixed midday:

| Phase | At | Clock | Sun | Look |
|---|---:|---|---|---|
| Dawn | 0.00 | 5:00 am | low, -12 deg | warm orange light, grey-blue sky, dim, long shadows |
| Morning | 0.18 | 8:00 am | -35 deg | bright warm light, clear sky |
| Midday | 0.40 | 12:00 pm | high, -70 deg | white light, brightest moment, shadows tucked under objects |
| Afternoon | 0.60 | 3:00 pm | -45 deg | warm light, still bright |
| Sunset | 0.76 | 6:30 pm | low, -12 deg | strong orange light, orange horizon, long raking shadows |
| Dusk | 0.88 | 8:00 pm | -8 deg | violet light, deep blue sky |
| Night | 0.95 | 11:00 pm | -50 deg | dim blue moonlight, darkest moment, faint shadows |
| Dawn | 1.00 | 5:00 am | low, -12 deg | identical to 0.00 -- the cycle joins up |

- **Phase is the day clock's own progress**, 0 at the start of a day and 1 as it rolls over. Values between keyframes are interpolated, so the change is continuous rather than stepped.
- **The cycle joins up at the rollover.** The first and last keyframes are the same moment, so night falls in the last stretch of a day and the sun rises exactly as the clock reaches 0:00 -- "Day N" always opens at dawn, and the sky never snaps.
- **A stopped clock holds the light.** Pausing, or switching to manual mode, freezes time of day too: the light is the clock, so freezing one freezes the other.
- **Night stays playable.** Ambient light never drops to zero, so the map, routes and overlays remain readable in the dark; the UI, speech bubbles and route overlay are unshaded and unaffected throughout.
- **Shadows travel with the sun.** The sun sweeps a full turn over the day (its yaw runs from +78 deg round to -282 deg, the same orientation one turn on, so the sweep never doubles back or snaps at the rollover), and shadow strength rides the same curve: crisp at midday, softer at dawn and dusk, barely there under moonlight. Long raking shadows near sunrise and sunset are the point, so the shadow range is set wide enough to hold them.
- **Shadows are desktop-only.** A browser hands the page a far smaller GPU budget than a native build, and overrunning it doesn't degrade gracefully -- the browser destroys the WebGL context and the game dies with "WebGL context lost, please reload the page". Shadows are the largest allocation the scene asks for, so the web build runs without them (`DayCycle.shadows_available()`); everything else in the cycle -- sun angle, light colour and energy, sky and ambient tint -- still runs, so a web day still visibly moves from dawn to night. Desktop keeps full-quality shadows: a 4096 map (2048 on native mobile) over a range just wide enough to cover the region from any in-game zoom or pan (70 units), since a wider range spreads the same map over more ground and aliases the grass block's corner tufts into a diagonal hatch.
- **The clock panel reads the wall-clock time** beside the day number -- "Day 3 - 6:45 pm" -- with the phase name on the line below (§10.8). A day opens at 5:00 am and the clock runs round to 5:00 am again as it rolls over.

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

### Transactional route placement (added in v0.3, revised in v0.4)

A route-building click is evaluated before it changes the map. The game calculates the tile's cost (route plus any bridge surcharge) and checks it against the topology.

```text
required_cost = route_tile_cost + optional_bridge_cost
```

The route tile is established only when both rules hold:

- The tile is empty and adjacent to the existing network or a node.
- The player can afford the tile's cost.

If either check fails, nothing is created and no treasury is deducted.

**The hub cap no longer gates placement (revised in v0.4).** Hubs are a separate, player-initiated action on any existing route tile (see §4.4), never created as part of placing the route tile itself. So a route placement is never rejected on hub-cap grounds — the road is always buildable, and building a hub on any of its tiles afterward is a distinct decision subject only to the per-network cap.

### Route tile visual design (added in v0.4 as directional shapes, replaced with one symmetric mesh per level in v0.5 item 23)

Each route level (Dirt, Paved, Main) renders as a single, radially symmetric
mesh, the same regardless of a tile's connections, shape, or facing:

- **Dirt**: a tan base with a centered square worn-earth patch and four
  small corner pebbles.
- **Paved**: a grey base topped with four raised cobblestone pavers (the
  original design -- this is what the other two levels were brought in
  line with).
- **Main**: a dark base with a pale painted cross (both axes, not a single
  directional line).

Because each of these reads identically under any 90-degree rotation, one
mesh per level covers every route tile everywhere on the map -- a straight
run, an L-bend, a dead-end stub, a 3+-way junction, all look the same at
that level. There is no corner variant, nothing is rotated at render time,
and there is no player override of any kind (the old tap-to-cycle-shape
feature that let a player flip between 6 directional shapes was retired
separately, v0.5 item 21). This replaces the earlier "auto-derived
directional shape" system (`SimulationEngine.route_shape()` and its
shape-family/facing computation), which is removed entirely -- a route
tile's rendering is now just `level -> mesh`, with no notion of shape or
facing left anywhere in the codebase.

### Explicit connections, and drawing a route by press-and-hold-to-drag (added in v0.4, revised in v0.5, start/end/interior restricted in v0.5 items 18-20)

**Connectivity is never implied by two cells simply sitting next to each
other.** Two route tiles, or a route tile and a node, are only linked for
gameplay purposes (pathfinding, hub-cap networks, established routes,
upkeep discount, route shape) if the player has explicitly drawn that link
by dragging across the boundary between them (see §16's `connections`).
This replaced the original position-adjacency model specifically because it
let two independently-drawn, side-by-side routes merge into one network
just by touching, sharing a hub-cap budget and upkeep discounts neither
route asked for.

**Tapping a route tile (or empty ground) never does anything but explain
that a drag is needed** (v0.5 item 21 retires the old tap-to-cycle-shape
feature) -- it never places, connects, or reshapes a tile. All route
creation is drag-only:

1. Press and hold on a valid anchor -- a source node, a built hub tile, or a
   route tile that ISN'T part of an established route yet -- for a short
   moment (roughly a third of a second) without releasing to switch into
   drag mode. A press on a settlement, empty ground, or an already-
   established route tile is not drag-eligible: every route must trace back
   to a supply point, or continue unfinished infrastructure that isn't
   serving any delivery yet (v0.5 items 18, 22).
2. Dragging the pointer traces a candidate path across further cells, drawn
   live as a translucent line so the player can see it before committing to
   anything.
3. **Every cell strictly between the start and end anchors must be empty
   ground** (v0.5 item 20) -- a new route can never cross or reuse an
   already-built tile or a different node partway through. Each such cell
   becomes a new tile to build, and each consecutive pair (including the two
   ends) becomes a connection to record. The running cost only counts these
   genuinely new tiles, and must fit the current treasury (the hub cap never
   blocks a placement -- see §4.4).
4. **The path's LAST cell must be a hub tile, a settlement node, or likewise
   an unestablished route tile** (v0.5 items 19, 22) -- a drag that releases
   on an already-established route tile, or on empty ground, is invalid, no
   matter how far it traveled or how affordable it was. This is what
   guarantees every committed drag either reaches a genuine delivery
   destination or joins onto unfinished infrastructure -- never a route that
   silently stops one tile short of the node it looked like it was reaching,
   and never one that piggybacks mid-network onto a route that's already
   live. The preview line renders green only once the affordability,
   interior, and end-point checks all pass, red otherwise, explaining why in
   a toast if the player releases while it's red.
5. **Only a fully valid path is committed, and only on release** -- an
   invalid path places and connects nothing at all. On a valid release,
   every queued tile and connection is written at once. A press that
   releases before the hold threshold, or one that never actually drags to
   a second cell, is an ordinary tap on the anchor (info tip for a node,
   just a hint for a route tile) -- never a build.

Because the interior must be empty ground, the only pre-existing cells a
drag ever touches are its very first and very last -- there's no way for a
new route to physically overlap an unrelated existing one. Two separately-
built roads, or a road and a node, only ever get linked by a drag that ends
exactly ON that shared hub, settlement, or unestablished route tile --
never by crossing through the middle of one another. The one exception is a
**bridge**, a structure the player places and pays for first, which a drag
may then run straight over without the two routes joining (see below).

### Bridges: crossing a route without joining it (added in v0.5 item 32)

The interior-must-be-empty-ground rule above has exactly one exception, and it
is a structure the player pays for and places deliberately: a **bridge**.

A bridge is not drawn as part of a route drag. It is a **placed structure**,
built with its own tool onto **one existing route tile**, the way a hub is
(§4.4). It turns that tile into a road-over-road crossing: the road already
there keeps running underneath, and a raised deck spans it at right angles. A
later drag may then run **straight over the deck**, and the two routes share
that cell without ever becoming one network.

Making it a placed structure rather than an automatic side effect of a drag is
the point. A crossing becomes a purchase the player decides on and can see on
the map before anything is drawn over it, instead of something that quietly
happens whenever a drag wobbles across an existing road — which is what would
turn the map into spaghetti.

**Placement rules.** A bridge may only be built where "across" is unambiguous
and the result stays legible:

- The tile must be an existing plain route tile carrying a **straight
  through-run** of road — exactly two connections, pointing opposite ways. No
  corners, forks or dead ends, and never a hub, storage tile or river crossing.
- Both tiles the deck would land on must be **on the map and not a node**. A
  delivery never passes through a source or settlement (§4.7), so a deck can
  never land on one.
- **No two bridges may land on each other**, which stops decks butting
  end-to-end into a continuous elevated road.
- A connected road network supports at most **2 bridges**. An existing bridge
  counts against both networks it serves — the road beneath it and the route
  across it — so approaching from the other side does not reset the budget.
- Nothing else can be built on a bridge tile afterwards, and a route drag may
  neither start nor stop on one: a crossing is passed over, never anchored to.

**Crossing rules.** Once the structure exists, a drag may cross it only
**straight through, along the deck's own axis** — entered and left in the same
direction. Turning a corner on top of somebody else's road is invalid, as is
stopping on the deck. The crossing route pays only for the fresh ground either
side; the bridge itself was paid for when it was placed.

**Bulldozing.** A bridge is a structure on top of a route tile, so clearing one
takes only the structure: the tile survives as a route tile at the level it
already was, still carrying the road that ran underneath, and only the deck's
connections are dropped. The route that crossed over is cut at both ends. Merging it into
the road below instead would silently join the two networks the crossing was
built to keep apart. Hubs follow the same rule (§4.4).

**Costs.** §60 to build, plus §6/day upkeep on top of the road's own (the deck
is a structure, so its upkeep is not discounted by an adjacent hub). Crossing
the deck costs **2× the usual freshness decay** for that tile — ramping up and
back down is roughly one extra tile's worth — so an overpass loses to a short
detour and is only worth it when going around would be genuinely long. Capacity
belongs to the tile, so both roads share one throughput budget.

Together the price, the upkeep, the freshness penalty and the per-network cap
are what keep crossings rare and deliberate. Going around remains the right
answer most of the time; a bridge is for when it genuinely isn't.

### Bulldozing a structure leaves its road behind (added in v0.5 items 33, 35)

Bulldoze used to erase whatever cell it was pointed at, connections and all.
That is right for a bare route tile, but wrong for a **hub**, a **storage
building** or a **bridge**: all three are structures built *on top of* an
existing route tile, so taking one away should not also swallow the road it was
built on and split the network in half.

Clearing a hub, a storage building or a bridge therefore removes only the
structure. Clearing the road it stood on is then a second bulldoze -- which is
the point: taking a building down is a different act from taking the road away,
and one click should not silently do both. The tile
survives as a route tile with its connections intact — the road keeps running
through it — **at the level it already was**, Dirt, Paved or Main. The player
paid for that paving separately from the structure and never asked to lose it,
so bulldozing the structure hands the road back as it found it. A bridge tile
carries its own level throughout; a hub cell replaces the route cell outright,
so it records the level it covered at build time in order to give it back.

A bridge additionally drops its **deck** connections while keeping the road
beneath it. The deck is the road that ceases to exist, so the route that
crossed over is cut at both ends; without that step, the two roads the crossing
was deliberately keeping apart would silently merge into one network the moment
it came down.

The sweep tool (below) applies exactly the same rule to every tile it crosses.

### Sweeping bulldoze and upgrade across tiles (added in v0.4 item 26)

Bulldoze and Upgrade are **sweep** tools: dragging either one across a run of tiles applies it to every tile the pointer crosses, instead of requiring a click per tile.

- **Starts immediately on press.** There is no hold threshold, unlike a route drag. A sweep only ever acts on tiles that already exist, nothing is applied until release, and the preview shows exactly what will happen first -- so there is nothing to protect against, and skipping the hold keeps the gesture clear of the long-press that mobile browsers intercept.
- **A tap is still a tap.** A press released without ever reaching a second cell performs the ordinary single-tile action, exactly as before.
- **Cells the tool can't act on are skipped, not fatal.** Empty ground under a bulldoze sweep, or a route already at Main under an upgrade sweep, is simply passed over -- a slightly wobbly drag across a road still does the obvious thing.
- **All or nothing on cost.** An upgrade sweep whose total exceeds the treasury applies to nothing at all, matching the route drag's transactional rule. The preview turns gray while it is unaffordable, so the player can shorten the sweep before releasing rather than being surprised by a rejection. Bulldoze costs nothing and can never be blocked this way.
- **One level per tile per sweep.** A tile crossed several times in one gesture is still upgraded once.

The preview colour says what the tool will do: red markers on the tiles a bulldoze sweep will clear, green on the tiles an upgrade sweep will lift, gray when the sweep is blocked and will do nothing. A faint line traces every crossed cell, affected or not, so the gesture reads even where it passes over empty ground.

### Overlay colour by source (added in v0.4 item 27)

The established-route overlay (below) draws one **lane per source**, in the colour of the food that source produces:

- **A tile is attributed to a source when that source can reach a settlement *through* it**, not merely when they share a road network. Attribution runs the established-route computation once per source, counting only that source as a starting anchor -- so a spur that only one source feeds unravels in every other source's pass, and never takes their colour.
- **Shared roads carry several lanes at once.** Where two sources' deliveries run down the same road, both colours run down it side by side, evenly straddling the road's centre; a lone source runs down the middle. The lanes are laid out perpendicular to each link, so they stay parallel along the whole shared stretch, and a link between two tiles carries exactly the sources both tiles have.
- **Route tiles themselves are not recoloured.** They keep their ordinary Dirt/Paved/Main appearance -- colouring the road surface as well was tried and dropped: it fought with the level colours, and the overlay is where "which supply is this" belongs.
- **The endpoints stay distinct regardless of colour:** a green arrow at the source end (pointing the way delivery flows) and a red bar at the settlement end.
- **The legend lists the mapping**, generated from the region's own sources rather than hardcoded, so it can't drift from what is actually drawn.

Colour comes from the *food* rather than the source marker because every source marker shares one colour (§16), so the food is the only thing that visually distinguishes one source from another -- and it matches the colours already used by the source/settlement speech bubbles (§10.1).

### Established-route overlay (added in v0.4, endpoints marked in v0.5)

A bright gold line is continuously overlaid on top of the map along every
route tile that lies on a **complete source→settlement path**, so the
player can see at a glance which roads actually link a source to a customer
rather than dangling unfinished. It is purely informational and never
changes simulation or cost.

The set of highlighted tiles is derived from the same connectivity graph
the simulation uses (built tiles plus the nodes they're explicitly
connected to -- see "Explicit connections" above and §16):

- Keep only tiles whose connected network contains **at least one source
  and at least one settlement** -- a network with no customer, or no
  supplier, is not an established route and stays unmarked.
- Within those networks, iteratively drop any tile that dead-ends (one or
  zero links to another kept tile or a node). This strips off stub
  branches that lead nowhere, leaving only the through-paths that actually
  run between endpoints.
- The line reaches into the source and settlement nodes each kept tile
  connects to, so a finished route reads as one continuous strand from
  supplier to customer.

**The two ends are visually distinguished, not just gold like the rest of
the strand:** the source end shows a green arrow pointing in the direction
delivery actually flows (source → first tile), and the settlement end shows
a red bar instead of gold, so the player can tell start from finish at a
glance without having to trace the whole line.

The overlay is rebuilt on every render, so it stays live as the player
edits the network or runs a day.

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

Storage buildings preserve food freshness. There are two storage types:

1. Normal Storage
2. Cool Storage

(A third, Freeze Storage, was retired in v0.4 item 28 -- see §4.3.3.)

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

## 4.3.3 Freeze Storage (RETIRED in v0.4 item 28)

**Freeze Storage no longer exists in the build.** It was an expensive third storage tier (400 to build, 80/day upkeep, 70 capacity, 14-tile protection distance, 0.10x loss multiplier) aimed at seafood and long-distance chains, paired with a "freeze-sensitive food" rule that docked quality from foods that dislike freezing (Bread -4, Vegetables -8, Milk -10) so it couldn't be the answer to everything.

Both are gone: the storage type, its balance entry, the `freeze_penalty` food field, and the penalty branch in the freshness simulation. Storage is Normal and Cool only. Seafood, which this tier existed to serve, now relies on Cool Storage and short routes like everything else -- worth watching in playtests, since it is the fastest-decaying food in the set.

Kept here rather than deleted so the numbers are recoverable if the tier is ever revived.

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

### Manual hub construction on any route tile (revised in v0.4 item 14, simplified in v0.5 item 17)

A Small Hub can be built on **any existing route tile** with a dedicated **Build Hub** tool: the player draws a route first, picks the tool, then clicks the route tile they want to convert, paying §150. There is no "completed-route fork" or branch-count requirement any more -- a plain straight run, an isolated stub, or an unfinished route that reaches no settlement are all valid hub sites, exactly like any other route tile.

The **only** remaining constraint is the per-network hub cap (below), checked live against the tile's connected road network at the moment the player clicks -- there's no precomputed `junction`/`hub_capped` flag to go stale. If the network is already at its cap, the Build Hub tool refuses with an explanation instead of charging anything.

**Route placement itself is never blocked by the hub cap**, and never blocked by hub cost either -- the player can always draw roads; building a hub anywhere on one is a separate, always-available action subject only to the cap.

```text
hub_adjusted_route_upkeep = adjacent_route_upkeep * (1 - hub_discount)
net_savings = route_discount_savings - hub_daily_upkeep
```

### Hub cap per connected network

Each connected road network can support at most **2 built hubs**. A network is a maximal set of orthogonally-connected built tiles (route, storage, and hub). Source and settlement nodes are terminal endpoints for flow, not transit tiles, so they never join two road groups into one network: **two road groups that touch only a shared source/settlement are separate networks with separate hub budgets** (revised in v0.4). A delivery can't cross a node, so the cap can't leak across one -- building a junction on a small road hanging off a source is never blocked just because some other road on that same source is already at the cap.

- Any route tile in a network already at the cap stays a plain, capacity-limited route tile -- the Build Hub tool refuses it there, and no cost is charged for the attempt.
- The player receives a clear explanation that the network has reached its hub cap.
- Route placement is never blocked by the cap; the player can reroute, keep networks separate, or remove an existing hub-bearing branch to free budget.
- Existing networks created by older versions or imported data should be validated separately; the MVP does not need migration logic.

This preserves the topology decision: keep networks physically separate to receive independent hub budgets, or merge them and accept a maximum of 2 hubs.

### Suggested hub levels

| Hub type | Build cost | Daily upkeep | Link capacity | Route discount | Flow capacity |
|---|---:|---:|---:|---:|---:|
| Small Hub | 150 | 25 | 4 links | 15% | 250 food/day |
| Regional Hub | 350 | 60 | 8 links | 25% | 600 food/day |
| Central Hub | 800 | 140 | 14 links | 35% | 1,400 food/day |

**Only the Small Hub exists in the build.** Every hub is a Small Hub, built manually on any route tile. The Regional Hub upgrade was retired in v0.4 item 28 -- its tool, its 200 upgrade cost, and the REGIONAL enum value are all removed -- and Central Hub was never in MVP scope. The rows above are kept for the numbers, should either tier be revived.

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

A hub should usually become worthwhile when it serves 3 or more connections or when it organizes several long routes, but nothing enforces that -- as of v0.5 item 17, the player can build a Small Hub on any existing route tile with the Build Hub tool, so the decision of *where* it's actually worth the §150 and daily upkeep is entirely theirs.

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

### Delivery-result info tip (added in v0.3, merged into a single tip in v0.4)

Every settlement—village, town, or city—shows an info tip when hovered (desktop) or tapped (mobile). It summarizes the most recently simulated day's per-food ✓ / ◐ / ✗ checklist without requiring the player to open the full report or a separate dialog.

Suggested tip:

```text
Village A — Last delivery
Grain: 18 / 20 · 91% fresh · from Farm
Bread: 14 / 22 · 76% fresh · from Bakery
Rejected: 2 bread below minimum freshness
Status: Partial
```

The tip should show, per requested food:

- Requested amount.
- Accepted delivered amount.
- Average delivered freshness.
- Supplying source or sources.
- Rejected amount and reason when applicable.
- A readable status such as Complete, Partial, or Missing.

Before the first simulation, show that no delivery result exists yet. As of v0.4 there is no separate click-to-open checklist: hover and tap both show this same full tip, and tapping a settlement never attempts to build there.

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

Progression runs at two scales. **Within** a region, the order book below paces
demand one line at a time. **Across** regions, the roster in §12.1 unlocks a
new landscape and climate each time the player grades well on the last; the
chapter list at the end of this section is the teaching order that roster
delivers.

### Gradual demand: orders open as deliveries earn them (added in v0.6, revised in items 38-40)

The chapter list below is the full-game shape. On any free-play region the
same intent is delivered by the order book, which paces one map instead of
six levels (the scripted tutorial, §12.2, is the exception -- there the step
list decides what opens, and the alternation is switched off):

```text
fill an order  ->  a new order opens, straight away
```

No prompt, no confirmation, nothing to press. **The model.** A settlement's
`NodeData.demand` is what it will *eventually* want; lines open one at a time
as deliveries earn them. An unopened line is not simulated, not scored and
not drawn.

**Nothing on the map ever appears or disappears.** All five settlements and
all five sources stand there from day 1, so the player can see the whole
region and plan long routes against it. A settlement is never founded,
upgraded or resized: it simply starts placing orders. Settlements *growing*
was considered and rejected -- a village visibly becoming a city reads as a
city-builder, and in a logistics game the thing that should visibly develop
is the network the player drew.

**Progress, not days.** Nothing in `OrderBook` consults the calendar. An
early design gated on an `earliest_day` floor plus a "held 70% happiness for
2 consecutive days" streak, and both were clocks -- the streak counted days
too, just conditionally. Now: idle for a hundred days and nothing opens; fill
an order and the next is there immediately. `GameState.day` still drives the
day clock, the sun cycle and the report, and drives no progression at all.

**What counts as filled.** The whole requested amount arriving -- exactly the
**amber** speech bubble, and exactly the point at which a line starts paying
(§9: red pays nothing, amber pays the line, green pays it plus the bonus).
Freshness above that does one job only: deciding how well the player is paid.
`min_freshness` still bites implicitly and correctly, because `run_day`
rejects anything under it before it counts as delivered, so a line can never
fill on cargo too spoiled to accept. 99% delivered is a red bubble, earns
nothing, and does not advance the player -- a short order is not a partial
sale.

Filled is **latched**: proving a line once proves it for good, so a later bad
day can never un-open an order, and refilling one already proved opens
nothing (or a working network would sprout an order every day).

**Growth alternates between two kinds.**

| Kind | Meaning | Cost shape |
| --- | --- | --- |
| **Deepen** | another food for a settlement already served | reuses the trunk road, low marginal upkeep, needs a second source reaching the same place |
| **Expand** | the first order at a settlement not yet served | new road, new upkeep, new territory |

Strictly alternated rather than rolled, because a run of one kind is what
makes progression feel arbitrary -- five expansions running leaves the player
with five half-served towns and no reason for any of them. Alternating
guarantees the network both widens and thickens. When the preferred kind has
nothing left, it falls through to the other, and the preference only flips
when a line actually opens, so a starved side never burns its turn.

An earlier revision (item 38) instead put **two offers** on the map, one of
each kind, and had the player tap one. It bought a genuine deepen-or-expand
decision at the price of stalling the whole region behind a tap that had to
be noticed and understood, and in play it was not (item 40). The variety it
provided is what the alternation now supplies automatically.

**Eligibility is a rank, not a distance.** Each kind draws from the easiest
`OFFER_POOL_SIZE` remaining candidates of its sort. Difficulty is derived
from the map rather than authored (`MapData.difficulty_of`): how far the
freshness falls short of what the settlement rewards, over the straight-line
distance to the nearest source producing that food. Ranking region 1 this way
puts Village A's grain easiest (-18) and City E's vegetables hardest (+30),
reproducing the hand-written teaching order for free and re-deriving it if a
source ever moves. An absolute difficulty reach was tried first and is wrong:
the difficulties are unevenly spaced, so any fixed reach is either too tight
to offer anything early or meaningless later.

**Seeded.** Openings are drawn from a per-run seed on `GameState`, so a run
replays identically given the same seed and the same play. Nothing else in
the simulation is random any more (item 37), so a run that could not be
reproduced could not be debugged.

**Scoring follows.** `avg_happiness` averages only settlements taking orders
-- scoring one nobody may deliver to yet would make the grade a measure of
the calendar. The report prints the denominator ("82% (2 of 5 settlements
taking orders)").

**The map authors one thing.** `MapData.opening_lines` -- the three easiest
lines on the board (Village A's grain and bread, Village B's grain).
Everything after them is earned. Fixed first beats rather than anything
chosen, because on day 1 nothing is built.

Three rather than one: a single opening order is solved by one short road
from the nearest source and teaches only the drag gesture, so the player has
nothing to weigh at the start. Three gives an actual decision from the first
minute -- which town to reach first, whether one trunk road serves both --
while staying far short of the twelve-bubble wall this whole feature exists
to remove.

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

### Original MVP terrain types (SUPERSEDED by §8.2, kept for history)

| Terrain | Cost effect | Freshness effect | Design purpose |
|---|---:|---:|---|
| Plains | Normal | Normal | Default |
| Forest | Low cost, winding paths | Slightly more decay | Cheap but longer |
| Mountain | High cost | More decay | Makes direct routes expensive |
| River | Bridge required | Normal | Creates chokepoints |
| Snow | Medium-high cost | More decay for fresh foods | Supports storage puzzles |

Only Plains and River were ever built (TERR-01). The rest were never
implemented, and when the roster in §12.1 came to need them the table above
turned out not to describe decisions the player would ever actually take --
see §8.2 for what replaces it and why.

### 8.1 Per-cell terrain grid (added in v0.6 item 45)

Terrain is a **per-cell grid on `MapData`**, not a derived property:

```text
MapData.terrain : PackedByteArray   # grid_size.x * grid_size.y, row-major
MapData.terrain_at(x, y) -> TerrainType
```

This replaces `river_col`, an exported int from which `get_terrain(x, _y)`
answered for a whole column while ignoring `y` outright. That was exactly
enough terrain for one region with one straight river down it, and no more:
a ridge, a coastline, a delta or a wall cannot be expressed as "column N".
Region 1's river is re-authored as WATER cells in its own grid, so it stays
identical on screen while ceasing to be a special case in code. `river_col`
and `is_river(x, y)` are retired; the water test is
`terrain_at(x, y) == WATER`.

`GameEnums.TerrainType` keeps `PLAINS = 0` and `RIVER = 1` at their existing
values so authored data does not shift under the change (`RIVER` is aliased
to `WATER`, its clearer name now that it covers sea inlets and delta
channels too), and appends `FOREST`, `MOUNTAIN`, `SNOW`, `BLOCKED`.

**Validation** (`MapData.validate()`, run by the dev checks, not at runtime)
gains three rules, because a terrain map can be authored into an unplayable
state in ways a node list cannot:

- `terrain.size()` must equal `grid_size.x * grid_size.y`.
- No node footprint may sit on WATER or BLOCKED ground.
- **Every node must have at least one buildable orthogonal neighbour.** A
  source walled in by cliffs can never be connected to anything, and the
  order book would then offer lines against it forever.

Note `MapData.difficulty_of` still ranks lines by *straight-line* distance to
the nearest producing source, and so does not know a mountain is in the way.
That stays deliberate and stays correct for its purpose: it ranks the problems
a map poses, and on a terrain map the ranking is simply coarser than the
routes the player will actually draw.

### 8.2 Terrain modifiers (supersedes the original table)

| Terrain | Build cost | Upkeep | Decay | Capacity | Design purpose |
|---|---:|---:|---:|---:|---|
| Plains | 1.0x | 1.0x | 1.0x | 1.0x | Default |
| Forest | 0.75x | 1.0x | 1.15x | 1.0x | Cheap ground that costs a little freshness |
| Mountain | 3.0x | 1.5x | **0.6x** | 1.0x | Short and expensive vs. long and cheap |
| Snow | 1.2x | 1.5x | **0.5x** | **0.6x** | Preserves well, moves badly |
| Water | unbuildable except at a crossing (flat §40, `RIVER_BRIDGE_COST`) | — | 1.0x | 1.0x | Chokepoints |
| Blocked | unbuildable, no exception | — | — | — | Cliffs, walls, gated approaches |

These plug into the multipliers §4.1 already writes down and has never used
(`terrain_cost_multiplier`, `terrain_decay_multiplier`), plus an upkeep and a
capacity multiplier on the same per-tile basis.

**Why Mountain now preserves food.** The original table charged mountain
ground more money *and* more freshness. Nothing is traded there -- it is worse
on both axes than going around, so a rational player never builds on it and
the terrain is functionally a wall. Water is already the game's wall, and it
is a better one because a crossing is purchasable. Making mountain ground
expensive but **cold** turns it into the game's first genuine cost/quality
trade: a milk or seafood run over a ridge can beat the valley detour on
freshness while losing on money, and which one wins depends on the food, the
distance, and whether the settlement pays a bonus tier -- a decision, not a
no-brainer. It also gives §4.3's storage a rival, since terrain becomes a
second way to protect cargo.

**Why Snow is not a second mountain.** Both preserve, so Snow needs its own
identity: it is the only terrain that touches **capacity**. A snow tile moves
60% of its level's rated throughput (36 / 96 / 240 for Dirt / Paved / Main),
which pressures route upgrades and parallel roads instead of the treasury.

**Forest is unchanged in intent** -- cheap ground bought with a little decay,
already a trade-off as originally written.

### 8.3 Regional climate (added in v0.6 item 45)

```text
MapData.climate_decay_mult : float = 1.0    # scales every food's per-tile decay
```

Applied once, on top of per-terrain decay, for the whole map. This is the
roster's main instrument (§12.1): the food set is fixed at five, and a
multiplier on decay re-ranks all five at once without authoring a single new
food. At 0.75 a cold region makes seafood (6.0/tile) routable across a map for
the first time; at 1.4 a hot one puts grain in the position seafood normally
occupies. Region 1 is 1.0 and plays exactly as it does today.

Deliberately a single scalar rather than a per-food table: per-food would let a
region quietly redefine what a food *is*, and the point is that the player's
knowledge of the food set carries between regions while the answer changes.

### 8.4 Blocked ground

`BLOCKED` is unbuildable ground that is not water, so it has no crossing price
and no bridge -- there is no version of the map where a route gets through it.
Water says "pay §40 or go around"; blocked ground says "go around". It exists
so a map can shape an approach rather than merely tax it, which is what makes
Oldwall's gates (§12.1) a funnel instead of a toll.

### Terrain example

```text
Direct mountain route:
Short, expensive to build and maintain, but the cargo arrives fresher.

Valley route:
Longer, cheap, and every extra tile costs freshness.

Cool Storage route:
Extra building cost, better delivered quality, works on any terrain.
```

The three now genuinely compete, which the original version of this example
did not: with mountains costing both money and freshness, the valley route
won on every axis and the choice was decorative.

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
- Settlement last-delivery detail, as balloons on hover/tap (§10.1)
- Top-left zoom/pan controls (§10.7)

#### The map layer: chips at rest, balloons on inspection (v0.6 items 47-49)

At rest every node draws a **vertical column of chips** -- one food glyph per
open order on a status-coloured background. The full balloon comes back only
for the node the player is hovering or has tapped.

```text
   collapsed                 expanded (hover/tap)
   ,-------.                 ,-------.--------------.
   | ✕fish |                 | ✕fish |  0/25        |
   `-------'                 `-------'--------------'
   ,-------.                 ,-------.--------------.
   | !wheat|                 | !wheat| 20/20        |
   `-------'                 `-------' 72%  [==|--] |
   ,-------.                 ,-------.--------------.
   | ✓loaf |                 | ✓loaf | 30/30        |
   `---v---'                 `---v---'--------------'
   Village C                 Village C

   Same row height, same pitch, same glyph cell, same tail. Expanding
   only widens each row to the right -- nothing already on screen moves.
```

- **A glyph, not a colour, says which food.** A balloon carries no food name,
  so colour alone identified all five -- and it cannot: milk on the old cream
  body was a contrast ratio of about 1.02:1, and grain and bread are adjacent
  golds. Each food has one silhouette: **wheat ear, loaf, carrot, bottle,
  fish**, stroked as well as filled so a pale or same-hued glyph still reads.
- **The chip's background says the status.** Red, amber and green read as a
  background at map distance in a way a corner badge does not. Allowed here
  because a chip carries no text -- item 30's rule against a saturated body
  exists only under *dark* text. The ✕/!/✓ mark stays regardless: shape is
  the colourblind guarantee and must not depend on hue.
- **Collapsed and expanded are one column at two widths** (item 50). Same row
  height, same pitch, same glyph cell, same tail -- expanding only widens each
  row rightward to add the amount, the freshness and the bar. Both are a
  single baked texture, which is what makes that alignment exact rather than
  hand-tuned.
- **Order is severity**: red, then amber, then green, ties broken by the
  shortfall as a fraction requested. The **top** chip is the line most worth
  acting on.
- **Vertical, not horizontal.** A five-order City spanned three-plus tiles
  sideways and crossed its neighbours; the space above a node is usually
  empty map.
- **A source is a different object**: near-square corners, neutral slate, no
  status tint, no status mark and no tail -- it has no delivery to be judged
  on. It never expands, and its used/produced figure lives in the hover tip.
- **A settlement opens no text tip** (item 48). The balloons are the detail
  view. Sources, routes, storage, hubs and bridges keep theirs.
- **Nothing new is tappable.** Expansion rides the hover/tap that already
  opens the info tip (§10.6).
- **Bubbles is a three-state control -- Glyphs / All / Off.** All restores
  always-on balloons for every node, for a player who wants every number on
  screen at once.

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

As of v0.5 item 17 there is a manual hub-placement tool (Build Hub) -- see "Manual hub construction on any route tile" under §4.4. Selecting an existing route tile with the Build Hub tool should show what a Small Hub would cost there and the network's current hub count, so the player can decide whether it's worth building.

```text
Build a Small Hub on this route tile?
Route: 8
Small Hub (via Build Hub): 150
Network hubs if built: 2 / 2
```

Route placement is never blocked by whether a hub can be afforded or the network is at its cap -- see §4.4.

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

### 10.6 Settlement delivery info

Hovering (desktop) or tapping (mobile) any settlement shows its last delivery result as a single info tip -- there is no separate dialog to open. The tip must remain compact enough not to obscure the nearby route network and should be positioned inside the viewport.

Minimum fields:

```text
Settlement name
Food: delivered / requested · average freshness · source
Rejected or missing amount
Overall status
```

### 10.7 Control panel (revised in v0.4 item 25)

**One** panel along the left edge carries the entire HUD. It replaces the earlier split between a top-left map-controls panel and a 300px right-hand build sidebar: two panels ate both edges of the screen, every build action meant crossing from one to the other, and the most-used tools had to be duplicated on both to soften that. The panel scrolls if the window is too short for it, and only the day clock (§10.8) lives outside it, in the opposite corner.

Top to bottom:

- **Status:** current day and treasury on one row; grade, best score, and 7-day average score as three captioned numbers beneath it (LOOP-01/LOOP-06).
- **Build tools:** every tool as a short, priced toggle in two columns -- Route §8 / Upgrade, then Normal §80 / Cool §180, then Hub §150 / Bulldoze. The panel is narrow, so a button carries only its name and price; the full explanation is in its tooltip and, once selected, in the bottom hint bar. Each tool now exists exactly once, so there is no shortcut copy to keep in sync.

- **Zoom:** +/− buttons adjust camera zoom continuously while held (tap for a small step, hold for continuous zoom).
- **Pan:** a 4-direction (^/v/</>) pad moves the camera across the map while held, clamped to a small margin past the map edge so the player can't pan away indefinitely. Plain ASCII glyphs are used instead of Unicode arrows since the default exported font has no glyphs for U+25B2-U+25BC/U+25C0/U+25B6, which renders as blank "tofu" boxes on some platforms.
- **Bubbles: Glyphs / All / Off (added in v0.4, made three-state in v0.6 item 47):** cycles the map's node layer. **Glyphs** is the default -- a compact glyph strip per node, with the full balloons appearing only for whichever node is hovered or tapped. **All** restores the older behaviour of every balloon being on screen at once, for a player who wants every number visible while optimising. **Off** hides the layer entirely, leaving routes, storage and hubs clear without zooming out.
- **Legend:** collapsed by default, since it is reference material rather than a control. Expanding it scrolls it into view.

None of this depends on a mouse wheel or keyboard, so the game stays playable and testable from a phone browser. These controls work identically with mouse and touch input. They coexist with the existing tap-to-build and hover/tap-to-inspect interactions -- pressing a control never triggers a tile action underneath it. World-tile input handling relies solely on Godot's touch-to-mouse emulation (the default `emulate_mouse_from_touch` project setting); the raw touch event is not independently routed to tile actions, since it bypasses Control consumption and would otherwise leak through pressed buttons.

### 10.8 Day clock panel (added in v0.4 item 24)

A fixed panel in the **top-right** corner of the screen -- diagonally opposite the control panel (§10.7), so the two never crowd each other -- carries the day timer and its transport controls:

```text
Day 3                    0:47
[==================        ]
Day runs itself at 0:00
[ Pause || ]  [ 1x ]
[ Auto ]      [ Report ]
[ Run Day Now > ]
```

- **Day and time:** the day number plus the in-game wall-clock time (§3.6) -- "Day 3 - 6:45 pm". The phase name ("Sunset") sits on the mode line below it.
- **Countdown:** minutes:seconds remaining in the current day, drawn large. It turns amber under 15 seconds and red under 5 so the end of a day is legible from the corner of the eye, and goes gray whenever the clock isn't running (paused, or manual mode). The bar beneath it shows the same value as a fraction of the full day.
- **Pause / speed:** hold the countdown, or cycle 1x/2x/4x (§3.5). Both are disabled in manual mode, where there is no running clock to control. The spacebar toggles pause as well.
- **Auto:** toggles the auto-running clock against the manual loop. Switching modes always resets the countdown to a full day, so the player is never dropped into an about-to-expire day.
- **Report:** reopens the last simulated day's full report for review (disabled before the first simulated day). This never advances the calendar -- only the end-of-day report's "Continue to next day" does that.
- **Run Day Now:** simulates the current day immediately instead of waiting out the clock.

Directly beneath the panel, an auto-run day posts a **summary card** -- day number, grade and score, profit, average freshness, settlement happiness, plus a personal-best or capacity-blocked line -- which fades on its own after a few seconds. It is non-blocking by design: the auto-run loop can't stop for a dialog every day, so the card carries the headline and the Report button carries the detail.

Like the control panel, this one is usable by mouse or touch and never triggers a tile action underneath it.

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

This section describes **region 1 only**, which is now the first free-play
region. The main game's stages are a roster of further regions (§12.1), and
the scripted tutorial that precedes them all is §12.2.

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
- Hub — built manually on any existing route tile, always as a Small Hub (see §4.4). Freeze Storage and the Regional Hub upgrade were retired in v0.4 item 28.

### MVP systems

- Route drawing (drag-only, starting from a source or a built hub and ending at a hub or a settlement)
- Route upkeep
- Route capacity (tight enough to be a routine bottleneck, not an edge case — see §4.1)
- Manual hub construction on any route tile, with a per-connected-network cap of 2 (see §4.4)
- Settlement-only delivery destinations; sources and non-target settlements cannot be transit nodes
- Demand-pull food assignment from sources to settlements
- Freshness decay
- Storage preservation
- Hub discount
- Settlement demand, fixed per food (the ±15–20% daily wobble was removed in v0.6 item 37)
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

There is no finish line. What keeps the chase live is the region opening up
(§6): every new order changes the problem the network has to solve, so a
layout that scored well over three orders is not guaranteed to over six, and
there is always a "can I make this cleaner" pull. That is a closer match to
§18's Core Fun Test than a checklist that, once cleared, has nothing left to
optimize. Note this used to lean on the daily demand wobble instead, which
v0.6 item 37 removed: re-scoring a *static* network now returns exactly the
same grade, so the pull has to come from new orders rather than from noise.

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
(10/6). Settlement demand for each food is fixed -- a settlement asks for the
same amount every day (v0.6 item 37).

Route construction costs 8 per tile before terrain modifiers. Dirt route upkeep
is 2 per tile/day before terrain, route-level, and hub modifiers. Route
capacity is 60 (Dirt) / 160 (Paved) / 400 (Main) food/day. Crossing a river
automatically constructs a bridge for an additional 40. Basic upgrades are
Dirt -> Paved -> Main routes and (hub-upgrade only) Small -> Regional hubs.
Storage types are separate buildings rather than an upgrade chain.

A Small Hub (150) can be built manually with the Build Hub tool on any
existing route tile, capped at 2 hubs per road network -- no fork or
branch-count requirement. Placing a route tile is only gated by its own cost
(route plus optional bridge); the hub cap never blocks placement, and once a
network is at its cap the Build Hub tool simply refuses any further tile on
it (§4.4).

The first playable version has no save persistence, delivery animation,
chapter tutorial sequence, Central Hub, source upgrades, or random events. It
does retain last-day flow records in memory for hub and settlement popups.

---

## 12.1 Region Roster: the main-game stages (added in v0.6 item 45)

§12's single region was the MVP's scope, not the game's. Every system in §4 is
now reachable on it, which means it has taught everything it can and only the
endless efficiency chase is left there. The main game is a **roster of
regions** fronted by a scripted tutorial stage (§12.2); region 1 is unchanged
in content and becomes the first free-play region.

### 12.1.1 What separates one region from another

A region is a **landscape and a climate**, not a place. The nearby model for a
map roster is one themed on cities, where each map's character is a street,
coast or river silhouette; following that would make this a city game that
happens to move food, and it would leave unused the one axis this game has and
that model does not -- **cargo that degrades, at rates differing 12x across the
food set**. So each region combines:

1. **A climate** (`climate_decay_mult`, §8.3), which re-ranks all five foods at
   once. This is the primary instrument. The same five foods, the same player
   knowledge, a different answer.
2. **A landscape** (the terrain grid, §8.1-8.4), which decides where roads can
   go and what they cost.
3. **A binding constraint** -- exactly one system per region promoted from
   background detail to the thing the map is about. Region 1's is freshness;
   the others take turns.

Regions are named for the land. Each keeps **its own best grade, best score and
7-day average** (§7.5, §12's endless chase), and **its own treasury**: a region
is a run, not a save the player carries between maps. Nothing unlocks
permanently across regions -- every map starts at `STARTING_FUNDS`, which is
what keeps a late region a puzzle rather than a formality funded by an earlier
one.

Each region authors its own `opening_lines`; the order book (§6) paces it from
there with no further authoring, exactly as it does today.

### 12.1.2 The roster

| # | Region | Climate | Grid | Landscape | Binding constraint | Teaches |
|---:|---|---:|---|---|---|---|
| 0 | **Millbrook** *(tutorial)* | 1.0 | 15x11 | Open plains, one river | — (scripted) | Every rule, one at a time (§12.2) |
| 1 | **Ashfield Plain** | 1.0 | 21x14 | Open plains, one river | Freshness | The whole vocabulary, unsupervised |
| 2 | **The Terraces** | 0.9 | 21x16 | Mountain ridge, 3 passes | Cost vs. quality | Terrain as a second storage |
| 3 | **Cold Coast** | 0.75 | 24x14 | Fjords, narrow crossings | Chokepoints | Seafood, and the cold chain |
| 4 | **The Delta** | 1.0 | 22x16 | Braided channels, islands | Network topology | When *not* to connect |
| 5 | **Oldwall** | 1.1 | 20x14 | Walled city, 3 gates | Route capacity | Upgrades and trunk roads |
| 6 | **The Flats** | 1.4 | 24x16 | Nothing at all | Everything at once | The exam |

**0. Millbrook** *(the scripted tutorial)*. 15x11, two sources, four
settlements, climate 1.0. Nine steps, each ending when the player does the
thing rather than when they press Next, introducing the route drag, the day
clock, bubbles, freshness, Cool Storage, hubs, capacity, the river crossing
and source upgrades in that order. Fully specified in §12.2.

**1. Ashfield Plain** *(shipped, unchanged)*. 21x14, five sources, five
settlements, one river column, climate 1.0. Its river moves into the terrain
grid (§8.1) and nothing else about it changes: same nodes, same demand, same
opening lines, same difficulty ranking. It is the **first free-play region**
-- everything Millbrook scripted, now unsupervised and on a map four times
the size -- and the one a returning player replays to warm up. Item 45
called it the tutorial; item 46 gave that job to Millbrook, which is the only
part of the roster that changed.

**2. The Terraces.** A mountain ridge runs the length of the map with three
passes through it. Lowland sources west (Farm, Bakery, Garden), upland
settlements east, and a Dairy high on the ridge itself. Climate 0.9.
*The hook* is §8.2's inverted mountain: a pass costs 3x to build and 1.5x to
maintain, and preserves cargo at 0.6x decay. So the short expensive road over
the ridge and the long cheap road around it are genuinely different answers,
and which is right depends on whether the food is grain (barely decays -- go
around) or milk (go over). The hub cap bites here too, since three passes and
two hubs per network is a real budget.
*Why second:* it is the first region where terrain is a tool rather than an
obstacle, and it says so in one screen.

**3. Cold Coast.** Sea inlets cut deep from the east, leaving fingers of land;
two Harbors and a Dairy on headlands, settlements inland. Water is unbuildable
except at authored **narrows**, one cell wide, which take the §40 crossing.
Climate 0.75.
*The hook* is that a cold map is the only place seafood (6.0/tile, the food the
retired Freeze Storage existed to serve -- item 28) can cross a map at all.
Cool Storage plus a short chain is the answer, and the narrows decide where the
chain can physically go, so `RIVER_BRIDGE_COST` stops being a footnote and
becomes a main cost line.
*Why third:* it makes good on PROG-05's promise (§6 Chapter 5), which lost its
answer when Freeze Storage was retired.

**4. The Delta.** Braided channels fragment the map into islands, each holding
a source or a settlement or two. Climate 1.0, flat ground throughout.
*The hook* costs nothing to build, because the rules already do it: hub and
bridge caps are **per connected road network** (§4.4), so a fragmented map
hands the player a dozen small networks each with its own 2-hub budget.
Bridging two islands into one network halves their combined hub allowance.
Deciding *not* to connect two roads is a move the single-landmass region 1 has
never once asked for, and here it is the whole map.
*Why fourth:* it needs the player to already understand what a network is, and
it re-reads a rule they think they know.

**5. Oldwall.** The one nod to a dense-city map, reframed so it is not a street
grid. A 3x3 City sits inside a ring of `BLOCKED` wall with exactly **three
gate cells**; villages and sources ring the outside. Climate 1.1.
*The hook* is that every delivery to the City eventually funnels through three
tiles, so **route capacity** (60 / 160 / 400) becomes the binding constraint
instead of freshness -- the first map that forces Main routes and parallel
trunk roads rather than merely permitting them. A gate is also the obvious
place for a hub, and there are three gates and two hubs.
*Why fifth:* capacity is the least-exercised system in the game and wants a
map of its own; it also satisfies the dense-city instinct with a chokepoint
puzzle rather than by drawing streets.

**6. The Flats.** No terrain features whatsoever, sources pushed to the far
corners, and climate 1.4 -- everything spoils half again as fast. Nothing to
blame, nothing to exploit, no clever crossing to find.
*The hook* is that it is the exam: pure optimisation against the efficiency
grade, and the natural permanent home for the endless chase (§18). A player
who cannot hold an A here has a gap somewhere in §4.
*Why last:* it is only interesting once the player has real instincts to test.

### 12.1.3 Unlock and region select

- A region unlocks by reaching **grade A** (§7.5, score >= 75) on the region
  before it, on any single day. A grade rather than a day count, for the same
  reason the order book gates on delivery rather than the calendar (§6): a
  clock measures patience, and the roster should measure play.
- A region-select screen lists each region with its landscape, climate, best
  grade, best score and 7-day average; locked regions show their unlock
  condition rather than being hidden, so the roster reads as a plan.
- **Millbrook (region 0) is unlocked from the start**, and completing *or
  skipping* it unlocks Ashfield Plain. Gating region 1 behind a finished
  tutorial would make the tutorial a toll; it earns its place by being worth
  playing, not by standing in the doorway. Once unlocked, nothing ever
  re-locks.
- Millbrook is replayable from region select, and carries no grade or score
  of its own -- it is a lesson, not a run, and scoring it would invite the
  player to optimise the one map whose numbers are authored to teach rather
  than to be beaten.
- Progress is per region and persists; nothing else does.

### 12.1.4 Relationship to §6's chapters

§6's six chapters remain the full-game teaching order they always described.
The roster is what delivers them -- one region per lesson rather than one
chapter per unlock -- and the mapping is close but not exact, because a region
has to be a place before it is a lesson: Chapter 1 is the scripted tutorial
(§12.2), Chapter 5's long-distance seafood lands on Cold Coast, Chapter 6's
city supply on Oldwall, and Chapters 2-4 are all reachable on Ashfield Plain,
which is why it can stay the first free-play map.

---

## 12.2 The tutorial stage: Millbrook (region 0, added in v0.6 item 46)

Item 45 called region 1 the tutorial, which described its difficulty and
nothing else -- it teaches no system, and a new player meets every rule at
once. **Millbrook** is a smaller, scripted region 0 that introduces them one
at a time; region 1 becomes the first free-play region.

### 12.2.1 The rule: a step ends when the player does the thing

Every step names a **condition over game state** and completes the moment it
holds. There is no Next button, no "tap to continue", and no timed dismissal.

This is item 40's finding applied to teaching. That item removed a
tap-to-accept offer because the plaques "were read as something to wait out
rather than something to press"; a Next button is the same object with a
clearer label, and it lets a player click past an instruction they have not
read and then be stuck with no way back. Gating on the map instead means the
instruction is on screen for exactly as long as it is untrue, and the map is
the progress bar.

**Conditions are read-only over state the game already keeps**, so the step
machine adds nothing to `SimulationEngine`:

| Condition | Reads |
|---|---|
| `route_established(source_id, node_id)` | `SimulationEngine.established_route_cells` |
| `days_simulated(n)` | `GameState.day` |
| `node_inspected(node_id)` | the info-tip handler (§10.6) |
| `line_filled(node_id, food_id)` | `GameState.filled_lines` (already latched) |
| `line_green(node_id, food_id)` | `last_settlement_status` vs `bonus_freshness` |
| `structure_built(kind)` | `GameState.grid` |
| `no_tile_over_capacity` | `GameState.last_congestion` |
| `source_upgraded(node_id)` | `NodeData.upgraded` |

Conditions are evaluated after a player action and after a day simulates --
not per frame.

**Completion latches**, for the same reason `filled_lines` does: bulldozing
the step-1 road while on step 7 must not throw the player back to step 1.
But if the *current* step's condition breaks before it has ever held, its
instruction simply stays up, so a mistake made now is corrected now.

### 12.2.2 It cannot be failed

There is no bankruptcy, loss or game-over condition anywhere in the build, so
this is free to guarantee and worth stating:

- **Tools are revealed, not disabled.** Each step adds its tool to the panel
  (§10.7). Nothing is greyed out with an error, because a disabled button the
  player wants to press teaches only that the game is refusing them.
- **Bulldoze is available from step 1**, alongside Route, as the escape hatch.
  It is never itself a step -- undoing a mistake is not a lesson.
- **The clock is off until step 2 introduces it.** Learning the drag gesture
  under a 60-second countdown is the one place the auto-clock (§3.5) actively
  hurts. From step 2 it runs normally at 1x.
- **Days report through the compact card**, never the blocking modal (§3.3),
  so a day rolling over never interrupts a step.
- **Skippable and replayable.** Skipping from region select still unlocks
  region 1 -- a tutorial that gates content is a toll, not a tutorial.

### 12.2.3 Map

**15x11, climate 1.0**, plains with a single river at **column 9**, dividing a
western area (steps 1-7) from an eastern one (steps 8-9).

| Node | Type | Cells | Food |
|---|---|---|---|
| Farm | Source | (2,2)-(3,2) | grain **100**/day |
| Dairy | Source | (2,8)-(3,8) | milk **40**/day |
| Village A | Village | (6,2) | grain 20 |
| Village B | Village | (7,4) | milk 20 |
| Village C | Village | (6,6) | grain 45 |
| Town D | Town | (11,6)-(12,6) | grain 20, milk 25 |

`opening_lines` holds **one** line: Village A's grain. Item 39 raised region 1
to three because a single opening order left a free-play player nothing to
weigh; a scripted tutorial supplies the weighing itself, and one bubble is
what step 1 wants on screen. The order book's deepen/expand alternation
(item 40) is **disabled on this map** -- the step list decides what opens.

**The numbers carry the lessons**, so no step has to assert anything the map
does not demonstrate:

- Village A is **3 tiles** from the Farm; grain decays 0.5/tile, so it lands
  at 98.5% and green. The first road works perfectly, on purpose.
- Village B is **8 tiles** from the Dairy; milk decays 4.0/tile, so it lands
  at **68% -- amber**, above the village's 35% minimum and below its 80%
  bonus line. The player succeeds and is shown that succeeding is not the
  ceiling. Cool Storage placed early on that run (protection 8 covers all
  8 tiles, 0.35x) takes it to **89% and green**.
- Grain to Village A (20) plus Village C (45) is **65/day down one shared
  Dirt trunk against a 60 cap** -- a capacity problem, with the Farm's 100
  leaving supply comfortably clear of it.
- Milk to Village B (20) plus Town D (25) is **45/day against the Dairy's
  40** -- a supply problem, on a trunk far under capacity.

Those last two are deliberately on **different foods**, so "the road cannot
carry it" and "the farm cannot make it" are never the same day's problem --
which is exactly the confusion a tutorial exists to prevent.

### 12.2.4 The nine steps

| # | Teaches | Instruction | Reveals | Completes when |
|---:|---|---|---|---|
| 1 | The route drag | "Press and **hold** the Farm, drag to Village A, and let go." | Route, Bulldoze | `route_established(farm, villageA)` |
| 2 | The day clock | "Deliveries happen when a day ends. Run the day." | Clock panel, Run Day Now | `days_simulated(1)` |
| 3 | Reading a bubble | "Village A got its whole order, fresh. Tap it to see the detail." | — | `node_inspected(villageA)` |
| 4 | Distance costs freshness | "The Dairy is further out. Run milk to Village B." | — (opens `villageB/milk`) | `line_filled(villageB, milk)` |
| 5 | Cool Storage | "That milk arrived at 68% -- amber pays the order, green pays 25% more. Put Cool Storage early on the run." | Normal, Cool | `line_green(villageB, milk)` |
| 6 | Hubs | "Village C wants grain too, and the road out of the Farm is already there. Build a hub where they share it." | Hub | `structure_built(hub)` **and** `line_filled(villageC, grain)` |
| 7 | Route capacity | "That trunk is carrying 65 a day down a 60 road. Upgrade it." | Upgrade | `no_tile_over_capacity` |
| 8 | Crossing the river | "Town D is across the water. A route tile on the river costs §40 extra -- or go the long way round." | — (opens `townD/grain`) | `line_filled(townD, grain)` |
| 9 | Source upgrades | "Town D wants milk as well. That's 45 a day, and the Dairy makes 40." | — (opens `townD/milk`) | `source_upgraded(dairy)` **and** `line_filled(townD, milk)` |

Then: *"That's the whole game. Ashfield Plain is open."*

**What is deliberately not taught.** Bridges (§4.1's placed road-over-road
deck) and the bulldoze/upgrade sweep (item 26) are left to be discovered: a
bridge is a capped, expensive, situational structure that a tutorial would
have to invent a reason to need, and the sweep is a convenience on a tool the
player already knows. Nine steps is already long, and every step past the
point the player has got it is a step they resent.

**Step 8 keeps the detour honest.** The river is crossable for §40 or
avoidable for roughly four more tiles of road and upkeep, and the instruction
says so. Teaching a cost as a toll teaches the player to pay it; teaching it
as a choice is the actual skill the rest of the game asks for.

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

Since hubs are built manually at flagged forks (v0.4 item 14), the visible reward comes from the Build Hub cost shown up front, the build confirmation, and the last-delivery split shown on hover.

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

This section is not final implementation, but it gives structure. (The
actual Godot port uses a plain tile grid, `GameState.grid`, rather than the
RouteSegment graph below -- see §12, §4.1. As of v0.4 item 15 it also has a
`GameState.connections` field: `Vector2i -> Dictionary[Vector2i, bool]`, a
symmetric adjacency-set of explicit, player-dragged links between cells.
This is what "connected" means everywhere in SimulationEngine now -- mere
grid adjacency never is. See §4.1's "Explicit connections" for how it's
populated.)

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
