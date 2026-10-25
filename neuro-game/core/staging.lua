local Staging = {}
local Utils = require("util.utils")
local CardArea = require("facts.card_area_util")
local GameActions = require("core.game_actions")

local Tuning = require("core.config")

local update_error_log = require("core.log_throttle").new(function() return Utils.gate_now("staging_error_log_cooldown") end)

local function spd()
  return Tuning.get("NEURO_SPEED_MULT")
end

local function tuned(gate_id, key)
  return Utils.gate_seconds(gate_id, key) * spd()
end

local LIFT_FRAC = 0.65
local ENGINE_LIFT_S = 0.4
local HOVER_FLOOR_S = 0.25
local PER_CARD_FLOOR_S = 0.20
local HOLD_FLOOR_S = 0.30

local function on_timeline(gate_id, seconds)
  if Utils.gate_clock(gate_id) == "REAL" then return seconds * Tuning.game_speed() end
  return seconds
end

local function off_timeline(gate_id, seconds)
  if Utils.gate_clock(gate_id) == "REAL" then return seconds / Tuning.game_speed() end
  return seconds
end

local function paced(gate_id, key, floor_wall_s)
  local v = Utils.gate_seconds(gate_id, key) * spd()
  local floor_s = on_timeline("staging_engine_floor", floor_wall_s)
  if v < floor_s then return floor_s end
  return v
end

local function lift_safe_commit(commit_dur, hover_dur)
  local floor_s = on_timeline("staging_engine_floor", ENGINE_LIFT_S) - (1 - LIFT_FRAC) * hover_dur
  if commit_dur < floor_s then return floor_s end
  return commit_dur
end

local staged, executing = nil, nil

