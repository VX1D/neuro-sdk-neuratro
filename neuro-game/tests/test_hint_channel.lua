_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("hint-channel")
local FactHints = require("facts.fact_hints")
local Delivery = require("core.context_delivery")

local function spy(accept)
  Delivery.reset_transport()
  FactHints.reset_pending()
  local rec = { msgs = {}, silent = {} }
  _G.G = { GAME = { round = 1 }, NEURO = {
    once_serials = {}, session_once_serials = {}, state_enter_serial = 1,
    decision_serial = 1, run_generation = 1,
  } }
  G.NEURO.send_context = function(_, msg, silent, receipt)
    if accept == false then
      if receipt then receipt.status = "rejected" end
      return false
    end
    rec.msgs[#rec.msgs + 1] = tostring(msg)
    rec.silent[#rec.silent + 1] = silent
    if receipt then receipt.status = "written" end
    return true
  end
  return rec
end

do
  local rec = spy()
  local ret = FactHints.emit("voucher_basics_run", "RULE ONE. ")
  check("retained rule returns no query text", ret == "")
  check("retained rule waits for the explicit flush", #rec.msgs == 0 and FactHints.pending_count() == 1)
  check("flush writes the exact bytes silently", FactHints.flush_pending() == 1
    and rec.msgs[1] == "RULE ONE. " and rec.silent[1] == true)
  check("physical write books and deduplicates the rule",
    FactHints.emit("voucher_basics_run", "RULE ONE. ") == ""
      and FactHints.pending_count() == 0 and FactHints.flush_pending() == 0)
end

do
  local rec = spy()
  FactHints.emit("voucher_basics_run", "FIRST. ")
  FactHints.emit("voucher_chain:v_hone,v_glow_up", "SECOND. ")
  FactHints.flush_pending()
  check("retained rules keep separate stable identities instead of an order-sensitive batch",
    #rec.msgs == 2 and rec.msgs[1] == "FIRST. " and rec.msgs[2] == "SECOND. ",
    table.concat(rec.msgs, "|"))
end

do
  local rec = spy(false)
  FactHints.emit("voucher_basics_run", "RETRY. ")
  check("rejected transport does not report delivery", FactHints.flush_pending() == 0 and #rec.msgs == 0)
  G.NEURO.send_context = function(_, msg, silent, receipt)
    rec.msgs[#rec.msgs + 1] = msg
    rec.silent[#rec.silent + 1] = silent
    receipt.status = "written"
    return true
  end
  Delivery.step()
  check("the same exact candidate retries and commits", #rec.msgs == 1 and rec.msgs[1] == "RETRY. ")
  FactHints.emit("voucher_basics_run", "RETRY. ")
  check("committed retry books the once gate", FactHints.pending_count() == 0)
end

do
  spy()
  local first = FactHints.emit("pack_cons", "CURRENT. ")
  local second = FactHints.emit("pack_cons", "CURRENT. ")
  G.NEURO.decision_serial = 2
  local third = FactHints.emit("pack_cons", "CURRENT. ")
  check("mutable state is included on initial force, re-ask, and next decision",
    first == "CURRENT. " and second == first and third == first)
  check("mutable state never enters retained queue", FactHints.pending_count() == 0)
end

do
  spy()
  local function joker(key, name)
    return { ability = { name = name, set = "Joker" },
      config = { center = { key = key, set = "Joker" } } }
  end
  G.jokers = { cards = { joker("j_blueprint", "Blueprint"), joker("j_cavendish", "Cavendish") } }
  local bp1 = FactHints.blueprint_chain_hint()
  local bp2 = FactHints.blueprint_chain_hint()
  check("current copy target is restated inline on re-ask",
    bp1:find("Blueprint", 1, true) and bp1:find("Cavendish", 1, true) and bp2 == bp1, bp1)
  G.shop_jokers = { cards = { {
    ability = { name = "Baron", set = "Joker" }, edition = { polychrome = true },
    config = { center = { key = "j_baron", set = "Joker" } },
  } } }
  local edition = FactHints.shop_edition_hint()
  check("current shop edition is state, not retained memory",
    edition:find("Baron (Polychrome)", 1, true) ~= nil and FactHints.pending_count() == 0, edition)
end

do
  local Dispatcher = require("core.dispatcher")
  local Actions = require("core.actions")
  local STATES = { BLIND_SELECT = 1, SHOP = 2, SELECTING_HAND = 3 }

  local sent = {}
  local function arming_env()
    Delivery.reset_transport()
    FactHints.reset_pending()
    sent = {}
    _G.G = {
      STATE = STATES.BLIND_SELECT, STATES = STATES, STATE_COMPLETE = true,
      TIMERS = { REAL = 1000 }, SETTINGS = { GAMESPEED = 1 },
      GAME = { dollars = 20, blind_on_deck = "Small", round = 11, chips = 0, STOP_USE = 0,
        current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
        round_resets = { ante = 4,
          blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_club" },
          blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" } },
        blind = { name = "Big Blind" }, used_vouchers = {}, modifiers = {},
        hands = { Pair = { level = 1, chips = 10, mult = 2, visible = true } } },
      P_BLINDS = { bl_small = { key = "bl_small", name = "Small Blind" },
        bl_big = { key = "bl_big", name = "Big Blind" },
        bl_club = { key = "bl_club", name = "The Club" } },
      jokers = { cards = {}, config = { card_limit = 5 } },
      consumeables = { cards = {}, config = { card_limit = 2 } },
      hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
      deck = { cards = {} },
      shop_jokers = { cards = {}, config = { card_limit = 2 } },
      shop_vouchers = { cards = {}, config = { card_limit = 1 } },
      shop_booster = { cards = {}, config = { card_limit = 2 } },
      FUNCS = { get_poker_hand_info = function(c) return "Pair", {}, { Pair = { c } }, c end,
        select_blind = function() end },
      CONTROLLER = { locks = {} }, blind_select = {}, E_MANAGER = { queues = {} },
    }
    local forced = {}
    G.NEURO = {
      enabled = true, persona = "neuro", run_generation = 1,
      dispatcher = Dispatcher, actions = Actions,
      _decision_windows = {}, once_serials = {}, session_once_serials = {},
      decision_serial = 1, state_enter_serial = 1, reserved_dollars = 0,
      update = function() end,
      send_action_result = function() end,
      register_actions = function() end,
      unregister_actions = function() end,
      send_context = function(_, msg, _silent, receipt)
        sent[#sent + 1] = tostring(msg)
        if receipt then receipt.status = "written" end
        return true
      end,
      force_actions = function(_, ctx, query) forced[#forced + 1] = tostring(ctx) .. tostring(query) end,
    }
    require("core.transition_guard").reset()
    local Orch = require("core.orchestrator")
    Orch.reset_run_state()
    require("core.force_state").clear_force_state()
    G.NEURO.force_dirty = true
    G.NEURO.force_dirty_at = G.TIMERS.REAL - 100
    require("hud.state").state_changed_at = G.TIMERS.REAL - 100
    return Orch, forced
  end

  local function delivered_text()
    local rows = {}
    for _, text in pairs(Delivery._delivered() or {}) do rows[#rows + 1] = tostring(text) end
    return table.concat(sent, " ") .. " || " .. table.concat(rows, " ")
  end

  do
    local Orch, forced = arming_env()
    local REAL_FORCE = Dispatcher.get_force_for_state
    Dispatcher.get_force_for_state = function()
      FactHints.emit("voucher_basics_run", "ABANDONED CANDIDATE. ")
      return nil -- the build is discarded: no flush, no arm, nothing on the wire
    end
    pcall(Orch._step_force_arming, "BLIND_SELECT", G.TIMERS.REAL)
    Dispatcher.get_force_for_state = REAL_FORCE
    check("W1a the discarded build queued a rule candidate and shipped nothing",
      FactHints.pending_count() == 1 and #forced == 0,
      FactHints.pending_count() .. "/" .. #forced)

    G.NEURO.force_dirty = true
    G.NEURO.force_dirty_at = G.TIMERS.REAL - 100
    G.TIMERS.REAL = G.TIMERS.REAL + 5
    pcall(Orch._step_force_arming, "BLIND_SELECT", G.TIMERS.REAL)
    check("W1b the next force does ship", #forced == 1, tostring(#forced))
    check("W1c and the abandoned candidate does not ride out on it",
      delivered_text():find("ABANDONED CANDIDATE.", 1, true) == nil
        and FactHints.pending_count() == 0, delivered_text())
  end

  do
    local Orch, forced = arming_env()
    local REAL_FORCE = Dispatcher.get_force_for_state
    Dispatcher.get_force_for_state = function(state)
      FactHints.emit("voucher_basics_run", "LIVE RULE. ")
      return REAL_FORCE(state)
    end
    pcall(Orch._step_force_arming, "BLIND_SELECT", G.TIMERS.REAL)
    Dispatcher.get_force_for_state = REAL_FORCE
    check("W2a the force shipped", #forced == 1, tostring(#forced))
    check("W2b and the rule its build raised was flushed with it",
      delivered_text():find("LIVE RULE.", 1, true) ~= nil
        and FactHints.pending_count() == 0, delivered_text())
  end
end

done()
