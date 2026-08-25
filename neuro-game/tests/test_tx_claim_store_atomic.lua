_G.NEURO_TEST = true

local CLOCK = { t = 2000 }
love = { timer = { getTime = function() return CLOCK.t end } }
_G.G = { NEURO = {}, TIMERS = { REAL = 2000 } }

local Bridge = require("core.bridge")
local Protocol = require("core.bridge_protocol")
local TxCache = require("core.tx_cache")
local json = require("util.neuro_json")
local Helpers = require("tests.helpers")
local check, done = Helpers.harness("tx-claim-store-atomic")

local TmpWork = require("tests.tmp_workdir")
local dir = TmpWork.open("tx_claim_store")
local OUTBOX = dir .. "/neuro_outbox.jsonl"

local function fresh()
  os.execute("rm -rf '" .. dir .. "' && mkdir -p '" .. dir .. "'")
  CLOCK.t = 2000
  TxCache.reset()
  local b = Bridge:new({ game = "Balatro", enabled = true, fs_dir = dir })
  b:set_message_handler(function() end)
  return b
end

local function results()
  local per_id, total = {}, 0
  local f = io.open(OUTBOX, "r")
  if not f then return per_id, total end
  for line in f:lines() do
    local ok, frame = pcall(json.decode, line)
    if ok and type(frame) == "table" and frame.command == "action/result" then
      local id = tostring(frame.data and frame.data.id)
      total = total + 1
      per_id[id] = (per_id[id] or 0) + 1
    end
  end
  f:close()
  return per_id, total
end

local function payability(id)
  if TxCache.get(id) ~= nil then return "stored" end
  if TxCache.claim(id) then
    TxCache.release_claim(id)
    return "claimable"
  end
  return "burned"
end

do
  TxCache.reset()
  local committed = TxCache.settle("prim-commit", function()
    return { ok = true, message = "done", name = "play_hand" }
  end)
  check("settle commits the verdict its attempt returned",
    committed == true and payability("prim-commit") == "stored")

  TxCache.open("prim-decline", "play_hand", CLOCK.t)
  local declined, extra = TxCache.settle("prim-decline", function() return nil, "receipt" end)
  check("a declining attempt hands the claim back instead of burning it",
    declined == false and extra == "receipt" and payability("prim-decline") == "claimable")
  check("a declined settle leaves the obligation on the deadline ledger",
    #TxCache.outstanding(CLOCK.t) == 1)

  TxCache.open("prim-throw", "play_hand", CLOCK.t)
  local ok, err = pcall(TxCache.settle, "prim-throw", function() error("attempt exploded", 0) end)
  check("a throwing attempt releases the claim and re-raises unchanged",
    ok == false and err == "attempt exploded" and payability("prim-throw") == "claimable")

  TxCache.settle("prim-once", function() return { ok = true, message = "first" } end)
  check("settle refuses a second attempt on an already answered id",
    TxCache.settle("prim-once", function() return { ok = false, message = "second" } end) == nil)

  local reentered = false
  TxCache.settle("prim-reentry", function()
    reentered = TxCache.settle("prim-reentry", function() return { ok = true } end) == nil
    return { ok = true, message = "outer" }
  end)
  check("a claim held by settle blocks a re-entrant settle on the same id", reentered)
end

do
  local b = fresh()
  TxCache.open("exit-ok", "play_hand", CLOCK.t)
  local accepted = b:send_action_result("exit-ok", true, "settled")
  check("exit: an accepted send stores the verdict",
    accepted == true and payability("exit-ok") == "stored")
  check("exit: a duplicate send is refused without disturbing the stored verdict",
    b:send_action_result("exit-ok", true, "again") == false
      and payability("exit-ok") == "stored")
end

do
  local b = fresh()
  TxCache.open("exit-rejected", "play_hand", CLOCK.t)
  b.enabled = false
  local accepted = b:send_action_result("exit-rejected", true, "rejected outright")
  b.enabled = true
  check("exit: a rejected send returns the claim",
    accepted == false and payability("exit-rejected") == "claimable")
  b:answer_owed_results(nil, "paid after recovery")
  local per_id = results()
  check("exit: the returned claim is payable exactly once",
    per_id["exit-rejected"] == 1)
end

do
  local b = fresh()
  TxCache.open("exit-send-throw", "play_hand", CLOCK.t)
  local original_send = b.send
  b.send = function() error("transport exploded") end
  local ok = pcall(b.send_action_result, b, "exit-send-throw", true, "never written")
  b.send = original_send
  check("exit: a throwing transport returns the claim",
    ok == false and payability("exit-send-throw") == "claimable")
  b:answer_owed_results(nil, "paid after recovery")
  check("exit: the claim returned by a throwing transport is payable exactly once",
    results()["exit-send-throw"] == 1)
end

do
  local b = fresh()
  TxCache.open("exit-frame-throw", "play_hand", CLOCK.t)
  local original_result = Protocol.result
  Protocol.result = function() error("frame builder exploded") end
  local ok = pcall(b.send_action_result, b, "exit-frame-throw", true, "never built")
  Protocol.result = original_result
  check("exit: a throw while building the result frame returns the claim",
    ok == false and payability("exit-frame-throw") == "claimable")
  b:answer_owed_results(nil, "paid after recovery")
  check("exit: the claim returned by a frame-builder throw is payable exactly once",
    results()["exit-frame-throw"] == 1)
end

do
  local b = fresh()
  TxCache.open("exit-unregister", "cash_out", CLOCK.t)
  b._force_answer_ids["exit-unregister"] = "cash_out_force_1"
  b._active_force_wire_by_canonical = { cash_out = "cash_out_force_1" }
  b._registered_force_aliases = { cash_out_force_1 = true }
  b.enabled = false
  local accepted = b:send_action_result("exit-unregister", true, "closes the force")
  b.enabled = true
  check("exit: a rejected force-alias unregister returns the claim",
    accepted == false and payability("exit-unregister") == "claimable")
  check("exit: the aborted force close left no result on the wire", results()["exit-unregister"] == nil)
  b._force_answer_ids["exit-unregister"] = nil
  b._active_force_wire_by_canonical = nil
  b:answer_owed_results(nil, "paid after recovery")
  check("exit: the claim returned by a rejected unregister is payable exactly once",
    results()["exit-unregister"] == 1)
end

do
  local pipe = assert(io.popen(
    "find . -name '*.lua' -not -path './tests/*' -not -path './.git/*' | sort"))
  local offenders, scanned, importers = {}, 0, 0
  for path in pipe:lines() do
    if path ~= "./core/tx_cache.lua" then
      local f = io.open(path, "r")
      if f then
        local src = Helpers.strip_lua_comments(f:read("*a"))
        f:close()
        scanned = scanned + 1
        local aliases = { ['require%("core%.tx_cache"%)'] = true }
        for alias in src:gmatch('[%w_]+%s*=%s*require%("core%.tx_cache"%)') do
          aliases[alias:match("^([%w_]+)")] = true
          importers = importers + 1
        end
        for alias in pairs(aliases) do
          for call in src:gmatch(alias .. "%s*%.%s*([%w_]+)%s*%(") do
            if call == "claim" or call == "release_claim" then
              offenders[#offenders + 1] = path .. " -> " .. call
            end
          end
        end
      end
    end
  end
  pipe:close()
  check("the guard actually scanned the production tree", scanned > 50, tostring(scanned))
  check("the guard resolved the ledger's local name where it is imported", importers >= 3,
    tostring(importers))
  check("no production file outside the ledger takes a bare claim",
    #offenders == 0, table.concat(offenders, ", "))
end

TmpWork.close()
done()
