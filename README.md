# reaper-claude

Let Claude drive a **running** REAPER session — read the project, answer
questions about it, and make changes — by executing ReaScript Lua inside the
live instance.

```bash
echo 'return reaper.CountTracks(0)' | ./rs
```

```
$ ./rs <<'EOF'
dofile(os.getenv("HOME") .. "/reaper-claude/lib.lua"); overview()
EOF
OK
My Song.RPP | 106.0 BPM | 44100 Hz | 240.0 s
 1 Vocals                                0.0 dB  items=2    fx=4
 2 Vocal Plate                          -5.2 dB  items=0    fx=2
 3 Guitar 1                            -12.5 dB  items=6    fx=0  MUTE
 ...
```

## How it works

REAPER's binary accepts a script path, and **`-nonewinst`** hands that script to
the instance that is already running rather than launching a second one. That is
the whole trick. [`rs`](rs) wraps it:

1. Write the Lua to a temp file, inside a shim that captures `print()` and
   return values.
2. `REAPER -nonewinst -noactivate <script>`.
3. Poll for the result file, print it, clean up.

Nothing has to be loaded inside REAPER first. There is no daemon, no listener
script, no wire protocol — the script runs the moment it arrives.

### Why not a polling bridge?

[`claude_bridge.lua`](claude_bridge.lua) is the earlier approach, kept for
reference: a `reaper.defer` loop inside REAPER polls `req.lua`, runs what it
finds, and writes `res.txt`, with `--ID`/`--END` sentinels framing each request.

It works, but everything in it exists to make file polling safe: request IDs,
consume-before-run guards so a crashing request can't loop, a one-at-a-time
queue. And it has to be started manually — if you forget, or REAPER restarts,
the failure mode is a silent hang rather than an error.

`rs` needs none of that. The one thing the bridge had that `rs` does not is a
persistent Lua state, so helpers defined once stayed defined. [`lib.lua`](lib.lua)
covers that: `dofile` it at the top of a request and you have the helpers back.

## Layout

| Path | What |
|---|---|
| [`rs`](rs) | The bridge. Lua on stdin, result on stdout. |
| [`lib.lua`](lib.lua) | Helpers: dB conversion, undo wrapping, track/region lookup. |
| [`skills/reaper-control/`](skills/reaper-control) | A Claude Code skill teaching all of the above. |
| [`claude_bridge.lua`](claude_bridge.lua) | The older polling bridge, for reference. |

## Install the skill

```bash
ln -s "$PWD/skills/reaper-control" ~/.claude/skills/reaper-control
```

Claude then picks it up for DAW-shaped requests — "mute the guitar", "what's the
tempo", "turn the vocal up 2 dB" — without you having to explain the bridge.

## Notes

- Verified against **REAPER 7.79 / macOS**.
- Stock ReaScript API only; this machine has no SWS or js_ReaScriptAPI, so the
  skill avoids `CF_*`, `BR_*`, and `JS_*`.
- REAPER must be running and the machine awake.
- Mutations are wrapped in a single undo block, so any change reverts with one
  Cmd+Z. Nothing saves the project unless you ask.
