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
EngineCards.install_smods({ current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end })
_G.NFS = setmetatable({}, { __index = function() return noop end })

local check, done = require("tests.helpers").harness("use outcome chosen seat")
require("core.config").init({ settings = {}, colours = {} }, function() return true end)
_G.Event = function(cfg) return cfg end

local Handle = require("handlers.use_card")
local Receipt = require("core.action_result")
local NeuroAnim = require("render.neuro-anim")
NeuroAnim.hover_pack_card, NeuroAnim.pick_pack_card, NeuroAnim.cancel_pending = nil, nil, nil

local function exec_now(exec)
  local events = {}
  G.E_MANAGER = { add_event = function(_, e) events[#events + 1] = e end }
  local rc = exec()
  for _, e in ipairs(events) do e.func() end
  return rc
end

-- Closing the pack returns hand cards one at a time; the outcome may see a different hand order.
local ace = EngineCards.playing("Ace", "Hearts", { sort_id = 1 })
local king = EngineCards.playing("King", "Diamonds", { sort_id = 2 })
G.hand = require("tests.helpers").card_area({ cards = { ace, king }, config = { card_limit = 8, type = "hand" } })
ace.area, king.area = G.hand, G.hand
local effect
local deja_vu = EngineCards.consumable("c_deja_vu", { facing = "front", cost = 1,
  use_consumeable = function()
    effect = function()
      king.seal = "Red"
      table.remove(G.hand.cards, 1)
      G.deck.cards[#G.deck.cards + 1] = ace
      ace.area = G.deck
    end
  end })
G.pack_cards = { cards = { deja_vu }, config = { card_limit = 1 } }
deja_vu.area = G.pack_cards
G.FUNCS.use_card = function(e)
  e.config.ref_table:use_consumeable()
  table.remove(G.pack_cards.cards, 1)
  return true
end
local rc = exec_now(Handle.handle_use_card(require("tests.helpers").with_card_names("use_consumable", { area = "booster_pack", index = 1, hand_indices = { 2 }, _action_id = "deja-vu" })))
check("the pick was accepted and used", type(rc) == "table" and effect ~= nil, tostring(rc))
G.E_MANAGER = { queues = { base = { { blocking = true, blockable = true } } } }
local t = Receipt.now()
Receipt.settle(rc, t, 1)
effect()
G.E_MANAGER = { queues = { base = {} } }
local saved = Receipt.now
Receipt.now = function() return t + 0.5 end
Receipt.settle(rc, t + 0.5, 1)
Receipt.now = saved
G.E_MANAGER = nil
local msg = tostring(rc.applied_message)
check("the effect names the hand card she chose", rc.phase == "applied"
  and msg:find("hand card 2 King of Diamonds became", 1, true) ~= nil
  and not msg:find("hand card 1", 1, true), msg)

done()
