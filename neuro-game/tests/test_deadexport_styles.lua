local check, done = require("tests.helpers").harness("deadexport_styles")
local strip = require("tests.helpers").strip_lua_comments

local ROOTS = { "core", "context", "force", "facts", "handlers", "hud", "render", "util" }
local files = { "neuro-game.lua" }
for _, d in ipairs(ROOTS) do
  local p = io.popen('find "' .. d .. '" -name "*.lua" -type f 2>/dev/null')
  if p then
    for line in p:lines() do files[#files + 1] = line end
    p:close()
  end
end

local style1, style2 = 0, 0
for _, f in ipairs(files) do
  local fh = io.open(f, "r")
  if fh then
    local text = strip(fh:read("*a"))
    fh:close()
    for _ in text:gmatch("\nfunction%s+[%a_][%w_]*%.[%a_][%w_]*%s*%(") do style1 = style1 + 1 end
    for _ in text:gmatch("\n[%a_][%w_]*%.[%a_][%w_]*%s*=%s*[%a_][%w_]*%s*\n") do style2 = style2 + 1 end
  end
end

check("the repo really does write the assignment style the scanner used to miss", style2 > 0, style2)

local p = io.popen("luajit tests/dump_deadexport_scan.lua 2>&1")
local out = p:read("*all")
p:close()
local scanned = tonumber(out:match("%[deadexport%] (%d+) exports scanned"))

check("the scanner reports how many exports it found", scanned ~= nil, out:sub(1, 200))
check("and it counts more than the 'function Mod.name(' style alone",
  scanned and scanned > style1, tostring(scanned) .. " scanned vs " .. style1 .. " style-1 defs")

done()
