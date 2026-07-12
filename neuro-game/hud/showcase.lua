local Showcase = {}

local S = require("hud.state")
local StateKinds = require("core.state_kinds")
local Prims = require("hud.prims")
local smoothstep01 = Prims.smoothstep01

Showcase.FOOTER_SLOT_DURATION = 5.0
Showcase.FOOTER_EMOTE_EVERY = 3
Showcase.JOKER_SHOWCASE_DURATION = 4.8
Showcase.JOKER_SHOWCASE_FADE_IN = 0.30
Showcase.JOKER_SHOWCASE_FADE_OUT = 0.55
Showcase.BUY_SHOWCASE_DURATION = 1.8
Showcase.MONEY_COUNT_DURATION = 0.35
local BUY_SHOWCASE_DURATION = Showcase.BUY_SHOWCASE_DURATION
local BUY_SHOWCASE_FADE_IN = 0.16
local BUY_SHOWCASE_FADE_OUT = 0.30
local BUY_SHOWCASE_EXIT = 0.16
local BUY_SHOWCASE_MIN_DWELL = 0.5

local function pull_buy_showcase(now)
  if not (G and G.NEURO) then return end
  if S.buy_showcase then return end
  local q = G.NEURO.purchase_showcase_queue
  if type(q) ~= "table" or #q == 0 then return end
  local item = table.remove(q, 1)
  G.NEURO.purchase_showcase_queue = q
  if type(item) ~= "table" then return end
  S.buy_showcase = {
    card = item.card,
    name = tostring(item.name or "Purchase"),
    desc = tostring(item.desc or ""),
    cost = tonumber(item.cost) or 0,
    area = tostring(item.area or "shop"),
    started = now or 0,
  }
end

function Showcase.buy_alpha(sc, now)
  if not sc then return 0 end
  now = now or 0
  if sc.exit_started then
    return (1 - smoothstep01((now - sc.exit_started) / BUY_SHOWCASE_EXIT)) * (sc.exit_a or 1)
  end
  local elapsed = now - (sc.started or 0)
  if elapsed < BUY_SHOWCASE_FADE_IN then
    return smoothstep01(elapsed / BUY_SHOWCASE_FADE_IN)
  elseif elapsed > (BUY_SHOWCASE_DURATION - BUY_SHOWCASE_FADE_OUT) then
    return smoothstep01((BUY_SHOWCASE_DURATION - elapsed) / BUY_SHOWCASE_FADE_OUT)
  end
  return 1
end

function Showcase.update_buy(now)
  pull_buy_showcase(now)
  if not S.buy_showcase then return end
  now = now or 0
  local sc = S.buy_showcase

  if sc.exit_started then
    if (now - sc.exit_started) >= BUY_SHOWCASE_EXIT then
      S.buy_showcase = nil
      pull_buy_showcase(now)
    end
    return
  end

  local q = G and G.NEURO and G.NEURO.purchase_showcase_queue
  local has_pending = type(q) == "table" and #q > 0
  local elapsed = now - (sc.started or 0)

  if has_pending and elapsed >= BUY_SHOWCASE_MIN_DWELL then
    sc.exit_started = now
    sc.exit_a = Showcase.buy_alpha(sc, now)
    return
  end

  if elapsed >= BUY_SHOWCASE_DURATION then
    S.buy_showcase = nil
    pull_buy_showcase(now)
  end
end

function Showcase.card_set_label(c)
  local set = c and c.config and c.config.center and c.config.center.set
  if set == "Joker"    then return "NEW JOKER"
  elseif set == "Planet"   then return "NEW PLANET"
  elseif set == "Tarot"    then return "NEW TAROT"
  elseif set == "Spectral" then return "NEW SPECTRAL"
  elseif set == "Voucher"  then return "VOUCHER"
  else return "NEW CARD" end
end

local function is_in_pack_state()
  if not G then return false end
  local sn = (G.NEURO and (G.NEURO.force_state or G.NEURO.state)) or ""
  return StateKinds.is_pack_state(sn)
end

local function push_showcase(c, label, _now)
  local item = {card = c, label = label or Showcase.card_set_label(c)}
  if is_in_pack_state() then
    S.pack_gained_q[#S.pack_gained_q + 1] = item
    while #S.pack_gained_q > 10 do table.remove(S.pack_gained_q, 1) end
  else
    S.joker_showcase_q[#S.joker_showcase_q + 1] = item
    while #S.joker_showcase_q > 10 do table.remove(S.joker_showcase_q, 1) end
  end
end

local function pull_showcase(now)
  if not S.joker_showcase and #S.joker_showcase_q > 0 then
    local item = table.remove(S.joker_showcase_q, 1)
    S.joker_showcase = {card = item.card, label = item.label, started = now or 0}
  end
end

function Showcase.update_joker(now)
  if not G then S.known_joker_refs = nil; S.known_cons_refs = nil; return end

  if G.jokers and G.jokers.cards then
    local cur = {}
    for _, c in ipairs(G.jokers.cards) do cur[c] = true end
    if S.known_joker_refs then
      for _, c in ipairs(G.jokers.cards) do
        if not S.known_joker_refs[c] then push_showcase(c, "NEW JOKER", now) end
      end
    end
    S.known_joker_refs = cur
  else
    S.known_joker_refs = nil
  end

  if G.consumeables and G.consumeables.cards then
    local cur = {}
    for _, c in ipairs(G.consumeables.cards) do cur[c] = true end
    if S.known_cons_refs then
      for _, c in ipairs(G.consumeables.cards) do
        if not S.known_cons_refs[c] then push_showcase(c, nil, now) end
      end
    end
    S.known_cons_refs = cur
  else
    S.known_cons_refs = nil
  end

  if not is_in_pack_state() and #S.pack_gained_q > 0 then
    for _, item in ipairs(S.pack_gained_q) do
      S.joker_showcase_q[#S.joker_showcase_q + 1] = item
    end
    S.pack_gained_q = {}
  end

  pull_showcase(now)
end

function Showcase.on_state_change()
  S.joker_showcase = nil
  S.joker_showcase_q = {}
  S.pack_gained_q = {}
  S.buy_showcase = nil
  S.pack_card_indices = {}
  if G and G.NEURO then G.NEURO.purchase_showcase_queue = {} end
end

return Showcase
