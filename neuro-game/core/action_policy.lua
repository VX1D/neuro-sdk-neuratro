local FORFEIT = {
  skip_pack = true,
  skip_blind = true,
  leave_shop = true,
}

local TOOLS = {
  sell_card = true, reroll_shop = true, reroll_boss = true,
  use_consumable = true, use_directional_consumable = true,
  set_joker_order = true, record_plan = true, record_joker_roles = true,
  select_deck = true, select_stake = true, select_challenge = true, toggle_seeded_run = true, paste_seed = true,
  copy_seed = true,
}

local PROGRESS_TOOLS = {
  sell_card = true, reroll_shop = true, reroll_boss = true, use_consumable = true, use_directional_consumable = true,
}

local NON_PROGRESS = {}
for name in pairs(TOOLS) do
  if not PROGRESS_TOOLS[name] then NON_PROGRESS[name] = true end
end

local REUSABLE = { buy_from_shop = true }

local BLIND_CHOICE = { "select_blind", "skip_blind" }
local PACK_CHOICE = { "choose_pack_card", "choose_directional_pack_card", "skip_pack" }
local GROUPS = {
  select_blind = BLIND_CHOICE, skip_blind = BLIND_CHOICE,
  choose_pack_card = PACK_CHOICE, choose_directional_pack_card = PACK_CHOICE, skip_pack = PACK_CHOICE,
  leave_shop = { "leave_shop", "buy_from_shop" },
}

local function is_tool(name) return TOOLS[name] == true end

local function disposable_group(name)
  if type(name) ~= "string" or name == "" or TOOLS[name] or REUSABLE[name] then return nil end
  return GROUPS[name] or { name }
end

local function is_decision(name)
  return type(name) == "string" and name ~= "" and not TOOLS[name]
end

return {
  NON_PROGRESS = NON_PROGRESS,
  FORFEIT = FORFEIT,
  TOOLS = TOOLS,
  REUSABLE = REUSABLE,
  is_tool = is_tool,
  is_decision = is_decision,
  disposable_group = disposable_group,
}
