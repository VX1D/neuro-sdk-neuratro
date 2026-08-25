_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("boss-ceiling")
local H = require("tests.helpers")
local Actions = require("core.actions")

_G.get_blind_amount = function() return 800 end

local BASE_LEVELS = {
  ["High Card"] = { chips = 5, mult = 1 },
  ["Pair"] = { chips = 10, mult = 2 },
  ["Two Pair"] = { chips = 20, mult = 2 },
  ["Three of a Kind"] = { chips = 30, mult = 3 },
  ["Straight"] = { chips = 30, mult = 4 },
  ["Flush"] = { chips = 35, mult = 4 },
  ["Full House"] = { chips = 40, mult = 4 },
  ["Four of a Kind"] = { chips = 60, mult = 7 },
  ["Straight Flush"] = { chips = 100, mult = 8 },
}

local function hands_table(overrides)
  local t = {}
  for name, v in pairs(BASE_LEVELS) do
    t[name] = { visible = true, level = 1, chips = v.chips, mult = v.mult, played = 0 }
  end
  for name, v in pairs(overrides or {}) do
    if v == false then
      t[name].visible = false
    else
      t[name] = { visible = true, level = v.level or 1, chips = v.chips, mult = v.mult, played = 0 }
    end
  end
  return t
end

local P_BLINDS = {
  bl_small = { name = "Small Blind", mult = 1 },
  bl_big = { name = "Big Blind", mult = 1.5 },
  bl_boss = { name = "The Club", mult = 2 },
  bl_needle = { name = "The Needle", mult = 1 },
  bl_eye = { name = "The Eye", mult = 2 },
  bl_flint = { name = "The Flint", mult = 2 },
}

local function guaranteed_joker(key, ability)
  return { ability = ability, config = { center = { key = key, set = "Joker" } }, sell_cost = 3 }
end
local DEFAULT_JOKERS = {
  guaranteed_joker("j_joker", { mult = 3, set = "Joker" }),
  guaranteed_joker("j_square", { extra = { chips = 6 }, set = "Joker" }),
}

local DEFAULT_DECK = {}
for _ = 1, 52 do DEFAULT_DECK[#DEFAULT_DECK + 1] = { base = { value = "8" } } end

local function query(boss_key, opts)
  opts = opts or {}
  local on_deck = opts.on_deck or "Boss"
  local deck = opts.deck or DEFAULT_DECK
  _G.G = {
    STATE = 2, STATES = { BLIND_SELECT = 2 }, P_BLINDS = P_BLINDS, playing_cards = deck,
    GAME = {
      win_ante = 8, dollars = 20, blind_on_deck = on_deck,
      hands = opts.hands_table or hands_table(opts.levels),
      round_resets = {
        ante = 1, blind_ante = 1, hands = opts.hands or 4,
        blind_states = {
          Small = on_deck == "Small" and "Select" or "Defeated",
          Big = on_deck == "Big" and "Select" or (on_deck == "Small" and "Upcoming" or "Defeated"),
          Boss = on_deck == "Boss" and "Select" or "Upcoming",
        },
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = boss_key },
      },
    },
    NEURO = { once_serials = {} },
    jokers = { cards = opts.no_jokers and {} or DEFAULT_JOKERS }, consumeables = { cards = {} },
  }
  Actions.is_action_valid = function(n) return n == "select_blind" end
  local FBS = require("force.force_blind_select")
  local ok, built = pcall(FBS.build)
  H.drain_hints()
  return ok and ((built or {}).query or "") or tostring(built)
end

local function has_projection(text)
  text = text or ""
  return text:find("comes to about", 1, true) ~= nil
    or text:find("This boss needs", 1, true) ~= nil
    or text:find("It needs", 1, true) ~= nil
end

for _, key in ipairs({ "bl_boss", "bl_flint", "bl_needle", "bl_eye" }) do
  local q = query(key)
  check("no per-hand reach projection on the blind screen (" .. key .. ")",
    not has_projection(q), q:match("[^.]*comes to about[^.]*")
      or q:match("[^.]*needs[^.]*") or "")
end

for _, key in ipairs({ "bl_flint", "bl_wall", "bl_final_vessel" }) do
  local ok, status = pcall(function()
    return require("facts.boss.render").render("status", key, { blind = { key = key } })
  end)
  check("no reach projection in the boss status line (" .. key .. ")",
    ok and not has_projection(status), tostring(status))
end

do
  local q = query("bl_flint")
  check("the boss rule itself still reaches the blind screen",
    q:find("The Flint", 1, true) ~= nil or q:find("halved", 1, true) ~= nil, q)
end

done()
