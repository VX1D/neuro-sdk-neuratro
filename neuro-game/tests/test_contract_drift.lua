require("tests.stubs").setup({ love = "lazy" })

local check, done = require("tests.helpers").harness("contract-drift")

local Limits = require("core.plan_limits")
local Registry = require("core.action_registry")

_G.G = { GAME = { starting_params = { play_limit = 2, discard_limit = 4 } } }
require("core.actions")
local PlanHandler = require("handlers.plan_handlers").handle_record_plan
local CardUtil = require("facts.card_util")

local record_plan = Registry.get("record_plan")
local props = (record_plan and record_plan.schema and record_plan.schema.properties) or {}
for _, f in ipairs({ "hand_plan", "build_plan", "money_plan" }) do
  check("record_plan." .. f .. " advertises the shared plan text cap",
    props[f] and props[f].type == "string" and props[f].maxLength == Limits.PLAN_TEXT_MAX,
    props[f] and props[f].maxLength)
end
check("record_plan schema does not advertise boss_plan", props.boss_plan == nil)

for _, action_name in ipairs({ "buy_from_shop", "sell_card", "use_consumable", "reroll_shop", "leave_shop", "select_blind" }) do
  local action = Registry.get(action_name)
  local embedded = action and action.schema and action.schema.properties and action.schema.properties.plan
  for _, field in ipairs({ "hand_plan", "build_plan", "money_plan" }) do
    check(action_name .. ".plan." .. field .. " shares the standalone text cap",
      embedded and embedded.properties and embedded.properties[field]
        and embedded.properties[field].maxLength == props[field].maxLength
        and props[field].maxLength == Limits.PLAN_TEXT_MAX)
  end
end

for _, action_name in ipairs({ "play_hand", "discard_hand" }) do
  local embedded = Registry.get(action_name).schema.properties.plan
  for _, field in ipairs({ "hand_plan", "build_plan", "money_plan" }) do
    check(action_name .. ".plan does not advertise transient overwrite field " .. field,
      embedded and embedded.properties and embedded.properties[field] == nil)
  end
  check(action_name .. ".plan.boss_plan shares the plan text cap",
    embedded and embedded.properties and embedded.properties.boss_plan
      and embedded.properties.boss_plan.type == "string"
      and embedded.properties.boss_plan.maxLength == Limits.PLAN_TEXT_MAX,
    embedded and embedded.properties and embedded.properties.boss_plan
      and embedded.properties.boss_plan.maxLength)
end

local standalone_intents = Registry.get("record_joker_roles").schema.properties.intents
check("record_joker_roles tag enum is CORE/SCALING/HOLD/CHANGE",
  table.concat(standalone_intents.items.properties.tag.enum, ",") == "CORE,SCALING,HOLD,CHANGE")
local note_schema = standalone_intents.items.properties.note
check("record_joker_roles note schema advertises the shared note cap",
  note_schema and note_schema.type == "string"
    and note_schema.maxLength == Limits.JOKER_NOTE_MAX,
  note_schema and note_schema.maxLength)
do
  local Validate = require("util.schema_validate")
  check("the note schema accepts its exact maximum",
    Validate.validate_value(note_schema, string.rep("x", Limits.JOKER_NOTE_MAX), "note") == true)
  check("the note schema rejects one character over its maximum",
    Validate.validate_value(note_schema, string.rep("x", Limits.JOKER_NOTE_MAX + 1), "note") == false)

  local saved_G = _G.G
  _G.G = { NEURO = {}, jokers = { cards = { { config = { center = { key = "j_a" } },
    ability = { set = "Joker", name = "A" }, sort_id = 7 } } } }
  local long_note = string.rep("x", Limits.JOKER_NOTE_MAX + 1)
  local exec, err = require("handlers.plan_handlers").handle_record_joker_roles({
    intents = { { index = 1, tag = "CORE", note = long_note } } })
  check("the handler rejects an over-limit note", exec == nil and type(err) == "string", tostring(err))
  check("the rejected note does not mutate joker intents", G.NEURO.joker_intents == nil, G.NEURO.joker_intents)
  _G.G = saved_G
end
check("record_joker_roles description states the note character limit",
  Registry.get("record_joker_roles").description:find(tostring(Limits.JOKER_NOTE_MAX), 1, true) ~= nil,
  Registry.get("record_joker_roles").description)
