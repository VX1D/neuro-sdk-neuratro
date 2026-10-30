local M = {}

local State = require("core.state")
local ActionResult = require("core.action_result")
local Utils = require("util.utils")

local INTEREST_GATE_ENTRY = 12 -- two interest steps: below this, little cash is lost

local function neuro() return G and G.NEURO end
local function set(list) return Utils.list_to_set(list) end
local function state_name() return State.get_state_name() end

local function records()
  local n = neuro()
  if not n then return nil end
  if type(n.gates) ~= "table" then n.gates = {} end
  return n.gates
end

local function shop_visit()
  local n = neuro() or {}
  return tostring(n.run_generation or 0) .. ":" .. tostring(n.shop_visit_epoch or 0)
end

local function joker_order_gap()
  local ok, gap = pcall(function() return require("util.scoring").joker_order_gap() end)
  return ok and gap or nil
end

local function joker_order_prose()
  local gap = joker_order_gap()
  if not gap then return nil end
  local unit = { mult = "Mult", chips = "Chips" }
  local sentences = {}
  for _, group in ipairs(gap.groups) do
    local parts = {}
    for _, b in ipairs(group.behind) do
      parts[#parts + 1] = string.format("slot %d %s (%s %s)", b.index,
        Utils.safe_name_or(b.card), Utils.signed(b.amount), unit[group.add])
    end
    local many = #parts > 1
    sentences[#sentences + 1] = string.format("%s %s right of slot %d %s (%s %s), so that multiplier never multiplies %s.",
      table.concat(parts, " and "), many and "sit" or "sits", group.pivot.index,
      Utils.safe_name_or(group.pivot.card), Utils.fmt_xmult(group.pivot.factor), unit[group.add],
      many and "them" or "it")
  end
  return "Jokers fire left to right: " .. table.concat(sentences, " ")
    .. " Moving a joker changes the order; leaving the shop with joker_order_confirmed true leaves on the current order."
end

local LEAVE_BRIEF = "Nothing was executed: leaving was held once for the review shown in the shop decision that follows; leaving again leaves."

