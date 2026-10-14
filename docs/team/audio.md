# Audio: sound design and engine

Owner: Audio Designer. Status: complete, typechecked on Linux. **It has not yet been run or heard on a device.**

## Direction

The soundscape is calm industrial, and it should still be pleasant after hours of play:
- Transients are soft. Every one-shot has an envelope and fades in and out.
- Machines are quiet beds in the low-mid range: the median energy sits between 60 and 650 Hz.
- UI sounds and music use one modal palette: D dorian / A aeolian, built from the notes D, E, A and F.
- Nothing is sampled. `tools/audio/generate.py` synthesises every sound with numpy and scipy, and its output is
  deterministic. See `tools/audio/README.md` for the full sound list and techniques.

## Files (`App/Resources/Sounds`, folder reference "Sounds", 31 files, 5.82 MB)

| group | files | format |
|---|---|---|
| UI | `ui_tap`, `ui_open`, `ui_close`, `ui_error`, `ui_success`, `ui_craft_done` | 44.1 kHz mono 16-bit WAV |
| Building | `build_place`, `build_remove`, `rotate`, `paste` | 〃 |
| Player | `mine_hit_ore`, `mine_hit_tree`, `mine_done`, `pickup`, `footstep_1..4` | 〃 |
| Events | `rocket_launch` (4.6 s), `alert` | 〃 |
| Machine loops (1–2 s, seamless) | `loop_assembler`, `loop_furnace`, `loop_drill`, `loop_belt`, `loop_steam_engine`, `loop_boiler`, `loop_inserter`, `loop_lab`, `loop_pumpjack` | 〃 |
| Music (60 s, seamless) | `music_1` (D dorian), `music_2` (A aeolian) | **16 kHz** mono 16-bit WAV |

**Why music is 16 kHz.** The brief asked for 22.05 kHz, 60 s or longer, under 2.5 MB per track and under 6 MB in
total. These limits cannot all be met: 22.05 kHz × 60 s is 2.65 MB per track. At 16 kHz a track is 1.92 MB. The
pads and plucks have almost nothing above 7 kHz, so little is lost. A future AAC/CAF encode in the Xcode build would
allow longer music at a higher rate. On Linux no encoder is available.

**Loops have no seams.** They are rendered circularly: tones have a whole number of cycles per loop, noise comes
from an inverse FFT, filters are run to steady state, reverb is a circular convolution, and events wrap around.
The generator checks every loop numerically:
- the step from the last sample to the first must be no larger than the 99.9th percentile of all sample steps;
- the RMS of the first 50 ms and the last 50 ms must be within 6 dB of each other.

It also checks that no peak goes above 0.9. Run `python3 tools/audio/generate.py --check` to repeat the checks.

## Engine: `App/Sources/Audio/AudioManager.swift`

`@MainActor final class AudioManager`, used through `AudioManager.shared`. It is built on `AVAudioEngine`:

```
mainMixerNode (master, 0 when disabled)
 ├─ sfxMixer      (sfx)          ← 8 pooled AVAudioPlayerNodes (one-shots, per-voice volume + pan)
 ├─ ambienceMixer (sfx × 0.8)    ← 1 looping AVAudioPlayerNode per LoopKind
 └─ musicMixer    (music × 0.6)  ← 1 AVAudioPlayerNode looping the current track
```

| API | behaviour |
|---|---|
| `configure(master:music:sfx:enabled:)` | Sets volumes (0…1). `enabled == false` silences output and pauses the engine. AppModel passes `enabled = master > 0`. |
| `play(_ sfx: SFX, volume: Float = 1, pan: Float = 0)` | Uses an idle voice. If all 8 are busy it takes the voice that finishes soonest. A repeat of the same SFX within 60 ms is dropped. Each SFX has a gain trim (`SFX.gain`). |
| `updateAmbience(listener:sources:)` | For each `LoopKind`: volume = `min(1, Σ 1/(1+d²/36)) × kind.gain`, panned toward the loudest source's x offset (±10 tiles maps to ±0.8). Volume and pan are smoothed at 60 Hz with a 90 ms time constant, so about 92 % of a change is reached after 0.25 s. A kind with no sources fades to 0, and then its node pauses. |
| `startMusic()` / `stopMusic()` | Waits 2 s, then: 3 s fade-in, the track loops twice (about 2 min), 3 s fade-out, 20–60 s of silence, next track. `stopMusic` fades out over 1 s. |
| `setPaused(_:)` | Background: pauses the engine. Foreground: reactivates the session, restarts the engine and re-schedules players. |

Behaviour details:
- **Lazy setup.** The engine is built, and all buffers are decoded (about 12 MB of float PCM), on the first
  `play`, `updateAmbience` or `startMusic`.
- **Session.** The category is `.ambient`, so the game mixes with other apps and respects the silent switch. The
  session is set up under `#if os(iOS) || GEARFORGE_TYPECHECK`.
- **System events.** The engine handles interruptions, `mediaServicesWereReset` and
  `AVAudioEngineConfigurationChange` (for example a route change or headphones) by re-arming the players.
