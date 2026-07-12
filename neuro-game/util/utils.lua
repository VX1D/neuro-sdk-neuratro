local Utils = {}

Utils.ABILITY_NUMERIC_FIELDS = {
  "x_mult", "h_mult", "h_mod", "c_mult", "t_mult", "d_mult", "s_mult", "p_mult", "x_chips",
}

local function trim(s)
  if not s then return "" end
  return tostring(s):match("^%s*(.-)%s*$") or ""
end

local function normalize_spaces(s)
  s = tostring(s or "")
  s = s:gsub("[\r\n]+", " ")
  s = s:gsub("%s+", " ")
  return trim(s)
end

local function strip_loc_tags(s)
  s = tostring(s or "")
  local prev
  repeat prev = s; s = s:gsub("{[^{}]*}", "") until s == prev
  return s
end

local function truncate(s, max_len)
  if type(s) ~= "string" then return s end
  if type(max_len) ~= "number" then return s end
  if #s <= max_len then return s end
  local suffix = "..."
  local cut = max_len - 3
  if max_len < 3 then
    suffix = ""
    cut = max_len
  end
  if cut < 0 then cut = 0 end
  while cut > 0 do
    local b = s:byte(cut + 1)
    if b and b >= 0x80 and b < 0xC0 then
      cut = cut - 1
    else
      break
    end
  end
  return s:sub(1, cut) .. suffix
end

local function humanize_identifier(id)
  local s = tostring(id or "")
  if s == "" then return "Unknown" end
  s = s:gsub("^[jJ]_", "")
  s = s:gsub("^[lL]_", "")
  s = s:gsub("^[vV]_", "")
  s = s:gsub("^[bB]l_", "")
  s = s:gsub("^[bB]_", "")
  s = s:gsub("^[cC]_", "")
  s = s:gsub("^[pP]_", "")
  s = s:gsub("_", " ")
  s = normalize_spaces(s)
  s = s:gsub("(%a)([%w']*)", function(a, b)
    return string.upper(a) .. string.lower(b)
  end)
  if s == "" then return "Unknown" end
  return s
end

local function loc_vars_values(card)
  local center = card and card.config and card.config.center
  if type(center) ~= "table" or type(center.loc_vars) ~= "function" then
    return nil
  end
  local ok, ret = pcall(center.loc_vars, center, {}, card)
  if not ok or type(ret) ~= "table" or type(ret.vars) ~= "table" then
    return nil
  end
  local vars = ret.vars
  local out = {}
  for i = 1, #vars do
    local v = vars[i]
    local t = type(v)
    if t == "number" or t == "string" or t == "boolean" then
      out[i] = tostring(v)
    else
      out[i] = "?"
    end
  end
  return out
end

