_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }

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
    hand = { cards = cards, config = { highlighted_limit = opts.highlighted_limit or 5 }, highlighted = {} },
    GAME = {
      blind = { debuff = {}, hands = {} }, round = 1, hands = {}, probabilities = { normal = 1 },
      starting_params = opts.starting_params or {},
      current_round = { hands_left = opts.hands_left or 3, discards_left = opts.discards_left or 2 },
    },
    FUNCS = { get_poker_hand_info = function(cs) return "High Card", {}, {}, { cs[1] } end },
    NEURO = {}, jokers = { cards = {} }, consumeables = { cards = {} },
    playing_cards = cards, deck = { cards = {} }, TIMERS = { REAL = 100 },
  }
end

-- The path the orchestrator takes before every force goes out (core/orchestrator.lua:215-222).
local function advertised(state_name)
  Actions.get_valid_actions_for_state(state_name)
  local out = {}
  for _, def in ipairs(Orchestrator.build_valid_action_definitions(state_name)) do out[def.name] = def end
  return out
end

local function prose_max(def, verb)
  return def and def.description and def.description:match(verb .. " 1%-(%d+) hand cards")
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
  local spec = def and def.schema and def.schema.properties and def.schema.properties[key]
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
  local play_wanted = accepted_sizes(HandHandlers.handle_play_hand, opts.hand)
  local discard_wanted = accepted_sizes(HandHandlers.handle_discard_hand, opts.hand)
  check(label .. ": the advertised play range is exactly the sizes the handler accepts",
    schema_sizes(defs.play_hand, "indices") == play_wanted,
    schema_sizes(defs.play_hand, "indices") .. " vs handler " .. play_wanted)
  check(label .. ": the advertised discard range is exactly the sizes the handler accepts",
    schema_sizes(defs.discard_hand, "indices") == discard_wanted,
    schema_sizes(defs.discard_hand, "indices") .. " vs handler " .. discard_wanted)
  check(label .. ": the play prose quotes the same maximum as the play schema",
    prose_max(defs.play_hand, "Play") == tostring(play_max), tostring(prose_max(defs.play_hand, "Play")))
  check(label .. ": the discard prose quotes the discard maximum, not the play maximum",
    prose_max(defs.discard_hand, "Discard") == tostring(discard_max),
    tostring(prose_max(defs.discard_hand, "Discard")))

  local registry = {}
  for _, def in ipairs(Registry.definitions()) do registry[def.name] = def end
  local hi = registry.use_consumable and registry.use_consumable.schema.properties.hand_indices
  check(label .. ": use_consumable targets as many hand cards as the run lets the player select",
    hi and hi.maxItems == Limits.hand_select_max(), hi and tostring(hi.maxItems))

  local lo, up = Legality.play_size_bounds()
  check(label .. ": the boss legality bounds run off the play accessor",
    lo == 1 and up == math.min(play_max, opts.hand), lo .. "-" .. up)

  local query = ForceSelectingHand.build().query
  check(label .. ": the force quotes the live play range",
    query:find('play_hand|{"indices":[<pick 1 to ' .. play_max .. ' different hand positions>]', 1, true) ~= nil, query)
  check(label .. ": the force quotes the live discard range",
    query:find('discard_hand|{"indices":[<pick 1 to ' .. discard_max .. ' different hand positions>]', 1, true) ~= nil, query)
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
  Orchestrator.register_valid_actions("SELECTING_HAND")

  G.GAME.starting_params.play_limit = 2
  G.hand.config.highlighted_limit = 5
  wire.sent = {}
  G.NEURO = wire
  Orchestrator.register_valid_actions("SELECTING_HAND")

  local withdrawn, fresh = {}, nil
  for _, m in ipairs(wire.sent) do
    if m.command == "actions/unregister" then
      for _, n in ipairs(m.data.action_names or {}) do withdrawn[n] = true end
    elseif m.command == "actions/register" then
      for _, a in ipairs(m.data.actions or {}) do
        if a.name == "play_hand" then fresh = a end
      end
    end
  end
  check("a mid-round cap change withdraws the stale play_hand from the wire", withdrawn["play_hand"] == true)
  check("a mid-round cap change puts the new play_hand schema on the wire",
    fresh ~= nil and fresh.schema.properties.indices.maxItems == 2,
    fresh and tostring(fresh.schema.properties.indices.maxItems))
  check("the re-registered prose moves with the schema",
    fresh ~= nil and prose_max(fresh, "Play") == "2", fresh and tostring(prose_max(fresh, "Play")))
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

