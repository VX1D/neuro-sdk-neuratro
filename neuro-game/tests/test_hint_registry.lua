_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("hint-registry")
local H = require("tests.helpers")
local Registry = require("facts.hint_registry")
local FactHints = require("facts.fact_hints")

do
  local faults = Registry.validate()
  check("the registry validates clean", #faults == 0, table.concat(faults, " | "))
end

do
  local ok = true
  local detail = ""
  for _, e in ipairs(Registry.entries()) do
    if e.channel ~= nil then
      ok = false
      detail = detail .. " [" .. tostring(e.tag) .. " carries an explicit channel field]"
    end
    local expect = (e.claim == "state") and "query" or "context"
    if Registry.channel_of(e) ~= expect then
      ok = false
      detail = detail .. string.format(" [%s: claim %s routed to %s]", tostring(e.tag),
        tostring(e.claim), tostring(Registry.channel_of(e)))
    end
  end
  check("claim alone decides the channel", ok, detail)
end

do
  local BAD = {
    { tag = "x_query_run", claim = "state", cadence = "run" },
    { tag = "x_ctx_decision", claim = "rule", cadence = "decision" },
    { tag = "x_durable_no_retract", claim = "durable", cadence = "round" },
    { tag = "x_unknown_claim", claim = "advice", cadence = "round" },
  }
  local caught = 0
  for _, bad in ipairs(BAD) do
    local entries = Registry.entries()
    entries[#entries + 1] = bad
    if #Registry.validate() > 0 then caught = caught + 1 end
    entries[#entries] = nil
  end
  check("validate rejects every cadence/claim combination the channels cannot carry",
    caught == #BAD, tostring(caught) .. "/" .. tostring(#BAD))
end

do
  check("R4a removed retraction tags do not resolve",
    Registry.lookup("sh_rules_retire_discard") == nil)
  check("R4b a content-signature tag resolves to its stem",
    (Registry.lookup("voucher_chain:v_hone,v_glow_up") or {}).tag == "voucher_chain:")
  check("R4c a tag that matches nothing resolves to nothing",
    Registry.lookup("bp_chai") == nil and Registry.lookup("no_such_hint") == nil)
end

do
  _G.G = { NEURO = { once_serials = {}, state_enter_serial = 1, decision_serial = 1 } }
  local ok = pcall(FactHints.emit, "totally_unregistered_tag", "text")
  check("emitting an unregistered tag fails loudly under test", not ok)
end

do
  _G.G = { NEURO = { once_serials = {}, session_once_serials = {}, state_enter_serial = 1,
    decision_serial = 1 }, GAME = { round = 1 } }
  FactHints.reset_pending()
  local state_text = FactHints.emit("pack_cons", "STATE CLAIM TEXT ")
  check("R6a a state claim is handed back to the builder for its query",
    state_text == "STATE CLAIM TEXT ", string.format("%q", state_text))
  check("R6b and it is not also queued for the permanent channel",
    not FactHints.hint_is_pending("pack_cons"))

  local rule_text = FactHints.emit("voucher_basics_run", "RULE TEXT ")
  check("R6c a rule hands the builder nothing", rule_text == "", string.format("%q", rule_text))
  check("R6d and is queued for the permanent channel instead",
    FactHints.hint_is_pending("voucher_basics_run"))
end

do
  _G.G = { NEURO = { once_serials = {}, session_once_serials = {}, state_enter_serial = 1,
    decision_serial = 1 }, GAME = { round = 4 } }
  FactHints.reset_pending()
  local a = FactHints.emit("pack_cons", "text ")
  local b = FactHints.emit("blind_select_advice", "text ")
  local keys = {}
  for k in pairs(G.NEURO.once_serials) do keys[#keys + 1] = k end
  table.sort(keys)
  local joined = table.concat(keys, " | ")
  check("R7a always state claims are returned on every build", a == "text " and b == "text ")
  check("R7b always state claims reserve no permanent-memory gate", joined == "", joined)
end

do
  local sources = {}
  for _, dir in ipairs({ "context", "facts", "force", "handlers", "core" }) do
    local pipe = io.popen("ls " .. dir .. "/*.lua 2>/dev/null")
    if pipe then
      for path in pipe:lines() do
        local fh = io.open(path, "r")
        if fh then sources[#sources + 1] = fh:read("*a"); fh:close() end
      end
      pipe:close()
    end
  end
  local blob = H.strip_lua_comments and H.strip_lua_comments(table.concat(sources, "\n"))
    or table.concat(sources, "\n")
  local dead = {}
  for _, e in ipairs(Registry.entries()) do
    if not blob:find('"' .. e.tag, 1, true) then dead[#dead + 1] = e.tag end
  end
  check("every registered tag is emitted somewhere in the tree", #dead == 0,
    table.concat(dead, ", "))
end

do
  local function read(path)
    local f = io.open(path, "rb"); if not f then return nil end
    local body = f:read("*a"); f:close(); return body
  end
  local orphans, misfiled = {}, {}
  for _, entry in ipairs(Registry.entries()) do
    local tag = tostring(entry.tag)
    local owner_body = read(entry.owner)
    if not owner_body then
      misfiled[#misfiled + 1] = tag .. " -> missing owner file " .. tostring(entry.owner)
    else
      local literal = '"' .. tag
      if not owner_body:find(literal, 1, true) then
        local stem = tag:gsub(":$", "")
        if not owner_body:find('"' .. stem, 1, true) then
          orphans[#orphans + 1] = tag .. " (declared owner " .. entry.owner .. ")"
        end
      end
    end
  end
  check("every registry entry is produced by the file it names as owner",
    #orphans == 0, table.concat(orphans, ", "))
  check("every declared owner file exists", #misfiled == 0, table.concat(misfiled, ", "))
end

done()
