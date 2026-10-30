local M = {}

local CardArea = require("facts.card_area_util")
local Utils = require("util.utils")
local GameFacts = require("facts.game_facts")
local PlanLimits = require("core.plan_limits")
local SchemaValidate = require("util.schema_validate")
local ActionResult = require("core.action_result")
local Lifecycle = require("core.neuro_lifecycle")

local validate_value = SchemaValidate.validate_value

local function clean(s, max_length, label)
  if type(s) ~= "string" then return nil end
  s = Utils.normalize_ws(s)
  if #s == 0 then return nil end
  if max_length then
    local ok, err = validate_value({ type = "string", maxLength = max_length }, s, label or "value")
    if not ok then return nil, err end
  end
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
  local primary, primary_err = visible_hand_name(raw.primary, "hand_focus.primary")
  if not primary then return nil, primary_err end
  local fallback, fallback_err
  if raw.fallback ~= nil then
    fallback, fallback_err = visible_hand_name(raw.fallback, "hand_focus.fallback")
    if not fallback then return nil, fallback_err end
  end
  return { primary = primary, fallback = fallback }
end

-- Multiple writes may share a decision serial, so commits need their ordinal within that decision.
local function write_ordinal(decision)
  local n = G.NEURO
  local run = tonumber(n.run_generation) or 0
  local log = n.plan_writes
  if type(log) ~= "table" or log.run ~= run then
    log = { run = run, counts = {} }
    n.plan_writes = log
  end
  log.counts[decision] = (log.counts[decision] or 0) + 1
  return log.counts[decision]
end

local function prepare_joker_intents(data)
  if not (G and G.jokers and G.jokers.cards) then
    return nil, ActionResult.wait("Your jokers are not loaded yet, so nothing was tagged.",
      "Wait until a run is in progress, then record the roles again.")
  end
  local njok = #G.jokers.cards
  if njok < 1 then return nil, "You have no jokers to tag." end
  local seen, resolved = {}, {}
  for _, entry in ipairs(data.intents) do
    local idx, tag = entry.index, entry.tag
    local ok_idx, err_idx = CardArea.validate_index(idx, njok, "index", "jokers")
    if not ok_idx then return nil, err_idx end
    if seen[idx] then return nil, "Duplicate index " .. tostring(idx) .. " in one call." end
    seen[idx] = true
    local note, note_err = clean(entry.note, PlanLimits.JOKER_NOTE_MAX, "note")
    if note_err then return nil, note_err end
    local clear_note = type(entry.note) == "string" and note == nil
    resolved[#resolved + 1] = { card = G.jokers.cards[idx], idx = idx, tag = tag, note = note,
      clear_note = clear_note }
  end
  local authored_ante = GameFacts.ante(0)
  local authored_decision = tonumber(G.NEURO and G.NEURO.decision_serial) or 0
  return function()
    local cards = G.jokers and G.jokers.cards
    if type(cards) ~= "table" then
      return nil, "Joker lineup changed before tagging ran; nothing was changed. Inspect the current order and choose again."
    end
    for _, r in ipairs(resolved) do
      if cards[r.idx] ~= r.card then
        return nil, "Joker lineup changed before tagging ran; nothing was changed. Inspect the current order and choose again."
      end
    end
    Lifecycle.observe_joker_roster()
    G.NEURO.joker_intents = G.NEURO.joker_intents or {}
    local provenance = {
      ante = authored_ante,
      decision_serial = authored_decision,
      write = write_ordinal(authored_decision),
    }
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
    end
    Lifecycle.sync_joker_intent_revision()
    provenance.revision = G.NEURO.joker_intent_revision
    return ActionResult.done()
  end
end

function M.boss_plan_writable()
  return require("core.gate").current_boss_scope() ~= nil
end

local PLAN_FIELDS = {
  { key = "hand", field = "hand_plan", scope = "current_blind_scope" },
  { key = "build", field = "build_plan", scope = "current_build_scope" },
  { key = "money", field = "money_plan", scope = "current_economy_scope" },
  { key = "boss", field = "boss_plan", scope = "current_boss_scope" },
}

