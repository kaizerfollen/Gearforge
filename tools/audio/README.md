# tools/audio — procedural sound generator

Every sound in Gearforge comes from `generate.py`. It synthesises them from scratch with numpy and scipy. It uses no
samples and downloads nothing. The output goes into `App/Resources/Sounds/`, which the Xcode project copies into the
bundle as the folder reference `Sounds`. Each sound has a fixed RNG seed, so the output is the same, byte for byte,
on every run.

```sh
pip install numpy scipy --break-system-packages   # if missing
python3 tools/audio/generate.py                   # regenerate everything, then verify
python3 tools/audio/generate.py --only ui_tap     # regenerate some sounds, then verify all
python3 tools/audio/generate.py --check           # only verify the files on disk
```

After each run the script prints a verification table. It checks:
- the format: mono, 16-bit, and the expected sample rate;
- that no peak goes above 0.9;
- duration limits: one-shots ≤ 1.5 s, rocket 4–6 s, loops 1–3 s, music 60–90 s;
- that one-shots start and end at silence;
- loop seams: the jump from the last sample to the first must be no larger than the 99.9th percentile of all
  sample-to-sample steps, and the RMS of the first 50 ms and the last 50 ms must be within 6 dB of each other;
- that each music file is under 2.5 MB and the total is under 6 MB.

The process exits non-zero if any check fails.

## Formats

| group            | rate      | notes |
|------------------|-----------|-------|
| one-shots, loops | 44.1 kHz  | 16-bit mono WAV |
| music            | 16 kHz    | 16-bit mono WAV. 22.05 kHz × 60 s would be 2.65 MB per track, which breaks both the 2.5 MB-per-track and the 6 MB-total budgets. The pads and plucks have almost nothing above 7 kHz, so 16 kHz loses little. |

## Sounds

| file | what |
|------|------|
| `ui_tap` | soft tick (sine ping + filtered noise click) |
| `ui_open` / `ui_close` | two-note pluck, rising / falling (A5 to D6) |
| `ui_error` | gentle low double buzz (D3, odd harmonics, low-passed) |
| `ui_success` | three-note bell chime D5–A5–D6 (research done, objective, level) |
| `ui_craft_done` | small pitch-drop pop |
| `build_place` | metallic clunk: falling thump, inharmonic plate modes, noise transient, small settle |
| `build_remove` | reverse-shaped band-noise whoosh that rises into a tick |
| `rotate` | three-click ratchet |
| `paste` | short whoosh and two light stamps |
| `mine_hit_ore` / `mine_hit_tree` | pick on rock (ping and debris) / wood chop (wooden modes) |
| `mine_done` | crumble and pop |
| `pickup` | quick E5 to A5 pluck |
| `footstep_1..4` | soft dirt/grass steps; each has its own filter, scuff timing and thump pitch |
| `rocket_launch` | 4.6 s rumble that swells and rises, with crackle and a sub tone |
| `alert` | soft two-tone A5 to E5 with an echo |
| `loop_assembler` (1.2 s) | 98 Hz hum, gear whirr and two soft clanks |
| `loop_furnace` (1.5 s) | low roar, flame flicker and crackle |
| `loop_drill` (1.0 s) | motor with rotation AM, grinding band and rumble |
| `loop_belt` (1.0 s) | soft slat rattle over a roller rumble |
| `loop_steam_engine` (1.2 s) | four chuffs per loop with piston thumps and hiss |
| `loop_boiler` (1.5 s) | low boil roar, bubbles and hiss |
| `loop_inserter` (1.0 s) | servo whine on two moves, stop clicks and idle hum |
| `loop_lab` (1.5 s) | soft chorused 110 Hz hum and quiet pentatonic bleeps |
| `loop_pumpjack` (2.0 s) | one stroke per loop: motor, thumps, creak and gurgle |
| `music_1` (60 s) | D dorian, Dm9–Fmaj7–Am7–G6 pads, plucked arpeggio and bells |
| `music_2` (60 s) | A aeolian, Am(add9)–Fmaj7–Dm9–Em7, sparser and darker |

## Seamless loops

Machine loops and music are rendered **circularly**, so they need no crossfade:
- Every steady tone has a whole number of cycles per loop (`qf`).
- Noise is built in the frequency domain (`fft_noise`). An inverse FFT is periodic by construction.
- IIR filters run over three copies of the signal, and the script keeps the last copy (`cfilt`).
- Reverb is a circular FFT convolution.
- Any event that runs past the end wraps around to the start (`place(..., wrap=True)`).

As a result, sample N-1 leads into sample 0 exactly as any two neighbouring samples do.

## Adding a sound

1. Write a function `s_name(rng) -> np.ndarray` (or `l_` / `m_`).
2. Register it with `reg(...)` and a new seed.
3. If the game should play it, add a case to `AudioManager.SFX` or `LoopKind`.
