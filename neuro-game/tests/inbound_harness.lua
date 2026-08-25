local M = {}

local Bridge = require("core.bridge")
local Dispatcher = require("core.dispatcher")
local Enforce = require("core.enforce")
local Actions = require("core.actions")
local Staging = require("core.staging")
local TxCache = require("core.tx_cache")
local json = require("util.neuro_json")

function M.id_slot(id)
  return type(id) .. "\0" .. tostring(id)
end

local play_card = require("tests.helpers").play_card

function M.new(opts)
  opts = opts or {}
  local dir = opts.dir or require("tests.tmp_workdir").open("inbound_harness")
  local clock = opts.clock or { t = 1000 }
  local registered = opts.registered or { "play_hand", "help" }
  local H = { dir = dir, clock = clock, inbox = dir .. "/neuro_inbox.jsonl",
    outbox = dir .. "/neuro_outbox.jsonl" }

  local function env()
    G.STATES = { SELECTING_HAND = 4 }
    G.STATE = 4
    G.STATE_COMPLETE = true
    G.OVERLAY_MENU = nil
    G.CONTROLLER = nil
    G.GAME = { dollars = 10, chips = 0, used_vouchers = {},
      current_round = { hands_left = 4, discards_left = 2 },
      round_resets = { ante = 1, blind_on_deck = "Small",
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" } },
      blind_on_deck = "Small",
      hands = { Pair = { level = 1, chips = 20, mult = 2, visible = true } }, modifiers = {} }
    G.hand = { cards = { play_card(1), play_card(2), play_card(3), play_card(4), play_card(5) },
      highlighted = {}, config = { card_limit = 5, highlighted_limit = 5 } }
    G.jokers = { cards = {}, config = { card_limit = 5 } }
    G.consumeables = { cards = {}, config = { card_limit = 2 } }
    G.deck = { cards = {} }
    G.FUNCS = { get_poker_hand_info = function(cards) return "Pair", {}, { Pair = { cards } }, cards end }
    require("core.transition_guard").reset()
    Enforce.reset_run_state()
    TxCache.reset()
    Dispatcher.reset_tx()
    G.NEURO = H.bridge
    H.bridge.enabled = true
    H.bridge.decision_serial = 1
    H.bridge.run_generation = 7
    H.bridge.dispatcher = Dispatcher
    H.bridge.actions = Actions
    require("tests.helpers").stage_registered(nil, registered)
  end

  function H.fresh()
    os.execute("rm -rf '" .. dir .. "' && mkdir -p '" .. dir .. "'")
    clock.t = 1000
    TxCache.reset()
    H.bridge = Bridge:new({ game = "Balatro", enabled = true, fs_dir = dir })
    H.bridge:set_message_handler(function(msg) Dispatcher.route_message(msg, H.bridge) end)
    env()
  end

  function H.feed(lines)
    local f = assert(io.open(H.inbox, "a"))
    for _, line in ipairs(lines) do f:write(line, "\n") end
    f:close()
  end

  function H.frames(n)
    for _ = 1, n do
      clock.t = clock.t + 0.2
      pcall(Staging.update)
      pcall(Dispatcher.update_receipts, clock.t)
    end
  end

  function H.results()
    local per_slot, total = {}, 0
    local f = io.open(H.outbox, "r")
    if not f then return per_slot, total end
    for line in f:lines() do
      local ok, frame = pcall(json.decode, line)
      if ok and type(frame) == "table" and frame.command == "action/result" then
        total = total + 1
        local slot = M.id_slot(frame.data and frame.data.id)
        per_slot[slot] = (per_slot[slot] or 0) + 1
      end
    end
    f:close()
    return per_slot, total
  end

  function H.action_line(id, name, payload)
    return string.format('{"command":"action","data":{"id":%s,"name":%q,"data":%q}}',
      json.encode(id), name or "play_hand", payload or '{"indices":[1,2]}')
  end

  function H.run(scenario, settle_frames)
    H.fresh()
    local ok, err = pcall(scenario)
    H.frames(settle_frames or 40)
    local by_dispatcher, dispatcher_total = H.results()
    local still_owed = #TxCache.outstanding(0)
    clock.t = clock.t + Bridge.RESULT_DEADLINE_SECS + 1
    pcall(function() H.bridge:update(0) end)
    local _, after_sweep = H.results()
    return {
      ok = ok, err = err,
      counts = by_dispatcher,
      owed = still_owed,
      swept = after_sweep - dispatcher_total,
    }
  end

  function H.cleanup()
    os.execute("rm -rf '" .. dir .. "'")
  end

  return H
end

return M
