local Utils = require("util.utils")
local Actions = require("core.actions")
local ForceHelpers = require("force.force_helpers")
local CtxEconomy = require("facts.economy_facts")
local ActionRegistry = require("core.action_registry")
local FactHints = require("facts.fact_hints")
local SkipTriggers = require("facts.skip_triggers")

local function skip_tag_timing(current_blind)
  local btype = (current_blind == "small" and "Small") or (current_blind == "big" and "Big") or nil
  local rr = G and G.GAME and G.GAME.round_resets
  local tag_key = btype and rr and type(rr.blind_tags) == "table" and rr.blind_tags[btype] or nil
  local moment = tag_key and require("facts.tag_facts").payout_moment(tag_key)
  if not moment then return "" end
  local name = require("facts.display_names").tag(tag_key) or "tag"
  local boss_key = require("context.ctx_blind").upcoming_boss()
  local boss = boss_key and require("facts.boss.model").display_name(boss_key)
  local boss_label = "this ante's Boss" .. (boss and (" (" .. boss .. ")") or "")
  local next_label = (btype == "Small") and "the Big Blind" or boss_label
  if moment == "shop" then
    return ", and the " .. name .. " pays only in a shop, the next one after you beat " .. next_label
      .. ", which you face with your current board and bank"
  end
  return ", and the " .. name .. " pays only after you beat " .. boss_label
    .. ", which you face with your current board and bank"
end

local function build()
  local on_deck_key = Actions.get_selectable_blind_key()
  if not on_deck_key then return nil end
  local current_blind = string.lower(on_deck_key)

  local action_list = { "select_blind", "skip_blind", "reroll_boss", "sell_card", "use_consumable", "use_directional_consumable", "set_joker_order", "record_plan" }
  local progress_actions, can, can_now = ForceHelpers.collect_actions(action_list)
  local can_select, can_skip, can_reroll =
    can_now.select_blind, can_now.skip_blind, can_now.reroll_boss

  local boss_brief, boss_fact = "", ""
  do
    local row = require("context.ctx_blind").boss_row_label()
    if row then
      boss_brief = "This ante's Boss rule is stated in full on the \"" .. row .. "\" row above. "
    else
      local boss_key, bdef = require("context.ctx_blind").upcoming_boss()
      local brief = bdef and require("facts.boss.render").boss_line("select", boss_key, bdef)
      if brief then
        boss_fact = ((current_blind == "boss") and "" or "This ante's ") .. brief
      end
    end
  end

  local pending_confirm = ForceHelpers.pending_confirmation_note(can)
  local query = pending_confirm .. ForceHelpers.repeat_pressure_note(progress_actions) .. boss_brief
  local curve = require("facts.economy_facts").scaling_curve()
  curve = curve or ""
  local skip_advice = ""
  if can_select and can_skip then
    skip_advice = "Play a blind you can clear -- it pays cash and (after you beat it) opens a shop. But actively weigh skipping a Small/Big blind you'd comfortably overkill: you bank its skip tag (shown on that blind's row) and give up its cash and the shop after it"
      .. skip_tag_timing(current_blind)
      .. ". Skip when that tag is worth more than what you give up; keep playing when the tag is weak or the blind might beat you. "
  end
  query = query .. ForceHelpers.paragraph(skip_advice)
  local plan_block = FactHints.plan_note("blind")
  if can_select then
    plan_block = plan_block .. "Include plan.hand_plan and plan.build_plan when you select the blind; these two brief decisions are saved with the blind selection. You may also declare plan.hand_focus={primary=one of the Unlocked hand types, fallback=another of them}; this is descriptive and never blocks another play. Do not copy live cards, cash, joker roster, or future-boss facts into the plan; those are refreshed separately. "
  end
  if current_blind == "boss" then
    plan_block = plan_block .. "This is the Boss blind, and no cards are dealt yet -- that is deliberate. Put in plan.boss_plan the RULE this boss imposes on you, not a plan for a hand you have not seen: which suit or rank is dead weight, what you will refuse to build on, how you will pace hands and discards across the whole round. Written before the deal it cannot be bent to fit whatever cards happen to arrive. "
  end
  query = query .. ForceHelpers.paragraph(plan_block)
  local candidates = ForceHelpers.candidate_list
  local move_bits, tool_bits = {}, {}
  if can_select then
    move_bits[#move_bits + 1] = ActionRegistry.render("select_blind", { blind = current_blind,
      plan = ForceHelpers.plan_placeholders("BLIND_SELECT", "select_blind", { "hand", "build", "money", "boss" }) })
  end
  if can_skip then move_bits[#move_bits + 1] = ActionRegistry.render("skip_blind", {}) .. ' (banks this blind\'s skip tag -- named on its row above -- and moves straight to the next blind, giving up that blind\'s cash payout and the shop that would follow beating it)' end
  if can_reroll then tool_bits.reroll_boss = ActionRegistry.render("reroll_boss", {}) .. ' (costs ' .. Utils.money(CtxEconomy.BOSS_REROLL_COST) .. ', from your Director\'s Cut / Retcon voucher; swaps this boss for a different one with a different debuff)' end
  ForceHelpers.consumable_tools(tool_bits, can_now)
  if can.sell_card then tool_bits.sell_card = candidates("sell_card") end
  if can.set_joker_order then
    tool_bits.set_joker_order = ForceHelpers.joker_order_move()
      or ActionRegistry.prompt("set_joker_order", "jokers fire left-to-right, so their order matters")
  end
  if can.record_plan then tool_bits.record_plan = ActionRegistry.prompt("record_plan", "optionally revises the current plan") end
  query = query .. ForceHelpers.your_move(move_bits)

  local StateDoc = require("context.state_doc")
  return ForceHelpers.finish(query, {
    state_extra = StateDoc.lines(StateDoc.section("Boss", boss_fact), StateDoc.section("Blinds ahead", curve),
      StateDoc.section("Skip rules", can_skip and SkipTriggers.note("blind", G.jokers) or ""),
      FactHints.plan_state("blind")),
    actions = progress_actions,
    tool_bits = tool_bits,
    blind = current_blind
  })
end

return { build = build }
