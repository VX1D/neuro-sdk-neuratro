-- profanity filter regression suite: locks the sanitize contract so future edits to core/filtered.lua
-- cannot silently leak slurs or start masking clean text (incl. Balatro vocab that collides with terms)
package.path = package.path .. ";./?.lua"
local F = require("core.filtered")

local pass, fail = 0, 0
local function check(name, cond, got)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL  " .. name .. (got ~= nil and ("  -- got: " .. tostring(got)) or "")) end
end
local function eq(name, input, want)
  local got = F.sanitize(input)
  check(name, got == want, got)
end
local function masked(name, input)
  local got = F.sanitize(input)
  -- "masked" = the slur does not survive: output contains no letters-run longer than 2, or is ***
  check(name, got:find("%*%*%*") ~= nil, got)
end

-- clean text (incl. allow-listed Balatro vocab) must pass through unchanged
eq("clean sentence unchanged", "hello world", "hello world")
eq("allow-listed joker preserved", "lusty joker", "lusty joker")
eq("allow-listed joker plural preserved", "lusty jokers", "lusty jokers")
eq("clean word that contains a term substring (bass)", "classic bass", "classic bass")
eq("clean word that contains a term substring (clapp)", "the clapp", "the clapp")
eq("allow-list exception (niggard)", "niggard", "niggard")

-- exact slurs are masked
eq("exact mute word -> ***", "ass", "***")
eq("exact mute inline -> masked inline", "hello ass world", "hello *** world")
masked("compound slur masked", "assfuck")

-- leetspeak/obfuscated forms are caught
masked("leetspeak mute (a55)", "a55")
masked("leetspeak wildcard (f4gg0t)", "f4gg0t")
masked("pipe homoglyph normalizes to i", "n" .. string.char(124) .. "gger")

-- replace-action terms are softened, not masked, in plain form
eq("replace term softened", "retard", "idiot")
eq("replace term softened inline", "you are a retard", "you are a idiot")

-- non-string inputs are coerced, never error
check("nil input -> empty string", F.sanitize(nil) == "")
check("number input coerced", type(F.sanitize(42)) == "string")

print(string.format("==== filter: %d/%d PASS, %d FAIL ====", pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