function Staging.lift_safe_delay(seconds)
  local entry = executing
  local cards = entry and entry.hover_cards
  if not (cards and #cards > 0) then return seconds end
  return lift_safe_commit(seconds, entry.hover_dur or 0)
end

local SHOP_ATTACK_ACTIONS = { buy_from_shop = true }

local function failsafe_s()
  local f = Utils.gate_seconds("staging_failsafe", "NEURO_STAGING_FAILSAFE")
  return math.max(f, f * spd())
end

local INFO_ACTIONS = { choose_persona = true }


local post_until = 0
local glow_release = nil
local clear_hovers

local function now() return Utils.gate_now("staging_failsafe") end

local function resolve_payload_card(name, payload, cards)
  if not payload.area then return end
  local _, card = CardArea.resolve_target(payload, CardArea.TARGET_RULES[name])
  if card then cards[#cards + 1] = card end
end

local function is_pack_area(area_name)
  if type(area_name) ~= "string" then return false end
  local n = CardArea.AREA_ALIASES[area_name] or area_name
  return n == "booster_pack" or n == "pack_cards"
end

local CARDLESS_POST = { select_blind = 0.4, skip_blind = 0.3, reroll_shop = 0.6, cash_out = 0.3,
  start_run = 0.3, start_challenge_run = 0.3 }

local USE_PROFILE = { hover = "NEURO_HOVER_USE", post = "NEURO_POST_BUY", commit = "NEURO_PACK_PICK_DELAY",
  pack_only = true, juice = { 0.8, 0.5 } }
local PROFILES = {
  play_hand = { play = true, post = "NEURO_POST_PLAY" },
  discard_hand = { play = true, post = "NEURO_POST_DISCARD" },
  buy_from_shop = { hover = "NEURO_HOVER_SHOP", post = "NEURO_POST_BUY", commit = "NEURO_SHOP_BUY_DELAY",
    juice = { 0.8, 0.5 } },
  use_consumable = USE_PROFILE, use_directional_consumable = USE_PROFILE,
  choose_pack_card = USE_PROFILE, choose_directional_pack_card = USE_PROFILE,
  sell_card = { hover = "NEURO_HOVER_DEFAULT", post = "NEURO_POST_SELL", juice = { 0.7, 0.4 } },
}

local function resolve_hover(name, payload)
  local cards = {}
  local hover_dur = paced("staging_hover", "NEURO_HOVER_DEFAULT", HOVER_FLOOR_S)
  local hold_dur = paced("staging_hold", "NEURO_HOLD_ALL_SELECTED", HOLD_FLOOR_S)
  local post_dur = tuned("staging_post", "NEURO_POST_DEFAULT")
  local commit_dur = 0
  local juice_scale = 0.5
  local juice_rot = 0.3

  local is_confirmed_play = name == "resolve_play" and payload.answer == "yes"
  local profile = PROFILES[is_confirmed_play and "play_hand" or name]
  if profile then
    if profile.play then
      local play_indices = payload.indices
      if is_confirmed_play then play_indices = require("handlers.hand_handlers").committing_indices() end
      if play_indices and G and G.hand and G.hand.cards then
        for _, idx in ipairs(play_indices) do
          if G.hand.cards[idx] then
            cards[#cards + 1] = G.hand.cards[idx]
          end
        end
      end
      hover_dur = paced("staging_hover", "NEURO_HOVER_PER_CARD", PER_CARD_FLOOR_S)
    else
      resolve_payload_card(name, payload, cards)
      hover_dur = paced("staging_hover", profile.hover, HOVER_FLOOR_S)
    end
    post_dur = tuned("staging_post", profile.post)
    if profile.commit and (not profile.pack_only or is_pack_area(payload.area)) then
      commit_dur = on_timeline("staging_commit", Utils.gate_seconds("staging_commit", profile.commit) or 0)
    end
    if profile.juice then juice_scale, juice_rot = profile.juice[1], profile.juice[2] end
  elseif CARDLESS_POST[name] then
    hover_dur = 0
    post_dur = CARDLESS_POST[name]
  end

  if #cards > 0 then
    commit_dur = lift_safe_commit(commit_dur, hover_dur)
  end

  local play_like = profile ~= nil and profile.play == true
  return {
    hover_cards = cards, hover_dur = hover_dur, post_dur = post_dur, commit_dur = commit_dur or 0,
    hold_dur = hold_dur or 0, multi = #cards > 1 and play_like, play_like = play_like,
    juice_scale = juice_scale, juice_rot = juice_rot,
  }
end

local function glow_map()
  if not (G and G.NEURO) then return nil end
  G.NEURO.ai_glow = G.NEURO.ai_glow or setmetatable({}, { __mode = "k" })
  return G.NEURO.ai_glow
end

function Staging.glow_now()
  return Utils.gate_now("glow_window")
end

local function set_glow_windows(entry)
  local map = glow_map()
  if not map then return end
  local cards = entry.hover_cards
  if #cards == 0 then return end
  local t0 = Staging.glow_now()
  local hover = off_timeline("glow_window", entry.hover_dur)
  if entry.multi then
    local t1 = t0 + #cards * hover + off_timeline("glow_window", entry.hold_dur)
    for i, c in ipairs(cards) do
      map[c] = { t0 = t0 + (i - 1) * hover, t1 = t1 }
    end
  else
    local t1 = t0 + hover + off_timeline("glow_window", entry.commit_dur or 0)
    local attack = SHOP_ATTACK_ACTIONS[entry.name] or nil
    local span = t1 - t0
    local lift01 = (span > 0) and (LIFT_FRAC * hover / span) or nil
    for _, c in ipairs(cards) do
      map[c] = { t0 = t0, t1 = t1, attack = attack, lift01 = lift01 }
    end
  end
end

local function juice_target_settled(card)
  if card.STATIONARY ~= true then return false end
  return Utils.engine_settled()
end

local function hover_card(card, juice_scale, juice_rot)
  if not card then return end
  if not card.highlighted then
    if not (card.area and GameActions.add_area_highlight(card.area, card)) then
      GameActions.set_highlight(card, true)
    end
  elseif G and G.NEURO and G.NEURO.ai_highlighted then
    G.NEURO.ai_highlighted[card] = true
  end
  if card.juice_up and not card._neuro_juiced and juice_target_settled(card) then
    card:juice_up(juice_scale or 0.25, juice_rot or 0.12)
    card._neuro_juiced = true
  end
end

local function unhover_card(card, keep_glow)
  if not card then return end
  local area = card.area
  if card.highlighted and area and type(area.remove_from_highlighted) == "function" then
    pcall(function() area:remove_from_highlighted(card) end)
  end
  local kept = false
  for _, c in ipairs((area and type(area.highlighted) == "table" and area.highlighted) or {}) do
    if c == card then kept = true; break end
  end
  if not kept then
    GameActions.set_highlight(card, false)
  elseif G and G.NEURO and G.NEURO.ai_highlighted then
    G.NEURO.ai_highlighted[card] = nil
  end
  card._neuro_juiced = nil
  if not keep_glow and G and G.NEURO and G.NEURO.ai_glow then
    G.NEURO.ai_glow[card] = nil
  end
end

clear_hovers = function(cards, keep_glow)
  if not cards then return end
  for _, c in ipairs(cards) do
    pcall(unhover_card, c, keep_glow)
  end
end

local function anticipate(entry)
  if not entry or entry.anticipated or not entry.play_like then return end
  local name = entry.name
  entry.anticipated = true
  local NeuroAnim = Utils.lazy_require("render.neuro-anim")
  if not NeuroAnim then return end
  if name == "discard_hand" then
    if NeuroAnim.pre_discard then pcall(NeuroAnim.pre_discard, entry.hover_cards) end
  elseif NeuroAnim.pre_play then
    pcall(NeuroAnim.pre_play, entry.hover_cards)
  end
end

function Staging.update()
  local ok, err = pcall(function()
    local t = now()
    if glow_release and t >= glow_release.at then
      local map = G and G.NEURO and G.NEURO.ai_glow
      if map then
        for _, c in ipairs(glow_release.cards) do map[c] = nil end
      end
      glow_release = nil
    end
    local entry = staged
    if not entry or entry == executing or entry.phase ~= "HOVER" then return end
    local cards = entry.hover_cards
    local elapsed = t - entry.start
    if #cards == 0 then
      entry.phase = "EXECUTE"
    elseif entry.multi then
      local select_time = #cards * entry.hover_dur
      if elapsed >= select_time + entry.hold_dur then
        entry.phase = "EXECUTE"
      elseif elapsed >= select_time then
        if not entry.locked_in then
          entry.locked_in = true
          anticipate(entry)
        else
          for i = 1, #cards do pcall(hover_card, cards[i], entry.juice_scale, entry.juice_rot) end
        end
      else
        local card_idx = math.min(#cards, math.floor(elapsed / entry.hover_dur) + 1)
        for i = 1, card_idx do pcall(hover_card, cards[i], entry.juice_scale, entry.juice_rot) end
      end
    elseif elapsed >= entry.hover_dur then
      anticipate(entry)
      entry.phase = "EXECUTE"
    elseif elapsed >= entry.hover_dur * LIFT_FRAC then
      pcall(hover_card, cards[1], entry.juice_scale, entry.juice_rot)
    end
  end)
  if not ok then
    update_error_log.print("[neuro-game] staging update error: " .. Utils.safe_tostring(err))
    if staged then staged.phase = "EXECUTE" end
  end
end

function Staging.begin(job)
  if INFO_ACTIONS[job.name] then return false end
  local ok, entry = pcall(resolve_hover, job.name, type(job.data) == "table" and job.data or {})
  if not ok then
    entry = { hover_cards = {}, hover_dur = 0, post_dur = 0, commit_dur = 0, hold_dur = 0,
      multi = false, play_like = false, juice_scale = 0.5, juice_rot = 0.3 }
  end
  entry.job, entry.name = job, job.name
  entry.phase = #entry.hover_cards == 0 and "EXECUTE" or "HOVER"
  entry.start = now()
  staged = entry
  set_glow_windows(staged)
  return true
end

function Staging.ready(job)
  return staged ~= nil and staged.job == job and staged.phase == "EXECUTE"
end

function Staging.stalled(job)
  return staged ~= nil and staged.job == job and now() - staged.start > failsafe_s()
end

function Staging.take(job)
  local entry = staged
  if not (entry and entry.job == job) then return end
  if not entry.play_like then pcall(clear_hovers, entry.hover_cards, (entry.commit_dur or 0) > 0) end
  executing = entry
end

function Staging.finish(job, ok)
  local entry = staged
  if not (entry and entry.job == job) then return end
  local t = now()
  if not entry.play_like and entry ~= executing then pcall(clear_hovers, entry.hover_cards) end
  if entry.play_like and not ok then pcall(clear_hovers, entry.hover_cards) end
  if entry == executing then
    if (entry.commit_dur or 0) > 0 then
      glow_release = { cards = entry.hover_cards, at = entry.start + entry.hover_dur + entry.commit_dur }
    end
    post_until = t + entry.post_dur
  end
  staged, executing = nil, nil
end

function Staging.is_busy()
  return staged ~= nil or now() < post_until
end

function Staging.reset_run_state()
  if staged then pcall(clear_hovers, staged.hover_cards) end
  staged, executing, post_until, glow_release = nil, nil, 0, nil
  update_error_log.reset()
end

local function staged_hover_count() return staged and #staged.hover_cards or 0 end

if rawget(_G, "NEURO_TEST") then
  Staging._test = { staged_hover_count = staged_hover_count }
end

return Staging
