_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 100 end } }
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("schema-prompt")
local SchemaValidate = require("util.schema_validate")
local ActionSchema = require("core.action_schema")

check("empty enum is rejected at schema admission", not ActionSchema.valid_schema({
  type = "object", properties = { choice = { type = "string", enum = {} } }
}, true))
local SEED = { type = "string", pattern = "^[A-Za-z0-9]*$", maxLength = 8 }
check("class pattern accepts its characters and the empty string",
  SchemaValidate.validate_value(SEED, "Ab12xyZ9", "seed") == true
    and SchemaValidate.validate_value(SEED, "", "seed") == true)
for _, bad in ipairs({ "abc!", "a b", "x-y", "\195\169", "ab\n" }) do
  local ok, err = SchemaValidate.validate_value(SEED, bad, "seed")
  check("class pattern refuses " .. ("%q"):format(bad) .. " listing the characters",
    ok == false and err == "seed may contain only the characters A-Z, a-z, 0-9.", tostring(err))
end
check("'+' class pattern refuses the empty string",
  not SchemaValidate.validate_value({ type = "string", pattern = "^[a-z_-]+$" }, "", "choice")
    and SchemaValidate.validate_value({ type = "string", pattern = "^[a-z_-]+$" }, "a_b-c", "choice"))
check("class pattern is admitted at registration", ActionSchema.valid_schema({
  type = "object", properties = { seed = SEED }
}, true))
for _, pattern in ipairs({ "^(foo|bar)$", "^foo\\.bar$", "foo(?=bar)", "^[\\A]$", "^[^a]*$",
    "^[a-z]?$", "[a-z]*", "^[a.z]*$", "^\\d+$" }) do
  check("pattern outside the class shape is rejected at registration: " .. pattern,
    not ActionSchema.valid_schema({
      type = "object", properties = { choice = { type = "string", pattern = pattern } }
    }, true))
end

G = {
  NEURO = { enabled = true, persona = "neuro", decision_serial = 1, run_generation = 1,
    once_serials = {}, session_once_serials = {}, state_enter_serial = 1, reserved_dollars = 0 },
  GAME = { hands = {
    Visible = { visible = true }, Implicit = {}, Hidden = { visible = false }
  }, current_round = {}, round_resets = {} },
  hand = { cards = {} }, jokers = { cards = {} }, consumeables = { cards = {} },
  deck = { cards = {} }, FUNCS = {}, TIMERS = { REAL = 100 }
}
local Actions = require("core.actions")
local Registry = require("core.action_registry")
local focus_schema = Registry.get("record_plan").schema.properties.hand_focus
check("hand-focus is an enum of exactly the visible hands",
  table.concat(focus_schema.properties.primary.enum or {}, ",") == "Visible"
    and table.concat(focus_schema.properties.fallback.enum or {}, ",") == "Visible"
    and focus_schema.properties.primary.type == "string")
local PlanHandlers = require("handlers.plan_handlers")
check("hand-focus accepts a strictly visible hand",
  PlanHandlers.prepare_plan({ hand_focus = { primary = "Visible" } }) ~= nil)
for _, hidden in ipairs({ "Implicit", "Hidden" }) do
  local ok, err = PlanHandlers.prepare_plan({ hand_focus = { primary = hidden } })
  check("hand-focus refuses '" .. hidden .. "' with the same visibility predicate",
    ok == nil and type(err) == "string", tostring(err))
  check("and the refusal lists what is visible, so one retry can succeed",
    type(err) == "string" and err:find("Send one of: Visible.", 1, true) ~= nil, tostring(err))
end
check("hand-focus applies the predicate to fallback too",
  PlanHandlers.prepare_plan({ hand_focus = { primary = "Visible", fallback = "Hidden" } }) == nil)

local descriptions_plain = true
for _, definition in ipairs(Registry.definitions()) do
  if definition.description:find("{count:", 1, true) then descriptions_plain = false end
end
check("registered action descriptions contain no internal count templates", descriptions_plain)

local EngineCards = require("tests.engine_cards")
G.STATES = EngineCards.states()
G.STATE, G.STATE_COMPLETE = G.STATES.SMODS_BOOSTER_OPENED, true
G.GAME.dollars = 9
G.pack_cards = { cards = { EngineCards.consumable("c_death", { sell_cost = 1, cost = 3,
  center = { loc_txt = { name = "Death" } } }) } }
G.consumeables.config = { card_limit = 2 }
G.jokers.config = { card_limit = 5 }
G.hand.cards = {
  { base = { value = "2", suit = "Hearts" } },
  { base = { value = "3", suit = "Hearts" } }
}
local query = require("force.force_pack").build().query
check("directional pack guidance does not name ordinary pack action",
  query:find("Use the choose_pack_card action", 1, true) == nil)


done()
