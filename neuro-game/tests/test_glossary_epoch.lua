_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 100 } }

local check, done = require("tests.helpers").harness("glossary-epoch")

local Orchestrator = require("core.orchestrator")
local TokenLegends = require("facts.token_legends")
local ContextCompact = require("context.context_compact")
local ContextDelivery = require("core.context_delivery")

local function make_joker(key, name)
  return {
    cost = 4, sell_cost = 2, debuff = false,
    ability = { set = "Joker", name = name, mult = 4 },
    config = { center = { key = key, name = name, set = "Joker",
      loc_txt = { name = name, description = "+4 Mult" } } },
  }
end

local function bridge(over)
  ContextDelivery.reset_transport()
  local N = { enabled = true, persona = "neuro", emitted = {}, llm_paused = false, session_once_serials = {}, once_serials = {} }
  function N:send_context(msg, _silent, receipt)
    if self.llm_paused then if receipt then receipt.status = "rejected" end return false end
    self.emitted[#self.emitted + 1] = tostring(msg)
    if receipt then receipt.status = "written" end
    return true
  end
  function N:register_actions() end
  function N:unregister_actions() end
  function N:force_actions() end
  function N:send_action_result() end
  if over then for k, v in pairs(over) do N[k] = v end end
  return N
end

local function world(ante, jokers)
  G.STATES = { SELECTING_HAND = 4 }
  G.STATE = 4
  G.STATE_COMPLETE = true
  G.OVERLAY_MENU = nil
  G.GAME = {
    dollars = 10, chips = 0, used_vouchers = {},
    current_round = { hands_left = 3, discards_left = 2 },
    round_resets = { ante = ante },
    hands = { Pair = { level = 1, chips = 20, mult = 2, visible = true } },
    modifiers = {},
  }
  G.hand = { cards = {}, highlighted = {}, config = { card_limit = 5, highlighted_limit = 5 } }
  G.jokers = { cards = jokers or {}, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.playbook_extra = nil
  G.deck = { cards = {} }
  ContextCompact.invalidate_cache()
end

local function emit()
  local before = #G.NEURO.emitted
  Orchestrator._emit_state_glossary("SELECTING_HAND")
  local out = {}
  for i = before + 1, #G.NEURO.emitted do out[#out + 1] = G.NEURO.emitted[i] end
  return out
end

local function has(batch, text)
  for _, m in ipairs(batch) do if m == text then return true end end
  return false
end

do
  world(1, { make_joker("j_joker", "Joker") })
  G.NEURO = bridge()

  local first = emit()
  check("the first pass of a session delivers the common legend",
    has(first, TokenLegends.READABLE_COMMON), table.concat(first, " || "))
  check("the first pass of a session delivers the state legend",
    has(first, TokenLegends.READABLE_STATE.SELECTING_HAND), table.concat(first, " || "))
  check("the first pass of a session delivers the joker legend",
    has(first, TokenLegends.READABLE_JOKER_TAGS), table.concat(first, " || "))

  local again = emit()
  check("a second pass inside the same session stays silent", #again == 0, table.concat(again, " || "))

  G.GAME.round_resets.ante = 2
  local next_ante = emit()
  check("a new ante does NOT re-deliver legends (session epoch)", #next_ante == 0, table.concat(next_ante, " || "))
end

do
  world(3, { make_joker("j_joker", "Joker") })
  G.NEURO = bridge({ llm_paused = true })
  check("a paused bridge emits no glossary", #emit() == 0)
  G.NEURO.llm_paused = false
  local after = emit()
  check("the session gate is not consumed while paused",
    has(after, TokenLegends.READABLE_COMMON), table.concat(after, " || "))
end

do
  world(4, {})
  G.NEURO = bridge()
  local no_jokers = emit()
  check("with no jokers the joker legend is withheld",
    not has(no_jokers, TokenLegends.READABLE_JOKER_TAGS), table.concat(no_jokers, " || "))
  G.jokers.cards = { make_joker("j_bull", "Bull") }
  local with_joker = emit()
  check("the joker legend lands on the first pass that has jokers",
    has(with_joker, TokenLegends.READABLE_JOKER_TAGS), table.concat(with_joker, " || "))
  check("the legends already booked this session do not repeat with it",
    not has(with_joker, TokenLegends.READABLE_COMMON), table.concat(with_joker, " || "))
end

do
  world(5, { make_joker("j_joker", "Joker") })
  G.NEURO = bridge()
  emit()
  G.GAME.round_resets.ante = 1
  local back = emit()
  check("changing ante stays silent under session epoch",
    #back == 0, table.concat(back, " || "))
end

do
  local MARK = "Card rank chips"
  local STATES = { BLIND_SELECT = 1, SHOP = 2, SELECTING_HAND = 3, HAND_PLAYED = 5,
    GAME_OVER = 4, MENU = 11 }
  local wire, forces = {}, 0

  local function play_card(sort_id)
    return { sort_id = sort_id, cost = 0, sell_cost = 0,
      ability = { set = "Default", name = "Mock" }, config = { center = {} },
      base = { value = tostring((sort_id % 9) + 2), suit = "Hearts" },
      juice_up = function() end, highlight = function() end }
  end

  local N = { enabled = true, persona = "neuro", llm_paused = false, reserved_dollars = 0,
    once_serials = {}, session_once_serials = {}, run_generation = 1 }
  function N:send_context(msg, _, receipt)
    wire[#wire + 1] = tostring(msg)
    if receipt then receipt.status = "written" end
    return true
  end
  function N:register_actions() end
  function N:unregister_actions() end
  function N:force_actions(ctx, query)
    forces = forces + 1
    wire[#wire + 1] = tostring(ctx or "") .. " " .. tostring(query or "")
  end
  function N:send_action_result() end
  function N:update() end
  function N:is_transport_saturated() return false end
  ContextDelivery.reset_transport()

  _G.G = {
    STATE = STATES.SELECTING_HAND, STATES = STATES, STATE_COMPLETE = true,
    TIMERS = { REAL = 1000 }, SETTINGS = { GAMESPEED = 1 }, CONTROLLER = { locks = {} },
    GAME = {
      dollars = 20, blind_on_deck = "Small", round = 1, chips = 0, STOP_USE = 0,
      current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
      round_resets = { ante = 1, blind_on_deck = "Small",
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" },
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" } },
      blind = { name = "Small Blind", chips = 300 }, used_vouchers = {}, modifiers = {},
      hands = { Pair = { visible = true, level = 1, chips = 10, mult = 2, played = 0 } },
      consumeable_usage_total = { tarot = 0 }, probabilities = { normal = 1 },
    },
    P_BLINDS = { bl_small = { key = "bl_small", name = "Small Blind" },
      bl_big = { key = "bl_big", name = "Big Blind" },
      bl_hook = { key = "bl_hook", name = "The Hook" } },
    hand = { cards = { play_card(1), play_card(2), play_card(3), play_card(4), play_card(5) },
      highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    jokers = { cards = { make_joker("j_joker", "Joker") }, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    deck = { cards = {} },
    FUNCS = { get_poker_hand_info = function(c) return "Pair", {}, { Pair = { c } }, c end,
      select_blind = function() end },
    blind_select = {}, NEURO = N,
  }
  ContextCompact.invalidate_cache()

  local function tick(seconds)
    for _ = 1, math.floor(seconds / 0.1) do
      G.TIMERS.REAL = G.TIMERS.REAL + 0.1
      pcall(Orchestrator.update, 0.1)
    end
  end

  for ante = 1, 8 do
    G.GAME.round_resets.ante = ante
    for _ = 1, 5 do
      G.STATE = STATES.SELECTING_HAND
      tick(2.0)
      G.STATE = STATES.HAND_PLAYED
      tick(0.3)
      G.GAME.round = G.GAME.round + 1
    end
  end

  local hits = 0
  for _, m in ipairs(wire) do
    local pos = 1
    while true do
      local a = m:find(MARK, pos, true)
      if not a then break end
      hits = hits + 1
      pos = a + #MARK
    end
  end

  check("the session really produced decisions (the count below is not vacuous)",
    forces >= 38, "forces=" .. forces .. " frames=" .. #wire)
  check("the rank-chip sentence reaches the model exactly ONCE in a whole session",
    hits == 1, "occurrences=" .. hits .. " across " .. #wire .. " frames, " .. forces .. " forces")
end

done()