local function prepare_plan(data, required_fields, scope_snapshot, explicitly_written)
  local p = (type(data.plan) == "table") and data.plan or {}
  local raw_focus = data.hand_focus ~= nil and data.hand_focus or p.hand_focus
  local text, text_err = {}, nil
  for _, f in ipairs(PLAN_FIELDS) do
    local raw = data[f.field] ~= nil and data[f.field] or p[f.field]
    local value, err = clean(raw, PlanLimits.PLAN_TEXT_MAX, f.field)
    text[f.key], text_err = value, text_err or err
  end
  local hand, build, money, boss = text.hand, text.build, text.money, text.boss
  if text_err then return ActionResult.reject("SCHEMA_INVALID", text_err) end
  local focus, focus_err = clean_hand_focus(raw_focus)
  if focus_err then return nil, focus_err end
  local written = explicitly_written or {
    hand = hand ~= nil, build = build ~= nil, money = money ~= nil, boss = boss ~= nil, focus = focus ~= nil,
  }
  local Gate = require("core.gate")
  local boss_writable = M.boss_plan_writable()
  local required, missing = required_fields or {}, {}
  for _, f in ipairs(PLAN_FIELDS) do
    if required[f.key] and not text[f.key] then missing[#missing + 1] = f.field end
  end
  if #missing > 0 then
    return ActionResult.reject("PRECONDITION_FAILED",
      "Provide the required plan fields with this action: " .. table.concat(missing, ", ") .. ".")
  end

  if not hand and not build and not money and not boss and not focus then
    return ActionResult.reject("PRECONDITION_FAILED",
      "Provide hand_plan, build_plan, money_plan, and/or hand_focus.")
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
    local committed = { hand = hand, build = build, money = money, boss = boss_writable and boss or nil }
    local scopes = {}
    for _, f in ipairs(PLAN_FIELDS) do
      scopes[f.key] = scope_snapshot and scope_snapshot[f.key] or Gate[f.scope]()
    end
    local focus_scope = scope_snapshot and (scope_snapshot.focus or scope_snapshot.hand)
      or Gate.current_blind_scope()
    if G and G.NEURO then
      local revision = (tonumber(G.NEURO.plan_revision) or 0) + 1
      G.NEURO.plan_revision = revision
      local provenance = {}
      for key, value in pairs(prev.provenance or {}) do provenance[key] = value end
      local write
      if written.hand and not written.focus then provenance.focus = nil end
      local function stamp(field, value, scope)
        if written[field] and value ~= nil then
          write = write or write_ordinal(authored_decision)
          provenance[field] = { ante = authored_ante, decision_serial = authored_decision,
            write = write, revision = revision, scope = scope }
        end
      end
      for _, f in ipairs(PLAN_FIELDS) do stamp(f.key, committed[f.key], scopes[f.key]) end
      stamp("focus", focus, focus_scope)
      local committed_focus, committed_focus_scope
      if written.focus then
        committed_focus, committed_focus_scope = focus, focus_scope
      elseif written.hand then
        committed_focus, committed_focus_scope = nil, nil
      else
        committed_focus, committed_focus_scope = prev.hand_focus, prev.hand_focus_scope
      end
      local plan = { hand_focus = committed_focus, hand_focus_scope = committed_focus_scope, ante = ante,
        provenance = provenance }
      for _, f in ipairs(PLAN_FIELDS) do
        local value, scope_key = committed[f.key], f.key .. "_scope"
        plan[f.key] = value or prev[f.key]
        plan[scope_key] = value and scopes[f.key] or prev[scope_key]
      end
      G.NEURO.plan = plan
    end
    Gate.mark_written(hand ~= nil, build ~= nil, money ~= nil)
    return nil
  end
end
M.prepare_plan = prepare_plan
local RECORD_PLAN_BOSS = "Not saved: boss_plan is not a field of a plan record; "
  .. "put a boss rule in plan.boss_plan when you select the blind, play or discard."

function M.record_plan_note(data)
  local nested = type(data) == "table" and type(data.plan) == "table" and data.plan or {}
  if type(data) == "table" and (data.boss_plan ~= nil or nested.boss_plan ~= nil) then return RECORD_PLAN_BOSS end
  return nil
end

M.ACCEPTED_UNDECLARED = { record_plan = { plan = true, boss_plan = true } }

M.handle_record_plan = function(data)
  data.boss_plan = nil
  if type(data.plan) == "table" then data.plan.boss_plan = nil end
  local state_name = require("core.state").get_state_name()
  local commit, err = prepare_plan(data, require("core.plan_requirements").required(state_name, "record_plan"))
  return commit, err
end
M.prepare_joker_intents = prepare_joker_intents
M.handle_record_joker_roles = prepare_joker_intents

return M
