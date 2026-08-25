_G.NEURO_TEST = true

local check, done = require("tests.helpers").harness("registry_measure")
local Lib = require("tools.registry_measure_lib")

local function line(cmd, data, session_id, seq)
  local json = require("util.neuro_json")
  return json.encode({ command = cmd, data = data, session_id = session_id, seq = seq, game = "Balatro" })
end

local function reg(names_and_defs, session_id, seq)
  local actions = {}
  for i, nd in ipairs(names_and_defs) do
    actions[i] = { name = nd[1], schema = nd[2], description = nd[3] or "" }
  end
  return line("actions/register", { actions = actions }, session_id, seq)
end

local function unreg(names, session_id, seq)
  return line("actions/unregister", { action_names = names }, session_id, seq)
end

local function force(action_names, session_id, seq)
  return line("actions/force", { action_names = action_names, query = "q", priority = "low" }, session_id, seq)
end

local function result(id, session_id, seq)
  return line("action/result", { id = id, success = true }, session_id, seq)
end

local function startup(session_id, seq)
  return line("startup", nil, session_id, seq)
end

local function run_lines(lines)
  local run = Lib.new_run()
  Lib.process_lines(run, lines, "synthetic")
  return Lib.finalize(run)
end

do
  local defA = { type = "object", required = {}, properties = {} }
  local lines = {
    reg({ { "play_hand", defA } }, 1, 1),
    reg({ { "play_hand", defA } }, 1, 2),
  }
  local agg = run_lines(lines)
  check("planted duplicate register is detected", agg.a_redundant_register_frames == 1,
    agg.a_redundant_register_frames)
  check("planted duplicate register frame still counts as a register frame", agg.register_frames == 2)
end

do
  local defA = { type = "object", required = {}, properties = {} }
  local lines = {
    reg({ { "play_hand", defA } }, 2, 1),
    unreg({ "play_hand" }, 2, 2),
    reg({ { "play_hand", defA } }, 2, 3),
  }
  local agg = run_lines(lines)
  check("re-register after unregister is not counted as redundant", agg.a_redundant_register_frames == 0,
    agg.a_redundant_register_frames)
end

do
  local defA = { type = "object", required = {}, properties = {} }
  local defB = { type = "object", required = { "x" }, properties = { x = { type = "string" } } }
  local lines = {
    reg({ { "play_hand", defA } }, 3, 1),
    reg({ { "play_hand", defB } }, 3, 2),
  }
  local agg = run_lines(lines)
  check("changed definition while live is not counted as redundant", agg.a_redundant_register_frames == 0,
    agg.a_redundant_register_frames)
end

do
  local defA = { type = "object", required = {}, properties = {} }
  local lines = {
    reg({ { "play_hand", defA } }, 4, 1),
    reg({ { "play_hand", defA }, { "discard_hand", defA } }, 4, 2),
  }
  local agg = run_lines(lines)
  check("mixed new+duplicate frame is not counted redundant", agg.a_redundant_register_frames == 0,
    agg.a_redundant_register_frames)
end

do
  local lines = {
    force({ "play_hand" }, 5, 1),
    force({ "discard_hand" }, 5, 2),
    result("id1", 5, 3),
  }
  local agg = run_lines(lines)
  check("planted overlapping force is detected", agg.b_overlapping_forces == 1, agg.b_overlapping_forces)
end

do
  local lines = {
    force({ "play_hand" }, 6, 1),
    result("id1", 6, 2),
    force({ "discard_hand" }, 6, 3),
    result("id2", 6, 4),
  }
  local agg = run_lines(lines)
  check("sequential answered forces are not counted as overlap", agg.b_overlapping_forces == 0,
    agg.b_overlapping_forces)
end

-- API/README.md: unregistering every disposable name cancels an upcoming force;
-- a replacement sent after that withdrawal is not an overlap.
do
  local lines = {
    force({ "discard_hand" }, 61, 1),
    unreg({ "discard_hand" }, 61, 2),
    force({ "play_hand", "discard_hand" }, 61, 3),
  }
  local agg = run_lines(lines)
  check("full unregister cancels the old force before its replacement",
    agg.b_overlapping_forces == 0, agg.b_overlapping_forces)
end

