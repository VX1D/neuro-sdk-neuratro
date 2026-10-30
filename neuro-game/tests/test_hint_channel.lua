require("tests.stubs").setup({ love = "lazy", localize = true })

local H = require("tests.helpers")
local check, done = H.harness("hint-channel")
local FactHints = require("facts.fact_hints")
local Delivery = require("core.context_delivery")

local function spy(accept)
  Delivery.reset_transport()
  FactHints.reset_pending()
  local rec = { msgs = {}, silent = {} }
  _G.G = { P_CENTERS = require("tests.engine_centers").centers(), GAME = { round = 1 }, NEURO = {
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
    and rec.msgs[1] == "RULE ONE." and rec.silent[1] == true)
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
    #rec.msgs == 2 and rec.msgs[1] == "FIRST." and rec.msgs[2] == "SECOND.",
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
  check("the same exact candidate retries and commits", #rec.msgs == 1 and rec.msgs[1] == "RETRY.")
  FactHints.emit("voucher_basics_run", "RETRY. ")
  check("committed retry books the once gate", FactHints.pending_count() == 0)
end

do
  spy()
  local function joker(key, name)
    return { ability = { name = name, set = "Joker" },
      config = { center = { key = key, set = "Joker", blueprint_compat = true } } }
  end
  G.jokers = { cards = { joker("j_blueprint", "Blueprint"), joker("j_cavendish", "Cavendish") } }
  local CtxJokers = require("context.ctx_jokers")
  local bp1 = tostring(CtxJokers.jokers_section(nil))
  local bp2 = tostring(CtxJokers.jokers_section(nil))
  check("current copy target is restated inline on re-ask",
    bp1:find("copying now: Cavendish", 1, true) ~= nil and bp2 == bp1 and FactHints.pending_count() == 0, bp1)
  G.shop_jokers = { cards = { {
    ability = { name = "Baron", set = "Joker" }, edition = { polychrome = true },
    config = { center = { key = "j_baron", set = "Joker" } },
  } } }
  local edition = FactHints.shop_edition_hint()
  check("current shop edition is state, not retained memory",
    edition:find("Baron", 1, true) == nil and FactHints.pending_count() == 0, edition)
end

do
  local Dispatcher = require("core.dispatcher")
  local Actions = require("core.actions")
  local STATES = require("tests.engine_cards").states()

  local sent = {}
  local function arming_env()
    Delivery.reset_transport()
    FactHints.reset_pending()
    sent = {}
    H.orch_board({ kind = "club", state = "BLIND_SELECT", states = STATES, edit = function(g)
      g.GAME.pack_choices = nil
    end })
    local forced = {}
    G.NEURO = H.orch_neuro({
      dispatcher = Dispatcher, actions = Actions, session_once_serials = {},
      send_action_result = "noop", register_actions = "noop",
      send_context = function(_, msg, _silent, receipt)
        sent[#sent + 1] = tostring(msg)
        if receipt then receipt.status = "written" end
        return true
      end,
      force_actions = function(_, ctx, query) forced[#forced + 1] = tostring(ctx) .. tostring(query) end,
    })
    require("core.validate").reset_run_state()
    local Orch = require("core.orchestrator")
    Orch.reset_run_state()
    require("core.window").reset()
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
    local REAL_FORCE = require("force.force_router").get_force_for_state
    require("force.force_router").get_force_for_state = function()
      FactHints.emit("voucher_basics_run", "ABANDONED CANDIDATE. ")
      return nil
    end
    pcall(require("core.window")._test.arm, "BLIND_SELECT")
    require("force.force_router").get_force_for_state = REAL_FORCE
    check("W1a the discarded build queued a rule candidate and shipped nothing",
      FactHints.pending_count() == 1 and #forced == 0,
      FactHints.pending_count() .. "/" .. #forced)

    G.NEURO.force_dirty_at = G.TIMERS.REAL - 100
    G.TIMERS.REAL = G.TIMERS.REAL + 5
    pcall(require("core.window")._test.arm, "BLIND_SELECT")
    check("W1b the next force does ship", #forced == 1, tostring(#forced))
    check("W1c and the abandoned candidate does not ride out on it",
      delivered_text():find("ABANDONED CANDIDATE.", 1, true) == nil
        and FactHints.pending_count() == 0, delivered_text())
  end

  do
    local Orch, forced = arming_env()
    local REAL_FORCE = require("force.force_router").get_force_for_state
    require("force.force_router").get_force_for_state = function(state)
      FactHints.emit("voucher_basics_run", "LIVE RULE. ")
      return REAL_FORCE(state)
    end
    pcall(require("core.window")._test.arm, "BLIND_SELECT")
    require("force.force_router").get_force_for_state = REAL_FORCE
    check("W2a the force shipped", #forced == 1, tostring(#forced))
    check("W2b and the rule its build raised was flushed with it",
      delivered_text():find("LIVE RULE.", 1, true) ~= nil
        and FactHints.pending_count() == 0, delivered_text())
  end
end

done()
