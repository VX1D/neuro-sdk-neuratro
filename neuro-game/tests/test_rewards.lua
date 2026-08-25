_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { GAME = {}, TIMERS = { REAL = 100 } }
local R = require("core.rewards")

local check, done = require("tests.helpers").harness("rewards")

local function setg(blind, ante, round, won, win_ante)
  G.GAME = { blind = blind, round_resets = { ante = ante }, round = round, won = won, win_ante = win_ante }
end

setg({ name = "Small Blind" }, 3, 7, nil)
local m = R.outcome("SELECTING_HAND", "ROUND_EVAL")
check("blind cleared reports its ante", type(m) == "string" and m:find("Small Blind", 1, true) and m:find("3", 1, true), m)

setg({ name = "The Goad", boss = true }, 6, 12, nil)
m = R.outcome("SELECTING_HAND", "ROUND_EVAL")
check("boss beaten reports beaten ante (post-increment corrected)",
  type(m) == "string" and m:find("Boss Blind", 1, true) and m:find("The Goad", 1, true) and m:find("5", 1, true) and not m:find("6", 1, true), m)

setg({ name = "The Goad", boss = true }, 9, 20, true)
m = R.outcome("SELECTING_HAND", "ROUND_EVAL")
check("won run announced (ante-8 win arrives as ante 9)",
  type(m) == "string" and m:lower():find("won the run", 1, true) and m:find("8", 1, true) and not m:lower():find("endless", 1, true), m)

setg({ name = "Cerberus", boss = true }, 7, 15, true, 6)
m = R.outcome("SELECTING_HAND", "ROUND_EVAL")
check("won run honors custom win_ante", type(m) == "string" and m:lower():find("won the run", 1, true) and m:find("6", 1, true), m)

setg({ name = "Cerberus", boss = true }, 10, 25, true)
m = R.outcome("SHOP", "ROUND_EVAL")
check("endless boss is not a fresh win",
  type(m) == "string" and m:lower():find("endless", 1, true) and m:find("9", 1, true) and not m:lower():find("won the run", 1, true), m)

setg({ name = "Small Blind" }, 9, 24, true)
m = R.outcome("SHOP", "ROUND_EVAL")
check("endless non-boss not mislabeled Boss Blind",
  type(m) == "string" and not m:find("Boss Blind", 1, true) and m:lower():find("endless", 1, true), m)

setg({ name = "The Wall", boss = true }, 5, 13, nil)
m = R.outcome("SELECTING_HAND", "GAME_OVER")
check("lost run", type(m) == "string" and m:lower():find("lost", 1, true) and m:find("5", 1, true), m)

setg({ name = "The Wall", boss = true }, 9, 30, true)
m = R.outcome("SELECTING_HAND", "GAME_OVER")
check("endless death announced (not silent, not 'lost the run')",
  type(m) == "string" and m:lower():find("endless run ended", 1, true), m)

G.GAME = { blind = { name = "Small Blind" }, won = nil }
m = R.outcome("SELECTING_HAND", "ROUND_EVAL")
check("missing ante/round -> '?' fallback, no throw", type(m) == "string" and m:find("?", 1, true), m)

setg({ name = "Small Blind" }, 3, 7, nil)
check("ROUND_EVAL re-entry -> nil", R.outcome("ROUND_EVAL", "ROUND_EVAL") == nil)
check("shop entry -> nil", R.outcome("BLIND_SELECT", "SHOP") == nil)
check("GAME_OVER re-entry -> nil", R.outcome("GAME_OVER", "GAME_OVER") == nil)

G.GAME = nil
check("no G.GAME -> nil, no throw", R.outcome("SELECTING_HAND", "ROUND_EVAL") == nil)

