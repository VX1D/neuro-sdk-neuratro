_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("action payload render")

local states = { SHOP = 1, SELECTING_HAND = 2, BLIND_SELECT = 3 }
_G.G = {
  STATE = states.SHOP, STATES = states,
  GAME = { dollars = 10, current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
    round_resets = { ante = 1, blind_states = {}, blind_choices = {} } },
  NEURO = { reserved_dollars = 0, run_generation = 1 },
  FUNCS = {},
  jokers = { cards = {}, config = { card_limit = 5 } },
  consumeables = { cards = {}, config = { card_limit = 2 } },
  shop = {}, shop_jokers = { cards = {} }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
}

require("core.dispatcher")
local Registry = require("core.action_registry")
local Json = require("util.neuro_json")
local SchemaValidate = require("util.schema_validate")

check("registry is populated (guards the sweep below from passing vacuously)",
  #Registry.names() >= 20, tostring(#Registry.names()))

local function payload_of(rendered)
  return (rendered or ""):match("^[^|]*|(.*)$")
end

local fieldless, swept = {}, 0
for _, name in ipairs(Registry.names()) do
  local contract = Registry.get(name)
  local properties = contract.schema and contract.schema.properties or {}
  if next(properties) == nil then fieldless[#fieldless + 1] = name end
  local rendered = Registry.render(name, {})
  local wire = payload_of(rendered)
  swept = swept + 1
  check(name .. ": empty payload renders as an object",
    wire == "{}", rendered)
  local ok, decoded = pcall(Json.decode, wire)
  check(name .. ": the offered payload passes the dispatcher object gate",
    ok and SchemaValidate.is_object_table(decoded), rendered)
end
check("the sweep covered every registered action", swept == #Registry.names(), tostring(swept))
check("the registry still has fieldless actions to protect", #fieldless >= 3, tostring(#fieldless))

for _, name in ipairs({ "skip_booster", "skip_blind", "reroll_boss", "toggle_shop", "cash_out" }) do
  check(name .. " is offered as " .. name .. "|{}",
    Registry.render(name, {}) == name .. "|{}", Registry.render(name, {}))
  check(name .. " renders the same with no payload argument at all",
    Registry.render(name) == name .. "|{}", tostring(Registry.render(name)))
end

check("a single-field payload is unchanged",
  Registry.render("select_blind", { blind = "boss" }) == 'select_blind|{"blind":"boss"}',
  Registry.render("select_blind", { blind = "boss" }))
check("a nested plan object is unchanged",
  Registry.render("select_blind", { plan = { hand_plan = "..." } }) == 'select_blind|{"plan":{"hand_plan":"..."}}',
  Registry.render("select_blind", { plan = { hand_plan = "..." } }))
check("a list field still renders as a list",
  Registry.render("play_hand", { indices = { 1, 2 } }) == 'play_hand|{"indices":[1,2]}',
  Registry.render("play_hand", { indices = { 1, 2 } }))

local caller_table = {}
Registry.render("skip_blind", caller_table)
check("rendering does not tag the caller's own table", getmetatable(caller_table) == nil)

check("a field outside the contract is still rejected",
  pcall(Registry.render, "skip_blind", { nonsense = 1 }) == false)

done()
