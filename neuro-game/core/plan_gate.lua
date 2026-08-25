local M = {}

local SHOP_MUTATION_AGES = {
  buy_from_shop = { build = true },
}

local ECONOMY_AGING_ACTIONS = {
  reroll_shop = true,
}

local function state_name() return require("core.state").get_state_name() end

local function blind_scope()
  local gm = G and G.GAME
  local rr = gm and gm.round_resets
  if not rr then return nil end
  local kind = gm.blind_on_deck
  if kind ~= "Small" and kind ~= "Big" and kind ~= "Boss" then
    kind = require("core.actions").get_selectable_blind_key()
  end
  if not kind then return nil end
  local key = rr.blind_choices and rr.blind_choices[kind] or nil
  return table.concat({ tostring(rr.ante or 0), tostring(kind), tostring(key or "?") }, "|")
end

local function economy_scope()
  local n = G and G.NEURO or {}
  local ante = require("facts.game_facts").ante(0)
  local ok_cs, cs = pcall(require("facts.card_util").consumable_slot_status)
  local slots = (ok_cs and type(cs) == "table")
    and (tostring(cs.count or 0) .. "/" .. tostring(cs.limit or 0)) or "?"
  local ok_sp, spend = pcall(require("facts.economy_facts").spendable)
  local band = (ok_sp and type(spend) == "number" and spend > 0) and "solvent" or "broke"
  return table.concat({
    tostring(n.run_generation or 0),
    tostring(ante),
    tostring(n.shop_visit_epoch or 0),
    tostring(n.economy_epoch or 0),
    slots,
    band,
  }, "|")
end

local function build_scope()
  return require("facts.card_util").joker_build_signature()
end

local function boss_scope()
  local rr = G and G.GAME and G.GAME.round_resets
  local ante = (rr and rr.ante) or 0
  local b = G and G.GAME and G.GAME.blind
  if b and b.boss and require("core.state").get_state_name() ~= "BLIND_SELECT" then
    local ok_bm, BossModel = pcall(require, "facts.boss.model")
    local key = ok_bm and BossModel.resolve_key and BossModel.resolve_key(b)
    return table.concat({ tostring(ante), tostring(key or b.name or "?") }, "|")
  end
  local upcoming = rr and rr.blind_choices and rr.blind_choices.Boss
  if not upcoming then return nil end
  return table.concat({ tostring(ante), tostring(upcoming) }, "|")
end

local function pending_shop_fields()
  local raw = G and G.NEURO and G.NEURO.shop_plan_revision_required
  if raw == true then return { hand = true, build = true, money = true } end
  return type(raw) == "table" and raw or {}
end

local function stale_shop_fields()
  local pending = pending_shop_fields()
  if not next(pending) then return pending end
  local plan = G and G.NEURO and G.NEURO.plan
  local stale = {}
  if pending.hand and not M.hand_plan_is_current(plan) then stale.hand = true end
  if pending.build and not M.build_plan_is_current(plan) then stale.build = true end
  if pending.money and not M.money_plan_is_current(plan) then stale.money = true end
  return stale
end

local function joker_order_gap()
  local ok, gap = pcall(function() return require("util.scoring").joker_order_gap() end)
  return ok and gap or nil
end
M.joker_order_gap = joker_order_gap

function M.joker_order_required()
  local gap = joker_order_gap()
  if not gap then return nil end
  local n = G and G.NEURO
  if n and n.joker_order_ack == gap.signature then return nil end
  return gap
end

function M.joker_order_prose()
  local gap = joker_order_gap()
  if not gap then return nil end
  local Utils = require("util.utils")
  local parts = {}
  for _, b in ipairs(gap.behind) do
    parts[#parts + 1] = string.format("slot %d %s (%s Mult)", b.index,
      Utils.safe_name_or(b.card), Utils.signed(b.mult))
  end
  local many = #parts > 1
  return string.format(
    "Jokers fire left to right: %s %s right of slot %d %s (%s Mult), so that xMult never multiplies %s."
      .. " set_joker_order moves a joker; toggle_shop with joker_order_confirmed true leaves on the current order.",
    table.concat(parts, " and "), many and "sit" or "sits", gap.pivot.index,
    Utils.safe_name_or(gap.pivot.card), Utils.fmt_xmult(gap.pivot.xmult), many and "them" or "it")
end

function M.ack_joker_order()
  local gap = joker_order_gap()
  if gap and G and G.NEURO then G.NEURO.joker_order_ack = gap.signature end
end

function M.current_blind_scope() return blind_scope() end
function M.current_economy_scope() return economy_scope() end
function M.current_build_scope() return build_scope() end
function M.current_boss_scope() return boss_scope() end
function M.hand_plan_is_current(plan)
  local scope = blind_scope()
  return plan and plan.hand and scope ~= nil and plan.hand_scope == scope
end
function M.money_plan_is_current(plan)
  return plan and plan.money and plan.money_scope == economy_scope()
end
function M.build_plan_is_current(plan)
  return plan and plan.build and plan.build_scope == build_scope()
end
function M.boss_plan_is_current(plan)
  local scope = boss_scope()
  return plan and plan.boss and scope ~= nil and plan.boss_scope == scope
end
function M.hand_focus_is_current(plan)
  local scope = blind_scope()
  return plan and type(plan.hand_focus) == "table" and scope ~= nil
    and plan.hand_focus_scope == scope
end
function M.shop_required_fields() return stale_shop_fields() end

