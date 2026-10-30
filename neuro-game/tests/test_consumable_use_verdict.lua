require("tests.stubs").setup({ love = "zero" })
_G.G = { P_CENTERS = require("tests.engine_centers").centers(), NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 1, TOTAL = 1 } }

local Engine = require("tests.real_engine")
Engine.load("consumable-use-verdict", 17)

local check, done = require("tests.helpers").harness("consumable-use-verdict")
local Receipt = require("core.action_result")
local UseCard = require("handlers.use_card")
local Shop = require("handlers.shop_handlers")

local used

local function board(state)
  used = {}
  local hand = Engine.area("hand", 5)
  _G.G = {
    P_CENTERS = require("tests.engine_centers").centers(),
    STATE = Engine.STATES[state or "SELECTING_HAND"], STATES = Engine.STATES,
    NEURO = { ai_highlighted = setmetatable({}, { __mode = "k" }), run_generation = 1,
      state = state or "SELECTING_HAND", reserved_dollars = 0 },
    TIMERS = { REAL = 1, TOTAL = 1 }, CONTROLLER = { locks = {} },
    GAME = { dollars = 20, bankrupt_at = 0, current_round = { hands_left = 3, discards_left = 2 },
      round_scores = { times_rerolled = { amt = 0 } }, used_vouchers = {} },
    hand = hand, play = { cards = {} },
    jokers = Engine.area("joker", 1, 5),
    consumeables = Engine.area("consumeable", 1, 2),
    shop_jokers = Engine.area("shop", 1, 2), shop_vouchers = Engine.area("shop", 1, 1),
    shop_booster = Engine.area("shop", 1, 2),
    FUNCS = {
      use_card = function(e)
        used[#used + 1] = e.config.ref_table.ability.name .. "[" .. Engine.ids(G.hand.highlighted) .. "]"
      end,
      buy_from_shop = function(e) used[#used + 1] = "buy:" .. e.config.ref_table.ability.name end,
    },
  }
  if state == "SHOP" then G.shop = {} end
  hand.cards[1] = Engine.playing_card(1, hand)
  hand.cards[2] = Engine.playing_card(2, hand, { polychrome = true })
  hand.cards[3] = Engine.playing_card(3, hand)
  return hand
end

local function wheel(area, eligible)
  local card = Engine.consumable(60, "The Wheel of Fortune", "c_wheel_of_fortune", "Tarot", { extra = 4 }, area)
  card.eligible_strength_jokers = eligible or {}
  return card
end

local function use(payload)
  payload._action_id = payload._action_id or ("use-" .. tostring(payload.name))
  local exec, err = UseCard.handle_use_card(require("tests.helpers").with_card_names("use_consumable", payload))
  if type(exec) == "function" then exec() end
  return exec, err
end

do
  board()
  G.consumeables.cards = { wheel(G.consumeables) }
  local exec, err = use({ area = "consumables", index = 1, name = "The Wheel of Fortune", hand_indices = { 1 } })
  check("Wheel of Fortune with no eligible joker is refused even when hand_indices are sent",
    exec == nil and type(err) == "table" and err.reason_code == "PRECONDITION_FAILED",
    type(err) == "table" and err.message or tostring(exec))
  check("the refused Wheel never reaches the engine", #used == 0, table.concat(used, " "))

  board()
  G.consumeables.cards = { wheel(G.consumeables, { {} }) }
  exec = use({ area = "consumables", index = 1, name = "The Wheel of Fortune" })
  check("Wheel of Fortune with an eligible joker is used", type(exec) == "function" and #used == 1,
    table.concat(used, " "))
end

local function aura()
  return Engine.consumable(61, "Aura", "c_aura", "Spectral", {}, G.consumeables)
end

do
  local hand = board()
  G.consumeables.cards = { aura() }
  local before = hand.highlighted
  local exec, err = use({ area = "consumables", index = 1, name = "Aura", hand_indices = { 2 } })
  check("Aura on a card that already has an edition is refused",
    exec == nil and type(err) == "table" and err.reason_code == "PRECONDITION_FAILED",
    type(err) == "table" and err.message or tostring(exec))
  check("the refused Aura never reaches the engine", #used == 0, table.concat(used, " "))
  check("judging the targets does not disturb the live selection",
    hand.highlighted == before and #hand.highlighted == 0 and hand.cards[2].highlighted ~= true)

  board()
  G.consumeables.cards = { aura() }
  exec = use({ area = "consumables", index = 1, name = "Aura", hand_indices = { 1 } })
  check("Aura on a plain card is used with exactly that card selected",
    type(exec) == "function" and used[1] == "Aura[1]", table.concat(used, " "))
end

local function buy(payload)
  payload._action_id = payload._action_id or "buy"
  return Shop.handle_buy_from_shop(payload)
end

do
  board("SHOP")
  G.shop_jokers.cards = { wheel(G.shop_jokers) }
  local exec, err = buy({ area = "shop_jokers", index = 1, name = "The Wheel of Fortune", use = true })
  check("buy-and-use of an unusable Wheel of Fortune is refused",
    exec == nil and type(err) == "table" and err.reason_code == "PRECONDITION_FAILED",
    type(err) == "table" and err.message or tostring(exec))

  board("SHOP")
  G.shop_jokers.cards = { wheel(G.shop_jokers, { {} }) }
  exec, err = buy({ area = "shop_jokers", index = 1, name = "The Wheel of Fortune", use = true })
  check("buy-and-use of a usable Wheel of Fortune is accepted", type(exec) == "function",
    type(err) == "table" and err.message or tostring(err))

  board("SHOP")
  G.consumeables.cards = { wheel(G.consumeables, { {} }), wheel(G.consumeables, { {} }) }
  G.shop_jokers.cards = { Engine.consumable(62, "The Emperor", "c_emperor", "Tarot", { tarots = 2 }, G.shop_jokers) }
  exec, err = buy({ area = "shop_jokers", index = 1, name = "The Emperor", use = true })
  check("buy-and-use of The Emperor with full consumable slots is refused, as the shop hides it",
    exec == nil and type(err) == "table" and err.reason_code == "PRECONDITION_FAILED",
    type(err) == "table" and err.message or tostring(exec))
  exec, err = buy({ area = "shop_jokers", index = 1, name = "The Emperor" })
  check("the full-slot plain buy no longer suggests a buy-and-use the game would refuse",
    exec == nil and type(err) == "table" and tostring(err.message):find("\"use\":true", 1, true) == nil,
    type(err) == "table" and err.message or tostring(exec))
end

do
  board("SHOP")
  G.consumeables.cards = { wheel(G.consumeables, { {} }), wheel(G.consumeables, { {} }) }
  G.shop_jokers.cards = { Engine.consumable(65, "The Hermit", "c_hermit", "Tarot", { extra = 20 }, G.shop_jokers) }
  local exec, err = buy({ area = "shop_jokers", index = 1, name = "The Hermit" })
  check("a plain buy of a usable untargeted card at full consumable slots points at buy-and-use",
    exec == nil and type(err) == "table" and err.reason_code == "NO_SLOT"
      and tostring(err.message):find("\"use\":true", 1, true) ~= nil,
    type(err) == "table" and err.message or tostring(exec))
end

do
  board("SMODS_BOOSTER_OPENED")
  for i = 1, 5 do
    G.jokers.cards[i] = Engine.consumable(70 + i, "Joker", "j_joker", "Joker", nil, G.jokers)
    G.jokers.cards[i].ability.consumeable = nil
  end
  G.pack_cards = Engine.area("booster", 1, 1)
  local pick = Engine.consumable(80, "Jolly Joker", "j_jolly", "Joker", nil, G.pack_cards)
  pick.ability.consumeable = nil
  G.pack_cards.cards = { pick }
  local exec, err = use({ area = "booster_pack", index = 1, name = "Jolly Joker" })
  check("a joker pick at full joker slots is refused with no slot",
    exec == nil and type(err) == "table" and err.reason_code == "NO_SLOT",
    type(err) == "table" and err.message or tostring(exec))
end

do
  board("SHOP")
  G.shop_jokers.cards = { Engine.consumable(65, "Death", "c_death", "Tarot",
    { max_highlighted = 2, min_highlighted = 2 }, G.shop_jokers) }
  local exec, err = buy({ area = "shop_jokers", index = 1, name = "Death", use = true })
  local msg = type(err) == "table" and tostring(err.message) or tostring(exec)
  check("buy-and-use of Death is refused as a directional card",
    exec == nil and type(err) == "table" and err.reason_code == "INVALID_SELECTION", msg)
end

do
  for _, spec in ipairs({ { 63, "Aura", "c_aura", {} }, { 64, "Cryptid", "c_cryptid", { extra = 2, max_highlighted = 1 } } }) do
    board("SHOP")
    G.shop_jokers.cards = { Engine.consumable(spec[1], spec[2], spec[3], "Spectral", spec[4], G.shop_jokers) }
    local exec, err = buy({ area = "shop_jokers", index = 1, name = spec[2], use = true })
    check("buy-and-use of " .. spec[2] .. " is refused as a hand-targeting card",
      exec == nil and type(err) == "table" and err.reason_code == "INVALID_SELECTION",
      type(err) == "table" and (err.reason_code .. " " .. tostring(err.message)) or tostring(exec))
  end
end

do
  local function jupiter(area)
    return Engine.consumable(90, "Jupiter", "c_jupiter", "Planet", { hand_type = "Flush" }, area)
  end
  board("SMODS_BOOSTER_OPENED")
  G.hand.cards = {}
  G.pack_cards = Engine.area("booster", 1, 1)
  G.pack_cards.cards = { jupiter(G.pack_cards) }
  local exec, err = UseCard.handle_use_card({ area = "booster_pack", index = 1, name = "Jupiter",
    hand_indices = { 1 }, _action_id = "pick-jupiter" })
  check("a planet pick with a stray hand_indices and no dealt hand is accepted",
    type(exec) == "function", type(err) == "table" and err.message or tostring(exec))

  board("SHOP")
  G.hand.cards = {}
  G.consumeables.cards = { jupiter(G.consumeables) }
  exec, err = use({ area = "consumables", index = 1, name = "Jupiter", hand_indices = { 1 } })
  check("a held planet used with a stray hand_indices selects nothing",
    type(exec) == "function" and used[1] == "Jupiter[]", table.concat(used, " "))

  board("SHOP")
  G.hand.cards = {}
  G.consumeables.cards = { aura() }
  exec, err = use({ area = "consumables", index = 1, name = "Aura", hand_indices = { 1 } })
  check("a hand-targeting card with no dealt hand says there is no hand, not an index range",
    exec == nil and type(err) == "table" and err.reason_code == "TARGET_UNAVAILABLE",
    type(err) == "table" and err.message or tostring(exec))
end

do
  local _, verr = require("facts.card_area_util").validate_hand_indices({ 1 }, 0, 5)
  check("an empty hand is reported without an impossible 1-0 range",
    verr ~= nil and tostring(verr):find("1-0", 1, true) == nil,
    tostring(verr))
end

done()
