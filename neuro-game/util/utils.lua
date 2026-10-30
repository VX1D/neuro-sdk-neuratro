local Utils = {}
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

-- Engine timers rewind between runs, so deadlines use a monotonic wall clock.
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

-- Unpunctuated clauses and small or greyed side notes need a separator; a bare space runs them together.
local CONTINUES = {}
for w in ("a an the and or to of for each every with by when if per give gives gain gains earn earns"
  .. " cost costs up at in on is are be from into than permanently"):gmatch("%S+") do CONTINUES[w] = true end

-- These capitalized game nouns may continue a clause rather than begin a new one.
local GAME_NOUNS = {}
for w in ("Joker Jokers Blind Blinds Boss Challenge Tarot Tarots Planet Planets Spectral Card Cards Tag Tags"
  .. " Booster Boosters Pack Packs Voucher Vouchers Seal Seals Ace Aces King Kings Queen Queens Jack Jacks"
  .. " Hearts Spades Clubs Diamonds Mult Chips Hand Hands Discard Discards Round Rounds Ante Antes Shop"
  .. " Stone Steel Glass Gold Lucky Wild Bonus Foil Holographic Polychrome Negative Straight Flush Pair"
  .. " Full High Two Three Four Five Small Big Common Uncommon Rare Legendary Mega Jumbo Arcana Celestial"
  .. " Standard Buffoon Club Heart Spade Diamond Stake Stakes Edition Editions Enhanced"):gmatch("%S+") do GAME_NOUNS[w] = true end

local function starts_clause(line)
  local s = trim(strip_loc_tags(line)):gsub("#%d+#", "1")
  local word = s:match("^(%u%l+)%f[%A]")
  return s:find("^[+%-]%$?%d") or s:find("^X%d") or s:find("^%$%d") or s:find("^%d+ in %d+ ")
    or (word and not GAME_NOUNS[word])
end

local function open_ended(line)
  local s = trim(strip_loc_tags(line))
  if s:find("[%.,;:!?%(]$") then return true end
  return CONTINUES[(s:match("(%a+)$") or ""):lower()] == true
end

