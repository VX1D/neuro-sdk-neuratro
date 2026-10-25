require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("force-guidance-contract")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local TD = require("tests.test_deadlock")
local Refs = require("force.force_references")
local Registry = require("core.action_registry")
local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local ContextReadable = require("context.context_readable")
local Gate = require("core.gate")

local function has(text, needle) return (text or ""):find(needle, 1, true) ~= nil end

local CATALOG = {}
for _, name in ipairs(Registry.names()) do CATALOG[name] = true end

local function offered_of(actions)
  local set = {}
  for _, name in ipairs(actions or {}) do set[name] = true end
  return set
end

local function hand_board(hands_left, discards_left)
  LB.load("SELECTING_HAND", "Normal: 5 cards, 4 hands, 3 discards")
  G.FUNCS.get_poker_hand_info = require("tests.engine_hand_info").engine()
  G.GAME.current_round.hands_left = hands_left
  G.GAME.current_round.discards_left = discards_left
end

do
  hand_board(1, 2)
  local p = FP.build("SELECTING_HAND")
  local s = p and p.state or ""
  local to_go = s:match("Score [^,]+, ([^ ]+) to go")
  check("the state prints the chips still to go", to_go ~= nil, s:sub(1, 300))
end

do
  local real_final, real_decline = Gate.final_play_required, Gate.decline_context
  Gate.final_play_required = function() return true end
  Gate.decline_context = function()
    return { indices = { 1 }, hand_type = "High Card" }
  end
  for _, case in ipairs({ { discards = 0, discard = false }, { discards = 2, discard = true } }) do
    hand_board(1, case.discards)
    G.NEURO.persona = "neuro"
    local f = require("force.force_router").get_force_for_state("SELECTING_HAND") or {}
    local offered = offered_of(f.actions)
    local q = f.query or ""
    local label = case.discards .. " discard(s)"
    check(label .. ": discard_hand is offered exactly when discards remain",
      (offered.discard_hand == true) == case.discard, table.concat(f.actions or {}, ","))
    check(label .. ": the query names no action",
      #Refs.named_actions(q, CATALOG) == 0,
      table.concat(Refs.named_actions(q, CATALOG), ","))
  end
  Gate.final_play_required, Gate.decline_context = real_final, real_decline
end

do
  local HH = require("handlers.hand_handlers")
  local real_pending, real_ready = HH.pending, HH.confirm_ready
  HH.pending = function() return { indices = { 1, 2 } } end
  HH.confirm_ready = function() return true end
  hand_board(3, 2)
  local f = require("force.force_selecting_hand").build() or {}
  HH.pending, HH.confirm_ready = real_pending, real_ready
  local offered = offered_of(f.actions)
  check("a confirmation without a rendered verdict offers only resolve_play",
    offered.resolve_play and #(f.actions or {}) == 1, table.concat(f.actions or {}, ","))
  check("and its text names no action",
    #Refs.named_actions(f.query, CATALOG) == 0,
    table.concat(Refs.named_actions(f.query, CATALOG), ","))
end

do
  local scanned, missing, with_ref, without_ref = 0, {}, 0, 0
  for _, sc in ipairs(TD.SCENARIOS) do
    if not sc.xfail then
      for _, key in ipairs({ "GAME", "hand", "jokers", "consumeables", "deck", "playing_cards",
          "shop_jokers", "shop_vouchers", "shop_booster", "shop", "pack_cards", "booster_pack",
          "blind_select_opts", "blind_select", "OVERLAY_MENU", "challenge_tab", "CHALLENGES",
          "STATES", "STATE", "TIMERS", "P_CENTER_POOLS", "P_TAGS", "P_BLINDS", "SETTINGS" }) do
        G[key] = nil
      end
      G.GAME = { current_round = {} }
      G.NEURO = { dispatcher = Dispatcher, actions = Actions, persona = "neuro", reserved_dollars = 0,
        shop_reroll_count = 0, state_enter_serial = scanned * 10 + 10 }
      require("core.validate").reset_run_state()
      local ok = pcall(TD.apply_mock, sc.mock())
      G.STATES = require("tests.engine_cards").states()
      G.STATE = G.STATES[sc.state]
      local ok_b, board = pcall(ContextReadable.build, sc.state, Actions.get_valid_actions_for_state(sc.state))
      local ok_f, f = pcall(require("force.force_router").get_force_for_state, sc.state)
      if ok and ok_f and type(f) == "table" and type(f.query) == "string" then
        scanned = scanned + 1
        local state = (ok_b and tostring(board) or "") .. "\n" .. tostring(f.state_extra or "")
        for _, phrase in ipairs(Refs.missing_sections(f.query, state)) do
          missing[#missing + 1] = sc.state .. " (" .. sc.desc .. "): " .. phrase
        end
        if sc.state == "SELECTING_HAND" then
          if Refs.has_section(f.state_extra, "one_card_away") then
            if has(f.query, "the one-card-away odds above") then with_ref = with_ref + 1 end
          else
            without_ref = without_ref + 1
          end
        end
      end
    end
  end
  check("the sweep built forces", scanned >= 95, tostring(scanned))
  check("no query points at a section its frame does not carry", #missing == 0, table.concat(missing, "; "))
  check("both sides are exercised: a frame with the odds section references it, one without does not",
    with_ref > 0 and without_ref > 0, with_ref .. "/" .. without_ref)
end

do
  LB.load("SHOP", "Normal: affordable joker, affordable booster, $10")
  G.hand = nil
  local p = FP.build("SHOP")
  local s = p and p.state or ""
  check("the owned Hanged Man is blocked in the shop", has(s, "The Hanged Man (Tarot)") and has(s, "Usable now: no"), s)
end

do
  for _, seeded in ipairs({ false, true }) do
    LB.load("RUN_SETUP", "Run setup overlay active")
    SMODS.RunSelect.Setup.choices = { seed = "", enable_seed = seeded }
    G.NEURO.persona = "neuro"
    local f = require("force.force_router").get_force_for_state("RUN_SETUP") or {}
    local q, tools = f.query or "", offered_of(f.tools)
    local label = "seeded " .. (seeded and "ON" or "OFF")
    check(label .. ": toggle_seeded_run and paste_seed are offered as tools (force_router.offer)",
      tools.toggle_seeded_run and tools.paste_seed and offered_of(f.actions).toggle_seeded_run
        and offered_of(f.actions).paste_seed,
      table.concat(f.tools or {}, ","))
    local state = require("tests.helpers").force_frame("RUN_SETUP", f)
    check(label .. ": the frame's state reads " .. (seeded and "ON" or "OFF"),
      has(state, seeded and ", seeded (no seed pasted yet)." or ", not seeded."), state)
    check(label .. ": the query names no action",
      #Refs.named_actions(q, CATALOG) == 0,
      table.concat(Refs.named_actions(q, CATALOG), ","))
  end
end

done()
