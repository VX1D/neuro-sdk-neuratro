local Cards = {}
Cards._mini_edition_fail = 0
Cards._mini_edition_skip = 0
Cards._mini_fallback = 0
Cards._badge_icon_missing = 0

local QUAD_CACHE_MAX = 512
-- quad_bucket nests ns/prefix/x/y/px/py before the leaf record.
local QUAD_CACHE_DEPTH = 6
local _diag_logged = {}
function Cards.diag_once(key, message)
  if _diag_logged[key] then return false end
  _diag_logged[key] = true
  print("[neuro-game] " .. tostring(message))
  return true
end

local Palette = require("render.palette")
local Utils = require("util.utils")
local S = require("hud.state")
local Assets = require("hud.assets")
local Prims = require("hud.prims")
local smoothstep01 = Prims.smoothstep01

local neuro_log = Utils.neuro_log

local function usable_name(value)
  if type(value) == "table" then value = Utils.flatten_description(value) end
  if type(value) ~= "string" or value == "" or Utils.is_masked_name(value) then return nil end
  return value
end

local function card_display_name(c)
  local n = usable_name(Utils.real_name(c))
  if n then return n end
  local center = c and c.config and c.config.center or {}
  local ability = c and c.ability or {}
  n = usable_name(center.loc_txt and center.loc_txt.name)
    or usable_name(center.name)
    or usable_name(ability.name)
  if n then return n end
  if center.key then
    n = usable_name(Utils.humanize_identifier(center.key))
    if n then return n end
  end
  return "Unknown"
end

local SEAL_DOT_COLORS = {
  Red    = {0.95, 0.20, 0.20},
  Blue   = {0.20, 0.55, 0.95},
  Gold   = {0.95, 0.75, 0.10},
  Purple = {0.70, 0.25, 0.90},
}
local EDITION_BADGE_COLORS = {
  negative   = {0.62, 0.60, 0.82},
  polychrome = {0.95, 0.60, 0.85},
  holo       = {0.45, 0.72, 1.00},
  foil       = {0.78, 0.84, 0.92},
}