local function join_desc_lines(lines, notes)
  local out, prev = {}, nil
  for i, line in ipairs(lines) do
    local text = trim(line)
    if trim(strip_loc_tags(text)) ~= "" then
      if prev and notes and notes[i] and not trim(strip_loc_tags(text)):find("^%(") then
        out[#out] = out[#out]:gsub(",%s*$", "")
        out[#out + 1] = " (" .. text .. ")"
      elseif prev and starts_clause(text) and not open_ended(prev) then
        out[#out + 1] = "; " .. text
      else
        out[#out + 1] = (prev and " " or "") .. text
      end
      prev = text
    end
  end
  return table.concat(out)
end

-- A line whose control codes all shrink or grey it is rendered as a note.
local function raw_note_line(line)
  if type(line) ~= "string" or not line:find("^%s*{") then return false end
  local any = false
  for code in line:gmatch("{([^{}]*)}") do
    if code ~= "" then
      local s = tonumber(code:match("s:([%d%.]+)"))
      if not ((s and s < 1) or code:find("C:inactive", 1, true)) then return false end
      any = true
    end
  end
  return any
end

local IDENTIFIER_PREFIXES = { "^[jJ]_", "^[lL]_", "^[vV]_", "^[bB]l_", "^[bB]_", "^[cC]_", "^[pP]_" }

local function humanize_identifier(id)
  local s = tostring(id or "")
  if s == "" then return "Unknown" end
  for _, prefix in ipairs(IDENTIFIER_PREFIXES) do s = s:gsub(prefix, "") end
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
  local reg_seen = {}
  local function snapshot(fresh)
    if not (G and type(G.I) == "table") then return end
    for _, reg in pairs(G.I) do
      if type(reg) == "table" and not reg_seen[reg] then
        n = n + 1
        regs[n] = reg
        reg_seen[reg] = true
        local before = not fresh and befores[n] or {}
        befores[n] = before
        if not fresh then for _, obj in pairs(reg) do before[obj] = true end end
      end
    end
  end
  snapshot(false)
  local ok, result = pcall(fn)
  snapshot(true)

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
local _text_epoch = 0
function Utils.begin_text_build()
  _text_epoch = _text_epoch + 1
end

local function cache_is_fresh(entry, t)
  if not entry or entry.epoch ~= _text_epoch then return false end
  local dt = t - (entry.at or 0)
  return dt >= 0 and dt < Utils.UI_TEXT_TTL
end

local function cache_revision(cache, card)
  if not card then return 0 end
  local entry = cache.entries[card]
  if not entry then return 0 end
  local revision = entry.revision or 0
  if cache_is_fresh(entry, Utils.gate_now("ui_text_cache_ttl")) then return revision end
  return -revision
end

local function text_cache()
  return { entries = setmetatable({}, { __mode = "k" }), serial = 0 }
end

local function memo(cache, card, signature, build)
  local t = Utils.gate_now("ui_text_cache_ttl")
  local sig = signature and signature(card)
  local entry = cache.entries[card]
  if entry and entry.sig == sig and cache_is_fresh(entry, t) then return entry end
  entry = build(card)
  cache.serial = cache.serial + 1
  entry.at, entry.epoch, entry.sig, entry.revision = t, _text_epoch, sig, cache.serial
  cache.entries[card] = entry
  return entry
end

local LOC_VARS_MAX_INDEX = 256
local LOC_VARS_SCAN_LIMIT = 512

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
  local max_index = 0
  local ambiguous = false
  local scanned = 0
  for k, _ in pairs(vars) do
    scanned = scanned + 1
    if scanned > LOC_VARS_SCAN_LIMIT then
      ambiguous = true
      break
    end
    if type(k) == "number" and k >= 1 and k % 1 == 0 and k > max_index then
      max_index = k
    end
  end
  if max_index == 0 then return {}, ambiguous end
  if max_index > LOC_VARS_MAX_INDEX then
    local out = {}
    for i = 1, LOC_VARS_MAX_INDEX do out[i] = "?" end
    return out, true
  end

  local out = {}
  for i = 1, max_index do
    local v = vars[i]
    local t = type(v)
    out[i] = not ambiguous and (t == "number" or t == "string" or t == "boolean") and tostring(v) or "?"
  end
  return out, ambiguous
end

function Utils.refresh_dynamic_joker(card)
  local ability = card and card.ability
  if type(ability) ~= "table" then return end
  local ckey = card.config and card.config.center and card.config.center.key
  if ckey == "j_swashbuckler" or (ckey == nil and ability.name == "Swashbuckler") then
    if not (G and G.jokers and G.jokers.cards) then return end
    -- Swashbuckler counts face-down jokers too; the engine scores every joker in the area.
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
  local from_loc_vars, loc_vars_ambiguous = loc_vars_values(card)
  if loc_vars_ambiguous then return from_loc_vars or {} end
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

  if #values > 1 then
    for i = 1, #values do values[i] = "?" end
  end
  return values
end

local _placeholder_cache = text_cache()

function Utils.placeholder_revision(card)
  return cache_revision(_placeholder_cache, card)
end

local function collect_placeholder_values(card)
  if not card then return {}, 0 end

  Utils.refresh_dynamic_joker(card)
  local entry = memo(_placeholder_cache, card, nil, function(c) return { values = build_placeholder_values(c) } end)
  return entry.values, entry.revision
end

local function coerce_text(v)
  local t = type(v)
  if t == "string" then return v end
  if t == "number" or t == "boolean" then return tostring(v) end
  return ""
end

local function append_text(parts, v)
  if type(v) == "table" then
    for _, line in ipairs(v) do parts[#parts + 1] = coerce_text(line) end
  else
    parts[#parts + 1] = coerce_text(v)
  end
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

local _ui_text_cache = text_cache()

function Utils.neuro_log(...)
  if require("core.config").bool("NEURO_DEBUG") then print("[neuro-game]", ...) end
end

local function push_line(lines, raw)
  if raw == nil then return end
  if lines.raw then
    local piece = strip_loc_tags(coerce_text(raw))
    if piece ~= "" then lines[#lines + 1] = piece end
    return
  end
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
  local dyna = type(cfg) == "table" and type(cfg.object) == "table"
    and type(cfg.object.config) == "table" and type(cfg.object.config.string) == "table"
  if type(cfg) == "table" and cfg.text ~= nil and not dyna then
    if type(cfg.text) == "table" then
      for _, v in ipairs(cfg.text) do
        push_line(lines, v)
      end
    else
      push_line(lines, cfg.text)
    end
  end

  if dyna then
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
      -- DynaText shows one element at a time, so list each distinct element only once.
      local seen = {}
      for _, e in ipairs(strs) do
        local s = dyna_str(e)
        local key = s and s:match("^%s*(.-)%s*$")
        if s and not seen[key] and not (s:find("#@", 1, true) or s:find("()", 1, true)) then
          seen[key] = true
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

local function is_badge_row(row)
  if type(row) ~= "table" or row.config ~= nil or #row == 0 then return false end
  for j = 1, #row do
    local n = row[j]
    if type(n) ~= "table" or type(n.nodes) ~= "table" or #n.nodes == 0 then return false end
    for k = 1, #n.nodes do
      if type(n.nodes[k]) ~= "table" or type(n.nodes[k].nodes) ~= "table" then return false end
    end
  end
  return true
end

-- Description text style comes from its rendered scale and colour.
local function row_text_styles(node, out, depth)
  if depth > 14 or type(node) ~= "table" then return end
  local cfg = node.config
  if type(cfg) == "table" then
    local oc = type(cfg.object) == "table" and cfg.object.config
    local dyna = type(oc) == "table" and type(oc.string) == "table"
    if type(cfg.text) == "string" and cfg.text:find("%S") and not dyna then
      out[#out + 1] = { scale = tonumber(cfg.scale), colour = cfg.colour }
    end
    if dyna then
      out[#out + 1] = { scale = tonumber(oc.scale), colour = type(oc.colours) == "table" and oc.colours[1] or nil }
    end
  end
  if node.nodes then row_text_styles(node.nodes, out, depth + 1) end
  for i = 1, #node do row_text_styles(node[i], out, depth + 1) end
end

local function same_colour(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  if a == b then return true end
  if a[1] == nil then return false end
  for i = 1, 4 do
    if a[i] ~= b[i] then return false end
  end
  return true
end

-- “None” is a literal localized word, not an absent value.
local function none_word()
  local ok, word = pcall(localize, "k_none")
  return (ok and type(word) == "string" and word ~= "" and word ~= "ERROR") and word or "None"
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

  local desc_lines, status_lines, row_notes = {}, {}, {}
  if type(ui.main) == "table" then
    local rows, main_scale = {}, 0
    for i = 1, #ui.main do
      local row = ui.main[i]
      if is_badge_row(row) then
        collect_ui_lines(row, status_lines, 0)
      else
        local styles = {}
        row_text_styles(row, styles, 0)
        for _, st in ipairs(styles) do main_scale = math.max(main_scale, st.scale or 0) end
        rows[#rows + 1] = { row = row, styles = styles }
      end
    end
    local inactive = G and G.C and G.C.UI and G.C.UI.TEXT_INACTIVE
    for _, r in ipairs(rows) do
      local pieces = { raw = true }
      collect_ui_lines(r.row, pieces, 0)
      local text = clean_loc_text(table.concat(pieces))
      if text and desc_lines[#desc_lines] ~= text then
        local note = #r.styles > 0
        for _, st in ipairs(r.styles) do
          local small = st.scale and st.scale < main_scale * 0.95
          if not (small or same_colour(st.colour, inactive)) then note = false end
        end
        desc_lines[#desc_lines + 1] = text
        row_notes[#desc_lines] = note
      end
    end
  end
  local desc = (#desc_lines > 0) and join_desc_lines(desc_lines, row_notes) or nil
  if #status_lines > 0 then
    local none = none_word()
    for i, line in ipairs(status_lines) do
      if line == none then status_lines[i] = line:lower() end
    end
    local status = "(currently: " .. table.concat(status_lines, " ") .. ")"
    desc = desc and (desc .. " " .. status) or status
  end

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
  local entry = memo(_ui_text_cache, card, ui_text_signature, function(c)
    local name, desc, info = build_ui_text(c)
    return { name = name, desc = desc, info = info }
  end)
  return entry.name, entry.desc, entry.info
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

local function readable_name(text, placeholders)
  local nm = clean_loc_text(text, placeholders)
  if not nm or nm == "" then return nil end
  if nm:find("_") and not nm:find(" ") then return humanize_identifier(nm) end
  return nm
end

local function localized_name(card, center, placeholders)
  local function clean(text)
    if not text then return nil end
    local nm = clean_loc_text(text, placeholders)
    if nm and nm ~= "" then return nm end
  end
  local entry = get_localization_entry(card)
  local nm = clean(entry and entry.name) or clean(center.loc_txt and center.loc_txt.name)
  if nm then return nm end
  local pc = center.key and G and G.P_CENTERS and G.P_CENTERS[center.key]
  return clean(pc and pc.loc_txt and pc.loc_txt.name)
end

-- Stone cards hide rank and suit in the engine.
function Utils.hides_front(card)
  if type(card) ~= "table" then return false end
  if type(card.should_hide_front) == "function" then
    local ok, v = pcall(card.should_hide_front, card)
    if ok and v then return true end
  end
  local center = type(card.config) == "table" and type(card.config.center) == "table" and card.config.center or {}
  local ability = type(card.ability) == "table" and card.ability or {}
  return center.effect == "Stone Card" or center.replace_base_card == true or center.key == "m_stone"
    or ability.effect == "Stone Card" or ability.enhancement == "m_stone" or ability.name == "Stone Card"
end

function Utils.playing_card_label(card)
  if Utils.hides_front(card) then
    local center = type(card.config) == "table" and type(card.config.center) == "table" and card.config.center or {}
    return localized_name(card, center) or (center.name and readable_name(center.name))
      or (center.key == "m_stone" and "Stone Card") or "card with no rank or suit"
  end
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

  local ok_ui, ui_name = pcall(get_cached_ui_text, card)
  if ok_ui and type(ui_name) == "string" and ui_name ~= "" and not Utils.is_masked_name(ui_name) then
    return ui_name
  end

  local localized = localized_name(card, center, placeholders)
  if localized then return localized end

  local lbl = card.label and readable_name(card.label, placeholders)
  if lbl then
    local first_char = lbl:sub(1, 1)
    if lbl:find(" ") or (first_char == first_char:upper() and first_char ~= first_char:lower()) then
      return lbl
    end
  end

  local nm = center.name and readable_name(center.name, placeholders)
  if nm then return nm end
  nm = card.ability and card.ability.name and readable_name(card.ability.name, placeholders)
  if nm then return nm end

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
  local localized = localized_name(card, center, placeholders)
  if localized then return localized end
  if type(center.name) == "string" and center.name ~= "" then
    local nm = readable_name(center.name, placeholders)
    if nm then return nm end
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
  for _, v in ipairs(desc) do append_text(parts, v) end
  if #parts > 0 then
    local notes = {}
    for i, line in ipairs(parts) do notes[i] = raw_note_line(line) end
    return join_desc_lines(parts, notes)
  end
  for k, v in pairs(desc) do
    if type(k) == "string" then append_text(parts, v) end
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
  local ok_ui, _, ui_desc = pcall(get_cached_ui_text, card)
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

  local candidates = {
    center.loc_txt and (center.loc_txt.description or center.loc_txt.text),
    ability.loc_txt and (ability.loc_txt.description or ability.loc_txt.text),
    card.loc_txt and (card.loc_txt.description or card.loc_txt.text),
    entry and (entry.text or entry.description),
    pc_loc,
  }
  -- Keep candidate positions fixed: missing candidates leave holes.
  for i = 1, 5 do
    local out = clean_loc_text(candidates[i], placeholders)
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
  local ok, _, _, info = pcall(get_cached_ui_text, card)
  if ok and type(info) == "string" and info ~= "" then return info end
  return nil
end

Utils.humanize_identifier = humanize_identifier

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

function Utils.env_flag(name)
  local v = os.getenv(name)
  if not v then return nil end
  v = tostring(v):lower()
  if v == "1" or v == "on" or v == "true" or v == "yes" then return true end
  if v == "0" or v == "off" or v == "false" or v == "no" then return false end
  return nil
end

function Utils.stable_repr(value, max_depth, depth, seen)
  local kind = type(value)
  if kind == "nil" or kind == "boolean" or kind == "number" or kind == "string" then
    return tostring(value)
  end
  if kind ~= "table" then return kind end
  depth = depth or 0
  if depth >= max_depth then return "{...}" end
  seen = seen or {}
  if seen[value] then return "<cycle>" end
  seen[value] = true
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, key in ipairs(keys) do
    parts[#parts + 1] = tostring(key) .. "=" .. Utils.stable_repr(value[key], max_depth, depth + 1, seen)
  end
  seen[value] = nil
  return "{" .. table.concat(parts, ",") .. "}"
end

function Utils.identity_value(value)
  if value == nil then return "-" end
  local text = tostring(value)
  return type(value) .. ":" .. tostring(#text) .. ":" .. text
end

function Utils.index_in(cards, target)
  for index, card in ipairs(cards or {}) do
    if card == target then return index end
  end
  return nil
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
local function infinity_text(n)
  local raw = tonumber(n)
  if raw == math.huge then return "inf" end
  if raw == -math.huge then return "-inf" end
  return nil
end

local function finite_number(n)
  n = tonumber(n)
  if not n or n ~= n or n == math.huge or n == -math.huge then return 0 end
  return n
end

function Utils.fmt_num(n)
  local inf = infinity_text(n)
  if inf then return inf end
  n = finite_number(n)
  local a = n < 0 and -n or n
  -- Round before testing zero so tiny negatives do not render as -0.
  if a < 1e15 and n % 1 ~= 0 then n = tonumber(string.format("%.2f", n)) end
  if n == 0 then return "0" end
  if a < 1e15 then
    if n % 1 ~= 0 then return (string.format("%.2f", n):gsub("%.?0+$", "")) end
    return string.format("%.0f", n)
  end
  return string.format("%.4g", n)
end


function Utils.money(n)
  n = tonumber(n) or 0
  return (n < 0 and "-$" or "$") .. Utils.fmt_num(n < 0 and -n or n)
end

function Utils.money_change(n)
  n = tonumber(n) or 0
  return (n < 0 and "" or "+") .. Utils.money(n)
end

function Utils.fmt_2dp(n)
  local inf = infinity_text(n)
  if inf then return inf end
  local value = tonumber(string.format("%.2f", finite_number(n)))
  if value == 0 then return "0" end
  return tostring(value)
end

function Utils.fmt_xmult(n)
  return "x" .. Utils.fmt_2dp(n)
end

function Utils.signed(n)
  local text = Utils.fmt_num(n)
  return (text:sub(1, 1) == "-" and "" or "+") .. text
end

function Utils.trim_line_ends(text)
  if type(text) ~= "string" then return text end
  return (text:gsub("[ \t]+\n", "\n"):gsub("[ \t]+$", ""):gsub("\n\n\n+", "\n\n"))
end

return Utils
