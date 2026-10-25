local H = require("tests.hand_pipeline_harness")
local Registry = require("core.action_registry")
local check, done = require("tests.helpers").harness("result-offer-references")

local function stray_calls()
  local registered, out = {}, {}
  for _, f in ipairs(H.frames()) do
    local d = f.data or {}
    if f.command == "startup" then
      registered = {}
    elseif f.command == "actions/register" then
      for _, a in ipairs(d.actions or {}) do registered[a.name] = true end
    elseif f.command == "actions/unregister" then
      for _, name in ipairs(d.action_names or {}) do registered[name] = nil end
    elseif f.command == "action/result" then
      local text = tostring(d.message or "")
      for _, name in ipairs(Registry.names()) do
        for _, lead in ipairs({ "currently offered " .. name, "Use the " .. name .. " action", "use " .. name .. " now" }) do
          if text:find(lead, 1, true) and not registered[name] then
            out[#out + 1] = tostring(d.id) .. ": " .. lead
          end
        end
      end
    end
  end
  return out
end

H.board({ confirm_hand = true })
check("fixture: the hand screen is forced", H.wait_force(), H.phase())
for round = 1, 2 do
  local play = H.send("play_hand", { indices = { 1 } })
  check(round .. ": the play opens its review", H.wait_force() and (H.result_for(play) or {}).success == true, H.phase())
  check(round .. ": whose force offers resolve_play", table.concat(G.NEURO.force_window.names, ",") == "resolve_play",
    table.concat(G.NEURO.force_window.names, ","))
  H.send("resolve_play", { answer = "yes" })
  check(round .. ": the confirmed play hands back the decision", H.wait_force(), H.phase())
end

local stray = stray_calls()
check("no result calls an unregistered action usable now", #stray == 0, table.concat(stray, " | "))
H.finish(check, done)
