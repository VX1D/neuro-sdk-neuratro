local M = {}
local Utils = require("util.utils")


function M.neuro_table(key, fresh)
  local g = rawget(_G, "G")
  local n = g and g.NEURO
  if type(n) ~= "table" then return nil end
  if type(n[key]) ~= "table" then n[key] = fresh and fresh() or {} end
  return n[key]
end

function M.record_failure(name, reason)
  if not Utils.neuro_ready() then return end
  G.NEURO.last_failed_action = name
  G.NEURO.last_failed_reason = reason
end

function M.clear_failure()
  if not Utils.neuro_ready() then return end
  G.NEURO.last_failed_action = nil
  G.NEURO.last_failed_reason = nil
end

function M.clear_pending_confirm()
  if not Utils.neuro_ready() then return end
  local Gate = require("core.gate")
  Gate.invalidate()
  Gate.forget("handler")
  G.NEURO.weak_fired_serial = nil
end

function M.reconnect_context_delivery()
  if not Utils.neuro_ready() then return end
  require("core.context_delivery").reconnect_transport()
end

function M.reset_context_delivery()
  if not Utils.neuro_ready() then return end
  require("core.context_delivery").reset_transport()
  local N = G.NEURO
  N.once_serials = {}
  N.session_once_serials = {}
end

function M.bump_run_generation(reason)
  local current = Utils.neuro_ready() and tonumber(G.NEURO.run_generation) or nil
  require("core.gate").invalidate()
  require("core.execute").abort(reason or "run generation changed")
  require("core.window").reset()
  M.clear_pending_confirm()
  require("core.validate").reset_streaks()
  if current == nil then return nil end
  G.NEURO.run_generation = current + 1
  return G.NEURO.run_generation
end
local identity_value = Utils.identity_value

local function joker_intent_state_identity()
  local cards = G and G.jokers and G.jokers.cards
  if type(cards) ~= "table" then return nil end
  local intents = G.NEURO.joker_intents or {}
  local parts = {}
  for i, card in ipairs(cards) do
    local sid = card and card.sort_id
    local intent = sid ~= nil and intents[sid] or nil
    parts[#parts + 1] = identity_value(i) .. ":" .. identity_value(sid) .. ":"
      .. identity_value(card) .. ":" .. identity_value(intent and intent.tag) .. ":"
      .. identity_value(intent and intent.note)
  end
  return table.concat(parts, "|")
end

local function bump_joker_intent_revision()
  G.NEURO.joker_intent_revision = (tonumber(G.NEURO.joker_intent_revision) or 0) + 1
  return G.NEURO.joker_intent_revision
end

function M.sync_joker_intent_revision()
  if not Utils.neuro_ready() then return nil, false end
  local N = G.NEURO
  local current = joker_intent_state_identity()
  if current == nil then return tonumber(N.joker_intent_revision) or 0, false end
  local previous = N.joker_intent_state_identity
  N.joker_intent_state_identity = current
  if previous == nil or previous == current then
    return tonumber(N.joker_intent_revision) or 0, false
  end
  return bump_joker_intent_revision(), true
end

function M.observe_joker_roster()
  if not Utils.neuro_ready() then return nil end
  local current = joker_intent_state_identity()
  if current ~= nil then G.NEURO.joker_intent_state_identity = current end
  return current
end


function M.reset_hud_state()
  local S = require("hud.state")
  local HUD_STATE_KEEP = S.PERSISTENT_KEYS
  if S.release_text_caches then S.release_text_caches() end
  local fresh = S.new_state()
  for k in pairs(S) do
    if not HUD_STATE_KEEP[k] and fresh[k] == nil then S[k] = nil end
  end
  for k, v in pairs(fresh) do
    if HUD_STATE_KEEP[k] then
      if S[k] == nil then S[k] = v end
    else
      S[k] = v
    end
  end
  require("hud.emotes").forget_failures()
end

local RUN_FIELDS = {
  "force_window", "force_liveness",
  "recent_actions", "once_serials", "decision_snapshot", "gameplay_journal",
  "gates", "play_proposal", "play_decision", "play_proposal_serial",
  "last_failed_action", "last_failed_reason",
  "last_action_at", "last_action_name", "last_play",
  "shop_pack_interrupt", "reserved_dollars", "purchase_showcase_queue", "held_plan_write",
  "joker_intent_state_identity", "reward_joker_roster",
  "plan", "plan_revision", "joker_intent_revision", "econ_plan_ok", "shop_plan_revision_required",
  "economy_epoch", "shop_visit_epoch", "shop_entry_dollars", "shop_entry_pending",
  "selected_back_key", "selected_stake", "pack_exit_pending", "weak_fired_serial", "jokers_sold", "jokers_sold_run", "joker_intents", "joker_observations", "joker_hits", "joker_bought_cost", "last_reward_outcome_key", "rare_joker_announced", "blind_reward_cache", "blind_reward_round",
  "state", "state_enter_serial", "decision_serial",
  "_prev_ante", "_reservation_epoch",
  "seed_pasted", "login_anim",
  "deck_chosen", "ai_highlighted", "ai_glow",
}
local function reset_module(path) return function() require(path).reset_run_state() end end
local RUN_RESETS = {
  { "staging", reset_module("core.staging") },
  { "joker_hits", reset_module("core.joker_hits") },
  { "dispatcher", reset_module("core.dispatcher") },
  { "window", function() require("core.window").reset() end },
  { "validate", reset_module("core.validate") },
  { "crash_guards", reset_module("core.crash_guards") },
  { "orchestrator", reset_module("core.orchestrator") },
  { "showcase", reset_module("hud.showcase") },
  { "hud_state", function()
    M.reset_hud_state()
    local HudShared = require("render.hud_shared")
    if HudShared.carousel_reset then HudShared.carousel_reset() end
  end },
}

local function reset_run_scope(owner)
  owner = owner or {}
  for _, key in ipairs(RUN_FIELDS) do owner[key] = nil end
  local errors = {}
  for _, entry in ipairs(RUN_RESETS) do
    local ok, err = pcall(entry[2], {})
    if not ok then errors[#errors + 1] = entry[1] .. ": " .. Utils.safe_tostring(err) end
  end
  if #errors > 0 then
    print("[neuro-game] lifecycle reset hook errors (run): " .. table.concat(errors, "; "))
  end
  return owner, errors
end
M.registry = { reset = function(_, owner) return reset_run_scope(owner) end }

function M.withdraw_open_force()
  if not Utils.neuro_ready() then return end
  require("core.window").withdraw("run_reset")
end

function M.reset_run_state(generation_already_bumped)
  if not Utils.neuro_ready() then return nil end
  local N = G.NEURO
  M.withdraw_open_force()
  if not generation_already_bumped then
    N.run_generation = (tonumber(N.run_generation) or 0) + 1
  end
  reset_run_scope(N)
  N.decision_serial    = 0
  N.state_enter_serial = 0
  N._prev_ante         = 0
  N.economy_epoch      = 0
  N.shop_visit_epoch   = 0
  N.render_dirty_epoch = 0
  N.plan_revision      = 0
  N.joker_intent_revision = 0
  N._reservation_epoch = N.run_generation
  N.ai_highlighted = setmetatable({}, { __mode = "k" })
  N.ai_glow = setmetatable({}, { __mode = "k" })
  return N.run_generation
end

return M
