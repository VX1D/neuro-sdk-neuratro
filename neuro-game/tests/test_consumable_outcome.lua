local clock = 10
if not love then love = {} end
love.timer = { getTime = function() return clock end }

local function noop() end
love.graphics = setmetatable({
  getFont = function() return { getWidth = function(_, s) return #tostring(s or "") * 8 end,
    getHeight = function() return 12 end } end,
  getWidth = function() return 1920 end, getHeight = function() return 1080 end,
}, { __index = function() return noop end })
love.filesystem = setmetatable({}, { __index = function() return function() return nil end end })

local area = require("tests.helpers").area
local EngineCards = require("tests.engine_cards")
local STATES = EngineCards.states()
_G.G = {
  STATE = STATES.SMODS_BOOSTER_OPENED, CONTROLLER = { locked = false },
  NEURO = { persona = "hiyori", state = "SMODS_BOOSTER_OPENED", enabled = true,
    purchase_showcase_queue = {}, last_action_at = 0, run_generation = 1,
    ai_highlighted = setmetatable({}, { __mode = "k" }) },
  GAME = { dollars = 20, pack_choices = 1, round = 1, round_resets = { ante = 1, blind_choices = {} },
    blind = {}, used_vouchers = {}, modifiers = {}, hands = {} },
  jokers = area({}), consumeables = area({}), hand = area({}), deck = area({}, 60),
  shop_jokers = area({}), shop_vouchers = area({}), shop_booster = area({}),
  FUNCS = {}, TIMERS = { REAL = 10 }, STATES = STATES,
  SETTINGS = { paused = false, GAMESPEED = 1 },
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
  ARGS = {}, P_CENTERS = {}, P_CENTER_POOLS = {}, P_BLINDS = {}, localization = {},
  ASSET_ATLAS = {}, SHADERS = {}, I = { MOVEABLE = {}, UIBOX = {}, NODE = {} },
  playing_cards = {},
}
require("tests.engine_cards").install_smods({ current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end })
_G.NFS = setmetatable({}, { __index = function() return noop end })

local check, done = require("tests.helpers").harness("consumable outcome")
require("core.config").init({ settings = {}, colours = {} }, function() return true end)
_G.Event = function(cfg) return cfg end

local Handle = require("handlers.use_card")
local Receipt = require("core.action_result")
local NeuroAnim = require("render.neuro-anim")
NeuroAnim.hover_pack_card, NeuroAnim.pick_pack_card, NeuroAnim.cancel_pending = nil, nil, nil

local function joker(key, name)
  return require("tests.engine_cards").card({ facing = "front", ability = { set = "Joker", name = name }, cost = 1, sell_cost = 1,
    config = { center = { key = key, set = "Joker", name = name, loc_txt = { name = name }, rarity = 1 } } })
end

local pending_effect
local function consumable(key, effect)
  return EngineCards.consumable(key, { facing = "front", cost = 1,
    use_consumeable = function() pending_effect = effect end })
end
local function wheel(effect) return consumable("c_wheel_of_fortune", effect) end

