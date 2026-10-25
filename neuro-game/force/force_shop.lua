local GameFacts = require("facts.game_facts")
local FactHints = require("facts.fact_hints")
local ForceHelpers = require("force.force_helpers")
local CardUtil = require("facts.card_util")
local CtxEconomy = require("facts.economy_facts")
local ActionRegistry = require("core.action_registry")
local Gate = require("core.gate")
local TargetContracts = require("facts.target_contracts")
local SkipTriggers = require("facts.skip_triggers")
local safe_name_or = require("util.utils").safe_name_or

local CONSUMABLE_PACK = { Arcana = true, Celestial = true, Spectral = true }

local function targeting_contract_prose(card, accepted, slot_free)
  local buy = slot_free and "buy it first" or "it needs a free consumable slot to be bought, then buy it"
  if TargetContracts.get(card) and accepted.use_directional_consumable then
    return buy .. ", then use it as a directional consumable with left_index the hand card it applies to and right_index the card it takes from"
  end
  if accepted.use_consumable then
    return buy .. ", then use it as a consumable with hand_indices"
  end
  return buy .. "; its targeting fields are validated when the use action is offered"
end

local voucher_chain_hint = FactHints.voucher_chain_hint
local voucher_basics_hint = FactHints.voucher_basics_hint
local shop_edition_hint = FactHints.shop_edition_hint

