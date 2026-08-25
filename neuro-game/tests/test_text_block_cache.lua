

local Cap = require("tests.raster_capture")
Cap.enable_text_capture()
local check, done = require("tests.helpers").harness("text block cache")

local Prims = require("hud.prims")

local SIZE = { w = 1280, h = 720 }
local DRAW_ENTRIES = {
  "rectangle", "circle", "ellipse", "arc", "line", "polygon", "points", "print", "printf", "draw",
}

local SCENES = { "shop", "trunc", "vouchers", "toasts", "buyuse", "pack2", "deck", "blindselect" }
local PERSONAS = { "neuro", "evil", "hiyori" }
local MOMENTS = { 0.4, 1.6, 2.4 }

local function capture_with_calls(enabled, scene, persona)
  local saved_new_text = love.graphics.newText
  if not enabled then love.graphics.newText = false end
  local calls, saved = 0, {}
  for _, name in ipairs(DRAW_ENTRIES) do
    local real = love.graphics[name]
    saved[name] = real
    love.graphics[name] = function(...)
      if Cap.rec.enabled then calls = calls + 1 end
      return real(...)
    end
  end
  local frames = Cap.capture({ scene = scene, persona = persona, size = SIZE, moments = MOMENTS })
  for _, name in ipairs(DRAW_ENTRIES) do love.graphics[name] = saved[name] end
  love.graphics.newText = saved_new_text
  return frames, calls
end

local function same_frames(a, b)
  if #a ~= #b then return false, "frame count" end
  for i = 1, #a do
    if a[i].err or b[i].err then return false, a[i].err or b[i].err end
    if #a[i].ops ~= #b[i].ops then
      return false, string.format("frame %d op count %d/%d", i, #a[i].ops, #b[i].ops)
    end
    for j = 1, #a[i].ops do
      if a[i].ops[j] ~= b[i].ops[j] then
        return false, string.format("frame %d op %d\n%s\n%s", i, j, a[i].ops[j], b[i].ops[j])
      end
    end
  end
  return true
end

local worst_same, worst_err = true, nil
local total_fallback, total_cached, never_dearer, dearer_at = 0, 0, true, nil
for _, scene in ipairs(SCENES) do
  for _, persona in ipairs(PERSONAS) do
    local fallback, fallback_calls = capture_with_calls(false, scene, persona)
    local cached, cached_calls = capture_with_calls(true, scene, persona)
    local same, err = same_frames(fallback, cached)
    if not same and worst_same then
      worst_same, worst_err = false, scene .. "/" .. persona .. " " .. tostring(err)
    end
    total_fallback, total_cached = total_fallback + fallback_calls, total_cached + cached_calls
    if cached_calls > fallback_calls and never_dearer then
      never_dearer = false
      dearer_at = string.format("%s/%s cached=%d fallback=%d", scene, persona, cached_calls,
        fallback_calls)
    end
  end
end
check("Text replay is byte-identical to the print op stream in every scene", worst_same, worst_err)
check("no scene costs more draw calls than the print path", never_dearer, dearer_at)
check("the caches actually remove calls", total_cached < total_fallback,
  string.format("cached=%d fallback=%d", total_cached, total_fallback))
print(string.format("MEASURED  draw entry calls %d -> %d over %d scene/persona captures",
  total_fallback, total_cached, #SCENES * #PERSONAS))

local font = Cap.mkfont(12)
local fixed = {
  font = font, track = 1,
  shadow_color = { 0, 0, 0 }, main_color = { 0.2, 0.4, 0.6 },
  shadow_alpha = 0.5, main_alpha = 0.95, shadow_dx = 1, shadow_dy = 1, tint_alpha = 0.5,
}

Cap.rec.reset()
love.graphics.setFont(font)
love.graphics.setColor(0, 0, 0, 0.25)
Prims.print_tracked("ABC", 11, 21, 1, font)
love.graphics.setColor(0.2, 0.4, 0.6, 0.475)
Prims.print_tracked("ABC", 10, 20, 1, font)
local alpha_fallback = Cap.rec.take()
Cap.rec.reset()
Prims.draw_cached_tracked_text({}, "alpha", "ABC", 10, 20, fixed)
local alpha_cached = Cap.rec.take()
local alpha_same, alpha_err = same_frames({ { ops = alpha_fallback } }, { { ops = alpha_cached } })
check("shadow and face adds reproduce alpha through the draw tint", alpha_same, alpha_err)
fixed.dynamic_position = true
Cap.rec.reset()
love.graphics.setColor(0, 0, 0, 0.25)
Prims.print_tracked("ABC", 34, 48, 1, font)
love.graphics.setColor(0.2, 0.4, 0.6, 0.475)
Prims.print_tracked("ABC", 33, 47, 1, font)
local moved_fallback = Cap.rec.take()
Cap.rec.reset()
local moved_batch = {}
Prims.draw_cached_tracked_text(moved_batch, "dynamic-pos", "ABC", 10, 20, fixed)
Cap.rec.take()
local moved_ok = Prims.draw_cached_tracked_text(moved_batch, "dynamic-pos", "ABC", 33, 47, fixed)
local moved_cached = Cap.rec.take()
local moved_same, moved_err = same_frames({ { ops = moved_fallback } }, { { ops = moved_cached } })
check("an animated position replays one block at the new x, y", moved_ok and moved_same, moved_err)
fixed.dynamic_position, fixed.dynamic_color = false, true
check("animated colours select print fallback",
  not Prims.draw_cached_tracked_text({}, "dynamic-col", "ABC", 0, 0, fixed))
fixed.dynamic_color = false
check("unsupported non-ASCII tracking selects print fallback",
  not Prims.draw_cached_tracked_text({}, "unicode", "VOUCHÉ", 0, 0, fixed))

done()
