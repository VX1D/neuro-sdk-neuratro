local M = {}

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
  return check, fails, function() return total end
end

function M.play_card(sort_id)
  return {
    sort_id = sort_id, cost = 0, sell_cost = 0,
    ability = { set = "Default", name = "Mock" }, config = { center = {} },
    base = { value = tostring(sort_id + 4), suit = "Hearts" },
    juice_up = function() end, highlight = function() end,
  }
end

function M.area(cards, limit)
  return { cards = cards or {}, config = { card_limit = limit or 5 } }
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

function M.force_phase(force_state)
  local window = force_state.window()
  return type(window) == "table" and window.phase or "none"
end

function M.selecting_hand_env(opts)
  opts = opts or {}
  G.TIMERS.REAL = opts.time or 100
  G.STATES = opts.states or { SELECTING_HAND = 4 }
  G.STATE = G.STATES.SELECTING_HAND
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
  G.hand = { cards = { M.play_card(1), M.play_card(2), M.play_card(3), M.play_card(4), M.play_card(5) },
    highlighted = {}, config = { card_limit = 5, highlighted_limit = 5 } }
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.deck = { cards = {} }
  G.FUNCS = {
    get_poker_hand_info = function(cards) return "Pair", {}, { Pair = { cards } }, cards end,
  }
  require("core.transition_guard").reset()
  require("core.enforce").reset_run_state()
  if opts.reset_tx_cache then require("core.tx_cache").reset() end
end

function M.receipt_selecting_hand_env(t)
  require("core.action_receipt").reset("test_env")
  G.TIMERS.REAL = t
  G.STATES = { SELECTING_HAND = 4 }
  G.STATE = 4
  G.GAME = {
    dollars = 10, chips = 0, used_vouchers = {},
    current_round = { hands_left = 3, discards_left = 2 },
    round_resets = { ante = 1 },
    hands = { Pair = { level = 1, chips = 20, mult = 2, visible = true } },
  }
  G.hand = { cards = { M.play_card(1), M.play_card(2), M.play_card(3) },
    highlighted = {}, config = { card_limit = 5, highlighted_limit = 5 } }
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.FUNCS = {
    get_poker_hand_info = function(cards) return "Pair", {}, { Pair = { cards } }, cards end,
  }
  require("core.transition_guard").reset()
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

return M
