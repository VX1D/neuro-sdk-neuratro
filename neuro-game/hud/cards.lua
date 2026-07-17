local Cards = {}
Cards._mini_edition_fail = 0
Cards._mini_fallback = 0

local Palette = require("render.palette")
local Utils = require("util.utils")
local S = require("hud.state")
local Assets = require("hud.assets")
local Prims = require("hud.prims")
local smoothstep01 = Prims.smoothstep01

local neuro_log = Utils.neuro_log

local function card_edition_tag(c)
  local ed = c and c.edition
  if not ed then return "" end
  if ed.negative    then return " [Neg +slot]" end
  if ed.polychrome  then return " [Poly x1.5]" end
  if ed.holo        then return " [Holo +10]"  end
  if ed.foil        then return " [Foil +50]"  end
  return ""
end

local function draw_animated_edition(tag, x, y, alpha, f, t, persona)
  if not tag or tag == "" then return end
  local ev = persona == "evil"
  local r, g, b
  if tag:find("Poly") then
    local hue = (t * (ev and 0.7 or 1.3)) % 1.0
    if ev then
      r = math.abs(math.sin(hue * 6.283 + 0.00)) * 0.75 + 0.20
      g = math.abs(math.sin(hue * 6.283 + 2.09)) * 0.25 + 0.02
      b = math.abs(math.sin(hue * 6.283 + 4.19)) * 0.45 + 0.04
    else
      r = math.abs(math.sin(hue * 6.283 + 0.00)) * 0.60 + 0.35
      g = math.abs(math.sin(hue * 6.283 + 2.09)) * 0.55 + 0.30
      b = math.abs(math.sin(hue * 6.283 + 4.19)) * 0.55 + 0.35
    end
  elseif tag:find("Holo") then
    local s = 0.5 + 0.5 * math.sin(t * (ev and 2.6 or 4.2))
    if ev then
      r = 0.82 + s * 0.18; g = 0.06 + s * 0.06; b = 0.08 + s * 0.10
    else
      r = 0.90 - s * 0.55; g = 0.55 + s * 0.42; b = 0.80 - s * 0.35
    end
  elseif tag:find("Foil") then
    local s = 0.5 + 0.5 * math.sin(t * 2.6)
    if ev then
      r = 0.70 + s * 0.22; g = 0.62 + s * 0.06; b = 0.60 + s * 0.06
    else
      r = 0.68 + s * 0.08; g = 0.78 + s * 0.14; b = 0.80 + s * 0.16
    end
  elseif tag:find("Neg") then
    local s = 0.5 + 0.5 * math.sin(t * (ev and 2.0 or 3.1))
    if ev then
      r = 0.65 + s * 0.30; g = 0.02; b = 0.04 + s * 0.06
    else
      r = 0.04 + s * 0.06; g = 0.55 + s * 0.38; b = 0.52 + s * 0.36
    end
  else
    return
  end
  local prev = love.graphics.getFont()
  if f and f ~= prev then love.graphics.setFont(f) end
  love.graphics.setColor(0, 0, 0, 0.40 * alpha)
  love.graphics.print(tag, x + 1, y + 1)
  love.graphics.setColor(r, g, b, 0.97 * alpha)
  love.graphics.print(tag, x, y)
  if tag:find("Poly") or tag:find("Holo") then
    love.graphics.setColor(r * 0.6, g * 0.6, b * 0.6, 0.18 * alpha)
    love.graphics.print(tag, x - 1, y)
    love.graphics.print(tag, x + 1, y)
  end
  if f and f ~= prev then love.graphics.setFont(prev) end
  love.graphics.setColor(1, 1, 1, 1)  -- don't leave the animated tint set for the next draw
end

local function card_display_name(c)
  local n = Utils.safe_name(c)
  return (type(n) == "string" and n ~= "") and n or "?"
end

local function card_description(c)
  return Utils.card_description(c)
end

local SEAL_DOT_COLORS = {
  Red    = {0.95, 0.20, 0.20},
  Blue   = {0.20, 0.55, 0.95},
  Gold   = {0.95, 0.75, 0.10},
  Purple = {0.70, 0.25, 0.90},
}

