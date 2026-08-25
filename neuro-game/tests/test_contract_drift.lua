_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("contract-drift")

local Limits = require("core.plan_limits")
local Registry = require("core.action_registry")

_G.G = { GAME = { starting_params = { play_limit = 2, discard_limit = 4 } } }
require("core.actions") -- populates the action registry, reading the caps set above
local PlanHandler = require("handlers.plan_handlers").handle_set_plan
local CardUtil = require("facts.card_util")

local set_plan = Registry.get("set_plan")
local props = (set_plan and set_plan.schema and set_plan.schema.properties) or {}
for _, f in ipairs({ "hand_plan", "build_plan", "money_plan" }) do
  check("set_plan." .. f .. " is an unbounded string: model-authored prose carries no length cap",
    props[f] and props[f].type == "string" and props[f].maxLength == nil, props[f] and props[f].maxLength)
end
check("set_plan schema does not advertise boss_plan", props.boss_plan == nil)

for _, action_name in ipairs({ "buy_from_shop", "sell_card", "use_card", "reroll_shop", "toggle_shop", "select_blind" }) do
  local action = Registry.get(action_name)
  local embedded = action and action.schema and action.schema.properties and action.schema.properties.plan
  for _, field in ipairs({ "hand_plan", "build_plan", "money_plan" }) do
    check(action_name .. ".plan." .. field .. " is uncapped, like the standalone field",
      embedded and embedded.properties and embedded.properties[field]
        and embedded.properties[field].maxLength == nil and props[field].maxLength == nil)
  end
end

for _, action_name in ipairs({ "play_hand", "discard_hand" }) do
  local embedded = Registry.get(action_name).schema.properties.plan
  for _, field in ipairs({ "hand_plan", "build_plan", "money_plan" }) do
    check(action_name .. ".plan does not advertise transient overwrite field " .. field,
      embedded and embedded.properties and embedded.properties[field] == nil)
  end
  check(action_name .. ".plan.boss_plan is an uncapped string",
    embedded and embedded.properties and embedded.properties.boss_plan
      and embedded.properties.boss_plan.type == "string"
      and embedded.properties.boss_plan.maxLength == nil,
    embedded and embedded.properties and embedded.properties.boss_plan
      and embedded.properties.boss_plan.maxLength)
end

local standalone_intents = Registry.get("set_joker_intents").schema.properties.intents
check("set_joker_intents tag enum is CORE/SCALING/HOLD/CHANGE",
  table.concat(standalone_intents.items.properties.tag.enum, ",") == "CORE,SCALING,HOLD,CHANGE")
local note_schema = standalone_intents.items.properties.note
check("set_joker_intents note schema advertises no maxLength",
  note_schema and note_schema.type == "string" and note_schema.maxLength == nil,
  note_schema and note_schema.maxLength)
