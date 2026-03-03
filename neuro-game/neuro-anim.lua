-- neuro-anim.lua
-- Cinematic animation sequences for Neuro's in-game actions.
-- Hooked from dispatcher.lua and neuro-game.lua.

local NeuroAnim = {}

-- ─────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────

local function now()
  return (G and G.TIMERS and G.TIMERS.REAL) or os.clock()
end

local function after(delay, fn)
  if G and G.E_MANAGER and Event then
    G.E_MANAGER:add_event(Event({
      trigger   = "after",
      delay     = delay,
      blockable = false,
      func      = function() pcall(fn); return true end,
    }))
  end
end

local function immediate(fn)
  if G and G.E_MANAGER and Event then
    G.E_MANAGER:add_event(Event({
      blockable = false,
      func      = function() pcall(fn); return true end,
    }))
  else
    pcall(fn)
  end
end

local function sound(name, pitch, vol)
  pcall(function() play_sound(name, pitch or 1, vol or 0.8) end)
end

local function juice(card, sc, rot)
  if card and card.juice_up then
    pcall(function() card:juice_up(sc or 0.3, rot or 0.2) end)
  end
end

local function float_text(text, opts)
  opts = opts or {}
  local major = opts.major
  if not major then
    major = (G and (G.play or G.hand or G.HUD_tags))
  end
  if not major then return end
  pcall(function()
    attention_text({
      text         = text,
      scale        = opts.scale  or 1.3,
      colour       = opts.colour or {1, 1, 1, 1},
      hold         = opts.hold   or 1.2,
      align        = "cm",
      offset       = { x = opts.ox or 0, y = opts.oy or -2.6 },
      major        = major,
      noisy        = opts.noisy,
      rotate       = opts.rotate,
    })
  end)
end

