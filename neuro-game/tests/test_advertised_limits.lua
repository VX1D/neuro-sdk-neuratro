require("tests.stubs").setup({ love = "timers" })

local Helpers = require("tests.helpers")
local check, done = Helpers.harness("advertised-limits")

local Limits = require("core.plan_limits")
local Actions = require("core.actions")
local Registry = require("core.action_registry")
local Legality = require("facts.boss.legality")
local ForceSelectingHand = require("force.force_selecting_hand")
local HandHandlers = require("handlers.hand_handlers")
local ActionResult = require("core.action_result")
local Bridge = require("core.bridge")
local Orchestrator = require("core.orchestrator")

check("the load-time snapshot is the vanilla cap, so a run that differs is what these tests must drive",
  Limits.hand_select_max() == 5, tostring(Limits.hand_select_max()))

local function run_state(opts)
  local cards = {}
  for i = 1, (opts.hand or 8) do
    cards[i] = { base = { value = 10, suit = "Spades" }, sort_id = i,
      config = { center = { key = "c_base", set = "Default" } } }
  end
  _G.G = {
    P_CENTERS = require("tests.engine_centers").centers(),
    hand = { cards = cards, config = { highlighted_limit = opts.highlighted_limit or 5 }, highlighted = {} },
    GAME = {
      blind = { debuff = {}, hands = {} }, round = 1, hands = {}, probabilities = { normal = 1 },
      starting_params = opts.starting_params or {},
      current_round = { hands_left = opts.hands_left or 3, discards_left = opts.discards_left or 2 },
    },
    FUNCS = { get_poker_hand_info = require("tests.engine_hand_info").stub("High Card", function(cs) return { cs[1] } end, {}) },
    NEURO = {}, jokers = { cards = {} }, consumeables = { cards = {} },
    playing_cards = cards, deck = { cards = {} }, TIMERS = { REAL = 100 },
  }
end

local function advertised(state_name)
  Actions.get_valid_actions_for_state(state_name)
  local out = {}
  for _, def in ipairs(Registry.definitions()) do out[def.name] = def end
  return out
end

local function live_schema(def, key)
  return def and def.schema and def.schema.properties and def.schema.properties[key]
end

local function schema_detail(spec)
  if not spec then return "missing" end
  return tostring(spec.minItems) .. "/" .. tostring(spec.maxItems)
end

local function handler_accepts(fn, n)
  local indices = {}
  for i = 1, n do indices[i] = i end
  G.NEURO = {}
  local res, err = fn({ indices = indices })
  if res ~= nil then return true end
  return ActionResult.normalize(err).reason_code ~= "INVALID_SELECTION"
end