local SEAL_GLYPH = {
  Red    = "R",
  Blue   = "B",
  Gold   = "G",
  Purple = "P",
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
local STICKER_ORDER = { "eternal", "perishable", "rental" }

local function valid_pos(p)
  return type(p) == "table" and type(p.x) == "number" and type(p.y) == "number"
end

local function quad_bucket(ns, prefix, x, y, px, py)
  local t = S.quad_cache
  local t0 = t[ns]
  if not t0 then t0 = {}; t[ns] = t0 end
  local t1 = t0[prefix]
  if not t1 then t1 = {}; t0[prefix] = t1 end
  local t2 = t1[x]
  if not t2 then t2 = {}; t1[x] = t2 end
  local t3 = t2[y]
  if not t3 then t3 = {}; t2[y] = t3 end
  local t4 = t3[px]
  if not t4 then t4 = {}; t3[px] = t4 end
  local leaf = t4[py]
  if not leaf then
    leaf = {}
    t4[py] = leaf
    S.quad_cache_n = (S.quad_cache_n or 0) + 1
  end
  return leaf
end

local function cached_quad(ns, prefix, x, y, px, py, sx, sy, w, h, image)
  if S.quad_cache_n and S.quad_cache_n >= QUAD_CACHE_MAX then
    S.quad_cache = {}
    S.quad_cache_n = 0
  end
  local rec = quad_bucket(ns, prefix, x, y, px, py)
  if rec.img == image then return rec.quad, false end
  local ok, nq = pcall(love.graphics.newQuad, sx, sy, w, h, image:getDimensions())
  if not ok then
    Cards._mini_quad_fail = (Cards._mini_quad_fail or 0) + 1
    Cards.diag_once("quad:" .. tostring(ns) .. ":" .. tostring(prefix),
      "quad creation failed for " .. tostring(prefix))
  end
  rec.img, rec.quad = image, ok and nq or false
  return rec.quad, (not ok)
end

local function atlas_quad(atlas_key, pos)
  local atlas = G.ASSET_ATLAS and G.ASSET_ATLAS[atlas_key]
  if not atlas or not atlas.image or not valid_pos(pos) then return nil end
  local px, py = atlas.px or 71, atlas.py or 95
  local q = cached_quad("base", atlas_key, pos.x, pos.y, px, py, pos.x * px, pos.y * py, px, py, atlas.image)
  if not q then return nil end
  return atlas, q, px, py
end

local ICON_CROP = {
  seal       = { x = 14, y = 15, w = 27, h = 27 },
  eternal    = { x = 4,  y = 4,  w = 19, h = 19 },
  perishable = { x = 4,  y = 4,  w = 19, h = 19 },
  rental     = { x = 4,  y = 24, w = 19, h = 19 },
}

local function draw_cropped_quad(atlas_key, pos, crop, x, y, scale_x, scale_y, a)
  local atlas = G and G.ASSET_ATLAS and G.ASSET_ATLAS[atlas_key]
  if not atlas or not atlas.image or not valid_pos(pos) or not crop then return 0 end
  local px, py = atlas.px or 71, atlas.py or 95
  local q = cached_quad("crop", atlas_key, pos.x, pos.y, px, py,
    pos.x * px + crop.x, pos.y * py + crop.y, crop.w, crop.h, atlas.image)
  if not q then return 0 end
  love.graphics.setColor(1, 1, 1, a or 1)
  love.graphics.draw(atlas.image, q, x + crop.x * scale_x, y + crop.y * scale_y, 0, scale_x, scale_y)
  love.graphics.setColor(1, 1, 1, 1)
  return px * scale_x
end

local CLEAR_RGBA = { 0, 0, 0, 0 }
local ORIGIN_2 = { 0, 0 }
local _tex_details = { 0, 0, 0, 0 }
local _image_details = { 0, 0 }
local _send_time = { 0, 0 }

local function draw_stickers(ab, x, y, scale_x, scale_y, a)
  for i = 1, #STICKER_ORDER do
    local key = STICKER_ORDER[i]
    if ab[key] then
      draw_cropped_quad("stickers", STICKER_POS[key], ICON_CROP[key], x, y, scale_x, scale_y, a)
    end
  end
end

local function draw_atlas_quad(atlas_key, pos, x, y, scale_x, scale_y_or_a, a_param)
  local atlas, q, px = atlas_quad(atlas_key, pos)
  if not atlas then return 0 end
  local scale_y, a
  if type(scale_y_or_a) == "number" and type(a_param) == "number" then
    scale_y = scale_y_or_a
    a = a_param
  else
    scale_y = scale_x
    a = scale_y_or_a or 1
  end
  love.graphics.setColor(1, 1, 1, a)
  love.graphics.draw(atlas.image, q, x, y, 0, scale_x, scale_y)
  love.graphics.setColor(1, 1, 1, 1)
  return px * scale_x
end

local function draw_shaded_quad(atlas_key, pos, x, y, scale_x, scale_y_or_a, a_or_shader, shader_name_or_card, card_or_dissolve, dissolve_or_b1, burn1_or_b2, burn2_or_hov, hovering_param)
  local scale_y
  local a, shader_name, card, dissolve, burn1, burn2, hovering
  if type(scale_y_or_a) == "number" and (type(a_or_shader) == "number" or type(a_or_shader) == "nil") then
    scale_y = scale_y_or_a
    a = a_or_shader or 1
    shader_name = shader_name_or_card
    card = card_or_dissolve
    dissolve = dissolve_or_b1
    burn1 = burn1_or_b2
    burn2 = burn2_or_hov
    hovering = hovering_param
  else
    scale_y = scale_x
    a = scale_y_or_a
    shader_name = a_or_shader
    card = shader_name_or_card
    dissolve = card_or_dissolve
    burn1 = dissolve_or_b1
    burn2 = burn1_or_b2
    hovering = burn2_or_hov
  end
  local shader = G.SHADERS and G.SHADERS[shader_name]
  local atlas, q, px, py = atlas_quad(atlas_key, pos)
  if not shader or not atlas then return false end
  local clear = (G.C and G.C.CLEAR) or CLEAR_RGBA
  local iw, ih = atlas.image:getDimensions()
  _tex_details[1], _tex_details[2], _tex_details[3], _tex_details[4] = pos.x, pos.y, px, py
  shader:send("texture_details", _tex_details)
  -- G.SHADERS is shared with the base game, which rewrites every uniform per sprite draw, so an
  -- "already sent it" cache would serve the base game's values.
  _image_details[1], _image_details[2] = iw, ih
  shader:send("image_details", _image_details)
  shader:send("mouse_screen_pos", ORIGIN_2)
  shader:send("screen_scale", (G.TILESCALE or 3.65) * (G.TILESIZE or 20) * (G.CANV_SCALE or 1))
  shader:send("hovering", hovering or 0)
  shader:send("dissolve", dissolve or 0)
  shader:send("time", 123.33412 * (((card and card.ID or 1) / 1.14212) % 3000))
  shader:send("burn_colour_1", burn1 or clear)
  shader:send("burn_colour_2", burn2 or clear)
  shader:send("shadow", false)
  if card then
    local send = card.ARGS and card.ARGS.send_to_shader
    if not send then
      local t = Utils.now()
      _send_time[1], _send_time[2] = t / 28, t
      send = _send_time
    end
    local uniform = (SMODS and SMODS.Shaders and SMODS.Shaders[shader_name]
      and SMODS.Shaders[shader_name].original_key) or shader_name
    local send_ok = pcall(shader.send, shader, uniform, send)
    if not send_ok then
      Cards._mini_shader_fail = (Cards._mini_shader_fail or 0) + 1
      Cards.diag_once("shader_send", "shader.send failed for " .. tostring(shader_name))
    end
  end
  love.graphics.setColor(1, 1, 1, a)
  love.graphics.setShader(shader)
  love.graphics.draw(atlas.image, q, x, y, 0, scale_x, scale_y)
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
    while #name > 1 and f:getWidth(name) > maxw do
      local i = #name
      while i > 1 do
        local b = name:byte(i)
        if not b or b < 0x80 or b >= 0xC0 then break end
        i = i - 1
      end
      name = name:sub(1, i - 1)
    end
    love.graphics.setColor(0.9, 0.9, 0.9, a)
    love.graphics.print(name, x + 2, y + 2 + (h - fh - 4) * 0.5)
    love.graphics.setColor(1, 1, 1, 1)
  end
  return w, h
end

local CENTERS_SETS = { Enhanced = true, Default = true, Back = true }

local function center_atlas_key(center, fallback)
  if not center then return nil end
  return center.atlas or (CENTERS_SETS[center.set] and "centers") or center.set or fallback
end

local function resolve_card_sprite(card)
  local cfg = card and card.config
  local center = cfg and cfg.center
  local front = cfg and cfg.card
  local ak, pos, is_front
  if center and valid_pos(center.pos) then
    ak = center_atlas_key(center, "Joker")
    pos = center.pos
  elseif front and valid_pos(front.pos) then
    ak = "cards_1"
    pos = front.pos
    is_front = true
  else
    return nil
  end
  local atlas = G.ASSET_ATLAS and G.ASSET_ATLAS[ak]
  if not atlas or not atlas.image then
    return ak, pos, nil, is_front
  end
  return ak, pos, atlas, is_front, atlas.px or 71, atlas.py or 95
end

local NOMINAL_W, NOMINAL_H = 71, 95

local function display_factor(center, axis, nominal)
  if type(center) ~= "table" then return nil end
  local box = center.display_size
  local v = (type(box) == "table") and tonumber(box[axis]) or nil
  if not v then
    box = center.pixel_size
    v = (type(box) == "table") and tonumber(box[axis]) or nil
  end
  if not v or v <= 0 or v == nominal then return nil end
  return v / nominal
end

local function dims_from_sprite(card, h, px, py)
  h = h or 95
  local has_sprite = px ~= nil and py ~= nil
  px = px or 71
  py = py or 95
  local scale = h / py
  local w = math.ceil(px * scale)
  local render_h = h
  local scale_x = scale
  local scale_y = scale
  if not has_sprite then return w, render_h, scale_x, scale_y end

  local center = card and card.config and card.config.center
  local key = center and center.key
  if key == "j_half" then
    render_h = math.ceil(h / 1.7)
    scale_y = scale / 1.7
  elseif key == "j_photograph" then
    render_h = math.ceil(h / 1.2)
    scale_y = scale / 1.2
  elseif key == "j_square" then
    render_h = w
    scale_y = w / py
  elseif key == "j_wee" then
    w = math.ceil(w * 0.7)
    render_h = math.ceil(h * 0.7)
    scale_x = scale * 0.7
    scale_y = scale * 0.7
  end

  local fh = display_factor(center, "h", NOMINAL_H)
  if fh then
    render_h = math.ceil(render_h * fh)
    scale_y = scale_y * fh
  end
  local fw = display_factor(center, "w", NOMINAL_W)
  if fw then
    w = math.ceil(w * fw)
    scale_x = scale_x * fw
  end

  return w, render_h, scale_x, scale_y
end

local DIMS_CACHE = setmetatable({}, { __mode = "k" })
local DIMS_REVALIDATE_S = 0.75
local DIMS_BUCKET_MAX = 8

local function resolve_dims(card, h)
  local cfg = card and card.config
  local center = cfg and cfg.center
  local front = cfg and cfg.card
  local now = Utils.now()
  -- These are rewritten in place on the same center table, so fingerprint values, not identity.
  local ds = center and center.display_size
  local ps = center and center.pixel_size
  local dw = (ds and tonumber(ds.w)) or (ps and tonumber(ps.w)) or nil
  local dh = (ds and tonumber(ds.h)) or (ps and tonumber(ps.h)) or nil
  local dkey = center and center.key or nil
  local bucket = card ~= nil and DIMS_CACHE[card] or nil
  local entry = bucket and bucket[h]
  if entry and entry.center == center and entry.front == front
      and entry.dw == dw and entry.dh == dh and entry.dkey == dkey
      and (now - entry.at) < DIMS_REVALIDATE_S then
    return entry.ak, entry.pos, entry.atlas, entry.is_front, entry.px, entry.py,
      entry.w, entry.render_h, entry.scale_x, entry.scale_y
  end
  local ak, pos, atlas, is_front, px, py = resolve_card_sprite(card)
  local w, render_h, scale_x, scale_y = dims_from_sprite(card, h, px, py)
  if card == nil then return ak, pos, atlas, is_front, px, py, w, render_h, scale_x, scale_y end
  if not bucket then bucket = {}; DIMS_CACHE[card] = bucket end
  entry = bucket[h]
  if not entry then
    -- Flight animations sweep `h` continuously, so the per-card bucket needs a cap.
    local n = 0
    for _ in pairs(bucket) do n = n + 1 end
    if n >= DIMS_BUCKET_MAX then bucket = {}; DIMS_CACHE[card] = bucket end
    entry = {}
    bucket[h] = entry
  end
  entry.center, entry.front, entry.at = center, front, now
  entry.dw, entry.dh, entry.dkey = dw, dh, dkey
  entry.ak, entry.pos, entry.atlas, entry.is_front, entry.px, entry.py = ak, pos, atlas, is_front, px, py
  entry.w, entry.render_h, entry.scale_x, entry.scale_y = w, render_h, scale_x, scale_y
  return ak, pos, atlas, is_front, px, py, w, render_h, scale_x, scale_y
end

local function card_dimensions(card, h)
  local _, _, _, _, _, _, w, render_h, scale_x, scale_y = resolve_dims(card, h)
  return w, render_h, scale_x, scale_y
end

local function draw_debuff_overlay(x, y, w, h, a)
  love.graphics.setColor(0.2, 0.2, 0.22, 0.5 * a)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(1, 0.25, 0.25, 0.9 * a)
  local f0 = love.graphics.getFont()
  local text = "DB"
  local tw = f0:getWidth(text)
  local maxw = w * 0.45
  local scale = math.min(1, maxw / math.max(1, tw))
  local f = f0
  if scale < 1 then
    local target_px = math.max(6, math.floor(f0:getHeight() * scale))
    f = Assets.font_px(target_px)
  end
  if f ~= f0 then love.graphics.setFont(f) end
  local fh, ftw = f:getHeight(), f:getWidth(text)
  love.graphics.print(text, x + math.max(1, math.floor((w - ftw) / 2)), y + math.max(1, math.floor((h - fh) / 2)))
  if f ~= f0 then love.graphics.setFont(f0) end
  love.graphics.setColor(1, 1, 1, 1)
end

local function edition_shader(ed)
  if not ed then return nil end
  return (ed.holo and "holo") or (ed.foil and "foil") or (ed.polychrome and "polychrome") or nil
end

local function try_shaded(atlas_key, pos, x, y, sx, sy, a, shader_name, card)
  local ok, drew = pcall(draw_shaded_quad, atlas_key, pos, x, y, sx, sy, a, shader_name, card)
  return ok, (ok and drew) or false
end

local function edition_fail(key, message)
  love.graphics.setShader()
  love.graphics.setColor(1, 1, 1, 1)
  Cards._mini_edition_fail = Cards._mini_edition_fail + 1
  Cards.diag_once(key, message)
end

local function draw_playing_card_mini(card, x, y, h, a, center, front, is_stone)
  local scale = h / 95
  local w = 71 * scale
  local ed = card.edition
  local front_atlas = (G.SETTINGS and G.SETTINGS.colourblind_option) and "cards_2" or "cards_1"
  local has_face = front and valid_pos(front.pos)

  local center_ak = center_atlas_key(center, "centers")
  local center_atlas_obj = center_ak and G.ASSET_ATLAS and G.ASSET_ATLAS[center_ak]
  local center_ok = center_atlas_obj and center_atlas_obj.image ~= nil

  local front_atlas_obj = G.ASSET_ATLAS and G.ASSET_ATLAS[front_atlas]
  local front_ok = front_atlas_obj and front_atlas_obj.image ~= nil

  if (center and valid_pos(center.pos) and not center_ok) or (has_face and not front_ok) then
    return draw_mini_fallback(card, x, y, w, h, a)
  end

  local want_center = center and valid_pos(center.pos) and center_ok
  local want_front = has_face and not is_stone and front_ok

  local neg_base = false
  if ed and ed.negative then
    local c_ok, f_ok = false, false
    local ok_neg = true
    if want_center then
      ok_neg, c_ok = try_shaded(center_ak, center.pos, x, y, scale, scale, a, "negative", card)
    end
    if ok_neg and want_front then
      ok_neg, f_ok = try_shaded(front_atlas, front.pos, x, y, scale, scale, a, "negative", card)
    end
    if ok_neg then
      neg_base = (not want_center or c_ok) and (not want_front or f_ok) and (c_ok or f_ok)
    else
      edition_fail("edition_negative_base", "negative base pass failed on a playing card mini")
    end
  end

  local drew = neg_base
  if not neg_base then
    if want_center and draw_atlas_quad(center_ak, center.pos, x, y, scale, a) > 0 then
      drew = true
    end
    if want_front and draw_atlas_quad(front_atlas, front.pos, x, y, scale, a) > 0 then
      drew = true
    end
  end
  if not drew then
    return draw_mini_fallback(card, x, y, w, h, a)
  end

  if ed then
    if ed.negative then
      if want_center then
        local ok = try_shaded(center_ak, center.pos, x, y, scale, scale, a, "negative_shine", card)
        if not ok then
          edition_fail("edition_negative_shine", "negative_shine pass failed on a playing card mini")
        end
      end
    else
      local sh = edition_shader(ed)
      if sh then
        local ok = true
        if want_center then ok = try_shaded(center_ak, center.pos, x, y, scale, scale, a, sh, card) end
        if ok and want_front then ok = try_shaded(front_atlas, front.pos, x, y, scale, scale, a, sh, card) end
        if not ok then
          Cards._mini_edition_fail = Cards._mini_edition_fail + 1
          love.graphics.setShader()
          love.graphics.setColor(0.82, 0.86, 1.0, 0.18 * a)
          love.graphics.rectangle("fill", x, y, w, h)
          love.graphics.setColor(1, 1, 1, 1)
        end
      end
    end
  end

  if card.seal and SEAL_POS[card.seal] then
    draw_cropped_quad("centers", SEAL_POS[card.seal], ICON_CROP.seal, x, y, scale, scale, a)
  end

  local ab = card.ability
  if ab then draw_stickers(ab, x, y, scale, scale, a) end

  if card.debuff then
    draw_debuff_overlay(x, y, w, h, a)
  end

  return w, h
end

local function draw_card_mini_approx(card, x, y, h, a, skip_art_badge)
  a = a or 1
  if not card or not G or not G.ASSET_ATLAS then return 0, 0 end
  local ak, pos, atlas, is_front, px, py, w, render_h, scale_x, scale_y = resolve_dims(card, h)
  local center = card.config and card.config.center
  local is_stone = (center and center.key == "m_stone")
    or (card.ability and card.ability.effect == "Stone Card")
  local front = card.config and card.config.card
  local has_face = front and valid_pos(front.pos)
    and front.value ~= nil and front.suit ~= nil
  if has_face or is_stone then
    return draw_playing_card_mini(card, x, y, h, a, center, front, is_stone)
  end
  if not atlas then
    return draw_mini_fallback(card, x, y, w, render_h, a)
  end

  local q = cached_quad("base", ak, pos.x, pos.y, px, py, pos.x * px, pos.y * py, px, py, atlas.image)
  if not q then
    return draw_mini_fallback(card, x, y, w, render_h, a)
  end

  local ed = card.edition
  local shaded = false

  if ed and ed.negative then
    local ok_neg
    ok_neg, shaded = try_shaded(ak, pos, x, y, scale_x, scale_y, a, "negative", card)
    if not ok_neg then
      edition_fail("edition_negative_base", "negative base pass failed on a joker/consumable mini")
    end
  end

  if not shaded then
    love.graphics.setColor(1, 1, 1, a)
    love.graphics.draw(atlas.image, q, x, y, 0, scale_x, scale_y)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if ed then
    if ed.negative then
      if shaded then
        local ok = try_shaded(ak, pos, x, y, scale_x, scale_y, a, "negative_shine", card)
        if not ok then
          edition_fail("edition_negative_shine", "negative_shine pass failed on a joker/consumable mini")
        end
      else
        Cards._mini_edition_skip = (Cards._mini_edition_skip or 0) + 1
        Cards.diag_once("edition_shader_missing",
          "edition shader or atlas unavailable for mini, drawing overlay fallback")
      end
    else
      local sh = edition_shader(ed)
      if sh then
        local ok
        ok, shaded = try_shaded(ak, pos, x, y, scale_x, scale_y, a, sh, card)
        if not ok then
          edition_fail("edition_pass_mini", "edition shader pass failed on a joker/consumable mini")
        elseif not shaded then
          Cards._mini_edition_skip = (Cards._mini_edition_skip or 0) + 1
          Cards.diag_once("edition_shader_missing",
            "edition shader or atlas unavailable for mini, drawing overlay fallback")
        end
      end
    end
  end
  if ed and not shaded then
    local t = Utils.now()
    if ed.negative then
      love.graphics.setColor(0, 0, 0, 0.55 * a)
      love.graphics.rectangle("fill", x, y, w, render_h)
      love.graphics.setColor(1, 1, 1, 0.40 * a)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", x, y, w, render_h)
      love.graphics.setLineWidth(1)
    elseif ed.polychrome then
      local r = 0.55 + 0.45 * math.sin(t * 2.5)
      local g = 0.55 + 0.45 * math.sin(t * 2.5 + 2.094)
      local b = 0.55 + 0.45 * math.sin(t * 2.5 + 4.189)
      love.graphics.setColor(r, g, b, 0.50 * a)
      love.graphics.rectangle("fill", x, y, w, render_h)
    elseif ed.holo then
      love.graphics.setColor(0.25, 0.50, 1.0, 0.38 * a)
      love.graphics.rectangle("fill", x, y, w, render_h)
      love.graphics.setColor(0.55, 0.80, 1.0, (0.20 + 0.10 * math.sin(t * 3.0)) * a)
      love.graphics.setLineWidth(1)
      love.graphics.rectangle("line", x, y, w, render_h)
    elseif ed.foil then
      love.graphics.setColor(0.78, 0.84, 0.92, 0.38 * a)
      love.graphics.rectangle("fill", x, y, w, render_h)
      love.graphics.setColor(0.92, 0.96, 1.0, (0.20 + 0.08 * math.sin(t * 2.0)) * a)
      love.graphics.setLineWidth(1)
      love.graphics.rectangle("line", x, y, w, render_h)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  local seal = card.seal
  if seal then
    local drew_seal = false
    if SEAL_POS[seal] then
      drew_seal = draw_cropped_quad("centers", SEAL_POS[seal], ICON_CROP.seal,
        x, y, scale_x, scale_y, a) > 0
    end
    if not drew_seal then
      Cards.diag_once("seal_atlas_missing", "centers atlas unavailable, drawing the seal dot instead")
      local sc = SEAL_DOT_COLORS[seal]
      if sc then
        local dot_r = math.max(3, render_h * 0.07)
        local dot_x = x + w - dot_r - 2
        local dot_y = y + render_h - dot_r - 2
        love.graphics.setColor(0, 0, 0, 0.50 * a)
        love.graphics.circle("fill", dot_x + 1, dot_y + 1, dot_r)
        love.graphics.setColor(sc[1], sc[2], sc[3], 0.92 * a)
        love.graphics.circle("fill", dot_x, dot_y, dot_r)
        love.graphics.setColor(1, 1, 1, 0.40 * a)
        love.graphics.circle("fill", dot_x - dot_r * 0.3, dot_y - dot_r * 0.3, dot_r * 0.35)
        local g = SEAL_GLYPH[seal]
        if g then
          local f0 = love.graphics.getFont()
          local gf = Assets.font_px(math.max(5, math.floor(dot_r * 1.4)))
          local gx = dot_x - math.floor(gf:getWidth(g) / 2)
          local gy = dot_y - math.floor(gf:getHeight() / 2)
          love.graphics.setColor(0.08, 0.08, 0.10, 0.95 * a)
          if gf ~= f0 then love.graphics.setFont(gf) end
          love.graphics.print(g, gx, gy)
          if gf ~= f0 then love.graphics.setFont(f0) end
          love.graphics.setColor(1, 1, 1, 1)
        end
      end
    end
  end

  draw_enh_badge(card, x, y, render_h, a)

  if ed and not skip_art_badge and not shaded then
    local ed_text, ed_col
    if ed.negative then ed_text, ed_col = "NEG", EDITION_BADGE_COLORS.negative
    elseif ed.polychrome then ed_text, ed_col = "POLY", EDITION_BADGE_COLORS.polychrome
    elseif ed.holo then ed_text, ed_col = "HOLO", EDITION_BADGE_COLORS.holo
    elseif ed.foil then ed_text, ed_col = "FOIL", EDITION_BADGE_COLORS.foil end
    if ed_text then
      local f0 = love.graphics.getFont()
      local sc = math.min(1, (w - 4) / math.max(1, f0:getWidth(ed_text)))
      local f = (sc < 1) and Assets.font_px(math.max(6, math.floor(f0:getHeight() * sc))) or f0
      local fh, tw = f:getHeight(), f:getWidth(ed_text)
      love.graphics.setColor(0, 0, 0, 0.6 * a)
      love.graphics.rectangle("fill", x + w - tw - 3, y + 2, tw + 3, fh + 2)
      love.graphics.setColor(ed_col[1], ed_col[2], ed_col[3], 0.97 * a)
      if f ~= f0 then love.graphics.setFont(f) end
      love.graphics.print(ed_text, x + w - tw - 1, y + 3)
      if f ~= f0 then love.graphics.setFont(f0) end
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  local ab = card.ability
  if ab and (ab.eternal or ab.perishable or ab.rental) then
    local st_atlas = G.ASSET_ATLAS and G.ASSET_ATLAS.stickers
    if st_atlas and st_atlas.image then
      local spx, spy = st_atlas.px or 71, st_atlas.py or 95
      draw_stickers(ab, x, y, w / spx, render_h / spy, a)
    else
      Cards._mini_sticker_fail = (Cards._mini_sticker_fail or 0) + 1
    end
  end

  if not is_front and center and valid_pos(center.soul_pos) then
    local sq = cached_quad("soul", ak, center.soul_pos.x, center.soul_pos.y, px, py,
      center.soul_pos.x * px, center.soul_pos.y * py, px, py, atlas.image)
    if sq then
      love.graphics.setColor(1, 1, 1, 0.85 * a)
      love.graphics.draw(atlas.image, sq, x, y, 0, scale_x, scale_y)
    end
  end

  if card.debuff then
    draw_debuff_overlay(x, y, w, render_h, a)
  end

  return w, render_h
end

local draw_card_mini = draw_card_mini_approx

local RARITY_COLORS = {
  [1] = {0.72, 0.80, 0.88},
  [2] = {0.40, 0.92, 0.50},
  [3] = {0.45, 0.60, 1.0},
  [4] = {0.80, 0.45, 0.95},
}

-- Mirrors the engine's own normalization (dump functions/common_events.lua:2248, SMODS
-- game_object.lua:1330-1332): a modded joker's rarity can be the string key ("Legendary") rather
-- than the vanilla-assigned number.
local RARITY_TIER = { Common = 1, Uncommon = 2, Rare = 3, Legendary = 4 }
local function rarity_tier(rarity)
  if type(rarity) == "string" then return RARITY_TIER[rarity] or tonumber(rarity) end
  return tonumber(rarity)
