
local strip_comments = require("tests.helpers").strip_lua_comments

local ROOTS = { "core", "context", "force", "facts", "handlers", "hud", "render", "util" }

local EXPECTED_TEST_ONLY = {}

local function walk(dir, out)
  local p = io.popen('find "' .. dir .. '" -name "*.lua" -type f 2>/dev/null')
  if not p then return out end
  for line in p:lines() do out[#out + 1] = line end
  p:close()
  return out
end

local files = {}
for _, d in ipairs(ROOTS) do walk(d, files) end
files[#files + 1] = "neuro-game.lua"

local src = {}
for _, f in ipairs(files) do
  local fh = io.open(f, "r")
  if fh then src[f] = strip_comments(fh:read("*a")) fh:close() end
end

local test_src = {}
do
  local p = io.popen('find tests -name "*.lua" -type f 2>/dev/null')
  if p then
    for line in p:lines() do
      local fh = io.open(line, "r")
      if fh then test_src[line] = strip_comments(fh:read("*a")) fh:close() end
    end
    p:close()
  end
end

local prod_string_uses = {}
local function harvest_prod_strings(text)
  for s in text:gmatch('"([%a_][%w_]*)"') do prod_string_uses[s] = true end
  for s in text:gmatch("'([%a_][%w_]*)'") do prod_string_uses[s] = true end
end
for _, text in pairs(src) do harvest_prod_strings(text) end

local exports = {}
local export_names = {}
local def_sites = {}

local function local_functions(text)
  local fns = {}
  for name in text:gmatch("local%s+function%s+([%a_][%w_]*)") do fns[name] = true end
  for name in text:gmatch("local%s+([%a_][%w_]*)%s*=%s*function%s*%(") do fns[name] = true end
  for name in text:gmatch("\nfunction%s+([%a_][%w_]*)%s*%(") do fns[name] = true end
  return fns
end

local function module_name(text)
  local last
  for name in text:gmatch("\nreturn%s+([%a_][%w_]*)%s*") do last = name end
  return last
end

local function seam_spans(text)
  local spans = {}
  for open_pos, whole in text:gmatch("()(if%s+[%w_%.]-NEURO_TEST[^\n]-then.-\nend)") do
    spans[#spans + 1] = { open_pos, open_pos + #whole }
  end
  for open_pos, whole in text:gmatch("()(if%s+rawget%(_G,%s*\"NEURO_TEST\"%)%s+then.-end)") do
    spans[#spans + 1] = { open_pos, open_pos + #whole }
  end
  return spans
end

local function in_seam(spans, pos)
  if not pos then return false end
  for _, sp in ipairs(spans) do
    if pos >= sp[1] and pos <= sp[2] then return true end
  end
  return false
end

local function line_of(text, pos)
  if not pos then return nil end
  local _, n = text:sub(1, pos):gsub("\n", "")
  return n + 1
end

local function add_export(file, mod, name, dot_pos, seam, line)
  exports[#exports + 1] = { file = file, mod = mod, name = name, seam = seam or nil, line = line }
  if dot_pos then
    def_sites[file] = def_sites[file] or {}
    def_sites[file][dot_pos] = true
  end
  if export_names[name] and export_names[name].file ~= file then
    print(string.format("[deadexport] DUPLICATE export name '%s': %s.%s vs %s.%s",
      name, export_names[name].mod, name, mod, name))
  end
  export_names[name] = { file = file, mod = mod }
end

for f, text in pairs(src) do
  local fns = local_functions(text)
  local mod_tbl = module_name(text)
  local seams = seam_spans(text)

  for mod, pos, name in text:gmatch("function%s+([%a_][%w_]*)%.()([%a_][%w_]*)%s*%(") do
    add_export(f, mod, name, pos - 1, in_seam(seams, pos), line_of(text, pos))
  end
  if mod_tbl then
    for pos, name, rhs in text:gmatch("%f[%w_]" .. mod_tbl .. "%.()([%a_][%w_]*)%s*=%s*([%a_][%w_]*)") do
      if fns[rhs] or rhs == "function" then
        add_export(f, mod_tbl, name, pos - 1, in_seam(seams, pos), line_of(text, pos))
      end
    end
    for pos, name, rhs in text:gmatch("%f[%w_]" .. mod_tbl .. "%[()\"([%a_][%w_]*)\"%]%s*=%s*([%a_][%w_]*)") do
      if fns[rhs] or rhs == "function" then
        add_export(f, mod_tbl, name, pos - 1, in_seam(seams, pos), line_of(text, pos))
      end
    end
  end
  local literal = text:match("\nreturn%s*(%b{})%s*$") or text:match("\nreturn%s*(%b{})%s*\n%s*$")
  if literal then
    for name, rhs in literal:gmatch("([%a_][%w_]*)%s*=%s*([%a_][%w_]*)") do
      if fns[rhs] then
        add_export(f, "<literal>", name, nil, false, line_of(text, text:find(literal, 1, true)))
      end
    end
  end
end

local function prod_dotted_uses(name)
  local pat = "()[%.:]" .. name .. "%f[^%w_]"
  local n = 0
  for file, text in pairs(src) do
    local defs = def_sites[file]
    for pos in text:gmatch(pat) do
      if not (defs and defs[pos]) then n = n + 1 end
    end
  end
  return n
end

local function test_dotted_uses(name)
  local pat = "[%.:]" .. name .. "%f[^%w_]"
  local n = 0
  for _, text in pairs(test_src) do
    for _ in text:gmatch(pat) do n = n + 1 end
  end
  return n
end

local prod_dead, test_consumer, prod_reachable, seam_live = {}, {}, {}, {}
for _, e in ipairs(exports) do
  local prod_use = prod_dotted_uses(e.name)
  if prod_use <= 0 and not prod_string_uses[e.name] then
    local test_use = test_dotted_uses(e.name)
    if test_use > 0 then
      if e.seam then seam_live[#seam_live + 1] = e else test_consumer[#test_consumer + 1] = e end
    else
      prod_dead[#prod_dead + 1] = e
    end
  else
    prod_reachable[#prod_reachable + 1] = e
  end
end

table.sort(seam_live, function(a, b) return a.file .. a.name < b.file .. b.name end)
table.sort(prod_reachable, function(a, b) return a.file .. a.name < b.file .. b.name end)
table.sort(prod_dead, function(a, b) return a.file .. a.name < b.file .. b.name end)
table.sort(test_consumer, function(a, b) return a.file .. a.name < b.file .. b.name end)

print(string.format("[deadexport] %d exports scanned across %d files", #exports, #files))
print(string.format("[deadexport] %d production-reachable (dotted call or string literal in src)", #prod_reachable))
print("")

if #seam_live > 0 then
  print(string.format("[deadexport] %d NEURO_TEST-guarded seams, each called by a test (informational)", #seam_live))
  print("")
end

if #test_consumer > 0 then
  print("[deadexport] production-dead but consumed by tests:")
  for _, e in ipairs(test_consumer) do
    print(string.format("  %-40s %s.%s", e.file .. ":" .. tostring(e.line or "?"), e.mod, e.name))
  end
  print("")
end

if #prod_dead > 0 then
  print("[deadexport] exports with no dotted call and no matching string literal anywhere:")
  for _, e in ipairs(prod_dead) do
    print(string.format("  %-40s %s.%s", e.file .. ":" .. tostring(e.line or "?"), e.mod, e.name))
  end
  print("")
end

local test_only_names = {}
for _, e in ipairs(test_consumer) do test_only_names[e.name] = true end

local baseline_only = {}
for name in pairs(EXPECTED_TEST_ONLY) do
  if not test_only_names[name] then baseline_only[name] = true end
end
local new_test_only = {}
for _, e in ipairs(test_consumer) do
  if not EXPECTED_TEST_ONLY[e.name] then new_test_only[e.name] = true end
end

local baseline_mismatch = 0
if next(baseline_only) then
  local lst = {}
  for name in pairs(baseline_only) do lst[#lst + 1] = name end
  table.sort(lst)
  print("[deadexport] BASELINE MISSING (in EXPECTED_TEST_ONLY but not classified as test-only):")
  for _, name in ipairs(lst) do
    print("  " .. name)
    baseline_mismatch = baseline_mismatch + 1
  end
  print("")
end
if next(new_test_only) then
  local lst = {}
  for name in pairs(new_test_only) do lst[#lst + 1] = name end
  table.sort(lst)
  print("[deadexport] NEW TEST-ONLY (not in baseline — update EXPECTED_TEST_ONLY):")
  for _, name in ipairs(lst) do
    print("  " .. name)
    baseline_mismatch = baseline_mismatch + 1
  end
  print("")
end

local duplicates = {}
do
  local seen = {}
  for _, e in ipairs(exports) do
    if seen[e.name] then duplicates[e.name] = true else seen[e.name] = true end
  end
end
if next(duplicates) then
  local lst = {}
  for name in pairs(duplicates) do lst[#lst + 1] = name end
  table.sort(lst)
  print("[deadexport] DUPLICATE export names (informational — different modules):")
  for _, name in ipairs(lst) do print("  " .. name) end
end

print(string.format("DEADEXPORT_PRODUCTION_ONLY=%d", #test_consumer))
print(string.format("DEADEXPORT_BASELINE_MISMATCH=%d", baseline_mismatch))

if os.getenv("FAIL_ON_FINDINGS") == "1" and baseline_mismatch > 0 then os.exit(1) end
if os.getenv("FAIL_ON_FINDINGS") == "1" and #prod_dead > 0 then os.exit(1) end
