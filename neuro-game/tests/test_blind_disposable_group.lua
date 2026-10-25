local H = require("tests.hand_pipeline_harness")
local check, done = require("tests.helpers").harness("blind-disposable-group")

local PLAN = { hand_plan = "Play the best pair each hand", build_plan = "Buy a mult joker next shop",
  money_plan = "Hold cash for interest" }

local function blind_select_board()
  H.board()
  G.STATE = H.STATES.BLIND_SELECT
  G.NEURO.state = "BLIND_SELECT"
  G.GAME.round_resets.blind_tags = { Small = "tag_economy", Big = "tag_economy" }
  G.blind_select_opts = { small = { get_UIE_by_ID = function() return {} end },
    big = { get_UIE_by_ID = function() return {} end } }
  G.FUNCS.select_blind = function()
    G.STATE = H.STATES.SELECTING_HAND
    G.GAME.round_resets.blind_states.Small = "Current"
  end
  G.FUNCS.skip_blind = function()
    G.GAME.round_resets.blind_states.Small = "Skipped"
    G.GAME.round_resets.blind_states.Big = "Select"
    G.GAME.blind_on_deck = "Big"
    G.GAME.round_resets.blind_on_deck = "Big"
  end
end

local function sequence_after(id)
  local out, started = {}, false
  for _, f in ipairs(H.frames()) do
    if f.command == "actions/unregister" then
      out[#out + 1] = "unregister:" .. table.concat(f.data.action_names, ",")
    elseif f.command == "action/result" and f.data.id == id then
      out[#out + 1] = "result"
      started = true
    elseif started and f.command == "actions/force" then
      out[#out + 1] = "force:" .. table.concat(f.data.action_names, ",")
    elseif started and f.command == "actions/register" then
      local names = {}
      for _, a in ipairs(f.data.actions or {}) do names[#names + 1] = a.name end
      out[#out + 1] = "register:" .. table.concat(names, ",")
    end
  end
  return table.concat(out, " ; ")
end

do
  blind_select_board()
  H.tick(10)
  local id = H.send("select_blind", { blind = "small", plan = PLAN })
  H.tick(10)
  local seq = sequence_after(id)
  check("select_blind unregisters select_blind and skip_blind, not the record_plan tool, before its result",
    seq:find("unregister:select_blind,skip_blind ; result", 1, true) ~= nil, seq)
  check("the round's force follows with neither blind answer registered",
    seq:find("force:play_hand,discard_hand", 1, true) ~= nil and seq:find("; register:", 1, true) == nil, seq)
end

do
  blind_select_board()
  H.tick(10)
  local id = H.send("skip_blind", "{}")
  H.tick(10)
  local seq = sequence_after(id)
  check("skip_blind unregisters select_blind and skip_blind, not the record_plan tool, before its result",
    seq:find("unregister:select_blind,skip_blind ; result", 1, true) ~= nil, seq)
  check("the next blind's force registers both again before offering them",
    seq:find("register:[^;]*select_blind[^;]*skip_blind[^;]* ; force:select_blind,skip_blind") ~= nil
      or seq:find("register:[^;]*skip_blind[^;]*select_blind[^;]* ; force:select_blind,skip_blind") ~= nil, seq)
end

H.finish(check, done)
