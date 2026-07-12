local M = {}

function M.debuffed_indices(cards)
  local out, n = {}, 0
  if type(cards) == "table" then
    for i, c in ipairs(cards) do
      if type(c) == "table" and c.debuff then out[i] = true; n = n + 1 end
    end
  end
  return out, n
end

function M.count(cards)
  local _, n = M.debuffed_indices(cards)
  return n
end

function M.blind_debuff(blind)
  return (type(blind) == "table" and type(blind.debuff) == "table") and blind.debuff or {}
end

local BOSS_NAMES = {
  bl_ox = "The Ox", bl_eye = "The Eye", bl_mouth = "The Mouth",
  bl_pillar = "The Pillar", bl_flint = "The Flint",
  bl_serpent = "The Serpent", bl_arm = "The Arm",
  bl_final_leaf = "Verdant Leaf", bl_final_bell = "Cerulean Bell",
}
local function blind_is(b, key)
  if type(b) ~= "table" then return false end
  if b.key == key then return true end
  return b.name == BOSS_NAMES[key]
end
M.blind_is = blind_is

local function loc_hand(name)
  if not name then return name end
  local loc = rawget(_G, "localize")
  if type(loc) == "function" then
    local ok, res = pcall(loc, name, "poker_hands")
    if ok and type(res) == "string" and res ~= "" and res ~= "ERROR" then return res end
  end
  return name
end

-- substitute #n# on fallback paths that bypass localize; a raw #1# must never ship
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
  if type(blind) ~= "table" then return "" end
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
  local best, best_n
  if G and G.GAME and type(G.GAME.hands) == "table" then
    for name, hd in pairs(G.GAME.hands) do
      local n = type(hd) == "table" and tonumber(hd.played) or nil
      if n and n > 0 and (not best_n or n > best_n) then best, best_n = name, n end
    end
  end
  return best
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
    local ok, res = pcall(blind_def.loc_vars, blind_def)
    if ok and type(res) == "table" then
      vars = res.vars or vars
      key = res.key or key
      set = res.set or set
    end
  end
  local txt = raw_desc(set, key or blind_def.key, vars)
  if txt then return txt end
  return M.boss_debuff_text(blind_def, vars)
end

-- var order from Tag:get_uibox_table (tag.lua:570-585); also handles not-yet-created tags
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
  local txt = raw_desc("Tag", key, vars)
  if txt then return txt end
  if def then
    -- substitute #n# BEFORE safe_description, else its placeholder pass blanks every var to ?
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
        d = Utils.safe_description(d, nil, 120)
      end
      if d and d ~= "" then return d end
    end
  end
  return ""
end

local VOUCHER_DISP_VARS = {
  ["Tarot Merchant"] = true, ["Tarot Tycoon"] = true,
  ["Planet Merchant"] = true, ["Planet Tycoon"] = true,
}
function M.voucher_effect_text(key)
  local center = G and G.P_CENTERS and key and G.P_CENTERS[key]
  if type(center) ~= "table" then return "" end
  local cfg = center.config or {}
  local vars
  local name = center.name or ""
  if VOUCHER_DISP_VARS[name] then vars = { cfg.extra_disp }
  elseif name == "Seed Money" or name == "Money Tree" then
    vars = { tonumber(cfg.extra) and cfg.extra / 5 or cfg.extra }
  else vars = { cfg.extra } end
  local txt = raw_desc("Voucher", center.key or key, vars)
  if txt then return txt end
  return ""
end

-- engine scoring set is a flat list OR a nested array-of-groups (misc_functions.lua:408)
function M.for_each_leaf_card(set, fn)
  if type(set) ~= "table" then return end
  local function visit(c)
    if type(c) ~= "table" then return end
    if type(c[1]) == "table" then
      for _, inner in ipairs(c) do visit(inner) end
    else
      fn(c)
    end
  end
  for _, c in ipairs(set) do visit(c) end
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

