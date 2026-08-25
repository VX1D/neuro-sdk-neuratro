local M = {}

local FactHints = require("facts.fact_hints")
local H = require("tests.helpers")

local PREFIX_KIND = {
  hint = "state", dhint = "decision", shint = "session",
  ahint = "ante", rdhint = "round", rhint = "run",
}

function M.parse_key(key, epoch)
  local rec = { key = key, epoch = epoch }
  local prefix, rest = tostring(key):match("^(%a+):(.*)$")
  rec.kind = prefix and PREFIX_KIND[prefix]
  if not rec.kind then return rec end
  local tag, sig = rest:match("^([^:]*):(.*)$")
  rec.tag, rec.sig = tag or rest, sig
  if rec.kind == "ante" then
    rec.ante = tonumber(sig)
  elseif rec.kind == "round" then
    rec.round = tostring(sig or ""):match("^(%d+)$")
  end
  return rec
end

local function stores()
  local N = (G and G.NEURO) or {}
  return { N.once_serials, N.session_once_serials }
end

function M.snapshot()
  local o = {}
  for _, s in ipairs(stores()) do
    for k, v in pairs(s or {}) do o[k] = v end
  end
  return o
end

function M.booked_since(before)
  local out = {}
  for _, s in ipairs(stores()) do
    for k, v in pairs(s or {}) do
      if before[k] == nil then out[#out + 1] = M.parse_key(k, v) end
    end
  end
  table.sort(out, function(a, b) return a.key < b.key end)
  return out
end

function M.capture(build)
  local before = M.snapshot()
  FactHints.reset_pending()
  local res = build()
  local text = H.drain_hints()
  local booked = M.booked_since(before)
  local by_tag = {}
  for _, rec in ipairs(booked) do by_tag[rec.tag or rec.key] = rec end
  return { query = (type(res) == "table" and res.query) or "", text = text,
    booked = booked, by_tag = by_tag }
end

function M.isolate(frame, tag)
  local full, rest = frame(), frame(tag)
  local i = 1
  while i <= #full and i <= #rest and full:byte(i) == rest:byte(i) do i = i + 1 end
  local j = 0
  while #full - j >= i and #rest - j >= i
    and full:byte(#full - j) == rest:byte(#rest - j) do j = j + 1 end
  return full:sub(i, #full - j)
end

function M.numbered_points(text)
  local marks, pos = {}, 1
  while true do
    local s, e, n = tostring(text):find("(%d+)%)", pos)
    if not s then break end
    marks[#marks + 1] = { n = tonumber(n), s = s, e = e }
    pos = e + 1
  end
  local order, clause = {}, {}
  for i, m in ipairs(marks) do
    local stop = marks[i + 1] and (marks[i + 1].s - 1) or #text
    order[#order + 1] = m.n
    clause[m.n] = tostring(text):sub(m.e + 1, stop)
  end
  return order, clause
end

function M.numbering_faults(text)
  local order = M.numbered_points(text)
  local faults = {}
  if #order == 0 then
    faults[#faults + 1] = "no numbered point in the block"
    return faults
  end
  for i, n in ipairs(order) do
    if n ~= i then
      faults[#faults + 1] = string.format("point %d appears where point %d should", n, i)
    end
  end
  return faults
end

local RESOURCES = { "discard", "hand", "joker", "chip", "mult", "blind", "voucher", "consumable" }

function M.resources(text)
  local set, low = {}, tostring(text):lower()
  for _, r in ipairs(RESOURCES) do
    if low:find(r, 1, true) then set[r] = true end
  end
  return set
end

function M.point_references(text)
  local out = {}
  for sentence in tostring(text):gmatch("[^.]+%.") do
    local n = sentence:match("point (%d+)")
    if n then out[#out + 1] = { n = tonumber(n), sentence = sentence } end
  end
  return out
end

function M.correction_faults(block, correction)
  local faults = {}
  local _, clause = M.numbered_points(block)
  local refs = M.point_references(correction)
  if #refs == 0 then
    faults[#faults + 1] = "the correction retires no numbered point"
    return faults
  end
  for _, ref in ipairs(refs) do
    local target = clause[ref.n]
    if not target then
      faults[#faults + 1] = string.format("point %d is not in the block it corrects", ref.n)
    else
      local have = M.resources(target)
      for r in pairs(M.resources(ref.sentence)) do
        if not have[r] then
          faults[#faults + 1] = string.format("point %d says nothing about %ss", ref.n, r)
        end
      end
    end
  end
  return faults
end

function M.ambiguity_faults(blocks, correction)
  local refs = M.point_references(correction)
  local hits = {}
  for i, block in ipairs(blocks) do
    local _, clause = M.numbered_points(block)
    local answers = true
    for _, ref in ipairs(refs) do
      if not clause[ref.n] then answers = false end
    end
    if answers then hits[#hits + 1] = "block #" .. i end
  end
  if #hits == 1 then return {} end
  if #hits == 0 then
    return { "the correction answers to none of the " .. #blocks .. " standing blocks" }
  end
  return { "the correction answers to " .. #hits .. " standing blocks at once: "
    .. table.concat(hits, ", ") }
end

function M.same_frame_faults(frame, block_tag, correction_tag)
  local correction = M.isolate(frame, correction_tag)
  if correction == "" then return {} end
  return M.correction_faults(M.isolate(frame, block_tag), correction)
end

return M
