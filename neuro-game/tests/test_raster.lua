
local Cap = require("tests.raster_capture")
local check, done = require("tests.helpers").harness("raster")

local function ops_of(frames, persona, t)
  for _, fr in ipairs(frames) do
    if fr.persona == persona and math.abs(fr.t - t) < 1e-6 then return fr end
  end
end

local function no_errors(frames)
  for _, fr in ipairs(frames) do
    if fr.err then return false, fr.err end
  end
  return true
end

local function text_on_line(frame, y_lo, y_hi, min_alpha)
  local rows = {}
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "T" and op.y and op.y >= y_lo and op.y <= y_hi
      and (op.a or 0) >= (min_alpha or 0.5) then
      local key = string.format("%.0f", op.y)
      rows[key] = rows[key] or {}
      table.insert(rows[key], op)
    end
  end
  local out = {}
  for _, row in pairs(rows) do
    table.sort(row, function(p, q) return p.x < q.x end)
    local s = {}
    for _, op in ipairs(row) do s[#s + 1] = op.text end
    out[#out + 1] = table.concat(s)
  end
  return out
end

local function has_line(frame, y_lo, y_hi, want)
  for _, s in ipairs(text_on_line(frame, y_lo, y_hi)) do
    if s:find(want, 1, true) then return true end
  end
  return false
end

local function count_opaque(frame, pred)
  local n = 0
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and (op.a or 0) >= 0.5 and pred(op) then n = n + 1 end
  end
  return n
end

check("the recorder drives the real love.draw entry point, not a hand-built ctx",
  Cap.SYNTHETIC == false and Cap.DRIVER:find("hud_overlay.draw_indicator", 1, true) ~= nil,
  Cap.DRIVER)

do
  Cap.rec.reset()
  local was_enabled = Cap.rec.enabled
  local suppressed_before = Cap.rec.n_suppressed
  local saved_format = string.format
  local format_calls, tostring_calls, image_probes = 0, 0, 0
  local text = setmetatable({}, {
    __tostring = function()
      tostring_calls = tostring_calls + 1
      return "disabled recorder text"
    end,
  })
  local image = {
    getDimensions = function()
      image_probes = image_probes + 1
      return 71, 95
    end,
  }

  Cap.rec.enabled = false
  string.format = function(...)
    format_calls = format_calls + 1
    return saved_format(...)
  end
  local ok, err = pcall(function()
    Cap.gfx.setScissor(10, 20, 30, 40)
    Cap.gfx.intersectScissor(20, 10, 30, 30)
    local x, y, w, h = Cap.gfx.getScissor()
    check("disabled recording still maintains scissor state",
      x == 20 and y == 20 and w == 20 and h == 20,
      saved_format("%s,%s %sx%s", x, y, w, h))
    Cap.gfx.setScissor()
    Cap.gfx.rectangle("fill", 1, 2, 3, 4, 5)
    Cap.gfx.circle("line", 1, 2, 3)
    Cap.gfx.ellipse("fill", 1, 2, 3, 4)
    Cap.gfx.arc("line", "open", 1, 2, 3, 4, 5)
    Cap.gfx.line(1, 2, 3, 4)
    Cap.gfx.polygon("fill", 1, 2, 3, 4, 5, 6)
    Cap.gfx.points(1, 2, 3, 4)
    Cap.gfx.print(text, 1, 2)
    Cap.gfx.printf(text, 1, 2, 100, "left")
    Cap.gfx.draw(image, 1, 2)
  end)
  string.format = saved_format
  Cap.rec.enabled = was_enabled
  local ops = Cap.rec.take()

  check("disabled recorder draw calls complete without conversion errors", ok, err)
  check("disabled recorder skips op-log formatting, tokenization and image probing",
    format_calls == 0 and tostring_calls == 0 and image_probes == 0,
    saved_format("format=%d tostring=%d image=%d", format_calls, tostring_calls, image_probes))
  check("disabled recorder suppresses every op without appending to the log",
    #ops == 0 and Cap.rec.n_suppressed - suppressed_before == 13,
    saved_format("ops=%d suppressed=%d", #ops, Cap.rec.n_suppressed - suppressed_before))
end

check("every dev-harness scene is reachable by id", #Cap.scenes() >= 18)

local SIZE = { w = 1280, h = 720 }
local TOAST_T = 1.10   -- past its fade-in

local toast = {}
for _, persona in ipairs({ "neuro", "evil", "hiyori" }) do
  toast[persona] = Cap.capture({ scene = "toasts", persona = persona,
    moments = { TOAST_T }, size = SIZE })
end

check("toast capture raises no draw error", (no_errors(toast.neuro)))
check("toast capture raises no draw error (evil)", (no_errors(toast.evil)))
check("toast capture raises no draw error (hiyori)", (no_errors(toast.hiyori)))

local tn = ops_of(toast.neuro, "neuro", TOAST_T)
local te = ops_of(toast.evil, "evil", TOAST_T)
local th_ = ops_of(toast.hiyori, "hiyori", TOAST_T)

local band = function(op) return op.y and op.y >= 0 and op.y <= 130
  and op.x and op.x > SIZE.w * 0.25 and op.x < SIZE.w * 0.75 end
check("the buy toast draws opaque ops in the top-centre band (neuro)",
  count_opaque(tn, band) > 20, count_opaque(tn, band))
check("the buy toast draws opaque ops in the top-centre band (evil)",
  count_opaque(te, band) > 20, count_opaque(te, band))
check("the buy toast draws opaque ops in the top-centre band (hiyori, neutral path)",
  count_opaque(th_, band) > 8, count_opaque(th_, band))

check("the toast prints its verb for the area on screen (neuro)",
  has_line(tn, 0, 60, "BOUGHT"), table.concat(text_on_line(tn, 0, 60), " | "))
check("the toast prints its verb for the area on screen (evil)",
  has_line(te, 0, 60, "BOUGHT"))
check("the toast prints its verb for the area on screen (hiyori)",
  has_line(th_, 0, 60, "BOUGHT"))

local function line_y(frame, want, y_lo, y_hi)
  local rows = {}
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "T" and op.y and op.y >= y_lo and op.y <= y_hi and (op.a or 0) >= 0.5 then
      local key = string.format("%.0f", op.y)
      rows[key] = rows[key] or {}
      table.insert(rows[key], op)
    end
  end
  local best
  for key, row in pairs(rows) do
    table.sort(row, function(p, q) return p.x < q.x end)
    local str = {}
    for _, op in ipairs(row) do str[#str + 1] = op.text end
    if table.concat(str):find(want, 1, true) then
      local y = tonumber(key)
      if not best or y < best then best = y end
    end
  end
  return best
end

local function acquire_panel(frame)
  local best
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "R" and op.mode == "line" and op.w and op.w > 100 and op.h and op.h > 25
      and op.x and op.x > 260 and op.x + op.w < 1050 and op.y and op.y < 250
      and (op.a or 0) >= 0.4 then
      if not best or op.a > best.a then best = op end
    end
  end
  return best
end

local function corridor_panel_count(frame)
  local main = acquire_panel(frame)
  if not main then return 0 end
  local n, seen = 0, {}
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "R" and op.mode == "line" and op.w and op.w > 100 and op.h and op.h > 25
      and op.x and op.x > 260 and op.x + op.w < 1050 and op.y and op.y < 250
      and (op.a or 0) >= 0.4 then
      local key = (math.abs(op.x + op.w / 2 - (main.x + main.w / 2)) <= 6
        and math.abs(op.y + op.h / 2 - (main.y + main.h / 2)) <= 6)
        and "main" or string.format("%.0f_%.0f", op.x, op.y)
      if not seen[key] then seen[key] = true; n = n + 1 end
    end
  end
  return n
end

local function is_blood(op)
  local reds = { { 0.29, 0.030, 0.055 }, { 0.46, 0.06, 0.09 } }
  for _, c in ipairs(reds) do
    if math.abs((op.r or 1) - c[1]) < 0.02 and math.abs((op.g or 1) - c[2]) < 0.02
      and math.abs((op.b or 1) - c[3]) < 0.02 then return true end
  end
  return false
end

local function contained(frame)
  local panel = acquire_panel(frame)
  if not panel then return false, string.format("t=%.2f no acquire panel found", frame.t or -1) end
  local x0, y0 = panel.x - 4, panel.y - 4
  local x1, y1 = panel.x + panel.w + 4, panel.y + panel.h + 4
  local pb = panel.y + panel.h
  local cur_scissor = nil
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "S" then
      cur_scissor = (not op.off) and { op.n[1], op.n[2], op.n[3], op.n[4] } or nil
    elseif op and op.x and op.y and op.x > 260 and op.x < 1050 and op.y < 250
      and (op.a or 0) > 0.03 then
      local shadow = (op.r or 1) < 0.01 and (op.g or 1) < 0.01 and (op.b or 1) < 0.01
        and (op.a or 0) <= 0.35 and op.v == "R" and op.mode == "fill"
      local drip = op.v == "R" and op.mode == "fill" and is_blood(op)
        and op.y >= pb - 6 and op.y + (op.h or 0) <= pb + 11
        and op.x >= panel.x - 1 and op.x + (op.w or 0) <= panel.x + panel.w + 1
      if shadow or drip then op = nil end
      if op then
        local bx0, by0, bx1, by1 = op.x, op.y, op.x, op.y
        if op.v == "R" or op.v == "I" then bx1, by1 = op.x + (op.w or 0), op.y + (op.h or 0)
        elseif op.v == "C" then
          local r = op.n[3] or 0
          bx0, by0, bx1, by1 = op.x - r, op.y - r, op.x + r, op.y + r
        elseif op.v == "T" then
          bx1 = op.x + 0.5 * (op.px or 12) * #(op.text or "")
          by1 = op.y + 1.15 * (op.px or 12)
        end
        if cur_scissor then
          local sx0, sy0 = cur_scissor[1], cur_scissor[2]
          local sx1, sy1 = cur_scissor[1] + cur_scissor[3], cur_scissor[2] + cur_scissor[4]
          bx0, by0 = math.max(bx0, sx0), math.max(by0, sy0)
          bx1, by1 = math.min(bx1, sx1), math.min(by1, sy1)
        end
        local visible = bx1 > bx0 and by1 > by0
        if visible
          and (bx0 < x0 - 0.5 or bx1 > x1 + 0.5 or by0 < y0 - 0.5 or by1 > y1 + 0.5) then
          return false, string.format("t=%.2f %s", frame.t, tostring(line):sub(1, 90))
        end
      end
    end
  end
  return true
end

do
  local panel = { x = 300, y = 10, w = 200, h = 100 }
  local base = { t = 0, ops = {
    string.format("R line 1 1 1 1 alpha %d %d %d %d 0 1", panel.x, panel.y, panel.w, panel.h),
  } }
  local clipped_ok = { t = 0, ops = {
    base.ops[1],
    string.format("S %d %d %d %d", panel.x, panel.y, panel.w, panel.h),
    string.format("R fill 1 1 1 1 alpha %d %d 20 20 0 1", panel.x + panel.w + 60, panel.y),
    "S off",
  } }
  local unclipped_bad = { t = 0, ops = {
    base.ops[1],
    string.format("R fill 1 1 1 1 alpha %d %d 20 20 0 1", panel.x + panel.w + 60, panel.y),
  } }
  local ok1, why1 = contained(clipped_ok)
  check("contained() clears an op that overflows the frame but is cut back by an active clip",
    ok1 == true, why1)
  local ok2, why2 = contained(unclipped_bad)
  check("contained() still catches the same overflow when nothing clips it",
    ok2 == false, ok2)
end

do
  local hpanel = acquire_panel(th_)
  check("hiyori toast panel outline is drawn opaque, not alpha 0",
    hpanel ~= nil and (hpanel.a or 0) >= 0.4, hpanel and hpanel.a)
  local abar
  if hpanel then
    for _, line in ipairs(th_.ops) do
      local op = Cap.parse_op(line)
      if op and op.v == "R" and op.mode == "fill" and op.x and op.y and op.w and op.h
        and op.x >= hpanel.x - 1 and op.x <= hpanel.x + 6
        and op.h >= hpanel.h * 0.3 and op.w <= 8 and (op.a or 0) >= 0.4 then
        abar = op
        break
      end
    end
  end
  check("hiyori toast accent bar is actually drawn, not skipped",
    abar ~= nil and (abar.a or 0) >= 0.4, abar and abar.a)
end

local MORPH_AT = { 0.30, 0.45, 0.55, 0.65, 0.80, 1.10 }
local fold = Cap.capture({ scene = "shop", persona = "neuro", moments = MORPH_AT, size = SIZE })
check("morph capture raises no draw error", (no_errors(fold)))

local fm = {}
for _, t in ipairs(MORPH_AT) do fm[t] = ops_of(fold, "neuro", t) end

check("the receipt is up with its verb before the hold",
  line_y(fm[0.30], "BOUGHT", 0, 120) ~= nil and line_y(fm[0.30], "NEW JOKER", 0, 120) == nil)
check("the full showcase label owns the panel after the morph",
  line_y(fm[0.80], "NEW JOKER", 0, 200) ~= nil and line_y(fm[0.80], "BOUGHT", 0, 200) == nil)
do
  local widths, tops = {}, {}
  local one_outline, contained_ok, why = true, true, nil
  for _, t in ipairs(MORPH_AT) do
    local panel = acquire_panel(fm[t])
    check(string.format("a panel is on screen at t=%.2f", t), panel ~= nil)
    if panel then
      widths[#widths + 1] = panel.w
      tops[#tops + 1] = panel.y
      if corridor_panel_count(fm[t]) > 1 then one_outline = false end
      local okc, w = contained(fm[t])
      if not okc then contained_ok = false; why = why or w end
    end
  end
  check("exactly one panel outline in the corridor at every sampled moment", one_outline)
  check("no op strays past cn(6) beyond the panel frame", contained_ok, why)
  local mono = true
  for i = 2, #widths do if widths[i] < widths[i - 1] - 0.01 then mono = false end end
  check("the panel width is monotonic through the morph",
    mono, table.concat(widths, " -> "))
  check("the panel ends more than twice its receipt width",
    widths[#widths] > widths[1] * 2, widths[1] .. " -> " .. widths[#widths])
  local top_lo, top_hi = math.huge, -math.huge
  for _, y in ipairs(tops) do
    top_lo, top_hi = math.min(top_lo, y), math.max(top_hi, y)
  end
  check("the top edge never moves through the whole beat", top_hi - top_lo <= 1.5,
    top_lo .. ".." .. top_hi)
end

local function scissor_events(frame)
  local out = {}
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "S" then out[#out + 1] = op end
  end
  return out
end

local function assert_clip_pushed_and_popped(frame, tag)
  local panel = acquire_panel(frame)
  local events = scissor_events(frame)
  local pushed_idx
  for i, ev in ipairs(events) do
    if not ev.off and panel
      and math.abs(ev.n[1] - panel.x) <= 2 and math.abs(ev.n[2] - panel.y) <= 2
      and math.abs(ev.n[3] - panel.w) <= 2 and math.abs(ev.n[4] - panel.h) <= 2 then
      pushed_idx = i
      break
    end
  end
  check(tag .. ": the full showcase pushes a scissor clip around its own bounds",
    pushed_idx ~= nil, panel and string.format("panel %.0f,%.0f %.0fx%.0f", panel.x, panel.y,
      panel.w, panel.h))
  local popped = false
  if pushed_idx then
    for i = pushed_idx + 1, #events do
      if events[i].off then popped = true; break end
    end
  end
  check(tag .. ": that clip is popped again before the frame ends", popped)
end
assert_clip_pushed_and_popped(fm[0.80], "neuro full showcase")

do
  local function opaque_name_rows(frame)
    local rows = {}
    for _, line in ipairs(frame.ops) do
      local op = Cap.parse_op(line)
      if op and op.v == "T" and (op.a or 0) >= 0.9 and op.x and op.x > 260 and op.x < 1050
        and op.y and op.y < 200 and op.px and op.px >= 14 then
        rows[string.format("%.0f", op.y)] = true
      end
    end
    local n = 0
    for _ in pairs(rows) do n = n + 1 end
    return n
  end
  check("mid-morph there is one opaque display-size text row, not two",
    opaque_name_rows(fm[0.55]) <= 1, opaque_name_rows(fm[0.55]))
end

do
  local function max_opaque_glyphs_at_one_x(frame, y_lo, y_hi, min_alpha)
    local by_x = {}
    for _, line in ipairs(frame.ops) do
      local op = Cap.parse_op(line)
      if op and op.v == "T" and op.y and op.y >= y_lo and op.y <= y_hi
        and (op.a or 0) >= (min_alpha or 0.9) and op.px and op.px < 12 then
        local key = string.format("%.0f", op.x)
        by_x[key] = (by_x[key] or 0) + 1
      end
    end
    local most = 0
    for _, n in pairs(by_x) do if n > most then most = n end end
    return most
  end
  check("mid-morph the two eyebrow labels never both render opaque at the same spot",
    max_opaque_glyphs_at_one_x(fm[0.55], 0, 120, 0.9) <= 1,
    max_opaque_glyphs_at_one_x(fm[0.55], 0, 120, 0.9))
end

local EVIL_AT = { 0.40, 0.62, 0.75, 1.05 }
local fold_e = Cap.capture({ scene = "shop", persona = "evil", moments = EVIL_AT, size = SIZE })
check("evil morph capture raises no draw error", (no_errors(fold_e)))
check("evil shows the receipt and then the morphed showcase",
  line_y(ops_of(fold_e, "evil", 0.40), "BOUGHT", 0, 300) ~= nil
  and line_y(ops_of(fold_e, "evil", 1.05), "BOUGHT", 0, 300) == nil
  and line_y(ops_of(fold_e, "evil", 1.05), "NEW JOKER", 0, 300) ~= nil)
do
  local widths = {}
  local one_outline, contained_ok, why = true, true, nil
  for _, t in ipairs(EVIL_AT) do
    local fr = ops_of(fold_e, "evil", t)
    local panel = acquire_panel(fr)
    check(string.format("evil: a panel is on screen at t=%.2f", t), panel ~= nil)
    if panel then
      widths[#widths + 1] = panel.w
      if corridor_panel_count(fr) > 1 then one_outline = false end
      local okc, w = contained(fr)
      if not okc then contained_ok = false; why = why or w end
    end
  end
  check("evil: exactly one panel outline at every sampled moment", one_outline)
  check("evil: no op strays past cn(6) beyond the frame (blood drips past the bottom only)",
    contained_ok, why)
  local mono = true
  for i = 2, #widths do if widths[i] < widths[i - 1] - 0.01 then mono = false end end
  check("evil: the panel width is monotonic through the morph",
    mono, table.concat(widths, " -> "))
end
assert_clip_pushed_and_popped(ops_of(fold_e, "evil", 1.05), "evil full showcase")
check("evil and neuro shop frames are materially different op streams",
  (function()
    local ef, nf = ops_of(fold_e, "evil", 0.40), fm[0.45]
    if not ef or not nf then return false end
    if #ef.ops ~= #nf.ops then return true end
    for i = 1, #ef.ops do if ef.ops[i] ~= nf.ops[i] then return true end end
    return false
  end)())

local slow = Cap.capture({ scene = "shop", persona = "neuro", moments = { 4 * 0.55 },
  size = SIZE, speed = "1/4x" })
local sfr, ffr = ops_of(slow, "neuro", 2.20), fm[0.55]
check("a quarter-speed frame is the full-speed frame at the same phase",
  sfr ~= nil and ffr ~= nil and #sfr.ops == #ffr.ops
  and line_y(sfr, "NEW JOKER", 0, 300) == line_y(ffr, "NEW JOKER", 0, 300)
  and line_y(sfr, "BOUGHT", 0, 300) == line_y(ffr, "BOUGHT", 0, 300),
  sfr and string.format("%d ops vs %d ops", #sfr.ops, ffr and #ffr.ops or -1))

local vfold = Cap.capture({ scene = "vouchers", persona = "neuro", moments = { 0.30, 0.85 },
  size = SIZE })
check("the voucher buy morphs as well",
  line_y(ops_of(vfold, "neuro", 0.30), "REDEEMED", 0, 300) ~= nil
  and line_y(ops_of(vfold, "neuro", 0.85), "REDEEMED", 0, 300) == nil
  and line_y(ops_of(vfold, "neuro", 0.85), "VOUCHER", 0, 300) ~= nil)
check("the voucher morph keeps one outline and stays contained",
  corridor_panel_count(ops_of(vfold, "neuro", 0.85)) <= 1
  and (contained(ops_of(vfold, "neuro", 0.85))))

check("the two personas produce materially different op streams",
  math.abs(#tn.ops - #te.ops) > 0 or tn.ops[1] ~= te.ops[1])

collectgarbage()
local unrelated = Cap.capture({ scene = "shop", persona = "evil", moments = { 0.62 }, size = SIZE })
check("an unrelated interleaved capture raises no draw error", no_errors(unrelated))
local again = Cap.capture({ scene = "toasts", persona = "neuro",
  moments = { TOAST_T }, size = SIZE })
local a2 = ops_of(again, "neuro", TOAST_T)
local same = (#a2.ops == #tn.ops)
if same then
  for i = 1, #tn.ops do
    if tn.ops[i] ~= a2.ops[i] then same = false; break end
  end
end
check("re-capturing the same request later in the same run is still byte-identical " ..
  "(determinism only, not a regression guard)", same)

do
  local GOLDEN_PATH = "tests/golden/toast_neuro_1280x720.ops"
  local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
  end
  local function write_file(path, s)
    os.execute("mkdir -p tests/golden")
    local f = io.open(path, "w")
    if not f then return false end
    f:write(s)
    f:close()
    return true
  end
  local golden_body = table.concat(tn.ops, "\n") .. "\n"
  local existing = read_file(GOLDEN_PATH)
  local regenerating = os.getenv("NEURO_RASTER_UPDATE_GOLDEN") == "1"
  check("the golden reference is present in the checkout (" .. GOLDEN_PATH ..
    " must be tracked in git; regenerate deliberately with NEURO_RASTER_UPDATE_GOLDEN=1)",
    existing ~= nil or regenerating, "file not found")
  if regenerating then
    local wrote = write_file(GOLDEN_PATH, golden_body)
    check("golden reference written this run -- verify it by hand once, then commit it " ..
      "(not a regression pass: nothing was compared)",
      wrote and read_file(GOLDEN_PATH) == golden_body)
  elseif existing then
    local same_as_golden = existing == golden_body
    local why
    if not same_as_golden then
      local a, b = {}, {}
      for l in existing:gmatch("[^\n]+") do a[#a + 1] = l end
      for l in golden_body:gmatch("[^\n]+") do b[#b + 1] = l end
      local first_diff
      for i = 1, math.max(#a, #b) do
        if a[i] ~= b[i] then first_diff = i; break end
      end
      why = first_diff
        and string.format("first diff at line %d: golden=%s captured=%s", first_diff,
          tostring(a[first_diff]):sub(1, 80), tostring(b[first_diff]):sub(1, 80))
        or string.format("golden has %d lines, capture has %d", #a, #b)
    end
    check("the toast capture matches the checked-in golden reference " ..
      "(set NEURO_RASTER_UPDATE_GOLDEN=1 to regenerate it deliberately)", same_as_golden, why)
  end
end

local big = Cap.capture({ scene = "toasts", persona = "neuro", moments = { TOAST_T },
  size = { w = 1920, h = 1080 } })
local bn = ops_of(big, "neuro", TOAST_T)

local function px_set(frame)
  local seen, n = {}, 0
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "T" and op.px and not seen[op.px] then seen[op.px] = true; n = n + 1 end
  end
  return seen, n
end
local small_px = px_set(tn)
local big_px = px_set(bn)
local grew = false
for px in pairs(big_px) do if not small_px[px] then grew = true end end
check("type size is recomposed at a larger viewport (real scale path)", grew)

local function widest_rect(frame)
  local w = 0
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "R" and op.h and op.h > 200 and (op.w or 0) > w then w = op.w end
  end
  return w
end
check("panel geometry is recomposed at a larger viewport",
  widest_rect(bn) > widest_rect(tn) + 20,
  string.format("720p=%.0f 1080p=%.0f", widest_rect(tn), widest_rect(bn)))

local RES_CHAIN = {
  { w = 1280, h = 720, ops = tn },
  { w = 1366, h = 768 },
  { w = 1600, h = 900 },
  { w = 1920, h = 1080, ops = bn },
  { w = 2560, h = 1440 },
  { w = 3840, h = 2160 },
}
local prev_w, prev_h = nil, nil
for _, res in ipairs(RES_CHAIN) do
  local fr = res.ops
  if not fr then
    local cap = Cap.capture({ scene = "toasts", persona = "neuro", moments = { TOAST_T },
      size = { w = res.w, h = res.h } })
    check(string.format("toast capture raises no draw error at %dx%d", res.w, res.h),
      no_errors(cap))
    fr = ops_of(cap, "neuro", TOAST_T)
  end
  check(string.format("a frame is produced at %dx%d", res.w, res.h), fr ~= nil)
  local w = fr and widest_rect(fr) or 0
  if prev_w then
    check(string.format("panel geometry keeps scaling with height between %dp and %dp",
      prev_h, res.h), fr ~= nil and w > prev_w,
      string.format("%.0f (h=%d) -> %.0f (h=%d)", prev_w, prev_h, w, res.h))
  end
  prev_w, prev_h = w, res.h
end

do
  local dir, cleanup = Cap.scratch("selftest")
  local a, cleanup_b = Cap.scratch("selftest")
  check("scratch paths carry per-process entropy", dir ~= a, dir)
  local f = io.open(dir .. "/probe", "w")
  check("scratch dir is writable", f ~= nil)
  if f then f:write("x"); f:close() end
  cleanup()
  cleanup_b()
  check("scratch dir is torn down", io.open(dir .. "/probe", "r") == nil)
end

do

  local function near(v, w) return v ~= nil and math.abs(v - w) < 0.004 end

  local function fills(frame, min_x, lo, hi)
    local out = {}
    for _, line in ipairs(frame.ops) do
      local op = Cap.parse_op(line)
      if op and op.v == "R" and op.mode == "fill" and op.x and op.y and op.w and op.h
        and op.x > min_x and op.y >= lo and op.y < hi then
        out[#out + 1] = op
      end
    end
    return out
  end

  local function footer_rule(frame, min_x)
    local y, len, x0
    for _, line in ipairs(frame.ops) do
      local op = Cap.parse_op(line)
      if op and op.v == "L" and (op.a or 0) >= 0.5
        and op.n[2] and op.n[2] > min_x
        and op.n[3] and op.n[5] and op.n[3] == op.n[5]
        and op.n[4] and (op.n[4] - op.n[2]) > 100
        and (not y or op.n[3] > y) then
        y, len, x0 = op.n[3], op.n[4] - op.n[2], op.n[2]
      end
    end
    return y, len, x0
  end

  local function band_h(h)
    local s = math.max(0.5, math.floor((h / 1080) / 0.05 + 0.5) * 0.05)
    return math.floor(80 * s + 0.5)
  end

  local function rail(frame, min_x, lo, hi, len)
    local tally = {}
    for _, op in ipairs(fills(frame, min_x, lo, hi)) do
      if op.h == 1 and op.w < len / 4 then tally[op.y] = (tally[op.y] or 0) + 1 end
    end
    local best_y, best_n
    for y, n in pairs(tally) do
      if not best_n or n > best_n then best_y, best_n = y, n end
    end
    return best_y, best_n or 0
  end

  local function band_extent(frame, min_x, lo, hi, len)
    local top, bot
    local function grow(a, b)
      if not top or a < top then top = a end
      if not bot or b > bot then bot = b end
    end
    for _, op in ipairs(fills(frame, min_x, lo, hi)) do
      if op.w < len * 0.9 then grow(op.y, op.y + op.h) end
    end
    for _, line in ipairs(frame.ops) do
      local op = Cap.parse_op(line)
      if op and op.v == "T" and op.x and op.y and op.x > min_x and op.y >= lo and op.y < hi
        and (op.a or 0) >= 0.4 then
        grow(op.y, op.y + (op.px or 0))
      end
    end
    return top, bot
  end

  local function ink(frame, min_x, lo, hi, len)
    local total = 0
    for _, op in ipairs(fills(frame, min_x, lo, hi)) do
      if op.w < len * 0.9 then           -- skip the panel's own full-width border
        total = total + op.w * op.h
      end
    end
    return total
  end

  local PERIOD = require("render.hud_shared").CAROUSEL_PERIOD
  local QUIP, LEG_A, LEG_B = PERIOD * 0.5, PERIOD * 1.5, PERIOD * 2.5
  local MID = PERIOD * 2 + 0.12
  for _, res in ipairs({ { w = 1920, h = 1080 }, { w = 1280, h = 720 }, { w = 960, h = 540 } }) do
    for _, persona in ipairs({ "neuro", "evil" }) do
      local tag = string.format("%dp %s", res.h, persona)
      local MIN_X = res.w * 0.55
      local cap = Cap.capture({ scene = "playing", persona = persona,
        moments = { QUIP, LEG_A, LEG_B, MID }, size = res })
      check("band capture raises no draw error at " .. tag, (no_errors(cap)))

      local fq = ops_of(cap, persona, QUIP)
      local fa = ops_of(cap, persona, LEG_A)
      local fb = ops_of(cap, persona, LEG_B)
      local fmid = ops_of(cap, persona, MID)
      check("band frames are produced at " .. tag,
        fq ~= nil and fa ~= nil and fb ~= nil and fmid ~= nil)

      if fq and fa and fb and fmid then
        local fy, rule_len, rule_x = footer_rule(fq, MIN_X)
        check("the footer rule is found at " .. tag, fy ~= nil, tostring(fy))

        if fy then
          local lo, hi = fy, fy + band_h(res.h)

          local rows = 0
          for _, op in ipairs(fills(fa, MIN_X, lo, hi)) do
            if op.h >= 4 and op.w > rule_len * 0.95 then
              rows = rows + 1
            end
          end
          check("the legend paints no plate into the band at " .. tag,
            rows == 0, string.format("%d plate-sized fills", rows))

          local qi = ink(fq, MIN_X, lo, hi, rule_len)
          local li = ink(fa, MIN_X, lo, hi, rule_len)
          check("the legend stays within the band's ink budget at " .. tag,
            qi > 0 and li <= qi * 14,
            string.format("quip=%.0f legend=%.0f (x%.1f)", qi, li, qi > 0 and li / qi or 0))

          local function ink_pair(frame, lo2, hi2)
            local rows_ = {}
            for _, line in ipairs(frame.ops) do
              local op = Cap.parse_op(line)
              if op and op.v == "T" and op.x and op.y and op.x > MIN_X
                and op.y >= lo2 and op.y < hi2 then
                local lum = 0.2126 * (op.r or 0) + 0.7152 * (op.g or 0) + 0.0722 * (op.b or 0)
                local key = lum < 0.05 and (op.y - 1) or op.y
                local r = rows_[key] or { ink = 0, sh = 0 }
                if lum < 0.05 then r.sh = math.max(r.sh, op.a or 0)
                else r.ink = math.max(r.ink, op.a or 0) end
                rows_[key] = r
              end
            end
            local low, at = nil, nil
            for y, r in pairs(rows_) do
              if r.ink > 0 and (not at or y > at) then at, low = y, r end
            end
            return low and low.ink or 0, low and low.sh or 0
          end
          local _, ref_sh = ink_pair(fa, fy - 200, fy)
          for _, pair in ipairs({ { fq, "seed quip" }, { fa, "legend" } }) do
            local ink_a, sh_a = ink_pair(pair[1], lo, hi)
            check("the " .. pair[2] .. " is inked to be read, not glanced at, at " .. tag,
              ink_a >= 0.88, string.format("%.2f", ink_a))
            check("the " .. pair[2] .. " carries the panel's shadow at " .. tag,
              ref_sh > 0 and sh_a >= ref_sh - 0.01,
              string.format("band=%.2f panel=%.2f", sh_a, ref_sh))
          end

          local qk, qn = rail(fq, MIN_X, lo, hi, rule_len)
          local lk, ln = rail(fa, MIN_X, lo, hi, rule_len)
          check("the seed quip draws a rule in the band at " .. tag, qn >= 6, qn)
          check("the legend draws a rule in the band at " .. tag, ln >= 6, ln)
          if qn >= 6 and ln >= 6 then
            check("the legend's rule is on the seed quip's axis at " .. tag,
              qk == lk, string.format("quip y=%.0f legend y=%.0f", qk, lk))
            local l_side, r_side = 0, 0
            local cx = rule_x + rule_len / 2
            for _, op in ipairs(fills(fa, MIN_X, lo, hi)) do
              if op.h == 1 and op.w < rule_len / 4 and op.y == lk then
                if op.x < cx then l_side = l_side + 1 else r_side = r_side + 1 end
              end
            end
            check("the legend's rule reaches out on both sides at " .. tag,
              l_side >= 3 and r_side >= 3, string.format("left=%d right=%d", l_side, r_side))
          end

          local mid = fy + math.floor(band_h(res.h) / 2)
          for _, pair in ipairs({ { fq, "seed quip" }, { fa, "legend" } }) do
            local top, bot = band_extent(pair[1], MIN_X, lo, hi, rule_len)
            check("the " .. pair[2] .. " block stays inside the band at " .. tag,
              top and bot and top >= lo and bot <= hi,
              string.format("%s..%s in %d..%d", tostring(top), tostring(bot), lo, hi))
            if top and bot then
              check("the " .. pair[2] .. " block is centred on the band axis at " .. tag,
                math.abs((mid - top) - (bot - mid)) <= 2,
                string.format("above=%.0f below=%.0f (mid=%d)", mid - top, bot - mid, mid))
            end
          end

          local bk, bcount = rail(fb, MIN_X, lo, hi, rule_len)
          local mk, mn = rail(fmid, MIN_X, lo, hi, rule_len)
          check("the rule holds its axis through the next slot and the cross-fade at " .. tag,
            bcount >= 6 and mn >= 6 and bk == qk and mk == qk,
            string.format("slot2 y=%s n=%d, mid-fade y=%s n=%d", tostring(bk), bcount, tostring(mk), mn))
        end
      end
    end
  end

  do
    local ms = { 1, 2, 3, 4, 5, 6 }
    local cap = Cap.capture({ scene = "pinlegend", persona = "neuro",
      moments = ms, size = { w = 1920, h = 1080 } })
    check("the pin-legend harness scene raises no draw error", (no_errors(cap)))
    local seen, n = {}, 0
    for _, t in ipairs(ms) do
      local fr = ops_of(cap, "neuro", t)
      local fy = fr and footer_rule(fr, 1920 * 0.55)
      if fy then
        for _, s in ipairs(text_on_line(fr, fy, fy + 90, 0.4)) do
          if not seen[s] then seen[s] = true; n = n + 1 end
        end
      end
    end
    check("the harness walks the whole legend deck one entry per second",
      n >= 12, string.format("%d distinct band lines over %d seconds", n, #ms))
  end

  do
    local cap = Cap.capture({ scene = "deck", persona = "neuro",
      moments = { 2.0, 7.0 }, size = { w = 1920, h = 1080 } })
    check("seed capture raises no draw error", (no_errors(cap)))
    for _, t in ipairs({ 2.0, 7.0 }) do
      local fr = ops_of(cap, "neuro", t)
      if fr then
        local rows_ = {}
        for _, line in ipairs(fr.ops) do
          local op = Cap.parse_op(line)
          if op and op.v == "T" and op.y and (op.a or 0) >= 0.4 then
            local lum = 0.2126 * (op.r or 0) + 0.7152 * (op.g or 0) + 0.0722 * (op.b or 0)
            if lum >= 0.05 then
              rows_[op.y] = (rows_[op.y] or "") .. (op.text or "")
            end
          end
        end
        local n = 0
        for _, line in pairs(rows_) do
          if line:upper():find("SEED", 1, true) then n = n + 1 end
        end
        check(string.format("the seed is on screen at most once at t=%.0f", t),
          n <= 1, string.format("%d lines mention it", n))
      end
    end
  end

  for _, res in ipairs({ { w = 1920, h = 1080 }, { w = 1280, h = 720 } }) do
    local tag = string.format("%dp", res.h)
    local MIN_X = res.w * 0.55
    local cap = Cap.capture({ scene = "shop", persona = "neuro",
      moments = { LEG_A, LEG_B }, size = res })
    check("unowned-effects capture raises no draw error at " .. tag, (no_errors(cap)))

    for _, t in ipairs({ LEG_A, LEG_B }) do
      local fr = ops_of(cap, "neuro", t)
      if fr then
        local fy, rule_len = footer_rule(fr, MIN_X)
        local lo, hi = fy or 0, (fy or 0) + band_h(res.h)
        local chip = 0
        for _, op in ipairs(fills(fr, MIN_X, lo, hi)) do
          if op.w >= 40 and op.h >= 6 and op.w < (rule_len or 0) * 0.9 then chip = chip + 1 end
        end
        check(string.format("a run owning no effects draws no pin at t=%.0f at %s", t, tag),
          fy ~= nil and chip == 0, string.format("%d chip-sized fills", chip))
        check(string.format("the band still shows the seed quip at t=%.0f at %s", t, tag),
          fy ~= nil and #text_on_line(fr, fy, fy + 90, 0.4) > 0)
      end
    end
  end
end
do
  local PERSONAS = { "neuro", "evil" }

  local function seam_rows(frame, min_x, min_pins)
    local rows = {}
    for _, line in ipairs(frame.ops) do
      local op = Cap.parse_op(line)
      if op and op.v == "R" and op.mode == "fill" and op.x and op.y and op.w and op.h then
        local k = string.format("%.0f|%.0f", op.y, op.h)
        rows[k] = rows[k] or {}
        table.insert(rows[k], op)
      end
    end
    local function has_cap(k, x, h)
      for _, o in ipairs(rows[k] or {}) do
        if o.w >= 10 and o.w <= h + 2 and o.x < x
          and o.x + o.w >= x - 1 and o.x + o.w <= x + 1 then
          return true
        end
      end
      return false
    end
    local by = {}
    for _, line in ipairs(frame.ops) do
      local op = Cap.parse_op(line)
      if op and op.v == "R" and op.mode == "fill" and op.w == 1
        and op.h and op.h >= 10 and op.h <= 24 and (op.a or 0) >= 0.5
        and op.x and op.x > min_x
        and has_cap(string.format("%.0f|%.0f", op.y, op.h), op.x, op.h) then
        local k = string.format("%.0f|%.0f", op.y, op.h)
        local g = by[k]
        if not g then g = { y = op.y, h = op.h, x0 = op.x, x1 = op.x, cols = {} }; by[k] = g end
        g.cols[#g.cols + 1] = { x = op.x, rgb = string.format("%.3f %.3f %.3f", op.r, op.g, op.b) }
        if op.x < g.x0 then g.x0 = op.x end
        if op.x > g.x1 then g.x1 = op.x end
      end
    end
    local out = {}
    for _, g in pairs(by) do
      if #g.cols >= (min_pins or 1) then
        table.sort(g.cols, function(a, b) return a.x < b.x end)
        out[#out + 1] = g
      end
    end
    table.sort(out, function(a, b) return a.y < b.y end)
    return out
  end

  local function panel_footer_y(frame, min_x)
    local y
    for _, line in ipairs(frame.ops) do
      local op = Cap.parse_op(line)
      if op and op.v == "L" and (op.a or 0) >= 0.5
        and op.n[2] and op.n[2] > min_x
        and op.n[3] and op.n[5] and op.n[3] == op.n[5]
        and op.n[4] and (op.n[4] - op.n[2]) > 100
        and (not y or op.n[3] > y) then
        y = op.n[3]
      end
    end
    return y
  end

  for _, persona in ipairs(PERSONAS) do
    for _, res in ipairs({ { w = 1920, h = 1080 }, { w = 1280, h = 720 } }) do
      local tag = string.format("%s at %dp", persona, res.h)
      local MIN_X = res.w * 0.55
      local ms = { 1.6, 2.6, 3.7, 4.7 }
      local cap = Cap.capture({ scene = "pinlegend", persona = persona,
        moments = ms, size = res })
      check("pin-legend capture raises no draw error for " .. tag, (no_errors(cap)))

      local row_hues, legend_hues, n_rows = {}, {}, 0
      for _, t in ipairs(ms) do
        local fr = ops_of(cap, persona, t)
        local fy = fr and panel_footer_y(fr, MIN_X)
        if fr and fy then
          for _, g in ipairs(seam_rows(fr, MIN_X, 2)) do
            if g.y < fy then
              n_rows = n_rows + 1
              for _, c in ipairs(g.cols) do row_hues[c.rgb] = true end
            end
          end
          for _, g in ipairs(seam_rows(fr, MIN_X, 1)) do
            if g.y > fy then
              for _, c in ipairs(g.cols) do legend_hues[c.rgb] = true end
            end
          end
        end
      end

      check("the right panel shows a multi-pin card row for " .. tag, n_rows > 0, n_rows)
      local n_leg, missing = 0, nil
      for rgb in pairs(legend_hues) do
        n_leg = n_leg + 1
        if not row_hues[rgb] then missing = missing or rgb end
      end
      local n_row = 0
      for _ in pairs(row_hues) do n_row = n_row + 1 end
      check("the footer legend teaches a colour at " .. tag, n_leg >= 1, n_leg)
      check("a card row paints a modifier the same colour the legend does for " .. tag,
        missing == nil, missing and ("legend uses " .. missing .. ", no card-row seam does"))
      if persona == "neuro" then
        check("the card row keeps one colour per modifier family at " .. tag,
          n_row >= 4, string.format("%d distinct seam colours over %d rows", n_row, n_rows))
      end
    end
  end

  local function seam_signature(fr, pick)
    local acc = {}
    for _, g in ipairs(seam_rows(fr, 0, 2)) do
      if pick(g) then
        for _, c in ipairs(g.cols) do acc[#acc + 1] = c.rgb end
      end
    end
    table.sort(acc)
    return table.concat(acc, " / "), #acc
  end

  for _, persona in ipairs(PERSONAS) do
    local W, H = 1920, 1080

    local surfaces = {}
    do
      local ms = { 1.6, 2.1, 2.6 }
      local cap = Cap.capture({ scene = "pinlegend", persona = persona,
        moments = ms, size = { w = W, h = H } })
      local rp, shop = {}, {}
      for i, t in ipairs(ms) do
        local fr = ops_of(cap, persona, t)
        local fy = fr and panel_footer_y(fr, W * 0.55) or 0
        rp[i] = fr and { seam_signature(fr, function(g) return g.x0 > W * 0.55 and g.y < fy end) }
          or { "", 0 }
        shop[i] = fr and { seam_signature(fr, function(g) return g.x1 < W * 0.45 end) } or { "", 0 }
      end
      surfaces[#surfaces + 1] = { name = "right-panel card row", f = rp }
      surfaces[#surfaces + 1] = { name = "shop row", f = shop }
    end
    do
      local ms = { 2.8, 3.0, 3.2 }
      local cap = Cap.capture({ scene = "trunc", persona = persona,
        moments = ms, size = { w = W, h = H } })
      local ts = {}
      for i, t in ipairs(ms) do
        local fr = ops_of(cap, persona, t)
        ts[i] = fr and { seam_signature(fr, function(g)
          return g.x0 > W * 0.35 and g.x1 < W * 0.68 and g.y < H * 0.4
        end) } or { "", 0 }
      end
      surfaces[#surfaces + 1] = { name = "toast", f = ts }
    end

    for _, su in ipairs(surfaces) do
      local f = su.f
      check(string.format("the %s's pins are sampled at every moment for %s", su.name, persona),
        f[1][2] >= 2 and f[1][2] == f[2][2] and f[2][2] == f[3][2],
        string.format("%d/%d/%d pins across the three moments", f[1][2], f[2][2], f[3][2]))
      check(string.format("a %s's pin colours do not change with the panel's shimmer for %s",
        su.name, persona), f[1][1] == f[2][1] and f[2][1] == f[3][1],
        string.format("first  %s\n           second %s", f[1][1], f[2][1]))
    end
  end

  for _, persona in ipairs(PERSONAS) do
    for _, res in ipairs({ { w = 960, h = 540 }, { w = 1280, h = 720 },
      { w = 1920, h = 1080 }, { w = 2560, h = 1440 } }) do
      local tag = string.format("%s at %dp", persona, res.h)
      local MIN_X = res.w * 0.55
      local cap = Cap.capture({ scene = "pinlegend", persona = persona,
        moments = { 1.6 }, size = res })
      local fr = ops_of(cap, persona, 1.6)
      local fy = fr and panel_footer_y(fr, MIN_X)
      local strip
      for _, g in ipairs(fr and fy and seam_rows(fr, MIN_X, 2) or {}) do
        if g.y < fy and not strip then strip = g end
      end
      check("the right panel draws a card-row pin strip at " .. tag, strip ~= nil)

      if strip then
        local plated = 0
        for _, line in ipairs(fr.ops) do
          local op = Cap.parse_op(line)
          if op and op.v == "R" and op.mode == "fill" and op.x and op.y and op.w and op.h
            and op.h == strip.h and op.y == strip.y
            and op.x >= strip.x0 - strip.h and op.w > strip.h then
            plated = plated + 1
          end
        end
        check("most pins on a card row carry a label, not a bare tile, at " .. tag,
          plated * 2 >= #strip.cols,
          string.format("%d of %d pins on the row are labelled", plated, #strip.cols))

        local rows_here, bottom = 0, strip.y + strip.h
        for _, g in ipairs(seam_rows(fr, MIN_X, 2)) do
          if g.y >= strip.y and g.y < strip.y + strip.h * 3 and g.h == strip.h then
            rows_here = rows_here + 1
            if g.y + g.h > bottom then bottom = g.y + g.h end
          end
        end
        local desc = 0
        for _, line in ipairs(fr.ops) do
          local op = Cap.parse_op(line)
          if op and op.v == "T" and (op.a or 0) >= 0.3 and op.x and op.y
            and op.x >= strip.x0 - strip.h and op.y >= bottom and op.y < bottom + strip.h * 2 then
            desc = desc + 1
          end
        end
        check("the card row still prints a description under its pins at " .. tag,
          desc > 0, string.format("%d glyphs below a %d-row strip", desc, rows_here))

        if res.h >= 1080 then
          check("a card row keeps its pins on one row where one row can carry labels at " .. tag,
            rows_here == 1, string.format("%d pin rows", rows_here))
        end

        local frame_bot
        for _, line in ipairs(fr.ops) do
          local op = Cap.parse_op(line)
          if op and op.v == "R" and op.mode == "line" and op.x and op.y and op.h
            and op.x > MIN_X and op.h > strip.h and op.x < strip.x0
            and op.y + op.h <= strip.y + strip.h
            and (not frame_bot or op.y + op.h > frame_bot) then
            frame_bot = op.y + op.h
          end
        end
        check("the row's card art is found at " .. tag, frame_bot ~= nil)
        if frame_bot then
          check("the pin strip never overlaps the card art at " .. tag,
            strip.y >= frame_bot, string.format("art ends %.0f, strip starts %.0f", frame_bot, strip.y))
          if res.h >= 1080 then
            check("the pin strip is led off the card art at " .. tag,
              strip.y - frame_bot >= 1,
              string.format("art ends %.0f, strip starts %.0f", frame_bot, strip.y))
          end
        end
      end
    end
  end

  for _, persona in ipairs(PERSONAS) do
    local T = 3.0
    local W, H = 1920, 1080
    local cap = Cap.capture({ scene = "trunc", persona = persona, moments = { T },
      size = { w = W, h = H } })
    check("trunc capture raises no draw error for " .. persona, (no_errors(cap)))
    local fr = ops_of(cap, persona, T)

    local box
    for _, line in ipairs(fr and fr.ops or {}) do
      local op = Cap.parse_op(line)
      if op and op.v == "R" and op.mode == "fill" and op.x and op.y and op.w and op.h
        and op.w > 150 and op.h > 60
        and (op.x + op.w / 2) > W * 0.3 and (op.x + op.w / 2) < W * 0.7
        and (not box or op.w * op.h > box.w * box.h) then
        box = op
      end
    end
    check("the toast panel is on screen for " .. persona, box ~= nil)

    local col_x
    for _, g in ipairs(fr and box and seam_rows(fr, box.x, 2) or {}) do
      if g.y > box.y and g.y < box.y + box.h and (not col_x or g.x0 < col_x) then col_x = g.x0 end
    end
    check("the toast draws a multi-pin strip for " .. persona, col_x ~= nil)

    if box and col_x then
      local top, bot
      for _, line in ipairs(fr.ops) do
        local op = Cap.parse_op(line)
        if op and op.v == "T" and (op.a or 0) >= 0.3 and op.x and op.y
          and op.x >= col_x - 6 and op.x < box.x + box.w
          and op.y > box.y and op.y < box.y + box.h then
          if not top or op.y < top then top = op.y end
          local b = op.y + (op.px or 12)
          if not bot or b > bot then bot = b end
        end
      end
      check("the toast's text column has ink for " .. persona, top ~= nil and bot ~= nil)
      if top and bot then
        local col_mid, box_mid = (top + bot) / 2, box.y + box.h / 2
        check("the toast's text column is centred in its box for " .. persona,
          math.abs(col_mid - box_mid) <= 4,
          string.format("column y %.0f..%.0f (mid %.1f) in a box y %.0f..%.0f (mid %.1f): "
            .. "%.0f above, %.0f below", top, bot, col_mid, box.y, box.y + box.h, box_mid,
            top - box.y, box.y + box.h - bot))
      end
    end
  end
end

done()
