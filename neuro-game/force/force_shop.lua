local Actions = require("core.actions")
local GameFacts = require("facts.game_facts")
local FactHints = require("facts.fact_hints")
local ForceHelpers = require("force.force_helpers")
local CardUtil = require("facts.card_util")
local CtxEconomy = require("facts.economy_facts")
local ActionRegistry = require("core.action_registry")
local blueprint_chain_hint = FactHints.blueprint_chain_hint
local voucher_chain_hint = FactHints.voucher_chain_hint
local voucher_basics_hint = FactHints.voucher_basics_hint
local shop_edition_hint = FactHints.shop_edition_hint
local failed_action_warning = ForceHelpers.failed_action_warning

local function boss_choice_is_public(rr)
  local st = rr and rr.blind_states
  if type(st) ~= "table" then return true end
  return not (st.Small == "Upcoming" and st.Big == "Upcoming" and st.Boss == "Upcoming")
end

local function build()
  local force_actions, can, can_now = ForceHelpers.collect_actions(
    { "buy_from_shop", "sell_card", "reroll_shop", "use_card", "use_directional_card", "toggle_shop" })

  if Actions.is_action_valid("set_joker_order") then
    force_actions[#force_actions + 1] = "set_joker_order"
    can.set_joker_order = true
  end
  if Actions.is_action_valid("set_plan") then
    force_actions[#force_actions + 1] = "set_plan"
  end
  if Actions.is_action_valid("set_joker_intents") then
    force_actions[#force_actions + 1] = "set_joker_intents"
  end
  if #force_actions == 0 then
    return nil
  end
  local PlanGate = require("core.plan_gate")
  local buy_locked = PlanGate.buy_locked()
  local plan_revision = PlanGate.shop_needs_revision()
  if Actions.is_action_valid("set_plan") then can.set_plan = true end
  if Actions.is_action_valid("set_joker_intents") then can.set_joker_intents = true end

  local js = CardUtil.joker_slot_status()
  local joker_slot_warn = ""
  if js.full then
    local has_neg_in_shop = CardUtil.area_has_negative_joker(G.shop_jokers)
    joker_slot_warn = ForceHelpers.joker_full_warn(js, has_neg_in_shop)
    if not has_neg_in_shop and G.shop_jokers and G.shop_jokers.cards then
      for _, c in ipairs(G.shop_jokers.cards) do
        if CardUtil.is_joker_like_card(c) then
          joker_slot_warn = joker_slot_warn
            .. "To take a shop joker with slots full: sell a joker ("
            .. ActionRegistry.example("sell_card", { area = "jokers" }) .. ") first, then buy_from_shop. "
          break
        end
      end
    end
  end
  local buffoon_full_warn = ""
  if js.full and G.shop_booster and G.shop_booster.cards then
    for _, c in ipairs(G.shop_booster.cards) do
      if CardUtil.booster_kind(c) == "Buffoon" then
        buffoon_full_warn = "A Buffoon pack gives jokers; with slots full you can open it but can't keep one without selling a joker first. "
        break
      end
    end
  end
  local function shop_stocks_consumable()
    for _, name in ipairs({ "shop_jokers", "shop_vouchers" }) do
      local area = G and G[name]
      for _, c in ipairs((area and area.cards) or {}) do
        if CardUtil.is_consumable_set(CardUtil.card_set(c)) then return true end
      end
    end
    for _, c in ipairs((G and G.shop_booster and G.shop_booster.cards) or {}) do
      local kind = CardUtil.booster_kind(c)
      if kind == "Arcana" or kind == "Celestial" or kind == "Spectral" or kind == "Buffoon" then
        return true
      end
    end
    return false
  end
  local cs = CardUtil.consumable_slot_status()
  local cons_slot_warn = ""
  if cs.full and shop_stocks_consumable() then
    cons_slot_warn = string.format("Consumable slots FULL (%d/%d). Buying a tarot/planet/spectral card TO KEEP needs an open one; using or selling an owned consumable frees it immediately. A no-target shop consumable can be bought-and-used on the spot (buy with \"use\":true, no free slot needed); only keeping one needs a slot. ", cs.count, cs.limit)
    if G.shop_booster and G.shop_booster.cards then
      for _, c in ipairs(G.shop_booster.cards) do
        local kind = CardUtil.booster_kind(c)
        if kind == "Arcana" or kind == "Celestial" or kind == "Spectral" then
          cons_slot_warn = cons_slot_warn
            .. "This does NOT block a booster pack here: a Tarot/Planet/Spectral pick is used the moment you pick it, so full slots cost you nothing on a pack. Only a picked card that CREATES a consumable needs an open slot. "
          break
        end
      end
    end
  end
  local blocked_consumable_warn = ""
  do
    local blocked_by_slot = false
    for _, c in ipairs((G and G.consumeables and G.consumeables.cards) or {}) do
      if not CardUtil.consumable_usable_now(c) then
        local _, mh = CardUtil.consumable_target_range(c)
        if not (mh and mh > 0) then blocked_by_slot = true break end
      end
    end
    if blocked_by_slot then
      blocked_consumable_warn = "An owned consumable is marked not usable because its output slot is full: free a joker or consumable slot and it becomes usable. "
    elseif CardUtil.has_blocked_consumable() then
      blocked_consumable_warn = "An owned consumable (marked not usable) isn't usable right now. In the shop you hold no hand, so any card that targets hand cards reads N here and will become usable once the next blind deals you a hand -- that needs no action. Only a creator card blocked by a full joker/consumable output slot needs you to free room. "
    end
  end
  local joker_order_hint = ""
  if can.set_joker_order then
    joker_order_hint = "Use " .. ActionRegistry.prompt("set_joker_order") .. " to rearrange the joker order. "
  end
  voucher_chain_hint()
  voucher_basics_hint()
  local edition_hint = shop_edition_hint()

  local shop_target_fact = ""
  if G.shop_jokers and G.shop_jokers.cards then
    local needs = {}
    for i, c in ipairs(G.shop_jokers.cards) do
      local set = CardUtil.card_set(c)
      if CardUtil.is_consumable_set(set) then
        local mn, mh = CardUtil.consumable_target_range(c)
        if mh and mh > 0 then
          local nm = c.ability and c.ability.name or set
          needs[#needs + 1] = string.format("slot %d '%s' targets %s hand cards", i, tostring(nm), (mn == mh) and tostring(mn) or (mn .. "-" .. mh))
        end
      end
    end
    if #needs > 0 then
      shop_target_fact = "Targeting consumables here: " .. table.concat(needs, "; ")
        .. " -- a targeting consumable is bought first, then applied with use_card and hand_indices. "
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
    local rows = {}
    for _, name in ipairs(SHOP_AREAS) do
      local area = G and G[name]
      local blocked, taken = {}, buyable[name] or {}
      local offered = {}
      for _, ix in ipairs(taken) do offered[ix] = true end
      for i, c in ipairs((area and area.cards) or {}) do
        if not offered[i] and CtxEconomy.item_afford_status(c, name).afford
          and not CardUtil.can_buy_card_space(c, name) then
          blocked[#blocked + 1] = i
        end
      end
      if #blocked > 0 then rows[#rows + 1] = name .. " " .. index_list_prose(blocked) end
    end
    if #rows > 0 then
      unbuyable_fact = "Your cash covers " .. table.concat(rows, ", ")
        .. ", but there is no free slot to put them in, so buy_from_shop is refused on those rows"
        .. (can.sell_card and " until a sell frees one. " or ". ")
    end
  end

  local function payload_with_requirements(name, payload)
    local out = {}
    for key, value in pairs(payload or {}) do out[key] = value end
    local requirements = PlanGate.action_requirements("SHOP", name)
    if next(requirements.plan) then
      out.plan = {}
      if requirements.plan.hand then out.plan.hand_plan = "..." end
      if requirements.plan.build then out.plan.build_plan = "..." end
      if requirements.plan.money then out.plan.money_plan = "..." end
    end
    if requirements.joker_order then out.joker_order_confirmed = true end
    return out
  end
  local function render_payload(name, payload)
    if not next(payload or {}) then return name .. "|{}" end
    return ActionRegistry.render(name, payload)
  end

  local function candidate_prompt(name)
    local payloads = {}
    for _, payload in ipairs(ActionRegistry.candidates(name)) do
      payloads[#payloads + 1] = render_payload(name, payload_with_requirements(name, payload))
    end
    return table.concat(payloads, " or ")
  end

  local function collapsed_prompt(name)
    local payloads = ActionRegistry.candidates(name)
    if #payloads == 0 then return "" end
    if #payloads == 1 then return render_payload(name, payload_with_requirements(name, payloads[1])) end
    local contract = ActionRegistry.get(name)
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

  local move_bits = {}
  if can_now.buy_from_shop then
    local rendered = candidate_prompt("buy_from_shop")
    if rendered ~= "" then move_bits[#move_bits + 1] = rendered end
  end
  if can_now.reroll_shop then move_bits[#move_bits + 1] = render_payload("reroll_shop", payload_with_requirements("reroll_shop", {})) .. ' (replaces the shop jokers with a new random set, not the voucher or packs)' end
  if can_now.sell_card then
    local rendered = collapsed_prompt("sell_card")
    if rendered ~= "" then move_bits[#move_bits + 1] = rendered end
  end
  if can_now.use_card then
    local rendered = candidate_prompt("use_card")
    if rendered ~= "" then move_bits[#move_bits + 1] = rendered end
  end
  if can_now.use_directional_card then
    move_bits[#move_bits + 1] = ActionRegistry.prompt("use_directional_card")
  end
  do
    -- Fail open, as force_router.lua:175 does: an unreadable count must not silently withdraw the
    -- hint for the action that may be the shop's only exit.
    local ok_tags, untagged = pcall(function()
      return require("facts.card_util").untagged_joker_count()
    end)
    if not ok_tags then
      require("util.metrics").incr("force_tag_count_error")
      print("[neuro-game] Could not count untagged jokers for the shop move line: "
        .. tostring(untagged))
    end
    if Actions.is_action_valid("set_joker_intents")
        and (not ok_tags or (tonumber(untagged) or 0) > 0) and not can.toggle_shop then
      local ok_prose, prose = pcall(require("core.enforce").untagged_joker_prose)
      move_bits[#move_bits + 1] = ActionRegistry.prompt("set_joker_intents")
        .. ' records what a joker is for'
        .. ((ok_prose and prose) and ('. ' .. prose) or '')
        .. '. toggle_shop is off the list until every joker has one'
    end
  end
  if can_now.toggle_shop then
    local exit_bit = render_payload("toggle_shop", payload_with_requirements("toggle_shop", {}))
      .. ' to leave the shop, carrying whatever is left in the bank into the next cash-out'
    if PlanGate.joker_order_required() then
      exit_bit = exit_bit .. ' -- ' .. PlanGate.joker_order_prose()
    end
    move_bits[#move_bits + 1] = exit_bit
  end
  local move_tail = ""
  if #move_bits > 0 then
    local range_bits = {}
    for _, name in ipairs(shop_areas) do
      range_bits[#range_bits + 1] = name .. " " .. index_list_prose(buyable[name])
    end
    if can.sell_card and G.jokers and G.jokers.cards and #G.jokers.cards > 0 then
      range_bits[#range_bits + 1] = "jokers " .. ForceHelpers.index_range(#G.jokers.cards)
    end
    if (can.sell_card or can.use_card or can.use_directional_card)
      and G.consumeables and G.consumeables.cards and #G.consumeables.cards > 0 then
      range_bits[#range_bits + 1] = "consumeables " .. ForceHelpers.index_range(#G.consumeables.cards)
    end
    local ranges = (#range_bits > 0) and table.concat(range_bits, ", ") or "none"
    move_tail = unbuyable_fact .. "Valid indices: " .. ranges
      .. ". \nYour move: " .. table.concat(move_bits, "; ") .. ". "
  end

  local cash = tonumber(G and G.GAME and G.GAME.dollars or 0) or 0

  local jn = (G.jokers and G.jokers.cards and #G.jokers.cards) or 0
  local ok_scoring, Scoring = pcall(require, "util.scoring")
  local xmult_state = (ok_scoring and Scoring and Scoring.owned_xmult_state and Scoring.owned_xmult_state()) or "none"
  local has_xmult = xmult_state ~= "none"

  local joker_priority = ""
  if jn == 0 then
    joker_priority = FactHints.emit("jokerless_priority", "You own NO jokers -- they are your scoring engine. When you own none, buy a joker before a voucher: a joker scores now, most vouchers pay off slowly (a few, like planet/economy vouchers, are run-defining). ")
  end

  local scaling_gap = ""
  if jn > 0 and not has_xmult then
    scaling_gap = FactHints.emit("scaling_gap",
      "None of your jokers multiply your score (no xMult); they are flat +Mult/+Chips. ")
  end

  local idle_slot_warn = ""
  do
    local posture = CtxEconomy.spend_posture()
    local text = ""
    if posture and posture.posture == "build" and (not js.full) and jn > 0 then
      local spend = CtxEconomy.spendable()
      local affordable_joker = false
      if G.shop_jokers and G.shop_jokers.cards then
        for _, c in ipairs(G.shop_jokers.cards) do
          if CardUtil.is_joker_like_card(c) and (tonumber(c.cost) or 1e9) <= spend then
            affordable_joker = true; break
          end
        end
      end
      if affordable_joker then
        text = "You have an empty joker slot -- it scores nothing empty, and your board is not carrying the ante curve yet. If an affordable joker here fits your build, filling it beats saving a few dollars. "
      end
    elseif posture and posture.posture == "bank" then
      text = "Every item here is priced above your safe-spend figure above, and your board already scores without one. Carried cash is the only income that compounds, so walking out with the bank intact is a move, not a skipped turn. "
    end
    if text ~= "" then idle_slot_warn = FactHints.emit("spend_posture", text) end
  end

  local broke_warn = ""
  if CtxEconomy.below_first_interest_step() then
    broke_warn = FactHints.emit("below_interest_step", "Your bank is below the first interest step, so it is earning nothing at all this round. Interest starts once you carry $5 out of the shop and grows with every further step -- worth weighing against a cheap card now. ")
  end

  local plan_line = FactHints.plan_note("shop")
  local plan_prompt = ""
  if buy_locked or plan_revision then
    plan_prompt = "Include the plan fields shown in the payload of your chosen action; they are validated and saved together with that action. Do not copy live cash, shop rows, joker roster, or boss text; those facts refresh separately. "
  end
  local interest_cap_warn = ""
  if not CtxEconomy.no_interest() and cash > CtxEconomy.interest_cap() and can.buy_from_shop then
    interest_cap_warn = string.format(
      "You hold $%d, above the $%d interest cap -- cash past the cap earns nothing sitting idle. If your build isn't clearing blinds comfortably, treat that excess as free fuel for power (level your main hand, add or upgrade an xMult joker, reroll for a fit, or sell a dead joker); if your build is already strong, there's little more to gain here. ",
      cash, CtxEconomy.interest_cap())
  end

  local build_mgmt = ""
  if can.set_joker_order and can.sell_card then
    build_mgmt = FactHints.emit("build_mgmt",
      "As you plan, weigh your joker build: reorder it with set_joker_order, and if a joker has stopped pulling its weight, sell_card frees a slot and cash for a better fit. Your call which. ")
  end

  local reroll_warn = ""
  do
    local rf = CtxEconomy.reroll_facts()
    if has_xmult and can.reroll_shop and type(rf.effective) == "number" and rf.effective > 0
      and rf.effective > CtxEconomy.safe_spend_keep_interest() then
      reroll_warn = "Rerolling now costs more than you can spend while keeping interest, and the price climbs each reroll -- reroll only when nothing here fits your build and you can spare it. "
    end
  end

  local scaling_curve_warn = ""
  do
    local curve = require("facts.economy_facts").scaling_curve()
    if curve then scaling_curve_warn = FactHints.emit("scaling_curve:" .. curve, curve) end
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
        unleveled_warn = FactHints.emit("unleveled_hands",
          "Your poker hands are all still at base level this deep in the run -- Planet cards (Celestial packs, or Planets in the shop) permanently raise a hand's chips and mult together. The hand type you play won't scale to later blinds until you level it. ")
      end
    end
  end

  local boss_primer = ""
  do
    local rr = G and G.GAME and G.GAME.round_resets
    local boss_key = rr and rr.blind_choices and rr.blind_choices.Boss
    local bdef = boss_key and G.P_BLINDS and G.P_BLINDS[boss_key]
    if bdef and boss_choice_is_public(rr) then
      local ok_brief, eff = pcall(require("facts.boss.render").boss_line, "select", boss_key, bdef)
      if ok_brief and type(eff) == "string" and eff ~= "" then
        boss_primer = FactHints.emit("shop_boss_primer", "Upcoming " .. eff .. " ")
      end
    end
  end

  local constraints = joker_slot_warn .. buffoon_full_warn .. cons_slot_warn .. blocked_consumable_warn
  if constraints ~= "" then constraints = "Constraints: " .. constraints end

  local notes = plan_line
    .. FactHints.joker_churn_note()
    .. plan_prompt
    .. build_mgmt
    .. boss_primer
    .. joker_priority
    .. idle_slot_warn
    .. broke_warn
    .. reroll_warn
    .. interest_cap_warn
    .. scaling_gap
    .. scaling_curve_warn
    .. unleveled_warn
    .. joker_order_hint
    .. edition_hint
    .. shop_target_fact

  notes = notes .. blueprint_chain_hint()

  local pending_confirm = ""
  do
    local ok_pc, note = pcall(require("handlers.shop_handlers").pending_confirmation_note, can)
    if ok_pc and type(note) == "string" then pending_confirm = note end
  end

  local query = "State: SHOP. "
    .. failed_action_warning()
    .. pending_confirm
    .. ForceHelpers.pending_gate_note(force_actions)
    .. ForceHelpers.repeat_pressure_note()
    .. notes
    .. constraints
    .. move_tail
  return {
    query = query:gsub("  +", " "),
    actions = force_actions
  }
end

return { build = build }
