# Verified ReaScript recipes

Every snippet below was run against a live REAPER 7.79 session. Anything not
verified is marked **[unverified]** -- check it before relying on it.

All assume `dofile(os.getenv("HOME") .. "/reaper-claude/lib.lua")` at the top.

## Project overview

```lua
local _, path = reaper.EnumProjects(-1, "")
local num, den = reaper.TimeMap_GetTimeSigAtTime(0, 0)
print(path, reaper.Master_GetTempo(), num .. "/" .. den,
      reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false),
      reaper.GetProjectLength(0))
```

## Tracks

```lua
for i, tr, n in tracks() do
  print(i, n,
    db(reaper.GetMediaTrackInfo_Value(tr, "D_VOL")),
    reaper.GetMediaTrackInfo_Value(tr, "D_PAN"),
    reaper.GetMediaTrackInfo_Value(tr, "B_MUTE") == 1,
    reaper.GetMediaTrackInfo_Value(tr, "I_SOLO") > 0)
end
```

Set a level, relative to where it currently sits:

```lua
local tr = find("vocals")
undo("Vocal +2 dB", function()
  local cur = db(reaper.GetMediaTrackInfo_Value(tr, "D_VOL"))
  reaper.SetMediaTrackInfo_Value(tr, "D_VOL", lin(cur + 2))
end)
```

Mute / unmute:

```lua
undo("Mute Guitar 1", function()
  reaper.SetMediaTrackInfo_Value(find("Guitar 1"), "B_MUTE", 1)
end)
```

## Items and takes

```lua
for i, it, pos, len in items(find("vocals")) do
  local tk = reaper.GetActiveTake(it)
  print(i, pos, len, tk and reaper.GetTakeName(tk), tk and reaper.TakeIsMIDI(tk))
end
```

## MIDI notes

`MIDI_GetNote` returns PPQ, not seconds -- convert before reporting times.

```lua
local tk = reaper.GetActiveTake(reaper.GetTrackMediaItem(find("Guitar 1"), 0))
local _, notes = reaper.MIDI_CountEvts(tk)
for n = 0, notes - 1 do
  local _, sel, mute, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(tk, n)
  local beat = reaper.MIDI_GetProjQNFromPPQPos(tk, sppq)
  local secs = reaper.MIDI_GetProjTimeFromPPQPos(tk, sppq)
  print(pitch, vel, beat, secs)
end
```

## FX chains

```lua
local tr = find("vocals")
for i = 0, reaper.TrackFX_GetCount(tr) - 1 do
  local _, nm = reaper.TrackFX_GetFXName(tr, i, "")
  print(i, nm, reaper.TrackFX_GetEnabled(tr, i))   -- false = bypassed
end
```

Bypass or re-enable:

```lua
undo("Bypass 1176", function() reaper.TrackFX_SetEnabled(tr, 2, false) end)
```

**An offline plugin cannot be enabled.** `TrackFX_SetEnabled(tr, i, true)` on an
offline FX returns without error and without effect -- verified on a UAD plugin
that had gone offline. Always check first, and bring it online if that is what
the user actually wants:

```lua
if reaper.TrackFX_GetOffline(tr, i) then
  print("fx " .. i .. " is OFFLINE -- enabling it will silently no-op")
  -- reaper.TrackFX_SetOffline(tr, i, false)
end
```

## Sends and routing

Category `0` = sends from this track. `P_DESTTRACK` returns the destination
MediaTrack, so a full routing map is one pass:

```lua
for i, tr, n in tracks() do
  for s = 0, reaper.GetTrackNumSends(tr, 0) - 1 do
    local dest = reaper.GetTrackSendInfo_Value(tr, 0, s, "P_DESTTRACK")
    print(n, "->", name(dest),
      db(reaper.GetTrackSendInfo_Value(tr, 0, s, "D_VOL")))
  end
end
```

Create a send -- `CreateTrackSend` returns the new send index:

```lua
undo("Send vocals to plate", function()
  local idx = reaper.CreateTrackSend(find("Vocals"), find("Vocal Plate"))
  reaper.SetTrackSendInfo_Value(find("Vocals"), 0, idx, "D_VOL", lin(-12))
end)
```

## Regions and sections

Song sections are usually regions. Scope edits by name rather than by raw time:

```lua
for _, r in ipairs(regions()) do print(r.idx, r.pos, r["end"], r.name) end

local s, e = region("final chorus")
```

## Transport and selection

```lua
print(reaper.GetCursorPosition())
local s, e = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)  -- read
reaper.GetSet_LoopTimeRange(true, false, 120.0, 140.0, false)        -- write
reaper.SetEditCurPos(120.0, true, false)   -- args: pos, moveview, seekplay
print(reaper.CountSelectedTracks(0), reaper.CountSelectedMediaItems(0))
```

## Capability probing

No SWS or js_ReaScriptAPI on this machine. Probe before using anything non-core:

```lua
if reaper.APIExists("CF_GetSWSVersion") then ... end
```

## Actions

Anything without a direct API call can go through the action list, but action
IDs are easy to get wrong and some are destructive -- confirm before running.

```lua
reaper.Main_OnCommand(40044, 0)  -- transport: play/stop  [unverified]
```