end

local function rarity_color(card)
  if not card then return nil end
  local center = card.config and card.config.center
  if center and center.rarity then
    return RARITY_COLORS[rarity_tier(center.rarity)]
  end
  return nil
end

local ENABLE_AI_CARD_GLOW = require("core.config").bool("NEURO_AI_CARD_GLOW")

local _gc = { pushed = false }

local VFADE_SLICES = 12
local _vfade_mesh, _vfade_tried

local function vfade_mesh()
  if _vfade_tried then return _vfade_mesh end
  _vfade_tried = true
  if type(love.graphics.newMesh) ~= "function" then return nil end
  local verts = {
    { 0, 0, 0, 0, 1, 1, 1, 0.0 },
    { 1, 0, 1, 0, 1, 1, 1, 0.0 },
    { 1, 1, 1, 1, 1, 1, 1, 1.0 },
    { 0, 1, 0, 1, 1, 1, 1, 1.0 },
  }
  local ok, m = pcall(function()
    local mm = love.graphics.newMesh(verts, "fan", "static")
    if not mm or type(mm.getVertexCount) ~= "function" then return nil end
    if mm:getVertexCount() ~= #verts then return nil end
    return mm
  end)
  _vfade_mesh = ok and m or nil
  if not _vfade_mesh then
    Cards._mini_mesh_fail = (Cards._mini_mesh_fail or 0) + 1
    Cards.diag_once("mesh", "mesh creation failed")
  end
  return _vfade_mesh
