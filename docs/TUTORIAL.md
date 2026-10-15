# Guided tutorial — design & maintenance

Status: implemented in S11 (2026-10-15). Code: `Core/Sources/FactoryCore/Progression/Tutorial.swift` (script),
`App/Sources/UI/TutorialOverlay.swift` (highlights + card), `GameScene.updateTutorialMarker` (ground frame),
tests `Core/Tests/FactoryCoreTests/TutorialTests.swift`.

## What the player sees
- A card **«Обучение N/15»** with one instruction, a ✕ (skip) and, on info steps, **«Далее»** / **«Понятно»**.
  It replaces the goals list in the HUD's left column (so it never covers the player or the buttons); over an open
  panel it is shown at the bottom of the screen.
- **What to tap is highlighted**: a pulsing orange frame and a bouncing arrow on HUD buttons, quickbar slots, panel
  items (coal in the inventory strip, the furnace output slot, the drill recipe, the crafting tab, ✕ of a panel).
- **Where to go on the map** is highlighted with a pulsing orange frame on the ground (stone, coal, the 2×2 spot on
  iron ore for the drill, the 2×2 spot for the furnace at the drill output, the drill / furnace to open). When that
  place is off screen an arrow at the screen edge points to it.

## When it runs
- Level **L1 «Высадка»** until the tutorial is finished or skipped once (`GameSettings.tutorialDone`).
- Main menu → **«Обучение»** always starts L1 with the tutorial (even if done before).
- While it runs the objective hint bubble (left column) is hidden and «Как играть» does not open by itself.
- Steps already satisfied are skipped automatically (loading a save, a player who is ahead) — nothing can get stuck.

## Steps (Tutorial.Step)
| # | id | Highlight | Done when |
|---|---|---|---|
| 1 | welcome | — | «Далее» |
| 2 | move | joystick | moved > 2.5 tiles (or later progress) |
| 3 | mineStone | nearest stone (3×3 on the ground) | 5 stone in the inventory |
| 4 | mineCoal | nearest coal | 5 coal |
| 5 | selectDrill | quickbar slot with the burner drill (fallback: Build button) | build mode with the drill |
| 6 | placeDrill | best 2×2 spot fully on iron ore near the player where the furnace also fits | a player-built burner drill stands on iron |
| 7 | selectFurnace | quickbar slot with the stone furnace | build mode with the furnace |
| 8 | placeFurnace | 2×2 spot covering the drill's output tile | a furnace covers the drill output |
| 9 | fuelDrill | the drill → with its screen open: coal (else wood) in the inventory strip | drill has fuel |
| 10 | fuelFurnace | the furnace → coal, else wood (the drill usually takes all the coal) | furnace has fuel |
| 11 | waitPlates | the furnace | first iron plate produced |
| 12 | takePlates | the furnace → output slot 0 | player's iron plates increased |
| 13 | craftDrill | Inventory button → Production tab → drill recipe | drill queued / crafted |
| 14 | openMap | minimap | map screen open |
| 15 | goals | — (the goals list returns to the left column) | «Понятно» |

World-step guard: if a panel is open during a world step, the card says «Закройте это окно» and highlights ✕.

## Anchor ids (`.tutorialAnchor(id)`)
`joystick`, `build`, `inventory`, `minimap`, `objectives`, `research`, `quickbar.0…9`, `panel.close`,
`insert.<itemIndex>` (entity screen inventory strip/column), `output.<slot>` (machine output), `recipe.<recipeIndex>`,
`group.<craftTabIndex>`, `tab.crafting` (compact inventory picker). A target lists several ids; the first one on
screen wins (e.g. recipe → its tab → the Crafting/Inventory picker).

## Adding a step
1. Add a case to `Tutorial.Step` (order = order of play).
2. `isDone`: a world/UI check (never time-based); make it true when later progress makes the step pointless.
3. `hint`: English text through `h(...)` (picked up by `tools/l10n/extract.py`), target, `next:` for info steps.
4. Missing anchor? Add `.tutorialAnchor("id")` to the view.
5. Russian text in `tools/l10n/ru.json`, run `python3 tools/l10n/build.py --strict`.
6. Extend `TutorialTests.testWalkthroughOnL1`.

## Camera & reach
- While a ground target is shown the camera eases toward it (≤ 9 tiles sideways, ≤ 4.5 up/down from the character)
  so it is not hidden under the joystick or the bottom bar; farther targets get an arrow at the screen edge.
- Stone/coal targets prefer tiles above the character. Out of reach → «Дойдите до… следуйте за стрелкой».

## Not done yet
- Tutorials for L2 (power, research) and later levels — same mechanism, new scripts.
- Voice-over / animated hand gesture; dimming the rest of the screen (kept off so the game stays playable).
