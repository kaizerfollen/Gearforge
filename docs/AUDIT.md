# Gearforge — Honest status audit (2026-10-14, updated S8)

Verdict: **the simulation core is complete and verified; the game as a product is NOT finished.**
S8: the iOS app **builds in real Xcode (Build Succeeded) and runs on the iPhone 17 Pro simulator**; the L1 burner loop
(walk, hand-mine stone/coal, place drill + furnace, fuel, smelt, take plates, chain-craft drills, drag belts) was
played through by hand and the UX problems found were fixed (see §2).

Legend: ✅ done & tested · 🟡 partial / untested · ❌ missing

## 1. Simulation core (FactoryCore) — 122 tests, all green (S7: core gaps closed, S8: playtest fixes)
| Mechanic | Status | Evidence |
|---|---|---|
| Belts (3 tiers), curves, sideload, undergrounds, splitters (priority/filter), loops | ✅ | LogisticsTests (11 belt tests), 0.1 ms/tick @10k belts |
| Inserters: burner/basic/long/fast/filter/stack/stack-filter, hand bonus, belt↔entity | ✅ | LogisticsTests, AuditTests (long-handed) |
| Chests + limit bar | ✅ | LogisticsTests |
| Assemblers 1–3, furnaces (auto recipe), chem plant, refinery, silo + launch | ✅ | ProductionTests, AuditTests (plastic, fluid recipe) |
| Drills (burner/electric), pumpjack, depletion, mining productivity | ✅ | ProductionTests, AuditTests (pumpjack→refinery) |
| Modules (allowed effects, prod whitelist), beacons | ✅ | ProductionTests, AuditTests (beacon +20 %) |
| Labs, research, queue, infinite research, bonuses | ✅ | ProductionTests, AuditTests |
| Power: poles, networks, steam (1.8 MW verified), solar/day-night, accumulators, brownout | ✅ | EnergyTests |
| Fluids: segments, pipe-to-ground, pumps, tanks, offshore pump, mixing guard | ✅ | EnergyTests |
| Character: move/collision, inventory+toolbelt, chain handcraft, cancel, hand mining | ✅ | GameplayTests |
| Commands: build/remove/rotate/fast-replace/undo/redo/ghosts/tiles/transfers | ✅ | GameplayTests |
| Map generation: deterministic, starting patches, water, trees, rocks | ✅ | GameplayTests, IntegrationTests |
| Saves: full world codec, identical continuation after load, slots, autosave, crash flag | ✅ | ProgressionTests |
| Campaign L1–L8 data, objectives (all kinds), stars, progress store | ✅ data / 🟡 balance | ProgressionTests (validity, L1 objectives) |
| Refinery output box order (heavy left, light middle, petroleum right) | ✅ | CoreGapTests |
| Items on the ground: spill when inventory full, inserter/drill drop & pickup, auto-loot, build-over pickup | ✅ | CoreGapTests |
| Copy/paste area: blueprints with settings, rotation, ghost settings applied on build, saved | ✅ core / ❌ UI | CoreGapTests |
| Charting / fog of war: character radius, radar nearby + sector scanning, map colours, bulk mapRGBA | ✅ (minimap + map screen) | CoreGapTests |
| Pollution statistic (per minute, total, by source) | ✅ (stats panel) | CoreGapTests |
| Direct machine→machine fluid links (no pipe) | ✅ | CoreGapTests |
| Pre-built factories for L5–L8 (designer agent; R/G/B/P/Y lines, oil on L6–L8; plates from supply chests) | ✅ | PrebuiltTests (rates measured) |
| Tap-to-walk A* pathfinding | ✅ (long-press ground / tap on map) | CoreGapTests |
| Walk-and-mine (hold on out-of-reach ore/tree → path into reach, then mine) | ✅ | GameplayTests |
| Tutorial layouts: L1/L2 starting patches within ~15/20 tiles of spawn; layout saved in settings | ✅ | ProgressionTests |
| Build overlays: drill output / inserter pickup+drop points for the preview | ✅ | GameplayTests |
| Later phases (blueprints, robots, trains, circuits, nuclear, enemies) | ❌ by plan | GDD §3 |

