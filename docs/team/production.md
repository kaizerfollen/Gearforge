# Production — status (S6, lead-written + rescued labs/research/beacons)

## Built
- **CraftingSystem**: assemblers 1–3, chemical plant, refinery, centrifuge, stone/steel/electric furnaces (auto recipe from first
  smeltable input; coal goes to fuel), rocket silo (fixed recipe, 100 parts, satellite payload, launch → orbital cards, stats/event).
  Ingredient buffers aligned to recipe, inserter insertion limit (1.1 formula), output stall, leftover-progress carry, productivity
  bar, modules (allowed-effects mask, productivity whitelist eject on recipe change), beacon effects (lazy, revision-keyed),
  electric (drain + usage × consumption) / burner energy, fluid ingredients/results via FluidSystem box API, sleep/wake.
- **MiningSystem**: burner/electric drills, pumpjack (fluid yield), round-robin tile mining, depletion, mining productivity research
  + module productivity, output to belt (lane/position from output point) or any endpoint, held output when blocked, `hasResource`
  placement helper, `miningArea` preview.
- **LabSystem / ResearchManager / BeaconSystem / TechFormula**: rescued from S4 (tested via lab research test).

## Numbers
- 3 000 working assemblers: **0.26 ms/tick release**.

## Gaps
- Fluid recipes untested until FluidSystem lands. Pumpjack requires fluids.
- Furnace output limit = stack size; result probability uses world RNG.
