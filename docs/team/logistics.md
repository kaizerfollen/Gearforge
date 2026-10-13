# Logistics — status (S5, lead-written)

## Built
- **BeltSystem**: transport lines (≤16 tiles, one tier), head-gap lane algorithm (O(lanes)/tick), curves (inner 106 / outer 295),
  sideloading onto near lane, underground pairing (auto entrance/exit, max distance per tier, hidden section), sideload onto
  undergrounds passes only the open-half lane, splitters (alternating in/out, input/output priority, filter), loops,
  lazy full rebuild preserving items, rendering geometry (`forEachItem`, curves as arcs), save/load (items as tile+lane+fraction).
- **InserterSystem**: all 7 types; half swing = ceil(0.5/rotationSpeed) ticks (cycle matches 1.1 table), hand size + bonuses,
  belt pickup/drop (far-lane rule), entity endpoints with machine accept limits, filters (whitelist), burner self-refuel,
  power satisfaction + requests, idle sleep (8 ticks entity source, 1 tick belt), `handPosition` for rendering.
- **ContainerSystem**: chests, bar limit (automation only), endpoint, save/load.

## Numbers
- 10 000 belt tiles + 20 000 items: **0.105 ms/tick release** (0.43 debug).

## API added
BeltSystem: `setUndergroundMode`, `isUndergroundEntrance`, `inputDirection(of:)`, `nearestLane(_:point:)`, `removeAllItems(on:)`,
`totalItemCount`, `lostItems`. InserterSystem: `handSize(of:)`, `pickupDropPoints(of:)`. ContainerSystem: `setBar`, `bar(of:)`.

## Gaps / next
- Inserter drop onto belt waits for a gap (no upstream hold); belt pickup lane preference simplified (lane 0 first).
- Topology rebuild is global (fine to ~20k belts; make regional later if drag-building lags).
- No ground items (inserters with no target wait).