end

local function fill_vfade(x, y, w, h, r, g, b, a)
  local m = vfade_mesh()
  if m then
    love.graphics.setColor(r, g, b, a)
    love.graphics.draw(m, x, y, 0, w, h)
    return
  end
  local sh = h / VFADE_SLICES
  for i = 1, VFADE_SLICES do
    love.graphics.setColor(r, g, b, a * i / VFADE_SLICES)
    love.graphics.rectangle("fill", x, y + (i - 1) * sh, w, sh)
  end
end

local EVIL_SCRIM = { { 0.0, 1.0, 0.2301 }, { 1.0, 2.5, 0.1446 }, { 2.5, 4.0, 0.0600 } }

local EVIL_A = {
  wash = 0.04,
  wash_commit = 0.05,
  pool = 0.05,
  pool_commit = 0.05,
  border = 0.36,
  border_commit = 0.08,
  border_pulse = 0.06,
  arms = 0.40,
  arms_commit = 0.20,
  arms_pulse = 0.08,
  mark = 0.13,
  mark_commit = 0.36,
  mark_core_commit = 0.22,
  bar_commit = 0.40,
}

local SHOP_ATTACK_GAIN = 2.2 -- shop hover alpha attack gain

local function shop_attack01(a, gain)
  return Prims.ease_out_cubic01(math.min(1, a * (gain or SHOP_ATTACK_GAIN)))
