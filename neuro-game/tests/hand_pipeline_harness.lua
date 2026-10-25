require("tests.stubs").setup({ love = "timers" })
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 1000 },
  P_CENTERS = require("tests.engine_centers").centers() }

local H = {}
local json = require("util.neuro_json")
local Bridge = require("core.bridge")
local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local Orch = require("core.orchestrator")
local Window = require("core.window")
local Gate = require("core.gate")
local Staging = require("core.staging")
local play_card = require("tests.helpers").play_card
H.Window, H.Gate, H.Staging, H.Dispatcher = Window, Gate, Staging, Dispatcher

local STATES = require("tests.engine_cards").states()
H.STATES = STATES
H.CLOCK = 1000
local dir = require("tests.tmp_workdir").open("hand_pipeline")
H.dir = dir
local cache = { offset = 0, frames = {} }

local function consume_highlighted(to_play)
  local hand = G.hand
  for _, selected in ipairs(hand.highlighted or {}) do
    for i = #hand.cards, 1, -1 do
      if hand.cards[i] == selected then table.remove(hand.cards, i) break end
    end
    if to_play then G.play.cards[#G.play.cards + 1] = selected end
  end
  hand.highlighted = {}
end

H.calls = { play = 0, discard = 0 }
H.errors = {}
function H.board(opts)
  opts = opts or {}
  require("core.config").set("NEURO_CONFIRM_HAND", opts.confirm_hand == false and "off" or "on")
  os.execute("rm -rf '" .. dir .. "' && mkdir -p '" .. dir .. "'")
  cache.offset, cache.frames = 0, {}
  H.calls = { play = 0, discard = 0 }
  require("tests.helpers").orch_board({ clock = H.CLOCK, states = STATES, edit = function(g)
    g.TIMERS.TOTAL = H.CLOCK
    g.GAME.starting_params = opts.starting_params
    g.GAME.current_round = { hands_left = opts.hands or 4, discards_left = opts.discards or 2, reroll_cost = 5,
      discards_used = 0 }
    g.GAME.blind = opts.blind or { name = "Small Blind", chips = 300 }
    g.GAME.hands = { Pair = { level = 1, chips = 10, mult = 2, visible = true },
      ["High Card"] = { level = 1, chips = 5, mult = 1, visible = true },
      Flush = { level = 1, chips = 35, mult = 4, visible = true } }
    g.hand = require("tests.helpers").card_area(g.hand)
    g.play = { cards = {} }
    g.FUNCS = {
      get_poker_hand_info = opts.phi or require("tests.engine_hand_info").stub("Pair"),
      play_cards_from_highlighted = function()
        H.calls.play = H.calls.play + 1
        if H.on_play then return H.on_play() end
        consume_highlighted(false)
        G.GAME.current_round.hands_left = G.GAME.current_round.hands_left - 1
      end,
      discard_cards_from_highlighted = function()
        H.calls.discard = H.calls.discard + 1
        consume_highlighted(false)
        G.GAME.current_round.discards_left = G.GAME.current_round.discards_left - 1
        G.GAME.current_round.discards_used = G.GAME.current_round.discards_used + 1
      end,
    }
  end })
  for i = 1, (opts.ncards or 6) do G.hand.cards[i] = play_card(i) end
  local b = Bridge:new({ game = "Balatro", enabled = true, fs_dir = dir })
  b.persona = "neuro"; b.run_generation = 1; b.transport_session = "hand-pipeline"; b.transport_epoch = 1
  b.dispatcher = Dispatcher; b.actions = Actions; b.decision_serial = 1; b.state_enter_serial = 1
  b.reserved_dollars = 0; b.state = "SELECTING_HAND"; b.once_serials = {}
  G.NEURO = b
  b:set_message_handler(function(msg) Dispatcher.route_message(msg, b) end)
  b:send_startup()
  b._bridge_init_complete = true
  pcall(function() require("core.context_delivery").reset() end)
  require("core.validate").reset_run_state()
  require("core.bridge").tx.reset()
  Dispatcher.reset_run_state()
  Staging.reset_run_state()
  Gate.invalidate()
  H.bridge = b
  H.seen = 0
  H.log = {}
end

function H.tick(seconds, step)
  step = step or 0.1
  for _ = 1, math.max(1, math.floor(seconds / step + 0.5)) do
    H.CLOCK = H.CLOCK + step
    G.TIMERS.REAL = H.CLOCK; G.TIMERS.TOTAL = H.CLOCK
    local ok, err = pcall(Orch.update, step)
    if not ok then H.errors[#H.errors + 1] = tostring(err) end
    H.drain()
  end
end

local function summarize(f)
  local c, d = f.command, f.data or {}
  if c == "actions/register" then
    local n = {} for _, a in ipairs(d.actions or {}) do n[#n + 1] = a.name end
    if #n > 6 then return c .. " [" .. #n .. " actions]" end
    return c .. " " .. table.concat(n, ",")
  elseif c == "actions/unregister" then return c .. " " .. table.concat(d.action_names or {}, ",")
  elseif c == "actions/force" then
    return c .. " " .. table.concat(d.action_names or {}, ",") .. " | q=" .. tostring(d.query or ""):sub(1, 70):gsub("\n", " ")
  elseif c == "action/result" then
    return string.format("%s id=%s success=%s msg=%q", c, tostring(d.id), tostring(d.success),
      tostring(d.message or ""):sub(1, 150))
  elseif c == "context" then
    return c .. " " .. tostring(d.message or ""):sub(1, 150):gsub("\n", " ")
  end
  return tostring(c)
end

local function outbox_frames()
  local f = io.open(dir .. "/neuro_outbox.jsonl", "rb")
  if not f then cache.offset, cache.frames = 0, {} return cache.frames, nil end
  local size = f:seek("end")
  if size < cache.offset then cache.offset, cache.frames = 0, {} end
  f:seek("set", cache.offset)
  local data = f:read("*a") or ""
  f:close()
  local pos = 1
  while true do
    local nl = data:find("\n", pos, true)
    if not nl then break end
    local ok, fr = pcall(json.decode, data:sub(pos, nl - 1))
    if ok and type(fr) == "table" then cache.frames[#cache.frames + 1] = fr end
    pos = nl + 1
  end
  cache.offset = cache.offset + pos - 1
  local tail
  if pos <= #data then
    local ok, fr = pcall(json.decode, data:sub(pos))
    if ok and type(fr) == "table" then tail = fr end
  end
  return cache.frames, tail
end

function H.frames()
  local frames, tail = outbox_frames()
  local out = {}
  for i = 1, #frames do out[i] = frames[i] end
  if tail then out[#out + 1] = tail end
  return out
end

function H.drain()
  local fr = H.frames()
  for i = H.seen + 1, #fr do
    H.log[#H.log + 1] = string.format("t=%.1f  %s", H.CLOCK - 1000, summarize(fr[i]))
    H.log_raw = H.log_raw or {}
    H.log_raw[#H.log_raw + 1] = fr[i]
  end
  H.seen = #fr
end

function H.mark(label)
  H.drain()
  H.log[#H.log + 1] = string.format("t=%.1f  ---- %s", H.CLOCK - 1000, label)
end

function H.inbox(msg)
  local fh = assert(io.open(dir .. "/neuro_inbox.jsonl", "a"))
  fh:write(json.encode(msg), "\n"); fh:close()
end

local n = 0
function H.send(name, payload)
  n = n + 1
  local id = "a" .. n
  H.inbox({ command = "action", data = { id = id, name = name,
    data = type(payload) == "table" and json.encode(payload) or payload } })
  H.mark("IN action " .. name .. " " .. tostring(type(payload) == "table" and json.encode(payload) or payload) .. " id=" .. id)
  return id
end

function H.dump(title)
  H.drain()
  print("=== " .. title)
  for _, l in ipairs(H.log) do if not l:find("context", 1, true) or H.show_ctx then print("  " .. l) end end
  H.log = {}
end

function H.count(command)
  local count = 0
  for _, f in ipairs(H.frames()) do if f.command == command then count = count + 1 end end
  return count
end

function H.results()
  local out = {}
  for _, f in ipairs(H.frames()) do
    if f.command == "action/result" then out[#out + 1] = f.data end
  end
  return out
end

function H.result_for(id)
  for _, r in ipairs(H.results()) do if r.id == id then return r end end
end

function H.phase()
  local w = G.NEURO.force_window
  return type(w) == "table" and w.phase or "none"
end

function H.wait_force(seconds)
  for _ = 1, math.floor((seconds or 30) / 0.1) do
    H.tick(0.1)
    if H.phase() == "forced" then return true end
  end
  return false
end

function H.last_force()
  local data
  for _, f in ipairs(H.frames()) do if f.command == "actions/force" then data = f.data end end
  return data
end

function H.names_of(frame)
  if frame.data.action_names then return frame.data.action_names end
  local out = {}
  for _, a in ipairs(frame.data.actions or {}) do out[#out + 1] = a.name end
  return out
end

function H.results_since(mark, id)
  local out, frames = {}, H.frames()
  for i = mark + 1, #frames do
    if frames[i].command == "action/result" and frames[i].data.id == id then out[#out + 1] = frames[i].data end
  end
  return out
end

function H.finish(check, done)
  check("no orchestrator errors", #H.errors == 0, table.concat(H.errors, " | "))
  require("tests.tmp_workdir").close()
  done()
end

return H