do
  local gen = 100
  local function tier(prev, state, hands_left)
    if hands_left ~= nil then G.GAME.current_round = { hands_left = hands_left } end
    gen = gen + 1
    G.NEURO = { run_generation = gen }
    local msg, spoken = R.outcome(prev, state)
    return msg, spoken
  end

  setg({ name = "The Goad", boss = true }, 5, 13, nil)
  local msg, spoken = tier("SELECTING_HAND", "GAME_OVER")
  check("losing the run invites a comment", msg ~= nil and spoken == true, tostring(spoken))

  setg({ name = "The Goad", boss = true }, 9, 20, true)
  msg, spoken = tier("SELECTING_HAND", "ROUND_EVAL")
  check("winning the run invites a comment", msg ~= nil and spoken == true, tostring(spoken))

  setg({ name = "The Wall", boss = true }, 9, 30, true)
  msg, spoken = tier("SELECTING_HAND", "GAME_OVER")
  check("the end of an endless run invites a comment", msg ~= nil and spoken == true, tostring(spoken))

  setg({ name = "The Hook", boss = true }, 6, 12, nil)
  msg, spoken = tier("SELECTING_HAND", "ROUND_EVAL")
  check("beating a boss invites a comment", msg ~= nil and spoken == true, tostring(spoken))

  setg({ name = "Small Blind" }, 3, 7, nil)
  msg, spoken = tier("SELECTING_HAND", "ROUND_EVAL", 2)
  check("a routine blind clear stays silent", msg ~= nil and not spoken, tostring(spoken))

  setg({ name = "Small Blind" }, 3, 7, nil)
  msg, spoken = tier("SELECTING_HAND", "ROUND_EVAL", 0)
  check("a blind taken on the last hand invites a comment",
    msg ~= nil and spoken == true, tostring(spoken))

  setg({ name = "Big Blind" }, 3, 8, nil)
  check("the fallback path really has no round data", G.GAME.current_round == nil)
  msg, spoken = tier("SELECTING_HAND", "ROUND_EVAL")
  check("no round data: a clear falls back to silent, never to spoken",
    msg ~= nil and not spoken, tostring(spoken))

  setg({ name = "Small Blind" }, 3, 7, nil)
  msg, spoken = tier("BLIND_SELECT", "SHOP")
  check("a non-outcome transition yields neither message nor speech",
    msg == nil and not spoken, tostring(spoken))
end

do
  G.NEURO = { run_generation = 1 }
  setg({ name = "Small Blind" }, 3, 7, nil)
  local first = R.outcome("SELECTING_HAND", "ROUND_EVAL")
  check("dedup: the first announcement of an outcome is delivered", type(first) == "string", first)
  local second = R.outcome("SELECTING_HAND", "ROUND_EVAL")
  check("dedup: the same outcome announced twice yields one message", second == nil, second)

  setg({ name = "Big Blind" }, 3, 8, nil)
  check("dedup: a different outcome in the same run still gets through",
    type(R.outcome("SELECTING_HAND", "ROUND_EVAL")) == "string")
end

do
  G.NEURO = { run_generation = 3 }
  setg({ name = "The Goad", boss = true }, 3, 8, nil)
  check("no previous state -> no GAME_OVER announcement", R.outcome(nil, "GAME_OVER") == nil)
  check("no previous state -> no ROUND_EVAL announcement", R.outcome(nil, "ROUND_EVAL") == nil)
  check("the suppressed announcement did not consume the dedup slot",
    G.NEURO.last_reward_outcome_key == nil, tostring(G.NEURO.last_reward_outcome_key))
end