local SEAL_POS = {
  Gold   = { x = 2, y = 0 },
  Purple = { x = 4, y = 4 },
  Red    = { x = 5, y = 4 },
  Blue   = { x = 6, y = 4 },
}

local STICKER_POS = {
  eternal    = { x = 0, y = 0 },
  perishable = { x = 0, y = 2 },
  rental     = { x = 1, y = 2 },
}

local function valid_pos(p)
  return type(p) == "table" and type(p.x) == "number" and type(p.y) == "number"
end

-- failures negative-cached as false so bad geometry doesn't retry every frame
local function cached_quad(key, sx, sy, w, h, image)
  local q = S.quad_cache[key]
  if q ~= nil then return q, false end
  local ok, nq = pcall(love.graphics.newQuad, sx, sy, w, h, image:getDimensions())
  q = ok and nq or false
  S.quad_cache[key] = q
  return q, (not ok)
end

local function atlas_quad(atlas_key, pos)
  local atlas = G.ASSET_ATLAS[atlas_key]
  if not atlas or not atlas.image or not valid_pos(pos) then return nil end
  local px, py = atlas.px or 71, atlas.py or 95
  local q = cached_quad(atlas_key .. "_" .. pos.x .. "_" .. pos.y, pos.x * px, pos.y * py, px, py, atlas.image)
  if not q then return nil end
  return atlas, q, px, py
end

local function draw_atlas_quad(atlas_key, pos, x, y, scale, a)
  local atlas, q, px = atlas_quad(atlas_key, pos)
  if not atlas then return 0 end
  love.graphics.setColor(1, 1, 1, a)
  love.graphics.draw(atlas.image, q, x, y, 0, scale, scale)
  love.graphics.setColor(1, 1, 1, 1)
  return px * scale
end

local function draw_shaded_quad(atlas_key, pos, x, y, scale, a, shader_name, card)
  local shader = G.SHADERS and G.SHADERS[shader_name]
  local atlas, q, px, py = atlas_quad(atlas_key, pos)
  if not shader or not atlas then return false end
  local iw, ih = atlas.image:getDimensions()
  shader:send("texture_details", { pos.x, pos.y, px, py })
  shader:send("image_details", { iw, ih })
  shader:send("mouse_screen_pos", { 0, 0 })
  shader:send("screen_scale", (G.TILESCALE or 3.65) * (G.TILESIZE or 20) * (G.CANV_SCALE or 1))
  shader:send("hovering", 0)
  shader:send("dissolve", 0)
  shader:send("time", 123.33412 * (((card and card.ID or 1) / 1.14212) % 3000))
  shader:send("burn_colour_1", (G.C and G.C.CLEAR) or { 0, 0, 0, 0 })
  shader:send("burn_colour_2", (G.C and G.C.CLEAR) or { 0, 0, 0, 0 })
  shader:send("shadow", false)
  if card and card.ARGS and card.ARGS.send_to_shader then
    pcall(shader.send, shader, shader_name, card.ARGS.send_to_shader)
  end
  love.graphics.setColor(1, 1, 1, a)
  love.graphics.setShader(shader)
  love.graphics.draw(atlas.image, q, x, y, 0, scale, scale)
  love.graphics.setShader()
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

local ENH_ABBR = {
  m_stone = "STN", m_bonus = "BON", m_mult = "MUL", m_wild = "WLD",
  m_gold = "GLD", m_steel = "STL", m_glass = "GLS", m_lucky = "LCK",
  m_twin = "TWN", m_dono = "DON", m_glorp = "GLP", m_blood = "BLD",
}

local function enh_abbr_of(card)
  local ab = card.ability
  if ab and ab.enhancement and ENH_ABBR[ab.enhancement] then return ENH_ABBR[ab.enhancement] end
  local center = card.config and card.config.center
  local key = center and center.key
  return key and ENH_ABBR[key] or nil
end

