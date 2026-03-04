local Utils = {}

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
  s = s:gsub("{[^}]*}", "")
  return s
end

local function humanize_identifier(id)
  local s = tostring(id or "")
  if s == "" then return "" end
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
  return s
end

local function collect_placeholder_values(card)
  local values = {}
  local function push(v)
    if v == nil then return end
    local t = type(v)
    if t == "number" then
      values[#values + 1] = tostring(v)
    elseif t == "string" then
      local n = tonumber(v)
      if n then values[#values + 1] = tostring(n) end
    end
  end

  if not card then return values end
  local ability = card.ability or {}

  push(ability.x_mult)
  push(ability.h_mult)
  push(ability.h_mod)
  push(ability.c_mult)
  push(ability.t_mult)
  push(ability.d_mult)
  push(ability.s_mult)
  push(ability.p_mult)
  push(ability.x_chips)
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

local function clean_loc_text(raw, placeholder_values)
  if raw == nil then return nil end
  local text = raw
  if type(text) == "table" then
    text = Utils.flatten_description(text)
  else
    text = tostring(text)
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
  text = normalize_spaces(text)
  if text == "" then return nil end
  return text
end

local _ui_text_cache = setmetatable({}, { __mode = "k" })

local function now_time()
  if G and G.TIMERS and G.TIMERS.REAL then return G.TIMERS.REAL end
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

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

  if node.nodes then
    collect_ui_lines(node.nodes, lines, seen, depth + 1)
  end

  for i = 1, #node do
    collect_ui_lines(node[i], lines, seen, depth + 1)
  end
end

local function build_ui_text(card)
  if not (card and type(card.generate_UIBox_ability_table) == "function") then
    return nil, nil
  end

  local ok, ui = pcall(function()
    return card:generate_UIBox_ability_table()
  end)
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
  if cache and (t - (cache.at or 0)) < 0.75 then
    return cache.name, cache.desc
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

function Utils.safe_name(card)
  if not card then return nil end

  if card.base and card.base.value and card.base.suit then
    return tostring(card.base.value) .. " of " .. tostring(card.base.suit)
  end

  local placeholders = collect_placeholder_values(card)
  local center = card.config and card.config.center or {}

  -- Try proper localization sources first so SMODS/modded cards get their real names
  -- (card.label for SMODS cards is often the raw key like "vedalsdrink", not the display name)

  local ui_name = nil
  local ok_ui, n = pcall(function()
    local name = get_cached_ui_text(card)
    return name
  end)
  if ok_ui then ui_name = n end
  if ui_name and ui_name ~= "" then
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

  -- Fall back to card.label — but only if it looks like a real name (has spaces or is capitalized)
  -- Skip raw identifiers like "vedalsdrink" that slip through as labels for SMODS cards
  if card.label and card.label ~= "" then
    local lbl = clean_loc_text(card.label, placeholders)
    if lbl and lbl ~= "" then
      if lbl:find("_") and not lbl:find(" ") then
        lbl = humanize_identifier(lbl)
      end
      -- Accept label if it has spaces (multi-word name) or starts uppercase (capitalized name)
      -- Reject single-word all-lowercase strings like "vedalsdrink" (raw SMODS keys)
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

function Utils.flatten_description(desc)
  if desc == nil then return nil end
  if type(desc) == "string" then return desc end
  if type(desc) ~= "table" then return tostring(desc) end
  local parts = {}
  for _, v in ipairs(desc) do
    if type(v) == "table" then
      for _, line in ipairs(v) do
        parts[#parts + 1] = tostring(line)
      end
    else
      parts[#parts + 1] = tostring(v)
    end
  end
  if #parts > 0 then return table.concat(parts, " ") end
  for k, v in pairs(desc) do
    if type(k) == "string" then
      if type(v) == "table" then
        for _, line in ipairs(v) do
          parts[#parts + 1] = tostring(line)
        end
      else
        parts[#parts + 1] = tostring(v)
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
  if out and max_len and #out > max_len then
    out = out:sub(1, max_len - 3) .. "..."
  end
  return out or ""
end

function Utils.card_description(card, max_len)
  if not card then return nil end

  local ok_ui, _, ui_desc = pcall(function()
    local name, desc = get_cached_ui_text(card)
    return name, desc
  end)
  if ok_ui and ui_desc and ui_desc ~= "" then
    if max_len and #ui_desc > max_len then
      return ui_desc:sub(1, max_len - 3) .. "..."
    end
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

  for _, candidate in ipairs(candidates) do
    local out = clean_loc_text(candidate, placeholders)
    if out and out ~= "" then
      if max_len and #out > max_len then
        return out:sub(1, max_len - 3) .. "..."
      end
      return out
    end
  end

  return nil
end

function Utils.humanize_identifier(id)
  return humanize_identifier(id)
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

return Utils
