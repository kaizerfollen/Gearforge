# Gearforge — Session Handoff (READ THIS FIRST)

Original factory-automation game for iOS (Swift, SpriteKit + SwiftUI), mechanically modelled on Factorio 1.1.
All names/art/text are original. This file is the single source of truth for "where are we" between sessions.

## Where the project lives
- **User's Mac (persistent, survives sessions):** `/Users/new_ivan/Claude/Gearforge/`
  - `project/` — latest working tree (open `project/App/Gearforge.xcodeproj` in Xcode once generated)
  - `checkpoints/Gearforge-<YYYYMMDD-HHMM>.bundle` — full git history (`git clone <bundle> Gearforge`); use the newest
  - `checkpoints/Gearforge-src-<YYYYMMDD-HHMM>.tar.gz` — working tree snapshot
  - NOTE: device_commit_files caches by file name — always use a NEW timestamped name (tools/checkpoint.sh does).
- **GitHub (primary remote from 2026-10-15):** `https://github.com/kaizerfollen/Gearforge` (branch `main`).
  In a new session: `add_repo kaizerfollen/Gearforge` (access push), then `git clone` it — no bundle needed.
  Push after every milestone; Mac checkpoints stay as a second backup.
- Cloud container (ephemeral!): `/home/claude/Gearforge` (git repo, branch `main`; remotes `origin` = GitHub, `bundle` = old bundle).

## How to build the iOS app (client)
Open `project/App/Gearforge.xcodeproj` in Xcode 15+ → target Gearforge → Signing & Capabilities → pick your Team → choose an iPad/iPhone simulator (landscape) → Run. Details: `docs/team/platform.md`.
Typecheck on Linux: `tools/ios-typecheck/run.sh --app-only`. Regenerate project after adding files: `python3 tools/ios/gen_xcodeproj.py`.

## Toolchain in a fresh container (download.swift.org is BLOCKED by the egress policy)
Install Swift 6.0.3 from Ubuntu 25.10 "questing" (archive.ubuntu.com is allowed), pinned low so nothing else upgrades:
```
cat > /etc/apt/sources.list.d/questing.sources <<'X'
Types: deb
URIs: http://archive.ubuntu.com/ubuntu/
Suites: questing
Components: main universe
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
X
printf 'Package: *\nPin: release n=questing\nPin-Priority: 100\n' > /etc/apt/preferences.d/questing-pin
grep -l docker /etc/apt/sources.list.d/* | xargs -r rm -f     # docker repo is blocked → apt update fails
apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -t questing swiftlang
```
Restore the repo: newest `Gearforge-<TS>.bundle` from `/mnt/user-data/outputs/gearforge/` (if the container kept it) or
stage it from the Mac `checkpoints/` → `git clone <bundle> /home/claude/Gearforge`.

## How to resume in a new session
1. If `/home/claude/Gearforge` is missing: stage `checkpoints/Gearforge.bundle` from the Mac
   (`device_stage_files`) and `git clone <staged bundle> /home/claude/Gearforge`.
2. Read this file, then `docs/ARCHITECTURE.md` (how) and `docs/GDD.md` (what). Numbers: `docs/research/*`.
3. `cd Core && swift build && swift test` must be green before starting new work.
4. Checkpoint after every merged milestone: `tools/checkpoint.sh`, then `device_commit_files` the two files in
   `/mnt/user-data/outputs/gearforge/` to `/Users/new_ivan/Claude/Gearforge/checkpoints/`, then on the device:
   `cd $HOME/mnt/Claude/Gearforge && mkdir -p .unpack && tar --overwrite -xzf checkpoints/Gearforge-src-<TS>.tar.gz -C .unpack && rsync -a --exclude xcuserdata .unpack/ project/`
   (no --delete / rm: deleting needs a permission prompt; Xcode keeps its workspace files in project/).
   Quick iteration: `tools/patch.sh <since-commit>` → tar of changed files only → device_commit_files to
   checkpoints/patch-<TS>.tar.gz → `tar --overwrite -xzf checkpoints/patch-<TS>.tar.gz -C .patch && rsync -a .patch/ project/`.
5. Xcode on the Mac (computer use, Xcode granted at "click" tier: no keyboard): rebuild+run via menu Product → Run
   (menu bar "Product" ≈ (358,12), "Run" ≈ (368,40) in the 1372×887 frame). Simulator window ≈ x 450–1150, y 90–430.

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
| Save format framework (sections, CRC, metadata) | **done** |
| Map generation (noise, layout) | rescued, determinism + starting patches tested |
| Research/labs/beacons | rescued, research test passes |
| Belts, inserters, containers | **done** (21 tests, 0.1 ms/tick for 10k belts + 20k items) |
| Crafting machines, furnaces, mining drills, silo | **done** (13 tests, 0.26 ms/tick for 3000 assemblers) |
| Power networks, fluids | **done** (11 tests; steam 1.8 MW verified) |
| Character (movement, crafting queue, hand mining), Commands (build/remove/undo) | **done** (17 tests) |
| GameSession fixed-step driver, SaveManager, levels/objectives, stats | **done** (10 tests; save→load→continue identical) |
| iOS app: Xcode project, renderer, HUD, menus, screens | **builds in Xcode, runs on iPhone 17 Pro simulator**; L1 loop hand-playtested (S8), minimap + map screen |
| Art: python sprite generators | **done** — 852 sprites, 16.8 MB (`python3 tools/art/generate.py`) |

