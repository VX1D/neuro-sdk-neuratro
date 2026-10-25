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

local check, done = require("tests.helpers").harness("use outcome unsettled")
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

local function trance_pick(id, land_after_cap)
  local target = EngineCards.playing("King", "Hearts", { sort_id = 1 })
  local other = EngineCards.playing("2", "Spades", { sort_id = 2 })
  G.hand = require("tests.helpers").card_area({ cards = { target, other }, config = { card_limit = 8, type = "hand" } })
  target.area, other.area = G.hand, G.hand
  local seal_event
  local trance = EngineCards.consumable("c_trance", { facing = "front", cost = 1,
    use_consumeable = function() seal_event = function() target.seal = "Blue" end end })
  G.pack_cards = { cards = { trance }, config = { card_limit = 1 } }
  trance.area = G.pack_cards
  G.FUNCS.use_card = function(e)
    e.config.ref_table:use_consumeable()
    table.remove(G.pack_cards.cards, 1)
    return true
  end
  local rc = exec_now(Handle.handle_use_card({ area = "booster_pack", index = 1, hand_indices = { 1 }, _action_id = id }))
  check(id .. ": the pick was accepted and used", type(rc) == "table" and seal_event ~= nil, tostring(rc))
  G.E_MANAGER = { queues = { base = { { blocking = true, blockable = true } } } }
  local t = Receipt.now()
  Receipt.settle(rc, t, 1)
  rc.deadline = t + 100
  local saved = Receipt.now
  if land_after_cap then
    Receipt.now = function() return t + Handle.OUTCOME_SETTLE_MAX + 0.1 end
    Receipt.settle(rc, t + Handle.OUTCOME_SETTLE_MAX + 0.1, 1)
    seal_event()
  else
    seal_event()
    G.E_MANAGER = { queues = { base = {} } }
    Receipt.now = function() return t + 0.5 end
    Receipt.settle(rc, t + 0.5, 1)
  end
  Receipt.now = saved
  G.E_MANAGER = nil
  return rc, target
end

do
  local rc, target = trance_pick("trance-late", true)
  local msg = tostring(rc.applied_message)
  check("the late seal did land on the card", target.seal == "Blue", tostring(target.seal))
  check("an effect landing after the cap is applied without a no-change claim",
    rc.phase == "applied" and not msg:find("no visible change", 1, true), msg)
end

do
  local DecisionDelta = require("facts.decision_delta")
  local target = EngineCards.playing("King", "Hearts", { sort_id = 1 })
  local other = EngineCards.playing("2", "Spades", { sort_id = 2 })
  G.hand = area({ target, other })
  target.area, other.area = G.hand, G.hand
  G.playing_cards = { target, other }
  local _, candidate = DecisionDelta.for_force("SMODS_BOOSTER_OPENED")
  DecisionDelta.commit(candidate)
  target.seal = "Blue"
  G.hand = area({})
  G.deck = area({ target, other }, 60)
  target.area, other.area = G.deck, G.deck
  local next_state = tostring(DecisionDelta.for_force("SHOP"))
  check("the next state carries a hand-card edit returned to the deck",
    next_state:find("King of Hearts to King of Hearts (Blue Seal)", 1, true) ~= nil, next_state)
  local rc = trance_pick("trance-late-2", true)
  check("so an unsettled effect does not send her to the next state for it",
    not tostring(rc.applied_message):find("next state", 1, true), tostring(rc.applied_message))
  G.playing_cards = {}
end

do
  local rc = trance_pick("trance-settled", false)
  local msg = tostring(rc.applied_message)
  check("a seal landing inside the cap is reported as a change",
    rc.phase == "applied" and msg:find("hand card 1", 1, true) ~= nil
      and not msg:find("no visible change", 1, true), msg)
end

done()
