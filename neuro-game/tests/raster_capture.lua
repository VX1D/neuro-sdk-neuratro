
local M = {}

M.DRIVER = "dev_scenario -> hud_overlay.draw_indicator (real love.draw path)"
M.SYNTHETIC = false

local rec = { ops = {}, enabled = true, n_suppressed = 0 }
M.rec = rec

local col, line_w, blend = { 1, 1, 1, 1 }, 1, "alpha"
local scissor = nil
local xf = { tx = 0, ty = 0, sx = 1, sy = 1 }
local xf_stack = {}

local canvas_target = nil

local function emit(s)
  local t = canvas_target
  if t then t.ops[#t.ops + 1] = s; return end
  rec.ops[#rec.ops + 1] = s
end

local function mx(x) return xf.tx + (tonumber(x) or 0) * xf.sx end
local function my(y) return xf.ty + (tonumber(y) or 0) * xf.sy end
local function mw(w) return (tonumber(w) or 0) * xf.sx end
local function mh(h) return (tonumber(h) or 0) * xf.sy end

local function n2(v) return string.format("%.2f", tonumber(v) or 0) end

local function c()
  return string.format("%.3f %.3f %.3f %.3f %s", col[1] or 1, col[2] or 1, col[3] or 1,
    col[4] or 1, blend)
end

local function tok(s)
  return (tostring(s):gsub("[%%%s%c]", function(ch) return string.format("%%%02X", ch:byte()) end))
end

function rec.reset()
  rec.ops = {}
  col, line_w, blend, scissor = { 1, 1, 1, 1 }, 1, "alpha", nil
  xf = { tx = 0, ty = 0, sx = 1, sy = 1 }
  xf_stack = {}
end

function rec.take()
  local out = rec.ops
  rec.ops = {}
  return out
end

local FONT_W_RATIO, FONT_H_RATIO = 0.5, 1.15
local _fonts = {}
local function mkfont(px)
  px = math.max(1, math.floor(tonumber(px) or 12))
  local f = _fonts[px]
  if f then return f end
  f = { px = px }
  function f:getWidth(s) return math.floor(FONT_W_RATIO * px * #tostring(s or "") + 0.5) end
  function f:getHeight() return math.floor(FONT_H_RATIO * px + 0.5) end
  function f:getAscent() return math.floor(0.8 * px + 0.5) end
  function f:getDescent() return -math.floor(0.2 * px + 0.5) end
  function f:getLineHeight() return 1 end
  function f:setFilter() end
  function f:getWrap(s, limit)
    s = tostring(s or "")
    local per = math.max(1, math.floor(limit / math.max(1, FONT_W_RATIO * px)))
    local lines, cur = {}, ""
    for word in s:gmatch("%S+") do
      local cand = (cur == "") and word or (cur .. " " .. word)
      if #cand <= per then cur = cand else lines[#lines + 1] = cur; cur = word end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    if #lines == 0 then lines = { "" } end
    return limit, lines
  end
  _fonts[px] = f
  return f
end
M.mkfont = mkfont

local SIZE = { w = 1280, h = 720 }
M.SIZE = SIZE

local function noop() end

local mesh_capture = false
local text_capture = false
local canvas_capture = false

local function colored_text_parts(value, font, x, y)
  local out, cx = {}, tonumber(x) or 0
  local cr, cg, cb, ca = 1, 1, 1, 1
  if type(value) ~= "table" then value = { tostring(value or "") } end
  for i = 1, #value do
    local part = value[i]
    if type(part) == "table" then
      cr, cg, cb, ca = part[1] or 1, part[2] or 1, part[3] or 1, part[4] or 1
    elseif part ~= nil then
      local s = tostring(part)
      out[#out + 1] = { text = s, x = cx, y = tonumber(y) or 0, r = cr, g = cg, b = cb, a = ca }
      cx = cx + font:getWidth(s)
    end
  end
  return out
end

local function new_text(font, value)
  if not text_capture then return nil end
  local text = { __raster_text = true, font = font, adds = {} }
  function text:add(payload, x, y)
    local parts = colored_text_parts(payload, self.font, x, y)
    for i = 1, #parts do self.adds[#self.adds + 1] = parts[i] end
    return #self.adds
  end
  function text:clear() self.adds = {} end
  function text:getFont() return self.font end
  if value ~= nil then text:add(value, 0, 0) end
  return text
end

local function new_mesh(vertices, mode, usage)
  if not mesh_capture then
    return setmetatable({}, { __index = function() return noop end })
  end
  local mesh = {
    __raster_mesh = true,
    vertices = vertices,
    mode = mode,
    usage = usage,
  }
  function mesh:setVertexMap(indices) self.vertex_map = indices end
  function mesh:getVertexCount() return #self.vertices end
  return mesh
end

local IMG = {
  getWidth = function() return 71 end, getHeight = function() return 95 end,
  getDimensions = function() return 71, 95 end, setFilter = noop, setWrap = noop,
}
M.IMG = IMG

local cur_font = mkfont(14)

local gfx
gfx = setmetatable({
  getWidth = function() return SIZE.w end,
  getHeight = function() return SIZE.h end,
  getDimensions = function() return SIZE.w, SIZE.h end,

  newFont = function(a, b) return mkfont(tonumber(b) or tonumber(a) or 12) end,
  setFont = function(f) if f then cur_font = f end end,
  getFont = function() return cur_font end,

  newImage = function() return IMG end,
  newQuad = function(x, y, w, h) return { x = x or 0, y = y or 0, w = w or 71, h = h or 95,
    getViewport = function(self) return self.x, self.y, self.w, self.h end,
    setViewport = function(self, vx, vy, vw, vh) self.x, self.y, self.w, self.h = vx, vy, vw, vh end } end,
  newMesh = new_mesh,
  newText = new_text,
  newCanvas = function(w, h)
    if not canvas_capture then return nil end
    local canvas = { __raster_canvas = true, w = tonumber(w) or SIZE.w, h = tonumber(h) or SIZE.h,
      ops = {} }
    function canvas:getWidth() return self.w end
    function canvas:getHeight() return self.h end
    function canvas:getDimensions() return self.w, self.h end
    function canvas:release() self.ops = {} end
    return canvas
  end,

  getShader = function() return nil end,
  setShader = noop,
  getBlendMode = function() return blend, "alphamultiply" end,
  setBlendMode = function(m) blend = m or "alpha" end,

  setColor = function(r, g, b, a)
    if type(r) == "table" then col = { r[1], r[2], r[3], r[4] or (g or 1) }
    else col = { r or 1, g or 1, b or 1, a or 1 } end
  end,
  getColor = function() return col[1], col[2], col[3], col[4] end,
  setLineWidth = function(w) line_w = tonumber(w) or 1 end,
  getLineWidth = function() return line_w end,
  setLineStyle = noop, setLineJoin = noop,

  push = function(mode)
    xf_stack[#xf_stack + 1] = {
      tx = xf.tx, ty = xf.ty, sx = xf.sx, sy = xf.sy,
      all = (mode == "all") and { col = { col[1], col[2], col[3], col[4] }, lw = line_w,
        blend = blend, font = cur_font,
        sc = scissor and { scissor[1], scissor[2], scissor[3], scissor[4] } or false } or nil,
    }
  end,
  pop = function()
    local s = table.remove(xf_stack)
    if not s then return end
    xf.tx, xf.ty, xf.sx, xf.sy = s.tx, s.ty, s.sx, s.sy
    if s.all then
      col, line_w, blend, cur_font = s.all.col, s.all.lw, s.all.blend, s.all.font
      scissor = s.all.sc or nil
    end
  end,
  origin = function() xf.tx, xf.ty, xf.sx, xf.sy = 0, 0, 1, 1 end,
  transformPoint = function(x, y) return mx(x), my(y) end,
  translate = function(dx, dy)
    xf.tx = xf.tx + (tonumber(dx) or 0) * xf.sx
    xf.ty = xf.ty + (tonumber(dy) or 0) * xf.sy
  end,
  scale = function(sx, sy)
    sx = tonumber(sx) or 1
    xf.sx, xf.sy = xf.sx * sx, xf.sy * (tonumber(sy) or sx)
  end,
  rotate = noop,
  shear = noop,

  setScissor = function(x, y, w, h)
    if x == nil then
      scissor = nil
      if not rec.enabled then rec.n_suppressed = rec.n_suppressed + 1; return end
      emit("S off")
    else
      scissor = { mx(x), my(y), mw(w), mh(h) }
      if not rec.enabled then rec.n_suppressed = rec.n_suppressed + 1; return end
      emit(string.format("S %s %s %s %s", n2(scissor[1]), n2(scissor[2]), n2(scissor[3]),
        n2(scissor[4])))
    end
  end,
  intersectScissor = function(x, y, w, h)
    local nx, ny, nw, nh = mx(x), my(y), mw(w), mh(h)
    if scissor then
      local l = math.max(scissor[1], nx)
      local t = math.max(scissor[2], ny)
      local r = math.min(scissor[1] + scissor[3], nx + nw)
      local b = math.min(scissor[2] + scissor[4], ny + nh)
      scissor = { l, t, math.max(0, r - l), math.max(0, b - t) }
    else
      scissor = { nx, ny, nw, nh }
    end
    if not rec.enabled then rec.n_suppressed = rec.n_suppressed + 1; return end
    emit(string.format("S %s %s %s %s", n2(scissor[1]), n2(scissor[2]), n2(scissor[3]),
      n2(scissor[4])))
  end,
  getScissor = function()
    if not scissor then return nil end
    return scissor[1], scissor[2], scissor[3], scissor[4]
  end,

  rectangle = function(mode, x, y, w, h, rx, ry)
    if not rec.enabled then rec.n_suppressed = rec.n_suppressed + 1; return end
    emit(string.format("R %s %s %s %s %s %s %s %s", mode or "fill", c(), n2(mx(x)), n2(my(y)),
      n2(mw(w)), n2(mh(h)), n2((tonumber(rx) or 0) * xf.sx), n2(line_w)))
  end,
  circle = function(mode, x, y, r)
    if not rec.enabled then rec.n_suppressed = rec.n_suppressed + 1; return end
    emit(string.format("C %s %s %s %s %s %s", mode or "fill", c(), n2(mx(x)), n2(my(y)),
      n2((tonumber(r) or 0) * xf.sx), n2(line_w)))
  end,
  ellipse = function(mode, x, y, rx, ry)
    if not rec.enabled then rec.n_suppressed = rec.n_suppressed + 1; return end
    emit(string.format("E %s %s %s %s %s %s %s", mode or "fill", c(), n2(mx(x)), n2(my(y)),
      n2((tonumber(rx) or 0) * xf.sx), n2((tonumber(ry) or rx or 0) * xf.sy), n2(line_w)))
  end,
  arc = function(mode, a, b, cc, d, e, f)
    if not rec.enabled then rec.n_suppressed = rec.n_suppressed + 1; return end
    if type(a) == "string" then a, b, cc, d, e = b, cc, d, e, f end
    emit(string.format("A %s %s %s %s %s %s %s %s", mode or "fill", c(), n2(mx(a)), n2(my(b)),
      n2((tonumber(cc) or 0) * xf.sx), n2(d), n2(e), n2(line_w)))
  end,
  line = function(...)
    if not rec.enabled then rec.n_suppressed = rec.n_suppressed + 1; return end
    local p = { ... }
    if type(p[1]) == "table" then p = p[1] end
    local s = {}
    for i = 1, #p - 1, 2 do
      s[#s + 1] = n2(mx(p[i])); s[#s + 1] = n2(my(p[i + 1]))
    end
    emit("L " .. c() .. " " .. n2(line_w) .. " " .. table.concat(s, " "))
  end,
  polygon = function(mode, ...)
    if not rec.enabled then rec.n_suppressed = rec.n_suppressed + 1; return end
    local p = { ... }
    if type(p[1]) == "table" then p = p[1] end
    local s = {}
    for i = 1, #p - 1, 2 do
      s[#s + 1] = n2(mx(p[i])); s[#s + 1] = n2(my(p[i + 1]))
    end
    emit("P " .. (mode or "fill") .. " " .. c() .. " " .. n2(line_w) .. " " ..
      table.concat(s, " "))
  end,
  points = function(...)
    if not rec.enabled then rec.n_suppressed = rec.n_suppressed + 1; return end
    local p = { ... }
    if type(p[1]) == "table" then p = p[1] end
    local s = {}
    for i = 1, #p - 1, 2 do
      s[#s + 1] = n2(mx(p[i])); s[#s + 1] = n2(my(p[i + 1]))
    end
    emit("D " .. c() .. " " .. table.concat(s, " "))
  end,
  print = function(text, x, y)
    if not rec.enabled then rec.n_suppressed = rec.n_suppressed + 1; return end
    emit(string.format("T %s %s %s %d %s", c(), n2(mx(x)), n2(my(y)),
      math.floor((cur_font.px or 12) * xf.sy + 0.5), tok(text)))
  end,
  printf = function(text, x, y, limit, align)
    if not rec.enabled then rec.n_suppressed = rec.n_suppressed + 1; return end
    emit(string.format("T %s %s %s %d %s", c(), n2(mx(x)), n2(my(y)),
      math.floor((cur_font.px or 12) * xf.sy + 0.5), tok(text)))
  end,
  draw = function(img, quad, x, y, r, sx, sy)
    if not rec.enabled then rec.n_suppressed = rec.n_suppressed + 1; return end
    if type(img) == "table" and img.__raster_text then
      local dx, dy = tonumber(quad) or 0, tonumber(x) or 0
      local dsx, dsy = tonumber(r) or 1, tonumber(sx) or tonumber(r) or 1
      for i = 1, #img.adds do
        local add = img.adds[i]
        local rr, gg, bb, aa =
          (add.r or 1) * (col[1] or 1), (add.g or 1) * (col[2] or 1),
          (add.b or 1) * (col[3] or 1), (add.a or 1) * (col[4] or 1)
        emit(string.format("T %.3f %.3f %.3f %.3f %s %s %s %d %s",
          rr, gg, bb, aa, blend,
          n2(mx(dx + add.x * dsx)), n2(my(dy + add.y * dsy)),
          math.floor(((img.font and img.font.px) or 12) * dsy * xf.sy + 0.5), tok(add.text)))
      end
      return
    end
    if type(img) == "table" and img.__raster_canvas then
      local qx, qy, qw, qh = 0, 0, img.w, img.h
      local dx, dy, dsx, dsy = quad, x, r, sx
      if type(quad) == "table" and quad.w then
        qx, qy, qw, qh = quad.x or 0, quad.y or 0, quad.w, quad.h
        dx, dy, dsx, dsy = x, y, r, sx
      end
      dx, dy = tonumber(dx) or 0, tonumber(dy) or 0
      dsx = tonumber(dsx) or 1
      dsy = tonumber(dsy) or dsx
      emit(string.format("I %s %s %s %s %s %s %s", c(), n2(mx(dx)), n2(my(dy)),
        n2(qw * dsx * xf.sx), n2(qh * dsy * xf.sy), n2(qx), n2(qy)))
      return
    end
    if type(img) == "table" and img.__raster_mesh then
      local dx, dy, dsx, dsy = quad, x, r, sx
      emit(string.format("M %s %s %s %s %s %d %d", c(), n2(mx(dx)), n2(my(dy)),
        n2((tonumber(dsx) or 1) * xf.sx), n2((tonumber(dsy) or tonumber(dsx) or 1) * xf.sy),
        img:getVertexCount(), #(img.vertex_map or {})))
      return
    end
    local qx, qy, qw, qh = 0, 0, 71, 95
    if type(quad) == "table" and quad.w then
      qx, qy, qw, qh = quad.x or 0, quad.y or 0, quad.w, quad.h
    elseif type(quad) ~= "table" then
      x, y, r, sx, sy = quad, x, y, r, sx
      if type(img) == "table" and img.getDimensions then qw, qh = img:getDimensions() end
    end
    emit(string.format("I %s %s %s %s %s %s %s", c(), n2(mx(x)), n2(my(y)),
      n2(qw * (tonumber(sx) or 1) * xf.sx), n2(qh * (tonumber(sy) or tonumber(sx) or 1) * xf.sy),
      n2(qx), n2(qy)))
  end,
  setCanvas = function(canvas)
    if not canvas_capture then return end
    if type(canvas) == "table" and canvas.__raster_canvas then canvas.ops = {}; canvas_target = canvas
    else canvas_target = nil end
  end,
  getCanvas = function() return canvas_target end,
  clear = noop, present = noop, stencil = noop, setStencilTest = noop,
  captureScreenshot = noop, setDefaultFilter = noop, applyTransform = noop, replaceTransform = noop,
}, { __index = function() return noop end })

M.gfx = gfx

local function stub_ns()
  return setmetatable({}, { __index = function() return noop end })
end

local function install_globals()
  rawset(_G, "NEURO_TEST", true)

  _G.love = setmetatable({
    graphics = gfx,
    timer = { getTime = function() return ((G and G.TIMERS and G.TIMERS.REAL) or 0) + 5000 end,
      getFPS = function() return 144 end, getDelta = function() return 1 / 60 end,
      getAverageDelta = function() return 1 / 60 end, sleep = noop, step = noop },
    math = { random = math.random, noise = function() return 0 end,
      newRandomGenerator = function() return { random = math.random } end },
    filesystem = setmetatable({ getInfo = function() return nil end },
      { __index = function() return function() return nil end end }),
    keyboard = setmetatable({ isDown = function() return false end }, { __index = function() return noop end }),
    mouse = setmetatable({ getPosition = function() return -1, -1 end,
      isDown = function() return false end }, { __index = function() return noop end }),
    window = stub_ns(), audio = stub_ns(), system = stub_ns(), event = stub_ns(),
    thread = stub_ns(), image = stub_ns(), sound = stub_ns(), font = stub_ns(),
  }, { __index = function() return stub_ns() end })

  local function atlas() return { image = IMG, px = 71, py = 95 } end
  local ATLAS = setmetatable({}, { __index = function(t, k) local a = atlas(); rawset(t, k, a); return a end })

  _G.G = {
    NEURO = { persona = "neuro", state = "MENU", enabled = true, ai_highlighted = {},
      ai_glow = {}, purchase_showcase_queue = nil, recent_actions = {} },
    GAME = { dollars = 25, round = 1, round_resets = { ante = 1, blind_choices = {} },
      blind = {}, used_vouchers = {}, modifiers = {}, hands = {} },
    TIMERS = { REAL = 0 },
    STAGE = 1, STAGES = { MAIN_MENU = 1, RUN = 2 },
    FUNCS = {}, STATES = {}, SETTINGS = { paused = false, GAMESPEED = 1 },
    C = setmetatable({
      ETERNAL    = { 0.780, 0.349, 0.522, 1 },
      PERISHABLE = { 0.310, 0.365, 0.631, 1 },
      RENTAL     = { 0.694, 0.561, 0.263, 1 },
      CLEAR      = { 0, 0, 0, 0 },
    }, { __index = function() return { 1, 1, 1, 1 } end }),
    ARGS = {}, P_CENTERS = {}, P_CENTER_POOLS = {}, P_BLINDS = {}, localization = {},
    ASSET_ATLAS = ATLAS, SHADERS = {}, TILESCALE = 3.65, TILESIZE = 20, CANV_SCALE = 1,
    I = { MOVEABLE = {}, UIBOX = {}, NODE = {} },
  }
  _G.SMODS = {
    current_mod = { path = "./", config = { settings = {}, colours = {} } },
    save_mod_config = function() return true end,
    Mods = {}, findModByID = function() return nil end,
  }
  _G.NFS = setmetatable({}, { __index = function() return noop end })
end

install_globals()

local Dev, HUD, Prims

function M.enable_mesh_capture()
  if Dev then error("mesh capture must be enabled before the first capture") end
  mesh_capture = true
end

function M.enable_text_capture()
  if Dev then error("text capture must be enabled before the first capture") end
  text_capture = true
end

function M.enable_canvas_capture()
  if Dev then error("canvas capture must be enabled before the first capture") end
  canvas_capture = true
end

function M.canvas_ops(canvas)
  return (type(canvas) == "table" and canvas.__raster_canvas) and canvas.ops or nil
end

local function lazy_require()
  if Dev then return end
  Dev = require("hud.dev_scenario")
  HUD = require("render.hud_overlay")
  Prims = require("hud.prims")
end

function M.scenes()
  lazy_require()
  local out = {}
  for i, sc in ipairs(Dev.SCENES) do out[i] = { i = i, id = sc.id, label = sc.label } end
  return out
end

function M.personas()
  local keys = {}
  for k in pairs(require("render.palette").PALETTES) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

local function bank_buttons()
  local was = rec.enabled
  rec.enabled = true
  local keep = rec.take()
  Dev.draw_buttons()
  local ops = rec.take()
  rec.ops = keep
  rec.enabled = was
  local out = {}
  for _, op in ipairs(ops) do
    local p = {}
    for w in op:gmatch("%S+") do p[#p + 1] = w end
    if p[1] == "T" then
      local label = (p[10] or ""):gsub("%%(%x%x)",
        function(hh) return string.char(tonumber(hh, 16)) end)
      out[#out + 1] = { label = label, x = tonumber(p[7]), y = tonumber(p[8]) }
    end
  end
  return out
end

local function click_label(want)
  for _, b in ipairs(bank_buttons()) do
    if b.label == want then
      Dev.mousepressed(b.x, b.y, 1)
      return true
    end
  end
  return false
end

local function header_button(prefix)
  for _, b in ipairs(bank_buttons()) do
    if b.label:sub(1, #prefix) == prefix then return b end
  end
end

function M.set_axis(axis_label_upper, value_label)
  lazy_require()
  local prefix, want = axis_label_upper .. ": ", axis_label_upper .. ": " .. value_label
  if not header_button(prefix) then click_label("TWEAK") end
  local hdr = header_button(prefix)
  if not hdr then error("dev bank has no '" .. axis_label_upper .. ":' header") end
  if hdr.label == want then return end
  for _ = 1, 80 do
    Dev.mousepressed(hdr.x, hdr.y, 1)
    local h = header_button(prefix)
    if not h then error("dev bank lost its '" .. axis_label_upper .. ":' header") end
    if h.label == want then return end
    if h.label == hdr.label then
      if not click_label(value_label) then
        error("dev bank has no '" .. axis_label_upper .. "' value " .. value_label)
      end
      h = header_button(prefix)
      if h then Dev.mousepressed(h.x, h.y, 1) end
      return
    end
    hdr = h
  end
  error("dev bank has no '" .. axis_label_upper .. "' value " .. value_label)
end

M.BASE_T = 100  -- an arbitrary non-zero clock origin; fades measured from 0 hide sign errors
M.FPS = 60

function M.capture(opts)
  lazy_require()
  local scene_i
  for i, sc in ipairs(Dev.SCENES) do if sc.id == opts.scene then scene_i = i end end
  if not scene_i then error("unknown scene '" .. tostring(opts.scene) .. "'") end

  SIZE.w, SIZE.h = opts.size and opts.size.w or 1280, opts.size and opts.size.h or 720

  Dev.set(false)
  G.TIMERS.REAL = M.BASE_T
  Dev.set(true)
  Dev.select(scene_i)
  if opts.persona then M.set_axis("PERSONA", opts.persona) end
  if opts.speed then M.set_axis("SPEED", opts.speed) end
  for label, value in pairs(opts.axes or {}) do M.set_axis(label, value) end

  local want = {}
  local last = 0
  for _, t in ipairs(opts.moments) do
    want[string.format("%.5f", t)] = true
    if t > last then last = t end
  end

  local dt = 1 / (opts.fps or M.FPS)
  local timeline, seen = {}, {}
  local t = 0
  while t < last - 1e-9 do
    local k = string.format("%.5f", t)
    if not seen[k] then seen[k] = true; timeline[#timeline + 1] = t end
    t = t + dt
  end
  for _, m in ipairs(opts.moments) do
    local k = string.format("%.5f", m)
    if not seen[k] then seen[k] = true; timeline[#timeline + 1] = m end
  end
  table.sort(timeline)

  local frames = {}
  for _, now in ipairs(timeline) do
    local keep = want[string.format("%.5f", now)] or false
    G.TIMERS.REAL = M.BASE_T + now
    rec.enabled = keep
    rec.reset()
    rec.enabled = keep
    local err
    local ok, e = xpcall(function()
      Dev.mount()
      HUD.draw_indicator()
      HUD.draw_cookie()
      HUD.draw_login()
    end, debug.traceback)
    if not ok then err = tostring(e) end
    local uok, uerr = pcall(Dev.unmount)
    if not uok then err = (err and (err .. "\n") or "") .. "unmount: " .. tostring(uerr) end
    rec.enabled = true
    if keep or err then
      frames[#frames + 1] = {
        persona = opts.persona or "neuro", scene = opts.scene, t = now,
        ops = rec.take(), err = err,
      }
    else
      rec.take()
    end
  end

  Dev.set(false)
  return frames
end

function M.write_ops(path, frames, meta)
  local f, e = io.open(path, "w")
  if not f then return nil, e end
  f:write("# neuro-game draw-op log\n")
  f:write("# driver: ", M.SYNTHETIC and ("SYNTHETIC-CTX -- " .. M.DRIVER) or M.DRIVER, "\n")
  for _, k in ipairs({ "scene", "size", "personas", "moments" }) do
    if meta and meta[k] then f:write("# ", k, ": ", tostring(meta[k]), "\n") end
  end
  f:write("# ops: R rect | C circle | E ellipse | A arc | L line | P poly | D points",
    " | T text | I image | S scissor\n")
  f:write("# fields: <verb> [mode] r g b a blend <geometry...>   (text: x y px %-escaped)\n")
  local bytes = 0
  for _, fr in ipairs(frames) do
    f:write(string.format("FRAME %s %s %.4f %dx%d %d\n", fr.persona, fr.scene, fr.t,
      SIZE.w, SIZE.h, #fr.ops))
    if fr.err then
      for line in tostring(fr.err):gmatch("[^\n]+") do f:write("! ", line, "\n") end
    end
    for _, op in ipairs(fr.ops) do f:write(op, "\n"); bytes = bytes + #op + 1 end
  end
  f:close()
  return bytes
end

local MODED = { R = true, C = true, E = true, A = true, P = true }

function M.parse_op(line)
  local p = {}
  for w in tostring(line):gmatch("%S+") do p[#p + 1] = w end
  local v = p[1]
  if not v then return nil end
  if v == "S" then
    if p[2] == "off" then return { v = "S", off = true, n = {} } end
    return { v = "S", n = { tonumber(p[2]), tonumber(p[3]), tonumber(p[4]), tonumber(p[5]) } }
  end
  local i = MODED[v] and 3 or 2
  local mode = MODED[v] and p[2] or nil
  local op = { v = v, mode = mode, r = tonumber(p[i]), g = tonumber(p[i + 1]),
    b = tonumber(p[i + 2]), a = tonumber(p[i + 3]), blend = p[i + 4], n = {} }
  i = i + 5
  if v == "T" then
    op.n = { tonumber(p[i]), tonumber(p[i + 1]), tonumber(p[i + 2]) }
    op.x, op.y, op.px = op.n[1], op.n[2], op.n[3]
    op.text = (p[i + 3] or ""):gsub("%%(%x%x)",
      function(hh) return string.char(tonumber(hh, 16)) end)
  else
    local k = 0
    while p[i] do k = k + 1; op.n[k] = tonumber(p[i]); i = i + 1 end
    if v == "R" or v == "I" then op.x, op.y, op.w, op.h = op.n[1], op.n[2], op.n[3], op.n[4]
    elseif v == "C" or v == "E" or v == "A" then op.x, op.y = op.n[1], op.n[2] end
  end
  return op
end

function M.read_ops(path)
  local f, e = io.open(path, "r")
  if not f then return nil, e end
  local frames, cur = {}, nil
  for line in f:lines() do
    if line:sub(1, 1) ~= "#" then
      if line:sub(1, 6) == "FRAME " then
        local persona, scene, t = line:match("^FRAME (%S+) (%S+) (%S+)")
        cur = { persona = persona, scene = scene, t = tonumber(t), ops = {}, errs = {} }
        frames[#frames + 1] = cur
      elseif line:sub(1, 2) == "! " and cur then
        cur.errs[#cur.errs + 1] = line:sub(3)
      elseif cur and line ~= "" then
        cur.ops[#cur.ops + 1] = line
      end
    end
  end
  f:close()
  return frames
end

function M.scratch(tag)
  local seed = os.tmpname()
  os.remove(seed)
  local dir = seed .. "-" .. tostring(tag or "raster")
  os.execute("mkdir -p '" .. dir .. "'")
  return dir, function() os.execute("rm -rf '" .. dir .. "'") end
end

return M
