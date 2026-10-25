local ES = require("tests.engine_cards").states()
_G.NEURO_TEST = true

local check, done = require("tests.helpers").harness("context-delivery")

local MOD_DIRS = { core = true, facts = true, force = true, context = true, handlers = true, util = true,
  hud = true, render = true }
local function fresh_modules()
  for name in pairs(package.loaded) do
    if MOD_DIRS[name:match("^([%w_]+)%.") or ""] then package.loaded[name] = nil end
  end
end

do
  local Delivery = require("core.context_delivery")
  local ActionGuide = require("facts.token_legends").ACTION_SEMANTICS_V1

  local function reset(sender)
    Delivery.reset_transport()
    _G.G = { NEURO = { send_context = sender } }
  end

  do
    local calls, committed = 0, 0
    reset(function(_, _, silent, receipt)
      calls = calls + 1
      check("rules are silent", silent == true)
      receipt.status = "written"
      return true, false, receipt
    end)
    check("immediate rule write is accepted", Delivery.rule("mechanic", "Always true.", {
      on_written = function() committed = committed + 1 end,
    }) == true)
    check("immediate write commits once", committed == 1 and calls == 1, committed .. "/" .. calls)
    Delivery.rule("mechanic", "Always true.")
    check("delivered rule is deduplicated", calls == 1, calls)
    check("a delivered rule identity cannot change",
      pcall(function() Delivery.rule("mechanic", "Now different.") end) == false)
  end

  do
    local typed_silent = false
    reset(function(_, _, silent, r)
      typed_silent = silent == true and r.kind == "context_rule" and r.context_key == ActionGuide.key
      return true
    end)
    check("essential guide delivery is typed and silent", Delivery.rule(
      ActionGuide.key, ActionGuide.text) == true and typed_silent)
    check("an accepted guide is already essential", Delivery.essential_ready())
    Delivery.reset_transport()
    check("transport reset clears guide readiness", not Delivery.essential_ready())

    local replay_typed_silent = false
    reset(function(_, _, silent, r)
      replay_typed_silent = silent == true and r.kind == "context_rule" and r.context_key == ActionGuide.key
      return true
    end)
    check("replayed canonical guide restores essential readiness",
      Delivery.rule(ActionGuide.key, ActionGuide.text) == true
        and replay_typed_silent and Delivery.essential_ready())
  end

  do
    local calls, receipts = 0, {}
    reset(function(_, _, _, r)
      calls = calls + 1
      receipts[#receipts + 1] = r
      r.status = calls == 1 and "rejected" or "written"
      return calls ~= 1, false, r
    end)
    check("rejected first attempt reports no acceptance",
      Delivery.event("event-1", "A past event happened.", { occurrence = "e1" }) == false)
    Delivery.step()
    check("rejected event retries and writes", calls == 2
      and Delivery._delivered()["event\1event-1\1e1"] == "A past event happened.", calls)
  end

  do
    local sent = {}
    reset(function(_, text)
      sent[#sent + 1] = text
      return text == "Written before."
    end)
    Delivery.rule("written", "Written before.")
    Delivery.rule("stuck", "Still in the backlog.")
    Delivery.reconnect_transport()
    sent = {}
    G.NEURO.send_context = function(_, text)
      sent[#sent + 1] = text
      return true
    end
    Delivery.step()
    local resent = {}
    for _, text in ipairs(sent) do resent[text] = true end
    check("a reconnect keeps a written rule delivered (BEST_PRACTICES.md:45)",
      Delivery._delivered()["rule\1written"] ~= nil and not resent["Written before."],
      table.concat(sent, " | "))
    check("and re-sends what never reached the outbox",
      resent["Still in the backlog."] and Delivery._delivered()["rule\1stuck"] ~= nil,
      table.concat(sent, " | "))
  end

  do
    reset(function(_, _, _, r) r.status = "written"; return true, false, r end)
    Delivery.rule("gloss:readable_common", "Glossary body.")
    for i = 1, 2500 do
      Delivery.rule("hint:k" .. i .. "@" .. i, "Hint body " .. i)
    end
    local remembered = 0
    for _ in pairs(Delivery._delivered()) do remembered = remembered + 1 end
    check("hint rules are capped, so delivery memory stops growing with the run",
      remembered == 2049, tostring(remembered))
    check("a fixed-key rule is never evicted, or the glossary would be sent to the model twice",
      Delivery._delivered()["rule\1gloss:readable_common"] ~= nil)
  end
end

do
  fresh_modules()
  require("tests.stubs").setup({ love = "lazy" })
  _G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {}, round = 3, round_resets = { ante = 2 } },
    STATES = ES, STATE = ES.SHOP, TIMERS = { REAL = 100 } }


  local CD = require("core.context_delivery")

  local function wire()
    local sent, receipts = {}, {}
    local b = { run_generation = 1 }
    function b:send_context(text, _, receipt)
      sent[#sent + 1] = text
      receipts[#receipts + 1] = receipt
      return not (self.refuse and text:find(self.refuse, 1, true))
    end
    return b, sent, receipts
  end

  do
    CD.reset_transport()
    local b, sent = wire()
    G.NEURO = b
    local text = "After the completed action 'sell_card': Sold: Joker for $1"
    local r1 = CD.event_at("action_applied", CD.here(), text, { bridge = b, occurrence = "sell-1" })
    local r2 = CD.event_at("action_applied", CD.here(), text, { bridge = b, occurrence = "sell-2" })
    check("two sales with equal prose in one round are both sent", #sent == 2, #sent)
    check("both report delivery", r1 == true and r2 == true, tostring(r1) .. "/" .. tostring(r2))
    CD.event_at("action_applied", CD.here(), text, { bridge = b, occurrence = "sell-2" })
    check("the same occurrence emitted again is not sent again", #sent == 2, #sent)
    CD.event_at("recovered_action:x:completed", CD.here(), "Recovered x.", { bridge = b, occurrence = "x:completed" })
    CD.event_at("recovered_action:x:completed", CD.here(), "Recovered x.", { bridge = b, occurrence = "x:completed" })
    check("an emitter that names a stable occurrence keeps its idempotence", #sent == 3, #sent)
    local ok = pcall(CD.event_at, "outcome", {}, "An emitter that names nothing.", { bridge = b })
    check("an event with no occurrence is refused, so no default can merge two happenings", not ok and #sent == 3, #sent)
  end

  do
    CD.reset_transport()
    local b, sent, receipts = wire()
    G.NEURO = b
    b.refuse = "Still in the backlog"
    local committed = 0
    CD.event("evt:written", "Reached the outbox before the reconnect.",
      { bridge = b, occurrence = "w", on_written = function() committed = committed + 1 end })
    CD.event("evt:buffered", "Still in the backlog at the reconnect.", { bridge = b, occurrence = "b" })
    check("both frames were handed to the transport once", #sent == 2, #sent)
    b.refuse = nil
    CD.reconnect_transport()
    CD.step()
    local resent_written, resent_buffered = 0, 0
    for i = 3, #sent do
      if sent[i]:find("Reached the outbox", 1, true) then resent_written = resent_written + 1 end
      if sent[i]:find("Still in the backlog", 1, true) then resent_buffered = resent_buffered + 1 end
    end
    check("a frame already appended to the outbox is not re-sent after a reconnect",
      resent_written == 0, resent_written)
    check("and it counts as delivered", committed == 1, committed)
    check("a frame the reconnect discarded from the backlog is re-sent once", resent_buffered == 1,
      resent_buffered)
    CD.event("evt:written", "Reached the outbox before the reconnect.", { bridge = b, occurrence = "w" })
    check("re-emitting the written occurrence later is still a no-op", #sent == 3, #sent)
  end

  do
    CD.reset_transport()
    local D = require("core.dispatcher")
    local PlanGate = require("core.gate")
    G.NEURO = { dispatcher = D, state = "SHOP", run_generation = 1 }
    local function joker()
      return require("tests.engine_cards").card({ ability = { set = "Joker", name = "Joker" }, sell_cost = 1,
        config = { center = { key = "j_joker", set = "Joker", loc_txt = { name = "Joker" } } } })
    end
    G.jokers = { cards = { joker(), joker(), joker() }, config = { card_limit = 5 } }
    G.GAME = G.GAME or {}
    G.GAME.dollars = 0
    G.FUNCS.sell_card = function(e)
      for i, card in ipairs(G.jokers.cards) do
        if card == e.config.ref_table then
          table.remove(G.jokers.cards, i)
          G.GAME.dollars = G.GAME.dollars + card.sell_cost
          break
        end
      end
    end
    local DecisionDelta = require("facts.decision_delta")
    local deltas = {}
    local contexts = {}
    local bridge = {
      send_action_result = function() end,
      send_context = function(_, msg) contexts[#contexts + 1] = msg return true end,
    }
    require("tests.helpers").stage_registered(nil, { "sell_card" })
    local Staging = require("core.staging")
    local function sell(id)
      G.NEURO.plan = {
        build = "Keep the remaining jokers.", build_scope = PlanGate.current_build_scope(),
        money = "Sell a plain Joker.", money_scope = PlanGate.current_economy_scope(),
      }
      G.NEURO.econ_plan_ok = true
      local _, review = D.get_action_handler("sell_card")({ area = "jokers", index = 1, name = "Joker" })
      require("core.gate").delivered(review)
      local _, candidate = DecisionDelta.for_force("SHOP")
      DecisionDelta.commit(candidate)
      D.route_message({ command = "action",
        data = { id = id, name = "sell_card", data = '{"area":"jokers","index":1,"name":"Joker"}' } }, bridge)
      for _ = 1, 300 do
        if not require("core.execute").busy() then break end
        G.TIMERS.REAL = G.TIMERS.REAL + 0.25
        Staging.update()
        require("core.execute").step(G.TIMERS.REAL)
      end
      deltas[#deltas + 1] = DecisionDelta.for_force("SHOP") or ""
    end
    sell("occ-1")
    G.TIMERS.REAL = G.TIMERS.REAL + 30
    sell("occ-2")
    local sold = 0
    for _, text in ipairs(deltas) do
      if text:find("jokers lost Joker", 1, true) and text:find("(+$1)", 1, true) then sold = sold + 1 end
    end
    check("selling two identical jokers for the same price shows both sales to the next forces", sold == 2
      and #contexts == 0, sold .. " / contexts " .. #contexts .. ": " .. table.concat(deltas, " | "))
  end

  do
    CD.reset_transport()
    local Orchestrator = require("core.orchestrator")
    local sent = {}
    G.NEURO = { run_generation = 3, enabled = true }
    function G.NEURO:send_context(msg, _, receipt)
      sent[#sent + 1] = msg
      if receipt then receipt.status = "written" end
      return true
    end
    local function popcorn(sort_id)
      return require("tests.engine_cards").card({ sort_id = sort_id, ability = { set = "Joker", name = "Popcorn", mult = 0 },
        config = { center = { key = "j_popcorn", set = "Joker", rarity = 1, name = "Popcorn" } } })
    end
    G.GAME = { round = 11, round_resets = { ante = 4 }, current_round = {} }
    G.jokers = { cards = { popcorn(101), popcorn(102) }, config = { card_limit = 5 } }
    Orchestrator._step_joker_departures("SELECTING_HAND")
    G.jokers.cards = {}
    Orchestrator._step_joker_departures("ROUND_EVAL")
    Orchestrator._step_joker_departures("ROUND_EVAL")
    local eaten = 0
    for _, msg in ipairs(sent) do
      if msg:find("Popcorn was eaten", 1, true) then eaten = eaten + 1 end
    end
    check("two identical Popcorns eaten in one round are two departures", eaten == 2,
      eaten .. ": " .. table.concat(sent, " | "))
  end

  do
    local calls, bare = 0, {}
    local files = io.popen("find core force handlers context facts util hud render -name '*.lua' 2>/dev/null; ls neuro-game.lua")
    for path in files:lines() do
      local f = io.open(path, "r")
      local src = f and f:read("*a") or ""
      if f then f:close() end
      local init = 1
      while true do
        local s, e = src:find("Delivery%.[%a_]+%(", init)
        if not s then break end
        init = e + 1
        local fn = src:sub(s, e):match("^Delivery%.([%a_]+)%($")
        if fn == "event" or fn == "prompt" or fn == "event_at" or fn == "prompt_at" then
          local depth, i = 1, e + 1
          while depth > 0 and i <= #src do
            local c = src:sub(i, i)
            if c == "(" then depth = depth + 1 elseif c == ")" then depth = depth - 1 end
            i = i + 1
          end
          calls = calls + 1
          if not src:sub(e + 1, i - 1):find("occurrence", 1, true) then
            local line = select(2, src:sub(1, s):gsub("\n", "\n")) + 1
            bare[#bare + 1] = path .. ":" .. line
          end
        end
      end
    end
    files:close()
    check("the scan found the production emitters", calls >= 8, calls)
    check("every production event or prompt names its occurrence", #bare == 0, table.concat(bare, ", "))
  end
end

do
  fresh_modules()
  require("tests.stubs").setup({ love = "lazy", localize = true })

  local function read(path)
    local f = assert(io.open(path, "r"))
    local s = f:read("*a")
    f:close()
    return s
  end

  local ContextDelivery = require("core.context_delivery")
  local ContextCompact = require("context.context_compact")
  local Window = require("core.window")

  local function producer()
    for level = 3, 10 do
      local info = debug.getinfo(level, "S")
      if not info then break end
      if info.what ~= "C" then return tostring(info.source) end
    end
    return "?"
  end

  local wire, foreign = {}, {}
  local function record(_, msg, silent, receipt)
    local from = producer()
    wire[#wire + 1] = { msg = tostring(msg), silent = silent, from = from }
    if not from:find("core/context_delivery.lua", 1, true) then foreign[#foreign + 1] = from end
    if receipt then receipt.status = "written" end
    return true
  end

  local function world(dollars, joker_name, send)
    _G.G = {
      STATE = ES.SELECTING_HAND, STATES = ES, P_CENTERS = require("tests.engine_centers").centers(),
      GAME = {
        dollars = dollars, chips = 0, bankrupt_at = 0, used_vouchers = {}, modifiers = {},
        current_round = { hands_left = 3, discards_left = 2, reroll_cost = 5 },
        round_resets = { ante = 2 }, blind = { name = "Small Blind", chips = 300, mult = 1 },
      },
      jokers = { cards = joker_name and { { ability = { name = joker_name, set = "Joker" },
        config = { center = { key = "j_test", name = joker_name, set = "Joker" } } } } or {},
        config = { card_limit = 5 } },
      consumeables = { cards = {}, config = { card_limit = 2 } },
      hand = { cards = {}, highlighted = {} }, playing_cards = {},
      NEURO = { enabled = true, run_generation = 1, once_serials = {}, session_once_serials = {},
        stable_refresh_due = true, send_context = send or record },
    }
  end

  ContextDelivery.reset_transport()
  world(8, "Joker")
  Window.emit_rules("SELECTING_HAND")
  local first = #wire
  check("driving the real producer puts retained context on the wire", first > 0, tostring(first))
  check("L1b every retained frame was produced by the typed owner, no other caller reached the bridge",
    #foreign == 0, table.concat(foreign, ", "))
  local all_silent = first > 0
  for i = 1, first do if wire[i].silent ~= true then all_silent = false end end
  check("L1c retained frames are silent", all_silent)

  world(23, "Bull")
  Window.emit_rules("SELECTING_HAND")
  check("a live run mutation produces no second retained frame", #wire == first, tostring(#wire))

  ContextDelivery.rule("lifetime:probe", "immutable rule text")
  local after_probe = #wire
  check("L3a a rule is written once", after_probe == first + 1, tostring(after_probe))
  local ok_change = pcall(ContextDelivery.rule, "lifetime:probe", "rewritten rule text")
  check("L3b rewriting a delivered key is refused, never framed a second time",
    ok_change == false and #wire == after_probe, tostring(ok_change) .. "/" .. tostring(#wire))

  local RECEIPT_RULE = "receipt-gated rule"
  local rejected = 0
  world(8, "Joker", function(_, _, _, receipt)
    rejected = rejected + 1
    if receipt then receipt.status = "rejected" end
    return false
  end)
  local accepted = ContextDelivery.rule("lifetime:receipt", RECEIPT_RULE)
  check("L4a a frame the bridge refused is not treated as delivered",
    accepted == false and rejected == 1 and #wire == after_probe,
    tostring(accepted) .. "/" .. tostring(rejected))
  G.NEURO.send_context = record
  ContextDelivery.step()
  check("L4b the refused frame is retried and physically written exactly once",
    #wire == after_probe + 1 and wire[#wire].msg == RECEIPT_RULE, tostring(#wire))
  ContextDelivery.rule("lifetime:receipt", RECEIPT_RULE)
  check("L4c and once written it is committed, so it is never framed again",
    #wire == after_probe + 1, tostring(#wire))

  local Metrics = require("util.metrics")

  local function delivered_count()
    local n = 0
    for _ in pairs(ContextDelivery._delivered() or {}) do n = n + 1 end
    return n
  end

  local function delivered_has(text)
    for _, v in pairs(ContextDelivery._delivered() or {}) do
      if v == text then return true end
    end
    return false
  end

  local function counter(name) return Metrics._counters[name] or 0 end

  do
    ContextDelivery.reset_transport()
    local STALE = "frame refused by the transport view that was replaced mid-loop"
    world(8, "Joker", function(_, _, _, receipt)
      if receipt then receipt.status = "rejected" end
      return false
    end)
    ContextDelivery.rule("lifetime:stale-epoch", STALE)
    local old_view_retries = 0
    G.NEURO.send_context = function(_, msg, _, receipt)
      if tostring(msg) == STALE then old_view_retries = old_view_retries + 1 end
      ContextDelivery.reset_transport()
      if receipt then receipt.status = "rejected" end
      return false
    end
    ContextDelivery.step()
    check("L5a a frame refused while the transport is replaced is not committed",
      not delivered_has(STALE), "delivered=" .. tostring(delivered_count()))
    G.NEURO.send_context = record
    ContextDelivery.step()
    check("L5b and it is re-attempted on the new view, not dropped",
      old_view_retries >= 1 and delivered_has(STALE), "retries=" .. tostring(old_view_retries))
  end

  do
    ContextDelivery.reset_transport()
    world(8, "Joker", record)
    for _ = 1, 5 do ContextDelivery.step() end
    local before = counter("context_delivery_abandoned")
    local attempts = 0
    world(8, "Joker", function(_, _, _, receipt)
      attempts = attempts + 1
      if receipt then receipt.status = "rejected" end
      return false
    end)
    ContextDelivery.rule("lifetime:never-accepted", "a frame the bridge always refuses")
    local CAP = 200
    for _ = 1, CAP do ContextDelivery.step() end
    check("a frame the bridge never accepts is abandoned instead of retried forever",
      attempts < CAP, attempts .. " attempts in " .. CAP .. " frames")
    check("L6b and its abandonment is counted",
      counter("context_delivery_abandoned") == before + 1,
      tostring(counter("context_delivery_abandoned") - before))
    local settled = attempts
    for _ = 1, 20 do ContextDelivery.step() end
    check("L6c after which the entry is gone from pending, not merely quiet",
      attempts == settled, attempts .. " vs " .. settled)
  end

  do
    ContextDelivery.reset_transport()
    world(8, "Joker", record)
    local BATCH = 600
    for i = 1, BATCH do ContextDelivery.event("lifetime:ev:" .. i, "event " .. i, { occurrence = i }) end
    local after_first = delivered_count()
    for i = BATCH + 1, BATCH * 2 do ContextDelivery.event("lifetime:ev:" .. i, "event " .. i, { occurrence = i }) end
    local after_second = delivered_count()
    check("transient identity memory saturates instead of growing with the stream",
      after_second == after_first and after_second < BATCH * 2,
      after_first .. " then " .. after_second .. " for " .. (BATCH * 2) .. " events")
    check("L7b it is the OLDEST identities that are dropped, so a recent one is still deduplicated",
      not delivered_has("event 1") and delivered_has("event " .. (BATCH * 2)),
      "oldest kept: " .. tostring(delivered_has("event 1")))
    ContextDelivery.rule("lifetime:durable-rule", "a rule that must outlive the event stream")
    for i = BATCH * 2 + 1, BATCH * 3 do ContextDelivery.event("lifetime:ev:" .. i, "event " .. i, { occurrence = i }) end
    check("L7c and a rule is never evicted by the event stream it shares the store with",
      delivered_has("a rule that must outlive the event stream"), "rule evicted")
  end

  do
    ContextDelivery.reset_transport()
    local CARRIED = "a rule the old transport never accepted"
    world(8, "Joker", record)
    ContextDelivery.rule("lifetime:carry-delivered", "already on the old wire")
    local delivered_before = delivered_count()
    G.NEURO.send_context = function(_, _, _, receipt)
      if receipt then receipt.status = "rejected" end
      return false
    end
    ContextDelivery.rule("lifetime:carry-pending", CARRIED)
    check("L8a the fixture really has one delivered and one undelivered entry",
      delivered_before == 1 and not delivered_has(CARRIED), tostring(delivered_before))

    ContextDelivery.reset_transport()
    check("L8b reset_transport clears the delivered view for the new SDK-side transport",
      delivered_count() == 0, tostring(delivered_count()))

    local written = {}
    G.NEURO.send_context = function(_, msg, _silent, receipt)
      written[#written + 1] = tostring(msg)
      if receipt then receipt.status = "written" end
      return true
    end
    ContextDelivery.step()
    check("L8c and carries the never-written entry into it instead of abandoning it",
      written[1] == CARRIED and delivered_has(CARRIED), table.concat(written, " | "))
  end
end

done()