## Session log
- **S1–S4 (earlier):** four separate attempts (FactoryForge, Forgeline, Forgeworks, Gearforge) — work never
  merged or saved off-container. Gearforge chosen as the base (best design docs + architecture).
- **S5 (2026-10-11):** rescued uncommitted agent worktrees into master, fixed build (14 tests green),
  established Mac checkpoints + this handoff file. Launched 7 wave-1 agents in parallel → **weekly usage limit hit
  after ~6 min** (each agent spent ~200k tokens just reading docs). Rescued fragments: pbxproj validator
  (tools/ios), belt/inserter sprite work (tools/art), Surface +6 lines.
  **LESSON: run at most 2 agents at a time, give them narrow file-level tasks with the exact sections to read,
  and/or have the lead write code directly. Commit + checkpoint after every agent.**

- **S6 (2026-10-14):** lead wrote logistics directly (belts/undergrounds/splitters/inserters/chests), 35 tests green. Then production (crafting/furnaces/silo/drills) — 48 tests green. Then energy (power/steam/solar/fluids) — 59 tests green. Then gameplay (character/crafting/mining/commands/undo) — 76 tests green. Then persistence/session/campaign — 86 tests green. **Core simulation complete.** Audit (S6 end): +6 audit tests (oil chain, beacons, research queue/infinite, long-handed, fluid recipes) → 93 tests green; gaps recorded in docs/AUDIT.md. Then art (852 sprites, agent), platform (xcodeproj generator + Linux typecheck harness, agent), app layer (controller, SpriteKit renderer, HUD, panels, menus) written by lead — typecheck OK; integration test 'first minutes of freeplay' green (87 tests).

- **S7 (2026-10-14 night):** closed core gaps: ground items, direct fluid links + refinery output order, charting/radar, pollution, copy/paste blueprints, tap-to-walk A* → 111 tests; designer agent: pre-built factories L5–L8 → 118 tests. Mac went offline at ~02:02 — checkpoints 0202+ only in container until re-synced.

- **S8 (2026-10-14 day):** app opened in real Xcode: **Build Succeeded, runs on the iPhone 17 Pro simulator**.
  Hand playtest of L1 through computer use; fixed: tutorial ore layout (L1/L2 patches near spawn, layout saved in
  WorldSettings), walk-and-mine + long-press walk, near-miss ore snap, build assist (IO markers, snap onto drill output,
  auto-exit build mode), pause/entity panel scrolling, craftable counts per tab, campaign lock icon; new minimap + map
  screen (tap to walk), pollution in stats. Then: **Russian localization** (l10n agent: 1000+ keys, tooling
  tools/l10n), **independent QA agent** (15 core bugs found → all fixed, 152 tests green), tutorial hint bubbles,
  left-handed layout, save thumbnails, tolerant settings decoding. Mac went offline ~12:50 (screen locked).
- **S9 (2026-10-14 evening):** new container (repo + Swift gone). Restored repo from bundle 1321, installed Swift
  from Ubuntu questing (see Toolchain), 152 tests + app typecheck green; synced checkpoint 1321 to the Mac. Then: ground items rendering + tap pickup,
  copy/paste area UI (paste clears trees), save rename, HUD safe-area fix — built & checked in Xcode simulator (153 tests).
  Then audio agent (31 procedural sounds + AudioManager), Codex, settings wiring (UI scale, colour-blind, reduce motion,
  grid, confirm placement, auto-build), QA agent (15 findings fixed), paste clears trees only within reach → 165 tests.
  NOTE: on the Mac `rm` is not permitted this session → unpack each patch into a new `.p<TS>` dir (hidden, harmless).

## Honest audit
See **docs/AUDIT.md** (what is done / partial / missing, saves, agents, priority backlog). Keep it updated.

## Next steps (in order)
1. ~~Logistics~~ → 2. ~~Production~~ (crafting/mining/labs) → 3. Energy (power/fluids)
→ 4. Gameplay (character/commands/mapgen) → 5. Persistence orchestration → 6. Xcode project + iOS renderer/UI.
Wave-1 agent briefs (full prompts) are reusable: see docs/team/PLAN.md roles; keep briefs narrow.
