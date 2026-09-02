
local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 7 end,
  getHeight = function() return 13 end,
}
local function noop() end
local IMG = { getWidth = function() return 71 end, getHeight = function() return 95 end,
  getDimensions = function() return 71, 95 end }
local gfxstub = setmetatable({
  getFont = function() return FONT end,
  newFont = function() return FONT end,
  getWidth = function() return 1280 end,
  getHeight = function() return 720 end,
  getShader = function() return nil end,
  getBlendMode = function() return "alpha", "alphamultiply" end,
  newQuad = function() return {} end,
  newImage = function() return IMG end,
  newMesh = function() return {} end,
  getScissor = function() return nil end,
}, { __index = function() return noop end })
love = setmetatable({
  graphics = gfxstub,
  timer = { getTime = function() return 0 end, getFPS = function() return 144 end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

local area = require("tests.helpers").area
_G.G = {
  NEURO = { persona = "hiyori", state = "SHOP", enabled = true, purchase_showcase_queue = {},
    last_action_at = 0, run_generation = 1,
    ai_highlighted = setmetatable({}, { __mode = "k" }) },
  GAME = { dollars = 40, pack_choices = 0, round = 1, round_resets = { ante = 1, blind_choices = {} },
    blind = {}, used_vouchers = {}, modifiers = {} },
  jokers = area({}), consumeables = area({}), hand = area({}),
  shop_jokers = area({}), shop_vouchers = area({}), shop_booster = area({}),
  FUNCS = {}, TIMERS = { REAL = 0 }, STATES = {},
  SETTINGS = { paused = false, GAMESPEED = 1 },
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
  ARGS = {}, P_CENTERS = {}, P_CENTER_POOLS = {}, P_BLINDS = {}, localization = {},
  ASSET_ATLAS = {}, SHADERS = {}, TILESCALE = 3.65, TILESIZE = 20, CANV_SCALE = 1,
  I = { MOVEABLE = {}, UIBOX = {}, NODE = {} },
}
_G.SMODS = { current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end }
_G.NFS = setmetatable({}, { __index = function() return noop end })

local check, done = require("tests.helpers").harness("voucher showcase and drawer hand-off")

local Config = require("core.config")
Config.init({ settings = {}, colours = {} }, function() return true end)

local queued_events = {}
_G.Event = function(cfg) return cfg end
local EMANAGER = { add_event = function(_, e) queued_events[#queued_events + 1] = e end }
local function drain_events()
  local list = queued_events
  queued_events = {}
  for _, e in ipairs(list) do if e.func then e.func() end end
end

local Prims = require("hud.prims")
local Motion = Prims.Motion
local S = require("hud.state")
local Showcase = require("hud.showcase")
local Vouchers = require("hud.vouchers")
local ShopHandlers = require("handlers.shop_handlers")

local DT = 1 / 60

local function voucher_card(key, name)
  return {
    config = { center = { key = key, set = "Voucher", name = name,
      loc_txt = { name = name, text = { "Effect of " .. name } } } },
    ability = { name = name, set = "Voucher" },
    cost = 10,
  }
end
local function joker_card(key, name)
  return {
    config = { center = { key = key, set = "Joker", name = name, loc_txt = { name = name },
      rarity = 1 } },
    ability = { name = name, set = "Joker" },
    cost = 4,
  }
end

local function reset_all()
  Showcase.reset_run_state()
  G.NEURO.purchase_showcase_queue = {}
  G.NEURO.last_action_at = 0
  G.GAME.used_vouchers = {}
  G.GAME.dollars = 40
  G.E_MANAGER = EMANAGER
  queued_events = {}
  S.known_voucher_keys = nil
  S.voucher_game_ref = nil
  S.voucher_order, S.voucher_anim = {}, {}
  S.voucher_count_pulse_at = 0
end

local function redeem(card, key)
  G.shop_vouchers = area({ card })
  G.FUNCS.use_card = function()
    G.GAME.used_vouchers[key] = true
    for i, c in ipairs(G.shop_vouchers.cards) do
      if c == card then table.remove(G.shop_vouchers.cards, i) break end
    end
    return true
  end
  local _, review = ShopHandlers.handle_buy_from_shop({ area = "shop_vouchers", index = 1 })
  local CR = require("core.context_review")
  if review and review.context_review_candidate then
    CR.stage(review.context_review_candidate, { status = "written" })
    CR.step_delivery()
  end
  local exec = ShopHandlers.handle_buy_from_shop({ area = "shop_vouchers", index = 1 })
  if type(exec) ~= "function" then return nil, tostring(exec) end
  exec()
  drain_events()
  return true
end

do
  reset_all()
  local card = voucher_card("v_grabber", "Grabber")
  local ok, err = redeem(card, "v_grabber")
  check("1a the redemption executes", ok == true, err)
  local q = G.NEURO.purchase_showcase_queue
  check("1b exactly one buy toast is queued", type(q) == "table" and #q == 1, q and #q)
  check("1c the toast is tagged shop_vouchers", q[1] and q[1].area == "shop_vouchers",
    q[1] and q[1].area)
  check("1d exactly one showcase is queued", #S.joker_showcase_q == 1, #S.joker_showcase_q)
  check("1e the showcase and the toast carry the identical card table",
    S.joker_showcase_q[1] and q[1] and S.joker_showcase_q[1].card == q[1].card
    and S.joker_showcase_q[1].card == card)
  check("1f the showcase is labelled VOUCHER",
    S.joker_showcase_q[1] and S.joker_showcase_q[1].label == "VOUCHER",
    S.joker_showcase_q[1] and S.joker_showcase_q[1].label)
  check("1g the redeemed voucher reaches neither joker nor consumable slots",
    #G.jokers.cards == 0 and #G.consumeables.cards == 0)
  Showcase.update_joker(0)
  check("1h the ref diff alone would have produced nothing for it",
    S.joker_showcase ~= nil and S.joker_showcase.card == card)
end

do
  reset_all()
  local card = joker_card("j_blueprint", "Blueprint")
  G.shop_jokers = area({ card })
  Showcase.update_joker(0)  -- empty joker row observed before the buy, as in a live shop
  G.FUNCS.buy_from_shop = function()
    table.remove(G.shop_jokers.cards, 1)
    G.jokers.cards[#G.jokers.cards + 1] = card
    return true
  end
  local exec = ShopHandlers.handle_buy_from_shop({ area = "shop_jokers", index = 1 })
  check("2a the joker buy executes", type(exec) == "function", tostring(exec))
  if type(exec) == "function" then exec(); drain_events() end
  check("2b a joker buy queues no voucher showcase", #S.joker_showcase_q == 0, #S.joker_showcase_q)
  check("2c a joker buy sets no drawer gate", next(S.voucher_drawer_gate) == nil)
  check("2d the joker still arrives through the ref diff",
    (function()
      Showcase.update_joker(0)
      return S.joker_showcase ~= nil and S.joker_showcase.card == card
    end)())
end

do
  reset_all()
  local card = voucher_card("v_grabber", "Grabber")
  Showcase.enqueue_voucher(card, 100)
  local gv = S.voucher_drawer_gate.v_grabber
  check("3a the redemption arms a gate carrying its own card", gv and gv.card == card)
  check("3b the gate is in flight immediately (queued, not yet handed off)",
    Showcase.card_in_flight(card) == true)
  check("3c a card that was never enqueued is never in flight",
    Showcase.card_in_flight(voucher_card("v_other", "Other")) == false)
  check("3d card_in_flight(nil) is false, not an error", Showcase.card_in_flight(nil) == false)

  local stranger = voucher_card("v_stranger", "Stranger")
  S.buy_showcase = { card = stranger, started = 100, area = "shop_vouchers" }
  S.joker_showcase = { card = stranger, label = "VOUCHER", started = 100 }
  check("3e occupying the live slots by hand claims nothing",
    Showcase.card_in_flight(stranger) == false)
  S.buy_showcase, S.joker_showcase = nil, nil

  local now, retired_at = 100, nil
  while now < 130 and not retired_at do
    Showcase.update_joker(now)
    if not Showcase.card_in_flight(card) then retired_at = now end
    now = now + DT
  end
  check("3f the corridor holds the card for its presentation and not one tick longer",
    retired_at ~= nil
    and retired_at > 100 + Showcase.JOKER_SHOWCASE_MIN
    and retired_at <= 100 + Showcase.JOKER_SHOWCASE_DURATION + DT * 2, tostring(retired_at))
  check("3f2 the corridor is empty once it has published the retirement",
    S.joker_showcase == nil and #S.joker_showcase_q == 0)
  check("3f3 and the gate carries the instant it was released, so the drawer never has to poll",
    gv.release_at ~= nil and math.abs(gv.release_at - (retired_at or 0)) <= DT,
    tostring(gv.release_at))

  check("3g a card with no centre key arms nothing",
    Showcase.enqueue_voucher({ config = { center = {} } }, 100) == false)
  check("3h a nil card arms nothing", Showcase.enqueue_voucher(nil, 100) == false)
end

do
  reset_all()
  Vouchers.update(0, nil, 1280, 720)
  local shared = voucher_card("v_seed_money", "Seed Money")
  Showcase.enqueue_purchase({ card = shared, name = "Seed Money", cost = 10,
    area = "shop_vouchers", at = 0 })
  Showcase.enqueue_voucher(shared, 0)
  G.GAME.used_vouchers.v_seed_money = true
  Vouchers.update(0.1, nil, 1280, 720)
  check("3i a hand-off with nothing published yet holds the drawer", #S.voucher_order == 0,
    #S.voucher_order)
  S.voucher_drawer_gate.v_seed_money.release_at = 0.2
  Vouchers.update(0.2, nil, 1280, 720)
  check("3j a published release files the voucher, though the receipt lane still holds the card",
    #S.voucher_order == 1 and Showcase.card_in_flight(shared) == true,
    #S.voucher_order .. "/" .. tostring(Showcase.card_in_flight(shared)))

  reset_all()
  Vouchers.update(0, nil, 1280, 720)
  local orphan = voucher_card("v_hush", "Hush")
  G.GAME.used_vouchers.v_hush = true
  S.voucher_drawer_gate.v_hush = { card = orphan,
    safety_at = Showcase.VOUCHER_DRAWER_SAFETY }
  Vouchers.update(0.1, nil, 1280, 720)
  check("3k and an unpublished one holds it even though no lane holds the card",
    #S.voucher_order == 0 and Showcase.card_in_flight(orphan) == false,
    #S.voucher_order .. "/" .. tostring(Showcase.card_in_flight(orphan)))
end

local function run_release(t0, t1, redeem_at, card, key)
  local tr = {}
  local now = t0
  while now <= t1 + 1e-9 do
    G.TIMERS.REAL = now
    if redeem_at and not tr.redeem_at and now >= redeem_at - 1e-9 then
      tr.redeem_at = now
      tr.redeem_ok = redeem(card, key)
    end
    Showcase.update_buy(now)
    Showcase.update_joker(now)
    local gv = S.voucher_drawer_gate[key]
    if gv and not tr.ceiling_at and now >= (gv.safety_at or math.huge) then tr.ceiling_at = now end
    if tr.redeem_at and not tr.retire_at and not Showcase.card_in_flight(card) then
      tr.retire_at = now
    end
    Vouchers.update(now, nil, 1280, 720)
    if not tr.file_at and #S.voucher_order > 0 then tr.file_at = now end
    now = now + DT
  end
  return tr
end

do
  reset_all()
  Vouchers.update(0, nil, 1280, 720)  -- first observation seeds an empty shelf
  local card = voucher_card("v_grabber", "Grabber")
  local tr = run_release(0, 12.0, 0.5, card, "v_grabber")
  check("4a the redemption runs through the real handler", tr.redeem_ok == true)
  check("4b the corridor retires the card exactly once, well before the stall ceiling",
    tr.retire_at ~= nil and tr.retire_at < 0.5 + Showcase.VOUCHER_DRAWER_SAFETY,
    tostring(tr.retire_at))
  check("4c the tray stays empty for the whole hold",
    tr.file_at ~= nil and tr.file_at >= (tr.retire_at or 0) - DT, tostring(tr.file_at))
  check("4d and files it in the frame the corridor publishes the retirement",
    tr.file_at ~= nil and tr.file_at <= (tr.retire_at or 0) + DT * 2, tostring(tr.file_at))
  check("4e the stall ceiling never fired", tr.ceiling_at == nil, tostring(tr.ceiling_at))
  check("4f the gate is consumed once it has been honoured",
    S.voucher_drawer_gate.v_grabber == nil)
  check("4g the shelf holds exactly the redeemed voucher", #S.voucher_order == 1, #S.voucher_order)
  check("4h it arrives as an acquisition, not as a silent seed",
    S.voucher_anim.v_grabber ~= nil
    and math.abs(S.voucher_anim.v_grabber.at - tr.file_at) < 1e-9)
  check("4i the count pulses with the arrival, not with the redemption",
    S.voucher_count_pulse_at > 0 and math.abs(S.voucher_count_pulse_at - tr.file_at) < 1e-9,
    tostring(S.voucher_count_pulse_at))
end

do
  reset_all()
  Vouchers.update(0, nil, 1280, 720)
  G.jokers = area({})
  Showcase.update_joker(0)                       -- seed the ref diff on an empty row
  G.jokers.cards = { joker_card("j_1", "One"), joker_card("j_2", "Two") }
  Showcase.update_joker(DT)                      -- two real gains queue ahead of the redemption
  check("4j precondition: two showcases are queued ahead",
    (S.joker_showcase ~= nil and 1 or 0) + #S.joker_showcase_q == 2,
    #S.joker_showcase_q)
  local card = voucher_card("v_grabber", "Grabber")
  local tr = run_release(DT, 20.0, 0.5, card, "v_grabber")
  check("4k a redemption two deep still hands off inside the ceiling",
    tr.retire_at ~= nil and (tr.retire_at - 0.5) < Showcase.VOUCHER_DRAWER_SAFETY,
    tostring(tr.retire_at and (tr.retire_at - 0.5)))
  check("4l and the whole backlog costs one budget, not one span per card",
    tr.retire_at ~= nil
    and (tr.retire_at - 0.5) <= Showcase.JOKER_SHOWCASE_BUDGET + Showcase.JOKER_SHOWCASE_DURATION,
    tostring(tr.retire_at and (tr.retire_at - 0.5)))
  check("4m the ceiling never fired at depth", tr.ceiling_at == nil, tostring(tr.ceiling_at))
  check("4n the badge still waits for the card", tr.file_at ~= nil
    and tr.file_at >= (tr.retire_at or 0) - DT, tostring(tr.file_at))
end

do
  reset_all()
  Vouchers.update(0, nil, 1280, 720)
  G.GAME.used_vouchers.v_grabber = true
  Vouchers.update(0.5, nil, 1280, 720)
  check("5a an ungated redemption files immediately", #S.voucher_order == 1, #S.voucher_order)
end

do
  reset_all()
  Vouchers.update(0, nil, 1280, 720)
  G.GAME.used_vouchers.v_grabber = true
  Vouchers.update(0.1, nil, 1280, 720)
  check("6a precondition: the voucher is on the shelf", #S.voucher_order == 1)
  S.voucher_drawer_gate.v_grabber = { card = voucher_card("v_grabber", "Grabber"),
    safety_at = 0.2 + Showcase.VOUCHER_DRAWER_SAFETY }
  Vouchers.update(0.2, nil, 1280, 720)
  check("6b a late gate never withdraws a filed voucher", #S.voucher_order == 1,
    #S.voucher_order)
  check("6c and the stale gate is dropped", S.voucher_drawer_gate.v_grabber == nil)

  reset_all()
  local ghost = voucher_card("v_ghost", "Ghost")
  Showcase.enqueue_voucher(ghost, 0)
  G.GAME.used_vouchers.v_ghost = true
  Vouchers.update(0, nil, 1280, 720)
  check("6d a live hand-off holds the drawer", #S.voucher_order == 0, #S.voucher_order)
  Vouchers.update(Showcase.VOUCHER_DRAWER_SAFETY - DT, nil, 1280, 720)
  check("6d2 and keeps holding right up to the ceiling", #S.voucher_order == 0, #S.voucher_order)
  check("6d3 the corridor never ticked, so the card is still in flight",
    Showcase.card_in_flight(ghost) == true)
  Vouchers.update(Showcase.VOUCHER_DRAWER_SAFETY + DT, nil, 1280, 720)
  check("6d4 a corridor that stopped ticking is released by the ceiling",
    #S.voucher_order == 1, #S.voucher_order)

  reset_all()
  Vouchers.update(0, nil, 1280, 720)
  G.jokers = area({})
  Showcase.update_joker(0)
  local filler = {}
  for i = 1, Showcase.SHOWCASE_QUEUE_CAP do filler[i] = joker_card("j_f" .. i, "Filler " .. i) end
  G.jokers.cards = filler
  Showcase.update_joker(DT)
  local card = voucher_card("v_full", "Full")
  local tr = run_release(DT, 30.0, 0.5, card, "v_full")
  check("6e a corridor loaded to the cap still hands off inside the ceiling",
    tr.retire_at ~= nil and (tr.retire_at - 0.5) < Showcase.VOUCHER_DRAWER_SAFETY,
    tostring(tr.retire_at and (tr.retire_at - 0.5)))
  check("6e2 so the ceiling never fires while the corridor runs", tr.ceiling_at == nil,
    tostring(tr.ceiling_at))

  reset_all()
  Vouchers.update(0, nil, 1280, 720)
  local held = voucher_card("v_frozen", "Frozen")
  Showcase.enqueue_voucher(held, 0)
  G.GAME.used_vouchers.v_frozen = true
  local now, filed_at = 0, nil
  while now < Showcase.VOUCHER_DRAWER_SAFETY * 2 do
    Showcase.update_joker(now)
    Showcase.note_stage_frozen(now)   -- the pack rows are covering the corridor, every frame
    Vouchers.update(now, nil, 1280, 720)
    if not filed_at and #S.voucher_order > 0 then filed_at = now end
    now = now + DT
  end
  check("6f a frozen corridor is not a stalled one: the ceiling never fires against it",
    filed_at == nil, tostring(filed_at))
  check("6f2 and the card is still in flight, which is why it must not have filed",
    Showcase.card_in_flight(held) == true)
  while now < Showcase.VOUCHER_DRAWER_SAFETY * 2 + 10 do
    Showcase.update_joker(now)        -- the pack is gone; nothing refreshes the freeze note
    Vouchers.update(now, nil, 1280, 720)
    if not filed_at and #S.voucher_order > 0 then filed_at = now end
    now = now + DT
  end
  check("6f3 once the pack lets go the corridor finishes and the drawer files",
    filed_at ~= nil and Showcase.card_in_flight(held) == false, tostring(filed_at))
end

do
  reset_all()
  Vouchers.update(0, nil, 1280, 720)
  G.jokers = area({})
  Showcase.update_joker(0)
  G.jokers.cards = { joker_card("j_greedy_joker", "Greedy Joker") }
  Showcase.update_joker(DT)
  check("8a precondition: an unrelated card owns the stage",
    S.joker_showcase ~= nil and S.joker_showcase.card ~= nil)

  local card = voucher_card("v_grabber", "Grabber")
  local tr = run_release(DT, 20.0, 0.05, card, "v_grabber")
  check("8b the drawer withholds the voucher while an unrelated card owns the stage",
    tr.retire_at ~= nil and tr.retire_at > 0.95, tostring(tr.retire_at))
  check("8c withheld for every frame of the hold, not merely past some fixed constant",
    tr.file_at ~= nil and tr.file_at >= tr.retire_at - DT,
    tostring(tr.file_at) .. "/" .. tostring(tr.retire_at))
  check("8d and filed in the frame the corridor releases it, not a moment later",
    tr.file_at ~= nil and tr.file_at <= tr.retire_at + DT * 2,
    tostring(tr.file_at) .. "/" .. tostring(tr.retire_at))
  check("8e one voucher on the shelf", #S.voucher_order == 1, #S.voucher_order)
end

do
  reset_all()
  Showcase.enqueue_voucher(voucher_card("v_grabber", "Grabber"), 100)
  check("9a precondition: a gate is armed", next(S.voucher_drawer_gate) ~= nil)
  Showcase.reset_run_state()
  check("9b reset clears the gates", next(S.voucher_drawer_gate) == nil)
  check("9c reset clears the queued voucher showcase", #S.joker_showcase_q == 0)
end

do
  reset_all()
  G.NEURO.state = "BUFFOON_PACK"
  local claimed = joker_card("j_claimed", "Claimed")
  Showcase.update_joker(0)
  Showcase.note_claimed(claimed, 0)
  G.jokers.cards[#G.jokers.cards + 1] = claimed
  Showcase.update_joker(0.05)
  check("10a a claimed card files no showcase while the pack is open",
    #S.pack_gained_q == 0 and #S.joker_showcase_q == 0 and S.joker_showcase == nil,
    #S.pack_gained_q .. "/" .. #S.joker_showcase_q)

  G.NEURO.state = "SHOP"
  Showcase.update_joker(0.10)
  check("10b and none is released when the pack closes",
    #S.joker_showcase_q == 0 and S.joker_showcase == nil,
    #S.joker_showcase_q .. "/" .. tostring(S.joker_showcase and S.joker_showcase.label))
end

do
  reset_all()
  G.NEURO.state = "BUFFOON_PACK"
  local claimed, spawned = joker_card("j_claimed", "Claimed"), joker_card("j_spawned", "Spawned")
  Showcase.update_joker(0)
  Showcase.note_claimed(claimed, 0)
  G.jokers.cards[#G.jokers.cards + 1] = claimed
  G.jokers.cards[#G.jokers.cards + 1] = spawned
  Showcase.update_joker(0.05)
  check("11a a card the cinematic never crowned is still announced",
    #S.pack_gained_q == 1, #S.pack_gained_q)
  check("11b and it is the uncrowned one",
    S.pack_gained_q[1] and S.pack_gained_q[1].card == spawned,
    S.pack_gained_q[1] and tostring(S.pack_gained_q[1].card and S.pack_gained_q[1].card.sort_id))

  G.NEURO.state = "SHOP"
  Showcase.update_joker(0.10)
  check("11c it plays once the pack closes", S.joker_showcase ~= nil
    and S.joker_showcase.card == spawned,
    tostring(S.joker_showcase and S.joker_showcase.card and S.joker_showcase.card.sort_id))
end

do
  reset_all()
  local card = joker_card("j_twice", "Twice")
  Showcase.update_joker(0)
  Showcase.note_claimed(card, 0)
  G.jokers.cards[1] = card
  Showcase.update_joker(0.05)
  check("12a the claim silences the gain it was filed for", S.joker_showcase == nil)

  G.jokers.cards = {}
  Showcase.update_joker(0.10)
  G.jokers.cards[1] = card
  Showcase.update_joker(0.15)
  check("12b a later gain of the same card is announced again",
    S.joker_showcase ~= nil and S.joker_showcase.card == card,
    tostring(S.joker_showcase and S.joker_showcase.label))

  reset_all()
  local stale = joker_card("j_stale", "Stale")
  Showcase.update_joker(0)
  Showcase.note_claimed(stale, 0)
  G.jokers.cards[1] = stale
  Showcase.update_joker(Showcase.CLAIM_GRACE + 1)
  check("12c a claim older than CLAIM_GRACE no longer silences anything",
    S.joker_showcase ~= nil and S.joker_showcase.card == stale,
    tostring(S.joker_showcase and S.joker_showcase.label))
end

do
  reset_all()
  local claimed = joker_card("j_rebuilt", "Rebuilt")
  claimed.sort_id = 4242
  Showcase.update_joker(0)
  Showcase.note_claimed(claimed, 0)
  local rebuilt = joker_card("j_rebuilt", "Rebuilt")   -- different table, same card
  rebuilt.sort_id = 4242
  G.jokers.cards[1] = rebuilt
  Showcase.update_joker(0.05)
  check("12d a rebuilt table with the same sort_id is still the claimed card",
    S.joker_showcase == nil and #S.pack_gained_q == 0,
    tostring(S.joker_showcase and S.joker_showcase.label))
end

do
  reset_all()
  local card = joker_card("j_reset", "Reset")
  Showcase.note_claimed(card, 0)
  Showcase.reset_run_state()
  Showcase.update_joker(0)
  G.jokers.cards[1] = card
  Showcase.update_joker(0.05)
  check("13 a run reset clears the claim ledger with everything else",
    S.joker_showcase ~= nil and S.joker_showcase.card == card,
    tostring(S.joker_showcase and S.joker_showcase.label))
end

do
  reset_all()
  G.GAME.used_vouchers.v_grabber = true
  Vouchers.update(0, nil, 1280, 720)
  local settled = S.drawer_h_current
  check("14a the first voucher's height lands in the same frame it is observed",
    settled ~= nil and settled > 0, tostring(settled))
  Vouchers.update(0.30, nil, 1280, 720)
  check("14b ten frames later the height has not moved",
    S.drawer_h_current == settled, tostring(S.drawer_h_current) .. " vs " .. tostring(settled))
end

do
  local GateClocks = require("core.gate_clocks")
  local Utils = require("util.utils")
  local gate = GateClocks.by_id["voucher_drawer_safety"]
  check("15a the drawer's stall ceiling is a classified timing gate", gate ~= nil, tostring(gate))
  check("15b owned by the file that arms it, and wired",
    gate ~= nil and gate.file == "hud/showcase.lua" and gate.wired == true,
    gate and (tostring(gate.file) .. "/" .. tostring(gate.wired)))
  check("15c on the clock the drawer is drawn against",
    gate ~= nil and gate.clock == GateClocks.REAL
      and Utils.gate_clock("voucher_drawer_safety") == GateClocks.REAL,
    gate and tostring(gate.clock))
end

do
  local source = assert(io.open("hud/vouchers.lua", "r")):read("*all")
  check("vouchers.lua carries no drawer extend/collapse ramp",
    source:find("EXT_D", 1, true) == nil
    and source:find("EXT_OVER_MAX", 1, true) == nil
    and source:find("drawer_ext_", 1, true) == nil)
end

done()