local function draw_enh_badge(card, x, y, h, a)
  local ab = enh_abbr_of(card)
  if not ab then return end
  local pill_h = math.max(8, h * 0.22)
  local f = Assets.font_px(math.floor(pill_h + 0.5))
  if not f or f:getHeight() <= 0 then return end
  local pad = 2
  local pw = f:getWidth(ab) + pad * 2
  local ph = f:getHeight() + pad
  local prev = love.graphics.getFont()
  love.graphics.setFont(f)
  love.graphics.setColor(0, 0, 0, 0.62 * a)
  love.graphics.rectangle("fill", x + 1, y + 1, pw, ph, 2, 2)
  love.graphics.setColor(1, 1, 1, 0.95 * a)
  love.graphics.print(ab, x + 1 + pad, y + 1 + pad * 0.5)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setFont(prev)
end

local function draw_mini_fallback(card, x, y, w, h, a)
  Cards._mini_fallback = Cards._mini_fallback + 1
  love.graphics.setColor(0.12, 0.12, 0.12, a)
  love.graphics.rectangle("fill", x, y, w, h, 2, 2)
  local name = card_display_name(card)
  if name and name ~= "?" then
    local f = love.graphics.getFont()
    local fh = f:getHeight()
    local maxw = w - 4
    while #name > 1 and f:getWidth(name) > maxw do name = name:sub(1, #name - 1) end
    love.graphics.setColor(0.9, 0.9, 0.9, a)
    love.graphics.print(name, x + 2, y + 2 + (h - fh - 4) * 0.5)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

local function draw_playing_card_mini(card, x, y, h, a, center, front, is_stone)
  local scale = h / 95
  local w = 71 * scale
  local ed = card.edition
  local front_atlas = (G.SETTINGS and G.SETTINGS.colourblind_option) and "cards_2" or "cards_1"
  local has_face = front and valid_pos(front.pos)

  local drew = false
  if center and valid_pos(center.pos) and draw_atlas_quad("centers", center.pos, x, y, scale, a) > 0 then
    drew = true
  end
  if has_face and not is_stone and draw_atlas_quad(front_atlas, front.pos, x, y, scale, a) > 0 then
    drew = true
  end
  if not drew then
    draw_mini_fallback(card, x, y, w, h, a)
    return w
  end

  if ed then
    local passes = (ed.negative and { "negative", "negative_shine" })
      or (ed.holo and { "holo" }) or (ed.foil and { "foil" }) or (ed.polychrome and { "polychrome" })
    if passes then
      local ok = pcall(function()
        for _, sh in ipairs(passes) do
          if center and valid_pos(center.pos) then draw_shaded_quad("centers", center.pos, x, y, scale, a, sh, card) end
          if has_face and not is_stone and sh ~= "negative_shine" then
            draw_shaded_quad(front_atlas, front.pos, x, y, scale, a, sh, card)
          end
        end
      end)
      if not ok then
        Cards._mini_edition_fail = Cards._mini_edition_fail + 1
        love.graphics.setColor(0.82, 0.86, 1.0, 0.18 * a)
        love.graphics.rectangle("fill", x, y, w, h)
        love.graphics.setColor(1, 1, 1, 1)
      end
    end
  end

  if card.seal and SEAL_POS[card.seal] then
    draw_atlas_quad("centers", SEAL_POS[card.seal], x, y, scale, a)
  end

  local ab = card.ability
  if ab then
    if ab.eternal then draw_atlas_quad("stickers", STICKER_POS.eternal, x, y, scale, a) end
    if ab.perishable then draw_atlas_quad("stickers", STICKER_POS.perishable, x, y, scale, a) end
    if ab.rental then draw_atlas_quad("stickers", STICKER_POS.rental, x, y, scale, a) end
  end

  if card.debuff then
    love.graphics.setColor(0.2, 0.2, 0.22, 0.5 * a)
    love.graphics.rectangle("fill", x, y, w, h)
    love.graphics.setColor(1, 0.25, 0.25, 0.9 * a)
    love.graphics.print("DB", x + 2, y + 2)
    love.graphics.setColor(1, 1, 1, 1)
  end

  return w
end

