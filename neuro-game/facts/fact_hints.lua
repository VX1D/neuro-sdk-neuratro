local M = {}

local GameFacts = require("facts.game_facts")
local CardUtil = require("facts.card_util")

local Utils = require("util.utils")
local Once = require("util.once")
local HintRegistry = require("facts.hint_registry")

local pending, pending_seen = {}, {}

local CHANNEL = {
  state_entry = "hint:",
  decision = "dhint:",
  session = "shint:",
  round = "rdhint:",
  run = "rhint:",
}

local function reset_pending()
  pending, pending_seen = {}, {}
end

local function queue_hint(key, epoch, text)
  if not (G and G.NEURO and text and text ~= "") then
    return ""
  end
  if pending_seen[key] or not Once.peek(key, epoch) then
    return ""
  end
  pending_seen[key] = true
  pending[#pending + 1] = { key = key, epoch = epoch, text = text }
  return ""
end

local function once_per_state_entry_hint(tag, text)
  if not (G and G.NEURO) then return "" end
  return queue_hint(CHANNEL.state_entry .. tostring(tag or "hint"),
    tonumber(G.NEURO.state_enter_serial or 0) or 0, text)
end

local function once_per_decision_hint(tag, text)
  if not (G and G.NEURO) then return "" end
  return queue_hint(CHANNEL.decision .. tostring(tag or "hint"),
    tonumber(G.NEURO.decision_serial or 0) or 0, text)
end

local function round_hint_key(tag)
  local round = GameFacts.round()
  if not round then return nil end
  return CHANNEL.round .. tostring(tag or "hint") .. ":" .. tostring(round)
end

local function once_per_round_hint(tag, text)
  if not (G and G.NEURO) then return "" end
  local key = round_hint_key(tag)
  if not key then return "" end
  return queue_hint(key, "run", text)
end

local function once_per_session_hint(tag, text)
  if not (G and G.NEURO) then return "" end
  return queue_hint(CHANNEL.session .. tostring(tag or "hint"), "session", text)
end

local function once_per_run_hint(tag, text)
  if not (G and G.NEURO) then return "" end
  return queue_hint(CHANNEL.run .. tostring(tag or "hint"), "run", text)
end

local function gate_for(tag, cadence)
  if not (G and G.NEURO) then return nil, nil end
  if cadence == "state_entry" then
    return CHANNEL.state_entry .. tostring(tag), tonumber(G.NEURO.state_enter_serial or 0) or 0
  elseif cadence == "decision" then
    return CHANNEL.decision .. tostring(tag), tonumber(G.NEURO.decision_serial or 0) or 0
  elseif cadence == "round" then
    return round_hint_key(tag), "run"
  elseif cadence == "session" then
    return CHANNEL.session .. tostring(tag), "session"
  elseif cadence == "run" then
    return CHANNEL.run .. tostring(tag), "run"
  end
  return nil, nil
end

local function emit(tag, text)
  if type(text) ~= "string" or text == "" then return "" end
  local entry = HintRegistry.lookup(tag)
  if not entry then
    require("util.metrics").incr("hint_unregistered")
    if rawget(_G, "NEURO_TEST") then
      error("hint tag not registered in facts/hint_registry.lua: " .. tostring(tag), 2)
    end
    print("[neuro-game] unregistered hint tag routed to the context channel: " .. tostring(tag))
    return once_per_run_hint(tag, text)
  end
  if entry.cadence == "always" then return text end
  if not (G and G.NEURO) then return "" end
  local key, epoch = gate_for(tag, entry.cadence)
  if not key then return "" end
  if HintRegistry.channel_of(entry) == "query" then
    return Once.once_until(key, epoch) and text or ""
  end
  return queue_hint(key, epoch, text)
end

local function pending_count()
  return #pending
end

local function key_matches_tag(key, tag)
  for _, prefix in pairs(CHANNEL) do
    if key:sub(1, #prefix) == prefix then
      local rest = key:sub(#prefix + 1)
      if rest == tag or rest:sub(1, #tag + 1) == tag .. ":" then
        return true
      end
    end
  end
  return false
end

local function hint_is_pending(tag)
  tag = tostring(tag)
  for key in pairs(pending_seen) do
    if key_matches_tag(key, tag) then return true end
  end
  return false
end

local function drop_hint(tag)
  tag = tostring(tag)
  local keys = {}
  for key in pairs(pending_seen) do
    if key_matches_tag(key, tag) then keys[#keys + 1] = key end
  end
  for _, key in ipairs(keys) do
    pending_seen[key] = nil
    for i = #pending, 1, -1 do
      if pending[i].key == key then table.remove(pending, i) end
    end
  end
end

local function flush_pending()
  if #pending == 0 then return 0 end
  local queued = pending
  reset_pending()
  if not Utils.can_send() then return 0 end
  local Delivery = require("core.context_delivery")
  local accepted = 0
  for _, h in ipairs(queued) do
    local key, epoch = h.key, h.epoch
    local ok = Delivery.rule("hint:" .. h.key .. "@" .. tostring(h.epoch), h.text, {
      on_written = function() Once.book(key, epoch) end,
    })
    if ok then accepted = accepted + 1 end
  end
  return accepted
end

local function chain_visible(card, target)
  if CardUtil.is_face_down(card) then return false end
  return not (target and CardUtil.is_face_down(target))
end

local function blueprint_chain_hint(force_visible)
  if not (G and G.jokers and G.jokers.cards) then return "" end
  local cards = G.jokers.cards
  local chain_parts = {}
  for i, card in ipairs(cards) do
    local kind = CardUtil.copy_joker_kind(card)
    if kind then
      local target = (kind == "brainstorm") and cards[1] or cards[i + 1]
      if target == card then target = nil end
      if chain_visible(card, target) then
        local nm = card and card.ability and card.ability.name
          or (kind == "brainstorm" and "Brainstorm" or "Blueprint")
        local target_nm = target and target.ability and target.ability.name or "none"
        local where = (kind == "brainstorm") and "the leftmost joker" or "the joker to its right"
        chain_parts[#chain_parts + 1] = string.format("%s (slot %d) copies %s (%s)", nm, i, where, target_nm)
      end
    end
  end
  if #chain_parts == 0 then return "" end
  local chain = table.concat(chain_parts, "; ")
  local text = "Joker copy order: " .. chain .. ". Order matters. "
  return force_visible and text or emit("bp_chain:" .. chain, text)
end

M.VOUCHER_CHAINS = {
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

local function voucher_chain_hint()
  if not (G and G.GAME) then return "" end
  local owned = G.GAME.used_vouchers or {}
  local chains = M.VOUCHER_CHAINS
  local shop_keys = {}
  if G.shop_vouchers and G.shop_vouchers.cards then
    for _, card in ipairs(G.shop_vouchers.cards) do
      local center = card.config and card.config.center
      local key = center and center.key or ""
      if key ~= "" then shop_keys[key] = true end
    end
  end
  local out = {}
  for _, pair in ipairs(chains) do
    local relevant = (shop_keys[pair.base] and not owned[pair.base])
      or (shop_keys[pair.upgrade] and owned[pair.base])
    if relevant then
      out[#out + 1] = emit("voucher_chain:" .. pair.base,
        string.format("Owning %s unlocks %s in later shops. ", pair.base_name, pair.up_name))
    end
  end
  return table.concat(out, "")
end

local function voucher_basics_hint()
  if not (G and G.shop_vouchers and G.shop_vouchers.cards and G.shop_vouchers.cards[1]) then return "" end
  return emit("voucher_basics_run",
    "A voucher is a permanent, run-wide upgrade that lasts the rest of the run once bought. Rerolling the shop never replaces a voucher on offer -- a reroll only redraws the cards for sale. The vouchers a shop is offering are listed with that shop. ")
end

local function shop_edition_hint()
  if not (G and G.shop_jokers and G.shop_jokers.cards) then return "" end
  local parts = {}
  for _, c in ipairs(G.shop_jokers.cards) do
    if c.edition and CardUtil.card_set(c) == "Joker" then
      local tag = CardUtil.edition_name(c.edition)
      if tag and tag ~= "" then
        local nm = (c.ability and c.ability.name) or "Joker"
        parts[#parts + 1] = nm .. " (" .. tag .. ")"
      end
    end
  end
  if #parts == 0 then return "" end
  return emit("shop_edition:" .. table.concat(parts, "|"),
    "Shop editions: " .. table.concat(parts, ", ")
    .. ". The edition is attached to that Joker; its listed edition effect applies alongside the card text and occupies no separate Joker slot. "
    .. "Editions are permanent and stack on the base effect, and are hard to add later (only a few consumables can). Worth taking when a joker slot is open. ")
end

local function plan_note(window)
  local p = G and G.NEURO and G.NEURO.plan
  if not p or not (p.hand or p.build or p.money or p.hand_focus or p.boss) then return "" end
  local cur = GameFacts.ante(0)
  local can_amend = (window == "shop" or window == "blind")
  local bits = {}
  local marks = {}
  local function provenance(field)
    local rec = p.provenance and p.provenance[field]
    local source_ante = type(rec) == "table" and tonumber(rec.ante) or tonumber(p.ante)
    local mark = { }
    if type(rec) == "table" then
      mark.ante = tostring(rec.ante or "?")
      mark.decision = tostring(rec.decision_serial or "?")
      mark.sig = mark.ante .. "@" .. mark.decision
      mark.label = string.format(" (written by you, Ante %s, decision %s)", mark.ante, mark.decision)
    end
    marks[#marks + 1] = mark
    local stale = ""
    if source_ante and cur > source_ante then
      local d = cur - source_ante
      stale = string.format(" [set %d ante%s ago -- update it if it no longer fits]",
        d, d == 1 and "" or "s")
    end
    return "\1" .. #marks .. "\2" .. stale
  end
  local function add_build()
    if not p.build then return end
    if require("core.plan_gate").build_plan_is_current(p) then
      bits[#bits + 1] = "Build focus" .. provenance("build") .. ": " .. p.build
    elseif can_amend then
      bits[#bits + 1] = "Your build last shop" .. provenance("build") .. ": '" .. p.build
        .. "'. Roster changed -- continue this direction, iterate on it, or change it (record_plan build_plan)."
    else
      bits[#bits + 1] = "Your earlier build plan" .. provenance("build") .. ": '" .. p.build .. "'."
    end
  end
  local function add_hand()
    if p.hand then
      if require("core.plan_gate").hand_plan_is_current(p) then
        bits[#bits + 1] = "Hand decision" .. provenance("hand") .. ": " .. p.hand
      elseif can_amend then
        bits[#bits + 1] = "Your hand plan last blind" .. provenance("hand") .. ": '" .. p.hand
          .. "'. Blind changed -- keep this line, adapt it, or set a new one (record_plan hand_plan)."
      else
        bits[#bits + 1] = "Your earlier hand plan" .. provenance("hand") .. ": '" .. p.hand .. "'."
      end
    end
    if type(p.hand_focus) == "table" and require("core.plan_gate").hand_focus_is_current(p) then
      local focus = "Declared hand focus" .. provenance("focus") .. ": primary "
        .. tostring(p.hand_focus.primary)
      if p.hand_focus.fallback then focus = focus .. ", fallback " .. tostring(p.hand_focus.fallback) end
      bits[#bits + 1] = focus
    end
  end
  local function add_boss()
    if not p.boss then return end
    local blind = G.GAME and G.GAME.blind
    if not (blind and blind.boss) then return end
    if not require("core.plan_gate").boss_plan_is_current(p) then return end
    bits[#bits + 1] = "Your boss-round plan" .. provenance("boss") .. ": '" .. tostring(p.boss) .. "'"
  end
  local function add_money()
    if not p.money then return end
    if require("core.plan_gate").money_plan_is_current(p) then
      bits[#bits + 1] = "Economy decision" .. provenance("money") .. ": " .. p.money
    elseif can_amend then
      bits[#bits + 1] = "Your last economy call" .. provenance("money") .. ": '" .. p.money
        .. "'. Shop/economy changed -- hold it or revise (record_plan money_plan)."
    else
      bits[#bits + 1] = "Your earlier economy call" .. provenance("money") .. ": '" .. p.money .. "'."
    end
  end
  local lead
  if window == "shop" then
    add_build(); add_hand(); add_money()
    lead = "Your decision notes -- do not treat them as a snapshot; current shop rows and facts win, revise only fields changed by your action: "
  elseif window == "pack" then
    add_build(); add_hand()
    lead = "Your decision notes -- pick to advance the diagnosed weakness; current pack contents and game facts are authoritative: "
  elseif window == "blind" then
    add_hand(); add_build()
    lead = "Current-blind decision notes -- facts win; revise with record_plan if your intended line changed: "
  elseif window == "hand" then
    add_boss(); add_hand(); add_build()
    lead = "Your plan this round -- facts win; the hand and build lines cannot be revised until the shop or next blind select: "
  else
    return ""
  end
  if #bits == 0 then return "" end
  local body = table.concat(bits, " · ")
  local counts, top, top_n, unattributed = {}, nil, 0, false
  for _, m in ipairs(marks) do
    if m.sig then
      counts[m.sig] = (counts[m.sig] or 0) + 1
      if counts[m.sig] > top_n then top, top_n = m, counts[m.sig] end
    else
      unattributed = true
    end
  end
  local hoist = (not unattributed) and top_n >= 2
  local shared = ""
  if hoist then
    shared = string.format(" %s written by you, Ante %s, decision %s.",
      (top_n == #marks) and "All" or "The rest", top.ante, top.decision)
  end
  for i, m in ipairs(marks) do
    local inline = (hoist and m.sig == top.sig) and "" or (m.label or "")
    body = body:gsub("\1" .. i .. "\2", function() return inline end)
  end
  if not body:match("[%.!?]$") then body = body .. "." end
  return lead .. body .. shared .. " "
end

local function joker_churn_note()
  local N = G and G.NEURO
  if not N then return "" end
  local epoch = tonumber(N.shop_visit_epoch) or 0
  local rec = N.jokers_sold
  local sold = (type(rec) == "table" and rec.epoch == epoch and rec.count) or 0
  if sold < 1 then return "" end
  return string.format(
    "You have sold %d joker%s this shop visit -- jokers are your scoring engine; do not keep selling them for cash, only for a specific planned buy. ",
    sold, sold == 1 and "" or "s")
end

M.plan_note = plan_note
M.joker_churn_note = joker_churn_note
M.reset_pending = reset_pending
M.flush_pending = flush_pending
M.emit = emit
M.blueprint_chain_hint = blueprint_chain_hint
M.voucher_chain_hint = voucher_chain_hint
M.voucher_basics_hint = voucher_basics_hint
M.shop_edition_hint = shop_edition_hint

if _G.NEURO_TEST then
  M.once_per_state_entry_hint = once_per_state_entry_hint
  M.once_per_decision_hint = once_per_decision_hint
  M.once_per_session_hint = once_per_session_hint
  M.once_per_round_hint = once_per_round_hint
  M.once_per_run_hint = once_per_run_hint
  M.hint_is_pending = hint_is_pending
  M.drop_hint = drop_hint
  M.pending_count = pending_count
end

return M
