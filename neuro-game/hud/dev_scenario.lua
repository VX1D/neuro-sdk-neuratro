local S = require("hud.state")

local DevScenario = { active = false }
local _saved, _game_created, _fake = nil, false, nil
local _scene, _entered_at, _persona = 1, 0, "neuro"
local _pending_voucher_anim, _show_i, _btn_hit = false, 0, {}

local SCENES = {
  { id = "shop",    label = "Shop" },
  { id = "round",   label = "In-Round" },
  { id = "blind",   label = "Blind Select" },
  { id = "arcana",  label = "Arcana Pack" },
  { id = "buffoon", label = "Buffoon Pack" },
  { id = "slide",   label = "Booster Slide" },
  { id = "buyvars", label = "Buy Banners" },
  { id = "footer",  label = "Footer" },
}

local function now()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or 0
end

local function fc(key, cost, name)
  local center = (G and G.P_CENTERS and G.P_CENTERS[key])
    or { key = key, set = "Joker", name = name or key, pos = {}, rarity = 1, loc_txt = { name = name or key } }
  return {
    config = { center = center },
    ability = { set = center.set or "Joker", name = center.name or name or key,
      mult = 0, h_mult = 0, h_mod = 0, t_mult = 0, t_chips = 0, x_mult = 1, extra = 0 },
    base = { name = key },
    cost = cost or 5,
    sell_cost = math.max(1, math.floor((cost or 5) / 2)),
    debuff = false,
  }
end

-- built once: stable card identities keep the ref-keyed fade-in / desc caches from thrashing
local function build_fake()
  local f = {
    jokers = { cards = { fc("j_joker", 4, "Joker"), fc("j_greedy_joker", 5, "Greedy Joker"),
      fc("j_jolly", 5, "Jolly Joker") }, config = { card_limit = 5 } },
    consumeables = { cards = { fc("c_fool", 3, "The Fool"), fc("c_pluto", 3, "Pluto") }, config = { card_limit = 2 } },
    shop_jokers = { cards = { fc("j_zany", 6, "Zany Joker"), fc("j_crazy", 6, "Crazy Joker") } },
    shop_vouchers = { cards = { fc("v_grabber", 10, "Grabber"), fc("v_seed_money", 30, "Seed Money") } },
    shop_booster = { cards = { fc("p_arcana_normal_1", 4, "Arcana Pack"),
      fc("p_buffoon_normal_1", 6, "Buffoon Pack") } },
    used_vouchers = { v_overstock_norm = true, v_overstock_plus = true, v_clearance_sale = true },
    arcana_all = { fc("c_fool", 3, "The Fool"), fc("c_magician", 3, "The Magician"),
      fc("c_high_priestess", 3, "High Priestess"), fc("c_empress", 3, "The Empress") },
    buffoon_all = { fc("j_joker", 4, "Joker"), fc("j_zany", 6, "Zany Joker"),
      fc("j_crazy", 6, "Crazy Joker"), fc("j_blueprint", 10, "Blueprint") },
    blind = { in_blind = true, chips = 5000, mult = 2, name = "The Hook",
      get_loc_debuff_text = function() return "1 selected card debuffed each hand" end },
    blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" },
    buy = { started = 0, area = "shop_booster", name = "Arcana Pack", cost = 0 },
    showcase_types = {
      { key = "j_joker",   label = "NEW JOKER" },
      { key = "c_pluto",   label = "NEW PLANET" },
      { key = "c_fool",    label = "NEW TAROT" },
      { key = "c_familiar", label = "NEW SPECTRAL" },
    },
    buy_variants = {
      { area = "shop_booster",  name = "Arcana Pack",  cost = 0 },
      { area = "shop",          name = "Greedy Joker", cost = 0 },
      { area = "joker_gain",    name = "Blueprint",    cost = 6 },
      { area = "booster_pick",  name = "The Fool",     cost = 0 },
      { area = "shop_vouchers", name = "Grabber",      cost = 0 },
    },
  }
  f.arcana_pack = { cards = {} }
  f.buffoon_pack = { cards = {} }
  return f
end

