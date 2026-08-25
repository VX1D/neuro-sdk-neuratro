rawset(_G, "NEURO_TEST", true)
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = {}

local check, done = require("tests.helpers").harness("joker-hidden-subtotal")

local LB = require("tests.fixtures.live_board")
local CtxJokers = require("context.ctx_jokers")
local Compact = require("context.context_compact")

local QUALIFIER = "Joker bonuses from the jokers you can see"
local PLAIN = "Joker bonuses (current values"

local EXTRA_TEXT = { j_joker = "+4 Mult" }

local function section(keys, hidden, state)
  LB.load("SELECTING_HAND", "Normal: 5 cards, 4 hands, 3 discards")
  local roster = {}
  for i, key in ipairs(keys) do
    roster[i] = LB.joker(key, 800 + i)
    if not LB.TEXT[key] then
      roster[i].config.center.loc_txt =
        { name = roster[i].config.center.name, description = { EXTRA_TEXT[key] or "+0 Mult" } }
    end
    roster[i].area = G.jokers
    if hidden and hidden[i] then roster[i].facing = "back" end
  end
  G.jokers = { cards = roster, config = { card_limit = 5 } }
  Compact.invalidate_cache()
  return tostring(CtxJokers.jokers_section(state or "SELECTING_HAND"))
end

local function agg_line(text)
  return text:match("Joker bonuses[^\n]*") or "<no Joker bonuses line>"
end

local MIXED = { "j_hologram", "j_baron", "j_scary_face" }

local all_up = section(MIXED, nil)
local partial = section(MIXED, { [2] = true })

check("control: a face-up roster renders the bonuses line", all_up:find(PLAIN, 1, true) ~= nil,
  agg_line(all_up))
check("control: the face-up line is unqualified -- nothing is being withheld from it",
  all_up:find(QUALIFIER, 1, true) == nil, agg_line(all_up))

check("one face-down joker no longer deletes the whole line",
  partial:find("Joker bonuses", 1, true) ~= nil, partial)
check("the face-up jokers keep their own numbers (Hologram x1.5)",
  agg_line(partial):find("x1.5 Mult", 1, true) ~= nil, agg_line(partial))
check("the face-up jokers keep their ceiling source (Scary Face +150 Chips)",
  agg_line(partial):find("Scary Face +150 Chips", 1, true) ~= nil, agg_line(partial))
check("the hidden joker contributes nothing to the figures",
  agg_line(partial):find("Baron", 1, true) == nil, agg_line(partial))

check("the partial figures really are a subtotal, not the roster's total",
  agg_line(partial) ~= agg_line(all_up),
  agg_line(partial) .. "  ==  " .. agg_line(all_up))
check("the partial line says whose bonuses it is stating",
  partial:find(QUALIFIER, 1, true) ~= nil, agg_line(partial))

local ACORN = { "j_hologram", "j_baron", "j_scary_face", "j_fibonacci", "j_odd_todd" }
local ALL_DOWN = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true }

local acorn = section(ACORN, ALL_DOWN)
check("a fully hidden roster still carries the aggregate",
  acorn:find("Joker bonuses", 1, true) ~= nil, acorn)
check("a fully hidden roster still states the hidden rows' contribution (Baron)",
  agg_line(acorn):find("Baron", 1, true) ~= nil, agg_line(acorn))
check("a fully hidden roster is NOT qualified -- nothing is left out of its figures",
  acorn:find(QUALIFIER, 1, true) == nil, agg_line(acorn))
check("every row is still rendered as face-down (hidden)",
  select(2, acorn:gsub("face%-down %(hidden%)", "")) == 5, acorn)

do
  local a = section({ "j_hologram", "j_baron", "j_scary_face" }, { [2] = true })
  local b = section({ "j_hologram", "j_cavendish", "j_scary_face" }, { [2] = true })
  check("hidden Baron and hidden Cavendish render the same section byte for byte", a == b,
    "[" .. agg_line(a) .. "] vs [" .. agg_line(b) .. "]")

  local c = section({ "j_hologram", "j_banner", "j_scary_face" }, { [2] = true })
  check("a hidden Banner is indistinguishable from a hidden Baron too", a == c,
    "[" .. agg_line(a) .. "] vs [" .. agg_line(c) .. "]")
end

do
  local forms, order, out = {}, {}, ACORN
  local function permute(k)
    if k > #out then
      local text = section(out, ALL_DOWN)
      if not forms[text] then forms[text] = true; order[#order + 1] = text end
      return
    end
    for i = k, #out do
      out[k], out[i] = out[i], out[k]
      permute(k + 1)
      out[k], out[i] = out[i], out[k]
    end
  end
  permute(1)
  check("Amber Acorn: 120 hidden orders of one multiset render one section", #order == 1,
    #order .. " distinct forms, e.g. [" .. agg_line(order[1]) .. "] vs ["
      .. agg_line(order[math.min(2, #order)]) .. "]")
end

do
  local with_mime = section({ "j_mime", "j_baron", "j_scary_face" }, nil)
  check("a retriggered ceiling says the passes are already in the figures",
    with_mime:find("retrigger passes included", 1, true) ~= nil, agg_line(with_mime))
  check("the retriggered ceiling really is larger than the un-retriggered one",
    agg_line(with_mime):find("x5.06 Mult", 1, true) ~= nil, agg_line(with_mime))

  local no_retrigger = section({ "j_hologram", "j_baron", "j_scary_face" }, nil)
  check("a board with no retrigger joker makes no such promise",
    no_retrigger:find("retrigger", 1, true) == nil, agg_line(no_retrigger))
  check("control: that board still names its ceiling scopes",
    no_retrigger:find("already count what pays per scoring card", 1, true) ~= nil,
    agg_line(no_retrigger))
end

do
  local ORDER_SET = { "j_cavendish", "j_joker" }
  local visible = section(ORDER_SET, nil)
  check("control: a face-up roster still reports the joker-order gap",
    visible:find("Joker order:", 1, true) ~= nil, visible)
  for _, slot in ipairs({ 1, 2 }) do
    local one_down = section(ORDER_SET, { [slot] = true })
    check("a face-down joker in slot " .. slot .. " withholds the order gap",
      one_down:find("Joker order:", 1, true) == nil, one_down)
  end
end

done()
