local M = {}

function M.load(label, lost_if_skipped)
  local dump = os.getenv("BALATRO_DUMP")
  local skip = require("tests.skip_ledger")
  if not dump or dump == "" then
    skip.bail(label, lost_if_skipped, "BALATRO_DUMP is unset; set it to the lovely dump directory")
  end
  _G.Moveable = { extend = function() local class = {}; class.__index = class; return class end }
  for _, file in ipairs({ "cardarea.lua", "card.lua" }) do
    local fh = io.open(dump .. "/" .. file, "r")
    if not fh then skip.bail(label, lost_if_skipped, "game dump not readable at " .. dump .. "/" .. file) end
    local src = fh:read("*a")
    fh:close()
    assert((loadstring or load)(src, "@" .. file))()
  end
  _G.play_sound = function() end
  M.dump = dump
  M.STATES = require("tests.engine_cards").states()
  return dump
end

function M.area(kind, highlighted_limit, card_limit)
  local area = setmetatable({ cards = {}, highlighted = {}, children = {},
    config = { type = kind, highlighted_limit = highlighted_limit or 5, card_limit = card_limit or 8 } }, CardArea)
  area.parse_highlighted = function() end
  return area
end

function M.playing_card(sort_id, area, edition)
  return setmetatable({
    sort_id = sort_id, cost = 1, sell_cost = 1, facing = "front", area = area, children = {},
    edition = edition,
    ability = { set = "Default", name = "Default Base" },
    config = { center = { key = "c_base", set = "Default" } },
    base = { value = tostring(sort_id + 1), suit = "Hearts", id = sort_id + 1 },
  }, Card)
end

function M.consumable(sort_id, name, key, set, consumeable, area)
  return setmetatable({
    sort_id = sort_id, cost = 3, sell_cost = 1, facing = "front", area = area, children = {},
    ability = { set = set, name = name, consumeable = consumeable or {} },
    config = { center = { key = key, set = set, name = name } },
  }, Card)
end

function M.ids(list)
  local out = {}
  for i, card in ipairs(list or {}) do out[i] = tostring(card.sort_id) end
  return table.concat(out, ",")
end

return M
