_G.NEURO_TEST = true

local function noop() end
local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local IMG = { getWidth = function() return 64 end, getHeight = function() return 64 end,
  getDimensions = function() return 64, 64 end }
love = setmetatable({
  graphics = setmetatable({
    getFont = function() return FONT end,
    newFont = function() return FONT end,
    getWidth = function() return 1920 end,
    getHeight = function() return 1080 end,
    getShader = function() return nil end,
    getBlendMode = function() return "alpha", "alphamultiply" end,
    newQuad = function() return {} end,
    newImage = function() return IMG end,
    newMesh = function() return {} end,
  }, { __index = function() return noop end }),
  timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

_G.G = { P_CENTERS = require("tests.engine_centers").centers(), NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 0, TOTAL = 0 }, SETTINGS = {} }
require("tests.engine_cards").install_smods({ current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end })
_G.NFS = setmetatable({}, { __index = function() return noop end })

local check, done = require("tests.helpers").harness("staged visibility")

local Cards = require("hud.cards")
local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local Staging = require("core.staging")

local MIN_VISIBLE_S = 0.5

local clock = 0
local function tick(dt)
  clock = clock + dt
  G.TIMERS.REAL = clock
  G.TIMERS.TOTAL = clock
end

local function make_bridge()
  return require("tests.helpers").fake_bridge({ ack = true, register = "noop", force = true, send = true })
end

local function mock_card(o)
  local c = {
    cost = 4, sell_cost = 2,
    ability = { set = "Default", name = "Mock" },
    config = { center = {} },
    juice_up = noop,
    highlight = function(self, on) self.highlighted = on end,
  }
  for k, v in pairs(o or {}) do c[k] = v end
  return c
end

local EngineCards = require("tests.engine_cards")

local function tarot(key, extra)
  local c = EngineCards.consumable(key, { cost = 4, sell_cost = 2, juice_up = noop })
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end

local function fresh(state)
  G.STATES = EngineCards.states()
  G.STATE = G.STATES[state]
  G.CONTROLLER = { locked = false }
  G.NEURO = { dispatcher = Dispatcher, actions = Actions, persona = "neuro", register_actions = function() end,
    ai_highlighted = setmetatable({}, { __mode = "k" }) }
  G.FUNCS = { get_poker_hand_info = require("tests.engine_hand_info").stub("Three of a Kind") }
  G.GAME = {
    dollars = 20, bankrupt_at = 0, stake = 1, chips = 0, used_vouchers = {},
    current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5, free_rerolls = 0 },
    round_resets = { ante = 2 },
    blind = { chips = 300, mult = 1 },
  }
  local hand = {}
  for i = 1, 5 do hand[i] = mock_card({ sort_id = i, base = { value = "10", suit = "Hearts" } }) end
  G.hand = require("tests.helpers").card_area({ cards = hand, highlighted = {}, config = { card_limit = 5 } })
  G.jokers = { cards = { mock_card({ ability = { set = "Joker", name = "Mock" } }) },
    config = { card_limit = 5 } }
  G.consumeables = { cards = { tarot("c_fool") }, config = { card_limit = 2 } }
  G.shop_jokers = { cards = { mock_card({ ability = { set = "Joker", name = "Mock" } }) } }
  G.shop_vouchers = { cards = {} }
  G.shop_booster = { cards = {} }
  local PlanGate = require("core.gate")
  G.NEURO.plan = { money = "buy the mock joker", money_scope = PlanGate.current_economy_scope(),
    build = "keep the mock joker" }
  G.NEURO.econ_plan_ok = true
  Dispatcher.reset_run_state()
  Staging.reset_run_state()
  require("tests.helpers").event_manager()
  require("tests.helpers").stage_registered(state,
    { "play_hand", "discard_hand", "buy_from_shop", "sell_card", "use_consumable", "choose_pack_card" })
  tick(10)
end

local function glow_engaged(card)
  local w = G.NEURO.ai_glow and G.NEURO.ai_glow[card]
  if type(w) ~= "table" or not (w.t1 and w.t0 and w.t1 > w.t0) then return false end
  local mid = (w.t0 + w.t1) / 2
  local level = Cards.glow_step(mid, 0, 0.016, true, w)
  return Cards.glow_window_valid(w, mid) and level > 0
end

