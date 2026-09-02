local M = {}

local CardArea = require("facts.card_area_util")
local Utils = require("util.utils")
local GameFacts = require("facts.game_facts")

local function clean(s)
  if type(s) ~= "string" then return nil end
  s = Utils.normalize_ws(s)
  if #s == 0 then return nil end
  return s
end

local function visible_hand_name(value, field)
  local names = GameFacts.visible_hand_names()
  local allowed = names and (" Send one of: " .. table.concat(names, ", ") .. ".")
    or " No hand type is visible yet, so this field cannot be set."
  if type(value) ~= "string" then
    return nil, field .. " must be a currently visible hand name." .. allowed
  end
  local cleaned = Utils.normalize_ws(value)
  local hand = G and G.GAME and G.GAME.hands and G.GAME.hands[cleaned]
  if type(hand) ~= "table" or hand.visible ~= true then
    return nil, field .. " must match a currently visible hand name exactly." .. allowed
  end
  return cleaned
end

local function clean_hand_focus(raw)
  if raw == nil then return nil end
  if type(raw) ~= "table" then return nil, "hand_focus must be an object." end
  for key in pairs(raw) do
    if key ~= "primary" and key ~= "fallback" then
      return nil, "hand_focus supports only primary and fallback."
    end
  end
  local primary, primary_err = visible_hand_name(raw.primary, "hand_focus.primary")
  if not primary then return nil, primary_err end
  local fallback, fallback_err
  if raw.fallback ~= nil then
    fallback, fallback_err = visible_hand_name(raw.fallback, "hand_focus.fallback")
    if not fallback then return nil, fallback_err end
  end
  return { primary = primary, fallback = fallback }
end