check("leave_shop no longer embeds joker_intents (it's a standalone action)",
  Registry.get("leave_shop").schema.properties.joker_intents == nil)
for _, action_name in ipairs({ "reroll_shop", "leave_shop" }) do
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
  check("play_hand runtime schema maxItems == Limits.play_select_max()",
    play_items and play_items.maxItems == Limits.play_select_max(), play_items and play_items.maxItems)
end

do
  local discard_sc = Registry.get("discard_hand")
  local discard_items = discard_sc and discard_sc.schema and discard_sc.schema.properties and discard_sc.schema.properties.indices
  check("discard_hand runtime schema maxItems == Limits.discard_select_max()",
    discard_items and discard_items.maxItems == Limits.discard_select_max(), discard_items and discard_items.maxItems)
end


local over = string.rep("x", Limits.PLAN_TEXT_MAX + 1)
local exec_over, over_err = PlanHandler({ hand_plan = over })
check("handler rejects a plan over the shared text cap",
  exec_over == nil and type(over_err) == "table" and over_err.reason_code == "SCHEMA_INVALID",
  over_err)
do
  local saved_G = _G.G
  _G.G = { NEURO = {}, GAME = _G.G and _G.G.GAME }
  check("an over-limit plan does not mutate plan state", G.NEURO.plan == nil, G.NEURO.plan)
  _G.G = saved_G
end
do
  local validate_value = require("util.schema_validate").validate_value
  local seed_schema = Registry.get("paste_seed").schema.properties.seed
  check("paste_seed advertises the 8-character bound and accepts an empty seed",
    seed_schema.minLength == nil and seed_schema.maxLength == 8
      and validate_value(seed_schema, "", "seed") == true,
    tostring(seed_schema.minLength) .. ".." .. tostring(seed_schema.maxLength))
  check("an 8-character ASCII seed passes the lexical schema",
    validate_value(seed_schema, "ABC123XY", "seed") == true)
  local unicode_schema = { type = "string", minLength = 1, maxLength = 8 }
  check("an 8-code-point non-ASCII value passes maxLength (characters, not bytes)",
    validate_value(unicode_schema, "♠♥♦♣♠♥♦♣", "unicode") == true)
  check("a 9-code-point non-ASCII value exceeds maxLength",
    validate_value(unicode_schema, "♠♥♦♣♠♥♦♣♠", "unicode") == false)
  check("a hyphenated seed is refused before the handler",
    validate_value(seed_schema, "AB-123", "seed") == false)
  check("a 9-character ASCII seed is still refused",
    validate_value(seed_schema, "ABC123XYZ", "seed") == false)
end

local function set_jokers(list) _G.G = { jokers = { cards = list } } end
local function card(key, edition) return { config = { center = { key = key } }, edition = edition } end

set_jokers({ card("j_a"), card("j_b") })
local base = CardUtil.joker_build_signature()
set_jokers({ card("j_b"), card("j_a") })
check("build_signature changes on reorder", CardUtil.joker_build_signature() ~= base)
set_jokers({ card("j_a"), card("j_b") })
check("build_signature stable when roster unchanged", CardUtil.joker_build_signature() == base)
set_jokers({ card("j_a", { polychrome = true, type = "polychrome", key = "e_polychrome", x_mult = 1.5 }), card("j_b") })
check("build_signature changes when an edition appears", CardUtil.joker_build_signature() ~= base)
local function back(key, edition) local c = card(key, edition); c.facing = "back"; return c end
set_jokers({ back("j_a"), card("j_b") })
local hidden = CardUtil.joker_build_signature()
set_jokers({ back("j_c", { polychrome = true, type = "polychrome", key = "e_polychrome", x_mult = 1.5 }), card("j_b") })
check("build_signature does not change when a face-down joker's identity or edition does",
  CardUtil.joker_build_signature() == hidden, CardUtil.joker_build_signature())
check("build_signature carries no face-down joker's key", not hidden:find("j_a", 1, true), hidden)

set_jokers({ card("j_a"), card("j_b") })
local comp = CardUtil.joker_composition_signature()
set_jokers({ card("j_b"), card("j_a") })
check("composition_signature stays order-insensitive (order_think safe)",
  CardUtil.joker_composition_signature() == comp)

done()
