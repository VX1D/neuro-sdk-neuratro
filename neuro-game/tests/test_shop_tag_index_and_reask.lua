_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local check, done = require("tests.helpers").harness("shop-tag-index-and-reask")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local Enforce = require("core.enforce")

local function shop_move_line(untagged_index)
  LB.load("SHOP", "Normal: affordable joker, affordable booster, $10")
  local tags = {}
  for i, c in ipairs(G.jokers.cards) do
    if i ~= untagged_index then tags[c.sort_id] = { tag = "CORE" } end
  end
  G.NEURO.joker_intents = tags
  require("context.context_compact").invalidate_cache()
  local _, force = FP.build("SHOP")
  for line in ((force.query or "") .. "\n"):gmatch("([^\n]*)\n") do
    if line:find("set_joker_intents", 1, true) then return line end
  end
  return ""
end

local line4 = shop_move_line(4)
check("the shop names WHICH joker lacks a tag",
  line4:find("Jokers that carry no tag: 4", 1, true) ~= nil, line4)
check("and never states a bare count next to 'carry no tag'",
  line4:find("1 carry no tag", 1, true) == nil and line4:find("carry no tag,", 1, true) == nil, line4)
check("it still says why toggle_shop is off the list",
  line4:find("toggle_shop is off the list until every joker has one", 1, true) ~= nil, line4)

check("the shop line reuses core.enforce's prose verbatim",
  line4:find(tostring(Enforce.untagged_joker_prose()), 1, true) ~= nil,
  line4 .. " || " .. tostring(Enforce.untagged_joker_prose()))

do
  local line25 = shop_move_line(nil)
  check("a fully tagged roster drops the line entirely", line25 == "", line25)
end

do
  LB.load("SHOP", "Normal: affordable joker, affordable booster, $10")
  G.NEURO.joker_intents = {}
  local real = Enforce.untagged_joker_prose
  Enforce.untagged_joker_prose = function() error("boom") end
  require("context.context_compact").invalidate_cache()
  local _, force = FP.build("SHOP")
  Enforce.untagged_joker_prose = real
  local got = ""
  for line in ((force.query or "") .. "\n"):gmatch("([^\n]*)\n") do
    if line:find("set_joker_intents", 1, true) then got = line end
  end
  check("an unreadable prose still leaves the tagging move offered",
    got:find("records what a joker is for", 1, true) ~= nil
      and got:find("toggle_shop is off the list", 1, true) ~= nil, got)
end

local ForceHelpers = require("force.force_helpers")

do
  -- Exactly what the engine records for a state gate: core/enforce.lua:501 builds the message and
  -- build_correction_text hands the same instant to the correction channel.
  G.NEURO.last_failed_action = "toggle_shop"
  G.NEURO.last_failed_reason = "Action 'toggle_shop' is not available in state 'SHOP'."
    .. " Jokers that carry no tag: 4. set_joker_intents tags them; toggle_shop returns to the list"
    .. " once every joker has one."
  G.NEURO.last_failed_correction = "Jokers that carry no tag: 4. set_joker_intents tags them;"
    .. " toggle_shop returns to the list once every joker has one."
  local w = ForceHelpers.failed_action_warning()
  check("the re-ask carries the correction", w:find("Jokers that carry no tag: 4", 1, true) ~= nil, w)
  check("the re-ask states the cause exactly once",
    select(2, w:gsub("Jokers that carry no tag", "")) == 1, w)
  check("the re-ask does not also quote the engine verdict",
    w:find("is not available in state", 1, true) == nil, w)
  check("the tag gate re-ask fits its measured budget", #w == 163, #w .. ": " .. w)
end

do
  G.NEURO.last_failed_action = "play_hand"
  G.NEURO.last_failed_reason = "Action 'play_hand' is not available in state 'SHOP'."
  G.NEURO.last_failed_correction = "Your last action wasn't applied: play_hand isn't available"
    .. " in the current state (SHOP)."
  local w = ForceHelpers.failed_action_warning()
  check("play_hand in SHOP fits its measured budget", #w == 133, #w .. ": " .. w)
end

do
  G.NEURO.last_failed_action = "play_hand"
  G.NEURO.last_failed_reason = "Action 'play_hand' is not available in state 'SHOP'."
  G.NEURO.last_failed_correction = nil
  local w = ForceHelpers.failed_action_warning()
  check("with no correction the raw reason is still printed",
    w:find("is not available in state 'SHOP'", 1, true) ~= nil, w)
  G.NEURO.last_failed_correction = ""
  check("an empty correction is treated the same as none",
    ForceHelpers.failed_action_warning() == w, ForceHelpers.failed_action_warning())
end

done()