function M.action_requirements(current_state, action_name)
  local requirements = { plan = {} }
  if current_state == "SHOP" then
    if action_name == "buy_from_shop" or action_name == "reroll_shop" then
      requirements.plan.money = true
    elseif action_name == "sell_card" then
      requirements.plan.build, requirements.plan.money = true, true
    elseif action_name == "use_card" or action_name == "use_directional_card" then
      requirements.plan.hand, requirements.plan.build = true, true
    elseif action_name == "toggle_shop" then
      for field, required in pairs(stale_shop_fields()) do
        if required then requirements.plan[field] = true end
      end
      if M.joker_order_required() then requirements.joker_order = true end
    end
  elseif current_state == "BLIND_SELECT" and action_name == "select_blind" then
    requirements.plan.hand, requirements.plan.build = true, true
    if require("core.actions").get_selectable_blind_key() == "Boss" then
      requirements.plan.boss = true
    end
  elseif current_state == "SELECTING_HAND" and (action_name == "play_hand" or action_name == "discard_hand")
      and G.GAME and G.GAME.blind and G.GAME.blind.boss
      and not M.boss_plan_is_current(G and G.NEURO and G.NEURO.plan) then
    requirements.plan.boss = true
  end
  return requirements
end

function M.complete_requirements(requirements, shop_visit_epoch)
  if not (G and G.NEURO) then return false end
  local fields = requirements and requirements.plan or {}
  if shop_visit_epoch ~= nil then
    local pending = pending_shop_fields()
    if fields.hand then pending.hand = nil end
    if fields.build then pending.build = nil end
    if fields.money then pending.money = nil end
    G.NEURO.shop_plan_revision_required = next(pending) and pending or nil
  end
  return true
end

function M.buy_locked()
  local n = G and G.NEURO
  return state_name() == "SHOP"
    and not (n and n.econ_plan_ok and M.money_plan_is_current(n.plan))
end

local function blind_needs_plan()
  if state_name() ~= "BLIND_SELECT" then return false end
  local n = G and G.NEURO
  return not (n and n.blind_plan_ok and M.hand_plan_is_current(n.plan))
end
function M.shop_needs_revision()
  if state_name() ~= "SHOP" then return false end
  return next(stale_shop_fields()) ~= nil
end

function M.enter_shop()
  if not (G and G.NEURO) then return end
  G.NEURO.shop_visit_epoch = (tonumber(G.NEURO.shop_visit_epoch) or 0) + 1
  G.NEURO.economy_epoch = (tonumber(G.NEURO.economy_epoch) or 0) + 1
  G.NEURO.econ_plan_ok = false
  G.NEURO.shop_plan_revision_required = nil
  G.NEURO.joker_order_ack = nil
  G.NEURO.last_sell_reject = nil
  G.NEURO.shop_entry_pending = true
  M.settle_shop_entry()
  require("core.decision_window").reset_field("shop_economy")
end

function M.settle_shop_entry()
  if not (G and G.NEURO and G.NEURO.shop_entry_pending) then return end
  G.NEURO.shop_entry_dollars = math.floor(tonumber(G.GAME and G.GAME.dollars or 0) or 0)
  if require("util.utils").engine_settled() then G.NEURO.shop_entry_pending = nil end
end

function M.mark_shop_changed(action_name)
  if not (G and G.NEURO) then return end
  local pending = pending_shop_fields()
  if ECONOMY_AGING_ACTIONS[action_name] then
    G.NEURO.economy_epoch = (tonumber(G.NEURO.economy_epoch) or 0) + 1
    G.NEURO.econ_plan_ok = false
  end
  local carried = M.action_requirements("SHOP", action_name).plan
  for field in pairs(SHOP_MUTATION_AGES[action_name] or {}) do
    if not carried[field] then pending[field] = true end
  end
  G.NEURO.shop_plan_revision_required = next(pending) and pending or nil
end

function M.shop_revision_is_complete(has_hand, has_build, has_money)
  local required = stale_shop_fields()
  return (not required.hand or has_hand)
    and (not required.build or has_build)
    and (not required.money or has_money)
end

function M.mark_written(has_hand, has_build, has_money)
  if not (G and G.NEURO) then return end
  local plan = G.NEURO.plan
  if has_money then G.NEURO.econ_plan_ok = M.money_plan_is_current(plan) end
  if has_hand then
    G.NEURO.blind_plan_ok = M.hand_plan_is_current(plan)
    G.NEURO.blind_plan_scope = blind_scope()
  end
  if state_name() == "SHOP" then
    local required = pending_shop_fields()
    if has_hand then required.hand = nil end
    if has_build then required.build = nil end
    if has_money then required.money = nil end
    G.NEURO.shop_plan_revision_required = next(required) and required or nil
  end
end

function M.begin_cycle()
  if not (G and G.NEURO) then return end
  local cur_ante = require("facts.game_facts").ante(0)
  local prev_ante = G.NEURO._prev_ante or 0
  if cur_ante ~= prev_ante then
    G.NEURO.economy_epoch = (tonumber(G.NEURO.economy_epoch) or 0) + 1
    G.NEURO.econ_plan_ok = false
    G.NEURO._prev_ante = cur_ante
  end
  local scope = blind_scope()
  if scope ~= G.NEURO.blind_plan_scope then G.NEURO.blind_plan_ok = false end
end

if rawget(_G, "NEURO_TEST") then M._test = { blind_needs_plan = blind_needs_plan } end

return M
