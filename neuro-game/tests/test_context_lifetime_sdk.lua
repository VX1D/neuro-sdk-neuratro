_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local Helpers = require("tests.helpers")
local check, done = Helpers.harness("context-lifetime-sdk")

local function read(path)
  local f = assert(io.open(path, "r"))
  local s = f:read("*a")
  f:close()
  return s
end

local OWNERS = { ["core/bridge.lua"] = true, ["core/context_delivery.lua"] = true }
local EXCLUDED_ROOTS = { tests = true }

local GUARDS = {
  "send_context%s*=%s*function",           -- stub field on a fake bridge object
  "type%s*%(%s*[^()]-send_context%s*%)",   -- capability probe
  "and%s+[%w_%.]-send_context%s*%)",       -- truthiness guard inside a condition
}

local function guard_ranges(line)
  local ranges = {}
  for _, pat in ipairs(GUARDS) do
    local init = 1
    while true do
      local s, e = line:find(pat, init)
      if not s then break end
      ranges[#ranges + 1] = { s, e }
      init = e + 1
    end
  end
  return ranges
end

local function scan_source(src)
  local found = {}
  local lineno = 0
  for line in (Helpers.strip_lua_comments(src) .. "\n"):gmatch("([^\n]*)\n") do
    lineno = lineno + 1
    if line:find("send_context", 1, true) then
      local ranges = guard_ranges(line)
      local init = 1
      while true do
        local s = line:find("send_context", init, true)
        if not s then break end
        local guarded = false
        for _, r in ipairs(ranges) do
          if s >= r[1] and s <= r[2] then guarded = true break end
        end
        if not guarded then
          found[#found + 1] = { line = lineno, text = (line:gsub("^%s+", "")) }
        end
        init = s + 1
      end
    end
  end
  return found
end

local EVASIONS = {
  { "colon call", "  G.NEURO:send_context(text, true)" },
  { "plain dot call", "  G.NEURO.send_context(b, msg, true, {})" },
  { "pcall handle", "  pcall(G.NEURO.send_context, b, msg, true)" },
  { "local alias", "  local f = b.send_context\n  f(b, msg, true)" },
  { "string index", '  b["send_context"](b, msg, true)' },
  { "rawget handle", '  local f = rawget(b, "send_context")' },
  { "method definition", "  function Shadow:send_context(msg) return self.b:send(msg) end" },
  { "tail of a chain", "  local send = G.NEURO and G.NEURO.send_context" },
}
local missed = {}
for _, case in ipairs(EVASIONS) do
  if #scan_source(case[2]) == 0 then missed[#missed + 1] = case[1] end
end
check("the producer scan catches every known call shape", #missed == 0, table.concat(missed, ", "))

local ALLOWED = {
  { "capability guard", "  if not (bridge and bridge.send_context) then return end" },
  { "nested capability guard", "  if not (G and G.NEURO and G.NEURO.send_context) then return false end" },
  { "type probe", '  if not (b and type(b.send_context) == "function") then return false end' },
  { "fake-bridge stub", "  send_context = function() end, register_actions = function() end," },
  { "prose about the transport", "  -- Bridge:send_context returns true for a buffered frame too" },
}
local false_alarms = {}
for _, case in ipairs(ALLOWED) do
  if #scan_source(case[2]) > 0 then false_alarms[#false_alarms + 1] = case[1] end
end
check("B0b the producer scan does not flag capability guards, stubs or prose",
  #false_alarms == 0, table.concat(false_alarms, ", "))

local files, roots = {}, {}
do
  local p = assert(io.popen("find . -name '*.lua' -type f -not -path './.git/*' | sort"))
  for path in p:lines() do
    path = path:gsub("^%./", "")
    local root = path:match("^([^/]+)/") or "."
    roots[root] = (roots[root] or 0) + 1
    if not EXCLUDED_ROOTS[root] then files[#files + 1] = path end
  end
  p:close()
end
check("B1a the producer scan walks the whole repo, not a directory list",
  #files >= 100 and roots["core"] and roots["hud"] and roots["render"] and roots["."],
  #files .. " files scanned")

local offenders, seen_owners = {}, 0
for _, path in ipairs(files) do
  if OWNERS[path] then
    seen_owners = seen_owners + 1
  else
    for _, hit in ipairs(scan_source(read(path))) do
      offenders[#offenders + 1] = path .. ":" .. hit.line .. "  " .. hit.text
    end
  end
end
check("B1b the two context owners are the files the scan exempts, and they exist",
  seen_owners == 2, tostring(seen_owners))
check("only core/bridge.lua and core/context_delivery.lua put context on the wire",
  #offenders == 0, table.concat(offenders, " | "))

local registry = read("facts/hint_registry.lua")
check("registry has no durable/retraction exception channel",
  registry:find("durable%s*=") == nil and registry:find("exception%s*=") == nil
    and registry:find("sh_rules_retire", 1, true) == nil)
local compact = read("context/context_compact.lua")
check("assembler has explicit lifetime ownership and no prefix classifier",
  compact:find("STABLE_PREFIXES", 1, true) == nil
    and compact:find('owned_section("rule"', 1, true) ~= nil
    and compact:find('owned_section("state"', 1, true) ~= nil)

local ContextDelivery = require("core.context_delivery")
local ContextCompact = require("context.context_compact")
local Orchestrator = require("core.orchestrator")

local function producer()
  for level = 3, 10 do
    local info = debug.getinfo(level, "S")
    if not info then break end
    if info.what ~= "C" then return tostring(info.source) end
  end
  return "?"
end

local wire, foreign = {}, {}
local function record(_, msg, silent, receipt)
  local from = producer()
  wire[#wire + 1] = { msg = tostring(msg), silent = silent, from = from }
  if not from:find("context_delivery", 1, true) then foreign[#foreign + 1] = from end
  if receipt then receipt.status = "written" end
  return true
end

local function world(dollars, joker_name, send)
  _G.G = {
    STATE = 1, STATES = { SELECTING_HAND = 1 }, P_CENTERS = {},
    GAME = {
      dollars = dollars, chips = 0, bankrupt_at = 0, used_vouchers = {}, modifiers = {},
      current_round = { hands_left = 3, discards_left = 2, reroll_cost = 5 },
      round_resets = { ante = 2 }, blind = { name = "Small Blind", chips = 300, mult = 1 },
    },
    jokers = { cards = joker_name and { { ability = { name = joker_name, set = "Joker" },
      config = { center = { key = "j_test", name = joker_name, set = "Joker" } } } } or {},
      config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    hand = { cards = {}, highlighted = {} }, playing_cards = {},
    NEURO = { enabled = true, run_generation = 1, once_serials = {}, session_once_serials = {},
      stable_refresh_due = true, send_context = send or record },
  }
  ContextCompact.invalidate_cache()
end

ContextDelivery.reset_transport()
world(8, "Joker")
Orchestrator._maybe_emit_stable_context("SELECTING_HAND")
local first = #wire
check("driving the real producer puts retained context on the wire", first > 0, tostring(first))
check("L1b every retained frame was produced by the typed owner, no other caller reached the bridge",
  #foreign == 0, table.concat(foreign, ", "))
local all_silent = first > 0
for i = 1, first do if wire[i].silent ~= true then all_silent = false end end
check("L1c retained frames are silent", all_silent)

world(23, "Bull")
Orchestrator._maybe_emit_stable_context("SELECTING_HAND")
check("a live run mutation produces no second retained frame", #wire == first, tostring(#wire))

ContextDelivery.rule("lifetime:probe", "immutable rule text")
local after_probe = #wire
check("L3a a rule is written once", after_probe == first + 1, tostring(after_probe))
local ok_change = pcall(ContextDelivery.rule, "lifetime:probe", "rewritten rule text")
check("L3b rewriting a delivered key is refused, never framed a second time",
  ok_change == false and #wire == after_probe, tostring(ok_change) .. "/" .. tostring(#wire))

local RECEIPT_RULE = "receipt-gated rule"
local rejected = 0
world(8, "Joker", function(_, _, _, receipt)
  rejected = rejected + 1
  if receipt then receipt.status = "rejected" end
  return false
end)
local accepted = ContextDelivery.rule("lifetime:receipt", RECEIPT_RULE)
check("L4a a frame the bridge refused is not treated as delivered",
  accepted == false and rejected == 1 and #wire == after_probe,
  tostring(accepted) .. "/" .. tostring(rejected))
G.NEURO.send_context = record
ContextDelivery.step()
check("L4b the refused frame is retried and physically written exactly once",
  #wire == after_probe + 1 and wire[#wire].msg == RECEIPT_RULE, tostring(#wire))
ContextDelivery.rule("lifetime:receipt", RECEIPT_RULE)
check("L4c and once written it is committed, so it is never framed again",
  #wire == after_probe + 1, tostring(#wire))

local Metrics = require("util.metrics")

local function delivered_count()
  local n = 0
  for _ in pairs(ContextDelivery._delivered() or {}) do n = n + 1 end
  return n
end

local function delivered_has(text)
  for _, v in pairs(ContextDelivery._delivered() or {}) do
    if v == text then return true end
  end
  return false
end

local function counter(name) return Metrics._counters[name] or 0 end

do
  ContextDelivery.reset_transport()
  local before = counter("context_delivery_stale_receipt")
  local STALE = "frame written into the transport view that was replaced mid-loop"

  local held = nil
  world(8, "Joker", function(_, msg, _silent, receipt)
    if tostring(msg) == STALE then
      if receipt then receipt.status = "buffered" end
      held = receipt
      return true
    end
    if receipt then receipt.status = "rejected" end
    return false
  end)
  ContextDelivery.rule("lifetime:reconnector", "the entry whose send reconnects the transport")
  ContextDelivery.rule("lifetime:stale-epoch", STALE)
  check("L5a the fixture holds a receipt minted in the current epoch",
    held ~= nil and held.status == "buffered", tostring(held and held.status))

  held.status = "written" -- the transport really did write it, into the OLD view
  G.NEURO.send_context = function(_, _, _, receipt)
    ContextDelivery.reset_transport() -- the reconnect, inside the loop
    if receipt then receipt.status = "rejected" end
    return false
  end
  ContextDelivery.step()

  check("a receipt minted in the previous epoch cannot commit into the new one",
    not delivered_has(STALE), "delivered=" .. tostring(delivered_count()))
  check("L5b and the stale commit is counted, not silently dropped",
    counter("context_delivery_stale_receipt") == before + 1,
    tostring(counter("context_delivery_stale_receipt") - before))
end

do
  ContextDelivery.reset_transport()
  world(8, "Joker", record)
  for _ = 1, 5 do ContextDelivery.step() end
  local before = counter("context_delivery_abandoned")
  local attempts = 0
  world(8, "Joker", function(_, _, _, receipt)
    attempts = attempts + 1
    if receipt then receipt.status = "rejected" end
    return false
  end)
  ContextDelivery.rule("lifetime:never-accepted", "a frame the bridge always refuses")
  local CAP = 200
  for _ = 1, CAP do ContextDelivery.step() end
  check("a frame the bridge never accepts is abandoned instead of retried forever",
    attempts < CAP, attempts .. " attempts in " .. CAP .. " frames")
  check("L6b and its abandonment is counted",
    counter("context_delivery_abandoned") == before + 1,
    tostring(counter("context_delivery_abandoned") - before))
  local settled = attempts
  for _ = 1, 20 do ContextDelivery.step() end
  check("L6c after which the entry is gone from pending, not merely quiet",
    attempts == settled, attempts .. " vs " .. settled)
end

do
  ContextDelivery.reset_transport()
  world(8, "Joker", record)
  local BATCH = 600
  for i = 1, BATCH do ContextDelivery.event("lifetime:ev:" .. i, "event " .. i) end
  local after_first = delivered_count()
  for i = BATCH + 1, BATCH * 2 do ContextDelivery.event("lifetime:ev:" .. i, "event " .. i) end
  local after_second = delivered_count()
  check("transient identity memory saturates instead of growing with the stream",
    after_second == after_first and after_second < BATCH * 2,
    after_first .. " then " .. after_second .. " for " .. (BATCH * 2) .. " events")
  check("L7b it is the OLDEST identities that are dropped, so a recent one is still deduplicated",
    not delivered_has("event 1") and delivered_has("event " .. (BATCH * 2)),
    "oldest kept: " .. tostring(delivered_has("event 1")))
  ContextDelivery.rule("lifetime:durable-rule", "a rule that must outlive the event stream")
  for i = BATCH * 2 + 1, BATCH * 3 do ContextDelivery.event("lifetime:ev:" .. i, "event " .. i) end
  check("L7c and a rule is never evicted by the event stream it shares the store with",
    delivered_has("a rule that must outlive the event stream"), "rule evicted")
end

do
  ContextDelivery.reset_transport()
  local CARRIED = "a rule the old transport never accepted"
  world(8, "Joker", record)
  ContextDelivery.rule("lifetime:carry-delivered", "already on the old wire")
  local delivered_before = delivered_count()
  G.NEURO.send_context = function(_, _, _, receipt)
    if receipt then receipt.status = "rejected" end
    return false
  end
  ContextDelivery.rule("lifetime:carry-pending", CARRIED)
  check("L8a the fixture really has one delivered and one undelivered entry",
    delivered_before == 1 and not delivered_has(CARRIED), tostring(delivered_before))

  ContextDelivery.reset_transport()
  check("L8b reset_transport clears the delivered view for the new SDK-side transport",
    delivered_count() == 0, tostring(delivered_count()))

  local written = {}
  G.NEURO.send_context = function(_, msg, _silent, receipt)
    written[#written + 1] = tostring(msg)
    if receipt then receipt.status = "written" end
    return true
  end
  ContextDelivery.step()
  check("L8c and carries the never-written entry into it instead of abandoning it",
    written[1] == CARRIED and delivered_has(CARRIED), table.concat(written, " | "))
end

done()
