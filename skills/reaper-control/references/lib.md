# lib.lua helper API

Load at the top of any request. It exports into globals, so call helpers bare.

```lua
dofile(os.getenv("HOME") .. "/reaper-claude/lib.lua")
```

| Helper | Purpose |
|---|---|
| `db(v)` | Linear amplitude -> dB. `db(1.0)` = 0. |
| `lin(d)` | dB -> linear amplitude, for writing `D_VOL`. |
| `undo(label, fn)` | Run `fn` inside one undo block, then `UpdateArrange()`. Re-raises errors after closing the block so a failure can't leave it open. |
| `name(tr)` / `set_name(tr, s)` | Track name read/write, with the `false`/`true` arg handled. |
| `tracks()` | Iterator: `for i, tr, n in tracks() do` -- `i` is **1-based**, matching the REAPER UI. |
| `find(pattern)` | Case-insensitive substring track lookup -> `tr, i, name`. **Errors on zero or multiple matches** rather than guessing. |
| `items(tr)` | Iterator: `for i, it, pos, len in items(tr) do`. |
| `regions()` | Array of `{idx, pos, end, name}` for all regions. |
| `region(pattern)` | Named region lookup -> `startPos, endPos, name`. Use to scope an edit to "the bridge". |
| `overview()` | Print project header plus a per-track table. Good opening move on an unfamiliar session. |

## Why `find` errors instead of picking

Guessing a track silently applies the edit to the wrong one, and the user may
not notice until much later. Surfacing the ambiguity costs one round trip:

```
ambiguous "guitar" -> 3:Guitar 1, 4:Guitar 2, 5:Guitar Chords — reference
```

Ask which one they meant, or narrow the pattern.
