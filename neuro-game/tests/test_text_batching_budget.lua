
local Cap = require("tests.raster_capture")
Cap.enable_mesh_capture()
Cap.enable_text_capture()
Cap.enable_canvas_capture()
local check, done = require("tests.helpers").harness("text batching budget")

local SIZE = { w = 1920, h = 1080 }
local PRINT_CEILING = 12

local n_print = 0
Cap.capture({ scene = "shop", persona = "neuro", size = SIZE, moments = { 0.1 } })
for _, op in ipairs({ "print", "printf" }) do
  local real = love.graphics[op]
  love.graphics[op] = function(...) n_print = n_print + 1; return real(...) end
end

local worst, worst_where = 0, "-"
for _, scene in ipairs({ "trunc", "shop", "overflow", "vouchers" }) do
  for _, persona in ipairs({ "neuro", "evil" }) do
    n_print = 0
    local frames = Cap.capture({ scene = scene, persona = persona, size = SIZE, moments = { 1.6 } })
    local played = math.max(1, math.floor(1.6 * Cap.FPS))
    local per_frame = n_print / played
    check(scene .. "/" .. persona .. " captures cleanly", frames[1] and not frames[1].err,
      frames[1] and frames[1].err)
    print(string.format("MEASURED  %s/%s = %.1f prints/frame", scene, persona, per_frame))
    if per_frame > worst then worst, worst_where = per_frame, scene .. "/" .. persona end
  end
end

check("no scene falls back to per-glyph text drawing", worst <= PRINT_CEILING,
  string.format("worst %.1f prints/frame at %s against a ceiling of %d",
    worst, worst_where, PRINT_CEILING))

done()
