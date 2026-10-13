# Gearforge — Session Handoff (READ THIS FIRST)

Original factory-automation game for iOS (Swift, SpriteKit + SwiftUI), mechanically modelled on Factorio 1.1.
All names/art/text are original. This file is the single source of truth for "where are we" between sessions.

## Where the project lives
- **User's Mac (persistent, survives sessions):** `/Users/new_ivan/Claude/Gearforge/`
  - `project/` — latest working tree (open `project/App/Gearforge.xcodeproj` in Xcode once generated)
  - `checkpoints/Gearforge-<YYYYMMDD-HHMM>.bundle` — full git history (`git clone <bundle> Gearforge`); use the newest
  - `checkpoints/Gearforge-src-<YYYYMMDD-HHMM>.tar.gz` — working tree snapshot
  - NOTE: device_commit_files caches by file name — always use a NEW timestamped name (tools/checkpoint.sh does).
- Cloud container (ephemeral!): `/home/claude/Gearforge` (git repo, branch `master`).

## How to resume in a new session
1. If `/home/claude/Gearforge` is missing: stage `checkpoints/Gearforge.bundle` from the Mac
   (`device_stage_files`) and `git clone <staged bundle> /home/claude/Gearforge`.
2. Read this file, then `docs/ARCHITECTURE.md` (how) and `docs/GDD.md` (what). Numbers: `docs/research/*`.
3. `cd Core && swift build && swift test` must be green before starting new work.
4. Checkpoint after every merged milestone: `tools/checkpoint.sh`, then `device_commit_files` the two files in
   `/mnt/user-data/outputs/gearforge/` to `/Users/new_ivan/Claude/Gearforge/checkpoints/`, then on the device:
   `cd $HOME/mnt/Claude/Gearforge && tar --overwrite -xzf checkpoints/Gearforge-src-<TS>.tar.gz -C project`.

## Team process (agents)
- Specialists run as agents in isolated git worktrees, each owning a set of files (ARCHITECTURE §1 table).
- Every agent: commits early and often in its worktree; keeps `swift build && swift test` green; writes
  `docs/team/<role>.md` (built / API / gaps / shared-file changes / how to test).
- Lead (main session) reviews, merges into `master`, runs tests, checkpoints to the Mac, updates this file.

## Status (update at every milestone)
| area | status |
|---|---|
| Design: GDD, research data (items/recipes/entities/techs/mechanics), GameData.json | done (v0.1) |
| Core contracts (World, EntityStore, protocols, PrototypeDB, Surface, Inventory, BinaryCoding) | done |
| Save format framework (sections, CRC, metadata) | WIP rescued, compiles |
| Map generation (noise, layout) | WIP rescued |
| Research/labs/beacons | WIP rescued |
| Belts, inserters, containers | **done** (21 tests, 0.1 ms/tick for 10k belts + 20k items) |
| Crafting machines, furnaces, mining drills, silo | stub |
| Power networks, fluids | stub |
| Character (movement, crafting queue, hand mining), Commands (build/remove/undo) | stub |
| GameSession fixed-step driver, SaveManager, levels/objectives, stats | partial |
| iOS app: Xcode project, renderer, HUD, menus, screens | helpers only (TerrainBaker, BuildPlanner, gestures) |
| Art: python sprite generators | WIP rescued (tools/art) |

## Session log
- **S1–S4 (earlier):** four separate attempts (FactoryForge, Forgeline, Forgeworks, Gearforge) — work never
  merged or saved off-container. Gearforge chosen as the base (best design docs + architecture).
- **S5 (2026-10-11):** rescued uncommitted agent worktrees into master, fixed build (14 tests green),
  established Mac checkpoints + this handoff file. Launched 7 wave-1 agents in parallel → **weekly usage limit hit
  after ~6 min** (each agent spent ~200k tokens just reading docs). Rescued fragments: pbxproj validator
  (tools/ios), belt/inserter sprite work (tools/art), Surface +6 lines.
  **LESSON: run at most 2 agents at a time, give them narrow file-level tasks with the exact sections to read,
  and/or have the lead write code directly. Commit + checkpoint after every agent.**

- **S6 (2026-10-14):** lead wrote logistics directly (belts/undergrounds/splitters/inserters/chests), 35 tests green.

## Next steps (in order)
1. ~~Logistics~~ → 2. Production (crafting/mining/labs) → 3. Energy (power/fluids)
→ 4. Gameplay (character/commands/mapgen) → 5. Persistence orchestration → 6. Xcode project + iOS renderer/UI.
Wave-1 agent briefs (full prompts) are reusable: see docs/team/PLAN.md roles; keep briefs narrow.