local boss_choice_is_public = require("facts.boss.model").upcoming_is_public
local function build()
  local force_actions, can, can_now = ForceHelpers.collect_actions(
    { "buy_from_shop", "sell_card", "reroll_shop", "use_consumable", "use_directional_consumable",
      "leave_shop", "set_joker_order", "record_plan", "record_joker_roles" })

  if #force_actions == 0 then
    return nil
  end
  local buy_locked = Gate.buy_locked()
  local plan_revision = Gate.shop_needs_revision()

  local any_public = ForceHelpers.any_public
  local js = CardUtil.joker_slot_status()
  local shop_offers_joker = any_public(G and G.shop_jokers, CardUtil.is_joker_like_card)
  local shop_offers_buffoon = any_public(G and G.shop_booster, function(c)
    return CardUtil.booster_kind(c) == "Buffoon"
  end)
  local joker_slot_warn, joker_slot_move = "", ""
  if js.full and (shop_offers_joker or shop_offers_buffoon) then
    local has_neg_in_shop = CardUtil.area_has_negative_joker(G.shop_jokers)
    joker_slot_warn = ForceHelpers.joker_full_warn(js, has_neg_in_shop)
    if shop_offers_joker and not has_neg_in_shop then
      if can.sell_card and can.buy_from_shop then
        joker_slot_move = "To take a shop joker with slots full: sell a joker ("
          .. ActionRegistry.example("sell_card", { area = "jokers" }) .. ") first, then buy it. "
      elseif can.buy_from_shop then
        joker_slot_move = "To take a shop joker with slots full, sell a joker first, then buy it. "
      elseif can.sell_card then
        joker_slot_move = "Selling a joker first frees a slot for a shop joker. "
      end
    end
  end
  local buffoon_full_warn = ""
  if js.full and shop_offers_buffoon then
    buffoon_full_warn = "A Buffoon pack gives jokers; with slots full you can open it but can't keep one without selling a joker first. "
  end
  local function shop_stocks_consumable()
    local function consumable(c) return CardUtil.is_consumable_set(CardUtil.card_set(c)) end
    return any_public(G and G.shop_jokers, consumable) or any_public(G and G.shop_vouchers, consumable)
      or any_public(G and G.shop_booster, function(c)
        local kind = CardUtil.booster_kind(c)
        return CONSUMABLE_PACK[kind] or kind == "Buffoon"
      end)
  end
  local cs = CardUtil.consumable_slot_status()
  local cons_slot_warn = ""
  if cs.full and shop_stocks_consumable() then
    cons_slot_warn = string.format("Consumable slots FULL (%d/%d). Buying a tarot/planet/spectral card TO KEEP needs an open one; using or selling an owned consumable frees it immediately. A no-target shop consumable can be bought and used on the spot without a free slot; only keeping one needs a slot. ", cs.count, cs.limit)
    for _, entry in ipairs(ForceHelpers.public_cards(G and G.consumeables)) do
      local idle = CardUtil.idle_planet_note(entry.card)
      if idle then
        cons_slot_warn = cons_slot_warn .. string.format("Consumable %d %s %s. ", entry.index,
          safe_name_or(entry.card), idle)
      end
    end
    if any_public(G and G.shop_booster, function(c) return CONSUMABLE_PACK[CardUtil.booster_kind(c)] end) then
      cons_slot_warn = cons_slot_warn
        .. "This does NOT block a booster pack here: a Tarot/Planet/Spectral pick is used the moment you pick it, so full slots cost you nothing on a pack. Only a picked card that CREATES a consumable needs an open slot. "
    end
  end
  local blocked_consumable_warn = require("facts.use_gate").blocked_note()
  voucher_chain_hint()
  voucher_basics_hint()
  local edition_hint = shop_edition_hint()

  local shop_target_fact = ""
  do
    local needs = {}
    for _, entry in ipairs(ForceHelpers.public_cards(G and G.shop_jokers)) do
      local c, i = entry.card, entry.index
      local set = CardUtil.card_set(c)
      if CardUtil.is_consumable_set(set) then
        local _, mh = CardUtil.consumable_target_range(c)
        if mh and mh > 0 then
          local nm = safe_name_or(c)
          needs[#needs + 1] = string.format("slot %d '%s': %s",
            i, tostring(nm), targeting_contract_prose(c, can_now, CardUtil.can_buy_card_space(c, "shop_jokers")))
        end
      end
    end
    if #needs > 0 then
      shop_target_fact = "Targeting consumables here: " .. table.concat(needs, "; ") .. ". "
    end
  end

  local SHOP_AREAS = { "shop_jokers", "shop_vouchers", "shop_booster" }
  local buyable = {}
  do
    local seen = {}
    for _, payload in ipairs(can_now.buy_from_shop and ActionRegistry.candidates("buy_from_shop") or {}) do
      local area, index = payload.area, tonumber(payload.index)
      if area and index then
        seen[area] = seen[area] or {}
        if not seen[area][index] then
          seen[area][index] = true
          buyable[area] = buyable[area] or {}
          buyable[area][#buyable[area] + 1] = index
        end
      end
    end
    for _, list in pairs(buyable) do table.sort(list) end
  end

  local function index_list_prose(list)
    if #list == 1 then return tostring(list[1]) end
    if list[#list] - list[1] == #list - 1 then return list[1] .. "-" .. list[#list] end
    return table.concat(list, "/")
  end

  local shop_areas = {}
  for _, name in ipairs(SHOP_AREAS) do
    if buyable[name] and #buyable[name] > 0 then shop_areas[#shop_areas + 1] = name end
  end

  local unbuyable_fact = ""
  if can_now.buy_from_shop then
    local rows, blocks_consumable, blocks_joker = {}, false, false
    for _, name in ipairs(SHOP_AREAS) do
      local area = G and G[name]
      local blocked, taken = {}, buyable[name] or {}
      local offered = {}
      for _, ix in ipairs(taken) do offered[ix] = true end
      for _, entry in ipairs(ForceHelpers.public_cards(area)) do
        local i, c = entry.index, entry.card
        if not offered[i] and CtxEconomy.item_afford_status(c, name).afford
          and not CardUtil.can_buy_card_space(c, name) then
          blocked[#blocked + 1] = i
          if CardUtil.is_consumable_card(c) then blocks_consumable = true else blocks_joker = true end
        end
      end
      if #blocked > 0 then rows[#rows + 1] = name .. " " .. index_list_prose(blocked) end
    end
    if #rows > 0 then
      local frees = {}
      if blocks_consumable then
        local ways = {}
        if can.use_consumable or can.use_directional_consumable then ways[#ways + 1] = "using" end
        if can.sell_card and #((G and G.consumeables and G.consumeables.cards) or {}) > 0 then
          ways[#ways + 1] = "selling"
        end
        if #ways > 0 then frees[#frees + 1] = table.concat(ways, " or ") .. " an owned consumable frees a consumable slot" end
      end
      if blocks_joker and can.sell_card then frees[#frees + 1] = "selling a joker frees a joker slot" end
      unbuyable_fact = "Your cash covers " .. table.concat(rows, ", ")
        .. ", but there is no free slot to put them in, so buying those rows is refused"
        .. (#frees > 0 and ("; " .. table.concat(frees, "; ") .. ". ") or ". ")
    end
  end

  local function payload_with_requirements(name, payload)
    local out = {}
    for key, value in pairs(payload or {}) do out[key] = value end
    out.plan = ForceHelpers.plan_placeholders("SHOP", name, { "hand", "build", "money" }) or out.plan
    if name == "leave_shop" and Gate.pending("joker_order") then out.joker_order_confirmed = true end
    return out
  end
  local render_payload = ForceHelpers.render_candidate

  local function candidate_prompt(name) return ForceHelpers.candidate_list(name, payload_with_requirements) end

  local function collapsed_prompt(name)
    local payloads = ActionRegistry.candidates(name)
    if #payloads == 0 then return "" end
    if #payloads == 1 then return render_payload(name, payload_with_requirements(name, payloads[1])) end
    local contract = ActionRegistry.display(name)
    local schema = (contract and contract.schema) or {}
    local required = {}
    for _, key in ipairs(schema.required or {}) do required[key] = true end
    local shape, distinct = nil, {}
    for _, payload in ipairs(payloads) do
      local keys = {}
      for key in pairs(payload) do keys[#keys + 1] = key end
      table.sort(keys)
      local sig = table.concat(keys, ",")
      if shape == nil then shape = sig elseif shape ~= sig then return candidate_prompt(name) end
      for key, value in pairs(payload) do
        distinct[key] = distinct[key] or {}
        distinct[key][tostring(value)] = value
      end
    end
    local bound = {}
    for key, values in pairs(distinct) do
      local count, only = 0, nil
      for _, value in pairs(values) do count = count + 1; only = value end
      if count == 1 then
        bound[key] = only
      elseif not required[key] then
        return candidate_prompt(name)
      else
        local enum = (schema.properties or {})[key] and schema.properties[key].enum
        if enum and #enum ~= count then return candidate_prompt(name) end
      end
    end
    for key, value in pairs(payload_with_requirements(name, {})) do bound[key] = value end
    local ok, rendered = pcall(ActionRegistry.example, name, bound)
    if not ok or type(rendered) ~= "string" or rendered == "" then return candidate_prompt(name) end
    return rendered
  end

  local move_bits, tool_bits = {}, {}
  local push_move = ForceHelpers.push_move
  if can_now.buy_from_shop then push_move(move_bits, candidate_prompt("buy_from_shop")) end
  if can_now.reroll_shop then tool_bits.reroll_shop = render_payload("reroll_shop", payload_with_requirements("reroll_shop", {})) end
  if can_now.sell_card then tool_bits.sell_card = collapsed_prompt("sell_card") end
  ForceHelpers.consumable_tools(tool_bits, can_now, payload_with_requirements)
  if can.set_joker_order then
    tool_bits.set_joker_order = ForceHelpers.joker_order_move()
      or ActionRegistry.prompt("set_joker_order", "rearranges the joker order")
  end
  local untagged
  do
    untagged = ForceHelpers.untagged_joker_count("while building the shop force")
    if can.record_joker_roles then
      tool_bits.record_joker_roles = ActionRegistry.prompt("record_joker_roles", "records what a joker is for")
    end
  end
  if can.record_plan then tool_bits.record_plan = ActionRegistry.prompt("record_plan", "optionally revises the current plan") end
  local untagged_fact = ""
  if can_now.leave_shop then
    local exit_bit = render_payload("leave_shop", payload_with_requirements("leave_shop", {}))
      .. ', carrying whatever is left in the bank into the next cash-out'
    if untagged == nil or untagged > 0 then
      local ok_prose, prose = pcall(require("facts.card_util").untagged_joker_prose)
      if ok_prose and prose then untagged_fact = prose .. "." end
      exit_bit = exit_bit .. ' -- every joker needs a role tag before you leave, so tag them as you leave'
        .. ' via intents (the same list joker roles are recorded with) or record their roles first'
    end
    if Gate.pending("joker_order") then
      exit_bit = exit_bit .. ' -- ' .. Gate.text("joker_order")
    end
    move_bits[#move_bits + 1] = exit_bit
  end
  local move_tail, index_fact = "", ""
  if #move_bits > 0 then
    local range_bits = {}
    for _, name in ipairs(shop_areas) do
      range_bits[#range_bits + 1] = name .. " " .. index_list_prose(buyable[name])
    end
    if can.sell_card and G.jokers and G.jokers.cards and #G.jokers.cards > 0 then
      range_bits[#range_bits + 1] = "jokers " .. ForceHelpers.index_range(#G.jokers.cards)
    end
    if (can.sell_card or can.use_consumable or can.use_directional_consumable)
      and G.consumeables and G.consumeables.cards and #G.consumeables.cards > 0 then
      range_bits[#range_bits + 1] = "consumables " .. ForceHelpers.index_range(#G.consumeables.cards)
    end
    local ranges = (#range_bits > 0) and table.concat(range_bits, ", ") or "none"
    index_fact = unbuyable_fact .. "Valid indices: " .. ranges .. "."
    move_tail = ForceHelpers.your_move(move_bits)
  end

  local jn = (G.jokers and G.jokers.cards and #G.jokers.cards) or 0
  local has_xmult = (require("util.scoring").owned_xmult_state() or "none") ~= "none"

  local joker_priority = ""
  if jn == 0 then
    joker_priority = "Jokers are your scoring engine: when you own none, buy a joker before a voucher: a joker scores now, most vouchers pay off slowly (a few, like planet/economy vouchers, are run-defining). "
  end


  local idle_slot_warn = ""
  do
    local posture = CtxEconomy.spend_posture()
    if posture and posture.posture == "build" and (not js.full) and jn > 0 then
      local spend = CtxEconomy.spendable()
      if any_public(G and G.shop_jokers, function(c)
        return CardUtil.is_joker_like_card(c) and (tonumber(c.cost) or 1e9) <= spend
      end) then
        idle_slot_warn = "An empty joker slot scores nothing: if an affordable joker here fits your build, filling it beats saving a few dollars. "
      end
    end
  end

  local broke_warn = ""
  if CtxEconomy.below_first_interest_step() then
    broke_warn = "Interest starts once you carry $5 out of the shop and grows with every further step -- worth weighing against a cheap card now. "
  end

  local plan_line = FactHints.plan_note("shop")
  local plan_prompt = ""
  if buy_locked or plan_revision then
    plan_prompt = "Include the plan fields shown in the example of your chosen action; they are validated and saved together with that action. Do not copy live cash, shop rows, joker roster, or boss text; those facts refresh separately. "
  end

  local build_mgmt = ""
  if can.set_joker_order and can.sell_card then
    build_mgmt =
      "As you plan, weigh your joker build: reorder it by moving jokers, and if a joker has stopped pulling its weight, selling it frees a slot and cash for a better fit. Your call which. "
  end

  local economy_note
  do
    local model = CtxEconomy.reserve_model()
    local rf = CtxEconomy.reroll_facts()
    local parts = {}
    if model and model.interest then
      local posture = CtxEconomy.spend_posture()
      if posture and posture.posture == "bank" then
        parts[#parts + 1] =
          "Carried cash is the only income that compounds, so walking out with the bank intact is a move, not a skipped turn. "
      end
      if has_xmult and can.reroll_shop and type(rf.effective) == "number" and rf.effective > 0
          and rf.effective > CtxEconomy.safe_spend_keep_interest() then
        parts[#parts + 1] = "Rerolling now costs more than you can spend while keeping interest, and the price climbs each reroll -- reroll only when nothing here fits your build and you can spare it. "
      end
      if model.surplus > 0 and can.buy_from_shop then
        parts[#parts + 1] = "Cash past the interest cap earns nothing sitting idle. If your build isn't clearing blinds comfortably, treat that excess as free fuel for power (level your main hand, add or upgrade an xMult joker, reroll for a fit); if your build is already strong, there's little more to gain here. "
      end
    elseif model and not model.bank_scaling and model.rerolls >= 2
        and (can.buy_from_shop or can.reroll_shop) then
      local uses = { "Planets for your main hand", "packs" }
      if can.reroll_shop then table.insert(uses, 1, "rerolls here") end
      parts[#parts + 1] = string.format(
        "Cash in the bank earns nothing this run -- spend what sits above the reserve on %s, or %s. ",
        table.concat(uses, ", ", 1, #uses - 1), uses[#uses])
    end
    economy_note = table.concat(parts)
  end

  local scaling_curve_warn = ""
  do
    local curve = require("facts.economy_facts").scaling_curve()
    if curve then scaling_curve_warn = curve end
  end

  local unleveled_warn = ""
  do
    local ante = GameFacts.ante(0)
    local hands = G and G.GAME and G.GAME.hands
    if ante >= 2 and type(hands) == "table" then
      local any_leveled = false
      for _, h in pairs(hands) do
        if type(h) == "table" and (tonumber(h.level) or 1) >= 2 then any_leveled = true break end
      end
      if not any_leveled then
        unleveled_warn =
          "Planet cards (Celestial packs, or Planets in the shop) permanently raise a hand's chips and mult together, and the hand type you play won't scale to later blinds until you level it. "
      end
    end
  end

  local boss_primer = ""
  do
    local boss_key, bdef, rr = require("context.ctx_blind").upcoming_boss()
    if bdef and boss_choice_is_public(rr) then
      local ok_brief, eff = pcall(require("facts.boss.render").boss_line, "upcoming", boss_key, bdef)
      if ok_brief and type(eff) == "string" and eff ~= "" then
        boss_primer = eff
      end
    end
  end

  local notes = plan_line
    .. FactHints.joker_churn_note()
    .. plan_prompt
    .. build_mgmt
    .. ForceHelpers.paragraph(joker_priority
      .. idle_slot_warn
      .. broke_warn
      .. economy_note
      .. unleveled_warn
      .. edition_hint
      .. shop_target_fact)

  local pending_confirm = ForceHelpers.pending_confirmation_note(can)

  local query = pending_confirm
    .. ForceHelpers.pending_gate_note(force_actions)
    .. ForceHelpers.repeat_pressure_note(force_actions)
    .. notes
    .. ForceHelpers.paragraph(joker_slot_move)
    .. ForceHelpers.paragraph(require("context.ctx_shop").requirements_query(can) or "")
    .. ForceHelpers.paragraph(move_tail)
  local StateDoc = require("context.state_doc")
  local state_extra = StateDoc.lines(
    StateDoc.section("Constraints", StateDoc.lines(joker_slot_warn .. buffoon_full_warn, cons_slot_warn,
      blocked_consumable_warn, untagged_fact, index_fact)),
    StateDoc.section("Upcoming boss", boss_primer),
    StateDoc.section("Blinds ahead", scaling_curve_warn),
    StateDoc.section("Skip rules", SkipTriggers.note("shop", G.jokers, G.shop_jokers)),
    FactHints.plan_state("shop"))
  return ForceHelpers.finish(query, { state_extra = state_extra, actions = force_actions, tool_bits = tool_bits })
end

return { build = build }
