
local Audit = require("tools.force_wire_audit")
local check, done = require("tests.helpers").harness("force-wire-audit")

local bad, malformed = Audit.scan_file("tests/fixtures/force_wire_ante4_regression.jsonl")
check("archived Ante 4 regression fixture is valid JSONL", bad ~= nil and #malformed == 0)
local archived_overlap = false
for _, finding in ipairs(bad or {}) do
  if finding.kind == "overlapping_force" and finding.previous_line == 5 and finding.line == 6 then
    archived_overlap = true
  end
end
check("archived Ante 4 regression is detected", archived_overlap, #bad)

local valid = {
  { command = "startup", data = {} },
  { command = "actions/register", data = { actions = {
    { name = "play_hand" }, { name = "discard_hand" },
  } } },
  { command = "actions/force", data = { action_names = { "play_hand", "discard_hand" } } },
  { command = "actions/unregister", data = { action_names = { "play_hand", "discard_hand" } } },
  { command = "actions/register", data = { actions = {
    { name = "play_hand" }, { name = "discard_hand" },
  } } },
  { command = "actions/force", data = { action_names = { "play_hand", "discard_hand" } } },
  { command = "action", data = { id = "answer", name = "play_hand", data = "{}" } },
  { command = "action/result", data = { id = "answer", success = true } },
  { command = "actions/force", data = { action_names = { "play_hand" } } },
}
check("exact unregister-register cycle permits replacement", #Audit.scan_frames(valid, "valid") == 0)

valid[5] = nil
local compact = {}
for i = 1, 9 do if valid[i] then compact[#compact + 1] = valid[i] end end
local missing = Audit.scan_frames(compact, "missing-register")
check("replacement cannot force names that cancellation left unregistered",
  #missing >= 1 and missing[1].kind == "forced_action_not_registered")

local class40 = Audit.scan_frames({
  { command = "startup", data = {} },
  { command = "actions/register", data = { actions = {
    { name = "cash_out", description = "canonical" },
    { name = "cash_out_force_7", description = "Call cash_out to continue" },
  } } },
  { command = "actions/force", data = {
    action_names = { "cash_out_force_7" }, state = "ROUND_EVAL cash_out",
    query = "Your move: cash_out|{}",
  } },
}, "class40")
check("class 40 catches canonical identifiers contradicting a scoped force alias",
  #class40 == 3 and class40[1].kind == "force_text_nonoffered_action", #class40)

local alias_clean = Audit.scan_frames({
  { command = "startup", data = {} },
  { command = "actions/register", data = { actions = {
    { name = "cash_out" },
    { name = "cash_out_force_7", description = "Call cash_out_force_7 to continue" },
  } } },
  { command = "actions/force", data = {
    action_names = { "cash_out_force_7" }, state = "ROUND_EVAL cash_out_force_7",
    query = "Your move: cash_out_force_7|{}",
  } },
}, "alias-clean")
check("class 40 scanner does not mistake a canonical prefix inside its alias", #alias_clean == 0)

local foreign_result = Audit.scan_frames({
  { command = "actions/register", data = { actions = {
    { name = "cash_out_force_1" }, { name = "record_plan" }, { name = "cash_out_force_2" },
  } } },
  { command = "actions/force", data = { action_names = { "cash_out_force_1" } } },
  { command = "action", data = { id = "foreign", name = "record_plan", data = "{}" } },
  { command = "action/result", data = { id = "foreign", success = true } },
  { command = "actions/force", data = { action_names = { "cash_out_force_2" } } },
}, "foreign-result")
check("a successful result for a foreign id does not close the active force",
  #foreign_result == 1 and foreign_result[1].kind == "overlapping_force", #foreign_result)

done()