local function draw_card_mini_approx(card, x, y, h, a)
  a = a or 1
  if not card or not G or not G.ASSET_ATLAS then return 0 end
  local w = math.floor(71 * (h / 95))
  local center = card.config and card.config.center
  local is_stone = (center and center.key == "m_stone")
    or (card.ability and card.ability.effect == "Stone Card")
  local front = card.config and card.config.card
  local has_face = front and valid_pos(front.pos)
    and front.value ~= nil and front.suit ~= nil
  if has_face or is_stone then
    return draw_playing_card_mini(card, x, y, h, a, center, front, is_stone)
  end
  local atlas_override = nil
  if not center or not valid_pos(center.pos) then
    if front and valid_pos(front.pos) then
      center = front
      atlas_override = "cards_1"
    else
      -- modded center with pos = {} throws arithmetic errors every frame otherwise
      draw_mini_fallback(card, x, y, w, h, a)
      return w
    end
  end

  local drew_base_for_enhanced = false
  if not atlas_override and front and valid_pos(front.pos)
      and front.value ~= nil and front.suit ~= nil then
    local base_atlas = G.ASSET_ATLAS["cards_1"]
    if base_atlas and base_atlas.image then
      local bpx = base_atlas.px or 71
      local bpy = base_atlas.py or 95
      local bsc = h / bpy
      local bqk = "cards_1_" .. front.pos.x .. "_" .. front.pos.y
      local bq = cached_quad(bqk, front.pos.x * bpx, front.pos.y * bpy, bpx, bpy, base_atlas.image)
      if bq then
        love.graphics.setColor(1, 1, 1, a)
        love.graphics.draw(base_atlas.image, bq, x, y, 0, bsc, bsc)
        drew_base_for_enhanced = true
      end
    end
  end

  local atlas_key = atlas_override or center.atlas or center.set or "Joker"
  local atlas = G.ASSET_ATLAS[atlas_key]
  local akey = atlas_key
  if not atlas or not atlas.image then
    akey = center.set or "Joker"
    atlas = G.ASSET_ATLAS[akey]
    if not atlas or not atlas.image then
      if not drew_base_for_enhanced then draw_mini_fallback(card, x, y, w, h, a); return w end
    end
  end

  w = 71 * (h / 95)   -- cards_1 atlas cell ratio
  if atlas and atlas.image then
    local px = atlas.px or 71
    local py = atlas.py or 95
    local scale = h / py
    w = px * scale

    local qk = akey .. "_" .. center.pos.x .. "_" .. center.pos.y
    local q = cached_quad(qk, center.pos.x * px, center.pos.y * py, px, py, atlas.image)
    if not q and not drew_base_for_enhanced then draw_mini_fallback(card, x, y, w, h, a); return w end

    if q then
      love.graphics.setColor(1, 1, 1, (drew_base_for_enhanced and 0.82 or 1) * a)
      love.graphics.draw(atlas.image, q, x, y, 0, scale, scale)
      love.graphics.setColor(1, 1, 1, 1)

      if valid_pos(center.soul_pos) then
        local sk = akey .. "_soul_" .. center.soul_pos.x .. "_" .. center.soul_pos.y
        local sq = cached_quad(sk, center.soul_pos.x * px, center.soul_pos.y * py, px, py, atlas.image)
        if sq then
          love.graphics.setColor(1, 1, 1, 0.85 * a)
          love.graphics.draw(atlas.image, sq, x, y, 0, scale, scale)
        end
      end
    end
  end

  local ed = card.edition
  if ed then
    local t = (G.TIMERS and G.TIMERS.REAL) or 0
    if ed.negative then
      love.graphics.setColor(0, 0, 0, 0.55 * a)
      love.graphics.rectangle("fill", x, y, w, h)
      love.graphics.setColor(1, 1, 1, 0.40 * a)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", x, y, w, h)
      love.graphics.setLineWidth(1)
    elseif ed.polychrome then
      local r = 0.55 + 0.45 * math.sin(t * 2.5)
      local g = 0.55 + 0.45 * math.sin(t * 2.5 + 2.094)
      local b = 0.55 + 0.45 * math.sin(t * 2.5 + 4.189)
      love.graphics.setColor(r, g, b, 0.50 * a)
      love.graphics.rectangle("fill", x, y, w, h)
    elseif ed.holo then
      love.graphics.setColor(0.25, 0.50, 1.0, 0.38 * a)
      love.graphics.rectangle("fill", x, y, w, h)
      love.graphics.setColor(0.55, 0.80, 1.0, (0.20 + 0.10 * math.sin(t * 3.0)) * a)
      love.graphics.setLineWidth(1)
      love.graphics.rectangle("line", x, y, w, h)
    elseif ed.foil then
      love.graphics.setColor(0.78, 0.84, 0.92, 0.38 * a)
      love.graphics.rectangle("fill", x, y, w, h)
      love.graphics.setColor(0.92, 0.96, 1.0, (0.20 + 0.08 * math.sin(t * 2.0)) * a)
      love.graphics.setLineWidth(1)
      love.graphics.rectangle("line", x, y, w, h)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  local seal = card.seal
  if seal then
    local sc = SEAL_DOT_COLORS[seal]
    if sc then
      local dot_r = math.max(3, h * 0.07)
      local dot_x = x + w - dot_r - 2
      local dot_y = y + h - dot_r - 2
      love.graphics.setColor(0, 0, 0, 0.50 * a)
      love.graphics.circle("fill", dot_x + 1, dot_y + 1, dot_r)
      love.graphics.setColor(sc[1], sc[2], sc[3], 0.92 * a)
      love.graphics.circle("fill", dot_x, dot_y, dot_r)
      love.graphics.setColor(1, 1, 1, 0.40 * a)
      love.graphics.circle("fill", dot_x - dot_r * 0.3, dot_y - dot_r * 0.3, dot_r * 0.35)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  draw_enh_badge(card, x, y, h, a)

  if ed then
    local ed_text = (ed.negative and "NEG") or (ed.polychrome and "POLY") or (ed.holo and "HOLO") or (ed.foil and "FOIL") or nil
    if ed_text then
      local f0 = love.graphics.getFont()
      local sc = math.min(1, (w - 4) / math.max(1, f0:getWidth(ed_text)))
      local f = (sc < 1) and Assets.font_px(math.max(6, math.floor(f0:getHeight() * sc))) or f0
      local fh, tw = f:getHeight(), f:getWidth(ed_text)
      love.graphics.setColor(0, 0, 0, 0.6 * a)
      love.graphics.rectangle("fill", x + w - tw - 3, y + 2, tw + 3, fh + 2)
      love.graphics.setColor(1, 1, 1, 0.95 * a)
      if f ~= f0 then love.graphics.setFont(f) end
      love.graphics.print(ed_text, x + w - tw - 1, y + 3)
      if f ~= f0 then love.graphics.setFont(f0) end
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  if card.debuff then
    love.graphics.setColor(0.2, 0.2, 0.22, 0.5 * a)
    love.graphics.rectangle("fill", x, y, w, h)
    love.graphics.setColor(1, 0.25, 0.25, 0.9 * a)
    love.graphics.print("DB", x + 2, y + 2)
    love.graphics.setColor(1, 1, 1, 1)
  end

  return w
