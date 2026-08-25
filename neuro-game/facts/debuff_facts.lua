local M = {}
local BossModel = require("facts.boss.model")

function M.count(cards)
  if type(cards) ~= "table" then return 0 end
  local n = 0
  for _, c in ipairs(cards) do
    if type(c) == "table" and c.debuff then n = n + 1 end
  end
  return n
end

local function blind_is(b, key)
  if type(b) ~= "table" then return false end
  if b.key == key then return true end
  local center = b.config and b.config.blind
  if type(center) == "table" and center.key == key then return true end
  return b.name == BossModel.boss_name(key)
end
if _G.NEURO_TEST then
  M.blind_is = blind_is
end

function M.pillar_active()
  local b = G and G.GAME and G.GAME.blind
  return not not (type(b) == "table" and not b.disabled and blind_is(b, "bl_pillar"))
end

function M.pillar_used_indices(cards)
  local out, n = {}, 0
  if type(cards) == "table" and M.pillar_active() then
    for i, c in ipairs(cards) do
      if type(c) == "table" and c.debuff and type(c.ability) == "table" and c.ability.played_this_ante then
        out[i] = true; n = n + 1
      end
    end
  end
  return out, n
end

local function pillar_used_count(cards)
  local _, n = M.pillar_used_indices(cards)
  return n
end

function M.played_this_ante_count()
  local n = 0
  local cards = G and G.playing_cards
  if type(cards) ~= "table" then return 0 end
  for _, c in ipairs(cards) do
    if type(c) == "table" and type(c.ability) == "table" and c.ability.played_this_ante then n = n + 1 end
  end
  return n
end

local function loc_hand(name)
  if not name then return name end
  local loc = rawget(_G, "localize")
  if type(loc) == "function" then
    local ok, res = pcall(loc, name, "poker_hands")
    if ok and type(res) == "string" and res ~= "" and res ~= "ERROR" then return res end
  end
  return name
end
M.loc_hand = loc_hand

local function subst_vars(txt, vars)
  if type(txt) ~= "string" or not txt:find("#%d+#") then return txt end
  return (txt:gsub("#(%d+)#", function(n)
    if type(vars) == "table" and vars[tonumber(n)] ~= nil then
      return tostring(vars[tonumber(n)])
    end
    return "?"
  end))
end

function M.boss_debuff_text(blind, vars)
  if type(blind) ~= "table" or blind.disabled then return "" end
  vars = vars or blind.vars
  if type(blind.get_loc_debuff_text) == "function" then
    local ok, v = pcall(blind.get_loc_debuff_text, blind)
    if ok and type(v) == "string" and v ~= "" then return subst_vars(v, vars) end
  end
  if type(blind.loc_debuff_text) == "string" and blind.loc_debuff_text ~= "" then
    return subst_vars(blind.loc_debuff_text, vars)
  end
  local t = blind.loc_txt
  if type(t) == "table" then
    if type(t.text) == "table" and #t.text > 0 then return subst_vars(table.concat(t.text, " "), vars) end
    if type(t.name) == "string" and t.name ~= "" then return t.name end
  end
  return ""
end

local function raw_desc(set, key, vars)
  local loc = rawget(_G, "localize")
  if type(loc) ~= "function" or not key then return nil end
  local ok, lines = pcall(loc, { type = "raw_descriptions", set = set, key = key, vars = vars or {} })
  if ok and type(lines) == "table" and #lines > 0 then
    local out = table.concat(lines, " ")
    if out:find("%S") then return out end
  end
  return nil
end

function M.most_played_hand()
  local mp = G and G.GAME and G.GAME.current_round and G.GAME.current_round.most_played_poker_hand
  if mp and mp ~= "" then return tostring(mp) end
  return nil
end

function M.blind_effect_text(key, blind_def)
  blind_def = blind_def or (G and G.P_BLINDS and key and G.P_BLINDS[key])
  if type(blind_def) ~= "table" then return "" end
  local vars = blind_def.vars
  if blind_is(blind_def, "bl_ox") then
    local mp = M.most_played_hand()
    if mp then vars = { loc_hand(mp) } end
  end
  local set = blind_def.set or "Blind"
  if type(blind_def.loc_vars) == "function" then
    local ok, res = pcall(blind_def.loc_vars, blind_def, {})
    if ok and type(res) == "table" then
      vars = res.vars or vars
      key = res.key or key
      set = res.set or set
    end
  end
  local txt = raw_desc(set, key or blind_def.key, vars)
  if not txt then txt = M.boss_debuff_text(blind_def, vars) end
  if txt and txt ~= "" and (key == "bl_wheel" or blind_is(blind_def, "bl_wheel")) and not txt:find("^%s*%d") then
    local p = tonumber(G and G.GAME and G.GAME.probabilities and G.GAME.probabilities.normal) or 1
    txt = tostring(p) .. txt
  end
  return txt or ""