end

local ATTACK_GAIN_MAX = 8

local function attack_gain(lift01)
  if not lift01 or lift01 <= 0 then return SHOP_ATTACK_GAIN end
  local at_lift = smoothstep01(lift01)
  if at_lift <= 0 then return ATTACK_GAIN_MAX end
  local g = 1 / at_lift
  if g < 1 then return 1 end
  if g > ATTACK_GAIN_MAX then return ATTACK_GAIN_MAX end
  return g
end

local function glow_alpha(a, attack, lift01)
  if not attack then return a end
  return shop_attack01(a, attack_gain(lift01))
end

local _glow_evil_ctx = {}

local function glow_evil_scrim(c)
  for i = 1, #EVIL_SCRIM do
    local band = EVIL_SCRIM[i]
    local thick = c.uu * (band[2] - band[1])
    local mid = c.uu * (band[1] + band[2]) * 0.5
    love.graphics.setColor(0, 0, 0, band[3] * c.a)
    love.graphics.setLineWidth(thick)
    love.graphics.rectangle("line", c.X0 - mid, c.Y0 - mid, c.BW + mid * 2, c.BH + mid * 2, c.rr + mid, c.rr + mid)
  end
  love.graphics.setColor(c.glow[1], c.glow[2], c.glow[3], (EVIL_A.wash + EVIL_A.wash_commit * c.commit01) * c.a)
  love.graphics.rectangle("fill", c.X0, c.Y0, c.BW, c.BH, c.rr, c.rr)
