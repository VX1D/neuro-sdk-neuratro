local M = {}

local function move(name)
  return (require("core.action_registry").phrase(name):gsub("^%u", string.lower))
end

function M.withheld(name, condition)
  return "That move (" .. move(name) .. ") is off the list until " .. condition
end

function M.settling_note(accepted, settling)
  local function moves(names)
    local out = {}
    for i, name in ipairs(names) do out[i] = move(name) end
    return table.concat(out, ", ")
  end
  return "NOTE: only these moves are accepted RIGHT NOW: " .. moves(accepted) .. " -- still settling on screen: "
    .. moves(settling) .. "; if you need one of them, pick a listed move or wait. "
end

M.SECTIONS = {
  one_card_away = "One card away: ",
  consumables = "Consumables (",
  boss_row = "Boss blind ",
  deck_list = "## Decks you can select",
  stake_list = "## Stakes (",
  plan = "## Your plan",
}
M.SECTION_REFERENCES = {
  { phrase = "the one-card-away odds above", section = "one_card_away" },
  { phrase = "a discard toward a one-card-away hand", section = "one_card_away" },
  { phrase = "An owned consumable", section = "consumables" },
  { phrase = "the consumables list shows", section = "consumables" },
  { phrase = "Boss rule is stated in full on the", section = "boss_row" },
  { phrase = "from the Decks you can select list", section = "deck_list" },
  { phrase = "from the Stakes list", section = "stake_list" },
  { phrase = "(Your plan, above)", section = "plan" },
}

function M.has_section(text, id)
  local marker = M.SECTIONS[id]
  assert(marker, "unknown section: " .. tostring(id))
  return type(text) == "string" and text:find(marker, 1, true) ~= nil
end

local function is_word_char(c) return c ~= "" and c:match("[%w_]") ~= nil end

function M.mentions(text, name)
  local out, init = {}, 1
  if type(text) ~= "string" or type(name) ~= "string" or name == "" then return out end
  while true do
    local s, e = text:find(name, init, true)
    if not s then return out end
    if not is_word_char(s > 1 and text:sub(s - 1, s - 1) or "")
        and not is_word_char(text:sub(e + 1, e + 1)) then
      out[#out + 1] = { s, e }
    end
    init = s + 1
  end
end

function M.named_actions(text, catalog)
  local out = {}
  if type(text) ~= "string" then return out end
  for name in pairs(catalog or {}) do
    if #M.mentions(text, name) > 0 then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

function M.missing_sections(query, state)
  local out = {}
  for _, ref in ipairs(M.SECTION_REFERENCES) do
    if type(query) == "string" and query:find(ref.phrase, 1, true)
        and not M.has_section(state, ref.section) then
      out[#out + 1] = ref.phrase
    end
  end
  return out
end

return M
