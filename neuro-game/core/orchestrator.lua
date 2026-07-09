local Orchestrator = {}

local Utils = require "util.utils"
local S = require("hud.state")
local Tuning = require "core.tuning"
local ContextCompact = require "context.context_compact"
local CtxHand = require "context.ctx_hand"
local Staging = require "core.staging"
-- core.selftest is loaded lazily below (only when a run is active or requested on boot), not required here
local NeuroState = require "core.state"
local StateKinds = require "core.state_kinds"
local NeuroActions = require "core.actions"
local NeuroDispatcher = require "core.dispatcher"
local DebugStats = require "render.debug_stats"
local HUD = require "render.hud_overlay"
local BridgeInit = require "core.bridge_init"
local ForceHelpers = require "force.force_helpers"
local DeckNames = require "facts.deck_names"
local NeuroAnim = require("render.neuro-anim")
local neuro_now = Utils.now

local bridge_attempted = false
local last_neuro_error = nil
local _game_err_cd = 0
local _game_err_last_msg = nil

local _neuro_autotest = false
do
  local cli = rawget(_G, "arg") or {}
  for _, v in ipairs(cli) do
    if v == "--test" then _neuro_autotest = true break end
  end
end

local neuro_last_force_attempt_at = 0
local neuro_seen_action_at = 0
local _selftest_on_boot = Tuning.bool("NEURO_SELFTEST_ON_BOOT")
-- separate flag: run ONLY the real pack-launch scenario (Cases.build_pack) -- heavy, opens real boosters
local _selftest_pack_on_boot = Tuning.bool("NEURO_SELFTEST_PACK")

local Lifecycle = require("core.neuro_lifecycle")
-- dirty-bump keeps the fingerprint (drop_fingerprint=false)
local function mark_force_dirty() Lifecycle.mark_force_dirty(false) end

