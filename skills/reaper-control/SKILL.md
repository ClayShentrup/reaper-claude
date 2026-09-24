---
name: reaper-control
description: >-
  Inspect and modify a running REAPER (DAW) session by executing ReaScript Lua
  inside it through the local `rs` bridge. Use for ANY request that reads or
  changes an open REAPER project: tracks, items, takes, MIDI notes, FX chains,
  sends and routing, volume/pan, mute/solo, markers and regions, tempo, or
  rendering. Trigger on DAW-shaped requests even when they never say "REAPER",
  "Lua", or "ReaScript" -- for example "mute the guitar", "what's the tempo",
  "turn the vocal up 2 dB", "add a reverb send", "what's on track 3", "list the
  sections", "double the last chorus", "why is the mix muddy". Not for editing
  audio files outside REAPER.
---

# Driving REAPER from Claude

## How to run code

REAPER's binary accepts a script path, and `-nonewinst` hands that script to the
**already-running** instance instead of launching a new one. The `rs` wrapper
builds on that: it captures `print()` output and return values into a temp file
and prints the result.

```bash
echo 'return reaper.CountTracks(0)' | ~/reaper-claude/rs
```

For anything longer than one line, use a quoted heredoc so the shell leaves the
Lua alone:

```bash
cd ~/reaper-claude && ./rs <<'EOF'
dofile(os.getenv("HOME") .. "/reaper-claude/lib.lua")
overview()
EOF
```

Output is `OK` or `ERROR`, then `print()` lines, then `=> <return values>`.

## Every call is a fresh Lua state

Nothing persists between `rs` invocations -- no variables, no helper functions.
Two consequences, and they drive everything else:

1. **Load the helpers explicitly.** Start any non-trivial request with
   `dofile(os.getenv("HOME") .. "/reaper-claude/lib.lua")`. See `references/lib.md`.
2. **Batch aggressively.** Each call is a process spawn plus a poll loop, so it
   is far cheaper to answer five questions in one script than to make five
   round trips. Gather everything you need up front, print it all, then reason
   about it.

## Write safety

These are not style preferences -- REAPER has no autosave, and the user's
unsaved work is live in front of them.

- **Wrap every mutation in one undo block** via `undo("label", function() ... end)`,
  so the user reverts your entire change with a single Cmd+Z. A bare
  `SetMediaTrackInfo_Value` leaves them clicking undo once per property.
- **Never call `reaper.Main_SaveProject`** unless explicitly asked. Leave the
  decision to save with the user.
- **Read before you write.** Print the current value, then set it. When a
  request is relative ("bring the vocal up 2 dB"), you must read first anyway.
- **Resolve names, don't guess indices.** `find("piano")` errors on ambiguity
  rather than picking one; prefer that to hardcoding a track number, which
  silently targets the wrong track after any reorder.
- **Destructive operations** -- deleting tracks or items, `Main_OnCommand`
  render/bounce actions, overwriting media -- get confirmed with the user first.

## Gotchas that cost a wasted round trip

| Trap | Reality |
|---|---|
| `D_VOL` looks like dB | It is **linear amplitude**. Use `db(v)` / `lin(d)` from lib.lua. `1.0` = 0 dB. |
| Track numbering | The API is **0-indexed**; REAPER's UI is 1-indexed. Track "3" in the UI is `GetTrack(0, 2)`. |
| `GetSetMediaTrackInfo_String` | Needs an explicit final arg: `false` to read, `true` to write. Omitting it fails silently. |
| Changes don't appear | Call `reaper.UpdateArrange()` after mutating. `undo()` already does. |
| `%-30s` misaligns names | Lua pads by **bytes**; em-dashes are 3 bytes. Pad by `utf8.len` instead. |
| `I_SOLO` is not boolean | `0` = off, non-zero = soloed (modes differ). `B_MUTE` *is* 0/1. |
| Enabling an FX does nothing | It is **offline**. `TrackFX_SetEnabled(.., true)` no-ops silently on an offline plugin. Check `TrackFX_GetOffline` first. |
| MIDI positions | `MIDI_GetNote` returns **PPQ**, not seconds. Convert with `MIDI_GetProjQNFromPPQPos` or `MIDI_GetProjTimeFromPPQPos`. |

## Environment

Verified against this machine, REAPER **7.79/OSX64**:

- **Stock ReaScript API only.** SWS and js_ReaScriptAPI are **not** installed, so
  do not reach for `CF_*`, `BR_*`, or `JS_*` functions -- they will fail. Check
  with `reaper.APIExists("name")` before relying on anything non-core.
- Lua 5.4, so `utf8.*` is available.
- REAPER must be **running** and the Mac **awake**. A sleeping machine means the
  bridge cannot reach it -- relevant when working over Remote Control.

## Reference

- `references/lib.md` -- the helper library API
- `references/recipes.md` -- verified snippets: tracks, items, MIDI, FX, sends,
  regions, transport