local function set_pack(pack, all, elapsed)
  local n = ((elapsed % 4.0) >= 2.5) and (#all - 1) or #all
  local c = pack.cards
  for i = #c, 1, -1 do c[i] = nil end
  for i = 1, n do c[i] = all[i] end
end

function DevScenario.select(i)
  if not SCENES[i] then return end
  _scene, _entered_at = i, now()
  if SCENES[i].id == "shop" then _pending_voucher_anim = true end
end

function DevScenario.set(on)
  if on and not DevScenario.active then
    _game_created = (G.GAME == nil)
    _saved = {
      state = G.NEURO and G.NEURO.state,
      persona = G.NEURO and G.NEURO.persona,
      force_inflight = G.NEURO and G.NEURO.force_inflight,
      jokers = G.jokers, consumeables = G.consumeables,
      shop_jokers = G.shop_jokers, shop_vouchers = G.shop_vouchers, shop_booster = G.shop_booster,
      pack_cards = G.pack_cards,
      dollars = G.GAME and G.GAME.dollars, round = G.GAME and G.GAME.round,
      round_resets = G.GAME and G.GAME.round_resets, current_round = G.GAME and G.GAME.current_round,
      used_vouchers = G.GAME and G.GAME.used_vouchers,
      blind = G.GAME and G.GAME.blind, chips = G.GAME and G.GAME.chips,
      seeded = G.GAME and G.GAME.seeded, pseudorandom = G.GAME and G.GAME.pseudorandom,
      selected_back = G.GAME and G.GAME.selected_back, pack_choices = G.GAME and G.GAME.pack_choices,
      buy = S.buy_showcase, joker_showcase = S.joker_showcase,
    }
    _fake = _fake or build_fake()
    _fake.buy.card = _fake.shop_booster.cards[1]
    _scene, _entered_at, _pending_voucher_anim = 1, now(), true
    DevScenario.active = true
    if G.NEURO then G.NEURO.dev_preview_active = true end
  elseif (not on) and DevScenario.active then
    DevScenario.active = false
    if G.NEURO then G.NEURO.dev_preview_active = false end
    if _saved then
      if G.NEURO then
        G.NEURO.state = _saved.state
        G.NEURO.persona = _saved.persona
        G.NEURO.force_inflight = _saved.force_inflight
        if G.NEURO.ai_highlighted and _fake then
          for _, c in ipairs(_fake.arcana_all) do G.NEURO.ai_highlighted[c] = nil end
          for _, c in ipairs(_fake.buffoon_all) do G.NEURO.ai_highlighted[c] = nil end
        end
      end
      G.jokers, G.consumeables = _saved.jokers, _saved.consumeables
      G.shop_jokers, G.shop_vouchers, G.shop_booster = _saved.shop_jokers, _saved.shop_vouchers, _saved.shop_booster
      G.pack_cards = _saved.pack_cards
      if _game_created then
        G.GAME = nil
      elseif G.GAME then
        G.GAME.dollars, G.GAME.round = _saved.dollars, _saved.round
        G.GAME.round_resets, G.GAME.current_round = _saved.round_resets, _saved.current_round
        G.GAME.used_vouchers, G.GAME.blind, G.GAME.chips = _saved.used_vouchers, _saved.blind, _saved.chips
        G.GAME.seeded, G.GAME.pseudorandom = _saved.seeded, _saved.pseudorandom
        G.GAME.selected_back, G.GAME.pack_choices = _saved.selected_back, _saved.pack_choices
      end
      S.buy_showcase, S.joker_showcase = _saved.buy, _saved.joker_showcase
      S.pack_picked, S.pack_prev_cards, S.pack_card_indices = {}, {}, {}
    end
    _saved, _game_created = nil, false
  end
end

function DevScenario.toggle() DevScenario.set(not DevScenario.active) end

function DevScenario.apply()
  if not (DevScenario.active and G and G.NEURO) then return end
  if not _fake then _fake = build_fake() end
  _fake.buy.card = _fake.buy.card or _fake.shop_booster.cards[1]
  local t = now()
  local id = SCENES[_scene].id

  G.NEURO.persona = _persona
  G.NEURO.force_inflight = false
  G.GAME = G.GAME or {}
  G.GAME.dollars = G.GAME.dollars or 25
  G.GAME.round_resets = G.GAME.round_resets or {}
  G.GAME.round_resets.ante = G.GAME.round_resets.ante or 2
  G.GAME.round_resets.blind_choices = nil
  G.GAME.round = G.GAME.round or 3
  G.GAME.current_round = G.GAME.current_round or {}
  G.GAME.current_round.reroll_cost = 5
  G.GAME.seeded = true
  G.GAME.pseudorandom = G.GAME.pseudorandom or {}
  G.GAME.pseudorandom.seed = "OVERLAYDEV"
  if G.P_CENTERS then G.GAME.selected_back = G.GAME.selected_back or G.P_CENTERS.b_red end
  G.GAME.blind, G.GAME.pack_choices, G.pack_cards = nil, nil, nil
  G.GAME.used_vouchers = _fake.used_vouchers
  G.jokers, G.consumeables = _fake.jokers, _fake.consumeables
  G.shop_jokers, G.shop_vouchers, G.shop_booster = _fake.shop_jokers, _fake.shop_vouchers, _fake.shop_booster

  if id == "shop" then
    G.NEURO.state = "SHOP"
    _fake.buy.area, _fake.buy.name, _fake.buy.cost = "shop_booster", "Arcana Pack", 0
    _fake.buy.card, _fake.buy.started = _fake.shop_booster.cards[1], t - 0.5
    S.buy_showcase = _fake.buy
    if not S.joker_showcase then
      S.joker_showcase = { card = _fake.shop_jokers.cards[1], label = "NEW JOKER", started = t }
    end
    if _pending_voucher_anim then
      _pending_voucher_anim = false
      if type(S.known_voucher_keys) == "table" then S.known_voucher_keys.v_overstock_plus = nil end
    end

  elseif id == "round" then
    G.NEURO.state = "SELECTING_HAND"
    G.NEURO.force_inflight = true
    G.GAME.blind = _fake.blind
    G.GAME.chips = 1200
    G.GAME.current_round.hands_left, G.GAME.current_round.discards_left = 3, 2
    S.buy_showcase = nil

  elseif id == "blind" then
    G.NEURO.state = "BLIND_SELECT"
    G.GAME.round_resets.blind_choices = _fake.blind_choices
    S.buy_showcase = nil

  elseif id == "arcana" then
    G.NEURO.state = "TAROT_PACK"
    set_pack(_fake.arcana_pack, _fake.arcana_all, t - _entered_at)
    G.pack_cards, G.GAME.pack_choices = _fake.arcana_pack, 1
    G.NEURO.ai_highlighted[_fake.arcana_all[2]] = true
    S.buy_showcase = nil

  elseif id == "buffoon" then
    G.NEURO.state = "BUFFOON_PACK"
    set_pack(_fake.buffoon_pack, _fake.buffoon_all, t - _entered_at)
    G.pack_cards, G.GAME.pack_choices = _fake.buffoon_pack, 1
    G.NEURO.ai_highlighted[_fake.buffoon_all[2]] = true
    S.buy_showcase = nil

  elseif id == "slide" then
    G.NEURO.state = "SHOP"
    _fake.buy.area, _fake.buy.name = "booster_choice", "Booster"
    _fake.buy.card, _fake.buy.started = _fake.shop_booster.cards[1], t - 0.5
    S.buy_showcase = _fake.buy

  elseif id == "buyvars" then
    G.NEURO.state = "SHOP"
    local bv = _fake.buy_variants
    local v = bv[(math.floor((t - _entered_at) / 1.8) % #bv) + 1]
    _fake.buy.area, _fake.buy.name, _fake.buy.cost = v.area, v.name, v.cost or 0
    _fake.buy.card, _fake.buy.started = _fake.shop_jokers.cards[1], t - 0.5
    S.buy_showcase = _fake.buy
    local st = _fake.showcase_types
    local si = (math.floor((t - _entered_at) / 1.8) % #st) + 1
    if (not S.joker_showcase) or _show_i ~= si then
      _show_i = si
      S.joker_showcase = { card = fc(st[si].key), label = st[si].label, started = t }
    end

  elseif id == "footer" then
    G.NEURO.state = "SHOP"
    G.GAME.used_vouchers = {}
    S.buy_showcase, S.joker_showcase = nil, nil
  end
end

function DevScenario.draw_buttons()
  if not DevScenario.active then return end
  _btn_hit = {}
  local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
  local font = love.graphics.getFont()
  if not font then return end
  local pad, h, gap = 12, 26, 6

  local items = {}
  for i, sc in ipairs(SCENES) do items[#items + 1] = { kind = "scene", i = i, label = sc.label } end
  items[#items + 1] = { kind = "persona", label = "Persona: " .. _persona }

  local widths, total = {}, 0
  for k, it in ipairs(items) do
    widths[k] = font:getWidth(it.label) + pad * 2
    total = total + widths[k] + gap
  end
  total = total - gap
  local x, y = math.floor((sw - total) / 2), sh - h - 10

  for k, it in ipairs(items) do
    local w = widths[k]
    local active = (it.kind == "scene" and it.i == _scene)
    love.graphics.setColor(0, 0, 0, 0.72)
    love.graphics.rectangle("fill", x, y, w, h, 4, 4)
    if active then love.graphics.setColor(0.28, 0.9, 1, 0.95)
    elseif it.kind == "persona" then love.graphics.setColor(0.95, 0.55, 0.9, 0.8)
    else love.graphics.setColor(1, 1, 1, 0.32) end
    love.graphics.rectangle("line", x, y, w, h, 4, 4)
    if active then love.graphics.setColor(0.28, 0.9, 1, 1) else love.graphics.setColor(0.92, 0.92, 0.94, 1) end
    love.graphics.print(it.label, x + pad, y + math.floor((h - font:getHeight()) / 2))
    _btn_hit[#_btn_hit + 1] = { x = x, y = y, w = w, h = h, it = it }
    x = x + w + gap
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function DevScenario.mousepressed(x, y, button)
  if not (DevScenario.active and button == 1) then return false end
  for _, b in ipairs(_btn_hit) do
    if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
      if b.it.kind == "scene" then
        DevScenario.select(b.it.i)
      else
        _persona = (_persona == "neuro") and "evil" or "neuro"
      end
      return true
    end
  end
  return false
end

return DevScenario