end

local draw_card_mini = draw_card_mini_approx

local RARITY_COLORS = {
  [1] = {0.72, 0.80, 0.88},
  [2] = {0.40, 0.92, 0.50},
  [3] = {0.45, 0.60, 1.0},
  [4] = {0.80, 0.45, 0.95},
}

local function rarity_color(card)
  if not card then return nil end
  local center = card.config and card.config.center
  if center and center.rarity then
    return RARITY_COLORS[center.rarity]
  end
  return nil
end

local ENABLE_AI_CARD_GLOW = require("core.tuning").bool("NEURO_AI_CARD_GLOW")

-- _gc carries the transform-push flag to the wrapper, which owns the matching pop
local _gc = { pushed = false }

-- caches the unsupported result: newMesh failure returns nil forever, no retry
local _ember_mesh, _ember_mesh_tried
local function ember_mesh()
  if _ember_mesh_tried then return _ember_mesh end
  _ember_mesh_tried = true
  if type(love.graphics.newMesh) ~= "function" then return nil end
  local verts = {
    { 0, 0, 0, 0, 1, 1, 1, 0.0 },
    { 1, 0, 1, 0, 1, 1, 1, 0.0 },
    { 1, 1, 1, 1, 1, 1, 1, 1.0 },
    { 0, 1, 0, 1, 1, 1, 1, 1.0 },
  }
  local ok, m = pcall(love.graphics.newMesh, verts, "fan", "static")
  if ok then _ember_mesh = m end
  return _ember_mesh
