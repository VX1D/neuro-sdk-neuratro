

local Cap = require("tests.raster_capture")
Cap.enable_mesh_capture()
local check, done = require("tests.helpers").harness("draw budget")

local SIZE = { w = 1920, h = 1080 }

local CEILING = {
  neuro  = { shop = 1370, trunc = 1730, vouchers = 1360, overflow = 1460, pinlegend = 1510 },
  evil   = { shop = 1010, trunc = 1370, vouchers = 1000, overflow = 1000, pinlegend = 1050 },
  hiyori = { shop = 630,  trunc = 940,  vouchers = 625,  overflow = 685,  pinlegend = 755 },
}

local function frame_ops(scene, persona)
  local frames = Cap.capture({ scene = scene, persona = persona, size = SIZE, moments = { 1.6 } })
  if frames[1].err then return nil, frames[1].err end
  local n = 0
  for _, line in ipairs(frames[1].ops) do
    if Cap.parse_op(line) then n = n + 1 end
  end
  return n
end

for persona, scenes in pairs(CEILING) do
  for scene, ceiling in pairs(scenes) do
    local n, err = frame_ops(scene, persona)
    if n then print(string.format("MEASURED  %s/%s = %d ops", scene, persona, n)) end
    check(scene .. "/" .. persona .. " captures cleanly", n ~= nil, err)
    if n then
      check(scene .. "/" .. persona .. " stays inside its draw budget", n <= ceiling,
        n .. " ops against a ceiling of " .. ceiling)
    end
  end
end

local SETCOLOR_CEILING = { neuro = 80000, evil = 88000 }

do
  local n_draw, n_set = 0, 0
  Cap.capture({ scene = "shop", persona = "neuro", size = SIZE, moments = { 0.1 } })
  for _, op in ipairs({ "rectangle", "arc", "circle", "polygon", "line", "ellipse", "draw" }) do
    local real = love.graphics[op]
    love.graphics[op] = function(...) n_draw = n_draw + 1; return real(...) end
  end
  local real_set = love.graphics.setColor
  love.graphics.setColor = function(...) n_set = n_set + 1; return real_set(...) end

  for _, persona in ipairs({ "neuro", "evil" }) do
    n_draw, n_set = 0, 0
    Cap.capture({ scene = "trunc", persona = persona, size = SIZE, moments = { 1.6 } })
    print(string.format("MEASURED  trunc/%s = %d setColor (%d draws, %.4f per draw)",
      persona, n_set, n_draw, n_set / math.max(1, n_draw)))
    check("trunc/" .. persona .. " stays inside its colour-change budget",
      n_set <= SETCOLOR_CEILING[persona],
      string.format("%d setColor against a ceiling of %d (%d draws)",
        n_set, SETCOLOR_CEILING[persona], n_draw))
  end
end

done()