local function prompt_count(text)
  local lo, hi = text:match("pick (%d+) to (%d+) different hand positions")
  if lo then return tonumber(lo), tonumber(hi) end
  local n = text:match("pick exactly (%d+) different hand positions")
  if n then return tonumber(n), tonumber(n) end
  if text:match("pick 1 hand position") then return 1, 1 end
  return nil
end

local function description_count(text)
  local lo, hi = text:match("Play (%d+)%-(%d+) hand cards")
  if lo then return tonumber(lo), tonumber(hi) end
  local n = text:match("Play exactly (%d+) hand cards")
  if n then return tonumber(n), tonumber(n) end
  if text:match("Play 1 hand card%f[%A]") then return 1, 1 end
  return nil
end

local function pair(lo, hi)
  if lo == nil then return "unparsed" end
  return tostring(lo) .. "-" .. tostring(hi)
end

for _, key in ipairs({ "bl_psychic", "bl_modded_le", "bl_modded_band", "bl_modded_exact",
                       "bl_goad", "bl_plant", "bl_club", "bl_eye", "bl_small" }) do
  local blind_def = P_BLINDS[key]
  run_state({ hand = 8, highlighted_limit = 8, starting_params = { play_limit = 5, discard_limit = 3 } })
  _G.G.P_BLINDS = P_BLINDS
  _G.G.GAME.blind = { key = key, name = blind_def.name, debuff = blind_def.debuff, hands = {} }

  local defs = advertised("SELECTING_HAND")
  local spec = defs.play_hand and defs.play_hand.schema.properties.indices
  local label = blind_def.name

  if spec then
    local lo, hi = spec.minItems, spec.maxItems
    local p_lo, p_hi = prompt_count(Registry.prompt("play_hand"))
    check(label .. ": the play prompt quotes the wire schema's range",
      p_lo == lo and p_hi == hi, pair(p_lo, p_hi) .. " vs schema " .. pair(lo, hi))

    local d_lo, d_hi = description_count(defs.play_hand.description)
    check(label .. ": the play description quotes the wire schema's range",
      d_lo == lo and d_hi == hi, pair(d_lo, d_hi) .. " vs schema " .. pair(lo, hi))

    local query = ForceSelectingHand.build().query
    local move = query:match("(play_hand|%b{})")
    local q_lo, q_hi
    if move then q_lo, q_hi = prompt_count(move) end
    check(label .. ": the rendered move quotes the wire schema's range",
      q_lo == lo and q_hi == hi, pair(q_lo, q_hi) .. " vs schema " .. pair(lo, hi))

    check(label .. ": the boss floor reaches the wire schema at all",
      lo == math.max(1, tonumber(blind_def.debuff.h_size_ge) or 1), tostring(lo))
  end
end

do
  run_state({ hand = 8, starting_params = { play_limit = 5, discard_limit = 0 } })
  local defs = advertised("SELECTING_HAND")
  check("a zero discard limit withdraws discard_hand instead of advertising a refused range",
    defs.discard_hand == nil,
    defs.discard_hand and schema_sizes(defs.discard_hand, "indices"))
  check("a zero discard limit is what the handler enforces",
    accepted_sizes(HandHandlers.handle_discard_hand, 8) == "",
    accepted_sizes(HandHandlers.handle_discard_hand, 8))
  local spec = defs.discard_hand and defs.discard_hand.schema.properties.indices
  check("no advertised item range is ever empty",
    spec == nil or (spec.minItems <= spec.maxItems), spec and (spec.minItems .. "-" .. spec.maxItems))
  check("play_hand is untouched by a zero discard limit", defs.play_hand ~= nil)
end

done()
