require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("prose-channel-moves")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local Helpers = require("tests.helpers")
local Gate = require("core.gate")
local TxCache = require("core.bridge").tx

local function has(text, needle) return tostring(text):find(needle, 1, true) ~= nil end

local function section(state, title)
  return tostring(state):match("## " .. title:gsub("%p", "%%%0") .. "[^\n]*\n(.-)\n## ") or
    tostring(state):match("## " .. title:gsub("%p", "%%%0") .. "[^\n]*\n(.*)$") or ""
end

local function send(name, data)
  local results = {}
  G.NEURO.send_action_result = function(_, _, ok, message) results[#results + 1] = { ok = ok, message = message } return true end
  G.NEURO.withdraw_actions = function() return true end
  local id = "prose-move-" .. tostring(os.clock())
  Helpers.stage_registered(nil, { name })
  TxCache.open(id, name, G.TIMERS.REAL)
  require("core.dispatcher").handle_message(Helpers.inbound_action(name, id, data), G.NEURO)
  pcall(require("core.execute").step, G.TIMERS.REAL)
  return results[1] or {}
end

local function pack(desc)
  LB.load("SMODS_BOOSTER_OPENED", desc)
  G.NEURO.gates = nil
  return FP.build("SMODS_BOOSTER_OPENED")
end

do
  local opened = {}
  for _, board in ipairs(require("tests.force_section_rows").ALL_BOARDS) do
    LB.load(board.state, board.desc)
    local frame = FP.build(board.state)
    if frame and frame.query:match("^%s") then opened[#opened + 1] = board.state .. "/" .. board.desc end
  end
  check("no live board's query starts with blank lines", #opened == 0, table.concat(opened, " | "))
end

do
  local frame = pack("Full joker slots during buffoon pack")
  check("withheld pick: choose_pack_card is not offered", not has(frame.query, "Use the choose_pack_card"), frame.query)
  check("withheld pick: no query starts with blank lines", frame.query:match("^%s") == nil, frame.query:sub(1, 40))
end

do
  local frame = pack("Celestial pack with planets")
  local rows = section(frame.state, "Cards in the pack")
  check("planet pack: the pointer's target exists -- every Planet row states its hand's played count",
    select(2, rows:gsub("%(Planet%)", "")) > 0
      and select(2, rows:gsub("%(Planet%)", "")) == select(2, rows:gsub("played [%w ]+ %d+x this run", "")), rows)
end

do
  LB.load("SHOP", "Normal: affordable joker, affordable booster, $10")
  FP.build("SHOP")
  G.NEURO.gates = nil
  G.NEURO.shop_entry_dollars, G.GAME.dollars = 14, 3
  local rejection = Gate.check("admission", "leave_shop", {})
  check("interest: the review fires", rejection ~= nil)
  Gate.delivered(rejection, rejection and rejection.message)
  local frame = {}
  frame.state, frame.query = Helpers.force_frame("SHOP")
  check("interest: the query states neither bank", not has(frame.query, "$3") and not has(frame.query, "$14"), frame.query)
  local shop = section(frame.state, "Shop (")
  check("interest: the Shop section states the bank", has(shop, "- $3 in bank."), shop)
  check("interest: the Shop section states what she entered with", has(shop, "- You entered this shop with $14."), shop)
  G.NEURO.shop_entry_dollars = 4
  check("interest: the entry line rides only while the review applies",
    not has((Helpers.force_frame("SHOP")), "You entered this shop with"))
end

do
  LB.load("SHOP", "Only vouchers affordable (no jokers/boosters)")
  FP.build("SHOP")
  G.NEURO.gates = nil
  G.GAME.dollars = 20
  local name = require("util.utils").real_name_or(G.shop_vouchers.cards[1])
  local result = send("buy_from_shop", { area = "shop_vouchers", index = 1, name = name,
    plan = { money_plan = "Buy the voucher now." } })
  check("voucher: the first buy is held for review", result.ok == true, tostring(result.message))
  local frame = {}
  frame.state, frame.query = Helpers.force_frame("SHOP")
  local row = Helpers.area_row(frame.state, "shop_vouchers", 1) or ""
  check("voucher: its row states the bank left after the buy", has(row, "buying it leaves $12"), row)
end

do
  LB.load("SHOP", "Normal: affordable joker, affordable booster, $10")
  local EC = require("tests.engine_cards")
  G.consumeables = Helpers.area({ EC.consumable("c_hermit", { sort_id = 901, cost = 3, sell_cost = 1 }),
    EC.consumable("c_hermit", { sort_id = 902, cost = 3, sell_cost = 1 }) }, 2)
  G.shop_jokers = Helpers.area({ EC.consumable("c_pluto", { sort_id = 903, cost = 3, sell_cost = 1 }) }, 2)
  G.GAME.dollars = 10
  local frame = FP.build("SHOP")
  check("full slots: no instruction in state", not has(frame.state, '"use"') and not has(frame.state, "buy with"), frame.state)
end

done()
