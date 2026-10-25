local M = {}
local BossModel = require("facts.boss.model")
local count = require("facts.text").count

function M.count(cards)
  return count(cards, function(c) return type(c) == "table" and c.debuff end)
end

local function blind_is(b, key)
  return BossModel.resolve_key(b) == key
end
if _G.NEURO_TEST then
  M.blind_is = blind_is
end

function M.pillar_active()
  return BossModel.active_key() == "bl_pillar"
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

local function apply_loc_vars(def, vars, key, set, ...)
  if def and type(def.loc_vars) == "function" then
    local ok, res = pcall(def.loc_vars, def, {}, ...)
    if ok and type(res) == "table" then
      return res.vars or vars, res.key or key, res.set or set
    end
  end
  return vars, key, set
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

-- Live play counts are used because `most_played_poker_hand` updates only after a boss.
function M.most_played_by_count()
  local hands = G and G.GAME and G.GAME.hands
  if type(hands) ~= "table" then return nil end
  local best, best_n, best_order
  for name, h in pairs(hands) do
    local n = type(h) == "table" and tonumber(h.played) or 0
    local order = type(h) == "table" and tonumber(h.order) or math.huge
    if n > 0 and (not best or n > best_n or (n == best_n and (order < best_order
        or (order == best_order and tostring(name) < tostring(best))))) then
      best, best_n, best_order = name, n, order
    end
  end
  return best and tostring(best) or nil
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
  vars, key, set = apply_loc_vars(blind_def, vars, key, set)
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
  vars, key, set = apply_loc_vars(def, vars, key, set, tag)
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
      d = require("util.utils").safe_description(d)
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
  local vars, ckey, set = apply_loc_vars(center, nil, center.key or key, "Voucher")
  if not vars then
    if VOUCHER_DISP_VARS[ckey] then vars = { cfg.extra_disp }
    elseif VOUCHER_FIFTH[ckey] then
      vars = { tonumber(cfg.extra) and cfg.extra / 5 or cfg.extra }
    else vars = { cfg.extra } end
  end
  return raw_desc(set, ckey, vars) or ""
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

local function hand_type_rule_live(b)
  local d = b.debuff
  if type(d) == "table" and d.hand then return true end
  if blind_is(b, "bl_eye") and type(b.hands) == "table" then
    for _, used in pairs(b.hands) do if used then return true end end
  end
  if blind_is(b, "bl_mouth") and b.only_hand then return true end
  return false
end

function M.boss_would_debuff_concealed(played_cards)
  local b = G and G.GAME and G.GAME.blind
  if not (type(b) == "table" and not b.disabled) then return false, true end
  local obj = b.config and b.config.blind
  if type(obj) == "table" and type(obj.debuff_hand) == "function" then return false, false end
  local n = type(played_cards) == "table" and #played_cards or 0
  local d = type(b.debuff) == "table" and b.debuff or {}
  local ge, le = tonumber(d.h_size_ge), tonumber(d.h_size_le)
  if (ge and n < ge) or (le and n > le) then return true, true end
  return false, not hand_type_rule_live(b)
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

function M.owns_joker(name)
  local fj = rawget(_G, "find_joker")
  if type(fj) ~= "function" then return false end
  local ok, res = pcall(fj, name)
  return ok and type(res) == "table" and next(res) ~= nil
end

local function active_boss_is(key)
  return BossModel.active_key(true) == key
end

function M.flint_active() return active_boss_is("bl_flint") end
function M.tooth_active() return active_boss_is("bl_tooth") end
function M.ox_active() return active_boss_is("bl_ox") end

function M.flint_halve(chips, mult)
  return math.max(math.floor((chips or 0) * 0.5 + 0.5), 0), math.max(math.floor((mult or 0) * 0.5 + 0.5), 1)
end

return M
