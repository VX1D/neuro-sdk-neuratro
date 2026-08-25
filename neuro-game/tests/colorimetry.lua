local C = {}

C.SDR_REFERENCE_NITS = 100

local M1 = 2610 / 16384
local M2 = 2523 / 4096 * 128
local K1 = 3424 / 4096
local K2 = 2413 / 4096 * 32
local K3 = 2392 / 4096 * 32

local function srgb_to_linear(v)
  if v <= 0.04045 then return v / 12.92 end
  return ((v + 0.055) / 1.055) ^ 2.4
end

local function linear_to_srgb(v)
  if v <= 0 then return 0 end
  if v <= 0.0031308 then return v * 12.92 end
  local o = 1.055 * v ^ (1 / 2.4) - 0.055
  if o > 1 then return 1 end
  return o
end

local function pq_encode(y)
  if y <= 0 then return 0 end
  local n = (y / 10000) ^ M1
  return ((K1 + K2 * n) / (1 + K3 * n)) ^ M2
end

function C.to_ictcp(rgb, nits)
  nits = nits or C.SDR_REFERENCE_NITS
  local r = srgb_to_linear(rgb[1])
  local g = srgb_to_linear(rgb[2])
  local b = srgb_to_linear(rgb[3])
  local X = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b
  local Y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
  local Z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b
  local r2 =  1.7166512 * X - 0.3556708 * Y - 0.2533663 * Z
  local g2 = -0.6666844 * X + 1.6164812 * Y + 0.0157685 * Z
  local b2 =  0.0176399 * X - 0.0427706 * Y + 0.9421031 * Z
  if r2 < 0 then r2 = 0 end
  if g2 < 0 then g2 = 0 end
  if b2 < 0 then b2 = 0 end
  local L = (1688 * r2 + 2146 * g2 + 262 * b2) / 4096 * nits
  local Ms = (683 * r2 + 2951 * g2 + 462 * b2) / 4096 * nits
  local S = (99 * r2 + 309 * g2 + 3688 * b2) / 4096 * nits
  local Lp, Mp, Sp = pq_encode(L), pq_encode(Ms), pq_encode(S)
  local I = 0.5 * Lp + 0.5 * Mp
  local Ct = (6610 * Lp - 13613 * Mp + 7003 * Sp) / 4096
  local Cp = (17933 * Lp - 17390 * Mp - 543 * Sp) / 4096
  return I, Ct, Cp
end

function C.delta_itp(a, b, nits)
  local I1, Ct1, Cp1 = C.to_ictcp(a, nits)
  local I2, Ct2, Cp2 = C.to_ictcp(b, nits)
  local dI = I2 - I1
  local dCt = 0.5 * (Ct2 - Ct1)
  local dCp = Cp2 - Cp1
  local total = 720 * math.sqrt(dI * dI + dCt * dCt + dCp * dCp)
  local intensity = 720 * math.abs(dI)
  local chroma = 720 * math.sqrt(dCt * dCt + dCp * dCp)
  return total, intensity, chroma
end

function C.delta_e_itp(a, b, nits)
  local total = C.delta_itp(a, b, nits)
  return total
end

function C.delta_i_itp(a, b, nits)
  local _, intensity = C.delta_itp(a, b, nits)
  return intensity
end

local function to_ycbcr(px)
  local r, g, b = px[1], px[2], px[3]
  local y = 0.2126 * r + 0.7152 * g + 0.0722 * b
  return y, (b - y) / 1.8556, (r - y) / 1.5748
end

local function from_ycbcr(y, cb, cr)
  local r = y + 1.5748 * cr
  local g = y - 0.1873 * cb - 0.4681 * cr
  local b = y + 1.8556 * cb
  if r < 0 then r = 0 elseif r > 1 then r = 1 end
  if g < 0 then g = 0 elseif g > 1 then g = 1 end
  if b < 0 then b = 0 elseif b > 1 then b = 1 end
  return { r, g, b }
end

function C.chroma_subsample(img, w, h)
  local y, cb, cr = {}, {}, {}
  for i = 1, w * h do
    y[i], cb[i], cr[i] = to_ycbcr(img[i])
  end
  local out = {}
  for by = 0, math.ceil(h / 2) - 1 do
    for bx = 0, math.ceil(w / 2) - 1 do
      local sb, sr, n = 0, 0, 0
      for dy = 0, 1 do
        for dx = 0, 1 do
          local px, py = bx * 2 + dx, by * 2 + dy
          if px < w and py < h then
            local i = py * w + px + 1
            sb, sr, n = sb + cb[i], sr + cr[i], n + 1
          end
        end
      end
      sb, sr = sb / n, sr / n
      for dy = 0, 1 do
        for dx = 0, 1 do
          local px, py = bx * 2 + dx, by * 2 + dy
          if px < w and py < h then
            local i = py * w + px + 1
            out[i] = from_ycbcr(y[i], sb, sr)
          end
        end
      end
    end
  end
  return out
end

function C.over_alpha(src, alpha, bg)
  return {
    bg[1] * (1 - alpha) + src[1] * alpha,
    bg[2] * (1 - alpha) + src[2] * alpha,
    bg[3] * (1 - alpha) + src[3] * alpha,
  }
end

function C.over_add(src, alpha, bg)
  local o = {}
  for i = 1, 3 do
    local v = bg[i] + src[i] * alpha
    o[i] = v > 1 and 1 or v
  end
  return o
end

function C.linear_to_srgb(v) return linear_to_srgb(v) end
function C.srgb_to_linear(v) return srgb_to_linear(v) end

return C
