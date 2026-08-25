_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("block-play-force")

local Actions = require("core.actions")
local Force = require("force.force_selecting_hand")
local Dispatcher = require("core.dispatcher")

local VALN = require("tests.helpers").VALN
local RANKS = { "A", "K", "Q", "J", "9", "8", "7", "6" }
local SUITS = { "Spades", "Hearts", "Clubs", "Diamonds" }

local _sort_id = 0
local function card(v, suit)
  _sort_id = _sort_id + 1
  return {
    base = { value = VALN[v] or v, suit = suit },
    sort_id = _sort_id,
    config = { center = { key = "c_base", set = "Default" } },
    is_suit = function(_, s) return s == suit end,
  }
end

local function setup(opts)
  _sort_id = 0
  local cards = {}
  for i = 1, (opts.hand or 5) do cards[i] = card(RANKS[i], SUITS[((i - 1) % 4) + 1]) end
  local blind = {
    key = opts.boss, name = opts.boss and "The Wall" or "Small Blind",
    boss = opts.boss ~= nil, debuff = opts.debuff or {},
    block_play = opts.block_play or nil,
    hands = {}, only_hand = false,
  }
  _G.G = {
    hand = { cards = cards, config = { highlighted_limit = opts.highlighted_limit or 5 }, highlighted = {} },
    GAME = {
      blind = blind,
      round = 1,
      chips = 0,
      hands = {},
      probabilities = { normal = 1 },
      starting_params = opts.starting_params or {},
      current_round = {
        hands_left = opts.hands_left or 3,
        discards_left = opts.discards_left or 2,
        discards_used = 0,
        most_played_poker_hand = "High Card",
      },
    },
    FUNCS = { get_poker_hand_info = function(cs) return "High Card", {}, {}, { cs[1] } end },
    NEURO = {},
    jokers = { cards = {} },
    consumeables = { cards = {} },
    playing_cards = cards,
    deck = { cards = {} },
    play = nil,
  }
  return cards
end

local function offered_set(force)
  local set = {}
  for _, name in ipairs(force and force.actions or {}) do set[name] = true end
  return set
end

do
  setup({ hand = 5, hands_left = 3, discards_left = 2, block_play = false })
  local force = Force.build()
  check("force builds when the banner is not blocking", type(force) == "table")
  local offered = offered_set(force)
  check("play_hand is offered with the banner clear", offered["play_hand"] == true)
  check("discard_hand is offered with the banner clear", offered["discard_hand"] == true)
end