## 2. iOS app (App/) — builds in Xcode, runs in the simulator, hand-playtested (S8); 0 UI tests
| Area | Status |
|---|---|
| Xcode project (generated, validated) | ✅ Build Succeeded (warnings: "update to recommended settings", atlas split into 3) |
| SpriteKit renderer: terrain tile maps, entities, belts anim, items, inserter arms, wires, character, preview, day/night | ✅ seen working (terrain, ores, trees, lake, drill, furnace glow, belts, day/night) |
| Touch controls: joystick, tap/select/open, hold-to-mine, pan, pinch, build drag (belts), remove drag, context menu | ✅ joystick, hold-to-mine (+walk), pan + Recenter, belt drag, remove; 🟡 pinch/context menu not tried |
| HUD: power, time, objectives, research, quickbar, craft queue, toasts, build reason, **minimap** | ✅ |
| Panels: inventory+crafting, entity screens, recipe picker, research, stats (+pollution), pause, **map** | ✅ inventory/craft, drill & furnace screens, stats, pause, map; 🟡 research/recipe picker not tried |
| Menus: main, new game (campaign+freeplay), load, settings | ✅ main, campaign select, Continue |
| Lifecycle: background save, crash recovery offer, autosave | ✅ autosave + "Last exit" continue verified |
| Playtest fixes (S8) | far starting ores; hold-to-mine reach; imprecise 2×2 placement (snap onto drill output + IO markers); stale red preview after last item; pause menu overflow; entity panel overflow; Production tab showed 0 craftable; map screen offset; lock icon over text |
| **Localization** (GDD §10: string tables from day 1) | ❌ 121+ hard-coded English UI strings; item/tech names English only; **no Russian** |
| Audio (music, SFX, ambience) | ❌ no sound assets, no audio code |
| Map screen / minimap | ✅ minimap (tap → map), map: pinch/pan, tap to walk |
| Tutorial hint bubbles (L1–L2 data has hints) | ❌ not shown |
| Codex (item/recipe browser) | ❌ |
| Save thumbnails, rename in UI | ❌ (core supports rename) |
| Settings wired: autosave, haptics, alt-mode, reach circle, day/night, FPS, battery saver | 🟡 |
| Settings NOT wired: left-handed, UI scale, colorblind palettes, larger text, joystick options, volume | ❌ |
| MFi game controller | ❌ (stretch) |

## 3. Art
- ✅ 852 sprites (all 55 MVP entities incl. directions & working frames, 104 item icons, 8 fluids, terrain, ores, character, UI glyphs, status icons, app icon).
- 🟡 Missing: water/shore transition tiles, pumpjack directions, lamp glow at night, ore pattern repetition, explosions/smoke particles.

## 4. Saves — where and what
- Location on device: `Application Support/Gearforge/Saves/<slot>.gfsave` (manual slots, `autosave_1..N`, `autosave_exit`, `background`).
- Also: `Application Support/Gearforge/settings.json` (app settings), `campaign.json` (stars/best times/unlocks).
- Format: `GFSV` header + META (name, mode, level, play time, tick, date, map size, seed) + WRLD payload (LZFSE-compressed on device, CRC-32).
- Player data saved: position, facing, full inventory, quickbar, craft queue with reserved ingredients, mining target/progress, research, bonuses, statistics, every entity's internal state, map chunks explored. Not saved: undo history.
- When: manual (pause menu), autosave every N min of game time (default 5, 3 rotating slots), on app going to background, on "Save & quit".

## 5. Team / agents
- Used: art director ✅, iOS platform/build engineer ✅, 7 wave-1 specialists (stopped by usage limit, only fragments).
- Not used yet: **game designer** (balance, level pre-builts, tutorial texts), **UX designer** (layout/ergonomics review),
  **QA engineer** (independent review + test plan), **localization** (ru/en string tables), **audio designer**,
  performance engineer (on-device profiling), rendering specialist (I wrote the renderer myself).

## 6. Priority backlog (next sessions)
1. ~~Build in Xcode~~ ✅ S8. Continue playtesting L2+ (research panel, recipe picker, power, inserters).
2. Localization: String Catalog `Localizable.xcstrings` (en + ru) for all UI strings + localized names for items/entities/techs/recipes (GameData `name` → localization keys).
3. Independent QA agent review of core + app; add UI smoke tests (XCUITest) once Xcode builds.
4. Missing MVP features: tutorial hints, copy/paste area UI, ground item rendering check, save thumbnails, wire remaining settings.
5. Audio: SFX + ambience + music (original, generated/procedural or licensed CC0).
6. Designer pass: L5–L8 pre-built factories, campaign balance, refinery output order.
7. On-device performance profiling (Instruments), render culling tuning, battery.
