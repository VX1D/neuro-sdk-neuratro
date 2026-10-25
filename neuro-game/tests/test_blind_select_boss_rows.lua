require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("blind-select-boss-rows")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local Model = require("facts.boss.model")

local PRE_BLIND_HANDS = 4

local function boss_row(key, name)
  LB.load("BLIND_SELECT", "Boss blind only (no skip, no reroll voucher)")
  G.GAME.current_round.hands_left = PRE_BLIND_HANDS
  G.P_BLINDS = G.P_BLINDS or {}
  _G.get_blind_amount = function() return 800 end
  G.P_BLINDS[key] = { name = name, dollars = 5, mult = 1, key = key, boss = { min = 2 }, debuff = {} }
  G.GAME.round_resets.blind_choices.Boss = key
  local p = FP.build("BLIND_SELECT") or {}
  local state = p.state or ""
  return state:match("\n%- (Boss blind " .. name:gsub("%p", "%%%0") .. "[^\n]*)") or "", state
end

local keys = {}
for key in pairs(Model.RECORDS) do keys[#keys + 1] = key end
table.sort(keys)

local missing, pace_bad = {}, {}
for _, key in ipairs(keys) do
  local rec = Model.RECORDS[key]
  local row = boss_row(key, rec.name)
  if row == "" then
    missing[#missing + 1] = key
  else
    local want = (key == "bl_needle") and 1 or PRE_BLIND_HANDS
    local per = 200 * PRE_BLIND_HANDS / want
    local pace = string.format("about %d per hand over %d hand%s", per, want, want == 1 and "" or "s")
    if not row:find(pace, 1, true) then pace_bad[#pace_bad + 1] = key .. ": " .. row:sub(1, 160) end
  end
end

check("every boss record renders a blind-select row (" .. #keys .. " records)", #missing == 0, table.concat(missing, ", "))
check("every row paces the target over the hands the boss leaves", #pace_bad == 0, table.concat(pace_bad, "\n"))

local function shop_primer(key, name)
  LB.load("SHOP", "Normal: affordable joker, affordable booster, $10")
  G.P_BLINDS = G.P_BLINDS or {}
  G.P_BLINDS[key] = { name = name, dollars = 5, mult = 1, key = key, boss = { min = 2 }, debuff = {} }
  G.GAME.round_resets.blind_choices = G.GAME.round_resets.blind_choices or {}
  G.GAME.round_resets.blind_choices.Boss = key
  G.GAME.round_resets.blind_states = { Small = "Defeated", Big = "Upcoming", Boss = "Upcoming" }
  local p = FP.build("SHOP") or {}
  local state = p.state or ""
  return state:match("## Upcoming boss\n%- ([^\n]*)") or "", state
end

local shop_missing = {}
for _, key in ipairs(keys) do
  local rec = Model.RECORDS[key]
  local primer = shop_primer(key, rec.name)
  if primer == "" then
    shop_missing[#shop_missing + 1] = key
  end
end
check("every boss record renders a shop primer (" .. #keys .. " records)", #shop_missing == 0,
  table.concat(shop_missing, ", "))

done()
