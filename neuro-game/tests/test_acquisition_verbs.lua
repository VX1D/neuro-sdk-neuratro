
local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local function noop() end
local PRINTED = {}
local IMG = { getWidth = function() return 64 end, getHeight = function() return 64 end,
  getDimensions = function() return 64, 64 end }
local gfxstub = setmetatable({
  getFont = function() return FONT end,
  newFont = function() return FONT end,
  getWidth = function() return 1920 end,
  getHeight = function() return 1080 end,
  getShader = function() return nil end,
  getBlendMode = function() return "alpha", "alphamultiply" end,
  newQuad = function() return {} end,
  newImage = function() return IMG end,
  newMesh = function() return {} end,
  print = function(text) PRINTED[#PRINTED + 1] = tostring(text or "") end,
}, { __index = function() return noop end })
love = setmetatable({
  graphics = gfxstub,
  timer = { getTime = function() return 0 end, getFPS = function() return 144 end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

local area = require("tests.helpers").area
_G.G = {
  NEURO = { persona = "hiyori", state = "SHOP", enabled = true,
    purchase_showcase_queue = {}, last_action_at = 0, run_generation = 1,
    ai_highlighted = setmetatable({}, { __mode = "k" }) },
  GAME = { dollars = 20, pack_choices = 0, round = 1, round_resets = { ante = 1, blind_choices = {} },
    blind = {}, used_vouchers = {}, modifiers = {}, hands = {} },
  jokers = area({}), consumeables = area({}), hand = area({}),
  shop_jokers = area({}), shop_vouchers = area({}), shop_booster = area({}),
  FUNCS = {}, TIMERS = { REAL = 0 },
  STATE = 5, STATES = { SELECTING_HAND = 1, MENU = 2, GAME_OVER = 4, SHOP = 5 },
  STAGE = 2, STAGES = { MAIN_MENU = 1, RUN = 2 },
  SETTINGS = { paused = false, GAMESPEED = 1 },
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
  ARGS = {}, P_CENTERS = {}, P_CENTER_POOLS = {}, P_BLINDS = {}, localization = {},
  ASSET_ATLAS = {}, SHADERS = {}, TILESCALE = 3.65, TILESIZE = 20, CANV_SCALE = 1,
  I = { MOVEABLE = {}, UIBOX = {}, NODE = {} },
}
_G.SMODS = { current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end }
_G.NFS = setmetatable({}, { __index = function() return noop end })

local check, done = require("tests.helpers").harness("acquisition verbs")

local Config = require("core.config")
Config.init({ settings = {}, colours = {} }, function() return true end)

local queued_events = {}
_G.Event = function(cfg) return cfg end
G.E_MANAGER = { add_event = function(_, e) queued_events[#queued_events + 1] = e end }
local function drain_events()
  local list = queued_events
  queued_events = {}
  for _, e in ipairs(list) do if type(e.func) == "function" then e.func() end end
end

local Showcase = require("hud.showcase")
local S = require("hud.state")
local ActionReceipt = require("core.action_receipt")
local UseCard = require("handlers.use_card")
local ShopHandlers = require("handlers.shop_handlers")
local Acquire = require("render.panels.acquire")
local DrawAcquire = Acquire.draw
local LevelDelta = require("util.level_delta")

local next_sort_id = 100
local function joker_card(key, name)
  next_sort_id = next_sort_id + 1
  return {
    config = { center = { key = key, set = "Joker", name = name, loc_txt = { name = name }, rarity = 1 } },
    ability = { name = name, set = "Joker" },
    cost = 6, sell_cost = 3, sort_id = next_sort_id,
  }
end

local function tarot_card(key, name)
  next_sort_id = next_sort_id + 1
  return {
    config = { center = { key = key, set = "Tarot", name = name, loc_txt = { name = name } } },
    ability = { name = name, set = "Tarot", consumeable = {} },
    cost = 4, sort_id = next_sort_id,
  }
end

local function reset()
  G.NEURO.purchase_showcase_queue = {}
  G.NEURO.last_action_at = 0
  G.NEURO.reserved_dollars = 0
  G.NEURO.dev_preview_active = nil
  G.TIMERS.REAL = 0
  G.STAGE = 2
  G.STATE = 5
  G.jokers, G.consumeables = area({}), area({})
  G.shop_jokers, G.shop_vouchers = area({}), area({})
  G.GAME.dollars = 20
  G.GAME.hands = {}
  S.buy_showcase = nil
  queued_events = {}
  Showcase.reset_run_state()
  for i = #PRINTED, 1, -1 do PRINTED[i] = nil end
end

local function receipt_ctx(now)
  local function CLR() return { 0.7, 0.7, 0.7, 1 } end
  local PAL = setmetatable({}, { __index = function() return CLR() end })
  return {
    theme = {
      p = CLR(), pg = CLR(), bg = CLR(), ACC = CLR(), FR = CLR(), FRD = CLR(),
      WHITE = { 1, 1, 1, 1 }, GOLD = CLR(), _pal = PAL,
      persona_evil = false, persona_neuro = false, pk = "hiyori",
      font = FONT, font_title = FONT, panel_font_small = FONT,
      cfont = FONT, cfont_title = FONT, cfont_small = FONT, cfont_micro = FONT,
    },
    motion = { now = now or G.TIMERS.REAL, pulse = 0.5, dt = 1 / 60, shimr = 1, shimg = 1, shimb = 1 },
    metrics = { cn = function(v) return v end, sw = 1920, sh = 1080, U = 4, GUT = 12, TRACK = 2 },
    data = {},
    draw = { trunc = function(s) return s end },
    center_max_w = 900, center_cx = 900, center_top_y = 8,
  }
end

local function draw_text(now)
  for i = #PRINTED, 1, -1 do PRINTED[i] = nil end
  local at = now or ((S.buy_showcase and S.buy_showcase.started or 0) + 0.5)
  local ok, err = xpcall(function() DrawAcquire(receipt_ctx(at)) end, debug.traceback)
  return ok, err, table.concat(PRINTED, "")
end

local function show_head(now)
  S.buy_showcase = nil
  Showcase.update_buy(now or G.TIMERS.REAL)
end

do
  reset()
  local death = tarot_card("c_death", "Death")
  G.shop_jokers = area({ death })
  G.FUNCS.buy_from_shop = function(e)
    check("1a buy-and-use reaches the engine with the buy_and_use id",
      e and e.config and e.config.id == "buy_and_use", e and e.config and e.config.id)
    table.remove(G.shop_jokers.cards, 1)
    return true
  end
  local exec = ShopHandlers.handle_buy_from_shop({ area = "shop_jokers", index = 1, use = true })
  check("1b the buy-and-use executes", type(exec) == "function", tostring(exec))
  if type(exec) == "function" then exec(); drain_events() end
  local q = G.NEURO.purchase_showcase_queue
  check("1c buy-and-use files exactly one receipt", #q == 1, #q)
  check("1d buy-and-use is not tagged as a plain shop acquisition",
    q[1] and q[1].area ~= "shop_jokers" and q[1].area ~= "shop", q[1] and q[1].area)
  check("1e buy-and-use is tagged shop_use", q[1] and q[1].area == "shop_use", q[1] and q[1].area)
  check("1f buy-and-use keeps the money it spent", q[1] and q[1].cost == 4, q[1] and q[1].cost)
  check("1g the used card reaches neither slot row",
    #G.consumeables.cards == 0 and #G.jokers.cards == 0)
  show_head(0)
  local ok, err, text = draw_text()
  check("1h the buy-and-use receipt draws", ok, err)
  check("1i the buy-and-use receipt never says a bare BOUGHT",
    text:find("BOUGHT & USED", 1, true) ~= nil, text)

  reset()
  local blueprint = joker_card("j_blueprint", "Blueprint")
  G.shop_jokers = area({ blueprint })
  G.FUNCS.buy_from_shop = function()
    table.remove(G.shop_jokers.cards, 1)
    G.jokers.cards[1] = blueprint
    return true
  end
  local exec2 = ShopHandlers.handle_buy_from_shop({ area = "shop_jokers", index = 1 })
  if type(exec2) == "function" then exec2(); drain_events() end
  local q2 = G.NEURO.purchase_showcase_queue
  check("1j a plain buy still rides its own area tag",
    q2[1] and q2[1].area == "shop_jokers", q2[1] and q2[1].area)
end

do
  reset()
  local fool = tarot_card("c_fool", "The Fool")
  G.consumeables = area({ fool })
  G.GAME.hands = { Flush = { level = 3, visible = true } }
  local called = 0
  G.FUNCS.use_card = function()
    called = called + 1
    table.remove(G.consumeables.cards, 1)
    return true
  end
  local exec = UseCard.handle_use_card({ area = "consumeables", index = 1 })
  check("2a using a held consumable executes", type(exec) == "function", tostring(exec))
  if type(exec) == "function" then exec() end
  check("2b the engine callback ran exactly once", called == 1, called)
  local q = G.NEURO.purchase_showcase_queue
  check("2c a consumable use files exactly one receipt (it used to file none)", #q == 1, #q)
  check("2d the use receipt is tagged use", q[1] and q[1].area == "use", q[1] and q[1].area)
  check("2e the use receipt carries no price", q[1] and q[1].cost == 0, q[1] and q[1].cost)
  show_head(0)
  local ok, err, text = draw_text()
  check("2f the USED receipt draws", ok, err)
  check("2g the USED receipt prints the USED verb", text:find("USED", 1, true) ~= nil, text)
  check("2h with no effect yet the value line is the card name",
    text:find("The Fool", 1, true) ~= nil, text)

  reset()
  local fool2 = tarot_card("c_fool", "The Fool")
  G.consumeables = area({ fool2 })
  G.FUNCS.use_card = function() return false end
  local exec_bad = UseCard.handle_use_card({ area = "consumeables", index = 1 })
  if type(exec_bad) == "function" then exec_bad() end
  check("2i a declined use files no receipt", #G.NEURO.purchase_showcase_queue == 0,
    #G.NEURO.purchase_showcase_queue)
end

do
  reset()
  local mercury = tarot_card("c_mercury", "Mercury")
  G.consumeables = area({ mercury })
  G.GAME.hands = { Flush = { level = 3, visible = true }, Pair = { level = 1, visible = true } }
  G.FUNCS.use_card = function() table.remove(G.consumeables.cards, 1); return true end
  local exec = UseCard.handle_use_card({ area = "consumeables", index = 1 })
  if type(exec) == "function" then exec() end
  local q = G.NEURO.purchase_showcase_queue
  check("3a the use receipt carries the pre-use hand levels",
    q[1] and type(q[1].levels) == "table" and q[1].levels.Flush == 3,
    q[1] and q[1].levels and q[1].levels.Flush)
  show_head(0)
  check("3b nothing has levelled yet, so no effect line is invented",
    S.buy_showcase and S.buy_showcase.effect == nil, S.buy_showcase and S.buy_showcase.effect)
  G.GAME.hands.Flush.level = 5
  G.TIMERS.REAL = 0.4
  Showcase.update_buy(0.4)
  check("3c the effect resolves once the engine has applied it",
    S.buy_showcase and S.buy_showcase.effect == "Flush leveled up from 3 to 5",
    S.buy_showcase and tostring(S.buy_showcase.effect))
  local ok, err, text = draw_text()
  check("3d the effect receipt draws", ok, err)
  check("3e the value line shows the effect, not a price",
    text:find("Flush leveled up from 3 to 5", 1, true) ~= nil, text)
  G.GAME.hands.Flush.level = 9
  Showcase.update_buy(0.5)
  check("3f a resolved effect is frozen, not re-read every frame",
    S.buy_showcase.effect == "Flush leveled up from 3 to 5", S.buy_showcase.effect)

  check("3g several levelled hands collapse to a count",
    LevelDelta.brief({ A = { level = 2 }, B = { level = 2 } }, { A = 1, B = 1 })
      == "2 hands leveled up",
    LevelDelta.brief({ A = { level = 2 }, B = { level = 2 } }, { A = 1, B = 1 }))
  check("3h no snapshot means no effect", LevelDelta.brief({ A = { level = 2 } }, nil) == nil)
  local msg = LevelDelta.brief({ Flush = { level = 2, visible = true } }, { Flush = 1 }) .. "."
  check("3i the context sentence is unchanged", msg == "Flush leveled up from 1 to 2.", msg)
end

do
  reset()
  local bp = joker_card("j_blueprint", "Blueprint")
  G.shop_jokers = area({ bp })
  G.GAME.dollars = 2
  ShopHandlers.handle_buy_from_shop({ area = "shop_jokers", index = 1 })
  check("4a0 a preflight with no action id files nothing",
    #G.NEURO.purchase_showcase_queue == 0, #G.NEURO.purchase_showcase_queue)
  G.NEURO._candidate_probe = true
  ShopHandlers.handle_buy_from_shop({ area = "shop_jokers", index = 1, _action_id = "probe" })
  G.NEURO._candidate_probe = nil
  check("4a1 a candidate probe files nothing either",
    #G.NEURO.purchase_showcase_queue == 0, #G.NEURO.purchase_showcase_queue)
  local rej, rej_err = ShopHandlers.handle_buy_from_shop(
    { area = "shop_jokers", index = 1, _action_id = "a1" })
  check("4a an unaffordable buy is still rejected",
    rej == nil and type(rej_err) == "table" and rej_err.reason_code == "INSUFFICIENT_FUNDS",
    rej_err and rej_err.reason_code)
  local q = G.NEURO.purchase_showcase_queue
  check("4b the refusal reaches the column", #q == 1 and q[1].area == "refused",
    #q .. "/" .. tostring(q[1] and q[1].area))
  check("4c the refusal names the price it could not pay", q[1] and q[1].cost == 6, q[1] and q[1].cost)
  show_head(0)
  local ok, err, text = draw_text()
  check("4d the refusal receipt draws", ok, err)
  check("4e the refusal reads as CAN'T AFFORD", text:find("CAN'T AFFORD", 1, true) ~= nil, text)
  check("4f the refusal still shows the card it reached for",
    text:find("Blueprint", 1, true) ~= nil, text)

  reset()
  check("4f0 a refusal with no action id is never a beat",
    Showcase.enqueue_refusal({ code = "NO_SLOT", name = "Blueprint", cost = 6 }) == false)
  check("4g protocol noise never enqueues",
    Showcase.enqueue_refusal({ code = "STALE_TARGET", name = "Blueprint", action_id = "a" }) == false
      and Showcase.enqueue_refusal({ code = "TARGET_UNAVAILABLE", name = "Blueprint", action_id = "a" }) == false
      and #G.NEURO.purchase_showcase_queue == 0, #G.NEURO.purchase_showcase_queue)

  reset()
  check("4h the first refusal is admitted",
    Showcase.enqueue_refusal({ code = "INSUFFICIENT_FUNDS", name = "Blueprint", cost = 6, action_id = "a" }) == true)
  S.buy_showcase = nil
  G.NEURO.purchase_showcase_queue = {}
  G.TIMERS.REAL = 0.1
  check("4i an immediate retry of the same refusal is dropped",
    Showcase.enqueue_refusal({ code = "INSUFFICIENT_FUNDS", name = "Blueprint", cost = 6, at = 0.1, action_id = "a" })
      == false and #G.NEURO.purchase_showcase_queue == 0)
  check("4j a different target inside the global gap is dropped too",
    Showcase.enqueue_refusal({ code = "INSUFFICIENT_FUNDS", name = "Baron", cost = 8, at = 0.1, action_id = "a" })
      == false)
  check("4k a different target after the global gap is admitted",
    Showcase.enqueue_refusal({ code = "INSUFFICIENT_FUNDS", name = "Baron", cost = 8,
      at = Showcase.REFUSAL_GAP + 0.01, action_id = "a" }) == true)
  G.NEURO.purchase_showcase_queue = {}
  check("4l the same target is still gated after the global gap",
    Showcase.enqueue_refusal({ code = "INSUFFICIENT_FUNDS", name = "Blueprint", cost = 6,
      at = Showcase.REFUSAL_COOLDOWN - 0.01, action_id = "a" }) == false)
  check("4m the per-target gate expires with the cooldown",
    Showcase.enqueue_refusal({ code = "INSUFFICIENT_FUNDS", name = "Blueprint", cost = 6,
      at = Showcase.REFUSAL_COOLDOWN + 0.01, action_id = "a" }) == true)

  reset()
  Showcase.enqueue_purchase({ card = nil, name = "Baron", cost = 8, area = "shop_jokers", at = 0 })
  check("4n a refusal is dropped while a real receipt is pending",
    Showcase.enqueue_refusal({ code = "NO_SLOT", name = "Blueprint", cost = 6, at = 0, action_id = "a" }) == false
      and #G.NEURO.purchase_showcase_queue == 1, #G.NEURO.purchase_showcase_queue)
end

do
  reset()
  local a, b = joker_card("j_a", "Alpha"), joker_card("j_b", "Beta")
  G.jokers = area({ a, b })
  Showcase.update_joker(0)
  check("5a a steady row files nothing", #G.NEURO.purchase_showcase_queue == 0)
  table.remove(G.jokers.cards, 1)
  Showcase.update_joker(0.1)
  check("5b an absence younger than the confirm window files nothing",
    #G.NEURO.purchase_showcase_queue == 0, #G.NEURO.purchase_showcase_queue)
  Showcase.update_joker(0.1 + Showcase.LOST_CONFIRM)
  local q = G.NEURO.purchase_showcase_queue
  check("5c a confirmed absence files one LOST", #q == 1 and q[1].area == "lost",
    #q .. "/" .. tostring(q[1] and q[1].area))
  check("5d the LOST receipt names the joker", q[1] and q[1].name == "Alpha", q[1] and q[1].name)
  show_head(1)
  local ok, err, text = draw_text()
  check("5e the LOST receipt draws", ok, err)
  check("5f the LOST receipt prints the LOST verb", text:find("LOST", 1, true) ~= nil, text)

  reset()
  local c1, c2 = joker_card("j_a", "Alpha"), joker_card("j_b", "Beta")
  G.jokers = area({ c1, c2 })
  Showcase.update_joker(0)
  local rebuilt = joker_card("j_a", "Alpha")
  rebuilt.sort_id = c1.sort_id
  G.jokers.cards = { c2, rebuilt }
  Showcase.update_joker(0.1)
  Showcase.update_joker(1.0)
  check("5g a reorder with rebuilt tables files no LOST",
    #G.NEURO.purchase_showcase_queue == 0, #G.NEURO.purchase_showcase_queue)

  reset()
  local d1, d2 = joker_card("j_a", "Alpha"), joker_card("j_b", "Beta")
  G.jokers = area({ d1, d2 })
  Showcase.update_joker(0)
  G.jokers.cards = { d2 }
  Showcase.update_joker(0.1)
  G.jokers.cards = { d1, d2 }
  Showcase.update_joker(0.3)
  Showcase.update_joker(2.0)
  check("5h a healed absence files no LOST",
    #G.NEURO.purchase_showcase_queue == 0, #G.NEURO.purchase_showcase_queue)

  local function mock_delayed_sell(sold_card, area_ref)
    G.FUNCS.sell_card = function()
      G.E_MANAGER:add_event(Event({ func = function()
        for i, c in ipairs(area_ref.cards) do
          if c == sold_card then table.remove(area_ref.cards, i) break end
        end
        return true
      end }))
      return true
    end
  end

  reset()
  local sold_i = joker_card("j_si", "Sold Ambig")
  local keep_i = joker_card("j_ki", "Keeper")
  G.jokers = area({ sold_i, keep_i })
  Showcase.update_joker(0)
  mock_delayed_sell(sold_i, G.jokers)
  G.NEURO.run_generation = 1
  G.NEURO._candidate_probe = true -- bypass the CONFIRMATION_REQUIRED handshake, unrelated to this fix
  local exec_i = ShopHandlers.handle_sell_card({ area = "jokers", index = 1, _action_id = "a-ambig" })
  G.NEURO._candidate_probe = nil
  check("5i0 a dispatched sell executes", type(exec_i) == "function", tostring(exec_i))
  local receipt_i = exec_i()
  check("5i1 a dispatched sell files a receipt, not an inline result",
    ActionReceipt.is_receipt(receipt_i), tostring(receipt_i))
  ActionReceipt.transition(receipt_i, "acknowledged")
  ActionReceipt.transition(receipt_i, "executing")
  ActionReceipt.transition(receipt_i, "verifying")
  ActionReceipt.update(ActionReceipt.now(), 1)
  check("5i2 the card has not left the row yet (engine still animating)",
    receipt_i.phase == "verifying", receipt_i.phase)
  G.NEURO.run_generation = 2 -- a fresh transport session bumps run_generation mid-sale
  ActionReceipt.update(ActionReceipt.now(), 2)
  check("5i3 the generation bump ends the receipt ambiguous", receipt_i.phase == "ambiguous", receipt_i.phase)
  check("5i4 an ambiguous receipt never files SOLD",
    #G.NEURO.purchase_showcase_queue == 0, #G.NEURO.purchase_showcase_queue)
  drain_events() -- now the engine actually finishes the dissolve and removes the card
  check("5i5 the card has now genuinely left the row", #G.jokers.cards == 1, #G.jokers.cards)
  Showcase.update_joker(0.2)
  Showcase.update_joker(1.0)
  check("5i6 the sold joker files no LOST despite the ambiguous receipt",
    #G.NEURO.purchase_showcase_queue == 0, #G.NEURO.purchase_showcase_queue)

  reset()
  local sold_j = joker_card("j_sj", "Sold Deadline")
  G.jokers = area({ sold_j })
  Showcase.update_joker(0)
  mock_delayed_sell(sold_j, G.jokers)
  G.NEURO.run_generation = 1
  G.TIMERS.REAL = 0
  G.NEURO._candidate_probe = true
  local exec_j = ShopHandlers.handle_sell_card({ area = "jokers", index = 1, _action_id = "a-deadline" })
  G.NEURO._candidate_probe = nil
  local receipt_j = exec_j()
  check("5j0 a dispatched sell files a receipt", ActionReceipt.is_receipt(receipt_j), tostring(receipt_j))
  ActionReceipt.transition(receipt_j, "acknowledged")
  ActionReceipt.transition(receipt_j, "executing")
  ActionReceipt.transition(receipt_j, "verifying")
  G.TIMERS.REAL = 3.1 -- past the receipt's own 3s deadline; the card still has not left the area
  ActionReceipt.update(ActionReceipt.now(), 1)
  check("5j1 the deadline ends the receipt failed", receipt_j.phase == "failed", receipt_j.phase)
  check("5j2 a deadline-failed receipt never files SOLD",
    #G.NEURO.purchase_showcase_queue == 0, #G.NEURO.purchase_showcase_queue)
  drain_events()
  Showcase.update_joker(3.3)
  Showcase.update_joker(3.9)
  check("5j3 the sold joker files no LOST despite the deadline timeout",
    #G.NEURO.purchase_showcase_queue == 0, #G.NEURO.purchase_showcase_queue)

  reset()
  local sold_k = joker_card("j_sk", "Sold Applied")
  G.jokers = area({ sold_k })
  Showcase.update_joker(0)
  G.FUNCS.sell_card = function() table.remove(G.jokers.cards, 1); return true end
  G.NEURO.run_generation = 1
  G.NEURO._candidate_probe = true
  local exec_k = ShopHandlers.handle_sell_card({ area = "jokers", index = 1, _action_id = "a-applied" })
  G.NEURO._candidate_probe = nil
  local receipt_k = exec_k()
  ActionReceipt.transition(receipt_k, "acknowledged")
  ActionReceipt.transition(receipt_k, "executing")
  ActionReceipt.transition(receipt_k, "verifying")
  ActionReceipt.update(ActionReceipt.now(), 1)
  check("5k0 an applied receipt reaches applied", receipt_k.phase == "applied", receipt_k.phase)
  local qk = G.NEURO.purchase_showcase_queue
  check("5k1 the applied sale files exactly one SOLD", #qk == 1 and qk[1].area == "sell",
    #qk .. "/" .. tostring(qk[1] and qk[1].area))
  Showcase.update_joker(0.2)
  Showcase.update_joker(1.0)
  check("5k2 the sold joker never gets a second LOST receipt",
    #G.NEURO.purchase_showcase_queue == 1, #G.NEURO.purchase_showcase_queue)

  reset()
  local t1, t2, t3 = joker_card("j_1", "One"), joker_card("j_2", "Two"), joker_card("j_3", "Three")
  G.jokers = area({ t1, t2, t3 })
  Showcase.update_joker(0)
  G.jokers.cards = {}
  Showcase.update_joker(0.1)
  Showcase.update_joker(2.0)
  check("5l a whole-row teardown files nothing",
    #G.NEURO.purchase_showcase_queue == 0, #G.NEURO.purchase_showcase_queue)

  reset()
  local m1, m2 = joker_card("j_a", "Alpha"), joker_card("j_b", "Beta")
  G.jokers = area({ m1, m2 })
  Showcase.update_joker(0)
  G.STAGE = 1
  G.jokers.cards = { m2 }
  Showcase.update_joker(0.1)
  Showcase.update_joker(2.0)
  check("5m no loss beats outside a live run",
    #G.NEURO.purchase_showcase_queue == 0, #G.NEURO.purchase_showcase_queue)

  reset()
  local g1, g2 = joker_card("j_a", "Alpha"), joker_card("j_b", "Beta")
  G.jokers = area({ g1, g2 })
  Showcase.update_joker(0)
  G.STATE = 4
  G.jokers.cards = { g2 }
  Showcase.update_joker(0.1)
  Showcase.update_joker(2.0)
  check("5m2 a game over files no loss",
    #G.NEURO.purchase_showcase_queue == 0, #G.NEURO.purchase_showcase_queue)

  reset()
  local p1, p2 = joker_card("j_a", "Alpha"), joker_card("j_b", "Beta")
  G.jokers = area({ p1, p2 })
  Showcase.update_joker(0)
  G.NEURO.dev_preview_active = true
  G.jokers.cards = { p2 }
  Showcase.update_joker(0.1)
  Showcase.update_joker(2.0)
  G.NEURO.dev_preview_active = nil
  G.jokers.cards = { p1, p2 }
  Showcase.update_joker(2.1)
  check("5n the design harness swapping areas files no loss",
    #G.NEURO.purchase_showcase_queue == 0, #G.NEURO.purchase_showcase_queue)

  reset()
  local anon = joker_card("j_x", "Anon")
  anon.sort_id = nil
  G.jokers = area({ anon, joker_card("j_y", "Other") })
  Showcase.update_joker(0)
  G.jokers.cards = { G.jokers.cards[2] }
  Showcase.update_joker(2.0)
  check("5o an unidentifiable joker is never declared lost",
    #G.NEURO.purchase_showcase_queue == 0, #G.NEURO.purchase_showcase_queue)
end

do
  reset()
  for i = 1, Showcase.PURCHASE_QUEUE_CAP + 3 do
    Showcase.enqueue_purchase({ name = "P" .. i, cost = i, area = "shop_jokers", at = 0 })
  end
  local q = G.NEURO.purchase_showcase_queue
  check("6a the queue holds the cap", #q == Showcase.PURCHASE_QUEUE_CAP, #q)
  check("6b the merged count survives", q[1].merged == 3, q[1].merged)
  check("6c the head keeps its own price", q[1].cost == 4, q[1].cost)
  check("6c2 the folded money survives on the chip, not on the head",
    q[1].merged_spend == 1 + 2 + 3 and q[1].merged_gain == nil,
    tostring(q[1].merged_spend) .. "/" .. tostring(q[1].merged_gain))

  reset()
  Showcase.enqueue_purchase({ name = "Sold", cost = 5, area = "sell", at = 0 })
  for i = 1, Showcase.PURCHASE_QUEUE_CAP do
    Showcase.enqueue_purchase({ name = "B" .. i, cost = 10, area = "shop_jokers", at = 0 })
  end
  local q2 = G.NEURO.purchase_showcase_queue
  check("6d a sale folded into a purchase never changes what the purchase cost",
    q2[1].cost == 10, q2[1].cost)
  check("6e the folded sale is kept as a gain, told apart from spend",
    q2[1].merged == 1 and q2[1].merged_gain == 5 and q2[1].merged_spend == nil,
    tostring(q2[1].merged) .. "/" .. tostring(q2[1].merged_gain)
      .. "/" .. tostring(q2[1].merged_spend))

  reset()
  Showcase.enqueue_purchase({ name = "Grabber", cost = 1, area = "shop_vouchers", at = 0 })
  for i = 1, Showcase.PURCHASE_QUEUE_CAP do
    Showcase.enqueue_purchase({ name = "J" .. i, cost = 10, area = "shop_jokers", at = 0 })
  end
  local q3 = G.NEURO.purchase_showcase_queue
  check("6e2 a folded purchase never inflates the price of the card that survived it",
    q3[1].name == "J1" and q3[1].cost == 10, tostring(q3[1].name) .. "/" .. tostring(q3[1].cost))
  check("6e3 and the voucher's own dollar is accounted on the chip",
    q3[1].merged_spend == 1, tostring(q3[1].merged_spend))

  reset()
  for i = 1, Showcase.PURCHASE_QUEUE_CAP + 5 do
    Showcase.enqueue_purchase({ name = "C" .. i, cost = 2, area = "shop_jokers", at = 0 })
  end
  local q4 = G.NEURO.purchase_showcase_queue
  check("6e4 a chained merge carries every folded dollar forward",
    q4[1].merged == 5 and q4[1].merged_spend == 5 * 2,
    tostring(q4[1].merged) .. "/" .. tostring(q4[1].merged_spend))

  check("6f a spend and a gain are told apart",
    Showcase.money_direction("shop_jokers") == "spend"
      and Showcase.money_direction("sell") == "gain"
      and Showcase.money_direction("use") == "none"
      and Showcase.money_direction("refused") == "none")
end

do
  local PRODUCED = { "shop_jokers", "shop_vouchers", "shop_booster", "shop", "booster_pick",
    "shop_use", "use", "lost", "refused", "sell" }
  for _, tag in ipairs(PRODUCED) do
    local m = Acquire.MORPH_AREAS[tag] == true
    local r = Acquire.RECEIPT_ONLY[tag] == true
    check("7 " .. tag .. " is routed by exactly one verb set", (m or r) and not (m and r),
      tostring(m) .. "/" .. tostring(r))
  end
  check("7 negative beats can never morph",
    Acquire.RECEIPT_ONLY.refused == true and Acquire.RECEIPT_ONLY.lost == true)
  check("7 the pack cinematic owns its own beat",
    Acquire.RECEIPT_ONLY.shop_booster == true)
end

reset()
done()
