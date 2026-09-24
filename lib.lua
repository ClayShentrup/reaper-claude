-- lib.lua — helpers for driving REAPER from Claude via ./rs
--
-- Each ./rs call is a fresh Lua state, so nothing persists between requests.
-- Load these helpers at the top of any request:
--     dofile(os.getenv("HOME") .. "/reaper-claude/lib.lua")

local M = {}

-- ---------------------------------------------------------------- units ---
-- D_VOL and send volumes are LINEAR amplitude, not dB.
function M.db(v)  return v > 0 and 20 * math.log(v, 10) or -math.huge end
function M.lin(d) return 10 ^ (d / 20) end

-- ----------------------------------------------------------------- undo ---
-- Wrap every mutation so the user can revert the whole thing with one Cmd+Z.
function M.undo(label, fn)
  reaper.Undo_BeginBlock()
  local ok, err = pcall(fn)
  reaper.Undo_EndBlock(label, -1)
  reaper.UpdateArrange()
  if not ok then error(err, 0) end
end

-- --------------------------------------------------------------- tracks ---
function M.name(tr)
  local _, n = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
  return n
end

function M.set_name(tr, n)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", n, true)
end

-- Iterate every track: for i, tr, name in tracks() do ... end  (i is 1-based)
function M.tracks()
  local i = -1
  return function()
    i = i + 1
    if i >= reaper.CountTracks(0) then return nil end
    local tr = reaper.GetTrack(0, i)
    return i + 1, tr, M.name(tr)
  end
end

-- Case-insensitive substring match; errors if ambiguous so we never guess.
function M.find(pattern)
  local hits = {}
  for i, tr, n in M.tracks() do
    if n:lower():find(pattern:lower(), 1, true) then
      hits[#hits + 1] = { i = i, tr = tr, name = n }
    end
  end
  if #hits == 0 then error('no track matching "' .. pattern .. '"', 0) end
  if #hits > 1 then
    local names = {}
    for _, h in ipairs(hits) do names[#names + 1] = h.i .. ":" .. h.name end
    error('ambiguous "' .. pattern .. '" -> ' .. table.concat(names, ", "), 0)
  end
  return hits[1].tr, hits[1].i, hits[1].name
end

-- ---------------------------------------------------------------- items ---
function M.items(tr)
  local i = -1
  return function()
    i = i + 1
    if i >= reaper.CountTrackMediaItems(tr) then return nil end
    local it = reaper.GetTrackMediaItem(tr, i)
    return i + 1, it,
      reaper.GetMediaItemInfo_Value(it, "D_POSITION"),
      reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  end
end

-- -------------------------------------------------------------- regions ---
function M.regions()
  local out, i = {}, 0
  while true do
    local ret, isrgn, pos, rgnend, nm, idx = reaper.EnumProjectMarkers(i)
    if ret == 0 then break end
    if isrgn then out[#out + 1] = { idx = idx, pos = pos, ["end"] = rgnend, name = nm } end
    i = i + 1
  end
  return out
end

-- Time span of a named region, for scoping edits to "the second chorus".
function M.region(pattern)
  for _, r in ipairs(M.regions()) do
    if r.name:lower():find(pattern:lower(), 1, true) then return r.pos, r["end"], r.name end
  end
  error('no region matching "' .. pattern .. '"', 0)
end

-- --------------------------------------------------------------- report ---
-- Pad to a display width in CHARACTERS. %-34s pads by bytes, which misaligns
-- any name containing multi-byte UTF-8 (em-dashes are 3 bytes each).
local function pad(s, w)
  local n = utf8 and utf8.len(s) or #s
  return s .. string.rep(" ", math.max(0, w - (n or #s)))
end

function M.overview()
  local _, path = reaper.EnumProjects(-1, "")
  print(("%s | %.1f BPM | %.0f Hz | %.1f s"):format(
    path:match("[^/]+$") or path, reaper.Master_GetTempo(),
    reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false), reaper.GetProjectLength(0)))
  for i, tr, n in M.tracks() do
    local flags = {}
    if reaper.GetMediaTrackInfo_Value(tr, "B_MUTE") == 1 then flags[#flags + 1] = "MUTE" end
    if reaper.GetMediaTrackInfo_Value(tr, "I_SOLO") > 0 then flags[#flags + 1] = "SOLO" end
    print(("%2d %s %6.1f dB  items=%-4d fx=%-2d %s"):format(
      i, pad(n, 34), M.db(reaper.GetMediaTrackInfo_Value(tr, "D_VOL")),
      reaper.CountTrackMediaItems(tr), reaper.TrackFX_GetCount(tr), table.concat(flags, " ")))
  end
end

-- Export into the caller's global namespace for terse one-off requests.
for k, v in pairs(M) do _G[k] = v end
return M
