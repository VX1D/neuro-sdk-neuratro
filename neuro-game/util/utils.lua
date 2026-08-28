local Utils = {}
-- collect_placeholder_values has no signature guard, so this TTL is the only thing that refreshes
-- a joker counter surfacing solely through loc_vars. Keep it short.
Utils.UI_TEXT_TTL = 0.75

function Utils.safe_tostring(value)
  local ok, text = pcall(tostring, value)
  return ok and text or "<unprintable value>"
end

function Utils.now()
  if G and G.TIMERS and G.TIMERS.REAL then return G.TIMERS.REAL end
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end
local pause_carry = 0
local last_real, last_total = nil, nil
local clock_epoch = 0

local function observe(real, total)
  if last_real and (real < last_real or (last_total and total and total < last_total)) then
    pause_carry = 0
    clock_epoch = clock_epoch + 1
  elseif last_real and G.SETTINGS and G.SETTINGS.paused then
    pause_carry = pause_carry + (real - last_real)
  end
  last_real, last_total = real, total or last_total
end

function Utils.clock_epoch() return clock_epoch end

function Utils.observe_clock()
  local timers = G and G.TIMERS
  local real = timers and type(timers.REAL) == "number" and timers.REAL or nil
  if not real then return clock_epoch end
  observe(real, type(timers.TOTAL) == "number" and timers.TOTAL or nil)
  return clock_epoch
end

function Utils.game_now()
  local timers = G and G.TIMERS
  if not timers then return Utils.now() end
  local total = type(timers.TOTAL) == "number" and timers.TOTAL or nil
  local real = type(timers.REAL) == "number" and timers.REAL or nil
  if not total then return real or Utils.now() end
  return total + pause_carry
end

-- The one clock a run reset does not rewind: G.TIMERS.REAL is set back to 12 when a run ends
-- (game.lua:1556-1558), which would jump every wire-facing deadline that reset happens to cross.
function Utils.wall_now()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.time()
end

local GateClocks = require("core.gate_clocks")
local GATE_CLOCK_READERS = { REAL = Utils.now, TOTAL = Utils.game_now, WALL = Utils.wall_now }

function Utils.gate_now(gate_id)
  return GATE_CLOCK_READERS[GateClocks.clock_of(gate_id)]()
end

function Utils.gate_clock(gate_id)
  return GateClocks.clock_of(gate_id)
end

function Utils.gate_seconds(gate_id, key)
  local gate = GateClocks.by_id[gate_id]
  assert(gate, "unknown timing gate: " .. tostring(gate_id))
  key = key or (gate.knobs and gate.knobs[1])
  local Tuning = require("core.config")
  local def = key and Tuning.definition(key) or nil
  if not def then return nil end
  if gate.clock ~= GateClocks.TOTAL or not def.cd then return Tuning.get(key) end
  local scale = tonumber(Tuning.get("NEURO_COOLDOWN_SCALE"))
  if not (scale and scale > 0) then scale = 1 end
  return (tonumber(Tuning.get_raw(key)) or 0) * scale
end

