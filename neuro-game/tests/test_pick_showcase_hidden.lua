local function noop() end
love = setmetatable({
  graphics = setmetatable({}, { __index = function() return noop end }),
  timer = { getTime = function() return 0 end, getFPS = function() return 144 end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

local area = require("tests.helpers").area
_G.G = {
  NEURO = { persona = "hiyori", state = "SMODS_BOOSTER_OPENED", enabled = true,
    purchase_showcase_queue = {}, last_action_at = 0, run_generation = 1,
    ai_highlighted = setmetatable({}, { __mode = "k" }) },
  GAME = { dollars = 20, pack_choices = 1, round = 1, round_resets = { ante = 1, blind_choices = {} },
    blind = {}, used_vouchers = {}, modifiers = {} },
  jokers = area({}), consumeables = area({}), hand = area({}),
  shop_jokers = area({}), shop_vouchers = area({}), shop_booster = area({}),
  FUNCS = {}, TIMERS = { REAL = 0 }, STATES = require("tests.engine_cards").states(),
  SETTINGS = { paused = false, GAMESPEED = 1 },
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
  ARGS = {}, P_CENTERS = {}, P_CENTER_POOLS = {}, P_BLINDS = {}, localization = {},
  ASSET_ATLAS = {}, SHADERS = {}, TILESCALE = 3.65, TILESIZE = 20, CANV_SCALE = 1,
  I = { MOVEABLE = {}, UIBOX = {}, NODE = {} },
}
require("tests.engine_cards").install_smods({ current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end })
_G.NFS = setmetatable({}, { __index = function() return noop end })

local check, done = require("tests.helpers").harness("pick showcase hidden")
require("core.config").init({ settings = {}, colours = {} }, function() return true end)

local queued_events = {}
_G.Event = function(cfg) return cfg end
G.E_MANAGER = { add_event = function(_, e) queued_events[#queued_events + 1] = e end }

local Handle = require("handlers.use_card")
local Receipt = require("core.action_result")

local function joker_card(key, name, facing)
  local c = require("tests.engine_cards").card({
    config = { center = { key = key, set = "Joker", name = name, loc_txt = { name = name }, rarity = 1 } },
    ability = {},
    cost = 1,
  })
  c.facing = facing
  return c
end

local function pick(card)
  G.NEURO.purchase_showcase_queue = {}
  queued_events = {}
  require("hud.showcase").reset_run_state()
  G.GAME.pack_choices = 1
  G.pack_cards = { cards = { card }, config = { card_limit = 1 } }
  G.FUNCS.use_card = function() table.remove(G.pack_cards.cards, 1); return true end
  local exec = Handle.handle_use_card({ area = "booster_pack", index = 1, _action_id = "pick" })
  if type(exec) ~= "function" then return nil end
  local receipt = exec()
  local events = queued_events
  queued_events = {}
  for _, e in ipairs(events) do if e.func then e.func() end end
  Receipt.settle(receipt, Receipt.now(), G.NEURO.run_generation)
  return G.NEURO.purchase_showcase_queue[1]
end

local hidden = joker_card("j_hidden", "Hidden", "back")
local item = pick(hidden)
check("a face-down pick still files a receipt", item ~= nil and item.name == "face-down card",
  item and tostring(item.name))
check("the receipt for a face-down pick carries no card object", item ~= nil and item.card == nil,
  item and tostring(item.card))

local shown = joker_card("j_shown", "Shown", "front")
item = pick(shown)
check("a face-up pick receipt carries its card", item ~= nil and item.card == shown, item and tostring(item.card))

done()