- **Robustness.**
  - A missing, unreadable or wrong-format file is logged once (`[Audio] …`) and then skipped.
  - `play()` on a player node is only called while the engine is running. AVFoundation raises an exception
    otherwise.
  - Formats: all one-shots must share one format, and every music track must match `music_1`.

## Hook-up

**`GameController`**

| trigger | sound |
|---|---|
| `execute` succeeds: build / ghost | `buildPlace` |
| `execute` succeeds: placeTiles | `buildPlace` at 0.6 |
| `execute` succeeds: remove / removeArea | `buildRemove` |
| `execute` succeeds: rotate (when not silent) | `rotate` |
| `execute` succeeds: pasteSettings / pasteBlueprint | `paste` |
| `execute` succeeds: takeAll / pickUpBeltItems / pickUpGround / transferFromEntity | `pickup` |
| `execute` fails (not silent), and "Out of reach" | `uiError` |
| `rotateBuild()` | `rotate` |
| `selectBuildItem`, entity tap | `uiTap` |
| `.researchFinished`, `.objectiveCompleted`, `.levelCompleted` events | `uiSuccess` |
| `.craftFinished` event | `uiCraftDone` |
| `.rocketLaunched` event | `rocketLaunch` |
| `.alert` event | `alert`, at most once per 3 s |

Player sounds, from `updatePlayerSounds(dt:)`:
- While mining, a hit every 0.5 s: `mineHitTree` on a tree entity, `mineHitOre` otherwise.
- `mineDone` when an ore unit is mined (the progress wraps) or when a tree or rock is gone.
- Footsteps every 0.32 s while `isMoving`, cycling through all four.
- `uiOpen` / `uiClose` when `panel` changes between nil and non-nil.

**`GameScene.refreshStates`** (4 Hz) sends ambience sources to `updateAmbience`, with the character as listener:
- Working machines inside the visible rect plus a 3-tile margin:
  - assembler → `assembler`
  - furnace → `furnace`
  - drill → `drill`, or `pumpjack` when the proto id is "pumpjack"
  - generator → `steamEngine`
  - boiler → `boiler`
  - lab → `lab`
- The 8 nearest inserters whose hand moved since the last refresh → `inserter`.
- The 12 nearest belt tiles that carry items in view → `belt`. The scene does not check whether those items are
  moving or blocked.

**`AppModel`**
- `configure(...)` runs at init and on every settings change.
- `startMusic()` runs in `begin`.
- `quitToMenu` runs `stopMusic()` and an empty `updateAmbience`, so the loops fade out.
- `scenePhaseChanged` sends `.background` → `setPaused(true)` and `.active` → `setPaused(false)`.

**Settings.** The Audio section has three sliders: Master, Music (`musicVolume`) and Sound effects (`sfxVolume`).
Their labels are localised in en and ru.

## Regenerating and adding sounds

```sh
python3 tools/audio/generate.py          # deterministic; prints the verification table
python3 tools/ios/gen_xcodeproj.py       # only needed if the Sounds folder itself moved (it is a folder reference)
```

To add a sound:
1. Write a generator function and register it with `reg(...)`.
2. Add a case to `AudioManager.SFX` or `LoopKind`.
3. Call `play` where the sound should happen.

Files inside `Sounds` need no project change, because Xcode copies the folder reference as a whole.

## Typecheck stub

`tools/ios-typecheck/Stubs/AVFoundation/AVFoundation.swift` copies the iOS 17/18 SDK signatures of everything the
engine uses:
- `AVAudioEngine`, `AVAudioPlayerNode` (+ `AVAudioPlayerNodeBufferOptions`), `AVAudioMixerNode`, `AVAudioMixing` /
  `AVAudioStereoMixing`;
- `AVAudioFile`, `AVAudioPCMBuffer`, `AVAudioFormat`, `AVAudioTime`, frame typedefs;
- `AVAudioSession` (Category, Mode, CategoryOptions, SetActiveOptions, InterruptionType/Options, notifications,
  keys);
- `.AVAudioEngineConfigurationChange`.

The `Tests/StubSamples/AVFoundationSamples.swift` sample covers these APIs. One difference from the real SDK:
`AVAudioSession`'s notification names are declared `static let`. The real SDK has `class let`, which source code
cannot declare. Call sites are identical.

## Known limits / risks

- **Nothing has been heard yet.** The levels, the per-SFX gains (`SFX.gain`, `LoopKind.gain`, trims) and the
  musical content were judged only from numbers: peak, RMS, spectral centroid. A listening pass on a device is the
  first TODO.
- The first sound triggers buffer decoding on the main actor, which takes a few tens of ms. If that causes a
  visible hitch, preload while the loading screen is shown.
- Music restarts from the top of the current track after the app returns from the background, and after
  interruptions.
- Ambience follows the game pause only through `isWorking`. If machines still report working while the pause
  panel is open, their loops keep playing quietly.
- One-shots are not spatialised (they all play at pan 0). The `pan:` parameter is ready for spatial SFX later.