end

local function tag_vars(def, tag)
  local name = (tag and tag.name) or (def and def.name) or ""
  local key = (tag and tag.key) or (def and def.key)
  local cfg = (tag and tag.config) or (def and def.config) or {}
  local function is(k, nm) return key == k or name == nm end
  if is("tag_investment", "Investment Tag") then return { cfg.dollars }
  elseif is("tag_handy", "Handy Tag") then
    local d = cfg.dollars_per_hand
    return { d, d and d * ((G and G.GAME and G.GAME.hands_played) or 0) }
  elseif is("tag_garbage", "Garbage Tag") then
    local d = cfg.dollars_per_discard
    return { d, d and d * ((G and G.GAME and G.GAME.unused_discards) or 0) }
  elseif is("tag_juggle", "Juggle Tag") then return { cfg.h_size }
  elseif is("tag_top_up", "Top-up Tag") then return { cfg.spawn_jokers }
  elseif is("tag_skip", "Skip Tag") then
    local d = cfg.skip_bonus
    return { d, d and d * (((G and G.GAME and G.GAME.skips) or 0) + 1) }
  elseif is("tag_orbital", "Orbital Tag") then
    local oh = tag and tag.ability and tag.ability.orbital_hand
    return { oh and loc_hand(oh) or "[Poker Hand]", cfg.levels }
  elseif is("tag_economy", "Economy Tag") then return { cfg.max }
  end
  return {}
end

function M.tag_effect_text(key, tag)
  local def = G and G.P_TAGS and key and G.P_TAGS[key]
  local vars = tag_vars(def, tag)
  local set = "Tag"
  if def and type(def.loc_vars) == "function" then
    local ok, res = pcall(def.loc_vars, def, {}, tag)
    if ok and type(res) == "table" then
      vars = res.vars or vars
      key = res.key or key
      set = res.set or set
    end
  end
  local txt = raw_desc(set, key, vars)
  if txt then return txt end
  if def then
    local function fallback_text(loc_txt)
      if type(loc_txt) ~= "table" then return nil end
      local raw = loc_txt.description or loc_txt.text or loc_txt.name
      if type(raw) == "table" then raw = table.concat(raw, " ") end
      if type(raw) ~= "string" or raw == "" then return nil end
      return subst_vars(raw, vars)
    end
    local d = fallback_text(def.loc_txt)
    if not d and def.config and type(def.config.ref_table) == "table" then
      d = fallback_text(def.config.ref_table.loc_txt)
    end
    if d then
      local ok_u, Utils = pcall(require, "util.utils")
      if ok_u and Utils and Utils.safe_description then
        d = Utils.safe_description(d)
      end
      if d and d ~= "" then return d end
    end
  end
  return ""
end

local VOUCHER_DISP_VARS = {
  v_tarot_merchant = true, v_tarot_tycoon = true,
  v_planet_merchant = true, v_planet_tycoon = true,
}
local VOUCHER_FIFTH = { v_seed_money = true, v_money_tree = true }
function M.voucher_effect_text(key)
  local center = G and G.P_CENTERS and key and G.P_CENTERS[key]
  if type(center) ~= "table" then return "" end
  local cfg = center.config or {}
  local vars
  local ckey = center.key or key
  local set = "Voucher"
  if type(center.loc_vars) == "function" then
    local ok, res = pcall(center.loc_vars, center, {})
    if ok and type(res) == "table" then
      vars = res.vars
      ckey = res.key or ckey
      set = res.set or set
    end
  end
  if not vars then
    if VOUCHER_DISP_VARS[ckey] then vars = { cfg.extra_disp }
    elseif VOUCHER_FIFTH[ckey] then
      vars = { tonumber(cfg.extra) and cfg.extra / 5 or cfg.extra }
    else vars = { cfg.extra } end
  end
  local txt = raw_desc(set, ckey, vars)
  if txt then return txt end
  return ""
end

local function visit_leaf(c, fn)
  if type(c) ~= "table" then return end
  if type(c[1]) == "table" then
    for _, inner in ipairs(c) do visit_leaf(inner, fn) end
  else
    fn(c)
  end
end

function M.for_each_leaf_card(set, fn)
  if type(set) ~= "table" then return end
  for _, c in ipairs(set) do visit_leaf(c, fn) end
end

function M.all_debuffed(set)
  if type(set) ~= "table" then return false end
  local total, deb = 0, 0
  M.for_each_leaf_card(set, function(c)
    total = total + 1
    if c.debuff then deb = deb + 1 end
  end)
  return total > 0 and deb == total