end

-- budget <=10 prims per glow: draw_px icons (60+ rects) are forbidden here
local function glow_evil(pl, a, W, H, X0, Y0, BW, BH, pulse, committed)
  local acc, ember, gold, hot, glow = pl.ACCENT, pl.D_ORANGE, pl.D_GOLD, pl.D_WHITE, pl.GLOW
  local core = committed and hot or ember
  local uu = W * 0.028
  local mr = gold[1] + (ember[1] - gold[1]) * pulse * 0.6
  local mg = gold[2] + (ember[2] - gold[2]) * pulse * 0.6
  local mb = gold[3] + (ember[3] - gold[3]) * pulse * 0.6
  love.graphics.setBlendMode("add")
  love.graphics.setLineWidth(uu * 2.4)
  love.graphics.setColor(glow[1], glow[2], glow[3], 0.12 * (0.85 + 0.2 * pulse) * a)
  love.graphics.rectangle("line", X0 - uu * 3, Y0 - uu * 3, BW + uu * 6, BH + uu * 6)
  love.graphics.setColor(glow[1], glow[2], glow[3], 0.05 * (0.85 + 0.2 * pulse) * a)
  love.graphics.rectangle("line", X0 - uu * 7, Y0 - uu * 7, BW + uu * 14, BH + uu * 14)
  do
    local fcx = X0 + BW * 0.5
    local fh2 = uu * (5 + 4 * pulse) * (committed and 1.4 or 1)
    love.graphics.setColor(mr, mg, mb, (0.30 + 0.25 * pulse) * a)
    love.graphics.polygon("fill", fcx - uu * 2.6, Y0, fcx, Y0 - fh2, fcx + uu * 2.6, Y0, fcx, Y0 + uu * 1.5)
  end
  local pool_h = H * 0.34
  local em = ember_mesh()
  if em then
    love.graphics.setColor(ember[1], ember[2], ember[3], (0.26 + 0.12 * pulse) * a)
    love.graphics.draw(em, X0, Y0 + BH - pool_h, 0, BW, pool_h)
  else
    love.graphics.setColor(ember[1], ember[2], ember[3], (0.12 + 0.07 * pulse) * a)
    love.graphics.rectangle("fill", X0, Y0 + BH - pool_h, BW, pool_h)
  end
  love.graphics.setColor(core[1], core[2], core[3], (committed and 0.46 or (0.34 + 0.18 * pulse)) * a)
  love.graphics.rectangle("fill", X0, Y0 + BH - H * 0.05, BW, H * 0.05)
  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(acc[1], acc[2], acc[3], (0.40 + 0.18 * pulse) * a)
  love.graphics.setLineWidth(W * 0.016)
  love.graphics.rectangle("line", X0, Y0, BW, BH)
  local arm = W * 0.11
  love.graphics.setColor(mr, mg, mb, (0.80 + 0.15 * pulse) * a)
  love.graphics.setLineWidth(W * 0.035)
  love.graphics.line(X0, Y0 + arm, X0, Y0, X0 + arm, Y0)
  love.graphics.line(X0 + BW - arm, Y0, X0 + BW, Y0, X0 + BW, Y0 + arm)
  love.graphics.line(X0, Y0 + BH - arm, X0, Y0 + BH, X0 + arm, Y0 + BH)
  love.graphics.line(X0 + BW - arm, Y0 + BH, X0 + BW, Y0 + BH, X0 + BW, Y0 + BH - arm)
end