end

local function glow_evil_pool(c)
  local pool_h = c.H * 0.34
  fill_vfade(c.X0, c.Y0 + c.BH - pool_h, c.BW, pool_h, c.ember[1], c.ember[2], c.ember[3],
    (EVIL_A.pool + EVIL_A.pool_commit * c.commit01) * c.a)
  if c.commit01 > 0 then
    local bar_h = c.H * 0.05
    local br = c.ember[1] + (c.hot[1] - c.ember[1]) * c.commit01
    local bg = c.ember[2] + (c.hot[2] - c.ember[2]) * c.commit01
    local bb = c.ember[3] + (c.hot[3] - c.ember[3]) * c.commit01
    love.graphics.setColor(br, bg, bb, EVIL_A.bar_commit * c.commit01 * c.a)
    love.graphics.rectangle("fill", c.X0, c.Y0 + c.BH - bar_h, c.BW, bar_h)
  end
  local by = c.Y0 + c.BH - c.uu * 1.5
  Prims.ember_bloom(c.X0 + c.BW * 0.30, by, c.uu * 3.5, c.uu * 0.75, (c.now * 0.45) % 1, c.gold, c.a)
  Prims.ember_bloom(c.X0 + c.BW * 0.72, by, c.uu * 3.5, c.uu * 0.75, (c.now * 0.45 + 0.53) % 1, c.gold, c.a)
end

local function glow_evil_border(c)
  local mr = c.gold[1] + (c.ember[1] - c.gold[1]) * c.pulse * 0.6
  local mg = c.gold[2] + (c.ember[2] - c.gold[2]) * c.pulse * 0.6
  local mb = c.gold[3] + (c.ember[3] - c.gold[3]) * c.pulse * 0.6
  love.graphics.setColor(mr, mg, mb,
    (EVIL_A.border + EVIL_A.border_commit * c.commit01 + EVIL_A.border_pulse * c.pulse) * c.a)
  love.graphics.setLineWidth(c.W * 0.030)
  love.graphics.rectangle("line", c.X0, c.Y0, c.BW, c.BH)
  local arm = c.W * 0.11
  love.graphics.setColor(c.gold[1], c.gold[2], c.gold[3],
    (EVIL_A.arms + EVIL_A.arms_commit * c.commit01 + EVIL_A.arms_pulse * c.pulse) * c.a)
  love.graphics.setLineWidth(c.W * 0.028)
  love.graphics.line(c.X0, c.Y0 + arm, c.X0, c.Y0, c.X0 + arm, c.Y0)
  love.graphics.line(c.X0 + c.BW - arm, c.Y0, c.X0 + c.BW, c.Y0, c.X0 + c.BW, c.Y0 + arm)
  love.graphics.line(c.X0, c.Y0 + c.BH - arm, c.X0, c.Y0 + c.BH, c.X0 + arm, c.Y0 + c.BH)
  love.graphics.line(c.X0 + c.BW - arm, c.Y0 + c.BH, c.X0 + c.BW, c.Y0 + c.BH, c.X0 + c.BW, c.Y0 + c.BH - arm)
end

local function glow_evil_mark(c)
  local bsc = 0.72 + 0.28 * c.commit01
  local mx = c.W * 0.5
  local mw2 = c.W * 0.065 * bsc
  local mup = c.W * 0.18 * bsc * 0.82 * (1 + 0.4 * c.commit01)
  local mdn = c.W * 0.18 * bsc * 0.18
  love.graphics.setColor(c.gold[1], c.gold[2], c.gold[3], (EVIL_A.mark + EVIL_A.mark_commit * c.commit01) * c.a)
  love.graphics.polygon("fill", mx - mw2, c.Y0, mx, c.Y0 - mup, mx + mw2, c.Y0, mx, c.Y0 + mdn)
  love.graphics.setColor(c.hot[1], c.hot[2], c.hot[3], EVIL_A.mark_core_commit * c.commit01 * c.a)
  love.graphics.polygon("fill", mx - mw2 * 0.46, c.Y0, mx, c.Y0 - mup * 0.52, mx + mw2 * 0.46, c.Y0, mx, c.Y0 + mdn * 0.53)
