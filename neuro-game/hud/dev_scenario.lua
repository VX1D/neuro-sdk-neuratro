local S = require("hud.state")
local Showcase = require("hud.showcase")
local Palette = require("render.palette")
local NeuroAnim = require("render.neuro-anim")
local StateKinds = require("core.state_kinds")
local Fixtures = require("hud.dev_fixtures")
local LevelDelta = require("util.level_delta")
local Acquire = require("render.panels.acquire")
local Pack = require("render.panels.pack")
local Utils = require("util.utils")

local DevScenario = { active = false }

DevScenario._hot_reload_locked = function() return DevScenario.active end

local _rate = 1
local _clock = { REAL = 0, TOTAL = 0 }
local _clock_live = nil
local _clk_real0, _clk_show0 = 0, 0

local function real_now()
  local t = _clock_live or (G and G.TIMERS)
  return (t and t.REAL) or 0
end

local function show_of(t)
  if _rate == 1 then return t end
  return _clk_show0 + (t - _clk_real0) * _rate
end

local function now()
  return show_of(real_now())
end

local function set_rate(r)
  if r == _rate then return end
  _clk_show0, _clk_real0 = now(), real_now()
  _rate = r
end

local function freeze_clock(at)
  _clk_show0, _clk_real0 = at, real_now()
  _rate = 0
  if _clock_live then
    _clock.REAL, _clock.TOTAL = at, at
  elseif G and G.TIMERS then
    _clock_live = G.TIMERS
    for k, v in pairs(_clock_live) do _clock[k] = v end
    _clock.REAL, _clock.TOTAL = at, at
    G.TIMERS = _clock
  end
end

local function thaw_clock(rate)
  if _rate ~= 0 then return end
  _clk_real0 = real_now()
  _rate = rate or 1
  if _clock_live then _clock.REAL, _clock.TOTAL = now(), now() end
end

local G_KEYS = {
  "GAME", "STAGE", "jokers", "consumeables", "shop_jokers", "shop_vouchers",
  "shop_booster", "pack_cards", "booster_pack", "hand", "play", "discard", "deck",
  "playing_cards",
}

local N_KEYS = {
  "state", "persona", "force_inflight", "seed_pasted",
  "ai_highlighted", "ai_glow", "login_anim", "egg", "reserved_dollars",
  "purchase_showcase_queue", "force_sent_at", "force_state", "action_phase",
  "last_action_name", "recent_actions", "dev_footer",
}

local HUD_KEEP = { new_state = true, invalidate_caches = true }

local _gstore, _nstore, _hud = nil, nil, nil
local _mounted, _dirty = false, true
local _world, _opts, _entered_at = nil, {}, 0
local _entered_pending = false
local _preset, _btn_hit = nil, {}
local _open, _tweak, _vp_saved = nil, false, nil

local _take_at, _take_n, _take_fired, _take_restart = 0, 0, false, true
local _tk, _added = {}, {}

local STATE_VALUES = {}
for i, name in ipairs(Fixtures.STATES) do STATE_VALUES[i] = { id = name, label = name } end

