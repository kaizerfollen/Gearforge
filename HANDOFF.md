# Gearforge — Session Handoff (READ THIS FIRST)

Original factory-automation game for iOS (Swift, SpriteKit + SwiftUI), mechanically modelled on Factorio 1.1.
All names/art/text are original. This file is the single source of truth for "where are we" between sessions.

## Where the project lives
- **User's Mac (persistent, survives sessions):** `/Users/new_ivan/Claude/Gearforge/`
  - `project/` — latest working tree (open `project/App/Gearforge.xcodeproj` in Xcode once generated)
  - `checkpoints/Gearforge.bundle` — full git history (`git clone Gearforge.bundle Gearforge` restores the repo)
  - `checkpoints/Gearforge-src.tar.gz` — working tree snapshot
- Cloud container (ephemeral!): `/home/claude/Gearforge` (git repo, branch `master`).

## How to resume in a new session
1. If `/home/claude/Gearforge` is missing: stage `checkpoints/Gearforge.bundle` from the Mac
   (`device_stage_files`) and `git clone <staged bundle> /home/claude/Gearforge`.
2. Read this file, then `docs/ARCHITECTURE.md` (how) and `docs/GDD.md` (what). Numbers: `docs/research/*`.
3. `cd Core && swift build && swift test` must be green before starting new work.
4. Checkpoint after every merged milestone: `tools/checkpoint.sh`, then `device_commit_files` the two files in
   `/mnt/user-data/outputs/gearforge/` to `/Users/new_ivan/Claude/Gearforge/checkpoints/`, then on the device:
   `cd $HOME/mnt/Claude/Gearforge && tar --overwrite -xzf checkpoints/Gearforge-src.tar.gz -C project`.

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
| Belts, inserters, containers | stub |
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
  established Mac checkpoints + this handoff file. Next: wave 1 implementation agents (see below).

## Next steps
See "Session log" last entry and the open waves in `docs/team/PLAN.md`.