local function glow_neuro(pl, a, W, H, X0, Y0, BW, BH, pulse, committed, now)
  local acc, gc = pl.ACCENT, pl.GLOW
  local sm = 0.5 + 0.5 * math.sin(now * 1.25)
  local shr = acc[1] + (gc[1] - acc[1]) * sm
  local shg = acc[2] + (gc[2] - acc[2]) * sm
  local shb = acc[3] + (gc[3] - acc[3]) * sm
  local rr = W * 0.06
  love.graphics.setColor(gc[1], gc[2], gc[3], 0.07 * a)
  love.graphics.rectangle("fill", X0, Y0, BW, BH, rr, rr)
  love.graphics.setColor(acc[1], acc[2], acc[3], 0.06 * a)
  love.graphics.rectangle("fill", X0, Y0 + BH * 0.55, BW, BH * 0.45, rr, rr)
  love.graphics.setColor(shr, shg, shb, (0.50 + 0.25 * pulse) * a)
  love.graphics.setLineWidth(W * 0.035)
  love.graphics.rectangle("line", X0, Y0, BW, BH, rr, rr)
  love.graphics.setColor(1, 1, 1, 0.10 * a)
  love.graphics.rectangle("fill", 0, Y0 + H * 0.02, W, H * 0.05)
  local bsc = committed and (1 + 0.3 * pulse) or 1
  local bx, byy = W * 0.5, Y0
  local bw2 = W * 0.13 * bsc
  love.graphics.setColor(acc[1], acc[2], acc[3], 0.95 * a)
  love.graphics.polygon("fill", bx, byy, bx - bw2, byy - bw2 * 0.7, bx - bw2, byy + bw2 * 0.7)
  love.graphics.polygon("fill", bx, byy, bx + bw2, byy - bw2 * 0.7, bx + bw2, byy + bw2 * 0.7)
  love.graphics.setColor(gc[1], gc[2], gc[3], 0.95 * a)
  love.graphics.circle("fill", bx, byy, bw2 * 0.32)
end

local function glow_hiyori(pl, a, W, H, X0, Y0, BW, BH, pulse)
  local pc, gc = pl.PRIMARY, pl.GLOW
  love.graphics.setColor(pc[1], pc[2], pc[3], (0.04 + 0.03 * pulse) * a)
  love.graphics.rectangle("fill", X0, Y0, BW, BH)
  love.graphics.setColor(pc[1], pc[2], pc[3], (0.10 + 0.08 * pulse) * a)
  love.graphics.rectangle("fill", 0, 0, W, H)
  love.graphics.setColor(gc[1], gc[2], gc[3], (0.55 + 0.35 * pulse) * a)
  love.graphics.setLineWidth(W * 0.03)
  love.graphics.rectangle("line", 0, 0, W, H)
  love.graphics.setColor(pc[1], pc[2], pc[3], (0.25 + 0.20 * pulse) * a)
  love.graphics.setLineWidth(W * 0.045)
  love.graphics.rectangle("line", X0, Y0, BW, BH)
end

-- prep_draw maps (0,0)..(W,H) onto the live card; transformPoint/origin read the wrong matrix and draw off-card
local function run_glow(self, vt, a, now)
  _gc.pushed = false
  if type(prep_draw) == "function" then
    prep_draw(self, 1, 0, nil)
    _gc.pushed = true
  else
    local tss = (G and G.TILESCALE and G.TILESIZE) and (G.TILESCALE * G.TILESIZE) or 1
    local sc = vt.scale or 1
    local cx = ((vt.x or 0) + vt.w / 2) * tss
    local cy = ((vt.y or 0) + vt.h / 2) * tss
    love.graphics.push(); _gc.pushed = true
    love.graphics.origin()
    love.graphics.translate(cx - vt.w * sc * tss / 2, cy - vt.h * sc * tss / 2)
    love.graphics.scale(sc * tss)
  end

  local pl = Palette.pal()
  local persona = Palette.persona()
  local reduced = Prims.Motion and Prims.Motion.reduced
  local W, H = vt.w, vt.h
  local pad = W * 0.05
  local X0, Y0 = -pad, -pad
  local BW, BH = W + pad * 2, H + pad * 2
  local hz = (pl.MOTION and pl.MOTION.pulse_hz) or 2.7
  local pulse = reduced and 0.5
    or (persona == "evil" and Prims.candle01(now) or (0.5 + 0.5 * math.sin(now * hz)))
  local committed = self.highlighted and a > 0.7

  if persona == "evil" then
    glow_evil(pl, a, W, H, X0, Y0, BW, BH, pulse, committed)
  elseif persona == "neuro" then
    glow_neuro(pl, a, W, H, X0, Y0, BW, BH, pulse, committed, now)
  else
    glow_hiyori(pl, a, W, H, X0, Y0, BW, BH, pulse)
  end