-- check=true (cardarea.lua:193) guards Eye/Mouth state writes so this has no side effects
function M.boss_would_debuff(played_cards, handname)
  local b = G and G.GAME and G.GAME.blind
  if not (type(b) == "table" and not b.disabled and type(b.debuff_hand) == "function") then return false end
  if type(played_cards) ~= "table" or #played_cards == 0 then return false end
  local ph
  pcall(function()
    if G.FUNCS and type(G.FUNCS.get_poker_hand_info) == "function" then
      local text, _, p = G.FUNCS.get_poker_hand_info(played_cards)
      ph = p
      if not handname or handname == "" then handname = text end
    end
  end)
  if type(ph) ~= "table" or type(handname) ~= "string" or handname == "" then return false end
  local blocked = false
  pcall(function() blocked = b:debuff_hand(played_cards, ph, handname, true) and true or false end)
  return blocked
end

-- size rules not checked here: they constrain card count, not hand type
function M.boss_blocks_handname(handname)
  local b = G and G.GAME and G.GAME.blind
  if not (type(b) == "table" and not b.disabled) or type(handname) ~= "string" then return false end
  local d = b.debuff
  if type(d) == "table" and d.hand and d.hand == handname then return true end
  if blind_is(b, "bl_eye") and type(b.hands) == "table" and b.hands[handname] then return true end
  if blind_is(b, "bl_mouth") and b.only_hand and b.only_hand ~= handname then return true end
  return false
end

function M.boss_hand_restriction_note()
  local b = G and G.GAME and G.GAME.blind
  if not (type(b) == "table" and not b.disabled) then return nil end
  if blind_is(b, "bl_mouth") then
    if b.only_hand then
      return "Boss (The Mouth): only " .. loc_hand(b.only_hand)
        .. " scores the rest of this round; every other hand type is debuffed to 0."
    end
    return "Boss (The Mouth): the first hand type you play locks every later hand this round to that same type (others score 0)."
  elseif blind_is(b, "bl_eye") then
    local used = {}
    if type(b.hands) == "table" then
      for hn, v in pairs(b.hands) do if v then used[#used + 1] = loc_hand(hn) end end
    end
    table.sort(used)
    local note = "Boss (The Eye): each hand type scores only once this round; a repeated type is debuffed to 0."
    if #used > 0 then note = note .. " Already used (now score 0): " .. table.concat(used, ", ") .. "." end
    return note
  end
  local d = b.debuff
  if type(d) == "table" then
    local ge = tonumber(d.h_size_ge)
    if ge and ge > 0 then return string.format("Boss: each hand must play at least %d cards or it is debuffed to 0.", ge) end
    local le = tonumber(d.h_size_le)
    if le and le > 0 then return string.format("Boss: each hand must play at most %d cards or it is debuffed to 0.", le) end
  end
  return nil
end

-- Cerulean Bell's forced highlight survives unhighlight_all (cardarea.lua:233), so it's always in the played/discarded hand
function M.forced_selection_index()
  if not (G and G.hand and type(G.hand.cards) == "table") then return nil end
  for i, c in ipairs(G.hand.cards) do
    if type(c) == "table" and type(c.ability) == "table" and c.ability.forced_selection then return i end
  end
  return nil
end

function M.boss_play_note()
  local b = G and G.GAME and G.GAME.blind
  if not (type(b) == "table" and not b.disabled) then return nil end
  if blind_is(b, "bl_serpent") then
    return "Boss (The Serpent): after each play or discard you draw at most 3 cards (capped by remaining deck; hand size is ignored)."
  elseif blind_is(b, "bl_arm") then
    return "Boss (The Arm): each hand you play permanently lowers that hand type's level by 1, but never below level 1 (the Ready levels shown drop as you replay a type)."
  elseif blind_is(b, "bl_final_leaf") then
    return "Boss (Verdant Leaf): every card is debuffed (scores 0) until you SELL a joker -- sell one to lift it."
  elseif blind_is(b, "bl_final_bell") then
    local i = M.forced_selection_index()
    if i then
      return string.format("Boss (Cerulean Bell): card %d is force-selected (LOCK) and will always be part of the hand you play or discard -- include index %d in your selection.", i, i)
    end
    return "Boss (Cerulean Bell): one card is force-selected each draw (LOCK) and must be part of every hand you play or discard."
  end
  return nil
end

function M.flint_active()
  local b = G and G.GAME and G.GAME.blind
  return not not (b and not b.disabled and b.in_blind and blind_is(b, "bl_flint"))
end

function M.flint_halve(chips, mult)
  return math.max(math.floor((chips or 0) * 0.5 + 0.5), 0), math.max(math.floor((mult or 0) * 0.5 + 0.5), 1)
end

return M
