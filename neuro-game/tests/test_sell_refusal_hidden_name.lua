require("tests.stubs").setup({ love = "lazy" })
_G.G = require("tests.helpers").base_G()
local check, done = require("tests.helpers").harness("sell refusal hidden name")
local IH = require("tests.inbound_harness")
local V = require("tests.fixtures.vanilla_jokers")

local h = IH.new({ registered = { "play_hand", "discard_hand", "sell_card", "help" } })
h.fresh()

local function board(eternal)
  local hidden_lu, baron = V.card_played("j_luchador", 501), V.card_played("j_baron", 502)
  hidden_lu.sell_cost, baron.sell_cost = 5, 4
  if eternal then hidden_lu.ability.eternal = true end
  hidden_lu.facing, baron.facing = "back", "back"
  local lu = V.card_played("j_luchador", 503); lu.facing = "front"
  G.jokers = { cards = { hidden_lu, baron, lu }, config = { card_limit = 5 } }
  hidden_lu.area, baron.area, lu.area = G.jokers, G.jokers, G.jokers
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.NEURO.is_transition_cooldown = function() return false end
  G.GAME.blind = { name = "Amber Acorn", boss = true, debuff = {}, disabled = false, get_type = function() return "Boss" end }
end

local function results()
  local out = {}
  for _, msg in ipairs(require("tests.helpers").outbox_frames(h.outbox, { command = "action/result" })) do
    if msg.data then out[msg.data.id] = msg.data end
  end
  return out
end

board(false)
h.feed({ h.action_line("s1", "sell_card", { area = "jokers", index = 1 }) })
h.bridge:poll_inbox(); h.frames(40)
board(true)
h.feed({ h.action_line("s2", "sell_card", { area = "jokers", index = 1 }) })
h.bridge:poll_inbox(); h.frames(40)

local got = results()
for _, id in ipairs({ "s1", "s2" }) do
  local r = got[id]
  local msg = r and tostring(r.message) or ""
  check(id .. ": the face-down sale is refused", r ~= nil and r.success == false, msg)
  check(id .. ": the face-down Luchador is not named as the card to sell",
    msg:find("Sell Luchador", 1, true) == nil, msg)
end

do
  board(false)
  G.jokers.cards[3] = nil
  local _, err = require("core.dispatcher").preflight("sell_card", { area = "jokers", index = 1 })
  local msg = type(err) == "table" and tostring(err.message) or tostring(err)
  check("the guard refusal for a lone face-down Luchador never contains its name",
    msg:find("Luchador", 1, true) == nil, msg)
end

done()
