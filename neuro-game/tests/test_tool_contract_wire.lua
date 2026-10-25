local H = require("tests.hand_pipeline_harness")
local Policy = require("core.action_policy")
local Window = require("core.window")
local check, done = require("tests.helpers").harness("tool-contract-wire")

local ACORN = { name = "Amber Acorn", chips = 300, config = { blind = { key = "bl_final_acorn" } } }

local function jokers()
  local function joker(sid, key, name)
    return { sort_id = sid, ability = { set = "Joker", name = name }, sell_cost = 2,
      config = { center = { key = key, name = name, set = "Joker" } } }
  end
  G.jokers.cards = { joker(801, "j_joker", "Joker"), joker(802, "j_greedy_joker", "Greedy Joker") }
end

local function since(mark)
  local out, frames = {}, H.frames()
  for i = mark + 1, #frames do out[#out + 1] = frames[i] end
  return out
end

local function listed(frames, command)
  local out = {}
  for _, f in ipairs(frames) do
    if f.command == command then
      local names = f.data.action_names or {}
      for _, a in ipairs(f.data.actions or {}) do names[#names + 1] = a.name end
      for _, name in ipairs(names) do out[#out + 1] = name end
    end
  end
  table.sort(out)
  return out
end

local function unregistered(frames) return listed(frames, "actions/unregister") end

local function forces_in(frames)
  local n = 0
  for _, f in ipairs(frames) do if f.command == "actions/force" then n = n + 1 end end
  return n
end

local function tools_in(list)
  local out = {}
  for _, name in ipairs(list) do if Policy.is_tool(name) then out[#out + 1] = name end end
  return out
end

local function decisions_of(w)
  local out = {}
  for _, name in ipairs(w.names) do if not Policy.is_tool(name) then out[#out + 1] = name end end
  table.sort(out)
  return out
end

H.board({ blind = ACORN })
jokers()
check("fixture: the hand screen is forced", H.wait_force(), H.phase())
local w = Window.current()
check("the force offers the tool beside its decisions (force_router.offer)",
  w.set.set_joker_order == true and w.set.play_hand == true, table.concat(w.names, ","))

local function sorted(list)
  local out = {}
  for i, name in ipairs(list) do out[i] = name end
  table.sort(out)
  return table.concat(out, ",")
end

local function crossing(label, name, payload)
  local f = Window.current()
  local mark = #H.frames()
  local id = H.send(name, payload)
  H.tick(0.2)
  local unreg, result_at, unreg_at = 0, nil, nil
  for i, fr in ipairs(since(mark)) do
    if fr.command == "actions/unregister" then unreg, unreg_at = unreg + 1, unreg_at or i end
    if fr.command == "action/result" and fr.data.id == id then result_at = i end
  end
  local r = H.result_for(id)
  check(label .. ": admitted with one result", r ~= nil and r.success == true, r and tostring(r.message))
  check(label .. ": one unregister carries F's decisions and none of its tools",
    unreg == 1 and table.concat(unregistered(since(mark)), ",") == table.concat(decisions_of(f), ",")
      and #tools_in(f.names) > 0,
    table.concat(unregistered(since(mark)), ",") .. " vs " .. table.concat(decisions_of(f), ","))
  check(label .. ": before the result (README.md:23-25)", unreg_at and result_at and unreg_at < result_at,
    tostring(unreg_at) .. "/" .. tostring(result_at))
  check(label .. ": F ended as answered", f.phase == "ended" and f.ended_by == "answered",
    tostring(f.phase) .. "/" .. tostring(f.ended_by))
  mark = #H.frames()
  check(label .. ": the decision is asked again", H.wait_force(), H.phase())
  local registers = 0
  for _, fr in ipairs(since(mark)) do if fr.command == "actions/register" then registers = registers + 1 end end
  local again = Window.current()
  check(label .. ": the next force registers its decisions again in one frame first", registers == 1
    and sorted(listed(since(mark), "actions/register")) == table.concat(decisions_of(again), ","),
    registers .. ": " .. table.concat(listed(since(mark), "actions/register"), ","))
  return id
end

local tool_id = crossing("tool crossing F", "set_joker_order", { from_index = 1, to_index = 2 })
check("the re-asked force offers the same decisions and the tool",
  table.concat(decisions_of(Window.current()), ",") == table.concat(decisions_of(w), ",")
    and Window.current().set.set_joker_order == true, table.concat(Window.current().names, ","))
local decision_id = crossing("decision crossing F", "discard_hand", { indices = { 1, 2 } })

local REASONS = {
  { "liveness_timeout", function(cur) H.tick(Window.liveness_timeout(cur) + 1, 0.5) end },
  { "widened", function()
      G.GAME.current_round.discards_left = 2
      H.tick(0.2)
    end, setup = function()
      G.GAME.current_round.discards_left = 0
      Window.withdraw("fixture")
    end },
  { "run_reset", function() require("core.neuro_lifecycle").withdraw_open_force() end },
  { "confirmation_mode_changed", function() require("core.gate").confirmation_mode_changed(false) end },
  { "persona_from_startup", function()
      G.NEURO.persona = "hiyori"
      require("core.dispatcher").route_message({ command = "startup",
        data = { session = { characterId = "neuro" } } }, G.NEURO)
    end },
  { "state_changed", function()
      G.STATE = H.STATES.BLIND_SELECT
      H.tick(0.2)
    end, leaves = true },
}

for _, case in ipairs(REASONS) do
  local reason, trigger = case[1], case[2]
  if case.setup then case.setup() end
  if not H.wait_force() then
    check(reason .. ": fixture forced a decision", false, H.phase())
  else
    local cur = Window.current()
    local offer = {}
    for i, name in ipairs(cur.names) do offer[i] = name end
    table.sort(offer)
    local mark = #H.frames()
    trigger(cur)
    check(reason .. ": the force ended for that reason", cur.phase == "ended" and cur.ended_by == reason,
      tostring(cur.phase) .. "/" .. tostring(cur.ended_by))
    check(reason .. ": it unregistered its whole offer, tool included",
      table.concat(unregistered(since(mark)), ",") == table.concat(offer, ",") and #tools_in(offer) > 0,
      table.concat(unregistered(since(mark)), ",") .. " vs " .. table.concat(offer, ","))
    if not case.leaves then check(reason .. ": and the game is asked again", H.wait_force(), H.phase()) end
  end
end

local frames = H.frames()
local forced_tools, per_id = 0, {}
for _, f in ipairs(frames) do
  local d = f.data or {}
  if f.command == "actions/force" then
    forced_tools = forced_tools + #tools_in(d.action_names or {})
  elseif f.command == "action/result" then
    per_id[d.id] = (per_id[d.id] or 0) + 1
  end
end
local repeated = {}
for id, count in pairs(per_id) do if count ~= 1 then repeated[#repeated + 1] = id .. "x" .. count end end
local overlapping, active = {}, nil
for i, f in ipairs(frames) do
  local d = f.data or {}
  if f.command == "startup" then
    active = nil
  elseif f.command == "actions/force" then
    if active then overlapping[#overlapping + 1] = "frame " .. i .. " over frame " .. active.at end
    active = { at = i, remaining = {} }
    for _, name in ipairs(d.action_names or {}) do
      if not Policy.is_tool(name) then active.remaining[name] = true end
    end
  elseif f.command == "actions/unregister" and active then
    for _, name in ipairs(d.action_names or {}) do active.remaining[name] = nil end
    if next(active.remaining) == nil then active = nil end
  end
end
check("the forces carried tools", forced_tools >= 6, tostring(forced_tools))
check("no force goes out while an earlier one still has a decision registered (SPECIFICATION.md:138-140)",
  #overlapping == 0, table.concat(overlapping, " | "))
check("every action id got exactly one result", #repeated == 0 and per_id[tool_id] == 1 and per_id[decision_id] == 1,
  table.concat(repeated, ","))
check("the run exercised several forces", forces_in(frames) >= 6, tostring(forces_in(frames)))
H.finish(check, done)