end

local GLOW_EVIL_LAYERS = {
  { mode = "alpha", fn = glow_evil_scrim },
  { mode = "add",   fn = glow_evil_pool },
  { mode = "alpha", fn = glow_evil_border },
  { mode = "add",   fn = glow_evil_mark },
}

local function glow_evil(pl, a, W, H, X0, Y0, BW, BH, pulse, commit01, now)
  local ember, gold, hot, glow = pl.D_ORANGE, pl.D_GOLD, pl.D_WHITE, pl.GLOW
  local uu = W * 0.028
  local rr = W * 0.06

  local c = _glow_evil_ctx
  c.ember, c.gold, c.hot, c.glow = ember, gold, hot, glow
  c.uu, c.rr, c.a, c.W, c.H, c.X0, c.Y0, c.BW, c.BH = uu, rr, a, W, H, X0, Y0, BW, BH
  c.pulse, c.commit01, c.now = pulse, commit01, now

  for i = 1, 4 do
    local L = GLOW_EVIL_LAYERS[i]
    love.graphics.setBlendMode(L.mode)
    L.fn(c)
  end

  love.graphics.setBlendMode("alpha")
end

local function glow_neuro(pl, a, W, H, X0, Y0, BW, BH, pulse, commit01, now)
  local acc, gc = pl.ACCENT, pl.GLOW
  local sm = 0.5 + 0.5 * math.sin(now * 1.25)
  local shr = acc[1] + (gc[1] - acc[1]) * sm
  local shg = acc[2] + (gc[2] - acc[2]) * sm
  local shb = acc[3] + (gc[3] - acc[3]) * sm
  local rr = W * 0.06
  love.graphics.setColor(gc[1], gc[2], gc[3], (0.05 + 0.05 * commit01) * a)
  love.graphics.rectangle("fill", X0, Y0, BW, BH, rr, rr)
  fill_vfade(0, H * 0.55, W, H * 0.45, acc[1], acc[2], acc[3], (0.04 + 0.05 * commit01) * a)
  love.graphics.setColor(shr, shg, shb, (0.38 + 0.10 * commit01 + 0.14 * pulse) * a)
  love.graphics.setLineWidth(W * 0.030)
  love.graphics.rectangle("line", X0, Y0, BW, BH, rr, rr)
  love.graphics.setColor(1, 1, 1, 0.10 * a)
  love.graphics.rectangle("fill", 0, Y0 + H * 0.02, W, H * 0.05)
  local bsc = 0.72 + 0.28 * commit01
  local mark_a = (0.30 + 0.65 * commit01) * a
  local bx, byy = W * 0.5, Y0
  local bw2 = W * 0.13 * bsc
  love.graphics.setColor(acc[1], acc[2], acc[3], mark_a)
  love.graphics.polygon("fill", bx, byy, bx - bw2, byy - bw2 * 0.7, bx - bw2, byy + bw2 * 0.7)
  love.graphics.polygon("fill", bx, byy, bx + bw2, byy - bw2 * 0.7, bx + bw2, byy + bw2 * 0.7)
  love.graphics.setColor(gc[1], gc[2], gc[3], mark_a)
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

local GLOW_PAINTERS = {
  evil = glow_evil,
  neuro = glow_neuro,
  hiyori = glow_hiyori,
}

local GS_MIN, GS_MAX = 0.5, 4
local EVIL_TEMPO_MIN, EVIL_TEMPO_MAX = 0.75, 2.0

local function evil_tempo()
  local gs = tonumber(G and G.SETTINGS and G.SETTINGS.GAMESPEED) or 1
  if gs < GS_MIN then gs = GS_MIN elseif gs > GS_MAX then gs = GS_MAX end
  if gs < EVIL_TEMPO_MIN then return EVIL_TEMPO_MIN end
  if gs > EVIL_TEMPO_MAX then return EVIL_TEMPO_MAX end
  return gs
end

local function run_glow(self, vt, a, commit01, now, attack, lift01)
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

  local pl = Palette.displayed_pal()
  local persona = Palette.displayed_persona()
  local W, H = vt.w, vt.h
  local pad = W * 0.05
  local X0, Y0 = -pad, -pad
  local BW, BH = W + pad * 2, H + pad * 2
  local hz = (pl.MOTION and pl.MOTION.pulse_hz) or 2.7
  a = glow_alpha(a, attack, lift01)
  local raw_pulse
  if persona == "evil" then
    local tempo = evil_tempo()
    local breath = 0.5 + 0.5 * math.sin(now * 1.2 * tempo)
    raw_pulse = breath * 0.72 + Prims.candle01(now * tempo) * 0.28
  else
    raw_pulse = 0.5 + 0.5 * math.sin(now * hz)
  end
  local pulse = 0.5 + (raw_pulse - 0.5) * a

  local paint = GLOW_PAINTERS[persona] or GLOW_PAINTERS.hiyori
  paint(pl, a, W, H, X0, Y0, BW, BH, pulse, commit01, now)
end

local GLOW_FALLBACK_WIN = 0.6
local GLOW_MIN_WIN = 0.05

local _Staging
local function glow_now()
  _Staging = _Staging or Utils.lazy_require("core.staging")
  return _Staging and _Staging.glow_now() or Utils.now()
end

local function glow_window_valid(win, now)
  if type(win) ~= "table" then return false end
  local t0 = tonumber(win.t0)
  local t1 = tonumber(win.t1)
  if not t0 or not t1 then return false end
  if (t1 - t0) <= GLOW_MIN_WIN then return false end
  return now >= t0
end

local function glow_step(now, lv, dt, active, win)
  if dt < 0 then dt = 0 elseif dt > 0.05 then dt = 0.05 end
  if active and glow_window_valid(win, now) then
    local pos = (now - win.t0) / (win.t1 - win.t0)
    if pos > 1 then pos = 1 end
    if pos > lv then lv = pos end
  else
    local target = active and 1 or 0
    local stepv = dt / GLOW_FALLBACK_WIN
    if lv < target then lv = math.min(target, lv + stepv)
    elseif lv > target then lv = math.max(target, lv - stepv) end
  end
  return lv, smoothstep01(lv), smoothstep01((lv - 0.35) / 0.65)
