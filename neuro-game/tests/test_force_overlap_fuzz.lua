local H = require("tests.hand_pipeline_harness")
local Window = require("core.window")
local play_card = require("tests.helpers").play_card
local Policy = require("core.action_policy")
local check, done = require("tests.helpers").harness("force-overlap-fuzz")

local ACORN = { name = "Amber Acorn", chips = 300, config = { blind = { key = "bl_final_acorn" } } }
local function joker(sid, key, name)
  return { sort_id = sid, ability = { set = "Joker", name = name }, sell_cost = 2,
    config = { center = { key = key, name = name, set = "Joker" } } }
end

local function payload(name)
  if name == "play_hand" or name == "discard_hand" then return { indices = { 1, 1 + math.random(2) } } end
  if name == "set_joker_order" then return { from_index = 1, to_index = 2 } end
  if name == "resolve_play" then return { answer = math.random() < 0.5 and "yes" or "no" } end
  return {}
end

local function audit(sent, seed)
  local bad, registered, active, results = {}, {}, nil, {}
  local function flag(i, what) bad[#bad + 1] = "seed " .. seed .. ": frame " .. i .. " " .. what end
  for i, f in ipairs(H.frames()) do
    local d = f.data or {}
    if f.command == "startup" then
      registered, active = {}, nil
    elseif f.command == "actions/register" then
      for _, a in ipairs(d.actions) do registered[a.name] = true end
    elseif f.command == "actions/unregister" then
      for _, name in ipairs(d.action_names) do
        registered[name] = nil
        if active then active.left[name] = nil end
      end
      if active and next(active.left) == nil then active = nil end
    elseif f.command == "action/result" then
      results[d.id] = (results[d.id] or 0) + 1
      if d.success and active and active.offered[sent[d.id] or ""] then
        flag(i, "answers " .. sent[d.id] .. " while frame " .. active.at .. " is registered")
      end
    elseif f.command == "actions/force" then
      if active then flag(i, "over frame " .. active.at) end
      active = { at = i, offered = {}, left = {} }
      for _, name in ipairs(d.action_names) do
        active.offered[name] = true
        if not Policy.is_tool(name) then active.left[name] = true end
        if not registered[name] then flag(i, "forces " .. name) end
      end
    end
  end
  for id in pairs(sent) do
    if results[id] ~= 1 then bad[#bad + 1] = "seed " .. seed .. ": " .. id .. " has " .. (results[id] or 0) .. " results" end
  end
  return bad
end

local problems, forces = {}, 0
for seed = 1, 40 do
  math.randomseed(seed)
  H.board({ confirm_hand = seed % 2 == 0, blind = seed % 3 ~= 0 and ACORN or nil })
  if seed % 3 ~= 0 then
    G.jokers.cards = { joker(901, "j_joker", "Joker"), joker(902, "j_greedy_joker", "Greedy Joker") }
  end
  local sent, session = {}, 0
  local function send(name, data) sent[H.send(name, data)] = name end
  for _ = 1, 120 do
    G.GAME.current_round.hands_left = math.max(G.GAME.current_round.hands_left, 1)
    while #G.hand.cards < 6 do G.hand.cards[#G.hand.cards + 1] = play_card(#G.hand.cards + 1) end
    G.play.cards = {}
    local r, w = math.random(), Window.current()
    if r < 0.30 and w and w.phase == "forced" then
      local name = w.names[math.random(#w.names)]
      send(name, payload(name))
    elseif r < 0.38 then
      local name = ({ "play_hand", "discard_hand", "set_joker_order", "resolve_play", "nope_action" })[math.random(5)]
      send(name, name == "set_joker_order" and { from_index = 2, to_index = 1 } or { indices = { 2 } })
    elseif r < 0.41 then
      send("play_hand", math.random() < 0.5 and "{bad" or { indices = { 1, 1 } })
    elseif r < 0.55 then
      H.inbox({ command = "speech_finished", data = { isFinal = math.random() < 0.4 } })
    elseif r < 0.60 then
      G.GAME.current_round.discards_left = G.GAME.current_round.discards_left == 0 and 2 or 0
    elseif r < 0.62 then
      G.NEURO.llm_paused = not G.NEURO.llm_paused
    elseif r < 0.63 then
      session = session + 1
      H.inbox({ command = "neuro-bridge/reregister_all", transport_session = "fuzz" .. seed .. "_" .. session })
    end
    H.tick(0.1 + math.random() * 1.5)
  end
  G.NEURO.llm_paused = false
  H.tick(8)
  forces = forces + H.count("actions/force")
  for _, line in ipairs(audit(sent, seed)) do problems[#problems + 1] = line end
end

check("the fuzz exercised many forces", forces >= 200, tostring(forces))
check("no force overlaps an earlier one, every forced name is registered, every success follows its offer's "
  .. "unregister, and every id has one result", #problems == 0,
  table.concat(problems, " | "))
H.finish(check, done)
