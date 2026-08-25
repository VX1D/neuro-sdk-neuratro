local CardDex = { active = false }

local Cards = require("hud.cards")

local SETS = { Joker = 1, Tarot = 2, Planet = 3, Spectral = 4, Voucher = 5, Booster = 6 }
local EDITIONS = {
  { key = "none",       label = "none",  ed = nil },
  { key = "foil",       label = "foil",  ed = { foil = true } },
  { key = "holo",       label = "holo",  ed = { holo = true } },
  { key = "polychrome", label = "poly",  ed = { polychrome = true } },
  { key = "negative",   label = "neg",   ed = { negative = true } },
}
local SIZES = { 26, 40, 110 }
local VARIANTS = {
  { key = "plain",    label = "plain" },
  { key = "seal",     label = "seal" },
  { key = "stickers", label = "stickers" },
  { key = "debuff",   label = "debuff" },
}

local PATH_COLORS = {
  shader   = { 0.35, 0.85, 0.45 },
  plain    = { 0.55, 0.62, 0.70 },
  overlay  = { 0.95, 0.78, 0.25 },
  fallback = { 0.95, 0.30, 0.30 },
  quad     = { 0.95, 0.30, 0.30 },
  edition  = { 0.95, 0.45, 0.20 },
  send     = { 0.95, 0.45, 0.20 },
  sticker  = { 0.80, 0.45, 0.95 },
}
local PATH_ORDER = { "shader", "plain", "overlay", "fallback", "quad", "edition", "send", "sticker" }

local _cards, _scroll, _ed_i, _size_i, _only_bad = nil, 0, 1, 3, false
local _paths, _content_h, _last_report = {}, 0, nil
local _job, _btn, _job_source, _boot_done = nil, nil, nil, false

local function counters()
  return {
    fallback = Cards._mini_fallback or 0,
    quad = Cards._mini_quad_fail or 0,
    edition = Cards._mini_edition_fail or 0,
    skip = Cards._mini_edition_skip or 0,
    send = Cards._mini_shader_fail or 0,
    sticker = Cards._mini_sticker_fail or 0,
  }
end

local function classify(before, after, has_edition)
  if after.fallback > before.fallback then return "fallback" end
  if after.quad > before.quad then return "quad" end
  if after.edition > before.edition then return "edition" end
  if after.send > before.send then return "send" end
  if after.sticker > before.sticker then return "sticker" end
  if after.skip > before.skip then return "overlay" end
  return has_edition and "shader" or "plain"
end

local function build_card(center, ed, variant)
  local ability = { set = center.set or "Joker", name = center.name or center.key,
    mult = 0, h_mult = 0, h_mod = 0, t_mult = 0, t_chips = 0, x_mult = 1, extra = 0 }
  if variant == "stickers" then
    ability.eternal, ability.perishable, ability.rental = true, true, true
  end
  return {
    config = { center = center },
    ability = ability,
    base = { name = center.key },
    edition = ed,
    seal = (variant == "seal") and "Gold" or nil,
    debuff = variant == "debuff",
    cost = 5, sell_cost = 2,
    VT = { w = 71, h = 95, scale = 1, x = 0, y = 0 },
  }
end