local function accepted_sizes(fn, upto)
  local out = {}
  for n = 1, upto do
    if handler_accepts(fn, n) then out[#out + 1] = tostring(n) end
  end
  return table.concat(out, ",")
end

local function schema_sizes(def, key)
  local spec = live_schema(def, key)
  if not spec then return "" end
  local out = {}
  for n = spec.minItems or 1, spec.maxItems or 0 do out[#out + 1] = tostring(n) end
  return table.concat(out, ",")
end

local function scenario(label, opts, play_max, discard_max)
  run_state(opts)
  check(label .. ": play_select_max reads the live play limit",
    Limits.play_select_max() == play_max, Limits.play_select_max())
  check(label .. ": discard_select_max reads the live discard limit, not the play limit",
    Limits.discard_select_max() == discard_max, Limits.discard_select_max())

  local defs = advertised("SELECTING_HAND")
  local play_base = live_schema(defs.play_hand, "indices")
  local discard_base = live_schema(defs.discard_hand, "indices")
  local play_live = Registry.display("play_hand")
  local discard_live = Registry.get("discard_hand")
  local play_wanted = accepted_sizes(HandHandlers.handle_play_hand, opts.hand)
  local discard_wanted = accepted_sizes(HandHandlers.handle_discard_hand, opts.hand)
  check(label .. ": the registered play catalogue advertises the run's cap",
    play_base and play_base.minItems == 1 and play_base.maxItems == play_max,
    schema_detail(play_base))
  check(label .. ": the registered discard catalogue advertises the run's cap",
    discard_base and discard_base.minItems == 1 and discard_base.maxItems == math.max(1, discard_max),
    schema_detail(discard_base))
  check(label .. ": the live play range is exactly the sizes the handler accepts",
    schema_sizes(play_live, "indices") == play_wanted,
    schema_sizes(play_live, "indices") .. " vs handler " .. play_wanted)
  check(label .. ": the live discard range is exactly the sizes the handler accepts",
    schema_sizes(discard_live, "indices") == discard_wanted,
    schema_sizes(discard_live, "indices") .. " vs handler " .. discard_wanted)

  local base_hi = live_schema(defs.use_consumable, "hand_indices")
  local live_hi = live_schema(Registry.get("use_consumable"), "hand_indices")
  check(label .. ": the registered consumable catalogue advertises the hand target bound",
    base_hi and base_hi.minItems == 1 and base_hi.maxItems == Limits.hand_select_max(),
    schema_detail(base_hi))
  check(label .. ": live consumable targeting reaches the hand selection cap",
    live_hi and live_hi.maxItems == Limits.hand_select_max(), live_hi and tostring(live_hi.maxItems))

  local lo, up = Legality.play_size_bounds()
  check(label .. ": the boss legality bounds run off the play accessor",
    lo == 1 and up == math.min(play_max, opts.hand), lo .. "-" .. up)
end


scenario("play raised past vanilla", { hand = 8, highlighted_limit = 8,
  starting_params = { play_limit = 8, discard_limit = 3 } }, 8, 3)
scenario("discard raised past vanilla", { hand = 8, highlighted_limit = 8,
  starting_params = { play_limit = 3, discard_limit = 8 } }, 3, 8)

do
  run_state({ hand = 8, highlighted_limit = 8, starting_params = { play_limit = 8, discard_limit = 3 } })
  local wire = Bridge:new({ game = "Balatro", enabled = true })
  wire.sent = {}
  wire.send = function(self, message) self.sent[#self.sent + 1] = message return true end
  G.NEURO = wire
  require("core.window").register_catalogue()

  G.GAME.starting_params.play_limit = 2
  G.hand.config.highlighted_limit = 5
  wire.sent = {}
  G.NEURO = wire
  require("core.window").register_catalogue()

  local withdrawn, registrations = {}, 0
  for _, m in ipairs(wire.sent) do
    if m.command == "actions/unregister" then
      for _, n in ipairs((m.data or {}).action_names or {}) do withdrawn[n] = true end
    elseif m.command == "actions/register" then
      registrations = registrations + 1
    end
  end
  local tightened = Registry.display("play_hand")
  local tightened_indices = live_schema(tightened, "indices")
  local tightened_wanted = accepted_sizes(HandHandlers.handle_play_hand, 8)
  check("a mid-round cap change re-registers in place, with no withdrawal gap",
    withdrawn["play_hand"] ~= true and registrations >= 1,
    tostring(registrations) .. "/" .. tostring(withdrawn["play_hand"]))
  check("a mid-round cap change narrows the live Registry definition",
    tightened_indices and tightened_indices.minItems == 1 and tightened_indices.maxItems == 2,
    schema_detail(tightened_indices))
  local sent_cap
  for _, m in ipairs(wire.sent) do
    for _, def in ipairs(m.command == "actions/register" and (m.data or {}).actions or {}) do
      if def.name == "play_hand" then sent_cap = live_schema(def, "indices") end
    end
  end
  check("and the tightened cap reaches her in the re-registered schema, so the prompt need not restate it",
    sent_cap and sent_cap.maxItems == 2,
    schema_detail(sent_cap))
  check("the tightened live schema still matches handler acceptance bounds",
    schema_sizes(tightened, "indices") == tightened_wanted and tightened_wanted == "1,2",
    schema_sizes(tightened, "indices") .. " vs handler " .. tightened_wanted)
end

local P_BLINDS = {
  bl_small = { name = "Small Blind", debuff = {} },
  bl_psychic = { name = "The Psychic", boss = { min = 1, max = 10 }, debuff = { h_size_ge = 5 } },
  bl_goad = { name = "The Goad", boss = { min = 1, max = 10 }, debuff = { suit = "Spades" } },
  bl_plant = { name = "The Plant", boss = { min = 4, max = 10 }, debuff = { is_face = "face" } },
  bl_club = { name = "The Club", boss = { min = 1, max = 10 }, debuff = { suit = "Clubs" } },
  bl_eye = { name = "The Eye", boss = { min = 3, max = 10 }, debuff = {} },
  bl_modded_le = { name = "The Vise", boss = { min = 1, max = 10 }, debuff = { h_size_le = 2 } },
  bl_modded_band = { name = "The Clamp", boss = { min = 1, max = 10 }, debuff = { h_size_ge = 3, h_size_le = 4 } },
  bl_modded_exact = { name = "The Pin", boss = { min = 1, max = 10 }, debuff = { h_size_ge = 4, h_size_le = 4 } },
}


for _, key in ipairs({ "bl_psychic", "bl_modded_le", "bl_modded_band", "bl_modded_exact",
                       "bl_goad", "bl_plant", "bl_club", "bl_eye", "bl_small" }) do
  local blind_def = P_BLINDS[key]
  run_state({ hand = 8, highlighted_limit = 8, starting_params = { play_limit = 5, discard_limit = 3 } })
  _G.G.P_BLINDS = P_BLINDS
  _G.G.GAME.blind = { key = key, name = blind_def.name, debuff = blind_def.debuff, hands = {} }

  local defs = advertised("SELECTING_HAND")
  local base_spec = live_schema(defs.play_hand, "indices")
  local live_spec = live_schema(Registry.display("play_hand"), "indices")
  local label = blind_def.name

  if base_spec and live_spec then
    local lo, hi = live_spec.minItems, live_spec.maxItems
    check(label .. ": the stable play catalogue advertises its bounds",
      base_spec.minItems == 1 and base_spec.maxItems ~= nil, schema_detail(base_spec))

    check(label .. ": the boss floor reaches the described schema",
      lo == math.max(1, tonumber(blind_def.debuff.h_size_ge) or 1), tostring(lo))
    check(label .. ": the described schema retains a finite current cap",
      type(hi) == "number" and hi >= lo, schema_detail(live_spec))

    local floor = math.max(1, tonumber(blind_def.debuff.h_size_ge) or 1)
    local ceiling = math.min(tonumber(blind_def.debuff.h_size_le) or 8, Limits.play_select_max())
    local accepted = accepted_sizes(HandHandlers.handle_play_hand, 8)
    local wanted = {}
    for n = floor, ceiling do wanted[#wanted + 1] = tostring(n) end
    check(label .. ": the handler accepts exactly the sizes the boss rule permits",
      accepted == table.concat(wanted, ","),
      "handler " .. accepted .. " vs rule " .. table.concat(wanted, ","))
  end
end

do
  run_state({ hand = 8, starting_params = { play_limit = 5, discard_limit = 0 }, discards_left = 0 })
  local defs = advertised("SELECTING_HAND")
  local force = ForceSelectingHand.build()
  local offered_discard = false
  for _, name in ipairs((force or {}).actions or {}) do
    if name == "discard_hand" then offered_discard = true end
  end
  check("a zero discard limit keeps the canonical discard contract but withdraws the move",
    defs.discard_hand ~= nil and not offered_discard,
    defs.discard_hand and schema_sizes(defs.discard_hand, "indices"))
  check("a zero discard limit is what the action validator enforces",
    Actions.is_action_valid("discard_hand") == false,
    tostring(Actions.is_action_valid("discard_hand")))
  local spec = live_schema(defs.discard_hand, "indices")
  check("the stable discard catalogue keeps a non-empty base range",
    spec and spec.minItems == 1 and (spec.maxItems == nil or spec.maxItems >= spec.minItems),
    schema_detail(spec))
end

done()
