# Persistence & progression — status (S6, lead-written + rescued file container)

## Built
- **SaveFile** (rescued): `GFSV` header, META/THMB/WRLD sections, CRC-32, optional compressor, metadata read without world.
- **WorldCodec**: SETT (JSON settings) · CORE (tick, RNG state, bonuses) · SURF (generated chunks, compact arrays) ·
  ENTS (records) · SYS0..9 (each system) · RSCH · CHAR · STAT · extra sections (SESS). Rejects saves made with a
  different GameData (item/entity/recipe counts). Occupancy and chunk entity lists rebuilt on load; systems `didLoad()`.
- **GameSession**: fixed 60 Hz accumulator (max 4 ticks/frame, excess dropped), pause, speed, play time, autosave due flag
  by game time, objective evaluation every 30 ticks, encode/decode with SESS section, file save/load helpers.
- **SaveManager**: slots dir, `.gfsave`, newest-first listing (metadata only), atomic writes, snapshot-on-main + write-anywhere
  split for background saves, rotating autosaves, rename/duplicate/delete with name validation, crash-recovery lock file.
- **Campaign L1–L8** (GDD §7) data incl. kits, tech restrictions, objectives, victory, par/gold; **ObjectiveTracker**
  (all objective kinds, sustain timers, stars); **CampaignProgress** JSON store (stars, best times, unlocks).

## Verified
- Save mid-game → load → both worlds continue **identically** (fingerprint of all systems) — 86 tests green.
- 64 explored chunks + 4.7k entities: 275 KB, encode 22 ms / decode 57 ms (debug).

## Gaps
- Pre-built factories for L5–L8 (designer blueprints) not yet authored; level resource totals approximate (mapgen richness).
