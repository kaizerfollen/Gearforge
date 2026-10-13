# Energy — status (S6, lead-written)

## Built
- **PowerSystem**: poles auto-wire (≤5, nearest within min reach, no triangles), networks by flood fill (lazy rebuild),
  endpoint → first pole whose supply area overlaps; per-tick solve per network: solar → steam → accumulator discharge,
  primary-input served first, surplus charges accumulators; satisfaction per class; brownout; stats (produced/consumed
  power per entity type); boilers (burner, 1 steam/tick @165 °C, throttle by water/steam space); steam engines burn
  steam ∝ delivered energy; UI queries: `stats(network:)`, `network(at:)`, `wires(in:)`, `supplyArea(of:)`,
  `accumulatorCharge`, `powerOutput`, `boilerFuel`, `wiredPoles`. Honours `cheatInfinitePower`.
- **FluidSystem**: 2.0-style segments (pipes, pipe-to-ground pairs ≤10, tanks, pass-through boxes of boilers/engines),
  endpoint boxes (machine in/out, boiler steam, offshore pump, pumpjack) exchange ≤100/tick, proportional sharing,
  pumps between segments (powered), offshore pump 20/tick, mixing check `wouldMixFluids`, `fill(of:)`,
  `pipeConnections(of:)` bitmask for sprites, `segmentContents`, save/load (segments pushed to boxes).

## Numbers
- Steam plant 1 boiler + 2 engines = 1.8 MW verified. 1600 poles + 4800 consumers: 0.84 ms/tick release.

## Gaps
- Entities overlapping two networks use the first. No manual wiring UI yet. Endpoint↔endpoint direct fluid links
  (machine output straight into another machine) not supported — needs a pipe.
