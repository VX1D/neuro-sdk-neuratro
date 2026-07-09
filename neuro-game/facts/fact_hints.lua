local M = {}

local CardUtil = require("facts.card_util")

local once_until = require("util.once").once_until
local function once_per_state_entry_hint(tag, text)
  if not (G and G.NEURO and text and text ~= "") then
    return ""
  end
  local serial = tonumber(G.NEURO.state_enter_serial or 0) or 0
  if once_until("hint:" .. tostring(tag or "hint"), serial) then
    return text
  end
  return ""
end

local function blueprint_chain_hint()
  if not (G and G.jokers and G.jokers.cards) then return "" end
  local cards = G.jokers.cards
  local chain_parts = {}
  for i, card in ipairs(cards) do
    local kind = CardUtil.copy_joker_kind(card)
    if kind then
      local nm = card and card.ability and card.ability.name
        or (kind == "brainstorm" and "Brainstorm" or "Blueprint")
      local target = (kind == "brainstorm") and cards[1] or cards[i + 1]
      if target == card then target = nil end
      local dir = (kind == "brainstorm") and "leftmost" or "right"
      local target_nm = target and target.ability and target.ability.name or "none"
      -- no xMult suffix: conditional jokers share Cavendish's extra.Xmult storage, so a flat number would misreport them
      chain_parts[#chain_parts + 1] = string.format("%s[%d]->copies %s(%s)", nm, i, target_nm, dir)
    end
  end
  if #chain_parts == 0 then return "" end
  return once_per_state_entry_hint("bp_chain",
    "JOKER CHAIN: " .. table.concat(chain_parts, "; ") .. ". Position-sensitive. ")
end

local function voucher_chain_hint()
  if not (G and G.GAME) then return "" end
  local owned = G.GAME.used_vouchers or {}
  local chains = {
    {base="v_overstock_norm",  upgrade="v_overstock_plus",  base_name="Overstock",       up_name="Overstock Plus"},
    {base="v_clearance_sale",  upgrade="v_liquidation",     base_name="Clearance Sale",  up_name="Liquidation"},
    {base="v_hone",            upgrade="v_glow_up",         base_name="Hone",            up_name="Glow Up"},
    {base="v_reroll_surplus",  upgrade="v_reroll_glut",     base_name="Reroll Surplus",  up_name="Reroll Glut"},
    {base="v_crystal_ball",    upgrade="v_omen_globe",      base_name="Crystal Ball",    up_name="Omen Globe"},
    {base="v_telescope",       upgrade="v_observatory",     base_name="Telescope",       up_name="Observatory"},
    {base="v_grabber",         upgrade="v_nacho_tong",      base_name="Grabber",         up_name="Nacho Tong"},
    {base="v_wasteful",        upgrade="v_recyclomancy",    base_name="Wasteful",        up_name="Recyclomancy"},
    {base="v_tarot_merchant",  upgrade="v_tarot_tycoon",    base_name="Tarot Merchant",  up_name="Tarot Tycoon"},
    {base="v_planet_merchant", upgrade="v_planet_tycoon",   base_name="Planet Merchant", up_name="Planet Tycoon"},
    {base="v_seed_money",      upgrade="v_money_tree",      base_name="Seed Money",      up_name="Money Tree"},
    {base="v_blank",           upgrade="v_antimatter",      base_name="Blank",           up_name="Antimatter"},
    {base="v_magic_trick",     upgrade="v_illusion",        base_name="Magic Trick",     up_name="Illusion"},
    {base="v_hieroglyph",      upgrade="v_petroglyph",      base_name="Hieroglyph",      up_name="Petroglyph"},
    {base="v_directors_cut",   upgrade="v_retcon",          base_name="Director's Cut",  up_name="Retcon"},
    {base="v_paint_brush",     upgrade="v_palette",         base_name="Paint Brush",     up_name="Palette"},
  }
  local shop_keys = {}
  if G.shop_vouchers and G.shop_vouchers.cards then
    for _, card in ipairs(G.shop_vouchers.cards) do
      local center = card.config and card.config.center
      local key = center and center.key or ""
      if key ~= "" then shop_keys[key] = true end
    end
  end
  local hints = {}
  for _, pair in ipairs(chains) do
    if shop_keys[pair.base] and not owned[pair.base] then
      hints[#hints + 1] = string.format("%s visible; owning it unlocks %s in later shops", pair.base_name, pair.up_name)
    elseif shop_keys[pair.upgrade] and owned[pair.base] then
      hints[#hints + 1] = string.format("%s visible (upgrade of %s)", pair.up_name, pair.base_name)
    end
  end
  if #hints == 0 then return "" end
  return once_per_state_entry_hint("voucher_chain",
    "VOUCHER CHAINS: " .. table.concat(hints, "; ") .. ". ")
end

-- reroll only rebuilds shop_jokers -- the voucher slot is untouched by reroll
local function voucher_basics_hint()
  if not (G and G.shop_vouchers and G.shop_vouchers.cards and G.shop_vouchers.cards[1]) then return "" end
  return once_per_state_entry_hint("voucher_basics",
    "A voucher is a permanent, run-wide upgrade (not a one-round item); one is offered per shop, and rerolling only replaces the joker/consumable row -- the voucher stays until bought. ")
end

local function shop_edition_hint()
  if not (G and G.shop_jokers and G.shop_jokers.cards) then return "" end
  local parts = {}
  for _, c in ipairs(G.shop_jokers.cards) do
    if c.edition and CardUtil.card_set(c) == "Joker" then
      local tag = CardUtil.edition_tag(c.edition)
      if tag then
        parts[#parts + 1] = ((c.ability and c.ability.name) or "Joker") .. "(" .. tag .. ")"
      end
    end
  end
  if #parts == 0 then return "" end
  return once_per_state_entry_hint("shop_edition",
    "SHOP EDITIONS: " .. table.concat(parts, ", ")
    .. ". Editions are permanent and stack on the joker's base effect; an edition can only be added to a joker you already own at random, by a few consumables (The Wheel of Fortune, Hex, Ectoplasm)"
    .. " -- high-value, usually worth taking when a joker slot is open (especially if your current jokers are weak). ")
end

M.once_per_state_entry_hint = once_per_state_entry_hint
M.blueprint_chain_hint = blueprint_chain_hint
M.voucher_chain_hint = voucher_chain_hint
M.voucher_basics_hint = voucher_basics_hint
M.shop_edition_hint = shop_edition_hint

return M