end

local _installed_card_draw = nil
local function hook_card_draw()
  if S.neuro_card_draw_hooked then return end
  if not ENABLE_AI_CARD_GLOW then
    S.neuro_card_draw_hooked = true
    return
  end
  if not Card or not Card.draw then return end
  if Card.draw == _installed_card_draw then
    -- The wrapper is still installed; re-wrapping would stack another xpcall layer per card draw.
    S.neuro_card_draw_hooked = true
    return
  end
  S.neuro_card_draw_hooked = true
  neuro_log("Card:draw overlay installed")

  local _orig_card_draw = Card.draw
  local _last_draw_err = nil
  local _last_glow_err = nil
  Card.draw = function(self, layer)
    local draw_ok, draw_err = xpcall(_orig_card_draw, debug.traceback, self, layer)
    if not draw_ok then
      local drain = G and G.NEURO and G.NEURO.drain_gfx_leak
      if type(drain) == "function" then pcall(drain) end
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

    local now = glow_now()

    local ai_hl  = G.NEURO.ai_highlighted and G.NEURO.ai_highlighted[self]
    if ai_hl and not self.highlighted then
      G.NEURO.ai_highlighted[self] = nil
      ai_hl = nil
    end
    local hl_active = ai_hl and self.highlighted and true or false
    local win = G.NEURO.ai_glow and G.NEURO.ai_glow[self]
    if win and not glow_window_valid(win, now) then win = nil end
    if win and now >= win.t1 and not hl_active then
      G.NEURO.ai_glow[self] = nil
      win = nil
    end
    local active = hl_active or (win ~= nil and now < win.t1)

    local last = S.card_glow_t[self]
    local dt = last and (now - last) or 0
    local lv = S.card_glow_lv[self] or 0
    local alpha, commit01
    lv, alpha, commit01 = glow_step(now, lv, dt, active, win)

    if lv <= 0 and not active then
      S.card_glow_lv[self] = nil
      S.card_glow_t[self]  = nil
      return
    end
    S.card_glow_lv[self] = lv
    S.card_glow_t[self]  = now

    local vt = self.VT
    if not vt or not vt.w or not vt.h then return end
    if vt.w <= 0 or vt.h <= 0 then return end

    local prev_shader = love.graphics.getShader()
    local prev_blend, prev_blend_alpha = love.graphics.getBlendMode()
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
    local _glow_ok, _glow_err = pcall(run_glow, self, vt, alpha, commit01, now, win and win.attack, win and win.lift01)
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
  _installed_card_draw = Card.draw
end

local function card_sprite(card)
  if not card or not G or not G.ASSET_ATLAS then return nil end
  local ak, pos, atlas = resolve_card_sprite(card)
  if not atlas then return nil end
  return ak, pos
end

local MINI_SETS = { Default = true, Enhanced = true, Back = true }

local function art_prefers_mini(card)
  local cfg = card and card.config
  if cfg and cfg.card and (cfg.card.pos or cfg.card.suit) then return true end
  local center = cfg and cfg.center
  return (center and MINI_SETS[center.set]) or false
end

local function draw_sprite_shaded(ak, pos, x, y, scale_x, scale_y, a, dissolve, burn1, burn2, hovering)
  if not (G.ASSET_ATLAS and ak and pos and scale_x and scale_y) then return false end
  local atlas = G.ASSET_ATLAS[ak]
  if not atlas or not atlas.image then return false end
  if not (G.SHADERS and G.SHADERS.dissolve) then
    local d = tonumber(dissolve) or 0
    if d > 0 then a = (a or 1) * math.max(0, 1 - d) end
    return draw_atlas_quad(ak, pos, x, y, scale_x, scale_y, a) > 0
  end
  return draw_shaded_quad(ak, pos, x, y, scale_x, scale_y, a, "dissolve", nil, dissolve, burn1, burn2, hovering)
end

Cards.card_sprite = card_sprite
Cards.art_prefers_mini = art_prefers_mini
Cards.card_dimensions = card_dimensions
Cards.draw_sprite_shaded = draw_sprite_shaded
Cards.card_display_name = card_display_name
Cards.card_description = Utils.card_description
Cards.draw_card_mini = draw_card_mini
Cards.draw_mini_fallback = draw_mini_fallback
-- Only the explicit teardowns free quads: the overflow flush in cached_quad can fire while a
-- caller still holds a quad from earlier in the same frame.
function Cards.release_quad_cache(t, depth)
  depth = depth or QUAD_CACHE_DEPTH
  if type(t) ~= "table" then return end
  if depth == 0 then
    local q = t.quad
    if q and q.release then pcall(q.release, q) end
    return
  end
  for _, sub in pairs(t) do Cards.release_quad_cache(sub, depth - 1) end
end

function Cards.clear_quad_cache()
  Cards.release_quad_cache(S.quad_cache)
  S.quad_cache = {}
  S.quad_cache_n = 0
end
function Cards.reset_mini_counters()
  Cards.clear_quad_cache()
  Cards._mini_edition_fail = 0
  Cards._mini_edition_skip = 0
  Cards._mini_fallback = 0
  Cards._badge_icon_missing = 0
  Cards._mini_sticker_fail = 0
  Cards._mini_quad_fail = 0
  Cards._mini_shader_fail = 0
  Cards._mini_mesh_fail = 0
  Cards._pack_mini_fail = 0
end
Cards.rarity_color = rarity_color
Cards.icon_crop = ICON_CROP
Cards.seal_pos = SEAL_POS
Cards.sticker_pos = STICKER_POS
Cards.seal_glyphs = SEAL_GLYPH
Cards.seal_dot_colors = SEAL_DOT_COLORS
Cards.hook_card_draw = hook_card_draw
Cards.glow_painters = GLOW_PAINTERS
if _G.NEURO_TEST then
  Cards.glow_step = glow_step
  Cards.glow_window_valid = glow_window_valid
  Cards.glow_alpha = glow_alpha
  Cards.run_glow = run_glow
  Cards.shop_attack01 = shop_attack01
end
Cards.shop_attack_gain = SHOP_ATTACK_GAIN
Cards.evil_alphas = EVIL_A
Cards.evil_scrim = EVIL_SCRIM

return Cards