-- ─────────────────────────────────────────────────────────────
-- PACK: hover before pick
-- Called right after LLM decision, before E_MANAGER delay fires.
-- ─────────────────────────────────────────────────────────────
function NeuroAnim.hover_pack_card(card, bp)
  if not card then return end

  local total = (bp and bp.cards and #bp.cards) or 0
  local is_last = (total <= 1)

  immediate(function()
    juice(card, is_last and 0.9 or 0.55, is_last and 0.45 or 0.3)
    card.highlighted = true
    sound("card1", 0.85 + math.random() * 0.2, 0.55)
  end)

  -- Fan other cards gently back
  after(0.15, function()
    if bp and bp.cards then
      for _, c in ipairs(bp.cards) do
        if c ~= card then juice(c, 0.08, 0.04) end
      end
    end
  end)

  -- Hover text
  after(0.25, function()
    if is_last then
      float_text("Last pick...", {
        scale  = 1.1,
        colour = {1, 0.85, 0.25, 0.9},
        hold   = 1.0,
        oy     = -2.9,
        major  = bp or (G and (G.pack_cards or G.booster_pack or G.play)),
      })
    else
      float_text("Considering...", {
        scale  = 0.9,
        colour = {1, 1, 1, 0.7},
        hold   = 0.85,
        oy     = -2.9,
        major  = bp or (G and (G.pack_cards or G.booster_pack or G.play)),
      })
    end
  end)
end

-- ─────────────────────────────────────────────────────────────
-- PACK: actual pick fires (inside E_MANAGER delayed event)
-- ─────────────────────────────────────────────────────────────
function NeuroAnim.pick_pack_card(card, bp)
  if not card then return end

  local total    = (bp and bp.cards and #bp.cards) or 0
  local is_last  = (total <= 1)

  -- Strong juice + sound
  juice(card, is_last and 1.1 or 0.75, is_last and 0.55 or 0.38)
  sound("whoosh1", 0.8 + math.random() * 0.15, 0.85)
  card.highlighted = false

  -- Victory text
  after(0.05, function()
    if is_last then
      -- Boom sound burst
      sound("gold_seal",  1.15 + math.random() * 0.1, 1.0)
      after(0.08, function() sound("whoosh1",  1.3, 0.7) end)
      after(0.18, function() sound("gold_seal", 0.9, 0.6) end)

      float_text("NICE PICK!", {
        scale  = 2.4,
        colour = {0.25, 1, 0.5, 1},
        hold   = 2.5,
        noisy  = true,
        oy     = 0,
        major  = bp or (G and (G.pack_cards or G.booster_pack or G.play)),
      })

      -- Boom: staggered card punches
      after(0.0,  function() juice(card, 1.2, 0.65) end)
      after(0.12, function() juice(card, 0.7, 0.40) end)
      after(0.26, function() juice(card, 0.4, 0.22) end)
    else
      float_text("Picked!", {
        scale  = 1.3,
        colour = {1, 1, 1, 1},
        hold   = 1.0,
        oy     = -2.6,
        major  = bp or (G and (G.pack_cards or G.booster_pack or G.play)),
      })
    end
  end)
end

-- ─────────────────────────────────────────────────────────────
-- HAND: pre-play card juice (staggered)
-- ─────────────────────────────────────────────────────────────
function NeuroAnim.pre_play(highlighted)
  if not highlighted or #highlighted == 0 then return end
  for i, c in ipairs(highlighted) do
    local cc, d = c, (i - 1) * 0.04
    after(d, function()
      juice(cc, 0.35, 0.2)
      sound("card1", 0.9 + math.random() * 0.15, 0.3)
    end)
  end
end

-- ─────────────────────────────────────────────────────────────
-- HAND: pre-discard card juice (staggered, reddish feel via sound)
-- ─────────────────────────────────────────────────────────────
function NeuroAnim.pre_discard(highlighted)
  if not highlighted or #highlighted == 0 then return end
  for i, c in ipairs(highlighted) do
    local cc, d = c, (i - 1) * 0.035
    after(d, function()
      juice(cc, 0.25, 0.15)
    end)
  end
  sound("whoosh1", 1.1 + math.random() * 0.1, 0.35)
end

-- ─────────────────────────────────────────────────────────────
-- SHOP ENTRY: stagger-juice all items
-- ─────────────────────────────────────────────────────────────
function NeuroAnim.on_shop_enter()
  after(0.25, function()
    local delay = 0
    local areas = { G.shop_jokers, G.shop_vouchers, G.shop_booster }
    for _, area in ipairs(areas) do
      if area and area.cards then
        for _, c in ipairs(area.cards) do
          local cc, d = c, delay
          after(d, function() juice(cc, 0.22, 0.14) end)
          delay = delay + 0.06
        end
      end
    end
  end)
end

-- ─────────────────────────────────────────────────────────────
-- SHOP BUY: juice the purchased card
-- ─────────────────────────────────────────────────────────────
function NeuroAnim.on_buy(card)
  if not card then return end
  immediate(function()
    juice(card, 0.6, 0.35)
    sound("gold_seal", 1.0 + math.random() * 0.1, 0.5)
  end)
end

-- ─────────────────────────────────────────────────────────────
-- ROUND EVAL: blind cleared celebration
-- ─────────────────────────────────────────────────────────────
function NeuroAnim.on_round_eval()
  after(0.4, function()
    sound("gold_seal", 0.9, 0.7)
    float_text("BLIND CLEARED!", {
      scale  = 1.9,
      colour = {1, 0.85, 0.2, 1},
      hold   = 2.2,
      noisy  = true,
      oy     = -1.8,
      major  = G and G.play,
    })
  end)
  -- Juice jokers in celebration
  after(0.55, function()
    if G and G.jokers and G.jokers.cards then
      for i, c in ipairs(G.jokers.cards) do
        local cc, d = c, (i - 1) * 0.09
        after(d, function() juice(cc, 0.45, 0.28) end)
      end
    end
  end)
end

-- ─────────────────────────────────────────────────────────────
-- BLIND SELECT: juice the three blind cards on entry
-- ─────────────────────────────────────────────────────────────
function NeuroAnim.on_blind_select()
  after(0.5, function()
    local delay = 0
    local areas = { G.blind_select_opts }
    for _, area in ipairs(areas) do
      if area and area.cards then
        for _, c in ipairs(area.cards) do
          local cc, d = c, delay
          after(d, function() juice(cc, 0.3, 0.18) end)
          delay = delay + 0.12
        end
      end
    end
  end)
end

-- ─────────────────────────────────────────────────────────────
-- CAN CLEAR NOW: hint that she can win this hand
-- ─────────────────────────────────────────────────────────────
function NeuroAnim.on_can_clear(hand_type)
  after(0.1, function()
    local txt = hand_type and ("WIN: " .. hand_type) or "CAN WIN!"
    float_text(txt, {
      scale  = 1.5,
      colour = {0.25, 1, 0.5, 1},
      hold   = 1.8,
      noisy  = true,
      oy     = -2.0,
      major  = G and G.play,
    })
    -- Juice all jokers
    if G and G.jokers and G.jokers.cards then
      for _, c in ipairs(G.jokers.cards) do
        juice(c, 0.3, 0.18)
      end
    end
  end)
end

-- ─────────────────────────────────────────────────────────────
-- STATE ENTRY DISPATCHER
-- ─────────────────────────────────────────────────────────────
local _last_anim_state = nil

function NeuroAnim.on_state_enter(state_name)
  if state_name == _last_anim_state then return end
  _last_anim_state = state_name

  if state_name == "SHOP" then
    NeuroAnim.on_shop_enter()
  elseif state_name == "ROUND_EVAL" then
    NeuroAnim.on_round_eval()
  elseif state_name == "BLIND_SELECT" then
    NeuroAnim.on_blind_select()
  end
end

return NeuroAnim
