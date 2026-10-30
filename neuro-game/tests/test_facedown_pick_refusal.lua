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
    blind = {}, used_vouchers = {}, modifiers = {}, consumeable_buffer = 0, joker_buffer = 0 },
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

local check, done = require("tests.helpers").harness("face-down pick refusal")
require("core.config").init({ settings = {}, colours = {} }, function() return true end)
_G.Event = function(cfg) return cfg end
G.E_MANAGER = { add_event = noop }

local EC = require("tests.engine_cards")
local Handle = require("handlers.use_card")

local function deal_hand(n)
  local ranks = { "2", "5", "9", "King", "Ace" }
  local cards = {}
  for i = 1, n do cards[i] = EC.playing(ranks[i], "Hearts", { sort_id = i }) end
  G.hand = area(cards)
  for _, c in ipairs(cards) do c.area = G.hand end
end

local function joker(facing)
  local c = EC.card({ config = { center = { key = "j_joker", set = "Joker", name = "Joker",
    loc_txt = { name = "Joker" }, rarity = 1 } }, ability = { set = "Joker", name = "Joker" }, cost = 2 })
  c.facing = facing
  return c
end

local function attempt(card, where, payload)
  local data = { _action_id = "x" }
  for k, v in pairs(payload or {}) do data[k] = v end
  if where == "pack" then
    G.pack_cards = area({ card })
    data.area, data.index = "booster_pack", 1
  else
    G.pack_cards = nil
    G.consumeables = area({ card })
    data.area, data.index = "consumables", 1
  end
  card.area = where == "pack" and G.pack_cards or G.consumeables
  G.FUNCS.use_card = function() return true end
  local out, err = Handle.handle_use_card(data)
  if type(out) == "function" then return false end
  return err and err.message or tostring(err)
end

local boards = {
  { label = "no hand", setup = function() G.STATE = G.STATES.SHOP; deal_hand(0) end },
  { label = "hand of 5", setup = function() G.STATE = G.STATES.TAROT_PACK; deal_hand(5) end },
}
local payloads = { {}, { hand_indices = { 1, 2 } } }

local by_where = { pack = {}, consumables = {} }
local leaks = {}
for _, board in ipairs(boards) do
  for _, where in ipairs({ "pack", "consumables" }) do
    for key in pairs(EC.consumable_centers()) do
      for _, payload in ipairs(payloads) do
        board.setup()
        G.jokers = area({ joker("front"), joker("front"), joker("front"), joker("front"), joker("front") })
        local card = EC.consumable(key, { facing = "back" })
        local msg = attempt(card, where, payload)
        if msg then
          by_where[where][msg] = (by_where[where][msg] or 0) + 1
          leaks[#leaks + 1] = msg
        end
      end
    end
    if where == "pack" then
      board.setup()
      G.jokers = area({ joker("front"), joker("front"), joker("front"), joker("front"), joker("front") })
      local msg = attempt(joker("back"), "pack")
      if msg then by_where.pack[msg] = (by_where.pack[msg] or 0) + 1 end
    end
  end
end

for where, texts in pairs(by_where) do
  local distinct = {}
  for msg, n in pairs(texts) do distinct[#distinct + 1] = string.format("%dx %s", n, msg) end
  table.sort(distinct)
  check(where .. ": every face-down refusal has one text", #distinct <= 1, table.concat(distinct, "\n   "))
end

local named = {}
for key, center in pairs(EC.consumable_centers()) do
  for _, msg in ipairs(leaks) do
    if msg:find(center.name, 1, true) then named[#named + 1] = center.name .. " in: " .. msg end
  end
end
check("no face-down refusal names a card", #named == 0, table.concat(named, " | "))

G.STATE = G.STATES.TAROT_PACK
deal_hand(5)
G.jokers = area({})
local death_up = attempt(EC.consumable("c_death", { facing = "front" }), "pack")
check("a face-up Death still points at the directional action",
  type(death_up) == "string" and death_up:find("Take a directional pack card", 1, true) ~= nil, tostring(death_up))

done()
