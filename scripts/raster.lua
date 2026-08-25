

if not package.path:find("neuro-game", 1, true) then
  package.path = package.path .. ";neuro-game/?.lua;neuro-game/?/init.lua;./?.lua;../neuro-game/?.lua"
end

local Cap = require("tests.raster_capture")

local function die(msg)
  io.stderr:write("raster: ", msg, "\n")
  os.exit(2)
end

local argv = { ... }
local cmd = argv[1]

local o = {
  scene = "shop", personas = { "neuro", "evil" }, at = nil, frames = 1, span = 4.40,
  w = 1280, h = 720, out = ".raster", png = false, crop = nil,
  cols = 4, zoom = 1, budget_mb = 24, clean = false, label = nil, fps = 60, keep = 40,
  speed = nil,
}

local function split(s, sep)
  local out = {}
  for part in tostring(s):gmatch("[^" .. sep .. "]+") do out[#out + 1] = part end
  return out
end

do
  local i = (cmd == "diff") and 4 or ((cmd == "scenes") and 2 or 1)
  while i <= #argv do
    local a = argv[i]
    local function val()
      i = i + 1
      if not argv[i] then die("option " .. a .. " needs a value") end
      return argv[i]
    end
    if a == "--scene" then o.scene = val()
    elseif a == "--persona" then o.personas = split(val(), ",")
    elseif a == "--at" then
      o.at = {}
      for _, v in ipairs(split(val(), ",")) do o.at[#o.at + 1] = tonumber(v) or die("bad --at") end
    elseif a == "--frames" then o.frames = tonumber(val()) or die("bad --frames")
    elseif a == "--span" then o.span = tonumber(val()) or die("bad --span")
    elseif a == "--size" then
      local w, h = val():match("^(%d+)[xX](%d+)$")
      if not w then die("bad --size, want WxH") end
      o.w, o.h = tonumber(w), tonumber(h)
    elseif a == "--label" then o.label = val()
    elseif a == "--out" then o.out = val()
    elseif a == "--png" then o.png = true
    elseif a == "--crop" then o.crop = val()
    elseif a == "--cols" then o.cols = tonumber(val()) or 4
    elseif a == "--zoom" then o.zoom = tonumber(val()) or 1
    elseif a == "--fps" then o.fps = tonumber(val()) or 60
    elseif a == "--speed" then o.speed = val()
    elseif a == "--budget" then o.budget_mb = tonumber(val()) or 24
    elseif a == "--keep" then o.keep = tonumber(val()) or 40
    elseif a == "--clean" then o.clean = true
    elseif a == "--expect" then o.expect = val()
    elseif a == "-h" or a == "--help" then
      local src = assert(io.open("scripts/raster.lua") or io.open("../scripts/raster.lua"))
      for line in src:lines() do
        if line:sub(1, 2) ~= "--" then break end
        print((line:gsub("^%-%- ?", "")))
      end
      src:close()
      os.exit(0)
    else die("unknown option " .. tostring(a)) end
    i = i + 1
  end
end

if cmd == "scenes" then
  print("scene        label")
  for _, sc in ipairs(Cap.scenes()) do
    print(string.format("%-12s %s", sc.id, sc.label))
  end
  print("")
  print("personas: " .. table.concat(Cap.personas(), " "))
  os.exit(0)
end

local function verb_of(op) return op:match("^(%S+)") or "?" end

if cmd == "diff" then
  local pa, pb = argv[2], argv[3]
  if not (pa and pb) then die("diff needs two .ops paths") end
  local A = Cap.read_ops(pa) or die("cannot read " .. pa)
  local B = Cap.read_ops(pb) or die("cannot read " .. pb)

  local function tally(frames)
    local n, by = 0, {}
    for _, fr in ipairs(frames) do
      for _, op in ipairs(fr.ops) do
        n = n + 1
        local v = verb_of(op)
        by[v] = (by[v] or 0) + 1
      end
    end
    return n, by
  end
  local na, ba = tally(A)
  local nb, bb = tally(B)

  print(string.format("A %-40s %d frames, %d ops", pa, #A, na))
  print(string.format("B %-40s %d frames, %d ops", pb, #B, nb))
  print(string.format("delta                                      %+d ops", nb - na))

  local verbs = {}
  for v in pairs(ba) do verbs[v] = true end
  for v in pairs(bb) do verbs[v] = true end
  local vs = {}
  for v in pairs(verbs) do vs[#vs + 1] = v end
  table.sort(vs)
  local parts = {}
  for _, v in ipairs(vs) do
    local d = (bb[v] or 0) - (ba[v] or 0)
    if d ~= 0 then parts[#parts + 1] = string.format("%s%+d", v, d) end
  end
  print("by verb: " .. (#parts > 0 and table.concat(parts, "  ") or "(none)"))

  local identical = (#A == #B)
  local first
  for i = 1, math.min(#A, #B) do
    local fa, fb = A[i], B[i]
    if fa.persona ~= fb.persona or math.abs(fa.t - fb.t) > 1e-6 then identical = false end
    local m = math.max(#fa.ops, #fb.ops)
    for j = 1, m do
      if fa.ops[j] ~= fb.ops[j] then
        identical = false
        if not first then
          first = string.format("frame %d (%s t=%.2f) op #%d\n  A: %s\n  B: %s", i,
            fa.persona, fa.t, j, tostring(fa.ops[j]), tostring(fb.ops[j]))
        end
        break
      end
    end
  end
  if identical then
    print("op streams are byte-identical")
  else
    print("op streams differ" .. (first and ("\nfirst divergence: " .. first) or ""))
  end

  if o.expect == "same" then os.exit(identical and 0 or 1) end
  if o.expect == "differ" then os.exit(identical and 1 or 0) end
  os.exit(0)
end

if cmd and cmd:sub(1, 2) ~= "--" then die("unknown command '" .. cmd .. "'") end

local moments = o.at
if not moments then
  moments = {}
  if o.frames <= 1 then
    moments[1] = 1.10
  else
    for i = 0, o.frames - 1 do
      moments[#moments + 1] = 0.20 + (o.span - 0.20) * i / (o.frames - 1)
    end
  end
end

local label = o.label or table.concat({
  o.scene,
  string.format("%dx%d", o.w, o.h),
  o.speed and ("x" .. o.speed:gsub("[^%w]", "")) or nil,
}, "_")

os.execute("mkdir -p '" .. o.out .. "'")
if o.clean then os.execute("rm -f '" .. o.out .. "'/*.ops '" .. o.out .. "'/*.png") end

local all = {}
for _, persona in ipairs(o.personas) do
  local ok, frames = pcall(Cap.capture, {
    scene = o.scene, persona = persona, moments = moments,
    size = { w = o.w, h = o.h }, fps = o.fps, speed = o.speed,
  })
  if not ok then die(tostring(frames)) end
  for _, fr in ipairs(frames) do all[#all + 1] = fr end
end

local n_err, n_ops = 0, 0
for _, fr in ipairs(all) do
  n_ops = n_ops + #fr.ops
  if fr.err then n_err = n_err + 1 end
end

local est = n_ops * 64
if est > o.budget_mb * 1024 * 1024 then
  die(string.format("estimated %.1f MB of ops exceeds --budget %d MB; use fewer --frames",
    est / 1048576, o.budget_mb))
end

local ops_path = o.out .. "/" .. label .. ".ops"
local bytes, werr = Cap.write_ops(ops_path, all, {
  scene = o.scene, size = string.format("%dx%d", o.w, o.h),
  personas = table.concat(o.personas, ","),
  moments = table.concat((function()
    local s = {}
    for i, t in ipairs(moments) do s[i] = string.format("%.2f", t) end
    return s
  end)(), ","),
})
if not bytes then die("write " .. ops_path .. ": " .. tostring(werr)) end

print(string.format("raster: %s  %d frames, %d ops, %.1f KB", ops_path, #all, n_ops, bytes / 1024))
for _, fr in ipairs(all) do
  if fr.err then
    io.stderr:write(string.format("raster: DRAW ERROR %s t=%.2f\n%s\n", fr.persona, fr.t, fr.err))
  end
end

if o.png then
  local py_path = (io.open("scripts/raster_png.py") and "scripts/raster_png.py") or "../scripts/raster_png.py"
  local cmdline = { "python3", py_path, "'" .. ops_path .. "'",
    "'" .. o.out .. "/" .. label .. "'" }
  if o.crop then cmdline[#cmdline + 1] = "--crop " .. o.crop end
  cmdline[#cmdline + 1] = "--cols " .. tostring(o.cols)
  cmdline[#cmdline + 1] = "--zoom " .. tostring(o.zoom)
  local rc = os.execute(table.concat(cmdline, " "))
  if type(rc) == "boolean" then rc = rc and 0 or 1 end
  if rc == 3 * 256 or rc == 3 then
    print("raster: PNG skipped (Pillow not installed) -- the op log above is complete")
  elseif rc ~= 0 then
    io.stderr:write("raster: PNG step failed (rc=" .. tostring(rc) .. ")\n")
    os.exit(1)
  end
end

do
  local pipe = io.popen("ls -1t '" .. o.out .. "' 2>/dev/null")
  if pipe then
    local names = {}
    for name in pipe:lines() do names[#names + 1] = name end
    pipe:close()
    for i = o.keep + 1, #names do os.remove(o.out .. "/" .. names[i]) end
    if #names > o.keep then
      print(string.format("raster: pruned %d old artifact(s) from %s (--keep %d)",
        #names - o.keep, o.out, o.keep))
    end
  end
end

os.exit(n_err == 0 and 0 or 1)
