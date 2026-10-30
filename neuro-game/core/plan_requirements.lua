local M = {}

M.FIELD_ORDER = { "hand", "build", "money", "boss" }

local HEADING = "## Required plan fields\nThese moves are refused without the plan fields listed, unless a current one is already recorded."
local REVISION = "after a shop buy or reroll, the fields the shop asks you to revise, sent again"

local function boss_on_deck()
  return require("core.actions").get_selectable_blind_key() == "Boss"
end

local function boss_unplanned()
  local blind = G and G.GAME and G.GAME.blind
  return blind ~= nil and blind.boss and not require("core.gate").boss_plan_is_current(G.NEURO and G.NEURO.plan)
end

local function stale_shop_fields()
  return require("core.gate").shop_required_fields()
end

local SHOP_CARD_USE = { state = "SHOP", context = "in the shop", fields = { hand = true, build = true } }
local BOSS_ROUND = { state = "SELECTING_HAND", when = boss_unplanned, context = "on a Boss round", fields = { boss = true } }
local SHOP_REVISION = { fields = stale_shop_fields }

local RULES = {
  select_blind = {
    { fields = { hand = true, build = true } },
    { when = boss_on_deck, context = "for the Boss blind", fields = { boss = true } },
  },
  buy_from_shop = { { fields = { money = true } } },
  reroll_shop = { { fields = { money = true } } },
  sell_card = { { state = "SHOP", context = "in the shop", fields = { build = true, money = true } } },
  use_consumable = { SHOP_CARD_USE },
  use_directional_consumable = { SHOP_CARD_USE },
  play_hand = { BOSS_ROUND },
  discard_hand = { BOSS_ROUND },
  leave_shop = { SHOP_REVISION },
  record_plan = { SHOP_REVISION },
}

function M.required(state_name, action_name)
  local out = {}
  for _, rule in ipairs(RULES[action_name] or {}) do
    if (rule.state == nil or rule.state == state_name) and (rule.when == nil or rule.when()) then
      local fields = type(rule.fields) == "function" and rule.fields() or rule.fields
      for field, on in pairs(fields) do
        if on then out[field] = true end
      end
    end
  end
  return out
end

local function field_names(fields)
  local names = {}
  for _, key in ipairs(M.FIELD_ORDER) do
    if fields[key] then names[#names + 1] = key .. "_plan" end
  end
  return table.concat(names, " and ")
end

local function rule_text(rule)
  if type(rule.fields) == "function" then return REVISION end
  return field_names(rule.fields) .. (rule.context and (" " .. rule.context) or "")
end

function M.guide_section()
  local phrases = require("core.action_phrases")
  local names = {}
  for name in pairs(RULES) do names[#names + 1] = name end
  table.sort(names, function(a, b) return phrases[a] < phrases[b] end)
  local lines = { HEADING }
  for _, name in ipairs(names) do
    local parts = {}
    for _, rule in ipairs(RULES[name]) do parts[#parts + 1] = rule_text(rule) end
    lines[#lines + 1] = "- " .. phrases[name] .. ": " .. table.concat(parts, "; ")
  end
  return table.concat(lines, "\n")
end

return M