end

function M.has_hand_restriction()
  local b = G and G.GAME and G.GAME.blind
  if not (type(b) == "table" and not b.disabled) then return false end
  if blind_is(b, "bl_eye") or blind_is(b, "bl_mouth") then return true end
  local d = b.debuff
  if type(d) == "table" and (tonumber(d.h_size_ge) or tonumber(d.h_size_le) or d.hand) then return true end
  local obj = b.config and b.config.blind
  if type(obj) == "table" and type(obj.debuff_hand) == "function" then return true end
  return false
end

function M.boss_would_debuff(played_cards, handname)
  local b = G and G.GAME and G.GAME.blind
  if not (type(b) == "table" and not b.disabled) then return false, true end
  if type(played_cards) ~= "table" or #played_cards == 0 then return false, true end
  local ph
  local ok_info = pcall(function()
    if G.FUNCS and type(G.FUNCS.get_poker_hand_info) == "function" then
      local text, _, p = G.FUNCS.get_poker_hand_info(played_cards)
      ph = p
      if not handname or handname == "" then handname = text end
    end
  end)
  if not ok_info then require("util.metrics").incr("boss_debuff_probe_failed") end
  if type(handname) ~= "string" or handname == "" then return false, ok_info end
  -- The engine's own static branches (dump blind.lua:571-590: debuff.hand, The Eye's hands[],
  -- The Mouth's only_hand) decide this without running debuff_hand. Demanding a live method here
  -- left the Ready list silent on a hand that scores 0 while the Close list warned about it.
  if M.boss_blocks_handname(handname) then return true, true end
  if type(b.debuff_hand) ~= "function" or type(ph) ~= "table" then return false, ok_info end
  local blocked = false
  local had_triggered = rawget(b, "triggered")
  local ok = pcall(function() blocked = b:debuff_hand(played_cards, ph, handname, true) and true or false end)
  b.triggered = had_triggered
  if not ok then
    require("util.metrics").incr("boss_debuff_probe_failed")
    return false, false
  end
  return blocked, ok_info
end

function M.boss_blocks_handname(handname)
  local b = G and G.GAME and G.GAME.blind
  if not (type(b) == "table" and not b.disabled) or type(handname) ~= "string" then return false end
  local d = b.debuff
  if type(d) == "table" and d.hand and d.hand == handname then return true end
  if blind_is(b, "bl_eye") and type(b.hands) == "table" and b.hands[handname] then return true end
  if blind_is(b, "bl_mouth") and b.only_hand and b.only_hand ~= handname then return true end
  return false
end

function M.forced_selection_index()
  if not (G and G.hand and type(G.hand.cards) == "table") then return nil end
  for i, c in ipairs(G.hand.cards) do
    if type(c) == "table" and type(c.ability) == "table" and c.ability.forced_selection then return i end
  end
  return nil
end

function M.boss_draws_facedown()
  local b = G and G.GAME and G.GAME.blind
  if not (type(b) == "table" and not b.disabled) then return false end
  local obj = b.config and b.config.blind
  if type(obj) == "table" and type(obj.stay_flipped) == "function" then return true end
  if blind_is(b, "bl_wheel") or blind_is(b, "bl_mark") then return true end
  if blind_is(b, "bl_fish") then
    local round = G and G.GAME and G.GAME.current_round
    return (tonumber(round and round.hands_left) or 0) > 0
  end
  if blind_is(b, "bl_house") then return false end
  return false
end

function M.fish_discards_faceup()
  local b = G and G.GAME and G.GAME.blind
  return not not (type(b) == "table" and not b.disabled and blind_is(b, "bl_fish"))
end

function M.owns_joker(name)
  local fj = rawget(_G, "find_joker")
  if type(fj) ~= "function" then return false end
  local ok, res = pcall(fj, name)
  return ok and type(res) == "table" and next(res) ~= nil
end

local function active_boss_is(key)
  local b = G and G.GAME and G.GAME.blind
  return not not (b and not b.disabled and b.in_blind and blind_is(b, key))
end

function M.flint_active() return active_boss_is("bl_flint") end
function M.tooth_active() return active_boss_is("bl_tooth") end
function M.ox_active() return active_boss_is("bl_ox") end

function M.flint_halve(chips, mult)
  return math.max(math.floor((chips or 0) * 0.5 + 0.5), 0), math.max(math.floor((mult or 0) * 0.5 + 0.5), 1)
end

if rawget(_G, "NEURO_TEST") then M._test = { pillar_used_count = pillar_used_count } end

return M