local function collect()
  local out = {}
  if not (G and G.P_CENTERS) then return out end
  for key, center in pairs(G.P_CENTERS) do
    if type(center) == "table" and SETS[center.set] and center.pos then
      out[#out + 1] = { key = key, center = center, set = center.set }
    end
  end
  table.sort(out, function(a, b)
    if a.set ~= b.set then return (SETS[a.set] or 99) < (SETS[b.set] or 99) end
    return a.key < b.key
  end)
  return out
end

local function ensure_cards()
  if not _cards then _cards = collect() end
  return _cards
end

function CardDex.entries()
  return ensure_cards()
end

local function run_combo(size, ed, variant, record_paths)
  local list = ensure_cards()
  local tally, bad = {}, {}
  for _, entry in ipairs(list) do
    local before = counters()
    local ok = pcall(function()
      Cards.draw_card_mini(build_card(entry.center, ed, variant), -20000, -20000, size, 1)
    end)
    local after = counters()
    local path = ok and classify(before, after, ed ~= nil) or "edition"
    if record_paths then _paths[entry.key] = path end
    tally[path] = (tally[path] or 0) + 1
    if path ~= "shader" and path ~= "plain" then
      bad[#bad + 1] = entry.key .. " (" .. entry.set .. ") -> " .. path
    end
  end
  return tally, bad
end

function CardDex.sweep()
  _paths = {}
  return (run_combo(SIZES[_size_i], EDITIONS[_ed_i].ed, "plain", true))
end

local function combo_list()
  local out = {}
  for _, size in ipairs(SIZES) do
    for _, e in ipairs(EDITIONS) do
      for _, v in ipairs(VARIANTS) do
        out[#out + 1] = { size = size, ed = e, variant = v }
      end
    end
  end
  return out
end

local function write_report(results, elapsed_note)
  local list = ensure_cards()
  local lines = {
    "# Neuratro card dex sweep",
    "",
    "Date: " .. os.date("%Y-%m-%d %H:%M:%S"),
    "Cards: " .. #list,
    "Matrix: " .. #SIZES .. " sizes x " .. #EDITIONS .. " editions x " .. #VARIANTS
      .. " variants = " .. (#SIZES * #EDITIONS * #VARIANTS) .. " sweeps",
    elapsed_note or "",
    "",
  }
  local off_total = 0
  for _, size in ipairs(SIZES) do
    lines[#lines + 1] = "## size: " .. size .. " px"
    lines[#lines + 1] = ""
    for _, e in ipairs(EDITIONS) do
      for _, v in ipairs(VARIANTS) do
        local r = results[size .. "|" .. e.key .. "|" .. v.key]
        if r then
          local parts = {}
          for _, path in ipairs(PATH_ORDER) do
            if r.tally[path] then parts[#parts + 1] = path .. "=" .. r.tally[path] end
          end
          off_total = off_total + #r.bad
          lines[#lines + 1] = "- **" .. e.label .. " / " .. v.label .. "**: "
            .. (#parts > 0 and table.concat(parts, ", ") or "no cards")
            .. (#r.bad > 0 and ("  <- " .. #r.bad .. " off-path") or "")
          for i = 1, math.min(#r.bad, 12) do
            lines[#lines + 1] = "  - `" .. r.bad[i] .. "`"
          end
          if #r.bad > 12 then
            lines[#lines + 1] = "  - ... and " .. (#r.bad - 12) .. " more"
          end
        end
      end
    end
    lines[#lines + 1] = ""
  end
  table.insert(lines, 6, "Off-path total: " .. off_total)

  lines[#lines + 1] = "## Path legend"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "- `shader` - edition drawn with the real shader"
  lines[#lines + 1] = "- `plain` - no edition, sprite only"
  lines[#lines + 1] = "- `overlay` - overlay fallback, shader or atlas missing"
  lines[#lines + 1] = "- `fallback` - name placeholder instead of the sprite"
  lines[#lines + 1] = "- `quad` - newQuad failed"
  lines[#lines + 1] = "- `edition` - edition pass threw"
  lines[#lines + 1] = "- `send` - shader.send failed"
  lines[#lines + 1] = "- `sticker` - sticker atlas missing"
  lines[#lines + 1] = ""

  local body = table.concat(lines, "\n")
  local name = "carddex/" .. os.date("%Y-%m-%d-%H%M%S") .. "-carddex.md"
  local lv = love
  if lv and lv.filesystem and lv.filesystem.write then
    lv.filesystem.createDirectory("carddex")
    if lv.filesystem.write(name, body) then
      _last_report = "love-save://" .. name
      print("[neuro-game] card dex report: " .. _last_report .. "  off-path=" .. off_total)
      return _last_report
    end
  end
  print("[neuro-game] card dex report failed to write")
  return nil
end

function CardDex.report()
  local results = {}
  for _, c in ipairs(combo_list()) do
    local tally, bad = run_combo(c.size, c.ed.ed, c.variant.key, false)
    results[c.size .. "|" .. c.ed.key .. "|" .. c.variant.key] = { tally = tally, bad = bad }
  end
  CardDex.sweep()
  return write_report(results)
end

function CardDex.ready()
  if not (G and G.P_CENTERS and G.ASSET_ATLAS) then return false end
  if next(G.ASSET_ATLAS) == nil then return false end
  return #collect() > 0
end

function CardDex.start_full_sweep(source)
  _job = { combos = combo_list(), i = 0, results = {} }
  _job_source = source or "button"
  return #_job.combos
end

function CardDex.step_job()
  if not _job then return false end
  local c = _job.combos[_job.i + 1]
  if not c then
    local done_report = write_report(_job.results, "Run: full matrix, started from " .. tostring(_job_source))
    _job, _job_source = nil, nil
    CardDex.sweep()
    return done_report
  end
  local tally, bad = run_combo(c.size, c.ed.ed, c.variant.key, false)
  _job.results[c.size .. "|" .. c.ed.key .. "|" .. c.variant.key] = { tally = tally, bad = bad }
  _job.i = _job.i + 1
  return true
end

function CardDex.boot_tick()
  if _boot_done then return false end
  if _job then
    CardDex.step_job()
    if not _job then _boot_done = true end
    return true
  end
  if not CardDex.ready() then return false end
  local n = CardDex.start_full_sweep("boot")
  print("[neuro-game] card dex on boot: sweeping " .. n .. " combos")
  return true
end

function CardDex.boot_done()
  return _boot_done
end

function CardDex.job_progress()
  if not _job then return nil end
  return _job.i, #_job.combos
end

function CardDex.set(on)
  CardDex.active = not not on
  if CardDex.active then
    _cards = collect()
    CardDex.sweep()
  end
end

function CardDex.toggle() CardDex.set(not CardDex.active) end

function CardDex.keypressed(key)
  if not CardDex.active then return false end
  if key == "e" then
    _ed_i = (_ed_i % #EDITIONS) + 1
    CardDex.sweep()
    return true
  elseif key == "s" then
    _size_i = (_size_i % #SIZES) + 1
    _scroll = 0
    CardDex.sweep()
    return true
  elseif key == "f" then
    _only_bad = not _only_bad
    _scroll = 0
    return true
  elseif key == "r" then
    if not _job then CardDex.start_full_sweep() end
    return true
  elseif key == "down" then
    _scroll = _scroll + 60
    return true
  elseif key == "up" then
    _scroll = math.max(0, _scroll - 60)
    return true
  elseif key == "pagedown" then
    _scroll = _scroll + 400
    return true
  elseif key == "pageup" then
    _scroll = math.max(0, _scroll - 400)
    return true
  elseif key == "home" then
    _scroll = 0
    return true
  end
  return false
end

function CardDex.mousepressed(x, y, button)
  if not (CardDex.active and _btn and button == 1) then return false end
  if x >= _btn.x and x <= _btn.x + _btn.w and y >= _btn.y and y <= _btn.y + _btn.h then
    if not _job then
      local n = CardDex.start_full_sweep()
      print("[neuro-game] card dex: full sweep started (" .. n .. " combos)")
    end
    return true
  end
  return CardDex.active
end

function CardDex.wheelmoved(_, wy)
  if not CardDex.active then return false end
  _scroll = math.max(0, _scroll - (wy or 0) * 60)
  if _content_h > 0 then _scroll = math.min(_scroll, _content_h) end
  return true
end

local function visible_list()
  local list = ensure_cards()
  if not _only_bad then return list end
  local out = {}
  for _, e in ipairs(list) do
    local p = _paths[e.key]
    if p and p ~= "shader" and p ~= "plain" then out[#out + 1] = e end
  end
  return out
end

function CardDex.draw()
  if not CardDex.active then return end
  local lg = love.graphics
  local sw, sh = lg.getWidth(), lg.getHeight()
  lg.setColor(0.04, 0.04, 0.06, 0.96)
  lg.rectangle("fill", 0, 0, sw, sh)

  local Assets = require("hud.assets")
  local hs = math.max(0.5, math.floor((sh / 1080) / 0.05 + 0.5) * 0.05)
  local font = Assets.font_px and Assets.font_px(math.floor(12 * hs + 0.5)) or lg.getFont()
  local f0 = lg.getFont()
  if font ~= f0 then lg.setFont(font) end
  local fh = font:getHeight()

  local size = SIZES[_size_i]
  local ed = EDITIONS[_ed_i].ed
  local list = visible_list()

  local cell_w = math.max(48, math.ceil(71 * (size / 95)) + 18)
  local cell_h = size + fh + 14
  local cols = math.max(1, math.floor((sw - 24) / cell_w))
  local rows = math.ceil(#list / cols)
  local head_h = 15 + fh * 3
  _content_h = math.max(0, rows * cell_h - (sh - head_h - 12))
  if _scroll > _content_h then _scroll = _content_h end

  local tally = {}
  for _, e in ipairs(ensure_cards()) do
    local p = _paths[e.key] or "plain"
    tally[p] = (tally[p] or 0) + 1
  end
  local parts = {}
  for _, p in ipairs(PATH_ORDER) do
    if tally[p] then parts[#parts + 1] = p .. ":" .. tally[p] end
  end

  lg.setColor(1, 1, 1, 0.95)
  lg.print("CARD DEX   " .. #ensure_cards() .. " cards   edition=" .. EDITIONS[_ed_i].label
    .. "   size=" .. size .. "px   filter=" .. (_only_bad and "issues only" or "all"), 12, 10)
  lg.setColor(0.75, 0.80, 0.88, 0.95)
  lg.print(table.concat(parts, "   "), 12, 10 + fh + 3)
  lg.setColor(0.55, 0.60, 0.68, 0.9)
  lg.print("E edition   S size   F filter   scroll: wheel/arrows"
    .. (_last_report and ("   last report: " .. _last_report) or ""), 12, 10 + (fh + 3) * 2)

  local bw, bh = math.max(150, font:getWidth("RUN ALL 60 SWEEPS") + 24), fh + 14
  local bx, by = sw - bw - 12, 8
  _btn = { x = bx, y = by, w = bw, h = bh }
  local running = _job ~= nil
  lg.setColor(running and 0.95 or 0.35, running and 0.78 or 0.85, running and 0.25 or 0.45, 0.22)
  lg.rectangle("fill", bx, by, bw, bh, 4, 4)
  lg.setColor(running and 0.95 or 0.35, running and 0.78 or 0.85, running and 0.25 or 0.45, 0.95)
  lg.rectangle("line", bx, by, bw, bh, 4, 4)
  local blabel = running and "SWEEPING..." or ("RUN ALL " .. (#SIZES * #EDITIONS * #VARIANTS) .. " SWEEPS")
  lg.setColor(1, 1, 1, 0.95)
  lg.print(blabel, bx + math.floor((bw - font:getWidth(blabel)) / 2), by + 7)

  if running then
    CardDex.step_job()
    local i, n = CardDex.job_progress()
    if i then
      local pw = bw
      lg.setColor(0.35, 0.85, 0.45, 0.85)
      lg.rectangle("fill", bx, by + bh + 3, pw * (i / n), 3)
      lg.setColor(0.75, 0.80, 0.88, 0.9)
      lg.print(i .. "/" .. n, bx, by + bh + 8)
    end
  end

  local top = head_h
  lg.setScissor(0, top, sw, sh - top)
  for i, entry in ipairs(list) do
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local x = 12 + col * cell_w
    local y = top + 6 + row * cell_h - _scroll
    if y + cell_h >= top and y <= sh then
      local path = _paths[entry.key] or "plain"
      local pc = PATH_COLORS[path] or PATH_COLORS.plain
      lg.setColor(pc[1], pc[2], pc[3], 0.16)
      lg.rectangle("fill", x - 3, y - 3, cell_w - 6, cell_h - 6, 3, 3)
      local ok = pcall(function()
        Cards.draw_card_mini(build_card(entry.center, ed), x, y, size, 1)
      end)
      if not ok then
        lg.setColor(0.95, 0.2, 0.2, 0.8)
        lg.rectangle("fill", x, y, cell_w - 12, size)
      end
      lg.setColor(pc[1], pc[2], pc[3], 0.95)
      lg.rectangle("fill", x - 3, y - 3, 4, 4)
      lg.setColor(0.86, 0.88, 0.92, 0.9)
      local label = entry.key:gsub("^[jvcp]_", "")
      if font:getWidth(label) > cell_w - 12 then
        while #label > 1 and font:getWidth(label .. "..") > cell_w - 12 do
          label = label:sub(1, #label - 1)
        end
        label = label .. ".."
      end
      lg.print(label, x, y + size + 3)
    end
  end
  lg.setScissor()
  if font ~= f0 then lg.setFont(f0) end
  lg.setColor(1, 1, 1, 1)
end

return CardDex
