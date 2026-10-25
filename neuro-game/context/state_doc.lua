local M = {}

local function item(line)
  if line:find("^%- ") or line:find("^%s") or line:find("^%d+%. ") then return line end
  return "- " .. line
end

function M.render(blocks)
  local order, body = {}, {}
  local function open(heading)
    if not body[heading] then
      body[heading] = {}
      order[#order + 1] = heading
    end
    return body[heading]
  end
  for _, block in ipairs(blocks or {}) do
    local heading = block.heading
    if heading then open(heading) end
    for line in (tostring(block.text or "") .. "\n"):gmatch("([^\n]*)\n") do
      line = line:gsub("%s+$", "")
      local opened = line:match("^## (.+)$")
      if opened then
        heading = opened
      elseif line ~= "" then
        heading = heading or "Game"
        local lines = open(heading)
        lines[#lines + 1] = item(line)
      end
    end
  end
  local out = {}
  for _, heading in ipairs(order) do
    if #body[heading] > 0 then out[#out + 1] = "## " .. heading .. "\n" .. table.concat(body[heading], "\n") end
  end
  return table.concat(out, "\n")
end

function M.lines(...)
  local out = {}
  for i = 1, select("#", ...) do
    local text = select(i, ...)
    if type(text) == "string" and text:find("%S") then out[#out + 1] = text end
  end
  return table.concat(out, "\n")
end

function M.section(heading, text)
  if type(text) ~= "string" or not text:find("%S") then return "" end
  return "## " .. heading .. "\n" .. text
end

return M
