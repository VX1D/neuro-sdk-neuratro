local M = {}

require("tests.engine_cards").install_smods(rawget(_G, "SMODS"))

M.RID = { ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9,
          ["10"] = 10, J = 11, Q = 12, K = 13, A = 14 }
M.VALN = { J = "Jack", Q = "Queen", K = "King", A = "Ace" }

function M.harness(label)
  local fails, total = 0, 0
  local function check(name, cond, detail)
    total = total + 1
    if cond then
      print("PASS  " .. name)
    else
      fails = fails + 1
      print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or ""))
    end
  end
  local function done()
    print(string.format("==== %s: %d/%d PASS, %d FAIL ====", label, total - fails, total, fails))
    os.exit(fails == 0 and 0 or 1)
  end
  return check, done
end


function M.stage_registered(state, extra)
  local Registry = require("core.action_registry")
  if state then
    local ok, names = pcall(function()
      return require("core.actions").get_valid_actions_for_state(state)
    end)
    if ok and names then Registry.note_registered(names) end
  end
  if extra then Registry.note_registered(extra) end
end

function M.force_payload(state_name, force)
  force = force or require("force.force_router").get_force_for_state(state_name)
  if type(force) ~= "table" then return "" end
  local ok, state = pcall(require("core.window").build_payload, state_name, force)
  local parts = {}
  if ok and type(state) == "string" and state ~= "" then parts[#parts + 1] = state end
  if type(force.query) == "string" and force.query ~= "" then parts[#parts + 1] = force.query end
  return table.concat(parts, "\n")
end

function M.force_frame(state_name, force)
  force = force or require("force.force_router").get_force_for_state(state_name)
  if type(force) ~= "table" then return "", "" end
  local ok, state = pcall(require("core.window").build_payload, state_name, force)
  return (ok and type(state) == "string") and state or "", type(force.query) == "string" and force.query or ""
end

function M.drain_hints()
  local FactHints = require("facts.fact_hints")
  if FactHints.pending_count() == 0 then return "" end
  local N = G and G.NEURO
  if not N then return "" end
  local prev = N.send_context
  local got = {}
  N.send_context = function(_, msg) got[#got + 1] = tostring(msg) return true end
  FactHints.flush_pending()
  N.send_context = prev
  return table.concat(got)
end

function M.collector()
  local fails, total = {}, 0
  local function check(name, cond)
    total = total + 1
    if not cond then fails[#fails + 1] = name end
  end
  local function count()
    return total
  end
  return check, fails, count
end

function M.cash_out_ready(g, dollars)
  g = g or G
  g.round_eval = g.round_eval or {}
  local button = { config = { id = "cash_out_button", button = "cash_out" } }
  local box = { config = { major = g.round_eval } }
  function box.get_UIE_by_ID(_, id) return id == "cash_out_button" and button or nil end
  g.I = g.I or {}
  g.I.UIBOX = g.I.UIBOX or {}
  g.I.UIBOX[#g.I.UIBOX + 1] = box
  if dollars ~= nil and g.GAME then
    g.GAME.current_round = g.GAME.current_round or {}
    g.GAME.current_round.dollars = dollars
  end
  return button
end

local HANDLIST = { "Flush Five", "Flush House", "Five of a Kind", "Straight Flush", "Four of a Kind", "Full House",
  "Flush", "Straight", "Three of a Kind", "Two Pair", "Pair", "High Card" }

function M.poker_hand_info(name, scoring)
  return require("tests.engine_hand_info").stub(name, scoring)
end

local HAND_BASE = {
  ["Flush Five"] = { false, 160, 16, 50, 3 }, ["Flush House"] = { false, 140, 14, 40, 4 },
  ["Five of a Kind"] = { false, 120, 12, 35, 3 }, ["Straight Flush"] = { true, 100, 8, 40, 4 },
  ["Four of a Kind"] = { true, 60, 7, 30, 3 }, ["Full House"] = { true, 40, 4, 25, 2 },
  Flush = { true, 35, 4, 15, 2 }, Straight = { true, 30, 4, 30, 3 }, ["Three of a Kind"] = { true, 30, 3, 20, 2 },
  ["Two Pair"] = { true, 20, 2, 20, 1 }, Pair = { true, 10, 2, 15, 1 }, ["High Card"] = { true, 5, 1, 10, 1 },
}

function M.game_hands(over)
  local hands = {}
  for order, name in ipairs(HANDLIST) do
    local b = HAND_BASE[name]
    local h = { visible = b[1], order = order, chips = b[2], mult = b[3], s_chips = b[2], s_mult = b[3],
      level = 1, l_chips = b[4], l_mult = b[5], played = 0, played_this_round = 0 }
    for k, v in pairs((over or {})[name] or {}) do h[k] = v end
    hands[name] = h
  end
  return hands
end

function M.play_card(sort_id)
  return require("tests.engine_cards").card({
    sort_id = sort_id, cost = 0, sell_cost = 0,
    ability = { set = "Default", name = "Mock" }, config = { center = {} },
    base = { value = tostring(sort_id + 4), suit = "Hearts" },
    juice_up = function() end,
  })
end

function M.area(cards, limit)
  return { cards = cards or {}, config = { card_limit = limit or 5 } }
end

local CardAreaRules = {}
CardAreaRules.__index = CardAreaRules

local function forced_in_hand(area, card)
  return card and card.ability and card.ability.forced_selection and area == G.hand
end

function CardAreaRules:add_to_highlighted(card)
  local kind = self.config.type
  if kind == "shop" or kind == "joker" or kind == "consumeable" then
    if #self.highlighted >= self.config.highlighted_limit then self:remove_from_highlighted(self.highlighted[1]) end
    self.highlighted[#self.highlighted + 1] = card
    card:highlight(true)
  elseif #self.highlighted >= self.config.highlighted_limit then
    card:highlight(false)
  else
    self.highlighted[#self.highlighted + 1] = card
    card:highlight(true)
  end
end

function CardAreaRules:remove_from_highlighted(card, force)
  if not force and forced_in_hand(self, card) then return end
  for i = #self.highlighted, 1, -1 do
    if self.highlighted[i] == card then
      table.remove(self.highlighted, i)
      break
    end
  end
  card:highlight(false)
end

function CardAreaRules:unhighlight_all()
  for i = #self.highlighted, 1, -1 do
    if not forced_in_hand(self, self.highlighted[i]) then
      self.highlighted[i]:highlight(false)
      table.remove(self.highlighted, i)
    end
  end
end

function M.card_area(area)
  area.cards = area.cards or {}
  area.highlighted = area.highlighted or {}
  area.config = area.config or {}
  area.config.highlighted_limit = area.config.highlighted_limit or 5
  area.config.type = area.config.type or "deck"
  return setmetatable(area, CardAreaRules)
end

function M.print_recorder(get_records)
  return function(text)
    local records = get_records()
    records[#records + 1] = tostring(text or "")
  end
end

function M.rect_recorder(get_records)
  return function(mode, x, y, w, h)
    local records = get_records()
    records[#records + 1] = { mode = mode, x = x, y = y, w = w, h = h }
  end
end

function M.flat_mult_joker(key, name)
  return {
    cost = 4, sell_cost = 2, ability = { set = "Joker", name = name, mult = 4 },
    config = { center = { key = key, name = name, set = "Joker",
      loc_txt = { name = name, description = "+4 Mult" } } },
  }
end

function M.is_owed(action_id)
  for _, entry in ipairs(require("core.bridge").tx.outstanding(0)) do
    if entry.key == action_id then return true end
  end
  return false
end

function M.open_force(state_name, names)
  local set = {}
  for _, name in ipairs(names) do set[name] = true end
  G.NEURO.force_window_id = (tonumber(G.NEURO.force_window_id) or 0) + 1
  local ok, valid = pcall(require("core.actions").get_valid_actions_for_state, state_name)
  local legal = {}
  for _, name in ipairs(ok and valid or {}) do legal[name] = true end
  for name in pairs(set) do legal[name] = true end
  G.NEURO.force_window = { id = G.NEURO.force_window_id, state = state_name, phase = "forced",
    names = names, set = set, legal = legal, sent_at = require("util.utils").gate_now("force_liveness_timeout") }
  return G.NEURO.force_window
end

function M.pre_action(name, data, bridge)
  if type(data) == "string" then
    local ok, decoded = pcall(require("util.neuro_json").decode, data)
    if not ok then return false, require("core.action_result").SDK.INVALID_JSON, false, "SCHEMA_INVALID" end
    data = decoded
  end
  local Validate = require("core.validate")
  local forced = require("core.window").forced(name)
  local busy, retry = Validate.busy_reason(name, bridge)
  local refusal = busy and require("core.action_result").wait(busy, retry) or nil
  local streak
  if not refusal then
    refusal, streak = Validate._test.admission(name, data or {}, forced, require("core.state").get_state_name())
  end
  if refusal then
    if refusal.reason_code == "CONFIRMATION_REQUIRED" then require("core.gate").delivered(refusal) end
    return false, refusal.message, require("core.action_result").terminal(refusal.reason_code, forced),
      refusal.reason_code
  end
  Validate.note_accepted({ name = name, streak = streak, forced = forced })
  return true
end

function M.enforce()
  local Validate = require("core.validate")
  return setmetatable({
    pre_action = function(bridge, name, data) return M.pre_action(name, data, bridge) end,
    note_rejection = Validate._test.note_rejection,
  }, { __index = Validate, __newindex = Validate })
end

function M.force_phase()
  local window = G and G.NEURO and G.NEURO.force_window
  return type(window) == "table" and window.phase or "none"
end

function M.selecting_hand_env(opts)
  opts = opts or {}
  G.TIMERS.REAL = opts.time or 100
  M.in_engine_state("SELECTING_HAND")
  G.STATE_COMPLETE = true
  G.OVERLAY_MENU = nil
  G.CONTROLLER = nil
  G.GAME = {
    dollars = 10, chips = 0, used_vouchers = {},
    current_round = { hands_left = 4, discards_left = 2 },
    round_resets = { ante = 1, blind_on_deck = "Small",
      blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" } },
    blind_on_deck = "Small",
    hands = { Pair = { level = 1, chips = 20, mult = 2, visible = true } },
    modifiers = {},
  }
  G.hand = M.card_area({ cards = { M.play_card(1), M.play_card(2), M.play_card(3), M.play_card(4), M.play_card(5) },
    highlighted = {}, config = { card_limit = 5, highlighted_limit = 5 } })
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.deck = { cards = {} }
  G.FUNCS = {
    get_poker_hand_info = require("tests.engine_hand_info").stub("Pair"),
  }
  require("core.validate").reset_run_state()
  if opts.reset_tx_cache then require("core.bridge").tx.reset() end
end

function M.receipt_selecting_hand_env(t)
  G.TIMERS.REAL = t
  M.in_engine_state("SELECTING_HAND")
  G.GAME = {
    dollars = 10, chips = 0, used_vouchers = {},
    current_round = { hands_left = 3, discards_left = 2 },
    round_resets = { ante = 1 },
    hands = { Pair = { level = 1, chips = 20, mult = 2, visible = true } },
  }
  G.hand = M.card_area({ cards = { M.play_card(1), M.play_card(2), M.play_card(3) },
    highlighted = {}, config = { card_limit = 5, highlighted_limit = 5 } })
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.FUNCS = {
    get_poker_hand_info = require("tests.engine_hand_info").stub("Pair"),
  }
  require("core.validate").reset_run_state()
end

local function long_bracket_end(text, i)
  local eq = text:match("^%[(=*)%[", i)
  if not eq then return nil end
  local close = "]" .. eq .. "]"
  local _, e = text:find(close, i + #eq + 2, true)
  if not e then return #text + 1 end
  return e + 1
end

local function blank_but_newlines(s)
  return (s:gsub("[^\n]", ""))
end

local function quoted_end(text, i, q)
  local n = #text
  local j = i + 1
  while j <= n do
    local c = text:sub(j, j)
    if c == "\\" then
      j = j + 2
    elseif c == q then
      return j + 1
    elseif c == "\n" then
      return j
    else
      j = j + 1
    end
  end
  return n + 1
end

function M.strip_lua_comments(text)
  local out, i, n = {}, 1, #text
  while i <= n do
    local j = text:find("[\"'%[%-]", i)
    if not j then
      out[#out + 1] = text:sub(i)
      break
    end
    if j > i then out[#out + 1] = text:sub(i, j - 1) end
    i = j
    local ch = text:sub(i, i)
    if ch == '"' or ch == "'" then
      local e = quoted_end(text, i, ch)
      out[#out + 1] = text:sub(i, e - 1)
      i = e
    elseif ch == "[" then
      local e = long_bracket_end(text, i)
      if e then
        out[#out + 1] = text:sub(i, e - 1)
        i = e
      else
        out[#out + 1] = ch
        i = i + 1
      end
    elseif ch == "-" and text:sub(i + 1, i + 1) == "-" then
      local e = long_bracket_end(text, i + 2)
      if e then
        out[#out + 1] = blank_but_newlines(text:sub(i, e - 1))
        i = e
      else
        i = text:find("\n", i, true) or (n + 1)
      end
    else
      out[#out + 1] = ch
      i = i + 1
    end
  end
  return table.concat(out)
end

function M.delivered(handler)
  return function(...)
    local exec, err, extra = handler(...)
    if type(err) == "table" and err.reason_code == "CONFIRMATION_REQUIRED" then require("core.gate").delivered(err) end
    return exec, err, extra
  end
end

function M.review_text(err)
  local e = require("core.action_result").normalize(err)
  return require("context.state_doc").lines(e.facts, e.message)
end

function M.open_proposal(indices, verdict, hand_type)
  local HH = require("handlers.hand_handlers")
  local cards = {}
  for i, index in ipairs(indices) do cards[i] = G.hand.cards[index] end
  local Gate = require("core.gate")
  Gate.invalidate()
  return Gate.open_proposal(Gate.proposal_fields({ signature = HH.play_signature(cards),
    content = HH.play_content(cards), indices = indices, hand_type = hand_type or "Pair" }),
    verdict or "Committing Pair.")
end

function M.review(name, stage, data, ctx)
  local Gate = require("core.gate")
  local rejection = Gate.check(stage or "admission", name, data, ctx)
  if rejection then Gate.delivered(rejection) end
  return rejection
end

local NAMED_POSITIONS = {
  play_hand = { indices = "cards" }, discard_hand = { indices = "cards" },
  use_consumable = { hand_indices = "hand_cards" }, choose_pack_card = { hand_indices = "hand_cards" },
  use_directional_consumable = { left_index = "left_card", right_index = "right_card" },
  choose_directional_pack_card = { left_index = "left_card", right_index = "right_card" },
}

function M.with_card_names(name, data)
  local fields = NAMED_POSITIONS[name]
  if not fields then return data end
  local json = require("util.neuro_json")
  local decoded = data
  if type(data) == "string" then
    local ok, value = pcall(json.decode, data)
    if not ok or type(value) ~= "table" then return data end
    decoded = value
  end
  if type(decoded) ~= "table" then return data end
  local hand = G and G.hand and G.hand.cards or {}
  local function label(idx)
    local card = hand[tonumber(idx)]
    return card and require("facts.card_area_util").hand_card_name(card) or "?"
  end
  local changed = false
  for positions, names in pairs(fields) do
    local value = decoded[positions]
    if decoded[names] == nil and value ~= nil then
      if type(value) == "table" then
        local out = {}
        for i, idx in ipairs(value) do out[i] = label(idx) end
        decoded[names] = out
      else
        decoded[names] = label(value)
      end
      changed = true
    end
  end
  if not changed then return data end
  return type(data) == "string" and json.encode(decoded) or decoded
end

function M.index_only(text)
  return (tostring(text):gsub("(%d+): [^,()]+", "%1"))
end

-- Inbound actions carry what she sends: positions only, no card names (her real inbox); a test adds names explicitly.
function M.inbound_action(name, id, data)
  local json = require("util.neuro_json")
  return {
    command = "action",
    data = { id = id, name = name, data = type(data) == "table" and json.encode(data) or data },
  }
end

M.SUCCESS_MESSAGE_MAX = 560

local MOCK_RESET = {
  "hand", "jokers", "consumeables", "deck",
  "shop_jokers", "shop_vouchers", "shop_booster",
  "pack_cards", "booster_pack",
  "blind_select_opts", "blind_select",
  "OVERLAY_MENU", "STATES", "STATE", "TIMERS", "P_CENTER_POOLS",
}

function M.mock_state(desc_match, state, reset_gate)
  if reset_gate then require("core.gate").reset() end
  for _, k in ipairs(MOCK_RESET) do G[k] = nil end
  G.GAME = { current_round = {} }
  G.NEURO.reserved_dollars = 0
  G.NEURO.shop_reroll_count = 0
  local TD = require("tests.test_deadlock")
  for _, sc in ipairs(TD.SCENARIOS) do
    if sc.state == state and sc.desc:find(desc_match, 1, true) then
      TD.apply_mock(sc.mock())
      M.in_scenario_state(sc)
      G.NEURO.persona = "neuro"; G.NEURO.state_entry_hints = nil
      return
    end
  end
  error(string.format("mock_state: no scenario matching %q in state %s", desc_match, state))
end

function M.quiet_harness(label, max_report)
  local fails, total = 0, 0
  local function check(name, cond, detail)
    total = total + 1
    if not cond then
      fails = fails + 1
      if fails <= max_report then
        print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or ""))
      end
    end
  end
  local function done()
    print(string.format("==== %s: %d/%d PASS, %d FAIL ====", label, total - fails, total, fails))
    os.exit(fails == 0 and 0 or 1)
  end
  return check, done
end

function M.orch_ticker(get, set)
  local Orch = require("core.orchestrator")
  local function step()
    set(get() + 0.1)
    G.TIMERS.REAL = get()
    return pcall(Orch.update, 0.1)
  end
  local T = {}
  function T.tick_for(seconds)
    for _ = 1, math.floor(seconds / 0.1) do
      local ok, err = step()
      if not ok then print("ORCH ERR: " .. tostring(err)) break end
    end
  end
  function T.tick_until(pred, max_seconds)
    for _ = 1, math.floor((max_seconds or 60) / 0.1) do
      if pred() then return true end
      local ok, err = step()
      if not ok then print("ORCH ERR: " .. tostring(err)) return false end
    end
    return pred()
  end
  function T.poll_until(pred, max_seconds)
    for _ = 1, math.floor((max_seconds or 60) / 0.1) do
      if pred() then return true end
      T.tick_for(0.1)
    end
    return pred()
  end
  return T
end

function M.state_setter()
  local clock = 0
  return function(sc)
    M.in_scenario_state(sc)
    clock = clock + 5
    G.TIMERS = G.TIMERS or {}
    G.TIMERS.REAL = clock
  end
end

function M.in_engine_state(name)
  G.STATES = require("tests.engine_cards").states()
  G.STATE = assert(G.STATES[name], "no engine state " .. tostring(name))
end

function M.in_scenario_state(sc)
  M.in_engine_state(sc.engine_state or sc.state)
end

function M.run_setup_overlay()
  return { config = {}, get_UIE_by_ID = function(_, id) return id == "run_setup_seed" and { config = {} } or nil end }
end

function M.options_overlay()
  local back = { config = { id = "overlay_menu_back_button", button = "exit_overlay_menu" } }
  return { config = {}, get_UIE_by_ID = function(_, id) return id == "overlay_menu_back_button" and back or nil end }
end

function M.unlock_overlay(card_id)
  local back = { config = { id = "overlay_menu_back_button", button = "continue_unlock" } }
  return { config = {}, joker_unlock_table = card_id,
    get_UIE_by_ID = function(_, id) return id == "overlay_menu_back_button" and back or nil end }
end

function M.game_over_overlay()
  local new_run = { config = { id = "from_game_over", button = "notify_then_setup_run" } }
  return { config = { no_esc = true }, get_UIE_by_ID = function(_, id) return id == "from_game_over" and new_run or nil end }
end

function M.base_G()
  local g = {
    NEURO = { run_generation = 1 }, STATES = require("tests.engine_cards").states(),
    P_BLINDS = { bl_small = { name = "Small Blind", dollars = 3, mult = 1 },
                 bl_big = { name = "Big Blind", dollars = 4, mult = 1.5 },
                 bl_hook = { name = "The Hook", dollars = 5, mult = 2, boss = true, debuff = {} } },
    P_TAGS = {}, P_CENTERS = require("tests.engine_centers").centers(), TIMERS = { REAL = 100, TOTAL = 100 },
    SETTINGS = { GAMESPEED = 1, paused = false }, SPEEDFACTOR = 1,
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    deck = { cards = {} }, playing_cards = {}, FUNCS = {},
    GAME = {
      dollars = 20, bankrupt_at = 0, chips = 0, round = 4, skips = 0, win_ante = 8,
      used_vouchers = {}, modifiers = {}, tags = {}, interest_amount = 1, interest_cap = 25,
      probabilities = { normal = 1 }, starting_params = {}, hands = {},
      blind = { name = "Big Blind", chips = 600, dollars = 4, in_blind = true, boss = false,
                debuff = {}, disabled = false, hands = {}, get_type = function() return "Big" end },
      current_round = { hands_left = 3, discards_left = 2, discards_used = 0,
        most_played_poker_hand = "High Card", reroll_cost = 5, free_rerolls = 0,
        dollars_to_be_earned = "" },
      round_resets = { ante = 3, blind_ante = 3, hands = 4, discards = 3,
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" },
        blind_states = { Small = "Defeated", Big = "Current", Boss = "Upcoming" } },
      round_bonus = { discards = 0, next_hands = 0 },
    },
  }
  g.STATE = g.STATES.SELECTING_HAND
  _G.G = g
  return g
end

function M.shop_env()
  G.TIMERS.REAL = 100
  M.in_engine_state("SHOP")
  G.STATE_COMPLETE = true
  G.OVERLAY_MENU = nil
  G.GAME = { dollars = 10, used_vouchers = {}, round_resets = { ante = 2 },
    current_round = {}, modifiers = {} }
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = { require("tests.fake_cards").fool() }, config = { card_limit = 2 } }
  G.hand = { cards = {}, highlighted = {}, config = { card_limit = 5 } }
  G.deck = { cards = {} }
  G.shop_jokers = { cards = {} }
  G.FUNCS = { sell_card = function() end }
  require("core.validate").reset_run_state()
  require("core.validate").reset_run_state()
end

function M.shop_go(check, state_id)
  local Orchestrator = require("core.orchestrator")
  return function(from, to)
    G.STATE = state_id[to]
    G.NEURO.state = from
    local ok, err = pcall(Orchestrator._step_state_transition, to, true, from)
    check("transition " .. from .. " -> " .. to .. " completes without error", ok, err)
    G.NEURO.state = to
    Orchestrator._step_shop_entry_settle(to)
  end
end

local FULL_RESET = {
  "GAME", "hand", "jokers", "consumeables", "deck", "playing_cards",
  "shop_jokers", "shop_vouchers", "shop_booster", "shop",
  "pack_cards", "booster_pack", "blind_select_opts", "blind_select",
  "OVERLAY_MENU", "challenge_tab", "CHALLENGES",
  "STATES", "STATE", "TIMERS", "P_CENTER_POOLS", "P_TAGS", "P_BLINDS", "SETTINGS",
}

function M.reset_board()
  for _, k in ipairs(MOCK_RESET) do G[k] = nil end
  G.GAME = { current_round = {} }
  G.NEURO.reserved_dollars = 0
  G.NEURO.shop_reroll_count = 0
end

function M.reset_board_full()
  for _, k in ipairs(FULL_RESET) do G[k] = nil end
  G.GAME = { current_round = {} }
  G.NEURO.reserved_dollars, G.NEURO.persona = 0, nil
  G.NEURO.state_enter_serial = (tonumber(G.NEURO.state_enter_serial) or 0) + 1000
end

function M.scenario(desc)
  for _, sc in ipairs(require("tests.test_deadlock").SCENARIOS) do if sc.desc == desc then return sc end end
  error("no scenario " .. desc)
end

function M.read_file(path)
  local fh = io.open(path, "r")
  if not fh then return nil end
  local s = fh:read("*a")
  fh:close()
  return s
end

function M.read_lines(dir, name)
  local out = {}
  local f = dir and io.open(dir .. "/" .. name, "r")
  if f then
    for l in f:lines() do out[#out + 1] = l end
    f:close()
  end
  return out
end

function M.outbox_frames(path, opts)
  opts = opts or {}
  local out = {}
  local f, err = io.open(path, "rb")
  if opts.must then assert(f, err) end
  if not f then return out end
  local raw = f:read("*a")
  f:close()
  local json = require("util.neuro_json")
  for line in raw:gmatch("[^\n]+") do
    local ok, frame = pcall(json.decode, line)
    if ok and type(frame) == "table" then
      if opts.command == nil or frame.command == opts.command then out[#out + 1] = frame end
    elseif opts.placeholder then
      out[#out + 1] = { command = "UNPARSEABLE" }
    end
  end
  return out
end

function M.has(list, v)
  for _, x in ipairs(list or {}) do if x == v then return true end end
  return false
end

function M.offered_set(force)
  local set = {}
  for _, name in ipairs(force and force.actions or {}) do set[name] = true end
  return set
end

function M.plan_frame(window)
  local FactHints = require("facts.fact_hints")
  local state, note = FactHints.plan_state(window), FactHints.plan_note(window)
  if state == "" and note == "" then return "" end
  return state .. "\n" .. note
end

function M.tools_block(query_text)
  local text = tostring(query_text or "")
  local at = text:find(require("force.force_helpers").TOOLS_LEAD, 1, true)
  if not at then return "" end
  local finish = text:find("\n\n", at, true)
  return text:sub(at, finish and finish - 1 or nil)
end

function M.area_row(text, area, index)
  local inside = false
  for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
    if line:find("^## ") then
      inside = line:find('(area "' .. area .. '"', 1, true) ~= nil
    elseif inside and line:sub(1, #tostring(index) + 2) == tostring(index) .. ". " then
      return line
    end
  end
  return nil
end

function M.built_text(res)
  if type(res) ~= "table" then return "" end
  return (res.query or "") .. "\n" .. (res.state_extra or "")
end

function M.force_signature(state)
  local force = require("force.force_router").get_force_for_state(state)
  if not force then return nil end
  return table.concat(force.actions, ",")
end

function M.each_position(n, fn)
  local bad = nil
  for pos = 1, n do
    local ok, detail = fn(pos)
    if not ok and not bad then bad = "at hidden position " .. pos .. ": " .. tostring(detail) end
  end
  return bad == nil, bad or "all positions 1.." .. n
end

function M.fresh_game_rules()
  package.loaded["context.game_rules"] = nil
  return require("context.game_rules")
end

function M.dispatch(name, id, data, b)
  require("core.dispatcher").handle_message(M.inbound_action(name, id, data), b)
end

function M.overlay_with(ids)
  return { get_UIE_by_ID = function(_, id) return ids[id] and {} or nil end }
end

function M.fresh_neuro()
  return { once_serials = {}, session_once_serials = {}, run_generation = 1,
    state_enter_serial = 1, decision_serial = 1 }
end

function M.joker_hits_board(cards)
  _G.G = { NEURO = {}, GAME = { hands = {} }, jokers = { cards = cards },
    P_CENTERS = require("tests.engine_centers").centers() }
  require("core.joker_hits").reset_run_state()
end

function M.fs_bridge(dir)
  os.execute("rm -rf " .. dir)
  os.execute("mkdir -p " .. dir)
  return require("core.bridge"):new({ enabled = true, fs_dir = dir })
end

function M.written_context(_, _, receipt)
  if receipt then receipt.status = "written" end
  return true
end

function M.wire_context(wire)
  return function(_, msg, silent, receipt)
    wire[#wire + 1] = { msg = msg, silent = silent }
    receipt.status = "written"
    return true
  end
end

local function mirrored(key, fn)
  if key ~= "register_actions" or type(fn) ~= "function" then return fn end
  return function(self, defs, ...)
    local result = fn(self, defs, ...)
    if result ~= false then
      for _, d in ipairs(defs or {}) do self._registered_sigs[d.name] = self._registered_sigs[d.name] or true end
    end
    return result
  end
end

function M.started_bridge(b)
  local Bridge = require("core.bridge")
  b.session_id = b.session_id or 1
  b.last_transition_at = b.last_transition_at or -math.huge
  b._registered_sigs = b._registered_sigs or {}
  b.is_transport_saturated = b.is_transport_saturated or Bridge.is_transport_saturated
  b.is_transition_cooldown = b.is_transition_cooldown or Bridge.is_transition_cooldown
  b.register_actions = mirrored("register_actions", rawget(b, "register_actions"))
  b.withdraw_actions = b.withdraw_actions or function() return true end
  local mt = {}
  for k, v in pairs(getmetatable(b) or {}) do mt[k] = v end
  local outer = mt.__newindex
  mt.__newindex = function(t, key, fn)
    if outer then outer(t, key, mirrored(key, fn)) else rawset(t, key, mirrored(key, fn)) end
  end
  return setmetatable(b, mt)
end

function M.fake_bridge(opts)
  opts = opts or {}
  local reason_key = opts.reason or "reason_code"
  local b = { results = {} }
  function b:send_action_result(id, ok, message, reason)
    self.results[#self.results + 1] = { id = id, ok = ok, message = message, [reason_key] = reason }
    if opts.ack == "written" then return true, { status = "written" } end
    if opts.ack then return true end
  end
  if opts.context == "emitted" then b.emitted = {} end
  if opts.context == "contexts" then b.contexts = {} end
  function b:send_context(message)
    if opts.context == "emitted" then self.emitted[#self.emitted + 1] = tostring(message) end
    if opts.context == "contexts" then self.contexts[#self.contexts + 1] = message end
    if opts.context_ack ~= false then return true end
  end
  if opts.register == "count" then
    b.registered = 0
    b.register_actions = function() b.registered = b.registered + 1 end
  elseif opts.register == "noop" then
    b.register_actions = function() end
  end
  if opts.cooldown then b.is_transition_cooldown = function() return false end end
  if opts.force then b.force_actions = function() end end
  if opts.send then b.send = function() end end
  for k, v in pairs(opts.over or {}) do b[k] = v end
  return b
end

function M.noop() end
function M.yes() return true end
function M.no() return false end

function M.receipt_written(_, _, _, receipt)
  if receipt then receipt.status = "written" end
  return true
end

function M.result_log(log, fields, ack)
  return function(self, ...)
    local entry = {}
    for i, k in ipairs(fields) do
      if k ~= "_" then entry[k] = (select(i, ...)) end
    end
    local into = type(log) == "string" and self[log] or log
    into[#into + 1] = entry
    if ack == "written" then return true, { status = "written" } end
    if ack ~= nil then return ack end
  end
end

local STUB_METHODS = { send_action_result = true, send_context = true, register_actions = true,
  withdraw_actions = true, force_actions = true, is_transition_cooldown = true, is_transport_saturated = true,
  update = true, send = true, send_startup = true }
local STUB_VALUES = { noop = M.noop, ["true"] = M.yes, ["false"] = M.no, written = M.receipt_written }

function M.stub_bridge(fields)
  local b = {}
  for k, v in pairs(fields) do
    b[k] = (STUB_METHODS[k] and type(v) == "string" and STUB_VALUES[v]) or v
  end
  return b
end

local function blind_trio(boss_key, boss_name)
  return { bl_small = { key = "bl_small", name = "Small Blind" },
    bl_big = { key = "bl_big", name = "Big Blind" },
    [boss_key] = { key = boss_key, name = boss_name } }
end

local ORCH_BOARDS = {
  hook = function(state, clock, states)
    return {
      P_CENTERS = require("tests.engine_centers").centers(),
      STATE = states[state], STATES = states, STATE_COMPLETE = true,
      TIMERS = { REAL = clock }, SETTINGS = { GAMESPEED = 1 },
      GAME = {
        dollars = 10, chips = 0, used_vouchers = {}, modifiers = {}, STOP_USE = 0,
        blind_on_deck = "Small",
        current_round = { hands_left = 4, discards_left = 2, reroll_cost = 5 },
        round_resets = { ante = 1, blind_on_deck = "Small",
          blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" },
          blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" } },
        blind = { name = "Small Blind" },
        hands = { Pair = { level = 1, chips = 20, mult = 2, visible = true } },
      },
      P_BLINDS = blind_trio("bl_hook", "The Hook"),
      hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
      jokers = { cards = {}, config = { card_limit = 5 } },
      consumeables = { cards = {}, config = { card_limit = 2 } },
      deck = { cards = {} },
      shop_jokers = { cards = {} }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
      FUNCS = { get_poker_hand_info = require("tests.engine_hand_info").stub("Pair"), select_blind = M.noop },
      CONTROLLER = { locks = {} }, blind_select = {}, E_MANAGER = { queues = {} },
    }
  end,
  club = function(state, clock, states)
    return {
      P_CENTERS = require("tests.engine_centers").centers(),
      STATE = states[state], STATES = states, STATE_COMPLETE = true,
      TIMERS = { REAL = clock }, SETTINGS = { GAMESPEED = 1 },
      GAME = { dollars = 20, blind_on_deck = "Small", round = 11, chips = 0, STOP_USE = 0,
        current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
        round_resets = { ante = 4,
          blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_club" },
          blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" } },
        blind = { name = "Big Blind" }, used_vouchers = {}, modifiers = {},
        hands = { Pair = { level = 1, chips = 10, mult = 2, visible = true } }, pack_choices = 2 },
      P_BLINDS = blind_trio("bl_club", "The Club"),
      jokers = { cards = {}, config = { card_limit = 5 } },
      consumeables = { cards = {}, config = { card_limit = 2 } },
      hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
      deck = { cards = {} },
      shop_jokers = { cards = {}, config = { card_limit = 2 } },
      shop_vouchers = { cards = {}, config = { card_limit = 1 } },
      shop_booster = { cards = {}, config = { card_limit = 2 } },
      FUNCS = { get_poker_hand_info = require("tests.engine_hand_info").stub("Pair"), select_blind = M.noop },
      CONTROLLER = { locks = {} }, blind_select = {}, E_MANAGER = { queues = {} },
    }
  end,
}

function M.orch_board(o)
  local g = ORCH_BOARDS[o.kind or "hook"](o.state or "SELECTING_HAND", o.clock or 1000,
    o.states or require("tests.engine_cards").states())
  if o.edit then o.edit(g) end
  _G.G = g
  return g
end

M.NONE = setmetatable({}, { __tostring = function() return "NONE" end })

function M.orch_neuro(over)
  local n = { enabled = true, persona = "neuro", run_generation = 1, once_serials = {}, decision_serial = 1,
    state_enter_serial = 1, reserved_dollars = 0, update = M.noop }
  for k, v in pairs(M.stub_bridge(over or {})) do
    if v == M.NONE then n[k] = nil else n[k] = v end
  end
  return M.started_bridge(n)
end

function M.orch_reset()
  require("core.validate").reset_run_state()
  require("core.action_registry").reset()
  require("core.bridge").tx.reset()
  require("core.orchestrator").reset_run_state()
end

function M.orch_world(o)
  M.orch_board(o)
  G.NEURO = M.orch_neuro(o.neuro)
  M.orch_reset()
  return G
end

function M.snapshot_env()
  local globals, loaded = {}, {}
  for k in pairs(_G) do globals[k] = true end
  for k in pairs(package.loaded) do loaded[k] = true end
  return function()
    for k in pairs(_G) do if not globals[k] then _G[k] = nil end end
    for k in pairs(package.loaded) do if not loaded[k] then package.loaded[k] = nil end end
  end
end

function M.run_module(name, label, board, ...)
  if board then
    _G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = board == "timed" and { REAL = 0 } or nil,
      P_CENTERS = require("tests.engine_centers").centers() }
    G.NEURO.dispatcher = require("core.dispatcher")
    G.NEURO.actions = require("core.actions")
  end
  local ok_r, fails, checks = pcall(require(name).run, ...)
  if not ok_r then print("RUN ERROR: " .. tostring(fails)); os.exit(4) end
  if type(fails) ~= "number" then print("RUN ERROR: non-numeric fail count: " .. tostring(fails)); os.exit(4) end
  print(label .. "_FAILS=" .. fails .. " (0 = clean)"
    .. (type(checks) == "number" and (" " .. label .. "_CHECKS=" .. checks) or ""))
  os.exit(fails == 0 and 0 or 1)
end

function M.event_manager()
  local em = { queue = {} }
  function em:add_event(event) self.queue[#self.queue + 1] = event end
  function em:run()
    local due = self.queue
    self.queue = {}
    for _, event in ipairs(due) do
      if not event.func() then self.queue[#self.queue + 1] = event end
    end
  end
  _G.Event = rawget(_G, "Event") or function(event) return event end
  G.E_MANAGER = em
  return em
end

function M.registry_contracts()
  local Registry = require("core.action_registry")
  local out = {}
  for _, name in ipairs(Registry.names()) do out[#out + 1] = Registry.get(name) end
  return out
end

function M.registry_problems(opts)
  opts = opts or {}
  local Registry = require("core.action_registry")
  local errors = {}
  for _, contract in ipairs(M.registry_contracts()) do
    if type(contract.description) ~= "string" or contract.description == "" then
      errors[#errors + 1] = contract.name .. ": missing description"
    end
    if type(contract.schema) ~= "table" or contract.schema.type ~= "object" then
      errors[#errors + 1] = contract.name .. ": missing object schema"
    end
    if type(contract.states) ~= "table" or next(contract.states) == nil then
      errors[#errors + 1] = contract.name .. ": no states"
    end
    if type(Registry.prompt(contract.name)) ~= "string" then
      errors[#errors + 1] = contract.name .. ": no prompt"
    end
    if opts.require_preflights and not contract.preflight then
      errors[#errors + 1] = contract.name .. ": no preflight"
    end
  end
  return #errors == 0, errors
end

return M