do
  local lines = {
    force({ "play_hand", "discard_hand" }, 62, 1),
    unreg({ "discard_hand" }, 62, 2),
    force({ "play_hand" }, 62, 3),
  }
  local agg = run_lines(lines)
  check("partial unregister does not disguise a real overlap",
    agg.b_overlapping_forces == 1, agg.b_overlapping_forces)
end

do
  local lines = {
    force({ "play_hand" }, 63, 1),
    unreg({ "sell_card" }, 63, 2),
    force({ "discard_hand" }, 63, 3),
  }
  local agg = run_lines(lines)
  check("unrelated unregister does not close the force",
    agg.b_overlapping_forces == 1, agg.b_overlapping_forces)
end

do
  local lines = {
    force({ "play_hand" }, 7, 1),
    force({ "play_hand" }, 8, 1),
    result("id1", 7, 2),
    result("id1", 8, 2),
  }
  local agg = run_lines(lines)
  check("interleaved sessions stay isolated for force tracking", agg.b_overlapping_forces == 0,
    agg.b_overlapping_forces)
  check("interleaved sessions are counted separately", agg.sessions == 2, agg.sessions)
end

do
  local defA = { type = "object", required = {}, properties = {} }
  local defB = { type = "object", required = { "x" }, properties = { x = { type = "string" } } }
  local lines = {
    reg({ { "a", defA } }, 9, 1),
    unreg({ "a" }, 9, 2),
    reg({ { "a", defA } }, 9, 3),
    unreg({ "a" }, 9, 4),
    reg({ { "a", defA } }, 9, 5),
    reg({ { "b", defB } }, 9, 6),
  }
  local agg = run_lines(lines)
  check("instance count matches plant (4 total sends)", agg.c_instances == 4, agg.c_instances)
  check("unique-definition count matches plant (2 distinct)", agg.c_unique_count == 2, agg.c_unique_count)
  check("count-based multiplicity is instances/uniques", math.abs(agg.c_multiplicity_count - 2.0) < 1e-9,
    agg.c_multiplicity_count)
end

do
  local defA = { type = "object", required = {}, properties = {} }
  local lines = {
    reg({ { "a", defA } }, 10, 1),
    "{not json",
    "",
    force({ "a" }, 10, 2),
  }
  local ok, agg = pcall(run_lines, lines)
  check("malformed line does not crash the reader", ok, agg)
  if ok then
    check("malformed line is tallied", agg.malformed == 1, agg.malformed)
    check("well-formed lines around a malformed one still get processed", agg.frames == 2, agg.frames)
  end
end

do
  local lines = { reg({}, 11, 1) }
  local agg = run_lines(lines)
  check("an empty register frame is not counted as a redundant one", agg.a_redundant_register_frames == 0,
    agg.a_redundant_register_frames)
end

do
  local defA = { type = "object", required = {}, properties = {} }
  local lines = {
    startup(nil, 1),
    reg({ { "play_hand", defA } }, nil, 2),
    reg({ { "play_hand", defA } }, nil, 3),
    force({ "play_hand" }, nil, 4),
    force({ "discard_hand" }, nil, 5),
    result("id1", nil, 6),
  }
  local ok, agg = pcall(run_lines, lines)
  check("a sessionless file does not crash the reader", ok, agg)
  if ok then
    check("a sessionless file falls back to exactly one session", agg.sessions == 1, agg.sessions)
    check("redundant-register detection still works without session_id",
      agg.a_redundant_register_frames == 1, agg.a_redundant_register_frames)
    check("overlapping-force detection still works without session_id",
      agg.b_overlapping_forces == 1, agg.b_overlapping_forces)
  end
end

do
  local lines = {
    startup(nil, 1),
    reg({ { "play_hand", { type = "object", required = {}, properties = {} } } }, nil, 2),
    startup(nil, 3),
    reg({ { "discard_hand", { type = "object", required = {}, properties = {} } } }, nil, 4),
  }
  local run = Lib.new_run()
  local ok, err = pcall(Lib.process_lines, run, lines, "synthetic-multi-session")
  check("a genuinely multi-session sessionless file is refused, not merged", not ok, ok)
  if not ok then
    check("the refusal names the multi-session cause", tostring(err):find("multi%-session") ~= nil, err)
  end
end

done()