local PERSONA_VALUES = {}
do
  local keys = {}
  for k in pairs(Palette.PALETTES) do keys[#keys + 1] = k end
  table.sort(keys)
  for i, k in ipairs(keys) do PERSONA_VALUES[i] = { id = k, label = k } end
end

local EVENT_VALUES = {}
for i, e in ipairs(Fixtures.EVENTS) do EVENT_VALUES[i] = { id = e.id, label = e.label } end

local MENU_VALUES = { { id = "preview", label = "preview" }, { id = "strict", label = "strict" } }

local PINS_VALUES = {
  { id = "auto", label = "auto" },
  { id = "seed", label = "seed",   phase = 0 },
  { id = "pins", label = "pins",   phase = 1 },
  { id = "fast", label = "pins 1s", phase = 1, dur = 1.0 },
}

local VIEWPORT_VALUES = {
  { id = "native",   label = "native" },
  { id = "1280x720", label = "1280x720" },
  { id = "1366x768", label = "1366x768" },
  { id = "1024x768", label = "1024x768" },
}

local PLAY_VALUES = {
  { id = "loop", label = "loop" },
  { id = "once", label = "once" },
  { id = "hold", label = "hold" },
}

local SPEED_VALUES = {
  { id = "1x",  label = "1x",   rate = 1 },
  { id = "1/2", label = "1/2x", rate = 0.5 },
  { id = "1/4", label = "1/4x", rate = 0.25 },
  { id = "1/8", label = "1/8x", rate = 0.125 },
}

local BEAT_OFF = { id = "off", label = "off" }
local BEAT_SETS = {
  none = { BEAT_OFF },
  acquire = { BEAT_OFF,
    { id = "a_in",    label = "IN" },
    { id = "a_hold",  label = "HOLD" },
    { id = "a_morph", label = "MORPH" },
    { id = "a_full",  label = "FULL" },
    { id = "a_out",   label = "OUT" } },
  pack = { BEAT_OFF,
    { id = "p_anoint", label = "ANOINT" },
    { id = "p_glide",  label = "GLIDE" },
    { id = "p_shrink", label = "SHRINK" },
    { id = "p_hold",   label = "HOLD" },
    { id = "p_exit",   label = "EXIT" } },
  pack_multi = { BEAT_OFF,
    { id = "p_anoint",   label = "ANOINT" },
    { id = "p_glide",    label = "GLIDE" },
    { id = "p_refreeze", label = "REFREEZE" },
    { id = "p_shrink",   label = "SHRINK" },
    { id = "p_hold",     label = "HOLD" },
    { id = "p_exit",     label = "EXIT" } },
}

local AXES = {
  { id = "play",    label = "PLAY",     values = PLAY_VALUES,         default = "loop",
    tier = "main",  cycler = true, framing = true },
  { id = "speed",   label = "SPEED",    values = SPEED_VALUES,        default = "1x",
    tier = "main",  cycler = true, framing = true },
  { id = "persona", label = "PERSONA",  values = PERSONA_VALUES,      default = "neuro",
    tier = "main",  cycler = true, framing = true },
  { id = "state",   label = "STATE",    values = STATE_VALUES,        default = "SHOP",
    tier = "tweak" },
  { id = "event",   label = "EVENT",    values = EVENT_VALUES,        default = "none",
    tier = "tweak" },
  { id = "card",    label = "CARD",     values = Fixtures.CARD_KINDS, default = "joker",
    tier = "tweak" },
  { id = "mod",     label = "MOD",      values = Fixtures.MODIFIERS,  default = "none",
    tier = "tweak" },
  { id = "layout",  label = "LAYOUT",   values = Fixtures.LAYOUTS,    default = "few",
    tier = "tweak", cycler = true },
  { id = "viewport", label = "VIEWPORT", values = VIEWPORT_VALUES,    default = "native",
    tier = "tweak", cycler = true, framing = true },
  { id = "menu",    label = "MENU",     values = MENU_VALUES,         default = "preview",
    tier = "tweak", cycler = true },
  { id = "pins",    label = "PINS",     values = PINS_VALUES,         default = "auto",
    tier = "tweak", cycler = true },
  { id = "beat",    label = "BEAT",     values = BEAT_SETS.none,      default = "off",
    tier = "main",  cycler = true },
}

local MAIN_AXES, TWEAK_AXES = {}, {}
local AXIS = {}
local _sel = {}
for _, ax in ipairs(AXES) do
  ax.index_of = {}
  for i, v in ipairs(ax.values) do ax.index_of[v.id] = i end
  ax.default_i = ax.index_of[ax.default] or 1
  AXIS[ax.id] = ax
  _sel[ax.id] = ax.default_i
  local tier = (ax.tier == "main") and MAIN_AXES or TWEAK_AXES
  tier[#tier + 1] = ax
end

function DevScenario.axis(id) return AXIS[id] end

local function value_of(axis_id)
  local ax = AXIS[axis_id]
  return ax.values[_sel[axis_id]] or ax.values[1]
end

local ACQUIRE_VARIANTS = {
  { area = "shop",          name = "Greedy Joker", card = "greedy" },
  { area = "shop_jokers",   name = "Blueprint",    card = "blueprint" },
  { area = "booster_pick",  name = "The Fool",     card = "fool" },
  { area = "shop_vouchers", name = "Grabber",      card = "grabber" },
  { area = "shop_use",      name = "The Magician", card = "magician" },
  { area = "use",           name = "Jupiter",      card = "jupiter", leveled = true },
  { area = "use",           name = "The Fool",     card = "fool" },
  { area = "sell",          name = "Baron",        card = "baron" },
  { area = "lost",          name = "Gros Michel",  card = "gros_michel" },
  { area = "refused",       name = "Blueprint",    card = "blueprint",
    code = "INSUFFICIENT_FUNDS" },
  { area = "refused",       name = "Canio",        card = "canio",
    code = "NO_SLOT" },
}

DevScenario.ACQUIRE_VARIANTS = ACQUIRE_VARIANTS

local FREE_RECEIPT_AREAS = { booster_pick = true, use = true, lost = true }

local function receipt_cost(area_tag, card)
  if FREE_RECEIPT_AREAS[area_tag] then return 0 end
  if area_tag == "sell" then return card.sell_cost or 0 end
  return card.cost or 0
end

local DEAL = {
  { value = "Ace",   suit = "Spades" },   { value = "King",  suit = "Hearts" },
  { value = "10",    suit = "Diamonds" }, { value = "7",     suit = "Clubs" },
  { value = "3",     suit = "Hearts" },   { value = "Queen", suit = "Clubs" },
  { value = "5",     suit = "Diamonds" }, { value = "9",     suit = "Spades" },
}

local function playing_cards(n)
  local out = {}
  for i = 1, n do
    local d = DEAL[((i - 1) % #DEAL) + 1]
    out[i] = Fixtures.card({
      key = "c_base", set = "Default", name = d.value .. " of " .. d.suit,
      value = d.value, suit = d.suit, cost = 1,
    })
  end
  return out
end

local function swap(container, keys, store)
  for _, k in ipairs(keys) do container[k], store[k] = store[k], container[k] end
end

local function swap_hud()
  local keys, seen = {}, {}
  for k in pairs(S) do
    if not HUD_KEEP[k] then seen[k] = true; keys[#keys + 1] = k end
  end
  for k in pairs(_hud) do
    if not HUD_KEEP[k] and not seen[k] then keys[#keys + 1] = k end
  end
  for _, k in ipairs(keys) do S[k], _hud[k] = _hud[k], S[k] end
end

local function swap_viewport()
  local gr = love and love.graphics
  if not gr then return end
  if _vp_saved then
    if _vp_saved.w then gr.getWidth, gr.getHeight = _vp_saved.w, _vp_saved.h end
    _vp_saved = nil
    return
  end
  _vp_saved = {}
  local w, h = value_of("viewport").id:match("^(%d+)x(%d+)$")
  if w then
    _vp_saved.w, _vp_saved.h = gr.getWidth, gr.getHeight
    w, h = tonumber(w), tonumber(h)
    gr.getWidth = function() return w end
    gr.getHeight = function() return h end
  end
end

local function swap_clock()
  if _clock_live then
    G.TIMERS = _clock_live
    _clock_live = nil
    return
  end
  local live = G and G.TIMERS
  if _rate == 1 or not live then return end
  _clock_live = live
  for k, v in pairs(live) do _clock[k] = v end
  _clock.REAL = show_of(live.REAL or 0)
  _clock.TOTAL = _clock.REAL
  G.TIMERS = _clock
end

local function swap_all()
  swap(G, G_KEYS, _gstore)
  if G.NEURO then swap(G.NEURO, N_KEYS, _nstore) end
  swap_hud()
  swap_viewport()
  swap_clock()
end

local function reset_hud()
  local fresh = S.new_state()
  for k in pairs(S) do
    if not HUD_KEEP[k] and fresh[k] == nil then S[k] = nil end
  end
  for k, v in pairs(fresh) do S[k] = v end
end

local function reset_pack_anim()
  S.pack_card_indices = {}
  S.pack_winners, S.pack_losers = {}, nil
  S.pack_collapse_t, S.pack_collapse_snap = nil, nil
  S.pack_collapse_req, S.pack_collapse_done = nil, nil
  S.pack_leave_t, S.pack_leave_snap, S.pack_leave_n = nil, nil, 0
  S.pack_initial_count, S.pack_hl, S.pack_hl_t = 0, false, 0
end

local function build()
  local st = value_of("state").id
  local o = _opts
  local kind, mod = value_of("card").id, value_of("mod").id
  local subject = Fixtures.subject(kind, mod)
  local jokers, cons = Fixtures.owned(value_of("layout").id, subject)
  local shop = Fixtures.shop(subject)

  local base_vouchers, used = {}, {}
  for i = 1, (o.vouchers or 3) do
    local k = Fixtures.VOUCHER_KEYS[i]
    if k then base_vouchers[#base_vouchers + 1] = k; used[k] = true end
  end

  local pack_all = Fixtures.pack_cards(st)
  pack_all[1] = Fixtures.subject(kind, mod)
  if o.pack_n then
    for i = #pack_all, o.pack_n + 1, -1 do pack_all[i] = nil end
  end
  local pack_live = {}
  for i, c in ipairs(pack_all) do pack_live[i] = c end
  local pack = Fixtures.area(pack_live, math.max(4, #pack_all))
  local is_pack = StateKinds.is_pack_state(st)
  local is_menu = StateKinds.is_menu_state(st)

  local game = Fixtures.game({
    dollars = o.dollars,
    reroll_cost = o.reroll_cost,
    used_vouchers = used,
    joker_limit = jokers.config.card_limit,
    cons_limit = cons.config.card_limit,
    blind = o.boss and Fixtures.boss_blind() or nil,
    pack_choices = is_pack and 1 or nil,
  })
  if o.seeded == false then game.seeded = false end

  local hand = Fixtures.area(playing_cards(5), 8)
  hand.config.highlighted_limit = 5
  if st == "SELECTING_HAND" or st == "HAND_PLAYED" then
    hand:add_to_highlighted(hand.cards[1])
    hand:add_to_highlighted(hand.cards[2])
  end

  reset_hud()
  _tk, _added = {}, {}

  G.GAME = game
  G.STAGE = G.STAGES and (is_menu and G.STAGES.MAIN_MENU or G.STAGES.RUN) or nil
  G.jokers, G.consumeables = jokers, cons
  if o.empty_shop then
    G.shop_jokers = Fixtures.area({})
    G.shop_vouchers = Fixtures.area({})
    G.shop_booster = Fixtures.area({})
  else
    G.shop_jokers, G.shop_vouchers, G.shop_booster = shop.jokers, shop.vouchers, shop.boosters
  end
  G.pack_cards = is_pack and pack or nil
  G.booster_pack = nil
  G.hand, G.deck = hand, Fixtures.area(playing_cards(8), 52)
  G.play, G.discard = Fixtures.area({}, 5), Fixtures.area({}, 5)
  G.playing_cards = {}
  for _, area in ipairs({ G.hand, G.deck }) do
    for _, c in ipairs(area.cards) do G.playing_cards[#G.playing_cards + 1] = c end
  end

  G.NEURO.state = st
  G.NEURO.persona = value_of("persona").id
  local pins = value_of("pins")
  G.NEURO.dev_footer = pins.phase and { phase = pins.phase, dur = pins.dur } or nil
  G.NEURO.force_inflight = o.force_inflight and true or false
  G.NEURO.seed_pasted = o.seed_pasted
  G.NEURO.ai_highlighted = {}
  G.NEURO.ai_glow = {}
  G.NEURO.login_anim = nil
  G.NEURO.egg = nil
  G.NEURO.reserved_dollars = o.reserved or 0
  G.NEURO.purchase_showcase_queue = nil
  G.NEURO.force_sent_at = nil
  G.NEURO.force_state = st
  G.NEURO.action_phase = o.force_inflight and "sent" or "idle"
  G.NEURO.last_action_name = "dev_preview"
  G.NEURO.recent_actions = {}
  if is_pack and pack.cards[2] then G.NEURO.ai_highlighted[pack.cards[2]] = true end

  local voucher_cards = {}
  for _, k in ipairs(Fixtures.VOUCHER_KEYS) do
    voucher_cards[k] = Fixtures.card({ key = k, set = "Voucher",
      name = Fixtures.VOUCHER_NAMES[k] or k, cost = 10 })
  end

  _world = {
    subject = subject,
    subject_name = subject.ability.name,
    buy_card = Fixtures.subject(kind, mod),
    use_card = Fixtures.subject("tarot", "none"),
    buyuse_card = Fixtures.subject("planet", "none"),
    pickmorph_card = Fixtures.subject("spectral", "none"),
    pack = pack,
    pack_all = pack_all,
    voucher_base = base_vouchers,
    voucher_used = used,
    voucher_cards = voucher_cards,
    cross_cards = {
      Fixtures.card({ key = "j_greedy_joker", name = "Greedy Joker", cost = 5 }),
      Fixtures.card({ key = "j_blueprint", name = "Blueprint", cost = 10, rarity = 3 }),
    },
    receipt_cards = {
      arcana      = Fixtures.card({ key = "p_arcana_normal_1", set = "Booster", name = "Arcana Pack", cost = 4 }),
      greedy      = Fixtures.card({ key = "j_greedy_joker", name = "Greedy Joker", cost = 5 }),
      grabber     = Fixtures.subject("voucher", "none"),
      magician    = Fixtures.subject("tarot", "none"),
      jupiter     = Fixtures.card({ key = "c_jupiter", set = "Planet", name = "Jupiter", cost = 3 }),
      fool        = Fixtures.card({ key = "c_fool", set = "Tarot", name = "The Fool", cost = 3 }),
      baron       = Fixtures.card({ key = "j_baron", name = "Baron", cost = 6 }),
      gros_michel = Fixtures.card({ key = "j_gros_michel", name = "Gros Michel", cost = 5 }),
      blueprint   = Fixtures.card({ key = "j_blueprint", name = "Blueprint", cost = 10, rarity = 3 }),
      canio       = Fixtures.subject("legendary", "none"),
    },
    showcase_cards = {
      Fixtures.subject(kind, mod),
      Fixtures.subject("tarot", "none"),
      Fixtures.subject("planet", "foil"),
      Fixtures.subject("spectral", "negative"),
      Fixtures.subject("voucher", "none"),
      Fixtures.subject("legendary", "polychrome"),
    },
  }
end

local BUY_PIN_PHASE = 0.30
local SHOWCASE_PIN_PHASE = 1.20
local LOGIN_PIN_PHASE = 2.40
DevScenario.BUY_PIN_PHASE = BUY_PIN_PHASE
DevScenario.SHOWCASE_PIN_PHASE = SHOWCASE_PIN_PHASE

local PACK_PIN_PHASE = 0.18

local function pin_hold(n)
  if S.pack_appear_t and S.pack_appear_t ~= 0 then
    S.pack_appear_t = n - PACK_PIN_PHASE
  end
  local bs = S.buy_showcase
  if bs then
    bs.started = n - BUY_PIN_PHASE
    bs.swap_started, bs.content_in_at = nil, nil
  end
  local js = S.joker_showcase
  if js then js.started = n - SHOWCASE_PIN_PHASE end
  local anim = G.NEURO.login_anim
  if anim then anim.start = n - LOGIN_PIN_PHASE end
  local egg = G.NEURO.egg
  if egg then egg.expires_at = n + 4 end
end

local function add_card(list, card)
  list[#list + 1] = card
  _added[#_added + 1] = { list = list, card = card }
end

local function undo_added()
  for i = #_added, 1, -1 do
    local a = _added[i]
    for j = #a.list, 1, -1 do
      if a.list[j] == a.card then table.remove(a.list, j) end
    end
    _added[i] = nil
  end
end

local EVENTS = {}

local function restart_take(take_i)
  thaw_clock(value_of("speed").rate or 1)
  _take_at, _take_fired, _take_n = now(), false, take_i
  if _entered_pending then _entered_at, _entered_pending = _take_at, false end
  _tk = {}
  undo_added()
  Showcase.reset_run_state()
  G.NEURO.purchase_showcase_queue = nil
  G.NEURO.login_anim = nil
  G.NEURO.egg = nil
  G.GAME.pack_choices = nil
  G.pack_cards = StateKinds.is_pack_state(G.NEURO.state or "") and _world.pack or nil
  reset_pack_anim()
  local used = _world.voucher_used
  for key in pairs(used) do used[key] = nil end
  for _, key in ipairs(_world.voucher_base) do used[key] = true end
  S.known_voucher_keys, S.voucher_order, S.voucher_anim = nil, {}, {}
  Showcase.update_joker(_take_at)
end

EVENTS.none = { span = 4.0 }

EVENTS.buy = {
  span = 6.4, beats = "acquire",
  fire = function()
    local c = _world.buy_card
    Showcase.enqueue_purchase({
      card = c, name = c.ability.name, cost = receipt_cost("shop_jokers", c), area = "shop_jokers",
    })
    add_card(G.jokers.cards, c)
  end,
}

EVENTS.voucher = {
  span = 7.0, beats = "acquire",
  fire = function(k, n)
    local free = {}
    for _, key in ipairs(Fixtures.VOUCHER_KEYS) do
      if not _world.voucher_used[key] then free[#free + 1] = key end
    end
    if #free == 0 then free = Fixtures.VOUCHER_KEYS end
    local card = _world.voucher_cards[free[(k % #free) + 1]]
    if not card then return end
    Showcase.enqueue_purchase({
      card = card, name = card.ability.name, cost = card.cost or 0, area = "shop_vouchers",
    })
    Showcase.enqueue_voucher(card, n)
    _world.voucher_used[card.config.center.key] = true
  end,
}

EVENTS.voucher_backlog = {
  span = 14.0, beats = "acquire",
  fire = function()
    add_card(G.jokers.cards, _world.cross_cards[1])
    add_card(G.jokers.cards, _world.cross_cards[2])
  end,
  tick = function(t, _, n)
    if t < 0.10 or _tk.bought then return end
    _tk.bought = true
    local free = {}
    for _, key in ipairs(Fixtures.VOUCHER_KEYS) do
      if not _world.voucher_used[key] then free[#free + 1] = key end
    end
    if #free == 0 then free = Fixtures.VOUCHER_KEYS end
    local card = _world.voucher_cards[free[1]]
    if not card then return end
    Showcase.enqueue_purchase({
      card = card, name = card.ability.name, cost = card.cost or 0, area = "shop_vouchers",
    })
    Showcase.enqueue_voucher(card, n)
    _world.voucher_used[card.config.center.key] = true
  end,
}

EVENTS.crosscut = {
  span = 4.2,
  fire = function()
    local a = _world.cross_cards[1]
    Showcase.enqueue_purchase({
      card = a, name = a.ability.name, cost = a.cost or 0, area = "shop_jokers",
    })
  end,
  tick = function(t)
    if t < 0.55 or _tk.second then return end
    _tk.second = true
    local b = _world.cross_cards[2]
    Showcase.enqueue_purchase({
      card = b, name = b.ability.name, cost = b.cost or 0, area = "shop_jokers",
    })
  end,
}

EVENTS.toasts = {
  span = 2.4, multi = true,
  fire = function(k, n)
    local v = ACQUIRE_VARIANTS[(k % #ACQUIRE_VARIANTS) + 1]
    local card = _world.receipt_cards[v.card]
    if v.code then
      Showcase.enqueue_refusal({
        card = card, name = v.name, cost = receipt_cost(v.area, card),
        code = v.code, action_id = "dev_harness", at = n,
      })
      return
    end
    local levels
    if v.area == "use" then
      levels = v.leveled and Fixtures.HAND_LEVEL_SNAP
        or LevelDelta.snapshot(G.GAME and G.GAME.hands)
    end
    Showcase.enqueue_purchase({
      card = card, name = v.name, cost = receipt_cost(v.area, card), area = v.area, levels = levels,
    })
  end,
}

EVENTS.gain = {
  span = 2.4,
  fire = function()
    local c = _world.pack_all[1]
    Showcase.enqueue_purchase({
      card = c, name = c and c.ability.name or "Card", cost = 0, area = "booster_pick",
    })
  end,
}

EVENTS.showcase = {
  span = Showcase.JOKER_SHOWCASE_DURATION + 0.6, multi = true,
  fire = function(k, n)
    local cards = _world.showcase_cards
    local c = cards[(k % #cards) + 1]
    local set = c.config.center.set
    if set == "Voucher" then
      Showcase.enqueue_voucher(c, n)
    elseif set == "Joker" then
      add_card(G.jokers.cards, c)
    else
      add_card(G.consumeables.cards, c)
    end
  end,
}

EVENTS.pick = {
  span = 4.6, multi = true, beats = "pack",
  fire = function(k)
    local pack = _world.pack
    local c = pack.cards
    for i = #c, 1, -1 do c[i] = nil end
    for i = 1, #_world.pack_all do c[i] = _world.pack_all[i] end
    G.pack_cards = pack
    _tk.picks = ((k % 2) == 1) and 2 or 1
    _tk.claimed = 0
    G.GAME.pack_choices = _tk.picks
  end,
  tick = function(t)
    local pack = _world.pack
    local claims = 0
    if t >= 1.2 then claims = 1 end
    if (_tk.picks or 1) > 1 and t >= 2.8 then claims = 2 end
    if claims <= (_tk.claimed or 0) then return end
    _tk.claimed = claims
    local winner = pack.cards[2] or pack.cards[1]
    if not winner then return end
    NeuroAnim.pick_pack_card(winner, pack)
    for i, c in ipairs(pack.cards) do
      if c == winner then table.remove(pack.cards, i) break end
    end
    if (G.GAME.pack_choices or 0) > 1 then G.GAME.pack_choices = G.GAME.pack_choices - 1 end
  end,
}

EVENTS.packclaim = {
  span = 4.6, multi = true, beats = "pack",
  fire = function(k)
    local pack = _world.pack
    local c = pack.cards
    for i = #c, 1, -1 do c[i] = nil end
    for i = 1, #_world.pack_all do c[i] = _world.pack_all[i] end
    G.pack_cards = pack
    _tk.picks = ((k % 2) == 1) and 2 or 1
    _tk.claimed = 0
    G.GAME.pack_choices = _tk.picks
  end,
  tick = function(t)
    local pack = _world.pack
    local claims = 0
    if t >= 1.2 then claims = 1 end
    if (_tk.picks or 1) > 1 and t >= 2.8 then claims = 2 end
    if claims <= (_tk.claimed or 0) then return end
    _tk.claimed = claims
    local winner = pack.cards[2] or pack.cards[1]
    if not winner then return end
    NeuroAnim.pick_pack_card(winner, pack)
    Showcase.enqueue_purchase({
      card = winner, name = winner.ability and winner.ability.name or "Card",
      cost = 0, area = "booster_pick",
    })
    for i, c in ipairs(pack.cards) do
      if c == winner then table.remove(pack.cards, i) break end
    end
    if (G.GAME.pack_choices or 0) > 1 then G.GAME.pack_choices = G.GAME.pack_choices - 1 end
  end,
}

EVENTS.boosteropen = {
  span = 3.2, beats = "pack",
  fire = function()
    local pack = _world.pack
    local c = pack.cards
    for i = #c, 1, -1 do c[i] = nil end
    for i = 1, #_world.pack_all do c[i] = _world.pack_all[i] end
    G.pack_cards = pack
    G.GAME.pack_choices = 1
    local card = _world.pack_all[1]
    Showcase.enqueue_purchase({
      card = card, name = "Arcana Pack", cost = 4, area = "shop_booster",
    })
  end,
}

EVENTS.lastcons = {
  span = 3.0,
  fire = function()
    G.consumeables.cards = { Fixtures.subject("tarot", "none") }
    _tk.dropped = false
  end,
  tick = function(t)
    if t < 1.0 or _tk.dropped then return end
    _tk.dropped = true
    G.consumeables.cards = {}
  end,
}

EVENTS.pickmore = {
  span = 4.2, multi = true, beats = "pack",
  fire = function()
    local pack = _world.pack
    local c = pack.cards
    for i = #c, 1, -1 do c[i] = nil end
    for i = 1, #_world.pack_all do c[i] = _world.pack_all[i] end
    G.pack_cards = pack
    _tk.claimed = 0
    G.GAME.pack_choices = 3
  end,
  tick = function(t)
    local pack = _world.pack
    local claims = 0
    if t >= 1.2 then claims = 1 end
    if t >= 2.6 then claims = 2 end
    if claims <= (_tk.claimed or 0) then return end
    _tk.claimed = claims
    local winner = pack.cards[2] or pack.cards[1]
    if not winner then return end
    NeuroAnim.pick_pack_card(winner, pack)
    for i, cc in ipairs(pack.cards) do
      if cc == winner then table.remove(pack.cards, i) break end
    end
    if (G.GAME.pack_choices or 0) > 1 then G.GAME.pack_choices = G.GAME.pack_choices - 1 end
  end,
}

EVENTS.picklate = {
  span = 3.4, multi = true, beats = "pack_multi",
  fire = function()
    local pack = _world.pack
    local c = pack.cards
    for i = #c, 1, -1 do c[i] = nil end
    for i = 1, #_world.pack_all do c[i] = _world.pack_all[i] end
    G.pack_cards = pack
    _tk.claimed = 0
    G.GAME.pack_choices = 2
  end,
  tick = function(t)
    local pack = _world.pack
    local claims = 0
    if t >= 1.2 then claims = 1 end
    if t >= 2.05 then claims = 2 end
    if claims <= (_tk.claimed or 0) then return end
    _tk.claimed = claims
    local winner = pack.cards[2] or pack.cards[1]
    if not winner then return end
    NeuroAnim.pick_pack_card(winner, pack)
    for i, cc in ipairs(pack.cards) do
      if cc == winner then table.remove(pack.cards, i) break end
    end
    if (G.GAME.pack_choices or 0) > 1 then G.GAME.pack_choices = G.GAME.pack_choices - 1 end
  end,
}

EVENTS.usecard = {
  span = 6.4, beats = "acquire",
  fire = function()
    local c = _world.use_card
    Showcase.enqueue_purchase({
      card = c, name = c.ability.name, cost = receipt_cost("use", c), area = "use",
    })
    add_card(G.consumeables.cards, c)
  end,
}

EVENTS.buyuse = {
  span = 6.4, beats = "acquire",
  fire = function()
    local c = _world.buyuse_card
    Showcase.enqueue_purchase({
      card = c, name = c.ability.name, cost = receipt_cost("shop_use", c), area = "shop_use",
    })
    add_card(G.consumeables.cards, c)
  end,
}

EVENTS.pickmorph = {
  span = 6.4, beats = "acquire",
  fire = function()
    local c = _world.pickmorph_card
    Showcase.enqueue_purchase({
      card = c, name = c.ability.name, cost = receipt_cost("booster_pick", c), area = "booster_pick",
    })
    add_card(G.consumeables.cards, c)
  end,
}

EVENTS.money = {
  span = 1.6, multi = true,
  fire = function(k) G.GAME.dollars = 12 + (k % 5) * 9 end,
}

EVENTS.login = {
  span = 5.4,
  fire = function(_, n) G.NEURO.login_anim = { start = n, name = "NEURO" } end,
}

EVENTS.cookie = {
  span = 4.6,
  fire = function(_, n) G.NEURO.egg = { text = "dev harness cookie", expires_at = n + 4 } end,
}

local function set_state(st)
  G.NEURO.state, G.NEURO.force_state = st, st
  G.pack_cards = StateKinds.is_pack_state(st) and _world.pack or nil
end

local PACK_TEARDOWN_GAP = 0.4

local REROLL_KEYS = { "j_zany", "j_crazy", "j_mad", "j_droll", "j_jolly", "j_greedy" }

local function kill_pack_area()
  local pack = _world.pack
  for i = #pack.cards, 1, -1 do pack.cards[i] = nil end
  G.pack_cards = nil
end

local function leave_pack_state(st)
  G.NEURO.state, G.NEURO.force_state = st, st
end

EVENTS.usecons_shop = {
  span = 3.0,
  fire = function()
    set_state("SHOP")
    _tk.parked, _tk.back = false, false
  end,
  tick = function(t)
    if t >= 0.8 and not _tk.parked then
      _tk.parked = true
      leave_pack_state("PLAY_TAROT")
      local c = _world.use_card
      Showcase.enqueue_purchase({
        card = c, name = c.ability.name, cost = receipt_cost("use", c), area = "use",
      })
    end
    if t >= 1.1 and not _tk.back then
      _tk.back = true
      leave_pack_state("SHOP")
    end
  end,
}

-- Exercises the shop panel's exit (build_panel_rows only emits shop rows while sn == "SHOP", render/hud_overlay.lua:404); G.shop_* is left alone, matching the real game.
EVENTS.leaveshop = {
  span = 2.4,
  fire = function() set_state("SHOP") end,
  tick = function(t)
    if t < 0.8 or _tk.left then return end
    _tk.left = true
    set_state("BLIND_SELECT")
  end,
}

EVENTS.shoptopack = {
  span = 3.0,
  fire = function()
    set_state("SHOP")
    local a = _world.buy_card
    Showcase.enqueue_purchase({
      card = a, name = a.ability.name, cost = a.cost or 0, area = "shop_jokers",
    })
  end,
  tick = function(t)
    if t < 0.6 or _tk.topack then return end
    _tk.topack = true
    set_state("BUFFOON_PACK")
  end,
}

EVENTS.picklive = {
  span = 4.6, beats = "pack",
  fire = function()
    local pack = _world.pack
    local c = pack.cards
    for i = #c, 1, -1 do c[i] = nil end
    for i = 1, #_world.pack_all do c[i] = _world.pack_all[i] end
    G.pack_cards = pack
    _tk.claimed = false
    G.GAME.pack_choices = 1
  end,
  tick = function(t)
    if t < 1.2 or _tk.claimed then return end
    _tk.claimed = true
    local pack = _world.pack
    local winner = pack.cards[2] or pack.cards[1]
    if not winner then return end
    NeuroAnim.pick_pack_card(winner, pack)
    for i = #pack.cards, 1, -1 do pack.cards[i] = nil end
  end,
}

EVENTS.picklast = {
  span = 4.6, beats = "pack",
  fire = function()
    local pack = _world.pack
    local c = pack.cards
    for i = #c, 1, -1 do c[i] = nil end
    for i = 1, #_world.pack_all do c[i] = _world.pack_all[i] end
    G.pack_cards = pack
    _tk.claimed, _tk.left = false, false
    G.GAME.pack_choices = 1
    set_state("BUFFOON_PACK")
  end,
  tick = function(t)
    if t >= 1.2 and not _tk.claimed then
      _tk.claimed = true
      local pack = _world.pack
      local winner = pack.cards[2] or pack.cards[1]
      if winner then
        NeuroAnim.pick_pack_card(winner, pack)
        for i = #pack.cards, 1, -1 do pack.cards[i] = nil end
      end
    end
    if t >= 1.26 and not _tk.killed then
      _tk.killed = true
      kill_pack_area()
    end
    if t >= 1.26 + PACK_TEARDOWN_GAP and not _tk.left then
      _tk.left = true
      leave_pack_state("BLIND_SELECT")
    end
  end,
}

-- Models the engine's real teardown gap: a Planet pick leaves G.GAME.pack_choices at 1 after the last claim (button_callbacks.lua:2318 only decrements past the first of a mega pack), so the losers sit claimed-but-undissolved until the ~1.8s-later booster_pack:remove() tears the area down.
EVENTS.packfinal = {
  span = 4.6, beats = "pack",
  fire = function()
    local pack = _world.pack
    local c = pack.cards
    for i = #c, 1, -1 do c[i] = nil end
    for i = 1, #_world.pack_all do c[i] = _world.pack_all[i] end
    G.pack_cards = pack
    _tk.claimed, _tk.torn_down = false, false
    G.GAME.pack_choices = 1
    set_state("PLANET_PACK")
  end,
  tick = function(t)
    if t >= 1.2 and not _tk.claimed then
      _tk.claimed = true
      local pack = _world.pack
      local winner = pack.cards[2] or pack.cards[1]
      if winner then
        NeuroAnim.pick_pack_card(winner, pack)
        for i, cc in ipairs(pack.cards) do
          if cc == winner then table.remove(pack.cards, i) break end
        end
      end
    end
    if t >= 3.0 and not _tk.torn_down then
      _tk.torn_down = true
      kill_pack_area()
    end
    if t >= 3.0 + PACK_TEARDOWN_GAP and not _tk.left then
      _tk.left = true
      leave_pack_state("SHOP")
    end
  end,
}

EVENTS.packtear = {
  span = 4.6, beats = "pack",
  fire = function()
    local pack = _world.pack
    local c = pack.cards
    for i = #c, 1, -1 do c[i] = nil end
    for i = 1, #_world.pack_all do c[i] = _world.pack_all[i] end
    G.pack_cards = pack
    _tk.claimed, _tk.killed, _tk.left = false, false, false
    G.GAME.pack_choices = 1
    set_state("BUFFOON_PACK")
  end,
  tick = function(t)
    if t >= 1.2 and not _tk.claimed then
      _tk.claimed = true
      local pack = _world.pack
      local winner = pack.cards[2] or pack.cards[1]
      if winner then
        NeuroAnim.pick_pack_card(winner, pack)
        for i, cc in ipairs(pack.cards) do
          if cc == winner then table.remove(pack.cards, i) break end
        end
      end
    end
    if t >= 1.54 and not _tk.killed then
      _tk.killed = true
      kill_pack_area()
    end
    if t >= 1.54 + PACK_TEARDOWN_GAP and not _tk.left then
      _tk.left = true
      leave_pack_state("SHOP")
    end
  end,
}

EVENTS.leavepack = {
  span = 2.6,
  fire = function()
    set_state("BUFFOON_PACK")
    _tk.killed, _tk.left = false, false
  end,
  tick = function(t)
    if t >= 0.8 and not _tk.killed then
      _tk.killed = true
      kill_pack_area()
    end
    if t >= 0.8 + PACK_TEARDOWN_GAP and not _tk.left then
      _tk.left = true
      leave_pack_state("BLIND_SELECT")
    end
  end,
}

EVENTS.swapcons = {
  span = 3.2,
  tick = function(t)
    if t < 1.2 or _tk.swapped then return end
    _tk.swapped = true
    local cards = G.consumeables and G.consumeables.cards
    if cards and cards[1] then cards[1] = Fixtures.subject("planet", "none") end
  end,
}

DevScenario.EVENTS = EVENTS

local function refresh_beat_axis()
  local ev = EVENTS[value_of("event").id]
  local set = (ev and ev.beats) or "none"
  local ax = AXIS.beat
  if ax._set == set then return end
  local cur = value_of("beat").id
  ax._set = set
  ax.values = BEAT_SETS[set]
  ax.index_of = {}
  for i, v in ipairs(ax.values) do ax.index_of[v.id] = i end
  ax.default_i = ax.index_of[ax.default] or 1
  _sel.beat = ax.index_of[cur] or ax.default_i
end

local _acq_deco = {}
local function acquire_tl()
  local pk = tostring(value_of("persona").id)
  local d = _acq_deco[pk]
  if d == nil then
    local ok, mod = pcall(require, "render.panels.acquire_" .. pk)
    if not ok then
      Utils.diag_once("dev_acquire_decorator:" .. pk,
        "dev preview could not load acquire decorator for " .. pk .. ": " .. tostring(mod))
    end
    d = (ok and type(mod) == "table") and mod or false
    _acq_deco[pk] = d
  end
  return (d and d.TL) or Acquire.TL.soft
end

local function pack_tl()
  return Pack.TIMELINES[value_of("persona").id] or Pack.TIMELINES.soft
end

local function beat_boundary(bid, n)
  if bid:sub(1, 2) == "a_" then
    local sc, js = S.buy_showcase, S.joker_showcase
    local tl = acquire_tl()
    if bid == "a_in" then return sc and sc.started and (sc.started + tl.IN * 0.5) end
    if bid == "a_hold" then return sc and sc.started and (sc.started + tl.IN) end
    local full_at, morph_at
    local morph_d = (sc and sc._morph_d) or tl.MORPH
    if js and js._morphed then
      full_at = js.started
      morph_at = full_at and (full_at - morph_d)
    elseif sc then
      morph_at = sc._morph_at
      if not morph_at then
        local ok, at = Acquire.pair(n, tl)
        if ok then morph_at = at end
      end
      full_at = morph_at and (morph_at + morph_d)
    end
    if bid == "a_morph" then return morph_at and (morph_at + tl.MORPH * 0.5) end
    if bid == "a_full" then return full_at end
    return full_at and (full_at + Acquire.TL.FULL_SPAN - tl.OUT * 0.5)
  end
  local ct = S.pack_collapse_t
  if not ct then return nil end
  local tl = pack_tl()
  if bid == "p_anoint" then return ct + tl.ANOINT * 0.5 end
  if bid == "p_glide" then return ct + tl.ANOINT + tl.GLIDE * 0.5 end
  local snap = S.pack_collapse_snap
  local loser_max = (snap and snap.loser_max)
    or (Pack.LOSER_D + math.max(0, (S.pack_initial_count or 1) - 1) * Pack.LOSER_SPREAD)
  local shrink_at = ct + tl.ANOINT + math.max(tl.GLIDE, loser_max)
  for _, w in ipairs(S.pack_winners or {}) do
    local e = (w.t0 or ct) + (w._anoint or tl.ANOINT) + tl.GLIDE
    if e > shrink_at then shrink_at = e end
  end
  if bid == "p_refreeze" then
    if not (snap and snap.split_at) then return nil end
    return shrink_at + tl.SHRINK * 0.5
  end
  if bid == "p_shrink" then
    if Pack.picks_owed() > 0 then return nil end
    return shrink_at + tl.SHRINK * 0.5
  end
  if bid == "p_hold" then return shrink_at + tl.SHRINK end
  return shrink_at + tl.SHRINK + tl.HOLD + tl.EXIT * 0.5
end

local function drive()
  refresh_beat_axis()
  local n = now()
  local o = _opts
  if o.reroll_cycle and G.shop_jokers and G.shop_jokers.cards and G.GAME then
    local gen = math.floor((n - _entered_at) / 3.0)
    if gen ~= _tk.reroll_gen then
      _tk.reroll_gen = gen
      local cards = G.shop_jokers.cards
      for i = 1, #cards do
        if i == 1 then
          cards[i] = Fixtures.subject(value_of("card").id, value_of("mod").id)
        else
          local key = REROLL_KEYS[((gen + i) % #REROLL_KEYS) + 1]
          cards[i] = Fixtures.card({ key = key, set = "Joker", name = key, cost = 4 })
        end
      end
      if gen % 2 == 1 and G.GAME.current_round then
        local rc = G.GAME.current_round
        rc.reroll_cost_increase = (rc.reroll_cost_increase or 0) + 1
      end
    end
  end

  local ev = EVENTS[value_of("event").id] or EVENTS.none
  local mode = value_of("play").id
  local beat = value_of("beat").id
  local span = ev.span or 4.0
  local cycling = beat == "off"
    and ((mode == "loop") or (mode == "hold" and ev.multi == true))

  if _take_restart then
    _take_restart = false
    restart_take(0)
    n = now()
  elseif cycling and (n - _take_at) >= span then
    restart_take(_take_n + 1)
  end

  if not _take_fired then
    _take_fired = true
    if ev.fire then ev.fire(_take_n, n) end
  end
  if ev.tick then ev.tick(n - _take_at, _take_n, n) end

  Showcase.update_joker(n)

  if beat ~= "off" and _rate > 0 then
    local at = beat_boundary(beat, n)
    if at and n >= at then freeze_clock(at) end
  end

  if mode == "hold" and beat == "off" then pin_hold(n) end

  Showcase.update_buy(now())
end

local SCENES = {
  { id = "shop", label = "Buy -> morph",
    axes = { state = "SHOP", event = "buy" },
    opts = { reroll_cycle = true, reroll_cost = 5, reserved = 4 } },
  { id = "slots", label = "Empty slots",
    axes = { state = "SHOP", layout = "empty" }, opts = {} },
  { id = "deck", label = "Deck + seed",
    axes = { state = "SHOP" },
    opts = { empty_shop = true, seeded = false, seed_pasted = "DEVSEED42" } },
  { id = "arcana", label = "Arcana pack",
    axes = { state = "TAROT_PACK" }, opts = {} },
  { id = "buffoon", label = "Buffoon pack",
    axes = { state = "BUFFOON_PACK" }, opts = {} },
  { id = "standard", label = "Standard pack",
    axes = { state = "STANDARD_PACK", card = "playing" }, opts = {} },
  { id = "pick", label = "Pack claim",
    axes = { state = "BUFFOON_PACK", event = "pick" }, opts = {} },
  { id = "toasts", label = "Receipt verbs",
    axes = { state = "SHOP", event = "toasts" }, opts = {} },
  { id = "crosscut", label = "Cross-cut",
    axes = { state = "SHOP", event = "crosscut" }, opts = {} },
  { id = "showcase", label = "Showcase entry",
    axes = { state = "SHOP", event = "showcase" }, opts = {} },
  { id = "vouchers", label = "Voucher buy",
    axes = { state = "SHOP", event = "voucher" }, opts = { vouchers = 2 } },
  { id = "voucherbacklog", label = "Voucher behind backlog",
    axes = { state = "SHOP", event = "voucher_backlog" }, opts = { vouchers = 2 } },
  { id = "roundeval", label = "Round eval",
    axes = { state = "ROUND_EVAL", event = "money" }, opts = { dollars = 34 } },
  { id = "boss", label = "Boss blind",
    axes = { state = "SELECTING_HAND" }, opts = { boss = true, force_inflight = true } },
  { id = "blindselect", label = "Blind select",
    axes = { state = "BLIND_SELECT" }, opts = { reroll_cost = 5 } },
  { id = "playing", label = "Playing hand",
    axes = { state = "SELECTING_HAND", card = "playing", mod = "loaded" },
    opts = { vouchers = 0 } },
  { id = "overflow", label = "Overflow",
    axes = { state = "SHOP", layout = "overflow", card = "long" }, opts = { vouchers = 5 } },
  { id = "trunc", label = "Long text",
    axes = { state = "SHOP", card = "long", mod = "loaded", event = "showcase" }, opts = {} },
  { id = "gameover", label = "Game over",
    axes = { state = "GAME_OVER", menu = "strict" }, opts = { dollars = 0 } },
  { id = "login", label = "Login",
    axes = { state = "MENU", event = "login" }, opts = { vouchers = 2 } },
  { id = "pack2", label = "Pack of 2",
    axes = { state = "BUFFOON_PACK" }, opts = { pack_n = 2 } },
  { id = "pack3", label = "Pack of 3",
    axes = { state = "TAROT_PACK" }, opts = { pack_n = 3 } },
  { id = "pickmore", label = "Pick, pack stays",
    axes = { state = "BUFFOON_PACK", event = "pickmore" }, opts = {} },
  { id = "picklate", label = "Late claim",
    axes = { state = "BUFFOON_PACK", event = "picklate" }, opts = {} },
  { id = "usecard", label = "Use -> morph",
    axes = { state = "SHOP", event = "usecard" }, opts = {} },
  { id = "buyuse", label = "Buy & use",
    axes = { state = "SHOP", event = "buyuse" }, opts = {} },
  { id = "pickmorph", label = "Pick -> morph",
    axes = { state = "SHOP", event = "pickmorph" }, opts = {} },
  { id = "packclaim", label = "Claim + receipt",
    axes = { state = "BUFFOON_PACK", event = "packclaim" }, opts = {} },
  { id = "boosteropen", label = "Booster receipt vs pack",
    axes = { state = "TAROT_PACK", event = "boosteropen" }, opts = {} },
  { id = "leaveshop", label = "Shop leaves",
    axes = { state = "SHOP", event = "leaveshop" }, opts = {} },
  { id = "shoptopack", label = "Receipt into pack",
    axes = { state = "SHOP", event = "shoptopack" }, opts = {} },
  { id = "picklive", label = "Pack pick, area emptied",
    axes = { state = "BUFFOON_PACK", event = "picklive" }, opts = {} },
  { id = "picklast", label = "Pack pick, last one",
    axes = { state = "BUFFOON_PACK", event = "picklast" }, opts = {} },
  { id = "packfinal", label = "Final pick, engine holds",
    axes = { state = "PLANET_PACK", event = "packfinal" }, opts = {} },
  { id = "packtear", label = "Fast teardown mid-cinematic",
    axes = { state = "BUFFOON_PACK", event = "packtear" }, opts = {} },
  { id = "usecons", label = "Consumable used in shop",
    axes = { state = "SHOP", event = "usecons_shop" }, opts = {} },
  { id = "packhidden", label = "Pack pick, face-down loser",
    axes = { state = "BUFFOON_PACK", event = "pick", mod = "facedown" }, opts = {} },
  { id = "leavepack", label = "Pack leaves unpicked",
    axes = { state = "BUFFOON_PACK", event = "leavepack" }, opts = {} },
  { id = "swapcons", label = "Carousel swap",
    axes = { state = "SHOP", event = "swapcons", layout = "overflow" }, opts = {} },
  { id = "lastcons", label = "Last consumable",
    axes = { state = "SHOP", event = "lastcons", layout = "overflow" }, opts = {} },
  { id = "pinlegend", label = "Pin legend",
    axes = { state = "SHOP", mod = "loaded", pins = "fast" }, opts = {} },
}

DevScenario.SCENES = SCENES

function DevScenario.select(i)
  local sc = SCENES[i]
  if not sc then return end
  _preset = i
  for _, ax in ipairs(AXES) do
    if not ax.framing then _sel[ax.id] = ax.default_i end
  end
  for aid, vid in pairs(sc.axes or {}) do
    local ax = AXIS[aid]
    if ax and ax.index_of[vid] then _sel[aid] = ax.index_of[vid] end
  end
  _opts = sc.opts or {}
  refresh_beat_axis()
  _dirty, _take_restart = true, true
  if _rate == 0 then _entered_pending = true else _entered_at, _entered_pending = now(), false end
end

local function axis_changed(axis_id)
  if axis_id == "speed" then
    set_rate(value_of("speed").rate or 1)
    _take_restart = true
    return
  end
  if axis_id == "play" or axis_id == "beat" then
    _take_restart = true
    return
  end
  _preset = nil
  refresh_beat_axis()
  _dirty, _take_restart, _entered_pending = true, true, true
end

local function cycle_axis(axis_id, step)
  local ax = AXIS[axis_id]
  local n = #ax.values
  _sel[axis_id] = ((_sel[axis_id] - 1 + step) % n) + 1
  axis_changed(axis_id)
end

local function set_axis(axis_id, i)
  if _sel[axis_id] == i then return end
  _sel[axis_id] = i
  axis_changed(axis_id)
end

function DevScenario.replay()
  _take_restart = true
end

function DevScenario.mount()
  if not (DevScenario.active and _gstore and G and G.NEURO) then return end
  if _mounted then return end
  swap_all()
  _mounted = true
  if _dirty or not _world then
    build()
    _dirty, _take_restart = false, true
  end
  drive()
  if value_of("menu").id == "strict" then G.NEURO.dev_preview_active = false end
end

function DevScenario.unmount()
  if not _mounted then return end
  if value_of("menu").id == "strict" then G.NEURO.dev_preview_active = true end
  _mounted = false
  swap_all()
end

function DevScenario.set(on)
  on = on and true or false
  if on == DevScenario.active then return end
  if on then
    _gstore, _nstore, _hud = {}, {}, S.new_state()
    _world, _preset = nil, nil
    for _, ax in ipairs(AXES) do _sel[ax.id] = ax.default_i end
    _rate, _clock_live = 1, nil
    _clk_real0, _clk_show0 = real_now(), real_now()
    _take_fired, _take_restart = false, true
    _tk, _added = {}, {}
    _open, _tweak = nil, false
    DevScenario.active = true
    DevScenario.select(1)
    if G and G.NEURO then G.NEURO.dev_preview_active = true end
  else
    DevScenario.unmount()
    if _gstore and G and G.NEURO then
      swap_all()
      Showcase.reset_run_state()
      swap_all()
    end
    DevScenario.active = false
    require("render.hud_shared").carousel_reset()
    if G and G.NEURO then G.NEURO.dev_preview_active = false end
    _gstore, _nstore, _hud, _world = nil, nil, nil, nil
    _tk, _added = {}, {}
    _rate = 1
    _btn_hit = {}
  end
end

function DevScenario.toggle() DevScenario.set(not DevScenario.active) end

function DevScenario.draw_buttons()
  if not DevScenario.active then return end
  _btn_hit = {}
  local get_w = (_vp_saved and _vp_saved.w) or love.graphics.getWidth
  local get_h = (_vp_saved and _vp_saved.h) or love.graphics.getHeight
  local sw, sh = get_w(), get_h()
  local font = love.graphics.getFont()
  if not font then return end
  local pad, h, gap = 12, 26, 6

  local function header_of(ax)
    return { kind = "header", cat = ax.id, cycler = ax.cycler,
      label = ax.label .. ": " .. value_of(ax.id).label, open = (_open == ax.id) }
  end

  local main = {
    { kind = "scene", label = "SCENE: " .. (_preset and SCENES[_preset].label or "-"),
      open = (_open == "scene") },
  }
  for _, ax in ipairs(MAIN_AXES) do main[#main + 1] = header_of(ax) end
  main[#main + 1] = { kind = "action", cat = "replay", label = "REPLAY" }
  main[#main + 1] = { kind = "tweak", label = "TWEAK", open = _tweak }

  local tweak = {}
  if _tweak then
    for _, ax in ipairs(TWEAK_AXES) do tweak[#tweak + 1] = header_of(ax) end
  end

  local values = {}
  if _open == "scene" then
    for i, sc in ipairs(SCENES) do
      values[#values + 1] = { kind = "preset", i = i, label = sc.label, on = (i == _preset) }
    end
  elseif _open and AXIS[_open] then
    local ax = AXIS[_open]
    for i, v in ipairs(ax.values) do
      values[#values + 1] = { kind = "value", axis = ax.id, vi = i, label = v.label,
        on = (i == _sel[ax.id]) }
    end
  end

  local max_w = sw - 24
  local function wrap(items, out)
    local row, row_w = {}, 0
    for _, it in ipairs(items) do
      local w = font:getWidth(it.label) + pad * 2
      it.w = w
      if #row > 0 and (row_w + gap + w) > max_w then
        out[#out + 1] = { items = row, w = row_w }
        row, row_w = {}, 0
      end
      row_w = row_w + (#row > 0 and gap or 0) + w
      row[#row + 1] = it
    end
    if #row > 0 then out[#out + 1] = { items = row, w = row_w } end
    return out
  end

  local rows = {}
  wrap(values, rows)
  wrap(tweak, rows)
  wrap(main, rows)

  local y = sh - #rows * (h + gap) - 10 + gap
  for _, r in ipairs(rows) do
    local x = math.floor((sw - r.w) / 2)
    for _, it in ipairs(r.items) do
      local w = it.w
      local lit = it.on or it.open
      love.graphics.setColor(0, 0, 0, 0.72)
      love.graphics.rectangle("fill", x, y, w, h, 4, 4)
      if lit then love.graphics.setColor(0.28, 0.9, 1, 0.95)
      elseif it.kind == "action" then love.graphics.setColor(0.45, 1, 0.6, 0.9)
      elseif it.kind == "value" then love.graphics.setColor(1, 1, 1, 0.32)
      else love.graphics.setColor(0.95, 0.55, 0.9, 0.8) end
      love.graphics.rectangle("line", x, y, w, h, 4, 4)
      if lit then love.graphics.setColor(0.28, 0.9, 1, 1)
      elseif it.kind == "action" then love.graphics.setColor(0.45, 1, 0.6, 1)
      else love.graphics.setColor(0.92, 0.92, 0.94, 1) end
      love.graphics.print(it.label, x + pad, y + math.floor((h - font:getHeight()) / 2))
      _btn_hit[#_btn_hit + 1] = { x = x, y = y, w = w, h = h, it = it }
      x = x + w + gap
    end
    y = y + h + gap
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function DevScenario.mousepressed(x, y, button)
  if not DevScenario.active then return false end
  for _, b in ipairs(_btn_hit) do
    if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
      local it = b.it
      if it.kind == "action" then
        DevScenario.replay()
      elseif it.kind == "tweak" then
        _tweak = not _tweak
        if not _tweak and _open ~= "scene" then _open = nil end
      elseif it.kind == "scene" then
        _open = (_open ~= "scene") and "scene" or nil
      elseif it.kind == "header" then
        if button == 2 then cycle_axis(it.cat, -1)
        elseif it.cycler then cycle_axis(it.cat, 1)
        else _open = (_open ~= it.cat) and it.cat or nil end
      elseif it.kind == "preset" then
        DevScenario.select(it.i)
      else
        set_axis(it.axis, it.vi)
      end
      return true
    end
  end
  return false
end

return DevScenario
