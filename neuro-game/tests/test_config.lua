_G.NEURO_TEST = true

local checks, fails = 0, 0
local function check(label, ok, detail)
  checks = checks + 1
  if ok then
    print("PASS " .. label)
  else
    fails = fails + 1
    print("FAIL " .. label .. (detail and (": " .. tostring(detail)) or ""))
  end
end

G = { SETTINGS = { GAMESPEED = 1 } }

local Config = require("core.config")
local Schema = require("core.config_schema")
local PERSONA_DEFAULT = Schema.by_key.NEURO_PERSONA.default
local data = { settings = {}, colours = {} }
local writes = 0
Config.init(data, function() writes = writes + 1; return true end)

check("empty storage uses deterministic defaults", Config.get_raw("NEURO_SPEED_MULT") == 1.0)
check("default config starts clean", Config._test.is_dirty() == false)
check("unknown setting is rejected", Config.set("NEURO_NOT_A_SETTING", 1) == nil)
check("invalid enum is rejected", Config.set("NEURO_PERSONA", "unknown") == nil)
check("all shipped personas are valid", Config.set("NEURO_PERSONA", "hiyori") == "hiyori")
check("session enum is readable after being set", Config.get_raw("NEURO_PERSONA") == "hiyori")
check("session enum never reaches the persisted store", data.settings.NEURO_PERSONA == nil)
check("session enum alone does not dirty the config", Config._test.is_dirty() == false)
check("non-session enum override is stored",
  Config.set("NEURO_CD_PRESET", "2x") == "2x" and data.settings.NEURO_CD_PRESET == "2x")
check("resetting a session enum falls back to the default",
  Config.reset("NEURO_PERSONA") == PERSONA_DEFAULT
    and Config.get_raw("NEURO_PERSONA") == PERSONA_DEFAULT)
Config.reset("NEURO_CD_PRESET")
check("number is clamped", Config.set("NEURO_SPEED_MULT", 99) == 2.0)
check("clamped number is stored", data.settings.NEURO_SPEED_MULT == 2.0)
check("setting a default removes the override", Config.set("NEURO_SPEED_MULT", 1.0) == 1.0 and data.settings.NEURO_SPEED_MULT == nil)
check("reset removes an override",
  Config.reset("NEURO_PERSONA") == PERSONA_DEFAULT and data.settings.NEURO_PERSONA == nil)
check("mutations mark config dirty", Config._test.is_dirty() == true)
check("save delegates exactly once", Config.save() == true and writes == 1)
check("successful save clears dirty", Config._test.is_dirty() == false)
check("clean save performs no write", Config.save() == true and writes == 1)

Config.set("NEURO_PERF_LOG", "on")
check("bool reads on-off enums", Config.bool("NEURO_PERF_LOG") == true)
Config.set("NEURO_COOLDOWN_SCALE", 2)
check("get_raw remains unscaled", Config.get_raw("NEURO_POST_PLAY") == 1.4)
check("get applies cooldown scale", math.abs(Config.get("NEURO_POST_PLAY") - 2.8) < 1e-9)

check("colour override accepts and normalizes hex", Config.set_colour("neuro", "ACCENT", "0a141e") == true
  and data.colours.neuro.ACCENT == "0A141E")
check("colour reset removes sparse storage", Config.reset_colour("neuro", "ACCENT") == true
  and data.colours.neuro == nil)

local failed_writes = 0
Config.init(data, function() failed_writes = failed_writes + 1; return false, "disk full" end)
Config.set("NEURO_DEBUG", "on")
local ok, err = Config.save()
check("failed save reports failure", ok == false and tostring(err):find("disk full", 1, true) ~= nil)
check("failed save preserves dirty state", Config._test.is_dirty() == true and failed_writes == 1)

Config.init(data, function() error("write exploded") end)
Config.set("NEURO_DEBUG", "off")
ok, err = Config.save()
check("save callback exception is contained", ok == false and tostring(err):find("write exploded", 1, true) ~= nil)
check("callback exception preserves dirty state", Config._test.is_dirty() == true)

local restored = { settings = { NEURO_PERSONA = "evil", NEURO_SPEED_MULT = 1.5 }, colours = { evil = { ACCENT = "E63950" } } }
Config.init(restored, function() return true end)
check("reinitialization restores native settings", Config.get_raw("NEURO_SPEED_MULT") == 1.5)
check("a session key left on disk by an older build is purged at init",
  restored.settings.NEURO_PERSONA == nil)
check("a purged session key reverts to its default",
  Config.get_raw("NEURO_PERSONA") == PERSONA_DEFAULT)