local DEFINITIONS = {
  {
    id = "interest_engine_off", stage = "admission", actions = set({ "leave_shop" }),
    applies = function()
      if state_name() ~= "SHOP" or not require("facts.economy_facts").below_first_interest_step() then return false end
      return (tonumber(G.NEURO.shop_entry_dollars) or 0) >= INTEREST_GATE_ENTRY
    end,
    key = function() return "interest:" .. shop_visit() end,
    text = function()
      return "Leaving the shop now means the next cash-out pays no interest: interest counts only the money you carry into the blind, and your bank is below the first step (the Shop section shows it and what you entered with). Dollars carry to the next shop either way. Leave the shop again to leave."
    end,
    brief = LEAVE_BRIEF,
    acknowledged_by = set({ "leave_shop", "record_plan" }),
  },
  {
    id = "order_think", stage = "admission", actions = set({ "leave_shop" }),
    applies = function()
      if state_name() ~= "SHOP" or not (G.jokers and G.jokers.cards and #G.jokers.cards >= 2) then return false end
      local PublicCard = require("facts.public_card_identity")
      for _, card in ipairs(G.jokers.cards) do
        if type(card) == "table" and not PublicCard.is_public(card) then return false end
      end
      return require("facts.card_util").order_matters() and joker_order_gap() == nil
    end,
    key = function() return require("facts.card_util").joker_composition_signature() end,
    text = function()
      return "Your joker lineup changed. Jokers trigger left to right, so their order changes the score."
        .. " Moving a joker changes the order; leaving the shop again leaves it with the current order."
    end,
    brief = LEAVE_BRIEF,
    acknowledged_by = set({ "set_joker_order", "leave_shop" }),
  },
  {
    id = "joker_order", stage = "plan", actions = set({ "leave_shop" }),
    applies = function() return state_name() == "SHOP" and joker_order_gap() ~= nil end,
    key = function()
      local gap = joker_order_gap()
      return "order:" .. shop_visit() .. ":" .. tostring(gap and gap.signature)
    end,
    confirms = function(data) return data.joker_order_confirmed == true end,
    text = joker_order_prose,
    brief = "Nothing was executed: the joker order review is in the decision that follows; move a joker to change the order, or leave with joker_order_confirmed true to keep it.",
    acknowledged_by = set({ "leave_shop" }),
  },
  {
    id = "sell_joker", stage = "handler", actions = set({ "sell_card" }),
    applies = function(ctx) return ctx ~= nil end,
    key = function() return require("handlers.shop_handlers").sell_review_key() end,
    text = function(ctx) return ctx.text() end,
    brief = "Nothing was sold: the sell review is in the decision that follows, and the next legal sale there is final.",
  },
  {
    id = "buy_voucher", stage = "handler", actions = set({ "buy_from_shop" }),
    applies = function(ctx) return ctx ~= nil end,
    key = function() return require("handlers.shop_handlers").voucher_review_key() end,
    text = function(ctx) return ctx.text() end,
    brief = "Nothing was bought: the voucher review is in the shop decision that follows, and the next legal voucher buy there is final.",
  },
}
local BY_ID = {}
for _, def in ipairs(DEFINITIONS) do BY_ID[def.id] = def end
M.DEFINITIONS = DEFINITIONS

local function key_of(def, ctx)
  local ok, key = pcall(def.key, ctx)
  if not ok or key == nil or key == "" then return "<unavailable:" .. def.id .. ">" end
  return tostring(key)
end

local function settled(def, key)
  local rs = records()
  local rec = rs and rs[def.id]
  return rec ~= nil and rec.key == key
end

local function blocks(def, name, data, ctx)
  if not (def.actions[name] and def.applies(ctx)) then return nil end
  local key = key_of(def, ctx)
  if settled(def, key) or (def.confirms and def.confirms(data or {})) then return nil end
  return key
end

function M.check(stage, name, data, ctx)
  local rs = records()
  if not rs then return nil end
  local texts, briefs, marks, code, said = {}, {}, {}, nil, {}
  for _, def in ipairs(DEFINITIONS) do
    local key = def.stage == stage and blocks(def, name, data, ctx)
    if key then
      local text = def.text and def.text(ctx)
      texts[#texts + 1] = text
      if def.brief and not said[def.brief] then said[def.brief], briefs[#briefs + 1] = true, def.brief end
      code = "CONFIRMATION_REQUIRED"
      if not def.confirms then marks[#marks + 1] = { id = def.id, key = key, target = ctx and ctx.target, text = text } end
    elseif def.stage == stage and def.actions[name] and rs[def.id] then
      rs[def.id].review = nil
    end
  end
  if not code then return nil end
  local brief = #briefs > 0 and table.concat(briefs, " ") or nil
  return ActionResult.error(code, #texts > 0 and table.concat(texts, "\n\n") or brief,
    { gate_marks = marks, brief = brief })
end

function M.result_message(rejection)
  if type(rejection) ~= "table" then return nil end
  local message = rejection.brief or rejection.message
  if rejection.note then message = message and (message .. " " .. rejection.note) or rejection.note end
  return message
end

function M.delivered(rejection, text)
  local rs = records()
  if not (rs and type(rejection) == "table") then return end
  for _, mark in ipairs(rejection.gate_marks or {}) do
    rs[mark.id] = { key = mark.key, target = mark.target, review = mark.text, delivered = true }
  end
  if rejection.proposal then M.open_proposal(rejection.proposal, text or rejection.message, rejection.facts) end
end

local function offers(def, offered)
  for _, name in ipairs(offered or {}) do
    if def.actions[name] then return true end
  end
  return false
end

function M.review_note(offered)
  local rs = records()
  if not rs then return "" end
  local out = {}
  for _, def in ipairs(DEFINITIONS) do
    local rec = rs[def.id]
    if rec and rec.review and offers(def, offered) and settled(def, key_of(def)) then
      local text = rec.review
      if def.stage == "admission" then
        local ok, live = pcall(function() return def.applies() and def.text() or nil end)
        text = ok and live or nil
      end
      if text then out[#out + 1] = text end
    end
  end
  return #out > 0 and (table.concat(out, " ") .. " ") or ""
end

function M.would_review(name)
  if not neuro() then return false end
  for _, def in ipairs(DEFINITIONS) do
    if def.stage ~= "plan" and blocks(def, name) then return true end
  end
  return false
end

function M.snapshot(name)
  local out = {}
  for _, def in ipairs(DEFINITIONS) do
    if def.acknowledged_by and def.acknowledged_by[name] then
      out[#out + 1] = { id = def.id, key = key_of(def) }
    end
  end
  return out
end

function M.acknowledge(snapshot)
  local rs = records()
  if not rs then return end
  for _, entry in ipairs(snapshot or {}) do rs[entry.id] = { key = entry.key } end
end

function M.reviewed_target(id)
  local def = BY_ID[id]
  if not (def and settled(def, key_of(def))) then return nil end
  return records()[id].target
end

function M.reviewed(id)
  local def, rs = BY_ID[id], records()
  local rec = rs and rs[id]
  return def ~= nil and rec ~= nil and rec.delivered == true and settled(def, key_of(def))
end

function M.applies(id)
  local def = BY_ID[id]
  if not (def and neuro()) then return false end
  local ok, live = pcall(def.applies)
  return ok and live == true
end

function M.pending(id)
  local def = BY_ID[id]
  return def ~= nil and neuro() ~= nil and def.applies() and not settled(def, key_of(def))
end

function M.text(id, ctx)
  local def = BY_ID[id]
  return def.text and def.text(ctx) or def.brief
end

function M.forget(stage)
  local rs = records()
  if not rs then return end
  for _, def in ipairs(DEFINITIONS) do
    if stage == nil or def.stage == stage then rs[def.id] = nil end
  end
end


local HAND_MUTATORS = set({
  "play_hand", "discard_hand", "use_consumable", "use_directional_consumable", "choose_pack_card",
  "choose_directional_pack_card", "sell_card", "set_joker_order", "record_joker_roles", "record_plan",
  "buy_from_shop", "reroll_shop", "leave_shop", "select_blind", "skip_blind", "skip_pack", "cash_out",
})

local function card_key(card)
  if type(card) ~= "table" then return "?" end
  if not require("facts.public_card_identity").is_public(card) then return "hidden" end
  local base, center, ability = card.base or {}, card.config and card.config.center or {}, card.ability or {}
  local edition = card.edition
  local edition_key = type(edition) == "table"
    and table.concat({ tostring(edition.foil), tostring(edition.holo), tostring(edition.polychrome), tostring(edition.negative) }, ",")
    or tostring(edition)
  return table.concat({
    tostring(card.sort_id), tostring(base.value), tostring(base.suit), tostring(center.key),
    tostring(card.seal), edition_key, tostring(card.debuff),
    tostring(ability.name), tostring(ability.effect), Utils.stable_repr(ability.extra, 3),
  }, "/")
end

local function hand_context_key()
  local n = neuro()
  local game, round = G.GAME or {}, G.GAME and G.GAME.current_round or {}
  local parts = {
    tostring(n.state), tostring(n.state_enter_serial), tostring(n.decision_serial),
    tostring(round.hands_left), tostring(round.discards_left), tostring(round.discards_used),
    tostring(game.chips), tostring(game.dollars),
  }
  for i, card in ipairs(G.hand and G.hand.cards or {}) do parts[#parts + 1] = "h" .. i .. ":" .. card_key(card) end
  for i, card in ipairs(G.jokers and G.jokers.cards or {}) do parts[#parts + 1] = "j" .. i .. ":" .. card_key(card) end
  local blind = game.blind or {}
  parts[#parts + 1] = table.concat({
    "b", tostring(blind.name), tostring(blind.disabled), tostring(blind.block_play), Utils.stable_repr(blind.debuff, 3),
    tostring(blind.config and blind.config.blind and blind.config.blind.key),
  }, ":")
  local names = {}
  for name in pairs(game.hands or {}) do names[#names + 1] = tostring(name) end
  table.sort(names)
  for _, name in ipairs(names) do
    local h = game.hands[name] or {}
    parts[#parts + 1] = table.concat({ "l", name, tostring(h.level), tostring(h.chips), tostring(h.mult), tostring(h.played) }, ":")
  end
  return table.concat(parts, "|")
end

local function decision()
  local n = neuro()
  if not n then return nil end
  if type(n.play_decision) ~= "table" then n.play_decision = { revision = 0 } end
  return n.play_decision
end

function M.proposal()
  local n = neuro()
  local p = n and n.play_proposal
  return type(p) == "table" and p or nil
end

function M.proposal_ref()
  local p = M.proposal()
  return p and p.ref or nil
end

function M.close_proposal(p, outcome)
  local n, d = neuro(), decision()
  if not (p and M.proposal() == p) then return false end
  if (outcome == "cancelled" and p.phase ~= "ready") or (outcome == "settled" and p.phase ~= "committing") then
    return false
  end
  n.play_proposal, p.phase = nil, outcome
  if outcome == "cancelled" then
    d.final_play_revision = d.revision
    d.last_decline = { revision = d.revision, indices = p.indices, hand_type = p.hand_type,
      dominant_alt = p.dominant_alt }
  end
  if outcome ~= "settled" then require("core.plan_transaction").release_hand_proposal(p.ref) end
  return true
end

function M.invalidate() return M.close_proposal(M.proposal(), "invalidated") end

local function advance(d, key)
  d.key, d.revision = key, d.revision + 1
  d.final_play_revision, d.last_decline = nil, nil
  M.invalidate()
end

function M.context_revision()
  local d = decision()
  if not d then return 0 end
  local key = hand_context_key()
  if d.key == nil then d.key = key elseif d.key ~= key then advance(d, key) end
  return d.revision
end

function M.observe_context_changed()
  local d = decision()
  if d then advance(d, hand_context_key()) end
end

local function identity()
  local n = neuro()
  return tonumber(n.run_generation) or 0, tonumber(n.state_enter_serial) or 0, tonumber(n.decision_serial) or 0
end

function M.proposal_valid(p)
  if not (neuro() and p and M.proposal() == p) then return false end
  local revision = M.context_revision()
  local gen, screen, serial = identity()
  return M.proposal() == p and p.run_generation == gen and p.state_enter_serial == screen
    and p.decision_serial == serial and p.context_revision == revision
end

function M.open_proposal(fields, verdict, facts)
  local n = neuro()
  if not (n and type(fields) == "table") or M.proposal() then return nil end
  if fields.context_revision ~= M.context_revision() then return nil end
  local gen, screen, serial = identity()
  if fields.decision_serial ~= serial or fields.state_enter_serial ~= screen or fields.run_generation ~= gen then
    return nil
  end
  n.play_proposal_serial = (tonumber(n.play_proposal_serial) or 0) + 1
  local p = {
    ref = string.format("proposal-%d-%d", gen, n.play_proposal_serial), phase = "ready",
    verdict = verdict, facts = facts, created_at = os.clock(),
    run_generation = gen, state_enter_serial = screen, decision_serial = serial,
    context_revision = fields.context_revision, signature = fields.signature, content = fields.content,
    indices = { unpack(fields.indices or {}) }, hand_type = fields.hand_type, dominant_alt = fields.dominant_alt,
  }
  n.play_proposal = p
  return p
end

function M.proposal_fields(fields)
  local gen, screen, serial = identity()
  fields.run_generation, fields.state_enter_serial, fields.decision_serial = gen, screen, serial
  fields.context_revision = M.context_revision()
  return fields
end

function M.begin_commit(p)
  if not (p and p.phase == "ready" and M.proposal_valid(p)) then return false end
  p.phase = "committing"
  return true
end

function M.commit_is_current(p)
  return p ~= nil and p.phase == "committing" and M.proposal_valid(p)
end

function M.rollback_commit(p)
  if not (p and M.proposal() == p and p.phase == "committing") then return false end
  if not M.proposal_valid(p) then
    M.close_proposal(p, "invalidated")
    return false
  end
  p.phase = "ready"
  return true
end

function M.final_play_required()
  local d = decision()
  return d ~= nil and d.final_play_revision == d.revision
end

function M.decline_context()
  M.context_revision()
  local d = decision()
  local rec = d and d.last_decline
  if type(rec) ~= "table" or rec.revision ~= d.revision or d.final_play_revision ~= d.revision then return nil end
  return { indices = rec.indices, hand_type = rec.hand_type, dominant_alt = rec.dominant_alt }
end

function M.stale_mutator(name)
  return M.proposal() ~= nil and HAND_MUTATORS[name] == true
end

function M.snapshot_proposal()
  local p = M.proposal()
  local gen, screen = identity()
  return { proposal_ref = p and p.ref, phase = p and p.phase or "proposal",
    context_revision = M.context_revision(), run_generation = gen, state_enter_serial = screen }
end

function M.snapshot_is_current(s)
  if type(s) ~= "table" or not neuro() then return false end
  local gen, screen = identity()
  if s.run_generation ~= gen or s.state_enter_serial ~= screen or s.context_revision ~= M.context_revision() then
    return false
  end
  local p = M.proposal()
  if s.proposal_ref == nil then return p == nil and s.phase == "proposal" end
  return p ~= nil and s.proposal_ref == p.ref and s.phase == p.phase
end

function M.confirmation_mode_changed(enabled)
  if enabled ~= true then
    local p = M.proposal()
    if p and p.phase == "ready" then M.close_proposal(p, "invalidated") end
    local d = decision()
    if d then d.final_play_revision, d.last_decline = nil, nil end
  end
  pcall(function() require("core.window").withdraw("confirmation_mode_changed") end)
end

function M.reset()
  local n = neuro()
  if n then n.gates, n.play_proposal, n.play_decision = nil, nil, nil end
end


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
  if b and b.boss and state_name() ~= "BLIND_SELECT" then
    local ok_bm, BossModel = pcall(require, "facts.boss.model")
    local key = ok_bm and BossModel.resolve_key and BossModel.resolve_key(b)
    return table.concat({ tostring(ante), tostring(key or b.name or "?") }, "|")
  end
  local upcoming = rr and rr.blind_choices and rr.blind_choices.Boss
  if not upcoming or not require("facts.boss.model").upcoming_is_public(rr) then return nil end
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

M.current_blind_scope = blind_scope
M.current_economy_scope = economy_scope
M.current_build_scope = build_scope
M.current_boss_scope = boss_scope
local function plan_current(plan, field, scope_of, needs_scope)
  local value = plan and plan[field]
  if not value then return value end
  local scope = scope_of()
  return (not needs_scope or scope ~= nil) and plan[field .. "_scope"] == scope
end
function M.hand_plan_is_current(plan) return plan_current(plan, "hand", blind_scope, true) end
function M.money_plan_is_current(plan) return plan_current(plan, "money", economy_scope) end
function M.build_plan_is_current(plan) return plan_current(plan, "build", build_scope) end
function M.boss_plan_is_current(plan) return plan_current(plan, "boss", boss_scope, true) end
function M.hand_focus_is_current(plan)
  local scope = blind_scope()
  return plan and type(plan.hand_focus) == "table" and scope ~= nil
    and plan.hand_focus_scope == scope
end
M.shop_required_fields = stale_shop_fields
M.pending_shop_fields = pending_shop_fields

local function settle_pending(hand, build, money)
  local pending = pending_shop_fields()
  if hand then pending.hand = nil end
  if build then pending.build = nil end
  if money then pending.money = nil end
  G.NEURO.shop_plan_revision_required = next(pending) and pending or nil
end

function M.action_requirements(current_state, action_name)
  return { plan = require("core.plan_requirements").required(current_state, action_name) }
end

function M.complete_requirements(requirements, shop_visit_epoch)
  if shop_visit_epoch == nil or not (G and G.NEURO) then return end
  local fields = requirements and requirements.plan or {}
  settle_pending(fields.hand, fields.build, fields.money)
end

function M.buy_locked()
  local n = G and G.NEURO
  return state_name() == "SHOP"
    and not (n and n.econ_plan_ok and M.money_plan_is_current(n.plan))
end

function M.shop_needs_revision()
  if state_name() ~= "SHOP" then return false end
  return next(stale_shop_fields()) ~= nil
end

local function live_shop_box()
  local box = G and G.shop
  if type(box) == "table" and not box.REMOVED then return box end
  return nil
end

function M.shop_visit_open()
  return live_shop_box() ~= nil
end

function M.bind_shop_visit()
  local box = live_shop_box()
  if box then box.neuro_shop_visit = shop_visit() end
end

function M.arrive_in_shop()
  if not (G and G.NEURO) then return end
  local box = live_shop_box()
  if not (box and box.neuro_shop_visit == shop_visit()) then M.enter_shop() end
  M.bind_shop_visit()
end

local function age_economy()
  G.NEURO.economy_epoch = (tonumber(G.NEURO.economy_epoch) or 0) + 1
  G.NEURO.econ_plan_ok = false
end

function M.enter_shop()
  if not (G and G.NEURO) then return end
  G.NEURO.shop_visit_epoch = (tonumber(G.NEURO.shop_visit_epoch) or 0) + 1
  age_economy()
  G.NEURO.shop_plan_revision_required = nil
  G.NEURO.shop_entry_pending = true
  M.settle_shop_entry()
end

function M.settle_shop_entry()
  if not (G and G.NEURO and G.NEURO.shop_entry_pending) then return end
  G.NEURO.shop_entry_dollars = math.floor(tonumber(G.GAME and G.GAME.dollars or 0) or 0)
  if require("util.utils").engine_settled() then G.NEURO.shop_entry_pending = nil end
end

function M.mark_shop_changed(action_name)
  if not (G and G.NEURO) then return end
  local pending = pending_shop_fields()
  if action_name == "reroll_shop" then age_economy() end
  -- A buy carries cash but not the build plan, leaving that plan pending.
  if action_name == "buy_from_shop" then pending.build = true end
  G.NEURO.shop_plan_revision_required = next(pending) and pending or nil
end

function M.mark_written(has_hand, has_build, has_money)
  if not (G and G.NEURO) then return end
  local plan = G.NEURO.plan
  if has_money then G.NEURO.econ_plan_ok = M.money_plan_is_current(plan) end
  if state_name() == "SHOP" then settle_pending(has_hand, has_build, has_money) end
end

function M.begin_cycle()
  if not (G and G.NEURO) then return end
  local cur_ante = require("facts.game_facts").ante(0)
  local prev_ante = G.NEURO._prev_ante or 0
  if cur_ante ~= prev_ante then
    age_economy()
    G.NEURO._prev_ante = cur_ante
  end
end


return M