local function collect_placeholder_values(card)
  if not card then return {} end

  local from_loc_vars = loc_vars_values(card)
  if from_loc_vars and #from_loc_vars > 0 then
    return from_loc_vars
  end

  local values = {}
  local function push(v)
    if v == nil then return end
    local t = type(v)
    if t == "number" or t == "boolean" then
      values[#values + 1] = tostring(v)
    elseif t == "string" then
      values[#values + 1] = v
    end
  end

  local ability = card.ability or {}

  for _, f in ipairs(Utils.ABILITY_NUMERIC_FIELDS) do push(ability[f]) end
  push(ability.extra_value)

  if ability.extra ~= nil then
    if type(ability.extra) == "table" then
      local keys = {}
      for k, _ in pairs(ability.extra) do
        if type(k) == "string" then keys[#keys + 1] = k end
      end
      table.sort(keys)
      for _, k in ipairs(keys) do
        push(ability.extra[k])
      end
      for _, v in ipairs(ability.extra) do
        push(v)
      end
    else
      push(ability.extra)
    end
  end

  return values
end

-- never tostring a function/table/userdata: a modded name-generator would render as "function: 0x.." in the hud
local function coerce_text(v)
  local t = type(v)
  if t == "string" then return v end
  if t == "number" or t == "boolean" then return tostring(v) end
  return ""
end
Utils.coerce_text = coerce_text

local function clean_loc_text(raw, placeholder_values)
  if raw == nil then return nil end
  local text = raw
  if type(text) == "table" then
    text = Utils.flatten_description(text)
  else
    text = coerce_text(text)
  end

  text = strip_loc_tags(text)
  text = text:gsub("#(%d+)#", function(idx)
    local i = tonumber(idx)
    if i and placeholder_values and placeholder_values[i] ~= nil then
      return tostring(placeholder_values[i])
    end
    return "?"
  end)
  text = text:gsub("#[^#]+#", "?")
  text = text:gsub("#", "")
  text = normalize_spaces(text)
  if text == "" then return nil end
  return text
end

local _ui_text_cache = setmetatable({}, { __mode = "k" })

Utils.DEBUG = require("core.tuning").bool("NEURO_DEBUG")
function Utils.neuro_log(...)
  if Utils.DEBUG then print("[neuro-game]", ...) end
end

-- use G.TIMERS.REAL (unpaused clock): throttles/timeouts must keep ticking while paused
function Utils.now()
  if G and G.TIMERS and G.TIMERS.REAL then return G.TIMERS.REAL end
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end
local now_time = Utils.now

local function push_unique_line(lines, seen, raw)
  if raw == nil then return end
  local text = clean_loc_text(raw)
  if not text or text == "" then return end
  if not seen[text] then
    seen[text] = true
    lines[#lines + 1] = text
  end
end

local function collect_ui_lines(node, lines, seen, depth)
  depth = depth or 0
  if depth > 14 or node == nil then return end

  local t = type(node)
  if t == "string" then
    push_unique_line(lines, seen, node)
    return
  end
  if t ~= "table" then
    return
  end

  local cfg = node.config
  if type(cfg) == "table" and cfg.text ~= nil then
    if type(cfg.text) == "table" then
      for _, v in ipairs(cfg.text) do
        push_unique_line(lines, seen, v)
      end
    else
      push_unique_line(lines, seen, cfg.text)
    end
  end

  if type(cfg) == "table" and type(cfg.object) == "table"
     and type(cfg.object.config) == "table" and type(cfg.object.config.string) == "table" then
    local strs = cfg.object.config.string
    -- DynaText string elements can be a bare number (e.g. Green Joker's Mult counter, often 0); coerce to string, don't drop it.
    local function dyna_str(e)
      local s = (type(e) == "string" and e) or (type(e) == "table" and e.string) or nil
      if type(s) == "number" then s = tostring(s) end
      return (type(s) == "string") and s or nil
    end
    local nums, all_num = {}, true
    for _, e in ipairs(strs) do
      local s = dyna_str(e)
      if s and tonumber(s) then
        nums[#nums + 1] = s
      else
        all_num = false
      end
    end
    if all_num and #nums >= 2 then
      local lo, hi = tonumber(nums[1]), tonumber(nums[1])
      for _, n in ipairs(nums) do local x = tonumber(n); if x < lo then lo = x end; if x > hi then hi = x end end
      push_unique_line(lines, seen, lo .. " to " .. hi)
    else
      for _, e in ipairs(strs) do
        local s = dyna_str(e)
        if s and not (s:find("#@", 1, true) or s:find("()", 1, true)) then
          push_unique_line(lines, seen, s)
        end
      end
    end
  end

  if node.nodes then
    collect_ui_lines(node.nodes, lines, seen, depth + 1)
  end

  for i = 1, #node do
    collect_ui_lines(node[i], lines, seen, depth + 1)
  end
end

local _reap_warned = false
local function build_ui_text(card)
  if not (card and type(card.generate_UIBox_ability_table) == "function") then
    return nil, nil
  end

  local before_sets = {}
  if G and type(G.I) == "table" then
    for _, reg in pairs(G.I) do
      if type(reg) == "table" then
        local before = {}
        for _, obj in pairs(reg) do before[obj] = true end
        before_sets[reg] = before
      end
    end
  end

  local ok, ui = pcall(function()
    return card:generate_UIBox_ability_table()
  end)

  local unreapable = 0
  for reg, before in pairs(before_sets) do
    local kill = {}
    for _, obj in pairs(reg) do
      if obj and not before[obj] then kill[#kill + 1] = obj end
    end
    for i = 1, #kill do
      local obj = kill[i]
      if type(obj.remove) == "function" then
        pcall(obj.remove, obj)
      else
        unreapable = unreapable + 1
      end
    end
  end
  if unreapable > 0 and not _reap_warned then
    _reap_warned = true
    print("[neuro-game] build_ui_text: " .. unreapable
      .. " UI object(s) with no :remove() -- possible DynaText/Moveable leak (modded card?)")
  end

  if not ok or type(ui) ~= "table" then
    return nil, nil
  end

  local name = nil
  if type(ui.name) == "string" then
    name = clean_loc_text(ui.name)
  elseif type(ui.name) == "table" then
    local name_lines, seen = {}, {}
    collect_ui_lines(ui.name, name_lines, seen, 0)
    if #name_lines > 0 then
      name = table.concat(name_lines, " ")
    end
  end

  local desc_lines, seen_desc = {}, {}
  collect_ui_lines(ui.main, desc_lines, seen_desc, 0)
  collect_ui_lines(ui.info, desc_lines, seen_desc, 0)

  local desc = nil
  if #desc_lines > 0 then
    desc = table.concat(desc_lines, " ")
  end

  return name, desc
end

local function get_cached_ui_text(card)
  if not card then return nil, nil end

  local t = now_time()
  local cache = _ui_text_cache[card]
  if cache then
    local dt = t - (cache.at or 0)
    if dt >= 0 and dt < 0.75 then
      return cache.name, cache.desc
    end
  end

  local name, desc = build_ui_text(card)
  _ui_text_cache[card] = { at = t, name = name, desc = desc }
  return name, desc
end

local function get_localization_entry(card)
  if not (G and G.localization and G.localization.descriptions and card) then
    return nil
  end
  local center = card.config and card.config.center or {}
  local ability = card.ability or {}
  local set = center.set or ability.set
  local key = center.key or ability.key
  if not set or not key then return nil end
  local set_table = G.localization.descriptions[set]
  if not set_table then return nil end
  return set_table[key]
end

function Utils.is_playing_card(card)
  return card ~= nil and card.base ~= nil and card.base.value ~= nil and card.base.suit ~= nil
end

function Utils.playing_card_label(card)
  local b = card and card.base
  return tostring((b and b.value) or "?") .. " of " .. tostring((b and b.suit) or "?")
end

function Utils.safe_name(card)
  if not card then return nil end

  if Utils.is_playing_card(card) then
    return Utils.playing_card_label(card)
  end

  local placeholders = collect_placeholder_values(card)
  local center = card.config and card.config.center or {}

  local ui_name = nil
  local ok_ui, n = pcall(function()
    local name = get_cached_ui_text(card)
    return name
  end)
  if ok_ui then ui_name = n end
  -- get_cached_ui_text may return a non-string (modded name-generator); guard or it renders as "function: 0x.."
  if type(ui_name) == "string" and ui_name ~= "" then
    return ui_name
  end

  local entry = get_localization_entry(card)
  if entry and entry.name then
    local nm = clean_loc_text(entry.name, placeholders)
    if nm and nm ~= "" then return nm end
  end

  if center.loc_txt and center.loc_txt.name then
    local nm = clean_loc_text(center.loc_txt.name, placeholders)
    if nm and nm ~= "" then return nm end
  end

  if center.key and G and G.P_CENTERS then
    local pc = G.P_CENTERS[center.key]
    if pc and pc.loc_txt and pc.loc_txt.name then
      local nm = clean_loc_text(pc.loc_txt.name, placeholders)
      if nm and nm ~= "" then return nm end
    end
  end

  if card.label and card.label ~= "" then
    local lbl = clean_loc_text(card.label, placeholders)
    if lbl and lbl ~= "" then
      if lbl:find("_") and not lbl:find(" ") then
        lbl = humanize_identifier(lbl)
      end
      local first_char = lbl:sub(1, 1)
      if lbl:find(" ") or (first_char == first_char:upper() and first_char ~= first_char:lower()) then
        return lbl
      end
    end
  end

  if center.name then
    local nm = clean_loc_text(center.name, placeholders)
    if nm and nm ~= "" then
      if nm:find("_") and not nm:find(" ") then
        return humanize_identifier(nm)
      end
      return nm
    end
  end
  if card.ability and card.ability.name then
    local nm = clean_loc_text(card.ability.name, placeholders)
    if nm and nm ~= "" then
      if nm:find("_") and not nm:find(" ") then
        return humanize_identifier(nm)
      end
      return nm
    end
  end

  if center.key then
    return humanize_identifier(center.key)
  end

  return "Unknown"
end

function Utils.real_name(card)
  if not card then return nil end
  if card.base and card.base.value and card.base.suit then
    return Utils.safe_name(card)
  end
  local placeholders = collect_placeholder_values(card)
  local center = card.config and card.config.center or {}
  local entry = get_localization_entry(card)
  if entry and entry.name then
    local nm = clean_loc_text(entry.name, placeholders)
    if nm and nm ~= "" then return nm end
  end
  if center.loc_txt and center.loc_txt.name then
    local nm = clean_loc_text(center.loc_txt.name, placeholders)
    if nm and nm ~= "" then return nm end
  end
  if center.key and G and G.P_CENTERS then
    local pc = G.P_CENTERS[center.key]
    if pc and pc.loc_txt and pc.loc_txt.name then
      local nm = clean_loc_text(pc.loc_txt.name, placeholders)
      if nm and nm ~= "" then return nm end
    end
  end
  if type(center.name) == "string" and center.name ~= "" then
    local nm = clean_loc_text(center.name, placeholders)
    if nm and nm ~= "" then
      if nm:find("_") and not nm:find(" ") then return humanize_identifier(nm) end
      return nm
    end
  end
  return Utils.safe_name(card)
end

function Utils.real_name_or(card)
  return Utils.real_name(card) or "Unknown"
end

function Utils.flatten_description(desc)
  if desc == nil then return nil end
  if type(desc) == "string" then return desc end
  if type(desc) ~= "table" then return tostring(desc) end
  local parts = {}
  for _, v in ipairs(desc) do
    if type(v) == "table" then
      for _, line in ipairs(v) do
        parts[#parts + 1] = coerce_text(line)
      end
    else
      parts[#parts + 1] = coerce_text(v)
    end
  end
  if #parts > 0 then return table.concat(parts, " ") end
  for k, v in pairs(desc) do
    if type(k) == "string" then
      if type(v) == "table" then
        for _, line in ipairs(v) do
          parts[#parts + 1] = coerce_text(line)
        end
      else
        parts[#parts + 1] = coerce_text(v)
      end
    end
  end
  return #parts > 0 and table.concat(parts, " ") or nil
end

function Utils.safe_description(loc_txt, card, max_len)
  local placeholders = collect_placeholder_values(card)
  local raw = nil
  if type(loc_txt) == "table" then
    raw = loc_txt.description or loc_txt.text or loc_txt.name
  else
    raw = loc_txt
  end
  local out = clean_loc_text(raw, placeholders)
  out = truncate(out, max_len)
  return out or ""
end

local function runtime_description(card, max_len)
  local ok_ui, _, ui_desc = pcall(function()
    local name, desc = get_cached_ui_text(card)
    return name, desc
  end)
  if ok_ui and ui_desc and ui_desc ~= "" then
    return truncate(ui_desc, max_len)
  end

  local placeholders = collect_placeholder_values(card)
  local center = card.config and card.config.center or {}
  local ability = card.ability or {}
  local entry = get_localization_entry(card)

  local pc_loc = nil
  if center.key and G and G.P_CENTERS then
    local pc = G.P_CENTERS[center.key]
    if pc and pc.loc_txt then
      pc_loc = pc.loc_txt.description or pc.loc_txt.text
    end
  end

  local candidates = {}
  local function add_candidate(v)
    if v ~= nil then candidates[#candidates + 1] = v end
  end
  add_candidate(center.loc_txt and (center.loc_txt.description or center.loc_txt.text))
  add_candidate(ability.loc_txt and (ability.loc_txt.description or ability.loc_txt.text))
  add_candidate(card.loc_txt and (card.loc_txt.description or card.loc_txt.text))
  add_candidate(entry and (entry.text or entry.description))
  add_candidate(pc_loc)

  for _, candidate in ipairs(candidates) do
    local out = clean_loc_text(candidate, placeholders)
    if out and out ~= "" then
      return truncate(out, max_len)
    end
  end

  return nil
end

function Utils.card_description(card, max_len)
  if not card then return nil end

  local center = card.config and card.config.center or {}
  local ability = card.ability or {}
  local runtime = runtime_description(card, max_len)

  if runtime then return runtime end

  local set = ability.set
  if set == "Booster" or (type(center.key) == "string" and center.key:sub(1, 2) == "p_") then
    local cfg = center.config or {}
    local choose = tonumber(cfg.choose) or 1
    local extra = tonumber(cfg.extra) or tonumber(cfg.cards) or choose
    local KIND = { arcana = "Tarot", celestial = "Planet", standard = "playing", buffoon = "Joker",
                   spectral = "Spectral", neurpack = "Neuratro joker", devpack = "dev", dev = "dev" }
    local kind = type(center.key) == "string" and center.key:match("p_(%a+)") or nil
    local label = (kind and KIND[kind]) or "pack"
    return truncate(string.format("Booster: pick %d of %d %s cards", choose, extra, label), max_len)
  end

  local is_playing_card = Utils.is_playing_card(card)
  if not is_playing_card and (set == "Joker" or set == "Tarot" or set == "Planet" or set == "Spectral" or set == "Voucher") then
    local name = Utils.safe_name(card) or "Unknown"
    return truncate("No detailed description available for " .. name .. ".", max_len)
  end
  return nil
end

function Utils.card_description_with_fallback(card, max_len)
  local desc = Utils.card_description(card, max_len)
  if desc and desc ~= "" then return desc end
  local center = card and card.config and card.config.center
  local ability = card and card.ability
  local loc = (center and center.loc_txt) or (ability and ability.loc_txt)
  return Utils.safe_description(loc, card, max_len)
end

function Utils.humanize_identifier(id)
  return humanize_identifier(id)
end

function Utils.safe_name_or(card)
  return Utils.safe_name(card) or "Unknown"
end

function Utils.try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if ok then return v end
  return nil
end

-- no eviction: fonts in use must never be collected out from under a draw
local _font_cache = {}

function Utils.font_at(path, base_px, scale)
  local px = math.floor(base_px * (scale or 1) + 0.5)
  if px < 1 then px = 1 end
  local key = tostring(path) .. "@" .. px
  local f = _font_cache[key]
  if not f then
    f = Utils.try(love.graphics.newFont, path, px) or love.graphics.newFont(px)
    _font_cache[key] = f
  end
  return f
end

function Utils.load_font_pair(path, sz_small, sz_big, scale)
  return Utils.font_at(path, sz_small, scale), Utils.font_at(path, sz_big, scale)
end

function Utils.has_playbook_extra()
  if G and G.playbook_extra then
    return true
  end
  if SMODS then
    if SMODS.findModByID then
      return SMODS.findModByID("Neurocards") ~= nil
    end
    if SMODS.Mods then
      for _, mod in pairs(SMODS.Mods) do
        if mod and (mod.id == "Neurocards" or mod.mod_id == "Neurocards") then
          return true
        end
      end
    end
  end
  return false
end

function Utils.list_to_set(list)
  local set = {}
  for i = 1, #(list or {}) do set[list[i]] = true end
  return set
end

Utils.strip_loc_tags = strip_loc_tags
Utils.normalize_spaces = normalize_spaces
function Utils.clean_plain(s) return normalize_spaces(strip_loc_tags(s)) end

function Utils.money(n)
  return "$" .. tostring(n or 0)
end

function Utils.lazy_require(name)
  local ok, mod = pcall(require, name)
  return ok and mod or nil
end

function Utils.game_ready() return G and G.GAME end
function Utils.neuro_ready() return G and G.NEURO end
function Utils.can_send() return G and G.NEURO and G.NEURO.send_context end
function Utils.send_context(msg, silent)
  if not (G and G.NEURO and G.NEURO.send_context) then return end
  pcall(function() G.NEURO:send_context(msg, silent) end)
end

-- %d wraps chips/scores >2^63 to INT64_MIN; exact int below 1e15 (double-precise), scientific above
function Utils.fmt_num(n)
  n = tonumber(n) or 0
  if n ~= n then return "0" end
  if n == 0 then return "0" end   -- avoid "-0" from a negative-zero delta
  local a = n < 0 and -n or n
  if a < 1e15 then return string.format("%.0f", n) end
  return string.format("%.4g", n)
end

return Utils