Utils.ABILITY_NUMERIC_FIELDS = {
  "x_mult", "h_mult", "h_mod", "t_mult", "s_mult", "x_chips",
  "mult", "chips",
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

function Utils.normalize_ws(value)
  return (tostring(value or ""):gsub("%c", " "):gsub("%s+", " ")
    :gsub("^%s+", ""):gsub("%s+$", ""))
end

local function strip_loc_tags(s)
  s = tostring(s or "")
  local prev
  repeat prev = s; s = s:gsub("{[^{}]*}", "") until s == prev
  return s
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

local _reap_warned = false
local function object_remove(obj)
  return obj.remove
end
local _reap_regs, _reap_befores, _reap_added = {}, {}, {}
local _reap_busy = false

local function reap_ui_window(fn)
  local nested = _reap_busy
  local regs, befores, added
  if nested then
    regs, befores, added = {}, {}, {}
  else
    _reap_busy = true
    regs, befores, added = _reap_regs, _reap_befores, _reap_added
  end

  local n = 0
  if G and type(G.I) == "table" then
    for _, reg in pairs(G.I) do
      if type(reg) == "table" then
        n = n + 1
        regs[n] = reg
        local before = befores[n]
        if not before then before = {}; befores[n] = before end
        for _, obj in pairs(reg) do before[obj] = true end
      end
    end
  end

  local ok, result = pcall(fn)

  local unreapable = 0
  for i = 1, n do
    local reg, before = regs[i], befores[i]
    local m = 0
    for _, obj in pairs(reg) do
      if obj and not before[obj] then m = m + 1; added[m] = obj end
    end
    for j = 1, m do
      local obj = added[j]
      added[j] = nil
      local got_remove, remove = pcall(object_remove, obj)
      if got_remove and type(remove) == "function" then
        local removed = pcall(remove, obj)
        if not removed then unreapable = unreapable + 1 end
      else
        unreapable = unreapable + 1
      end
    end
    for obj in pairs(before) do before[obj] = nil end
    regs[i] = nil
  end
  if not nested then _reap_busy = false end
  if unreapable > 0 and not _reap_warned then
    _reap_warned = true
    print("[neuro-game] UI reaper: " .. unreapable
      .. " UI object(s) could not be removed -- possible DynaText/Moveable leak (modded card?)")
  end

  return ok, result
end
local function cache_is_fresh(entry, t)
  if not entry then return false end
  local dt = t - (entry.at or 0)
  return dt >= 0 and dt < Utils.UI_TEXT_TTL
end

local function cache_revision(cache, card)
  if not card then return 0 end
  local entry = cache[card]
  if not entry then return 0 end
  local revision = entry.revision or 0
  if cache_is_fresh(entry, Utils.gate_now("ui_text_cache_ttl")) then return revision end
  return -revision
end

local function loc_vars_values(card)
  local center = card and card.config and card.config.center
  if type(center) ~= "table" or type(center.loc_vars) ~= "function" then
    return nil
  end
  local ok, ret = reap_ui_window(function()
    return center.loc_vars(center, {}, card)
  end)
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

function Utils.refresh_dynamic_joker(card)
  local ability = card and card.ability
  if type(ability) ~= "table" then return end
  local ckey = card.config and card.config.center and card.config.center.key
  if ckey == "j_swashbuckler" or (ckey == nil and ability.name == "Swashbuckler") then
    if not (G and G.jokers and G.jokers.cards) then return end
    local sell = 0
    for i = 1, #G.jokers.cards do
      local j = G.jokers.cards[i]
      if j ~= card and j.area == G.jokers then
        sell = sell + (tonumber(j.sell_cost) or 0)
      end
    end
    ability.mult = sell
  end
end

local function build_placeholder_values(card)
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

  if #values > 1 then return {} end
  return values
end

local _placeholder_cache = setmetatable({}, { __mode = "k" })
local _placeholder_serial = 0

function Utils.placeholder_revision(card)
  return cache_revision(_placeholder_cache, card)
end

local function collect_placeholder_values(card)
  if not card then return {}, 0 end

  Utils.refresh_dynamic_joker(card)

  local t = Utils.gate_now("ui_text_cache_ttl")
  local cached = _placeholder_cache[card]
  if cache_is_fresh(cached, t) then
    return cached.values, cached.revision
  end

  local values = build_placeholder_values(card)
  _placeholder_serial = _placeholder_serial + 1
  local revision = _placeholder_serial
  _placeholder_cache[card] = { at = t, values = values, revision = revision }
  return values, revision
end

local function coerce_text(v)
  local t = type(v)
  if t == "string" then return v end
  if t == "number" or t == "boolean" then return tostring(v) end
  return ""
end

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
local _ui_text_serial = 0

function Utils.neuro_log(...)
  if require("core.config").bool("NEURO_DEBUG") then print("[neuro-game]", ...) end
end

local function push_line(lines, raw)
  if raw == nil then return end
  local text = clean_loc_text(raw)
  if not text or text == "" then return end
  if lines[#lines] ~= text then
    lines[#lines + 1] = text
  end
end

local function collect_ui_lines(node, lines, depth)
  depth = depth or 0
  if depth > 14 or node == nil then return end

  local t = type(node)
  if t == "string" then
    push_line(lines, node)
    return
  end
  if t ~= "table" then
    return
  end

  local cfg = node.config
  if type(cfg) == "table" and cfg.text ~= nil then
    if type(cfg.text) == "table" then
      for _, v in ipairs(cfg.text) do
        push_line(lines, v)
      end
    else
      push_line(lines, cfg.text)
    end
  end

  if type(cfg) == "table" and type(cfg.object) == "table"
     and type(cfg.object.config) == "table" and type(cfg.object.config.string) == "table" then
    local strs = cfg.object.config.string
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
      push_line(lines, lo .. " to " .. hi)
    else
      for _, e in ipairs(strs) do
        local s = dyna_str(e)
        if s and not (s:find("#@", 1, true) or s:find("()", 1, true)) then
          push_line(lines, s)
        end
      end
    end
  end

  if node.nodes then
    collect_ui_lines(node.nodes, lines, depth + 1)
  end

  for i = 1, #node do
    collect_ui_lines(node[i], lines, depth + 1)
  end
end

local function build_ui_text(card)
  if not (card and type(card.generate_UIBox_ability_table) == "function") then
    return nil, nil
  end

  local ok, ui = reap_ui_window(function()
    return card:generate_UIBox_ability_table()
  end)

  if not ok or type(ui) ~= "table" then
    return nil, nil
  end

  local name = nil
  if type(ui.name) == "string" then
    name = clean_loc_text(ui.name)
  elseif type(ui.name) == "table" then
    local name_lines = {}
    collect_ui_lines(ui.name, name_lines, 0)
    if #name_lines > 0 then
      name = table.concat(name_lines, " ")
    end
  end

  local desc_lines = {}
  collect_ui_lines(ui.main, desc_lines, 0)
  local desc = (#desc_lines > 0) and table.concat(desc_lines, " ") or nil

  local info_lines = {}
  collect_ui_lines(ui.info, info_lines, 0)
  local info = (#info_lines > 0) and table.concat(info_lines, " ") or nil

  return name, desc, info
end

local function ui_text_signature(card)
  local vars = loc_vars_values(card)
  if not (vars and #vars > 0) then
    local ability = card.ability
    if type(ability) ~= "table" then return "" end
    vars = {}
    for _, f in ipairs(Utils.ABILITY_NUMERIC_FIELDS) do vars[#vars + 1] = tostring(ability[f]) end
    vars[#vars + 1] = tostring(ability.extra_value)
    if type(ability.extra) ~= "table" then vars[#vars + 1] = tostring(ability.extra) end
  end
  return table.concat(vars, "\1")
end

local function get_cached_ui_text(card)
  if not card then return nil, nil, nil end

  Utils.refresh_dynamic_joker(card)

  local t = Utils.gate_now("ui_text_cache_ttl")
  local sig = ui_text_signature(card)
  local cache = _ui_text_cache[card]
  if cache and cache.sig == sig and cache_is_fresh(cache, t) then
    return cache.name, cache.desc, cache.info
  end

  local name, desc, info = build_ui_text(card)
  _ui_text_serial = _ui_text_serial + 1
  _ui_text_cache[card] = {
    at = t, sig = sig, name = name, desc = desc, info = info, revision = _ui_text_serial,
  }
  return name, desc, info
end

function Utils.ui_text_revision(card)
  return cache_revision(_ui_text_cache, card)
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

local _masked_names = { ["Not Discovered"] = true, ["Locked"] = true }
local _localized_masked_names = false
local function masked_names()
  if not _localized_masked_names and G then
    local ok_nd, nd = pcall(function() return localize("k_not_discovered") end)
    if ok_nd and type(nd) == "string" and nd ~= "" then _masked_names[nd] = true end
    local ok_lk, lk = pcall(function() return localize("k_locked") end)
    if ok_lk and type(lk) == "string" and lk ~= "" then _masked_names[lk] = true end
    _localized_masked_names = ok_nd and ok_lk
  end
  return _masked_names
end
function Utils.is_masked_name(ui_name)
  return masked_names()[ui_name] == true
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
  if type(ui_name) == "string" and ui_name ~= "" then
    if not Utils.is_masked_name(ui_name) then
      return ui_name
    end
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

function Utils.safe_description(loc_txt, card)
  local placeholders = collect_placeholder_values(card)
  local raw
  if type(loc_txt) == "table" then
    raw = loc_txt.description or loc_txt.text or loc_txt.name
  else
    raw = loc_txt
  end
  return clean_loc_text(raw, placeholders) or ""
end

local function runtime_description(card)
  local ok_ui, _, ui_desc = pcall(function()
    local name, desc = get_cached_ui_text(card)
    return name, desc
  end)
  if ok_ui and ui_desc and ui_desc ~= "" then
    return ui_desc
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
      return out
    end
  end

  return nil
end

function Utils.card_description(card)
  if not card then return nil end

  local center = card.config and card.config.center or {}
  local ability = card.ability or {}
  local runtime = runtime_description(card)

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
    return string.format("Booster: pick %d of %d %s cards", choose, extra, label)
  end

  local is_playing_card = Utils.is_playing_card(card)
  if not is_playing_card and (set == "Joker" or set == "Tarot" or set == "Planet" or set == "Spectral" or set == "Voucher") then
    local name = Utils.safe_name(card) or "Unknown"
    return "No detailed description available for " .. name .. "."
  end
  return nil
end

function Utils.card_description_with_fallback(card)
  local desc = Utils.card_description(card)
  if desc and desc ~= "" then return desc end
  local center = card and card.config and card.config.center
  local ability = card and card.ability
  local loc = (center and center.loc_txt) or (ability and ability.loc_txt)
  return Utils.safe_description(loc, card)
end

function Utils.card_info_text(card)
  if not card then return nil end
  local ok, _name, _desc, info = pcall(get_cached_ui_text, card)
  if ok and type(info) == "string" and info ~= "" then return info end
  return nil
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

local _font_cache = {}

function Utils.font_at(path, base_px, scale)
  local px = math.floor(base_px * (scale or 1) + 0.5)
  if px < 1 then px = 1 end
  local by_px = _font_cache[path or false]
  if not by_px then by_px = {}; _font_cache[path or false] = by_px end
  local f = by_px[px]
  if not f then
    f = Utils.try(love.graphics.newFont, path, px) or love.graphics.newFont(px)
    by_px[px] = f
  end
  return f
end

function Utils.load_font_pair(path, sz_small, sz_big, scale)
  return Utils.font_at(path, sz_small, scale), Utils.font_at(path, sz_big, scale)
end

function Utils.list_to_set(list)
  local set = {}
  for i = 1, #(list or {}) do set[list[i]] = true end
  return set
end

function Utils.clean_plain(s) return normalize_spaces(strip_loc_tags(s)) end

function Utils.drop_last_codepoint(s)
  local i = #s
  while i > 1 do
    local b = s:byte(i)
    if b < 0x80 or b >= 0xC0 then break end
    i = i - 1
  end
  return s:sub(1, i - 1)
end

function Utils.money(n)
  return "$" .. tostring(n or 0)
end

function Utils.money_signed(n)
  n = tonumber(n) or 0
  return n < 0 and ("-$" .. tostring(-n)) or ("$" .. tostring(n))
end

function Utils.lazy_require(name)
  local ok, mod = pcall(require, name)
  return ok and mod or nil
end

local _diag_once_logged = {}
function Utils.diag_once(key, message)
  if _diag_once_logged[key] then return false end
  _diag_once_logged[key] = true
  print("[neuro-game] " .. tostring(message))
  return true
end

function Utils.game_ready() return G and G.GAME end
function Utils.neuro_ready() return G and G.NEURO end
function Utils.can_send()
  if not (G and G.NEURO and G.NEURO.send_context) then return false end
  return not (G.NEURO.is_transport_saturated and G.NEURO:is_transport_saturated())
end
function Utils.engine_settled()
  local em = G and G.E_MANAGER
  if not (em and em.queues) then return true end
  for key, queue in pairs(em.queues) do
    if key ~= "unlock" and type(queue) == "table" then
      for i = 1, #queue do
        local event = queue[i]
        if not (type(event) == "table" and event.blocking == false and event.blockable == false) then
          return false
        end
      end
    end
  end
  return true
end
function Utils.fmt_num(n)
  n = tonumber(n) or 0
  if n ~= n then return "0" end
  if n == 0 then return "0" end   -- avoid "-0" from a negative-zero delta
  local a = n < 0 and -n or n
  if a < 1e15 then
    if n % 1 ~= 0 then return (string.format("%.2f", n):gsub("%.?0+$", "")) end
    return string.format("%.0f", n)
  end
  return string.format("%.4g", n)
end

function Utils.fmt_2dp(n)
  return tostring(tonumber(string.format("%.2f", n)))
end

function Utils.fmt_xmult(n)
  return "x" .. Utils.fmt_2dp(n)
end

function Utils.signed(n, suffix)
  return (n < 0 and "" or "+") .. Utils.fmt_num(n) .. (suffix or "")
end

return Utils