do
  setup({ hand = 5, hands_left = 3, discards_left = 2, block_play = true })
  check("Actions already withdraws play_hand while the banner blocks it",
    Actions.is_action_valid("play_hand") == false)
  local force = Force.build()
  check("the force still builds -- discard_hand remains a legal move", type(force) == "table")
  local offered = offered_set(force)
  check("play_hand is NOT offered while the banner is still animating",
    offered["play_hand"] ~= true, "offered: " .. table.concat((function() local t={} for k in pairs(offered) do t[#t+1]=k end return t end)(), ","))
  check("discard_hand stays offered -- the banner lock only blocks playing",
    offered["discard_hand"] == true)
  check("the query never invites a play_hand send while blocked",
    force.query:find('"play_hand"', 1, true) == nil
      and force.query:find("play_hand|", 1, true) == nil, force.query)
end

do
  setup({ hand = 5, hands_left = 3, discards_left = 0, block_play = true })
  check("the router asks nothing when nothing is legal (banner blocks play, no discards left)",
    Dispatcher.get_force_for_state("SELECTING_HAND") == nil)
  local force = Force.build()
  check("C1b the builder offers neither hand action and leaves the verdict to the router",
    type(force) == "table" and #force.actions == 0,
    force and table.concat(force.actions, ",") or "nil")

  setup({ hand = 5, hands_left = 3, discards_left = 0, block_play = false })
  local force2 = Force.build()
  check("the force resumes the instant the banner clears, no other state changed",
    type(force2) == "table")
  local offered2 = offered_set(force2)
  check("play_hand is offered again once the banner clears",
    offered2["play_hand"] == true)
  check("discard_hand is correctly absent -- discards_left is genuinely 0, unrelated to the banner",
    offered2["discard_hand"] ~= true)
end

do
  setup({ hand = 5, hands_left = 0, discards_left = 1, block_play = true })
  local force = Force.build()
  check("the force still builds on the discard-only path", type(force) == "table")
  local offered = offered_set(force)
  check("play_hand is absent (no hands left, independent of the banner)",
    offered["play_hand"] ~= true)
  check("discard_hand is offered", offered["discard_hand"] == true)
end

do
  setup({ hand = 0, hands_left = 3, discards_left = 2, block_play = false })
  check("Actions withdraws play_hand on an undealt hand",
    Actions.is_action_valid("play_hand") == false)
  check("Actions withdraws discard_hand on an undealt hand",
    Actions.is_action_valid("discard_hand") == false)
  local force = Force.build()
  check("the builder still builds while the hand is undealt", type(force) == "table")
  local offered = offered_set(force)
  check("neither hand action is offered on an undealt hand",
    offered["play_hand"] ~= true and offered["discard_hand"] ~= true)
end

do
  local CASES = {
    { label = "dealt, hands and discards left", hand = 5, hands_left = 3, discards_left = 2 },
    { label = "dealt, no discards", hand = 5, hands_left = 3, discards_left = 0 },
    { label = "dealt, no hands", hand = 5, hands_left = 0, discards_left = 2 },
    { label = "dealt, banner blocking play", hand = 5, hands_left = 3, discards_left = 2, block_play = true },
    { label = "undealt, hands and discards left", hand = 0, hands_left = 3, discards_left = 2 },
    { label = "undealt, no resources left", hand = 0, hands_left = 0, discards_left = 0 },
  }
  local seen = { play_true = false, play_false = false, disc_true = false, disc_false = false,
    asked = false, silent = false }
  local agree = true
  local built = true
  local routed = true
  local detail = ""
  for _, c in ipairs(CASES) do
    setup(c)
    local vp = Actions.is_action_valid("play_hand") == true
    local vd = Actions.is_action_valid("discard_hand") == true
    seen[vp and "play_true" or "play_false"] = true
    seen[vd and "disc_true" or "disc_false"] = true
    local force = Force.build()
    if type(force) ~= "table" then
      built = false
      detail = detail .. string.format(" [%s: builder returned nil]", c.label)
    end
    local asked = Dispatcher.get_force_for_state("SELECTING_HAND") ~= nil
    seen[asked and "asked" or "silent"] = true
    local may_defer = c.block_play == true
    if asked ~= (vp or vd) and not (may_defer and not asked) then
      routed = false
      detail = detail .. string.format(" [%s: asked=%s valid_play=%s valid_discard=%s]",
        c.label, tostring(asked), tostring(vp), tostring(vd))
    end
    if force then
      local offered = offered_set(force)
      if (offered["play_hand"] == true) ~= vp or (offered["discard_hand"] == true) ~= vd then
        agree = false
        detail = detail .. string.format(" [%s: offered_play=%s valid_play=%s offered_discard=%s valid_discard=%s]",
          c.label, tostring(offered["play_hand"] == true), tostring(vp),
          tostring(offered["discard_hand"] == true), tostring(vd))
      end
    end
  end
  check("the sweep is not vacuous -- it covers valid and invalid for both names, asked and silent",
    seen.play_true and seen.play_false and seen.disc_true and seen.disc_false
      and seen.asked and seen.silent)
  check("the builder builds in every case -- it never decides that the state asks nothing",
    built, detail)
  check("F1b the router asks exactly when this board (no jokers, no consumables) has a legal move",
    routed, detail)
  check("the force offers play_hand/discard_hand exactly when Actions accepts them", agree, detail)
end

do
  local Utils = require("util.utils")
  setup({ hand = 5, hands_left = 3, discards_left = 2, block_play = true })
  G.TIMERS = { TOTAL = 0, REAL = 0 }
  local first = Dispatcher.get_force_for_state("SELECTING_HAND")
  check("F1c the router holds the force back while the boss banner lock is fresh", first == nil,
    tostring(first))

  local failsafe = Utils.gate_seconds("router_guard_defer", "NEURO_ROUTER_DEFER_FAILSAFE") or 8.0
  G.TIMERS.TOTAL = failsafe * 2 + 1
  local later = Dispatcher.get_force_for_state("SELECTING_HAND")
  check("F1c2 and gives up waiting once the failsafe elapses, so the lock cannot hang the run",
    type(later) == "table", tostring(later))
  if type(later) == "table" then
    local offered = offered_set(later)
    check("F1c3 the force it finally sends is the discard-only one the board actually allows",
      offered["discard_hand"] == true and offered["play_hand"] ~= true,
      table.concat(later.actions or {}, ","))
  end
end

done()
