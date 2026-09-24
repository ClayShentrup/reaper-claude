#!/bin/bash
# Run Lua code inside the running REAPER instance via -nonewinst, and print the result.
# Usage: echo 'return reaper.CountTracks(0)' | ~/reaper-claude/rs
#        ~/reaper-claude/rs < myscript.lua
set -euo pipefail

REAPER_BIN="/Applications/REAPER.app/Contents/MacOS/REAPER"
DIR="$HOME/reaper-claude"
mkdir -p "$DIR"

ID="$$_$(date +%s 2>/dev/null || echo 0)_$RANDOM"
SCRIPT_FILE="$DIR/tmp_${ID}.lua"
RESULT_FILE="$DIR/tmp_${ID}_result.txt"

# Read user Lua from stdin into USER_CODE via a temp file to avoid quoting issues.
USER_CODE_FILE="$DIR/tmp_${ID}_user.lua"
cat > "$USER_CODE_FILE"

cat > "$SCRIPT_FILE" <<LUAEOF
local result_file = "$RESULT_FILE"
local user_code_file = "$USER_CODE_FILE"

local out_lines = {}
local orig_print = print
print = function(...)
  local args = {...}
  local parts = {}
  for i = 1, select("#", ...) do
    parts[i] = tostring(args[i])
  end
  out_lines[#out_lines+1] = table.concat(parts, "\t")
end

local f = io.open(user_code_file, "r")
local user_src = f:read("*a")
f:close()

local chunk, load_err = load(user_src, "user_code")

local function write_result(status, body)
  local rf = io.open(result_file, "w")
  rf:write(status .. "\n")
  if #out_lines > 0 then
    rf:write(table.concat(out_lines, "\n") .. "\n")
  end
  if body ~= nil then
    rf:write(body .. "\n")
  end
  rf:close()
end

if not chunk then
  print = orig_print
  write_result("ERROR", "compile error: " .. tostring(load_err))
else
  local rets = {xpcall(chunk, debug.traceback)}
  local ok = rets[1]
  print = orig_print
  if ok then
    local retvals = {}
    for i = 2, #rets do
      retvals[#retvals+1] = tostring(rets[i])
    end
    local retstr = nil
    if #retvals > 0 then
      retstr = "=> " .. table.concat(retvals, ", ")
    end
    write_result("OK", retstr)
  else
    write_result("ERROR", tostring(rets[2]))
  end
end
LUAEOF

"$REAPER_BIN" -nonewinst -noactivate "$SCRIPT_FILE" >/dev/null 2>&1

# Poll for the result file.
for i in $(seq 1 200); do
  if [ -f "$RESULT_FILE" ]; then
    break
  fi
  sleep 0.02
done

if [ ! -f "$RESULT_FILE" ]; then
  echo "ERROR: timed out waiting for REAPER result" >&2
  rm -f "$SCRIPT_FILE" "$USER_CODE_FILE"
  exit 1
fi

cat "$RESULT_FILE"

rm -f "$SCRIPT_FILE" "$USER_CODE_FILE" "$RESULT_FILE"