-- roster-only sig: re-sends gate on WHO you own + run economy, never on scaling ticks (live numbers ride volatile J rows)
local function stable_content_sig()
  if not (G and G.GAME) then return "-" end
  local p = {}
  local function roster(area)
    if not (area and area.cards) then return end
    for _, j in ipairs(area.cards) do
      p[#p + 1] = ((j.config and j.config.center and j.config.center.key) or "?")
        .. ((j.edition and j.edition.key) or "")
    end
  end
  roster(G.jokers)
  roster(G.playbook_extra)
  if G.GAME.used_vouchers then
    local vk = {}
    for k in pairs(G.GAME.used_vouchers) do vk[#vk + 1] = tostring(k) end
    table.sort(vk); p[#p + 1] = table.concat(vk, ".")
  end
  local center = DeckNames.current_deck_center()
  p[#p + 1] = tostring((center and center.key) or "-")
  local m = G.GAME.modifiers or {}
  p[#p + 1] = tostring(m.money_per_hand or 1) .. "/" .. tostring(m.money_per_discard or 0)
    .. "/" .. (m.no_interest and "NI" or "-") .. "/" .. tostring(G.GAME.interest_amount or 1)
    .. "/" .. tostring(G.GAME.interest_cap or 25)
  return table.concat(p, "|")
end

local LevelDelta = require("util.level_delta")
local function emit_level_delta()
  if not (G and G.GAME and G.GAME.hands and G.NEURO and G.NEURO.send_context) then return end
  local msg, cur = LevelDelta.compute(G.GAME.hands, G.NEURO.hand_level_snapshot)
  G.NEURO.hand_level_snapshot = cur
  if msg then pcall(function() G.NEURO:send_context(msg, true) end) end
end

local TokenLegends = require("facts.token_legends")
local once_until = ForceHelpers.once_until
-- retained context persists, so it need not be re-sent every turn
local function emit_state_glossary(state_name)
  if not (G and G.NEURO and G.NEURO.send_context) then return end
  local cat, text = TokenLegends.for_state(state_name)
  if not (cat and text) then return end
  local ante = (G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante) or 0
  -- shared token core rides its own once-per-ante message so state legends don't repeat it
  if once_until("gloss:common", ante) then
    pcall(function() G.NEURO:send_context("GLOSS| " .. TokenLegends.COMMON, true) end)
  end
  if not once_until("gloss:" .. cat, ante) then return end
  pcall(function() G.NEURO:send_context("GLOSS| " .. text, true) end)
end

-- stable only where jokers/vouchers inform decisions; skipping the rest avoids content flapping (ROUND_EVAL carries no JD)
local STABLE_STATES = { SELECTING_HAND = true, SHOP = true, BLIND_SELECT = true }

local function maybe_emit_stable_context(state_name)
  if not (G and G.NEURO and G.NEURO.send_context) then return end
  if not (STABLE_STATES[state_name] or StateKinds.is_pack_state(state_name)) then return end
  -- level deltas ride their own message; must run before the sig gate
  emit_level_delta()
  local sig = stable_content_sig()
  if not G.NEURO.stable_refresh_due and sig == G.NEURO.stable_sig_cheap then
    return
  end
  local ok, stable = pcall(ContextCompact.build, state_name, nil,
    { split = "stable", full_jokers = true, no_cache = true })
  if not ok or not stable or stable == "" then
    return
  end
  G.NEURO.stable_sig_cheap = sig
  if G.NEURO.stable_refresh_due or stable ~= G.NEURO.stable_ctx_sig then
    G.NEURO.stable_ctx_sig = stable
    G.NEURO.stable_refresh_due = false
    G.NEURO:send_context(stable, true)
    G.NEURO.last_force_fingerprint = nil
  end
end

local function register_valid_actions(state_name)
  local valid = NeuroActions.get_valid_actions_for_state(state_name)
  if not (G and G.NEURO and G.NEURO.register_actions) then return valid end
  local valid_set = Utils.list_to_set(valid)
  local filtered = {}
  for _, def in ipairs(NeuroActions.get_static_actions()) do
    if valid_set[def.name] then filtered[#filtered + 1] = def end
  end
  if #filtered > 0 then G.NEURO:register_actions(filtered) end
  return valid
end

local function neuro_can_act()
  if not (G and G.NEURO) then return false end
  local now = neuro_now()
  if (now - S.state_changed_at) < Tuning.get("NEURO_STATE_COOLDOWN") then
    return false
  end
  local state_name = G.NEURO.state or ""
  local entry_cd = Tuning.get("NEURO_ENTRY_CD_" .. tostring(state_name))
  if entry_cd and (now - S.state_changed_at) < entry_cd then
    return false
  end
  if G.NEURO.last_action_at and (now - G.NEURO.last_action_at) < Tuning.get("NEURO_ACTION_COOLDOWN") then
    return false
  end
  return true
end

local clear_force_state = require("force.force_helpers").clear_force_state
local force_is_stale = require("force.force_helpers").force_is_stale
local snapshot_once_serials = require("force.force_helpers").snapshot_once_serials
local restore_once_serials = require("force.force_helpers").restore_once_serials

local function build_force_fingerprint(state_name, force, context_payload)
  local actions = (force and force.actions) or {}
  local action_part = table.concat(actions, ",")
  local query_part = (force and force.query) or ""
  local decision_part = tostring(context_payload or "")
  if ContextCompact and ContextCompact.decision_fingerprint then
    local ok_fp, fp = pcall(ContextCompact.decision_fingerprint, state_name, context_payload)
    if ok_fp and fp and fp ~= "" then
      decision_part = fp
    end
  end
  return table.concat({
    tostring(state_name or ""),
    query_part,
    action_part,
    decision_part,
  }, "\n")
end

local build_action_set = Utils.list_to_set

local _init_deps = {
  mark_force_dirty = mark_force_dirty,
  register_valid_actions = register_valid_actions,
}

function Orchestrator.init()
  -- Motion.reduced is a plain field read on hot render paths, so seed it from Tuning here, not a function call
  if NeuroAnim and NeuroAnim.Motion then
    NeuroAnim.Motion.reduced = Tuning.bool("NEURO_REDUCED_MOTION")
  end
  local ok, err = pcall(BridgeInit.run, _init_deps)
  if not ok then
    print("[neuro-game] LOAD ERROR (neuro setup): " .. tostring(err))
  end
  bridge_attempted = true
end

function Orchestrator.update(dt, original_love_update)
  if G then
    local area_keys = {"hand", "jokers", "consumeables", "shop_jokers", "shop_vouchers", "shop_booster", "pack_cards", "booster_pack"}
    for i = 1, #area_keys do
      local area = G[area_keys[i]]
      if area and area.cards == nil then
        area.cards = {}
      end
    end
  end

  if _neuro_autotest then
    _neuro_autotest = false
    local tok, result = pcall(function() return require("tests.test_deadlock").run() end)
    if not tok then
      print("[test] Error: " .. tostring(result))
      love.event.quit(1)
    else
      love.event.quit((result or 0) > 0 and 1 or 0)
    end
    return
  end

  local update_success, update_err = pcall(function()
    if original_love_update then
      original_love_update(dt)
    end
  end)

  if not update_success then
    local now = os.clock()
    local msg = tostring(update_err)
    if now > _game_err_cd or msg ~= _game_err_last_msg then
      print("[neuro-game] Warning: Game update error: " .. msg)
      _game_err_last_msg = msg
      _game_err_cd = now + 5
    end
  else
    if _game_err_cd > 0 and os.clock() > _game_err_cd then
      _game_err_cd = 0
      _game_err_last_msg = nil
    end
  end

  if not S.neuro_card_draw_hooked then
    local hok, herr = pcall(HUD.hook_card_draw)
    if not hok then
      print("[neuro-game] UPDATE ERROR (hook_card_draw): " .. tostring(herr))
      S.neuro_card_draw_hooked = true
    end
  end

  if not bridge_attempted and G then
    local bok, berr = pcall(BridgeInit.run, _init_deps)
    if not bok then
      print("[neuro-game] UPDATE ERROR (bridge setup): " .. tostring(berr))
    end
    bridge_attempted = true
  end

  if G and G.NEURO and G.NEURO.enabled and NeuroState then
    local neuro_success, neuro_err = pcall(function()
      G.NEURO:update(dt)
      Staging.update(dt)
      if _selftest_on_boot or _selftest_pack_on_boot or (G.NEURO and G.NEURO.selftest_active) then
        local SelfTest = require("core.selftest")
        if SelfTest.running() then
          SelfTest.tick(dt)
        elseif (_selftest_on_boot or _selftest_pack_on_boot) and SelfTest.available() then
          local pack_only = _selftest_pack_on_boot
          _selftest_on_boot = false
          _selftest_pack_on_boot = false
          local opts
          if pack_only then
            local ok_c, Cases = pcall(require, "core.selftest_cases")
            if ok_c and Cases.build_pack then opts = { cases = Cases.build_pack(), reset = Cases.reset } end
          end
          local st_ok, st_err = SelfTest.start(opts)
          if not st_ok then print("[neuro-game] selftest on boot failed: " .. tostring(st_err)) end
        end
      end
      if G.NEURO.input_buffer and G.NEURO.input_buffer ~= ""
        and not (G.CONTROLLER and G.CONTROLLER.text_input_hook) then
        G.NEURO.input_buffer = ""
      end

      if G.FUNCS and NeuroState.get_state_name then
        local state_name = NeuroState.get_state_name()
        local state_changed = state_name ~= G.NEURO.state
        local prev_state = G.NEURO.state
        if state_changed then
          Staging.on_state_change()
          -- drop active showcase/spotlight on state change so it cannot bleed into next state (leak/race)
          S.joker_showcase = nil
          S.joker_showcase_q = {}
          S.pack_gained_q = {}
          if G.NEURO then G.NEURO.purchase_showcase_queue = {} end
          S.buy_showcase = nil
          S.pack_card_indices = {}
          if NeuroAnim and NeuroAnim.on_state_enter then
            pcall(NeuroAnim.on_state_enter, state_name)
          end
          if state_name == "BLIND_SELECT" then
            CtxHand.clear_last_play()
          end
          G.NEURO.reforce_count = 0
          G.NEURO.state_enter_serial = (G.NEURO.state_enter_serial or 0) + 1
          S.state_changed_at = neuro_now()
          if state_name == "SHOP" and prev_state ~= "SHOP" then
            G.NEURO.shop_reroll_count = 0
            G.NEURO.reserved_dollars = 0
          elseif prev_state == "SHOP" and state_name ~= "SHOP" then
            G.NEURO.shop_reroll_count = nil
            G.NEURO.reserved_dollars = 0
          end
          Lifecycle.clear_failure()
          G.NEURO.state = state_name
          G.NEURO.last_force_fingerprint = nil
          if state_name == "SELECTING_HAND" and (prev_state == "SPLASH" or prev_state == "MENU" or prev_state == "RUN_SETUP") then
            ContextCompact.invalidate_cache()
            G.NEURO.rules_sent = nil
            G.NEURO.seed_pasted = nil
            G.NEURO.stable_refresh_due = true
            CtxHand.clear_last_play()
          end
          if state_name == "SELECTING_HAND" and prev_state == "BLIND_SELECT" then
            ContextCompact.invalidate_cache()
            G.NEURO.stable_refresh_due = true
          end
          local valid_action_names = register_valid_actions(state_name)
          if Tuning.bool("NEURO_CTX_SPLIT") then
            -- sending volatile here would clobber stable on a last-wins client
            maybe_emit_stable_context(state_name)
          else
            G.NEURO:send_context(ContextCompact.build(state_name, valid_action_names), true)
          end
          mark_force_dirty()
        end

        local now = neuro_now()
        HUD.update_joker_showcase(now)

        if NeuroAnim and NeuroAnim.on_pack_open
          and StateKinds.is_pack_state(state_name) then
          pcall(NeuroAnim.on_pack_open)
        end

        if G.NEURO.persona == "hiyori" and not G.NEURO.login_anim and not S.auto_login_fired then
          if state_name == "MENU" then
            if not S.menu_enter_t then S.menu_enter_t = now end
            if now - S.menu_enter_t >= 5.0 then
              S.auto_login_fired = true
              S.menu_enter_t = nil
              local picks = {"neuro", "evil"}
              local pick = picks[math.random(#picks)]
              local display_name = pick == "evil" and "Evil Neuro" or "Neuro-sama"
              G.NEURO.persona = pick
              if type(NeuroAnim) == "table" and type(NeuroAnim.draw_login_anim) == "function" then
                G.NEURO.login_anim = { start = now, name = display_name, palette_ready = false }
              end
            end
          elseif state_name ~= "SPLASH" then
            S.menu_enter_t = nil
          end
        elseif G.NEURO.persona ~= "hiyori" then
          S.auto_login_fired = false
        end

        if G.NEURO.force_inflight and G.NEURO.force_state
          and state_name and state_name ~= "" and state_name ~= "UNKNOWN"
          and G.NEURO.force_state ~= state_name then
          G.NEURO.force_last_result = "superseded"
          clear_force_state()
          mark_force_dirty()
        end
        if state_name and state_name ~= "" and state_name ~= "MENU"
          and state_name ~= "SPLASH" and state_name ~= "UNKNOWN"
          and not G.NEURO.llm_paused then
          -- do not include neuro_last_force_attempt_at here: it self-bumps and defeats the stall watchdog
          local last_activity = math.max(
            G.NEURO.force_sent_at or 0,
            G.NEURO.last_action_at or 0,
            S.state_changed_at or 0)
          if (now - last_activity) > Tuning.force_stall_seconds() then
            if G.NEURO.force_inflight then
              G.NEURO.force_last_result = "stall"
              clear_force_state()
            end
            G.NEURO.last_force_fingerprint = nil
            mark_force_dirty()
          end
        end

        -- MENU/SPLASH are excluded from the watchdog above; clear a stuck force_inflight here or re-forcing hangs until a state change
        if G.NEURO.force_inflight and (state_name == "MENU" or state_name == "SPLASH")
            and not G.NEURO.llm_paused then
          if (now - (G.NEURO.force_sent_at or 0)) > Tuning.force_stall_seconds() then
            G.NEURO.force_last_result = "stall"
            clear_force_state()
            mark_force_dirty()
          end
        end

        local _overlay_block = G.OVERLAY_MENU and NeuroActions.is_action_valid("exit_overlay_menu")
        if _overlay_block and not G.NEURO.force_inflight and not G.NEURO.force_dirty then
          mark_force_dirty()
        end
        local _act_at = G.NEURO.last_action_at or 0
        if _act_at ~= neuro_seen_action_at and not G.NEURO.force_inflight then
          neuro_seen_action_at = _act_at
          mark_force_dirty()
        end
        local _login_block = false
        if G.NEURO.login_anim and G.NEURO.login_anim.start then
          _login_block = (now - G.NEURO.login_anim.start) < 6.0
        end
        if G.NEURO.force_dirty and G.NEURO.persona and not G.NEURO.llm_paused
          and not _login_block then
          if not G.NEURO.force_inflight and (_overlay_block or (not Staging.is_busy() and neuro_can_act())) then
            local dirty_at = G.NEURO.force_dirty_at or S.state_changed_at or 0
            if neuro_last_force_attempt_at > dirty_at then
              dirty_at = neuro_last_force_attempt_at
            end
            local _bp3 = require("facts.card_util").pack_area()
            local pack_not_ready = StateKinds.is_pack_state(state_name)
              and not (_bp3 and _bp3.cards and #_bp3.cards > 0)
            if (now - dirty_at) >= Tuning.get("NEURO_FORCE_DEBOUNCE") and not pack_not_ready then
              register_valid_actions(state_name)
              -- refund once-per-entry hints if the built force is dropped below (else they burn unsent)
              local hint_snapshot = snapshot_once_serials()
              local force = NeuroDispatcher.get_force_for_state(state_name)
              if not force then
                -- force-less state: bump attempt time so debounce re-gates (no per-frame spin)
                neuro_last_force_attempt_at = now
              end
              if force then
                local wants_full_jokers = false
                if G.NEURO.last_action_name == "joker_info" then
                  local last_at = G.NEURO.last_action_at or 0
                  wants_full_jokers = (now - last_at) <= 2.5
                end

              if Tuning.bool("NEURO_CTX_SPLIT") then
                if wants_full_jokers then G.NEURO.stable_refresh_due = true end
                maybe_emit_stable_context(state_name)
              end
              local force_context = ContextCompact.build(state_name, force.actions, {
                full_jokers = wants_full_jokers,
                force_phase = true,
                split = Tuning.bool("NEURO_CTX_SPLIT") and "volatile" or nil,
              })
              local force_fingerprint = build_force_fingerprint(state_name, force, force_context)
              if force_is_stale(state_name, force) then
                restore_once_serials(hint_snapshot)
                mark_force_dirty()
                neuro_last_force_attempt_at = now
              elseif force_fingerprint ~= G.NEURO.last_force_fingerprint then
                emit_state_glossary(state_name)
                G.NEURO.force_last_result = "pending"
                G.NEURO.force_state = state_name
                G.NEURO.force_inflight = true
                G.NEURO.force_sent_at = now
                G.NEURO.force_action_names = force.actions
                G.NEURO.force_action_set = build_action_set(force.actions)
                G.NEURO.last_force_fingerprint = force_fingerprint
                neuro_last_force_attempt_at = now
                G.NEURO:force_actions(
                  force_context,
                  force.query,
                  force.actions,
                  { priority = "medium", ephemeral_context = true }
                )
                G.NEURO.force_dirty = false
              else
                restore_once_serials(hint_snapshot)
                neuro_last_force_attempt_at = now
              end
              end
            end
          end
        end
      end
    end)

    if not neuro_success then
      local err_str = tostring(neuro_err)
      if err_str ~= last_neuro_error then
        print("[neuro-game] Warning: Neuro update error: " .. err_str)
        last_neuro_error = err_str
      end
    else
      last_neuro_error = nil
    end
  end

  DebugStats.sample(dt)
end

return Orchestrator
