_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} }, TIMERS = { REAL = 100 } }

local check, done = require("tests.helpers").harness("action-example-source")

require("core.actions")
local Registry = require("core.action_registry")

local DIRS = { "force", "context", "handlers", "facts", "core", "util" }

local PINNED = {
  ["force/force_pack.lua"] = {
    ['use_card|{"area":"booster_pack","index":%d,"hand_indices":[<%s>]}'] = true,
  },
  ["force/menu_flow.lua"] = {
    ['paste_seed|{"seed":"ABC123XY"}'] = true,
  },
}

local function notation_violation(payload)
  if payload:find(":%s*[ijN][,}%]]") then return "bare i/j/N token" end
  if payload:find("%[%s*[ijN]%s*,") then return "bare token inside an array" end
  if payload:gsub("<[^>]*>", "0"):find("[{,]%s*[%a_]") then return "unquoted key" end
  if payload:find(":integer") or payload:find(":array") or payload:find(">=") then
    return "schema-keyword notation"
  end
  return nil
end

local function scan(text)
  local found = {}
  for name, payload in text:gmatch("([%w_]+)|(%b{})") do
    if Registry.get(name) and payload ~= "{}" then
      found[#found + 1] = { name = name, payload = payload }
    end
  end
  return found
end

local files = {}
do
  local pipe = assert(io.popen("find " .. table.concat(DIRS, " ") .. " -name '*.lua' | sort", "r"))
  for line in pipe:lines() do files[#files + 1] = line end
  pipe:close()
end
check("the scan reaches the runtime tree", #files > 90, tostring(#files))

local seen = {}
for _, path in ipairs(files) do
  local f = io.open(path, "r")
  local src = f and f:read("*all") or ""
  if f then f:close() end
  for _, hit in ipairs(scan(src)) do
    local literal = hit.name .. "|" .. hit.payload
    local allowed = PINNED[path] and PINNED[path][literal]
    check("" .. path .. ": " .. hit.name .. " example is registry-derived or pinned",
      allowed == true,
      "hand-written " .. hit.name .. "|" .. hit.payload
      .. " -- render it with ActionRegistry.prompt/example/render instead")
    if allowed then
      seen[path] = seen[path] or {}
      seen[path][literal] = true
    end
    check("" .. path .. ": " .. hit.name .. " literal keeps the one notation",
      notation_violation(hit.payload) == nil,
      tostring(notation_violation(hit.payload)) .. " in " .. hit.payload)
  end
end

local PROSE_PINNED = {
  ["force/force_blind_select.lua"] = {
    ["{primary=an exact visible hand name, fallback=another visible hand name}"] = true,
  },
}

local function string_literals(src)
  local out = {}
  for lit in src:gmatch('"([^"\n]*)"') do out[#out + 1] = lit end
  for lit in src:gmatch("'([^'\n]*)'") do out[#out + 1] = lit end
  for lit in src:gmatch("%[%[(.-)%]%]") do out[#out + 1] = lit end
  return out
end

local SCHEMA_KEYWORDS = { ":integer", ":array", "array[", ">=", ":unique", ":number", ":string" }
local function schema_keyword(text)
  for _, kw in ipairs(SCHEMA_KEYWORDS) do
    if text:find(kw, 1, true) then return kw end
  end
  return nil
end

local function objects_in(lit)
  local out, from = {}, 1
  while true do
    local i = lit:find("{", from, true)
    if not i then return out end
    local grp = lit:match("%b{}", i)
    if not grp then return out end
    out[#out + 1] = { text = grp, before = lit:sub(1, i - 1) }
    from = i + #grp
  end
end

local function prose_scan(src)
  local found = {}
  for _, lit in ipairs(string_literals(src)) do
    for _, obj in ipairs(objects_in(lit)) do
      local attached = obj.before:match("([%w_]+)|$")
      if not (attached and Registry.get(attached)) then
        local named
        for _, name in ipairs(Registry.names()) do
          if obj.before:find(name, 1, true) then named = name break end
        end
        if named or schema_keyword(obj.text) then
          found[#found + 1] = { text = obj.text, named = named or "(schema notation)" }
        end
      end
    end
  end
  return found
end

local prose_seen = {}
for _, path in ipairs(files) do
  local f = io.open(path, "r")
  local src = f and f:read("*all") or ""
  if f then f:close() end
  for _, hit in ipairs(prose_scan(src)) do
    local allowed = PROSE_PINNED[path] and PROSE_PINNED[path][hit.text]
    check("" .. path .. ": an object shown beside " .. hit.named .. " is a registry render",
      allowed == true,
      "hand-written " .. hit.text .. " in prose naming " .. hit.named
      .. " -- render it with ActionRegistry.prompt/example/render instead")
    if allowed then
      prose_seen[path] = prose_seen[path] or {}
      prose_seen[path][hit.text] = true
    end
  end
end
for path, texts in pairs(PROSE_PINNED) do
  for text in pairs(texts) do
    check("" .. path .. ": the pinned prose object is still there",
      prose_seen[path] and prose_seen[path][text] == true, text)
  end
end

do
  local M9A = "To play, send play_hand with {indices:array[1-5]:unique}. "
  local hits = prose_scan("local s = '" .. M9A .. "'")
  check("the prose spelling of the F1 example is extracted", #hits == 1, tostring(#hits))
  check("and it is pinned nowhere",
    not (PROSE_PINNED["force/force_selecting_hand.lua"] or {})[hits[1] and hits[1].text],
    hits[1] and hits[1].text or "nothing extracted")
  check("a correct registry render in the same prose is not flagged",
    #prose_scan("local s = 'Your move: ' .. \"" .. Registry.prompt("play_hand") .. "\"") == 0,
    Registry.prompt("play_hand"))
end

for path, payloads in pairs(PINNED) do
  for payload in pairs(payloads) do
    check("" .. path .. ": the pinned literal is still there",
      seen[path] and seen[path][payload] == true, payload)
  end
end

do
  local REGRESSION = 'local s = \'use_card|{"area":"consumeables","index":N,"hand_indices":[N,...]}\''
  local hits = scan(REGRESSION)
  check("the removed literal is still extracted", #hits == 1, tostring(#hits))
  if hits[1] then
    check("it is not pinned for any file",
      not (PINNED["force/force_selecting_hand.lua"] or {})[hits[1].name .. "|" .. hits[1].payload],
      hits[1].payload)
    check("its notation is rejected on its own",
      notation_violation(hits[1].payload) ~= nil, hits[1].payload)
  end
  check("a registry render passes the same notation check",
    notation_violation((Registry.prompt("use_card"):gsub("^use_card|", ""))) == nil,
    Registry.prompt("use_card"))
end

done()
