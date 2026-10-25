local H = require("tests.hand_pipeline_harness")
local check, done = require("tests.helpers").harness("play-rules-channel")

local RULES = {
  "The cards listed on a Ready hand are the exact cards that form it",
  "First check the chips remaining to clear the blind",
  "Judge each hand's value YOURSELF from its level and base values",
  "a discard toward a one-card-away hand can upgrade it",
  "winning in fewer hands pays more at cash-out",
}

local function has(text, needle) return tostring(text):find(needle, 1, true) ~= nil end

local function offers(frame, name)
  for _, n in ipairs(H.names_of(frame)) do if n == name then return true end end
  return false
end

H.board({ discards = 3 })
H.tick(8)

local frames = H.frames()
local force_at, force
for i, f in ipairs(frames) do
  if f.command == "actions/force" and offers(f, "play_hand") then force_at, force = i, f.data break end
end
check("a hand decision is forced", force ~= nil, tostring(#frames))

local context = {}
for i = 1, (force_at or #frames) do
  if frames[i].command == "context" then context[#context + 1] = frames[i].data.message end
end
local delivered = table.concat(context, "\n\n")
for _, rule in ipairs(RULES) do
  check("context delivers before the hand decision: " .. rule, has(delivered, rule))
end

local query = force and force.query or ""
check("the hand query carries no Rules block", not has(query, "Rules:"), query)
for _, rule in ipairs(RULES) do
  check("the hand query does not repeat: " .. rule, not has(query:lower(), rule:lower()), query)
end
check("the hand query restates no registered schema fields",
  not has(query, "with required") and not has(query, "plus optional"), query)

H.finish(check, done)