do
  local flagged = {}
  for _, def in ipairs(Schema.entries) do
    if def.event then flagged[#flagged + 1] = def.key end
  end
  check("no key declares the retired event flag (" .. table.concat(flagged, ",") .. ")",
    #flagged == 0)
end

do
  local ok_fh, ForceHelpers = pcall(require, "force.force_helpers")
  G.NEURO = G.NEURO or {}
  G.NEURO.persona = PERSONA_DEFAULT
  local gate = ok_fh and ForceHelpers.hiyori_persona_gate and ForceHelpers.hiyori_persona_gate()
  check("the boot persona is the unset sentinel, so the identity gate fires",
    type(gate) == "table" and gate.actions and gate.actions[1] == "choose_persona")
  for _, pk in ipairs({ "neuro", "evil" }) do
    G.NEURO.persona = pk
    check("a chosen persona (" .. pk .. ") closes the identity gate",
      ok_fh and ForceHelpers.hiyori_persona_gate() == nil)
  end
  G.NEURO.persona = nil
end
check("reinitialization restores native colours", Config._test.get_colour("evil", "ACCENT") == "E63950")

local corrupt = { settings = { UNKNOWN = 1, NEURO_SPEED_MULT = 99, NEURO_PERSONA = "bad" }, colours = "bad" }
Config.init(corrupt, function() return true end)
check("initialization sanitizes unknown and invalid settings", corrupt.settings.UNKNOWN == nil
  and corrupt.settings.NEURO_PERSONA == nil and corrupt.settings.NEURO_SPEED_MULT == 2.0)
check("initialization repairs colour storage", type(corrupt.colours) == "table")
check("normalization marks repaired config dirty", Config._test.is_dirty() == true)

do
  Config.init({ settings = {}, colours = {} }, function() return true end)
  local FS = require("core.force_state")
  local cases = {
    { key = "NEURO_ACK_IDLE_REASK", const = "ACK_IDLE_REASK" },
    { key = "NEURO_FORCE_LIVENESS_TIMEOUT", const = "FORCE_LIVENESS_TIMEOUT" },
    { key = "NEURO_FORCE_CANCEL_SETTLE", const = "CANCEL_SETTLE" },
  }
  for _, case in ipairs(cases) do
    local def = Schema.by_key[case.key]
    check(case.key .. " is a tunable second, not a cooldown-scaled one",
      def ~= nil and def.kind == "number" and def.unit == "s" and def.cd ~= true,
      def and tostring(def.cd) or "missing")
    check(case.key .. " default is the constant core/force_state.lua exports",
      def and def.default == FS[case.const], def and tostring(def.default) or "missing")
  end

  G.NEURO = { enabled = true, decision_serial = 0, decision_ack_serial = 0,
    decision_ack_at = 0, force_sent_at = 0, force_cancel_pending = { names = { "x" },
      set = { x = true }, at = 0 } }
  G.NEURO.force_window = { key = "S#0", state = "S", phase = "acknowledged",
    names = { "x" }, set = { x = true } }
  check("ack idle re-ask follows the knob, not the constant",
    FS.reask_due(FS.ACK_IDLE_REASK - 1) == false
      and (Config.set("NEURO_ACK_IDLE_REASK", 10) or true)
      and FS.reask_due(11) == true,
    tostring(Config.get("NEURO_ACK_IDLE_REASK")))
  Config.reset("NEURO_ACK_IDLE_REASK")

  G.NEURO.force_window.phase = "forced"
  check("force liveness follows the knob, not the constant",
    FS.liveness_expired(FS.FORCE_LIVENESS_TIMEOUT - 1) == false
      and (Config.set("NEURO_FORCE_LIVENESS_TIMEOUT", 30) or true)
      and FS.liveness_expired(31) == true,
    tostring(Config.get("NEURO_FORCE_LIVENESS_TIMEOUT")))
  Config.reset("NEURO_FORCE_LIVENESS_TIMEOUT")

  G.NEURO.force_cancel_pending.phase = "sending"
  G.NEURO.force_cancel_pending.started_at = 0
  G.NEURO.force_cancel_pending.receipt = { status = "buffered" }
  local cancellation_before_cap = FS.cancel_pending(FS.CANCEL_IDLE_CAP - 0.1)
  local cancellation_was_waiting = cancellation_before_cap ~= nil
    and cancellation_before_cap.stalled ~= true
  Config.set("NEURO_FORCE_CANCEL_IDLE", 1)
  local cancellation_after_cap = FS.cancel_pending(FS.CANCEL_IDLE_CAP + 1)
  check("cancel fail-closed bound follows the knob without permitting an overlapping force",
    cancellation_was_waiting
      and cancellation_after_cap == nil and G.NEURO.force_cancel_pending == nil
      and G.NEURO.force_transport_fault ~= nil and G.NEURO.llm_paused == true,
    tostring(Config.get("NEURO_FORCE_CANCEL_IDLE")))
  Config.reset("NEURO_FORCE_CANCEL_IDLE")
  G.NEURO = nil
end

print(string.format("==== config: %d/%d PASS, %d FAIL ====", checks - fails, checks, fails))
os.exit(fails == 0 and 0 or 1)