end

local function hook_card_draw()
  if S.neuro_card_draw_hooked then return end
  if not ENABLE_AI_CARD_GLOW then
    S.neuro_card_draw_hooked = true
    return
  end
  if not Card or not Card.draw then return end
  S.neuro_card_draw_hooked = true
  neuro_log("Card:draw overlay installed")

  local _orig_card_draw = Card.draw
  local _last_draw_err = nil
  local _last_glow_err = nil
  Card.draw = function(self, layer)
    -- do NOT drain the matrix stack here: popping mid-CardArea unbalances sibling cards
    local draw_ok, draw_err = xpcall(_orig_card_draw, debug.traceback, self, layer)
    if not draw_ok then
      local msg = tostring(draw_err)
      if msg ~= _last_draw_err then
        _last_draw_err = msg
        neuro_log("Card.draw error:", msg)
      end
      return
    end

    if layer == 'shadow' then return end
    if layer and layer ~= 'card' then return end
    if not (G and G.NEURO) then return end

    local now = (G.TIMERS and G.TIMERS.REAL) or 0
    local alpha = 0

    local ai_hl = G.NEURO.ai_highlighted and G.NEURO.ai_highlighted[self]
    if ai_hl and self.highlighted then
      alpha = 1.0
      S.card_glow_fade[self] = now + 0.6
    elseif ai_hl and not self.highlighted then
      G.NEURO.ai_highlighted[self] = nil
      local fade_until = S.card_glow_fade[self]
      if fade_until and now < fade_until then
        alpha = smoothstep01((fade_until - now) / 0.6)
      else
        S.card_glow_fade[self] = nil
        return
      end
    else
      local fade_until = S.card_glow_fade[self]
      if fade_until and now < fade_until then
        alpha = smoothstep01((fade_until - now) / 0.6)
      else
        S.card_glow_fade[self] = nil
        return
      end
    end

    local vt = self.VT
    if not vt or not vt.w or not vt.h then return end
    if vt.w <= 0 or vt.h <= 0 then return end

    -- capture + restore gfx state OUTSIDE the pcall so a throw mid-draw can't leak matrix/shader/blend into the base render
    local prev_shader = love.graphics.getShader()
    local prev_blend, prev_blend_alpha = love.graphics.getBlendMode()
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
    local _glow_ok, _glow_err = pcall(run_glow, self, vt, alpha, now)
    if _gc.pushed then pcall(love.graphics.pop) end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
    if prev_blend_alpha then
      love.graphics.setBlendMode(prev_blend or "alpha", prev_blend_alpha)
    else
      love.graphics.setBlendMode(prev_blend or "alpha")
    end
    love.graphics.setShader(prev_shader)
    if not _glow_ok then
      local gmsg = tostring(_glow_err)
      if gmsg ~= _last_glow_err then
        _last_glow_err = gmsg
        print("[neuro-game] GLOW ERROR:", gmsg)
      end
    end
  end
end

Cards.card_edition_tag = card_edition_tag
Cards.draw_animated_edition = draw_animated_edition
Cards.card_display_name = card_display_name
Cards.card_description = card_description
Cards.draw_card_mini = draw_card_mini
function Cards.reset_mini_counters()
  Cards._mini_edition_fail = 0
  Cards._mini_fallback = 0
end
Cards.rarity_color = rarity_color
Cards.hook_card_draw = hook_card_draw

return Cards