local function scenario(label, state, name, payload, engine_fn, targets, opts)
  opts = opts or {}
  fresh(state)
  if opts.arrange then opts.arrange() end
  local executed_at
  G.FUNCS[engine_fn] = function() executed_at = executed_at or clock end
  local bridge = make_bridge()
  local routed_at = clock
  Dispatcher.route_message({ command = "action", data = { id = "vis-" .. label, name = name,
    data = payload } }, bridge)
  local cards = targets()
  check(label .. ": routed action is staged, not executed on arrival",
    executed_at == nil and Staging.is_busy(), tostring(executed_at))
  check(label .. ": admission result precedes execution",
    #bridge.results == 1 and bridge.results[1].ok == true,
    bridge.results[1] and bridge.results[1].message)
  check(label .. ": staging carries the target cards",
    Staging._test.staged_hover_count() == #cards, Staging._test.staged_hover_count())
  local glowing = 0
  for _, c in ipairs(cards) do if glow_engaged(c) then glowing = glowing + 1 end end
  check(label .. ": glow painter engaged for every staged card", glowing == #cards,
    glowing .. "/" .. #cards)
  if opts.stale then
    check(label .. ": the card at the stale index is not lit", not glow_engaged(opts.stale()))
  end
  local lifted, stale_lifted = false, false
  for _ = 1, 400 do
    if executed_at then break end
    for _, c in ipairs(cards) do if c.highlighted then lifted = true end end
    if opts.stale and opts.stale().highlighted then stale_lifted = true end
    tick(0.05)
    Staging.update()
    require("core.execute").step(clock)
    G.E_MANAGER:run()
  end
  check(label .. ": target card is lifted before execution", lifted)
  check(label .. ": the card at the stale index is not lifted", not stale_lifted)
  check(label .. ": execution waits a visible delay",
    executed_at ~= nil and executed_at - routed_at >= MIN_VISIBLE_S,
    executed_at and string.format("%.2fs", executed_at - routed_at) or "never")
  check(label .. ": exactly one result on the wire", #bridge.results == 1, #bridge.results)
end

local function hand_at(ix)
  return function()
    local out = {}
    for _, i in ipairs(ix) do out[#out + 1] = G.hand.cards[i] end
    return out
  end
end

local Config = require("core.config")
Config.set("NEURO_CONFIRM_HAND", "off")
scenario("play with hand confirmation off", "SELECTING_HAND", "play_hand", '{"indices":[1,2,3]}',
  "play_cards_from_highlighted", hand_at({ 1, 2, 3 }))
Config.set("NEURO_CONFIRM_HAND", "on")
scenario("discard", "SELECTING_HAND", "discard_hand", '{"indices":[4,5]}',
  "discard_cards_from_highlighted", hand_at({ 4, 5 }))
scenario("buy", "SHOP", "buy_from_shop", '{"area":"shop_jokers","index":1}',
  "buy_from_shop", function() return { G.shop_jokers.cards[1] } end)
scenario("sell", "SHOP", "sell_card", '{"area":"consumables","index":1,"plan":{"build_plan":"sell the tarot"}}',
  "sell_card", function() return { G.consumeables.cards[1] } end)

local function named(set, name, extra)
  local c = mock_card({ ability = { set = set, name = name, mult = 4 } })
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end
local function two_jokers_in_shop()
  G.shop_jokers.cards = { named("Joker", "Mock"), named("Joker", "Greedy Joker") }
end
local function two_tarots()
  G.consumeables.cards = { tarot("c_fool"), tarot("c_hermit") }
end
local function shop_second() return { G.shop_jokers.cards[2] } end
local function shop_first() return G.shop_jokers.cards[1] end
local function tarot_second() return { G.consumeables.cards[2] } end
local function tarot_first() return G.consumeables.cards[1] end

scenario("buy with a shifted index", "SHOP", "buy_from_shop",
  '{"area":"shop_jokers","index":1,"name":"Greedy Joker"}', "buy_from_shop", shop_second,
  { arrange = two_jokers_in_shop, stale = shop_first })
scenario("buy with an index past the row", "SHOP", "buy_from_shop",
  '{"area":"shop_jokers","index":7,"name":"Greedy Joker"}', "buy_from_shop", shop_second,
  { arrange = two_jokers_in_shop, stale = shop_first })
scenario("sell with a shifted index", "SHOP", "sell_card",
  '{"area":"consumables","index":1,"name":"The Hermit","plan":{"build_plan":"sell the tarot","money_plan":"keep the cash"}}',
  "sell_card", tarot_second, { arrange = two_tarots, stale = tarot_first })
scenario("use with a shifted index", "SHOP", "use_consumable",
  '{"area":"consumables","index":1,"name":"The Hermit","plan":{"build_plan":"use the tarot","hand_plan":"play pairs"}}', "use_card", tarot_second,
  { arrange = two_tarots, stale = tarot_first })
scenario("pick with a shifted index", "SMODS_BOOSTER_OPENED", "choose_pack_card",
  '{"area":"booster_pack","index":1,"name":"The Hermit"}', "use_card",
  function() return { G.pack_cards.cards[2] } end, {
    arrange = function()
      G.pack_cards = { cards = { tarot("c_fool"), tarot("c_hermit") },
        config = { card_limit = 2 } }
      G.booster_pack = G.pack_cards
    end,
    stale = function() return G.pack_cards.cards[1] end })
scenario("use of a face-down card by index", "SHOP", "use_consumable",
  '{"area":"consumables","index":1,"name":"The Hermit","plan":{"build_plan":"use the tarot","hand_plan":"play pairs"}}', "use_card",
  function() return { G.consumeables.cards[1] } end, {
    arrange = function()
      local fool = tarot("c_fool", { area = G.consumeables })
      fool.ability.wheel_flipped = true
      G.GAME.last_tarot_planet = "c_pluto"
      G.consumeables.cards = { fool, tarot("c_hermit") }
    end,
    stale = function() return G.consumeables.cards[2] end, hidden = "Fool" })

do
  fresh("SHOP")
  two_jokers_in_shop()
  local n = 0
  local function stages(payload)
    n = n + 1
    local bridge = make_bridge()
    Dispatcher.route_message({ command = "action", data = { id = "vis-pre-" .. n, name = "buy_from_shop",
      data = payload } }, bridge)
    local staged = require("core.execute").busy() ~= nil
    Dispatcher.reset_run_state()
    return staged and bridge.results[1] and bridge.results[1].ok == true
  end
  check("a name that matches no card is refused, not staged",
    not stages('{"area":"shop_jokers","index":1,"name":"Blueprint"}'))
  G.shop_jokers.cards[2].ability.wheel_flipped = true
  check("a name never resolves to a face-down card",
    not stages('{"area":"shop_jokers","index":1,"name":"Greedy Joker"}')
      and not stages('{"area":"shop_jokers","index":7,"name":"Greedy Joker"}'))
end

done()
