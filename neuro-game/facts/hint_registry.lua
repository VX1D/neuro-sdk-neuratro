local M = {}

local ENTRIES = {
  { tag = "voucher_chain:", prefix = true, cadence = "session" },
  { tag = "voucher_basics_run", cadence = "session" },
  { tag = "hand_base_values:", prefix = true, cadence = "session" },
}

local by_tag, prefixes = {}, {}
for _, e in ipairs(ENTRIES) do
  if e.prefix then prefixes[#prefixes + 1] = e else by_tag[e.tag] = e end
end
table.sort(prefixes, function(a, b) return #a.tag > #b.tag end)

function M.lookup(tag)
  tag = tostring(tag or "")
  local exact = by_tag[tag]
  if exact then return exact end
  for _, e in ipairs(prefixes) do
    if tag:sub(1, #e.tag) == e.tag then return e end
  end
  return nil
end

return M