do
  local Orchestrator = require("core.orchestrator")
  local Lifecycle = require("core.neuro_lifecycle")
  local ContextCompact = require("context.context_compact")

  local N = { enabled = true, persona = "neuro", emitted = {}, silents = {}, llm_paused = false,
    once_serials = {}, session_once_serials = {}, run_generation = 2, state = "SELECTING_HAND" }
  function N:send_context(msg, silent)
    self.emitted[#self.emitted + 1] = tostring(msg)
    self.silents[#self.emitted] = silent
    return true
  end
  function N:register_actions() end
  function N:unregister_actions() end
  function N:force_actions() end
  function N:send_action_result() end
  function N:update() end

  G.STATES = { SELECTING_HAND = 4, GAME_OVER = 8 }
  G.STATE = 8
  G.STATE_COMPLETE = true
  G.OVERLAY_MENU = nil
  G.FUNCS = {}
  G.GAME = {
    dollars = 0, chips = 100, used_vouchers = {}, round = 8,
    current_round = { hands_left = 0, discards_left = 0 },
    round_resets = { ante = 3 },
    blind = { name = "The Goad", boss = true, chips = 5000 },
    hands = { Pair = { level = 1, chips = 20, mult = 2, visible = true } },
    modifiers = {},
  }
  G.hand = { cards = {}, highlighted = {}, config = { card_limit = 5, highlighted_limit = 5 } }
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.playbook_extra = nil
  G.deck = { cards = {} }
  ContextCompact.invalidate_cache()
  G.NEURO = N

  Orchestrator._step_state_transition("GAME_OVER", true, "SELECTING_HAND")
  Lifecycle.reset_run_state()
  Orchestrator._step_state_transition("GAME_OVER", "GAME_OVER" ~= N.state, N.state)

  local deaths, death_silent = 0, nil
  for i, msg in ipairs(N.emitted) do
    if msg:find("lost the run", 1, true) then
      deaths = deaths + 1
      death_silent = N.silents[i]
    end
  end
  check("end to end: a run death is announced exactly once across the run reset",
    deaths == 1, "announcements=" .. deaths)
  check("end to end: the run death reaches the transport as an invitation (silent=false)",
    death_silent == false, tostring(death_silent))

  local leaked = {}
  for i, msg in ipairs(N.emitted) do
    if N.silents[i] ~= true and not msg:find("lost the run", 1, true) then leaked[#leaked + 1] = msg end
  end
  check("end to end: no other context in the frame became spoken",
    #leaked == 0, table.concat(leaked, " | "))
end

do
  local gen = 500
  local function round_eval(gm)
    gen = gen + 1
    G.GAME = gm
    G.NEURO = { run_generation = gen }
    return R.outcome("SELECTING_HAND", "ROUND_EVAL")
  end
  local function saved_boss(extra)
    local gm = { blind = { name = "The Wall", boss = true, chips = 50000 },
      round_resets = { ante = 6 }, round = 13, chips = 20000 }
    for k, v in pairs(extra or {}) do gm[k] = v end
    return gm
  end

  _G.SMODS = { saved = true }
  local msg, spoken = round_eval(saved_boss({ saved_text = true }))
  check("rescued boss is never called a beaten Boss Blind",
    type(msg) == "string" and not msg:find("You beat", 1, true) and not msg:find("cleared", 1, true), msg)
  check("rescued boss says outright that the blind was not beaten",
    type(msg) == "string" and msg:find("did NOT beat", 1, true) ~= nil
      and msg:find("unbeaten", 1, true) ~= nil, msg)
  check("rescue names the shortfall in chips",
    type(msg) == "string" and msg:find("20000", 1, true) ~= nil and msg:find("50000", 1, true) ~= nil, msg)
  check("a rescue is worth speaking on stream", spoken == true, tostring(spoken))
  check("rescue reports the ante the run was on", type(msg) == "string" and msg:find("ante 5", 1, true) ~= nil, msg)

  check("a readable save flag is named as a save effect",
    type(msg) == "string" and msg:find("A save effect kept the run alive", 1, true) ~= nil, msg)

  _G.SMODS = nil
  msg = round_eval(saved_boss({ saved_text = true }))
  check("G.GAME.saved_text alone is enough to name the save effect",
    type(msg) == "string" and msg:find("A save effect kept the run alive", 1, true) ~= nil, msg)

  _G.SMODS = { saved = true }
  msg = round_eval(saved_boss())
  check("SMODS.saved alone is enough to name the save effect",
    type(msg) == "string" and msg:find("A save effect kept the run alive", 1, true) ~= nil, msg)

  _G.SMODS = nil
  msg = round_eval(saved_boss())
  check("the chips predicate alone blocks the false clear when no save flag is readable",
    type(msg) == "string" and msg:find("did NOT beat", 1, true) ~= nil
      and msg:find("A save effect", 1, true) == nil, msg)
  _G.SMODS = { saved = true }

  _G.SMODS = { saved = true }
  local sm = { blind = { name = "Small Blind", chips = 300 }, round_resets = { ante = 2 },
    round = 4, chips = 120, saved_text = true }
  msg, spoken = round_eval(sm)
  check("an uncleared Small Blind is not reported as cleared either",
    type(msg) == "string" and not msg:find("You cleared", 1, true)
      and msg:find("did NOT beat", 1, true) ~= nil, msg)
  check("an uncleared Small Blind reports its own ante (never decremented)",
    type(msg) == "string" and msg:find("ante 2", 1, true) ~= nil, msg)
  check("a rescue on a routine blind is still spoken", spoken == true, tostring(spoken))

  msg = round_eval(saved_boss({ saved_text = true, won = true, round_resets = { ante = 9 }, win_ante = 8 }))
  check("failing the final boss and being saved is never announced as winning the run",
    type(msg) == "string" and not msg:lower():find("won the run", 1, true)
      and msg:find("did NOT beat", 1, true) ~= nil, msg)

  msg = round_eval(saved_boss({ saved_text = true, won = true, round_resets = { ante = 11 } }))
  check("an uncleared blind in endless is not dressed up as an endless clear",
    type(msg) == "string" and not msg:lower():find("endless", 1, true)
      and msg:find("did NOT beat", 1, true) ~= nil, msg)

  local gm = saved_boss({ saved_text = true })
  gen = gen + 1
  G.GAME = gm
  G.NEURO = { run_generation = gen }
  local first = R.outcome("SELECTING_HAND", "ROUND_EVAL")
  local second = R.outcome("SHOP", "ROUND_EVAL")
  check("a rescue is announced once per run, like every other outcome",
    type(first) == "string" and second == nil, tostring(second))

  _G.SMODS = nil
  msg = round_eval({ blind = { name = "The Wall", boss = true, chips = 50000 },
    round_resets = { ante = 6 }, round = 13, chips = 50000 })
  check("exactly meeting the requirement is still a clear",
    type(msg) == "string" and msg:find("You beat the Boss Blind", 1, true) ~= nil, msg)

  msg = round_eval({ blind = { name = "The Wall", boss = true, chips = 50000 },
    round_resets = { ante = 6 }, round = 13, chips = 60000 })
  check("beating the blind outright is untouched by the rescue branch",
    type(msg) == "string" and msg:find("You beat the Boss Blind", 1, true) ~= nil, msg)

  msg = round_eval({ blind = { name = "Small Blind" }, round_resets = { ante = 3 }, round = 7 })
  check("a mock with no chips data at all still reads as a clear",
    type(msg) == "string" and msg:find("You cleared", 1, true) ~= nil, msg)
end

do
  local Orchestrator = require("core.orchestrator")
  local ContextCompact = require("context.context_compact")

  local N = { enabled = true, persona = "neuro", emitted = {}, silents = {}, llm_paused = false,
    once_serials = {}, session_once_serials = {}, run_generation = 77, state = "SELECTING_HAND" }
  function N:send_context(msg, silent)
    self.emitted[#self.emitted + 1] = tostring(msg)
    self.silents[#self.emitted] = silent
    return true
  end
  function N:register_actions() end
  function N:unregister_actions() end
  function N:force_actions() end
  function N:send_action_result() end
  function N:update() end

  _G.SMODS = { saved = true }
  G.STATES = { SELECTING_HAND = 4, ROUND_EVAL = 7, GAME_OVER = 8 }
  G.STATE = 7
  G.STATE_COMPLETE = true
  G.OVERLAY_MENU = nil
  G.FUNCS = {}
  G.GAME = {
    dollars = 0, chips = 20000, used_vouchers = {}, round = 13,
    current_round = { hands_left = 0, discards_left = 0 },
    round_resets = { ante = 6 },
    blind = { name = "The Wall", boss = true, chips = 50000 },
    saved_text = true,
    hands = { Pair = { level = 1, chips = 20, mult = 2, visible = true } },
    modifiers = {},
  }
  G.hand = { cards = {}, highlighted = {}, config = { card_limit = 5, highlighted_limit = 5 } }
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.deck = { cards = {} }
  ContextCompact.invalidate_cache()
  G.NEURO = N

  Orchestrator._step_state_transition("ROUND_EVAL", true, "SELECTING_HAND")

  local victory, rescue, rescue_silent = nil, nil, nil
  for i, msg in ipairs(N.emitted) do
    if msg:find("You beat the Boss Blind", 1, true) or msg:lower():find("won the run", 1, true) then
      victory = msg
    end
    if msg:find("did NOT beat", 1, true) then rescue = msg; rescue_silent = N.silents[i] end
  end
  check("end to end: no victory claim reaches the transport for a blind that was not cleared",
    victory == nil, tostring(victory))
  check("end to end: the rescue really reaches the transport", rescue ~= nil, tostring(rescue))
  check("end to end: the rescue arrives as an invitation (silent=false)",
    rescue_silent == false, tostring(rescue_silent))
  _G.SMODS = nil
end

do
  local sent = {}
  G.NEURO = { run_generation = 4, enabled = true }
  require("core.context_delivery").reset_transport()
  function G.NEURO:send_context(msg, silent, receipt)
    sent[#sent + 1] = { msg = msg, silent = silent }
    if receipt then receipt.status = "written" end
    return true
  end

  local function joker(name, rarity, set)
    return { config = { center = { key = "j_x", name = name, set = set or "Joker", rarity = rarity,
      loc_txt = { name = name } } }, ability = { set = set or "Joker", name = name } }
  end

  check("a Common joker says nothing", R.announce_rare_joker(joker("Joker", 1)) == false)
  check("an Uncommon joker says nothing", R.announce_rare_joker(joker("Vampire", 2)) == false)
  check("a Tarot card is not a joker pull",
    R.announce_rare_joker(joker("The Fool", 3, "Tarot")) == false)
  check("nothing was sent for those", #sent == 0, tostring(#sent))

  check("the first Rare joker of the run is announced",
    R.announce_rare_joker(joker("Blueprint", 3)) == true)
  check("it goes out as an invitation, not as retention",
    #sent == 1 and sent[1].silent == false and sent[1].msg:find("Rare", 1, true) ~= nil
      and sent[1].msg:find("Blueprint", 1, true) ~= nil, sent[1] and sent[1].msg)

  check("only the FIRST one -- a second Rare pull is silent",
    R.announce_rare_joker(joker("Baron", 3)) == false and #sent == 1, tostring(#sent))
  check("a Legendary after a Rare is also silent (once per run, not once per rarity)",
    R.announce_rare_joker(joker("Perkeo", 4)) == false and #sent == 1, tostring(#sent))

  local declared = false
  for _, f in ipairs(require("core.lifecycle_registry").describe().run.fields) do
    if f == "rare_joker_announced" then declared = true end
  end
  check("the gate is a registered run-scoped lifecycle field", declared)
  require("core.lifecycle_registry").reset("run", G.NEURO, {})
  G.NEURO.run_generation = 5
  require("core.context_delivery").reset_transport()
  check("a fresh run announces its first Rare joker again",
    R.announce_rare_joker(joker("Brainstorm", 4)) == true and #sent == 2, tostring(#sent))
end

do
  local Config = require("core.config")
  Config.init({ settings = {}, colours = {} }, function() return true end)
  local Dispatcher = require("core.dispatcher")

  local function shop_world(rarity, name)
    local card = {
      cost = 5, sell_cost = 2, highlighted = false, sort_id = 77, debuff = false,
      ability = { set = "Joker", name = name, mult = 4 },
      config = { center = { key = "j_test", name = name, set = "Joker", rarity = rarity,
        loc_txt = { name = name, description = "+4 Mult" } } },
      juice_up = function() end, highlight = function() end,
    }
    G.STATES = { SHOP = 5 }
    G.STATE = 5
    G.E_MANAGER = nil
    G.OVERLAY_MENU = nil
    G.GAME = { dollars = 20, used_vouchers = {}, current_round = {}, round_resets = { ante = 1 },
      modifiers = {}, hands = {} }
    G.shop_jokers = { cards = { card }, config = { card_limit = 4 } }
    G.jokers = { cards = {}, config = { card_limit = 5 } }
    G.consumeables = { cards = {}, config = { card_limit = 2 } }
    G.hand = { cards = {}, highlighted = {}, config = { card_limit = 5, highlighted_limit = 5 } }
    G.FUNCS = { buy_from_shop = function() return true end }
    return card
  end

  local function buy(rarity, name)
    local sent = {}
    shop_world(rarity, name)
    G.NEURO = { run_generation = 9, enabled = true, _reservation_epoch = 0, reserved_dollars = 0 }
    function G.NEURO:send_context(msg, silent) sent[#sent + 1] = { msg = msg, silent = silent }; return true end
    local handler = Dispatcher.get_action_handler("buy_from_shop")
    local staged = handler and handler({ area = "shop_jokers", index = 1 })
    if type(staged) == "function" then staged() end
    return sent
  end

  local common = buy(1, "Joker")
  local spoken_common = 0
  for _, e in ipairs(common) do if e.silent == false then spoken_common = spoken_common + 1 end end
  check("end to end: buying a Common joker invites nothing", spoken_common == 0, spoken_common)

  local rare = buy(3, "Blueprint")
  local invitation
  for _, e in ipairs(rare) do if e.silent == false then invitation = e.msg end end
  check("end to end: buying a Rare joker really reaches the transport as an invitation",
    invitation ~= nil and invitation:find("Rare", 1, true) ~= nil
      and invitation:find("Blueprint", 1, true) ~= nil, tostring(invitation))
end

do
  local ContextDelivery = require("core.context_delivery")
  local Orchestrator = require("core.orchestrator")
  local Shop = require("handlers.shop_handlers")

  local function joker(key, name, sort_id, mult)
    return {
      sort_id = sort_id, cost = 4, sell_cost = 2, highlighted = false, debuff = false,
      ability = { set = "Joker", name = name, mult = mult },
      config = { center = { key = key, set = "Joker", rarity = 1,
        name = name, loc_txt = { name = name } } },
      juice_up = function() end, highlight = function(self, value) self.highlighted = value end,
    }
  end

  local sent = {}
  G.NEURO = { run_generation = 31, enabled = true, _reservation_epoch = 0,
    reserved_dollars = 0, once_serials = {}, session_once_serials = {} }
  function G.NEURO:send_context(msg, silent, receipt)
    sent[#sent + 1] = { msg = msg, silent = silent }
    if receipt then receipt.status = "written" end
    return true
  end
  G.GAME = { dollars = 20, used_vouchers = {}, round = 11,
    round_resets = { ante = 4, blind_choices = {} }, current_round = {}, modifiers = {}, hands = {} }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } }
  local popcorn = joker("j_popcorn", "Popcorn", 101, 4)
  local fillers = {}
  for i = 1, 4 do fillers[i] = joker("j_filler_" .. i, "Filler " .. i, i, 4) end
  G.jokers = { cards = { fillers[1], fillers[2], fillers[3], fillers[4], popcorn },
    config = { card_limit = 5 } }

  ContextDelivery.reset_transport()
  Orchestrator._step_joker_departures("SELECTING_HAND")
  table.remove(G.jokers.cards, 5)
  Orchestrator._step_joker_departures("ROUND_EVAL")
  check("Popcorn self-destruction reaches retained history exactly once",
    #sent == 1 and sent[1].msg:find("Popcorn was eaten", 1, true) ~= nil
      and sent[1].silent == true, sent[1] and sent[1].msg or tostring(#sent))
  Orchestrator._step_joker_departures("ROUND_EVAL")
  check("settled observer does not repeat the Popcorn event", #sent == 1, #sent)

  local gros = joker("j_gros_michel", "Gros Michel", 102, 15)
  G.GAME.round = 12
  G.jokers.cards = { gros }
  Orchestrator._step_joker_departures("SELECTING_HAND")
  G.jokers.cards = {}
  Orchestrator._step_joker_departures("ROUND_EVAL")
  check("Gros Michel extinction reaches retained history",
    #sent == 2 and sent[2].msg:find("Gros Michel was destroyed", 1, true) ~= nil,
    sent[2] and sent[2].msg or tostring(#sent))

  G.jokers.cards = { popcorn }
  Orchestrator._step_joker_departures("SHOP")
  G.jokers.cards = {}
  Orchestrator._step_joker_departures("SHOP")
  check("selling a self-expiring joker is not mislabeled as self-destruction", #sent == 2, #sent)

  local registered = false
  for _, field in ipairs(require("core.lifecycle_registry").describe().run.fields) do
    if field == "reward_joker_roster" then registered = true end
  end
  check("roster observation is run-scoped", registered)

  local even = joker("j_even_steven", "Even Steven", 200, 0)
  G.jokers.cards = { fillers[1], fillers[2], fillers[3], fillers[4], popcorn }
  G.shop_jokers = { cards = { even }, config = { card_limit = 2 } }
  G.shop_vouchers, G.shop_booster = { cards = {} }, { cards = {} }
  G.STATE, G.STATES = 5, { SHOP = 5, ROUND_EVAL = 7, SELECTING_HAND = 4 }
  G.FUNCS = {}
  local blocked, blocked_err = Shop.handle_buy_from_shop({ area = "shop_jokers", index = 1 })
  check("a genuinely full 5/5 roster refuses the purchase",
    blocked == nil and blocked_err and blocked_err.reason_code == "NO_SLOT",
    blocked_err and blocked_err.reason_code)

  Orchestrator._step_joker_departures("SELECTING_HAND")
  table.remove(G.jokers.cards, 5)
  Orchestrator._step_joker_departures("ROUND_EVAL")
  G.STATE = G.STATES.SHOP
  G.FUNCS.buy_from_shop = function(args)
    local card = args.config.ref_table
    table.remove(G.shop_jokers.cards, 1)
    G.jokers.cards[#G.jokers.cards + 1] = card
    G.GAME.dollars = G.GAME.dollars - card.cost
    return true
  end
  local execute, buy_err = Shop.handle_buy_from_shop({ area = "shop_jokers", index = 1 })
  check("Popcorn expiry makes the next purchase executable without a sell",
    type(execute) == "function", buy_err and buy_err.message)
  if type(execute) == "function" then execute() end
  check("the replacement lands in the freed fifth slot",
    #G.jokers.cards == 5 and G.jokers.cards[5] == even and #G.shop_jokers.cards == 0,
    #G.jokers.cards)
end

done()
