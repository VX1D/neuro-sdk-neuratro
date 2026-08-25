_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local check, done = require("tests.helpers").harness("wire-notation")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")

require("core.actions")
local Registry = require("core.action_registry")

local NAMES = Registry.names()
local IS_NAME = {}
for _, n in ipairs(NAMES) do IS_NAME[n] = true end

local BANNED = { ":integer", ":array", "array[", ">=", ":unique", ":number", ":string", ":boolean" }

local function notation_violation(body)
  if body:find(":%s*[ijN][,}%]]") then return "bare i/j/N token" end
  if body:find("%[%s*[ijN]%s*,") then return "bare token inside an array" end
  if body:gsub("<[^>]*>", "0"):find("[{,]%s*[%a_]") then return "unquoted key" end
  for _, kw in ipairs(BANNED) do
    if body:find(kw, 1, true) then return "schema-keyword notation (" .. kw .. ")" end
  end
  return nil
end

local PINNED_PROSE = {
  ["{primary=an exact visible hand name, fallback=another visible hand name}"] = true,
}

local FIELD_PREFIXES = { '"plan":', "plan=" }

local function top_level_groups(msg)
  local out, depth, start = {}, 0, nil
  for i = 1, #msg do
    local c = msg:sub(i, i)
    if c == "{" then
      if depth == 0 then start = i end
      depth = depth + 1
    elseif c == "}" and depth > 0 then
      depth = depth - 1
      if depth == 0 and start then
        out[#out + 1] = { text = msg:sub(start, i), at = start,
          prefix = msg:sub(math.max(1, start - 40), start - 1) }
        start = nil
      end
    end
  end
  return out
end

local function attached_name(prefix)
  local name = prefix:match("([%w_]+)|$")
  return (name and IS_NAME[name]) and name or nil
end

local function is_field(prefix)
  for _, p in ipairs(FIELD_PREFIXES) do
    if prefix:sub(-#p) == p then return true end
  end
  return false
end

local function top_keys(body)
  local flat = body:sub(2, -2)
  local prev
  repeat
    prev = flat
    flat = flat:gsub("%b{}", ""):gsub("%b[]", ""):gsub("%b<>", "")
  until flat == prev
  local out = {}
  for key in flat:gmatch('"([%w_]+)"%s*:') do out[#out + 1] = key end
  return out
end

local function order_index(list)
  local idx = {}
  for i, k in ipairs(list) do idx[k] = i end
  return idx
end

local bad, groups_seen, boards, per_name = {}, 0, 0, {}

local function audit(label, msg)
  for _, kw in ipairs(BANNED) do
    if msg:find(kw, 1, true) then
      local at = msg:find(kw, 1, true)
      bad[#bad + 1] = label .. ": schema-keyword notation on the wire -- " .. kw
        .. " in ..." .. msg:sub(math.max(1, at - 60), at + 40) .. "..."
    end
  end
  for _, g in ipairs(top_level_groups(msg)) do
    groups_seen = groups_seen + 1
    local name = attached_name(g.prefix)
    if name then
      per_name[name] = (per_name[name] or 0) + 1
      local v = notation_violation(g.text)
      if v then bad[#bad + 1] = label .. ": " .. name .. " payload -- " .. v .. " in " .. g.text end
      local prompt = Registry.prompt(name) or ""
      local canon = prompt:gsub(", optional>", ">")
      for ph in g.text:gmatch("%b<>") do
        if not canon:find((ph:gsub(", optional>", ">")), 1, true) then
          bad[#bad + 1] = label .. ": " .. name .. " is shown placeholder " .. ph
            .. " that core/action_registry.lua never renders -- " .. prompt
        end
      end
      local want = order_index(top_keys(prompt:match("|(%b{})") or "{}"))
      local last = 0
      for _, key in ipairs(top_keys(g.text)) do
        local at = want[key]
        if not at then
          bad[#bad + 1] = label .. ": " .. name .. " payload states key " .. string.format("%q", key)
            .. " the registry contract does not have -- " .. g.text
        elseif at < last then
          bad[#bad + 1] = label .. ": " .. name .. " payload reorders the contract's keys -- " .. g.text
        else
          last = at
        end
      end
    elseif is_field(g.prefix) then
      local v = notation_violation(g.text)
      if v then bad[#bad + 1] = label .. ": plan field -- " .. v .. " in " .. g.text end
    elseif not PINNED_PROSE[g.text] then
      bad[#bad + 1] = label .. ": hand-written object on the wire, attached to no action -- "
        .. string.format("%q", g.prefix:sub(-30)) .. " >> " .. g.text
    end
  end
end

for _, board in ipairs(LB.BOARDS) do
  LB.load(board.state, board.desc)
  local payload = FP.build(board.state)
  if payload then
    boards = boards + 1
    audit(board.state .. "/" .. board.desc, payload.message)
  else
    bad[#bad + 1] = board.state .. "/" .. board.desc .. ": no force at all"
  end
end

check("the sweep read a real wire payload for every board",
  boards >= 11 and FP.captures() >= boards,
  "boards: " .. boards .. ", payloads captured: " .. FP.captures())
check("the sweep found action payloads to audit, not an empty message",
  groups_seen >= 60, "top-level JSON objects on the wire: " .. groups_seen)
check("play_hand -- the action F1 was answered wrongly for -- was actually audited",
  (per_name.play_hand or 0) > 0, "play_hand payloads seen: " .. tostring(per_name.play_hand))
check("every JSON object the model is sent is a registry render of the action it names",
  #bad == 0, "\n  " .. table.concat(bad, "\n  "))

do
  local WIRE = "State: SELECTING_HAND. You still need 300 chips. "
  local M9A = "To play, send play_hand with {indices:array[1-5]:unique}. "
  local TAIL = 'Your move: play_hand|{"indices":[<pick 1 to 5 different hand positions>],"plan":<object, optional>}.'

  local keep = bad
  local function audits(text)
    bad = {}
    audit("selftest", text)
    local out = bad
    bad = keep
    return out
  end

  check("the clean payload this guard passes really is clean", #audits(WIRE .. TAIL) == 0,
    table.concat(audits(WIRE .. TAIL), " | "))
  check("a hand-written example in prose is caught wherever it sits",
    #audits(WIRE .. M9A .. TAIL) > 0, "the F1 sentence passed the auditor")
  check("and still caught immediately before the 'Your move' tail",
    #audits(WIRE .. TAIL:gsub("^Your move", M9A .. "Your move")) > 0,
    "the F1 sentence passed when placed next to the correct render")
  check("a second spelling with clean notation is caught too, not just the keywords",
    #audits(WIRE .. 'Send play_hand|{"cards":[1,2,3]} to play. ' .. TAIL) > 0,
    "an off-contract key passed the auditor")
end

done()
