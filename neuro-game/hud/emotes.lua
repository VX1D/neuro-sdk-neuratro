local Emotes = {}

local S = require("hud.state")
local Paths = require("core.mod_paths")
local Utils = require("util.utils")

local neuro_log = Utils.neuro_log

local function panel_emote_path(name, ext)
  return Paths.mod_relative("assets/" .. name .. "." .. ext)
end

function Emotes.get(name)
  if not name or name == "" then return nil end
  local cached = S.panel_emote_cache[name]
  if cached ~= nil then
    return (cached ~= false) and cached or nil
  end
  if (S.panel_emote_attempts[name] or 0) >= 3 then
    S.panel_emote_cache[name] = false
    return nil
  end
  S.panel_emote_attempts[name] = (S.panel_emote_attempts[name] or 0) + 1

  local sheet_path = panel_emote_path(name .. "_sheet", "png")
  local meta_path = panel_emote_path(name .. "_sheet", "meta")
  local sheet_ok, sheet_img = pcall(love.graphics.newImage, sheet_path)
  if sheet_ok and sheet_img then
    local sw, sh = sheet_img:getWidth(), sheet_img:getHeight()
    local n, fw, fh, fps
    local meta_ok, meta_data = pcall(love.filesystem.read, meta_path)
    if meta_ok and meta_data then
      n, fw, fh, fps = meta_data:match("(%d+),(%d+),(%d+),([%d%.]+)")
      n = tonumber(n) or 1
      fw = tonumber(fw) or 128
      fh = tonumber(fh) or 128
      fps = tonumber(fps) or 10
    elseif sh > 0 and sw % sh == 0 then
      fh, fw = sh, sh
      n = math.max(1, math.floor(sw / sh))
      fps = 10
    else
      fh, fw = sh, sw
      n = 1
      fps = 0
    end
    local quads = {}
    for i = 0, n - 1 do
      quads[#quads + 1] = love.graphics.newQuad(i * fw, 0, fw, fh, sw, sh)
    end
    local emote = { img = sheet_img, quads = quads, fps = fps, n_frames = n, fw = fw, fh = fh }
    S.panel_emote_cache[name] = emote
    neuro_log("Loaded animated emote:", name, "(" .. n .. " frames, " .. fps .. " fps)")
    return emote
  end

  local exts = { "png", "gif", "jpg", "jpeg", "webp" }
  for _, ext in ipairs(exts) do
    local p = panel_emote_path(name, ext)
    local ok, img = pcall(love.graphics.newImage, p)
    if ok and img then
      local emote = { img = img, quads = nil, fps = 0, n_frames = 1, fw = img:getWidth(), fh = img:getHeight() }
      S.panel_emote_cache[name] = emote
      return emote
    end
  end

  return nil
end

function Emotes.pick_footer(persona_key, state_name)
  if persona_key == "hiyori" then return "hiyori" end

  if persona_key == "evil" then
    if state_name == "ROUND_EVAL" then return "boomevil" end
    if state_name == "SHOP" then return "evilgamba" end
    return nil
  end

  if state_name == "ROUND_EVAL" then return "neuroexplode" end
  return "neurocube"
end

return Emotes
