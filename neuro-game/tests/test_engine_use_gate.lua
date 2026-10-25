require("tests.stubs").setup({ love = "zero" })
_G.G = { P_CENTERS = require("tests.engine_centers").centers(), NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 1, TOTAL = 1 } }

local Engine = require("tests.real_engine")
Engine.load("engine-use-gate", 24)

local check, done = require("tests.helpers").harness("engine-use-gate")
local Receipt = require("core.action_result")
local UseCard = require("handlers.use_card")
local Shop = require("handlers.shop_handlers")
local CardUtil = require("facts.card_util")

local calls

local function joker(area)
  return { ability = { set = "Joker", name = "Joker" }, config = { center = { key = "j_joker", set = "Joker" } },
    area = area }
end

local function board(state, jokers, joker_limit)
  calls = {}
  local hand = Engine.area("hand", 5)
  _G.G = {
    P_CENTERS = require("tests.engine_centers").centers(),
    STATE = Engine.STATES[state], STATES = Engine.STATES,
    NEURO = { ai_highlighted = setmetatable({}, { __mode = "k" }), run_generation = 1, state = state,
      reserved_dollars = 0 },
    TIMERS = { REAL = 1, TOTAL = 1 }, CONTROLLER = { locks = {} },
    GAME = { dollars = 20, bankrupt_at = 0, current_round = { hands_left = 3, discards_left = 2 },
      round_scores = { times_rerolled = { amt = 0 } }, used_vouchers = {}, probabilities = { normal = 1 } },
    hand = hand, play = { cards = {} },
    jokers = Engine.area("joker", 1, joker_limit or 2),
    consumeables = Engine.area("consumeable", 1, 2),
    shop_jokers = Engine.area("shop", 1, 2), shop_vouchers = Engine.area("shop", 1, 1),
    shop_booster = Engine.area("shop", 1, 2),
    FUNCS = {
      use_card = function(e)
        local c = e.config.ref_table
        if c:check_use() then calls[#calls + 1] = "ABORTED:" .. c.ability.name return end
        calls[#calls + 1] = "use:" .. c.ability.name
      end,
      buy_from_shop = function(e) calls[#calls + 1] = "buy:" .. e.config.ref_table.ability.name end,
    },
  }
  _G.alert_no_space = function() calls[#calls + 1] = "ALERT" end
  if state == "SHOP" then G.shop = {} end
  for i = 1, jokers or 0 do G.jokers.cards[i] = joker(G.jokers) end
  if state ~= "SHOP" then
    for i = 1, 3 do hand.cards[i] = Engine.playing_card(i, hand) end
  end
  return hand
end

local function ankh(area) return Engine.consumable(70, "Ankh", "c_ankh", "Spectral", { extra = 2 }, area) end
local function err_text(err) return type(err) == "table" and tostring(err.message) or tostring(err) end

do
  board("SELECTING_HAND", 2, 2)
  G.consumeables.cards = { ankh(G.consumeables) }
  local exec, err = UseCard.handle_use_card({ area = "consumables", index = 1, name = "Ankh", _action_id = "a1" })
  check("owned Ankh with full joker slots is refused before the engine aborts it",
    exec == nil and type(err) == "table" and err.reason_code == "PRECONDITION_FAILED", err_text(err))
  check("the gate probe raises no no-space alert and reaches no engine call", #calls == 0,
    table.concat(calls, " "))

  board("SELECTING_HAND", 1, 2)
  G.consumeables.cards = { ankh(G.consumeables) }
  exec = UseCard.handle_use_card({ area = "consumables", index = 1, name = "Ankh", _action_id = "a2" })
  if type(exec) == "function" then exec() end
  check("Ankh with a free joker slot reaches use_card and is used", calls[1] == "use:Ankh",
    table.concat(calls, " "))
end

do
  board("SHOP", 2, 2)
  G.shop_jokers.cards = { ankh(G.shop_jokers) }
  local exec, err = Shop.handle_buy_from_shop({ area = "shop_jokers", index = 1, name = "Ankh", use = true,
    _action_id = "b1" })
  check("Ghost-deck buy-and-use of Ankh with full joker slots is refused, nothing charged",
    exec == nil and type(err) == "table" and err.reason_code == "PRECONDITION_FAILED" and #calls == 0,
    err_text(err) .. " | " .. table.concat(calls, " "))
end

do
  board("SMODS_BOOSTER_OPENED", 2, 2)
  G.pack_cards = Engine.area("shop", 1, 3)
  local card = ankh(G.pack_cards)
  G.pack_cards.cards = { card }
  check("a Spectral-pack Ankh is not takeable while joker slots are full",
    CardUtil.can_take_pack_card(card) == false)
  G.jokers.cards[2] = nil
  check("the same Ankh is takeable once a joker slot is free", CardUtil.can_take_pack_card(card) == true)
end

do
  local hand = board("SMODS_BOOSTER_OPENED")
  hand.cards[2], hand.cards[3] = nil, nil
  local death = Engine.consumable(71, "Death", "c_death", "Tarot",
    { max_highlighted = 2, min_highlighted = 2, mod_num = 2 }, nil)
  check("Death is not takeable from a pack when the hand holds one card",
    CardUtil.can_take_pack_card(death) == false)
  hand.cards[2] = Engine.playing_card(2, hand)
  check("Death is takeable once two hand cards can be its targets", CardUtil.can_take_pack_card(death) == true)

  hand = board("SMODS_BOOSTER_OPENED")
  for i = 1, 3 do hand.cards[i].edition = { foil = true } end
  local aura = Engine.consumable(72, "Aura", "c_aura", "Spectral", {}, nil)
  check("Aura is not takeable when every hand card already has an edition",
    CardUtil.can_take_pack_card(aura) == false)
  hand.cards[2].edition = nil
  check("Aura is takeable once an editionless hand card exists", CardUtil.can_take_pack_card(aura) == true)
end

do
  board("SELECTING_HAND", 1, 5)
  G.jokers.cards[1].edition = { foil = true }
  local wheel = Engine.consumable(75, "The Wheel of Fortune", "c_wheel_of_fortune", "Tarot", { extra = 4 },
    G.consumeables)
  wheel.eligible_strength_jokers = {}
  G.consumeables.cards = { wheel }
  local note = require("facts.use_gate").blocked_note()
  check("the force note names the blocked card", note:find("The Wheel of Fortune", 1, true) ~= nil, note)
  local Actions = require("core.actions")
  local real_valid = Actions.is_action_valid
  Actions.is_action_valid = function(n, ...) return n == "use_consumable" or real_valid(n, ...) end
  local force = require("force.force_selecting_hand").build() or {}
  local state = require("tests.helpers").force_frame("SELECTING_HAND", force)
  Actions.is_action_valid = real_valid
  check("the note is a board fact: the frame's Constraints section carries it and the query does not",
    (state:match("\n## Constraints\n(.-)\n## ") or ""):find(note:gsub("%s+$", ""), 1, true) ~= nil
      and not (force.query or ""):find("marked not usable", 1, true), state .. "\n--\n" .. tostring(force.query))
end

do
  board("SELECTING_HAND", 1, 5)
  local hermit = Engine.consumable(76, "The Hermit", "c_hermit", "Tarot", { extra = 20 }, G.consumeables)
  G.consumeables.cards = { hermit }
  local exec = UseCard.handle_use_card({ area = "consumables", index = 1, name = "The Hermit", _action_id = "h1" })
  G.CONTROLLER.locked = true
  local result = type(exec) == "function" and exec() or nil
  check("an accepted use does not bypass a locked engine at execution",
    #calls == 0 and Receipt.is_outcome(result),
    table.concat(calls, " ") .. " | " .. tostring(result and (result.message or result.reason)))
end

done()
