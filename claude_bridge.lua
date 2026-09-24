-- claude_bridge.lua  --  run Lua sent by Claude inside REAPER
--
-- Protocol (one request at a time), all in ~/reaper-claude/:
--   req.lua  first line "--ID <n>", last line "--END"
--   res.txt  written by this bridge: "--ID <n>", print() output, return
--            values ("=> ..."), then --DONE | --COMPILE_ERROR | --RUNTIME_ERROR
--            with the error message / traceback.
-- An empty req.lua means idle. The bridge empties it before running the code,
-- so a crashing request can never loop.
-- State persists between requests (helpers defined once stay defined).
-- undo("label", function() ... end) wraps changes in one undo step.

local dir = os.getenv("HOME") .. "/reaper-claude/"
local REQ, RES = dir .. "req.lua", dir .. "res.txt"
local traceback = (debug and debug.traceback) or function(e) return tostring(e) end

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function write(path, s)
  local f = io.open(path, "wb")
  if not f then return end
  f:write(s)
  f:close()
end

local out -- output lines for the request currently running
local env = setmetatable({}, { __index = _G })
env.print = function(...)
  local t = {}
  for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
  out[#out + 1] = table.concat(t, "\t")
end
env.undo = function(label, fn)
  reaper.Undo_BeginBlock()
  local ok, e = pcall(fn)
  reaper.Undo_EndBlock(label, -1)
  reaper.UpdateArrange()
  if not ok then error(e, 0) end
end

local function run(code)
  local id = code:match("^%-%-ID%s+(%S+)") or "?"
  out = {}
  local status, detail
  local chunk, err = load(code, "=req", "t", env)
  if not chunk then
    status, detail = "COMPILE_ERROR", err
  else
    local r = table.pack(xpcall(chunk, traceback))
    if r[1] then
      status = "DONE"
      local rets = {}
      for i = 2, r.n do rets[#rets + 1] = tostring(r[i]) end
      if #rets > 0 then out[#out + 1] = "=> " .. table.concat(rets, "\t") end
    else
      status, detail = "RUNTIME_ERROR", tostring(r[2])
    end
  end
  local body = "--ID " .. id .. "\n"
  if #out > 0 then body = body .. table.concat(out, "\n") .. "\n" end
  if detail then body = body .. detail .. "\n" end
  write(RES, body .. "--" .. status .. "\n")
end

local function tick()
  local code = read(REQ)
  if code and code:find("%-%-END%s*$") then
    write(REQ, "") -- consume first
    run(code)
  end
  reaper.defer(tick)
end

reaper.ShowConsoleMsg("Claude bridge listening: " .. dir .. "\n")
tick()
