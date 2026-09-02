local Actions = require("core.actions")
local GameFacts = require("facts.game_facts")
local ForceHelpers = require("force.force_helpers")
local CtxEconomy = require("facts.economy_facts")
local ActionRegistry = require("core.action_registry")
local FactHints = require("facts.fact_hints")
local failed_action_warning = ForceHelpers.failed_action_warning

local function build()
  local on_deck_key = Actions.get_selectable_blind_key()
  if not on_deck_key then return nil end
  local current_blind = string.lower(on_deck_key)

  local action_list = { "select_blind", "skip_blind", "reroll_boss", "sell_card", "use_consumable", "use_directional_consumable", "set_joker_order", "record_plan" }
  local progress_actions, can, can_now = ForceHelpers.collect_actions(action_list)
  local can_select, can_skip, can_reroll =
    can_now.select_blind, can_now.skip_blind, can_now.reroll_boss

  local boss_brief = ""
  do
    local row = require("context.ctx_blind").boss_row_label()
    if row then
      boss_brief = "This ante's Boss rule is stated in full on the \"" .. row .. "\" row above. "
    else
      local choices = G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_choices
      local boss_key = choices and choices.Boss
      local bdef = boss_key and G.P_BLINDS and G.P_BLINDS[boss_key]
      local brief = bdef and require("facts.boss.render").boss_line("select", boss_key, bdef)
      if brief then
        local lead = (current_blind == "boss") and "" or "This ante's "
        boss_brief = lead .. brief .. " "
      end
    end
  end

  local win_ante = G and G.GAME and G.GAME.win_ante or 8
  local cur_ante = GameFacts.ante(0)
  local ante_progress = string.format("Ante %d/%d (beat the final Boss to win). ", cur_ante, win_ante)
  local pending_confirm = ""
  do
    local ok_pc, note = pcall(require("handlers.shop_handlers").pending_confirmation_note, can)
    if ok_pc and type(note) == "string" then pending_confirm = note end
  end
  local query = "State: BLIND_SELECT. " .. failed_action_warning() .. pending_confirm
    .. ForceHelpers.repeat_pressure_note() .. ante_progress
  query = query .. "Currently selectable: " .. current_blind .. ". " .. boss_brief
  do
    local curve = require("facts.economy_facts").scaling_curve()
    if curve then query = query .. FactHints.emit("scaling_curve:" .. curve, curve) end
  end
  local skip_advice = ""
  if can_select and can_skip then
    skip_advice = FactHints.emit("blind_select_advice", "Play a blind you can clear -- it pays cash and (after you beat it) opens a shop. But actively weigh skip_blind on a Small/Big blind you'd comfortably overkill: you bank its skip tag (shown on that blind's row) for free and give up only the modest cash. Skip when that tag is worth more than the payout; keep playing when the tag is weak or the blind might beat you. ")
  end
  query = query .. skip_advice
  query = query .. FactHints.plan_note("blind")
  query = query .. "Include plan.hand_plan and plan.build_plan in select_blind; these two brief decisions are saved with the blind selection. You may also declare plan.hand_focus={primary=an exact visible hand name, fallback=another visible hand name}; this is descriptive and never blocks another play. Do not copy live cards, cash, joker roster, or future-boss facts into the plan; those are refreshed separately. "
  if current_blind == "boss" then
    query = query .. "This is the Boss blind, and no cards are dealt yet -- that is deliberate. Put in plan.boss_plan the RULE this boss imposes on you, not a plan for a hand you have not seen: which suit or rank is dead weight, what you will refuse to build on, how you will pace hands and discards across the whole round. Written before the deal it cannot be bent to fit whatever cards happen to arrive. "
  end
  if can.set_joker_order then
    query = query .. "You can also reorder jokers (set_joker_order; they fire left-to-right, order matters) or sell a weak one (sell_card) here. "
  elseif can.sell_card then
    query = query .. "You can also sell a weak joker (sell_card) here. "
  end
  local function candidates(name)
    local out = {}
    for _, payload in ipairs(ActionRegistry.candidates(name)) do
      out[#out + 1] = ActionRegistry.render(name, payload)
    end
    return table.concat(out, " or ")
  end
  local move_bits = {}
  if can_select then
    local payload = { blind = current_blind }
    local requirements = require("core.plan_gate").action_requirements("BLIND_SELECT", "select_blind")
    if next(requirements.plan) then
      payload.plan = {}
      if requirements.plan.hand then payload.plan.hand_plan = "..." end
      if requirements.plan.build then payload.plan.build_plan = "..." end
      if requirements.plan.money then payload.plan.money_plan = "..." end
      if requirements.plan.boss then payload.plan.boss_plan = "..." end
    end
    move_bits[#move_bits + 1] = ActionRegistry.render("select_blind", payload)
  end
  if can_skip then move_bits[#move_bits + 1] = ActionRegistry.render("skip_blind", {}) .. ' (banks this blind\'s skip tag -- named on its row above -- and moves straight to the next blind, giving up that blind\'s cash payout and the shop that would follow beating it)' end
  if can_reroll then move_bits[#move_bits + 1] = ActionRegistry.render("reroll_boss", {}) .. ' (costs $' .. tostring(CtxEconomy.BOSS_REROLL_COST) .. ', from your Director\'s Cut / Retcon voucher; swaps this boss for a different one with a different debuff)' end
  if can_now.use_consumable then move_bits[#move_bits + 1] = candidates("use_consumable") .. " before selecting" end
  if can_now.use_directional_consumable then move_bits[#move_bits + 1] = ActionRegistry.prompt("use_directional_consumable") .. " before selecting" end
  if can.sell_card then move_bits[#move_bits + 1] = candidates("sell_card") .. " sells a joker or consumable for money" end
  if can.set_joker_order then move_bits[#move_bits + 1] = ActionRegistry.prompt("set_joker_order") .. " rearranges joker order (fires left-to-right)" end
  if can.record_plan then move_bits[#move_bits + 1] = ActionRegistry.prompt("record_plan") .. " optionally revises the current plan" end
  if #move_bits > 0 then
    query = query .. "\nYour move: " .. table.concat(move_bits, "; ") .. ". "
  end

  return {
    query = query:gsub("  +", " "),
    actions = progress_actions,
    blind = current_blind
  }
end

return { build = build }
