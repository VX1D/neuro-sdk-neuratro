local M = {}

local Registry = require("core.action_registry")

local BANNED = { ":integer", ":array", "array[", ">=", ":unique", ":number", ":string", ":boolean" }

local PINNED_PROSE = {
  ["{primary=an exact visible hand name, fallback=another visible hand name}"] = true,
}

local FIELD_PREFIXES = { '"plan":', "plan=" }

local function notation_violation(body)
  if body:find(":%s*[ijN][,}%]]") then return "bare i/j/N token" end
  if body:find("%[%s*[ijN]%s*,") then return "bare token inside an array" end
  if body:gsub("<[^>]*>", "0"):find("[{,]%s*[%a_]") then return "unquoted key" end
  for _, kw in ipairs(BANNED) do
    if body:find(kw, 1, true) then return "schema-keyword notation (" .. kw .. ")" end
  end
  return nil
end
M.notation_violation = notation_violation

local function top_level_groups(msg)
  local out, depth, start = {}, 0, nil
  for i = 1, #msg do
    local c = msg:sub(i, i)
    if c == "{" then
      if depth == 0 then start = i end
      depth = depth + 1
    elseif c == "}" and depth > 0 then
      depth = depth - 1
      if depth == 0 and start then
        out[#out + 1] = { text = msg:sub(start, i), at = start,
          prefix = msg:sub(math.max(1, start - 40), start - 1) }
        start = nil
      end
    end
  end
  return out
end

local function is_field(prefix)
  for _, p in ipairs(FIELD_PREFIXES) do
    if prefix:sub(-#p) == p then return true end
  end
  return false
end

local function top_keys(body)
  local flat = body:sub(2, -2)
  local prev
  repeat
    prev = flat
    flat = flat:gsub("%b{}", ""):gsub("%b[]", ""):gsub("%b<>", "")
  until flat == prev
  local out = {}
  for key in flat:gmatch('"([%w_]+)"%s*:') do out[#out + 1] = key end
  return out
end

local function order_index(list)
  local idx = {}
  for i, k in ipairs(list) do idx[k] = i end
  return idx
end

function M.audit(label, msg)
  local IS_NAME = {}
  for _, n in ipairs(Registry.names()) do IS_NAME[n] = true end
  local bad, groups_seen, per_name = {}, 0, {}
  for _, kw in ipairs(BANNED) do
    local at = msg:find(kw, 1, true)
    if at then
      bad[#bad + 1] = label .. ": schema-keyword notation on the wire -- " .. kw
        .. " in ..." .. msg:sub(math.max(1, at - 60), at + 40) .. "..."
    end
  end
  for _, g in ipairs(top_level_groups(msg)) do
    groups_seen = groups_seen + 1
    local name = g.prefix:match("([%w_]+)|$")
    name = (name and IS_NAME[name]) and name or nil
    if name then
      per_name[name] = (per_name[name] or 0) + 1
      local v = notation_violation(g.text)
      if v then bad[#bad + 1] = label .. ": " .. name .. " payload -- " .. v .. " in " .. g.text end
      local prompt = Registry.prompt(name) or ""
      local canon = prompt:gsub(", optional>", ">")
      for ph in g.text:gmatch("%b<>") do
        if not canon:find((ph:gsub(", optional>", ">")), 1, true) then
          bad[#bad + 1] = label .. ": " .. name .. " is shown placeholder " .. ph
            .. " that core/action_registry.lua never renders -- " .. prompt
        end
      end
      local want = order_index(top_keys(prompt:match("|(%b{})") or "{}"))
      local last = 0
      for _, key in ipairs(top_keys(g.text)) do
        local at = want[key]
        if not at then
          bad[#bad + 1] = label .. ": " .. name .. " payload states key " .. string.format("%q", key)
            .. " the registry contract does not have -- " .. g.text
        elseif at < last then
          bad[#bad + 1] = label .. ": " .. name .. " payload reorders the contract's keys -- " .. g.text
        else
          last = at
        end
      end
    elseif is_field(g.prefix) then
      local v = notation_violation(g.text)
      if v then bad[#bad + 1] = label .. ": plan field -- " .. v .. " in " .. g.text end
    elseif not PINNED_PROSE[g.text] then
      bad[#bad + 1] = label .. ": hand-written object on the wire, attached to no action -- "
        .. string.format("%q", g.prefix:sub(-30)) .. " >> " .. g.text
    end
  end
  return bad, groups_seen, per_name
end

return M
