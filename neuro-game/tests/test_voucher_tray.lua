

local Drive = require("tests.raster_drive")
local Cap = Drive.Cap
local check, done = require("tests.helpers").harness("voucher tray")

local S = require("hud.state")
local Showcase = require("hud.showcase")
local HudShared = require("render.hud_shared")

local PERIOD = HudShared.CAROUSEL_PERIOD
local SIZE = { w = 1280, h = 720 }
local DT = 1 / 60

local TRAY_X = 1000
local TITLE = "VOUCHERS"

local function header_y(frame)
  local glyph_rows = {}
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "T" and op.text and op.x and op.x > TRAY_X and op.y and (op.a or 0) > 0.30 then
      if op.text == TITLE then return op.y end
      if #op.text == 1 then
        local row = glyph_rows[op.y]
        if not row then row = {}; glyph_rows[op.y] = row end
        row[#row + 1] = op
      end
    end
  end
  for y, row in pairs(glyph_rows) do
    table.sort(row, function(a, b) return a.x < b.x end)
    local glyphs = {}
    for i = 1, #row do glyphs[i] = row[i].text end
    if table.concat(glyphs):find(TITLE, 1, true) then return y end
  end
  return nil
end

local function tray_rows(frame)
  local hy = header_y(frame)
  if not hy then return "" end
  local seen = {}
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "T" and op.text and op.text ~= "" and op.x and op.x > TRAY_X
      and op.y and op.y > hy + 10 and (op.a or 0) > 0.30 then
      seen[op.text] = true
    end
  end
  local out = {}
  for text in pairs(seen) do out[#out + 1] = text end
  table.sort(out)
  return table.concat(out, "|")
end

local function tray_held(frame)
  local hy = header_y(frame)
  if not hy then return nil end
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "T" and op.text and op.x and op.x > TRAY_X and op.y
      and math.abs(op.y - hy) <= 4 and (op.a or 0) > 0.30 then
      local held = op.text:match("^%d+/(%d+)$")
      if held then return tonumber(held) end
    end
  end
  return nil
end

do
  local card, retire_t
  local frames = Drive.play({
    scene = "vouchers", persona = "hiyori", size = SIZE, span = 7.0, from = 0,
    on_frame = function(t)
      if not card then
        local _, gv = next(S.voucher_drawer_gate or {})
        card = gv and gv.card
      end
      if card and not retire_t and not Showcase.card_in_flight(card) then retire_t = t end
    end,
  })
  check("1 captures cleanly", Drive.errors(frames) == nil, Drive.errors(frames))
  check("1a the corridor retires the redeemed card mid-take", retire_t ~= nil, tostring(retire_t))

  local grew_t
  for _, fr in ipairs(frames) do
    local held = tray_held(fr)
    if held and held >= 3 then grew_t = fr.t break end
  end
  check("1b the tray does grow a row for the redemption", grew_t ~= nil, tostring(grew_t))
  check("1c and never before the corridor published the hand-off",
    grew_t ~= nil and retire_t ~= nil and grew_t >= retire_t - 2 * DT,
    string.format("drawn at %.4f, published at %.4f", grew_t or -1, retire_t or -1))
end

do
  local settled = {}
  local frames = Drive.play({
    scene = "slots", persona = "hiyori", size = SIZE, span = 3.6, from = 0,
    on_frame = function() settled[#settled + 1] = (S.drawer_slide_current or 0) > 0.999 end,
  })
  check("2 captures cleanly", Drive.errors(frames) == nil, Drive.errors(frames))
  local first, change_t
  for i, fr in ipairs(frames) do
    if settled[i] then
      local rows = tray_rows(fr)
      if rows ~= "" then
        if not first then first = rows
        elseif rows ~= first then change_t = fr.t break end
      end
    end
  end
  check("2a the tray rotates within the take", change_t ~= nil, tostring(change_t))
  check("2b the first row of a run is drawn for a whole dwell",
    change_t ~= nil and change_t >= PERIOD - 3 * DT,
    string.format("%.4f of %.4f", change_t or -1, PERIOD))
end

do
  local pinned, idx, seeded_at = {}, {}, {}
  local frames = Drive.play({
    scene = "vouchers", persona = "hiyori", size = SIZE, span = 18.0, from = 0,
    on_frame = function()
      pinned[#pinned + 1] = (S.voucher_rot_hold_until or 0) - G.TIMERS.REAL
      idx[#idx + 1] = S.voucher_rot_idx
      seeded_at[#seeded_at + 1] = S.known_voucher_keys == nil
    end,
  })
  check("3 captures cleanly", Drive.errors(frames) == nil, Drive.errors(frames))

  local reseed_i
  for i = 2, #frames do
    if frames[i].t > 8.0 and seeded_at[i] then reseed_i = i break end
  end
  check("3a the shelf is seeded again mid-play", reseed_i ~= nil, tostring(reseed_i))
  check("3b with a pin from the previous shelf still live at that instant",
    reseed_i ~= nil and (pinned[reseed_i] or -1) > 0,
    reseed_i and string.format("%.4f", pinned[reseed_i] or -1))
  check("3c the pin does not survive the shelf that carried its row",
    reseed_i ~= nil and (pinned[reseed_i + 1] or 1) <= 0 and (idx[reseed_i + 1] or 0) == 1,
    reseed_i and string.format("hold %.4f, idx %s", pinned[reseed_i + 1] or -1,
      tostring(idx[reseed_i + 1])))

  local base, seed_t, change_t
  for i = reseed_i or #frames, #frames do
    local rows = tray_rows(frames[i])
    if rows ~= "" and (tray_held(frames[i]) or 0) == 2 then
      if not base then base, seed_t = rows, frames[i].t
      elseif rows ~= base then change_t = frames[i].t - seed_t break end
    end
  end
  check("3d the tray rotates again after the reseed", change_t ~= nil, tostring(change_t))
  check("3e and the reseeded shelf's first row is drawn for a whole dwell",
    change_t ~= nil and change_t >= PERIOD - 3 * DT,
    string.format("%.4f of %.4f", change_t or -1, PERIOD))
end

done()
