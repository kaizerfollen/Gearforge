# Gearforge — Production Plan & Team Rules

## The team
| role | agent | owns |
|---|---|---|
| Lead / Producer / Tech director | main session | contracts (World, EntityStore, protocols, PrototypeDB), merges, checkpoints, HANDOFF.md |
| Game designer | `designer` | GDD, docs/research, GameData.json + generator, balance, campaign level data |
| Logistics engineer | `logistics` | Simulation/Logistics/* (belts, undergrounds, splitters, inserters, chests) |
| Production engineer | `production` | Simulation/Production/* (crafting machines, furnaces, drills, labs, research, beacons, silo) |
| Energy engineer | `energy` | Simulation/Power/*, Simulation/Fluids/*, Simulation/Burner.swift |
| Gameplay engineer | `gameplay` | Player/*, Commands/*, World/MapGen/*, Simulation/StaticEntitySystem.swift |
| Persistence & progression engineer | `progression` | Persistence/*, Progression/*, Sources/FactoryBench |
| Art director | `art` | tools/art/*, App/Resources/Sprites.atlas, App/Resources/Assets.xcassets, App/Sources/Art |
| iOS platform/build engineer | `platform` | App/project generation, tools/ios-typecheck (Linux shim), CI scripts |
| iOS rendering engineer | `rendering` | App/Sources/Rendering, App/Sources/Bridge |
| iOS UI/UX engineer | `ui` | App/Sources/App, App/Sources/UI |
| QA / performance | `qa` | Tests/*Integration*, perf benches, review reports |

## Waves
- **Wave 1 (core simulation + infra):** logistics, production, energy, gameplay, progression, art, platform. **← S5**
- **Wave 2 (iOS game):** rendering, ui, + follow-ups from wave 1 gaps; integration tests (qa).
- **Wave 3 (content complete):** campaign L1–L8 playable, stats, codex, settings, tutorials; designer balance pass.
- **Wave 4 (polish/perf):** 5k entities / 20k belt items < 6 ms/tick bench, render culling/batching, audio, haptics.
- **Later phases (GDD §3):** blueprints, robots, trains, circuits, nuclear, hostiles.

## Rules for every agent (non-negotiable)
1. Read `HANDOFF.md`, `docs/ARCHITECTURE.md`, the GDD sections and `docs/research/*` sections relevant to you.
2. Only edit files you own. If a shared file (World.swift, Entities.swift, Prototypes*.swift, SystemProtocols.swift,
   Inventory.swift, Math.swift, BinaryCoding.swift, GameData.json) truly needs a change, make it **minimal and
   additive** (new members/extensions; never rename or remove) and list it in your report. Prefer
   `extension World { ... }` in a file you own.
3. Keep public API signatures already declared in your stubs (other teams code against them). You may ADD API.
4. **Commit early and often** in your worktree (at least after every working sub-feature) — uncommitted work is
   lost when a session ends. Message format: `<role>: <what>`.
5. `cd Core && swift build && swift test` must be green at every commit. Add XCTest tests for every mechanic,
   using real data (`PrototypeDB.shared`), in `Core/Tests/FactoryCoreTests/<Role>Tests.swift`.
6. Performance: no allocations per entity per tick in steady state, no Dictionary/Set iteration for logic, no string
   lookups in hot loops, sleep idle entities where possible. Deterministic (no Date/random in sim).
7. Persistence: implement `serialize/deserialize/didLoad` for everything you own, round-trip tested.
8. Original IP: never use Factorio names, art, logos or text. Use the renames in docs/research/01_items.md.
9. At the end write `docs/team/<role>.md`: what was built, public API added, known gaps / TODO for next wave,
   shared-file changes, how to test. Commit it. Final reply to the lead: ≤ 250 words summary.