do
  local Validate = require("util.schema_validate")
  check("the schema accepts a note of any length",
    Validate.validate_value(note_schema, string.rep("x", 5000), "note") == true)

  local saved_G = _G.G
  _G.G = { NEURO = {}, jokers = { cards = { { config = { center = { key = "j_a" } },
    ability = { set = "Joker", name = "A" }, sort_id = 7 } } } }
  local long_note = string.rep("x", 2000)
  local exec, err = require("handlers.plan_handlers").handle_set_joker_intents({
    intents = { { index = 1, tag = "CORE", note = long_note } } })
  check("the handler accepts a 2000-character note", type(exec) == "function", tostring(err))
  local receipt = type(exec) == "function" and exec() or ""
  check("the note is stored verbatim, neither shortened nor dropped",
    G.NEURO.joker_intents[7] and G.NEURO.joker_intents[7].note == long_note,
    G.NEURO.joker_intents[7] and #G.NEURO.joker_intents[7].note)
  check("the tag still lands with the full note",
    G.NEURO.joker_intents[7] and G.NEURO.joker_intents[7].tag == "CORE")
  check("the receipt reports the note without any shortening clause",
    receipt:find("shortened", 1, true) == nil and receipt:find(long_note, 1, true) ~= nil, #receipt)
  _G.G = saved_G
end
check("set_joker_intents description states no character limit",
  Registry.get("set_joker_intents").description:find("characters", 1, true) == nil,
  Registry.get("set_joker_intents").description)
check("toggle_shop no longer embeds joker_intents (it's a standalone action)",
  Registry.get("toggle_shop").schema.properties.joker_intents == nil)
for _, action_name in ipairs({ "reroll_shop", "toggle_shop" }) do
  local schema = Registry.get(action_name).schema
  check(action_name .. " advertises a parameter object", schema.type == "object"
    and type(schema.properties) == "table" and schema.properties.plan ~= nil)
end

check("fixture actually drives divergent play/discard caps (or the assertions below are vacuous)",
  Limits.play_select_max() ~= Limits.discard_select_max(),
  string.format("play=%s discard=%s", tostring(Limits.play_select_max()), tostring(Limits.discard_select_max())))

do
  local play_sc = Registry.get("play_hand")
  local play_items = play_sc and play_sc.schema and play_sc.schema.properties and play_sc.schema.properties.indices
  check("play_hand schema maxItems == Limits.play_select_max()",
    play_items and play_items.maxItems == Limits.play_select_max(), play_items and play_items.maxItems)
end

do
  local discard_sc = Registry.get("discard_hand")
  local discard_items = discard_sc and discard_sc.schema and discard_sc.schema.properties and discard_sc.schema.properties.indices
  check("discard_hand schema maxItems == Limits.discard_select_max()",
    discard_items and discard_items.maxItems == Limits.discard_select_max(), discard_items and discard_items.maxItems)
end

local over = string.rep("x", 5000)
local exec_over = PlanHandler({ hand_plan = over })
check("handler accepts a 5000-char plan field", type(exec_over) == "function")
do
  local saved_G = _G.G
  _G.G = { NEURO = {}, GAME = _G.G and _G.G.GAME }
  if type(exec_over) == "function" then exec_over() end
  check("the plan field is stored verbatim, at any length",
    G.NEURO.plan and G.NEURO.plan.hand == over, G.NEURO.plan and #tostring(G.NEURO.plan.hand))
  _G.G = saved_G
end
do
  local validate_value = require("util.schema_validate").validate_value
  local seed_schema = Registry.get("paste_seed").schema.properties.seed
  check("paste_seed still advertises the 1-8 character bound",
    seed_schema.minLength == 1 and seed_schema.maxLength == 8,
    tostring(seed_schema.minLength) .. ".." .. tostring(seed_schema.maxLength))
  check("an 8-character non-ASCII seed passes the cap (characters, not bytes)",
    validate_value(seed_schema, "♠♥♦♣♠♥♦♣", "seed") == true)
  check("a 9-character seed is still refused",
    validate_value(seed_schema, "♠♥♦♣♠♥♦♣♠", "seed") == false)
end

local function set_jokers(list) _G.G = { jokers = { cards = list } } end
local function card(key, edition) return { config = { center = { key = key } }, edition = edition } end

set_jokers({ card("j_a"), card("j_b") })
local base = CardUtil.joker_build_signature()
set_jokers({ card("j_b"), card("j_a") })
check("build_signature changes on reorder", CardUtil.joker_build_signature() ~= base)
set_jokers({ card("j_a"), card("j_b") })
check("build_signature stable when roster unchanged", CardUtil.joker_build_signature() == base)
set_jokers({ card("j_a", { polychrome = true }), card("j_b") })
check("build_signature changes when an edition appears", CardUtil.joker_build_signature() ~= base)

set_jokers({ card("j_a"), card("j_b") })
local comp = CardUtil.joker_composition_signature()
set_jokers({ card("j_b"), card("j_a") })
check("composition_signature stays order-insensitive (order_think safe)",
  CardUtil.joker_composition_signature() == comp)

done()