local VALID_INTENT = { CORE = true, SCALING = true, HOLD = true, CHANGE = true }
local function identity_value(value)
  if value == nil then return "-" end
  local text = tostring(value)
  return type(value) .. ":" .. tostring(#text) .. ":" .. text
end

local function joker_intents_identity()
  local parts = {}
  for i = 1, #G.jokers.cards do
    local card = G.jokers.cards[i]
    local sid = card and card.sort_id
    local intent = sid ~= nil and G.NEURO.joker_intents[sid] or nil
    parts[#parts + 1] = identity_value(sid)
      .. "|" .. identity_value(intent and intent.tag)
      .. "|" .. identity_value(intent and intent.note)
  end
  return table.concat(parts, ";")
end

local function prepare_joker_intents(data)
  if not (G and G.jokers and G.jokers.cards) then
    return nil, "Jokers are not available yet."
  end
  local njok = #G.jokers.cards
  if njok < 1 then return nil, "You have no jokers to tag." end
  local intents = data and data.intents
  if type(intents) ~= "table" or #intents == 0 then
    return nil, "Provide intents: a list of { index, tag }."
  end
  local seen, resolved = {}, {}
  for _, entry in ipairs(intents) do
    if type(entry) ~= "table" then return nil, "Each intent must be an object { index, tag }." end
    local idx, tag = entry.index, entry.tag
    if not VALID_INTENT[tag] then
      return nil, "Invalid tag '" .. tostring(tag) .. "'. Use CORE, SCALING, HOLD, or CHANGE."
    end
    local ok_idx, err_idx = CardArea.validate_index(idx, njok, "index", "jokers")
    if not ok_idx then return nil, err_idx end
    if seen[idx] then return nil, "Duplicate index " .. tostring(idx) .. " in one call." end
    seen[idx] = true
    local note = clean(entry.note)
    local clear_note = type(entry.note) == "string" and note == nil
    resolved[#resolved + 1] = { card = G.jokers.cards[idx], idx = idx, tag = tag, note = note,
      clear_note = clear_note }
  end
  local authored_ante = GameFacts.ante(0)
  local authored_decision = tonumber(G.NEURO and G.NEURO.decision_serial) or 0
  return function()
    if not G.NEURO then return "Tagged." end
    G.NEURO.joker_intents = G.NEURO.joker_intents or {}
    G.NEURO.joker_intent_revision = (tonumber(G.NEURO.joker_intent_revision) or 0) + 1
    local provenance = {
      ante = authored_ante,
      decision_serial = authored_decision,
      revision = G.NEURO.joker_intent_revision,
    }
    local parts = {}
    for _, r in ipairs(resolved) do
      local sid = r.card and r.card.sort_id
      if sid then
        local prior = G.NEURO.joker_intents[sid]
        local note
        if r.clear_note then
          note = nil
        elseif r.note then
          note = r.note
        else
          note = prior and prior.note or nil
        end
        G.NEURO.joker_intents[sid] = { tag = r.tag, note = note, provenance = provenance }
      end
      local label = tostring(r.idx) .. "=" .. r.tag .. " (" .. Utils.real_name_or(r.card) .. ")"
      if r.note then
        label = label .. " note: \"" .. r.note .. "\""
      elseif r.clear_note then label = label .. " note cleared" end
      parts[#parts + 1] = label
    end
    local identity = joker_intents_identity()
    local prev_identity = G.NEURO.joker_intents_ack_identity
    G.NEURO.joker_intents_ack_identity = identity
    if identity == prev_identity then return "Tagged." end
    return "Tagged: " .. table.concat(parts, ", ")
  end
end

local function prepare_plan(data, required_fields, scope_snapshot, explicitly_written)
  data = data or {}
  local p = (type(data.plan) == "table") and data.plan or {}
  local raw_hand = data.hand_plan ~= nil and data.hand_plan or p.hand_plan
  local raw_build = data.build_plan ~= nil and data.build_plan or p.build_plan
  local raw_money = data.money_plan ~= nil and data.money_plan or p.money_plan
  local raw_boss = data.boss_plan ~= nil and data.boss_plan or p.boss_plan
  local raw_focus = data.hand_focus ~= nil and data.hand_focus or p.hand_focus
  local written = explicitly_written or {
    hand = data.hand_plan ~= nil or p.hand_plan ~= nil,
    build = data.build_plan ~= nil or p.build_plan ~= nil,
    money = data.money_plan ~= nil or p.money_plan ~= nil,
    boss = data.boss_plan ~= nil or p.boss_plan ~= nil,
    focus = data.hand_focus ~= nil or p.hand_focus ~= nil,
  }

  local hand = clean(raw_hand)
  local build = clean(raw_build)
  local money = clean(raw_money)
  local boss = clean(raw_boss)
  local focus, focus_err = clean_hand_focus(raw_focus)
  if focus_err then return nil, focus_err end
  local PlanGate = require("core.plan_gate")
  local state_at_prepare = require("core.state").get_state_name()
  local boss_writable = (state_at_prepare == "BLIND_SELECT"
      and require("core.actions").get_selectable_blind_key() == "Boss")
    or (state_at_prepare ~= "BLIND_SELECT"
      and not not (G and G.GAME and G.GAME.blind and G.GAME.blind.boss))
  local required = required_fields
  if required == nil and not PlanGate.shop_revision_is_complete(hand ~= nil, build ~= nil, money ~= nil) then
    required = PlanGate.shop_required_fields()
  end
  if required then
    local missing = {}
    if required.hand and not hand then missing[#missing + 1] = "hand_plan" end
    if required.build and not build then missing[#missing + 1] = "build_plan" end
    if required.money and not money then missing[#missing + 1] = "money_plan" end
    if required.boss and not boss then missing[#missing + 1] = "boss_plan" end
    if #missing > 0 then
      return require("core.action_result").reject("PRECONDITION_FAILED",
        "Provide the required plan fields with this action: " .. table.concat(missing, ", ") .. ".")
    end
  end

  if not hand and not build and not money and not boss and not focus then
    return require("core.action_result").reject("PRECONDITION_FAILED",
      "Provide hand_plan, build_plan, money_plan, boss_plan, and/or hand_focus.")
  end
  local authored_ante = GameFacts.ante(0)
  local authored_decision = tonumber(G and G.NEURO and G.NEURO.decision_serial) or 0
  return function()
    require("core.plan_transaction").release_fields({
      hand_plan = hand, build_plan = build, money_plan = money, boss_plan = boss,
      hand_focus = focus,
    })
    local ante = GameFacts.ante(0)
    local prev = (G and G.NEURO and G.NEURO.plan) or {}
    local boss_committed = boss_writable and boss or nil
    local hand_scope = scope_snapshot and scope_snapshot.hand or PlanGate.current_blind_scope()
    local build_scope = scope_snapshot and scope_snapshot.build or PlanGate.current_build_scope()
    local money_scope = scope_snapshot and scope_snapshot.money or PlanGate.current_economy_scope()
    local boss_scope = scope_snapshot and scope_snapshot.boss or PlanGate.current_boss_scope()
    local focus_scope = scope_snapshot and (scope_snapshot.focus or scope_snapshot.hand)
      or PlanGate.current_blind_scope()
    if G and G.NEURO then
      local revision = (tonumber(G.NEURO.plan_revision) or 0) + 1
      G.NEURO.plan_revision = revision
      local provenance = {}
      for key, value in pairs(prev.provenance or {}) do provenance[key] = value end
      if written.hand and not written.focus then provenance.focus = nil end
      local function stamp(field, value, scope)
        if written[field] and value ~= nil then
          provenance[field] = { ante = authored_ante, decision_serial = authored_decision,
            revision = revision, scope = scope }
        end
      end
      stamp("hand", hand, hand_scope)
      stamp("build", build, build_scope)
      stamp("money", money, money_scope)
      stamp("boss", boss_committed, boss_scope)
      stamp("focus", focus, focus_scope)
      local committed_focus, committed_focus_scope
      if written.focus then
        committed_focus, committed_focus_scope = focus, focus_scope
      elseif written.hand then
        committed_focus, committed_focus_scope = nil, nil
      else
        committed_focus, committed_focus_scope = prev.hand_focus, prev.hand_focus_scope
      end
      G.NEURO.plan = {
        hand = hand or prev.hand,
        hand_scope = hand and hand_scope or prev.hand_scope,
        build = build or prev.build,
        build_scope = build and build_scope or prev.build_scope,
        money = money or prev.money,
        money_scope = money and money_scope or prev.money_scope,
        boss = boss_committed or prev.boss,
        boss_scope = boss_committed and boss_scope or prev.boss_scope,
        hand_focus = committed_focus,
        hand_focus_scope = committed_focus_scope,
        ante = ante,
        provenance = provenance,
      }
    end
    PlanGate.mark_written(hand ~= nil, build ~= nil, money ~= nil)
    return nil
  end
end

local function handle_record_plan(data)
  return prepare_plan(data)
end

local function handle_record_joker_roles(data)
  return prepare_joker_intents(data)
end

M.prepare_plan = prepare_plan
M.handle_record_plan = handle_record_plan
M.handle_record_joker_roles = handle_record_joker_roles

if _G.NEURO_TEST then
  M.prepare_joker_intents = prepare_joker_intents
end

return M