local function exec_now(exec)
  local events = {}
  G.E_MANAGER = { add_event = function(_, e) events[#events + 1] = e end }
  local rc = exec()
  for _, e in ipairs(events) do e.func() end
  return rc
end

local function pick(card, id)
  G.pack_cards = { cards = { card }, config = { card_limit = 1 } }
  card.area = G.pack_cards
  G.FUNCS.use_card = function(e)
    local c = e.config.ref_table
    c:use_consumeable()
    table.remove(G.pack_cards.cards, 1)
    return true
  end
  local rc = exec_now(Handle.handle_use_card({ area = "booster_pack", index = 1, _action_id = id }))
  G.E_MANAGER = { queues = { base = { { blocking = true, blockable = true } } } }
  Receipt.settle(rc, clock + 0.5, 1)
  local waited = rc.phase == nil
  if pending_effect then pending_effect() end
  pending_effect = nil
  G.E_MANAGER = { queues = { base = {} } }
  Receipt.settle(rc, clock + 1, 1)
  return rc, waited
end

do
  local blue = joker("j_blue_joker", "Blue Joker")
  G.jokers = area({ blue })
  local rc, waited = pick(wheel(function() blue.edition = { polychrome = true } end), "wof-hit")
  check("the result waits for the queued effect instead of reporting the bare use", waited, rc.phase)
  check("a winning Wheel of Fortune names the joker and the edition it got",
    rc.phase == "applied" and rc.applied_message == "Used: The Wheel of Fortune -- Blue Joker became Polychrome",
    tostring(rc.applied_message))
end

do
  local blue = joker("j_blue_joker", "Blue Joker")
  G.jokers = area({ blue })
  local rc = pick(wheel(function() end), "wof-nope")
  check("a Nope! Wheel of Fortune says it changed nothing visible",
    rc.applied_message == "Used: The Wheel of Fortune -- no visible change", tostring(rc.applied_message))
end

do
  local blue = joker("j_blue_joker", "Blue Joker")
  blue.facing = "back"
  G.jokers = area({ blue })
  local rc = pick(wheel(function() blue.edition = { polychrome = true } end), "wof-hidden")
  check("an edition landing on a face-down joker is not named",
    rc.applied_message == "Used: The Wheel of Fortune -- no visible change", tostring(rc.applied_message))
end

do
  G.jokers = area({})
  G.GAME.dollars = 12
  local hermit = consumable("c_hermit", function() G.GAME.dollars = 24 end)
  local rc = pick(hermit, "hermit")
  check("any consumable reports its visible effect: money doubled",
    rc.applied_message == "Used: The Hermit -- money +$12 (now $24)", tostring(rc.applied_message))
end

do
  G.jokers = area({ joker("j_blue_joker", "Blue Joker") })
  local card = wheel(function() end)
  G.pack_cards = { cards = { card }, config = { card_limit = 1 } }
  card.area = G.pack_cards
  local rc = exec_now(Handle.handle_use_card({ area = "booster_pack", index = 1, _action_id = "wof-slow" }))
  G.E_MANAGER = { queues = { base = { { blocking = true, blockable = true } } } }
  local t = Receipt.now()
  Receipt.settle(rc, t, 1)
  rc.deadline = t + 100
  local saved = Receipt.now
  Receipt.now = function() return t + Handle.OUTCOME_SETTLE_MAX + 0.1 end
  Receipt.settle(rc, t + Handle.OUTCOME_SETTLE_MAX + 0.1, 1)
  Receipt.now = saved
  check("a use whose effect is still queued at the cap makes no claim about change",
    rc.phase == "applied" and rc.applied_message == "Used: The Wheel of Fortune -- nothing visible had changed yet when this was reported",
    tostring(rc.phase) .. " / " .. tostring(rc.applied_message))
  G.E_MANAGER = nil
end

do
  local ShopHandlers = require("handlers.shop_handlers")
  G.NEURO.state = "SHOP"
  G.STATE = STATES.SHOP
  local blue = joker("j_blue_joker", "Blue Joker")
  G.jokers = area({ blue })
  G.GAME.dollars = 20
  local card = wheel(function() blue.edition = { foil = true } end)
  card.cost = 2
  G.shop_jokers = area({ card })
  card.area = G.shop_jokers
  G.FUNCS.buy_from_shop = function(e)
    local c = e.config.ref_table
    table.remove(G.shop_jokers.cards, 1)
    G.GAME.dollars = G.GAME.dollars - c.cost
    c:use_consumeable()
    return true
  end
  local exec = ShopHandlers.handle_buy_from_shop({ area = "shop_jokers", index = 1, use = true,
    _action_id = "shop-wof" })
  local rc = type(exec) == "function" and exec_now(exec) or exec
  check("buy-and-use returns a receipt", Receipt.is_receipt(rc), tostring(rc))
  if Receipt.is_receipt(rc) then
    G.E_MANAGER = { queues = { base = { { blocking = true, blockable = true } } } }
    Receipt.settle(rc, Receipt.now(), 1)
    local waited = rc.phase == nil
    if pending_effect then pending_effect() end
    pending_effect = nil
    G.E_MANAGER = { queues = { base = {} } }
    Receipt.settle(rc, Receipt.now(), 1)
    check("a bought-and-used Wheel of Fortune reports its outcome, not the price",
      waited and rc.phase == "applied"
        and rc.applied_message == "Buying: The Wheel of Fortune for $2 and used it -- Blue Joker became Foil",
      tostring(rc.phase) .. " / " .. tostring(rc.applied_message))
  end
  G.E_MANAGER = nil
end

do
  local ShopHandlers = require("handlers.shop_handlers")
  G.jokers = area({})
  G.GAME.dollars = 9
  local card = consumable("c_hermit", function() G.GAME.dollars = G.GAME.dollars * 2 end)
  card.cost = 3
  G.shop_jokers = area({ card })
  card.area = G.shop_jokers
  G.FUNCS.buy_from_shop = function(e)
    local c = e.config.ref_table
    table.remove(G.shop_jokers.cards, 1)
    G.GAME.dollars = G.GAME.dollars - c.cost
    c:use_consumeable()
    return true
  end
  local exec = ShopHandlers.handle_buy_from_shop({ area = "shop_jokers", index = 1, use = true,
    _action_id = "shop-hermit" })
  local rc = type(exec) == "function" and exec_now(exec) or exec
  if Receipt.is_receipt(rc) then
    if pending_effect then pending_effect() end
    pending_effect = nil
    G.E_MANAGER = { queues = { base = {} } }
    Receipt.settle(rc, Receipt.now(), 1)
  end
  local msg = Receipt.is_receipt(rc) and tostring(rc.applied_message) or tostring(rc)
  check("a bought-and-used Hermit states its effect as a change, with no before-amount of its own",
    msg == "Buying: The Hermit for $3 and used it -- money +$6 (now $12)", msg)
  G.E_MANAGER = nil
end

done()
