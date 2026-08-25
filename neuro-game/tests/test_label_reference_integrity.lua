_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local check, done = require("tests.helpers").harness("label-reference-integrity")

local Actions = require("core.actions")
local Dispatcher = require("core.dispatcher")
local ContextCompact = require("context.context_compact")
local TokenLegends = require("facts.token_legends")
local TD = require("tests.test_deadlock")

local WIPE = { "hand", "jokers", "consumeables", "shop_jokers", "shop_vouchers", "shop_booster",
  "shop", "pack_cards", "booster_pack", "blind_select_opts", "blind_select", "OVERLAY_MENU",
  "P_BLINDS", "P_TAGS", "P_CENTER_POOLS" }

local STATE_ID, next_id = {}, 0
local function enter_state(name)
  if not STATE_ID[name] then next_id = next_id + 1; STATE_ID[name] = next_id end
  G.STATES = G.STATES or {}
  G.STATES[name] = STATE_ID[name]
  G.STATE = STATE_ID[name]
end

local emitted = {}

local function absorb(text)
  if type(text) == "string" and text ~= "" then emitted[#emitted + 1] = text end
end

local function load_scenario(sc)
  for _, k in ipairs(WIPE) do G[k] = nil end
  G.NEURO = { dispatcher = Dispatcher, actions = Actions, persona = "neuro",
    reserved_dollars = 0, shop_reroll_count = 0, _decision_windows = {}, state_enter_serial = 1 }
  if not pcall(TD.apply_mock, sc.mock()) then return false end
  enter_state(sc.state)
  ContextCompact.invalidate_cache()
  return true
end

local function capture(state_name, with_force)
  if with_force then
    local ok_f, force = pcall(Dispatcher.get_force_for_state, state_name)
    if ok_f and type(force) == "table" then absorb(tostring(force.query or "")) end
  end
  ContextCompact.invalidate_cache()
  for _, split in ipairs({ "volatile", "stable" }) do
    local ok_c, ctx = pcall(ContextCompact.build, state_name, nil,
      { split = split, full_jokers = true, no_cache = true })
    if ok_c then absorb(ctx) end
  end
end

for _, sc in ipairs(TD.SCENARIOS) do
  if not sc.no_force and load_scenario(sc) then capture(sc.state, true) end
end

local function scenario_for(state_name, desc_match)
  for _, sc in ipairs(TD.SCENARIOS) do
    if sc.state == state_name and sc.desc:find(desc_match, 1, true) then return sc end
  end
  return nil
end

do
  local sc = scenario_for("SHOP", "Normal")
  if sc and load_scenario(sc) then
    G.GAME.hands = {
      Pair = { visible = true, level = 2, chips = 20, mult = 3, played = 6 },
      Flush = { visible = true, level = 1, chips = 35, mult = 4, played = 0 },
    }
    capture("SHOP", false)
  end
end

do
  local sc = scenario_for("RUN_SETUP", "Run setup overlay active")
  if sc and load_scenario(sc) then
    G.P_CENTER_POOLS = { Stake = {
      { key = "stake_white", loc_txt = { name = "White Stake" } },
      { key = "stake_red", loc_txt = { name = "Red Stake" } },
    } }
    capture("RUN_SETUP", false)
  end
end

do
  local sc = scenario_for("BLIND_SELECT", "Small blind selectable")
  if sc and load_scenario(sc) then
    G.P_BLINDS = {
      bl_small = { name = "Small Blind", dollars = 3, debuff = {} },
      bl_big = { name = "Big Blind", dollars = 4, debuff = {} },
      bl_hook = { name = "The Hook", dollars = 5, debuff = {}, boss = { min = 1 } },
    }
    G.P_TAGS = { tag_charm = { name = "Charm Tag", config = {} } }
    G.GAME.round_resets.blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" }
    G.GAME.round_resets.blind_tags = { Small = "tag_charm" }
    capture("BLIND_SELECT", false)
  end
end

local emitted_blob = table.concat(emitted, "\n")
check("the emitted corpus is non-empty, so the scan has something to check against",
  #emitted > 0 and #emitted_blob > 2000, #emitted .. " chunks / " .. #emitted_blob .. " B")

local described = {}
for _, def in ipairs(Actions.get_static_actions()) do
  if type(def.description) == "string" then
    described[#described + 1] = { where = "action " .. tostring(def.name), text = def.description }
  end
end
described[#described + 1] = { where = "token_legends READABLE_COMMON", text = TokenLegends.READABLE_COMMON }
described[#described + 1] = { where = "token_legends READABLE_JOKER_TAGS", text = TokenLegends.READABLE_JOKER_TAGS }
for state, text in pairs(TokenLegends.READABLE_STATE) do
  described[#described + 1] = { where = "token_legends READABLE_STATE " .. state, text = text }
end
for i, text in ipairs(emitted) do
  described[#described + 1] = { where = "force/context chunk " .. i, text = text }
end

check("model-facing descriptions were collected", #described > 20, tostring(#described))

local SHAPES = {
  { pattern = "%f[%u]([A-Z][A-Z]?[A-Z]?):", suffix = ":" },
  { pattern = "%f[%u]([A-Z][A-Z]+)%s+rows?", suffix = "" },
  { pattern = "%f[%u]([A-Z][A-Z]+)%s+list", suffix = "" },
  { pattern = "%f[%u]([A-Z][A-Z]+)%s+column", suffix = "" },
}

local function labels_in(text)
  local out = {}
  for _, shape in ipairs(SHAPES) do
    for token in text:gmatch(shape.pattern) do out[#out + 1] = token .. shape.suffix end
  end
  return out
end

do
  local probe = labels_in("read H: and the L: rows, the BO row, the STK list and the SDC column")
  local joined = table.concat(probe, ",")
  check("the label extractor recognises every retired shape", #probe == 5
    and joined:find("H:", 1, true) and joined:find("L:", 1, true) and joined:find("BO", 1, true)
    and joined:find("STK", 1, true) and joined:find("SDC", 1, true), joined)
end

local function dangling_in(entries)
  local out = {}
  for _, entry in ipairs(entries) do
    for _, label in ipairs(labels_in(entry.text)) do
      if not emitted_blob:find(label, 1, true) then
        out[#out + 1] = label .. " (" .. entry.where .. ")"
      end
    end
  end
  return out
end

local canary = dangling_in({ { where = "canary", text = "read the ZZQ: row" } })
check("the dangling-label scan still produces a finding when one is planted",
  #canary == 1 and canary[1]:find("ZZQ:", 1, true) ~= nil, table.concat(canary, " | "))

local dangling = dangling_in(described)
check("no model-facing text points at a label the mod never emits", #dangling == 0,
  table.concat(dangling, " | "))

local RETIRED = { "H:", "J:", "C:", "I:", "L:", "STK", "BO row", "SDC row", "k column" }
for _, label in ipairs(RETIRED) do
  local hits = {}
  for _, def in ipairs(Actions.get_static_actions()) do
    if type(def.description) == "string" and def.description:find(label, 1, true) then
      hits[#hits + 1] = tostring(def.name)
    end
  end
  check("no action description mentions the retired label '" .. label .. "'", #hits == 0,
    table.concat(hits, ","))
end

local SECTIONS = { "Your hand:", "Your jokers (", "Consumables (", "Shop items:", "Hand levels",
  "Stakes (", "Decks you can select (", "Skip tag " }
for _, section in ipairs(SECTIONS) do
  check("the mod emits the section '" .. section .. "' a description now names",
    emitted_blob:find(section, 1, true) ~= nil, section)
end

done()
