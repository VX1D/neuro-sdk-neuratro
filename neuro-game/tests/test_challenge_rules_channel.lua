require("tests.stubs").setup({ love = "lazy", G = "board" })

local LABEL = "challenge-rules-channel"
local LOST_IF_SKIPPED = 16
local skip = require("tests.skip_ledger")
local check, done = require("tests.helpers").harness(LABEL)

local DUMP = os.getenv("BALATRO_DUMP")
if not DUMP or DUMP == "" then skip.bail(LABEL, LOST_IF_SKIPPED, "BALATRO_DUMP is unset") end
local read = require("tests.helpers").read_file
local game_src, misc_src = read(DUMP .. "/game.lua"), read(DUMP .. "/functions/misc_functions.lua")
if not (game_src and misc_src) then skip.bail(LABEL, LOST_IF_SKIPPED, "game dump unreadable at " .. DUMP) end

local exe = os.getenv("BALATRO_EXE")
if not exe or exe == "" then
  local steamapps = DUMP:match("^(.*/steamapps)/compatdata/")
  exe = steamapps and (steamapps .. "/common/Balatro/Balatro.exe") or nil
end
local function from_exe(path)
  if not (exe and read(exe) ~= nil and not exe:find("'", 1, true)) then return nil end
  local pipe = io.popen("unzip -p '" .. exe .. "' " .. path .. " 2>/dev/null")
  local src = pipe and pipe:read("*a")
  if pipe then pipe:close() end
  return src ~= "" and src or nil
end
local loc_src, challenges_src = from_exe("localization/en-us.lua"), from_exe("challenges.lua")
if not (loc_src and challenges_src) then
  skip.bail(LABEL, LOST_IF_SKIPPED, "game localization or challenges unreadable; set BALATRO_EXE to Balatro.exe")
end
local LOC = assert((loadstring or load)(loc_src))()

local localize_src = misc_src:match("\nfunction localize%(args, misc_cat%).-\nend\n")
assert(localize_src, "the dump's localize() was not found")
local real_localize = assert((loadstring or load)(localize_src .. "\nreturn localize"))()
local function proto(field)
  local body = game_src:match("self%." .. field .. "%s*=%s*(%b{})")
  assert(body, field .. " not found in the dump")
  return assert((loadstring or load)("local HEX = function(s) return s end "
    .. "local localize = function() return '' end return " .. body))()
end

_G.localize = real_localize
G.localization = LOC
for _, f in ipairs({ "P_CENTERS", "P_TAGS", "P_BLINDS" }) do
  G[f] = proto(f)
  for k, v in pairs(G[f]) do if type(v) == "table" then v.key = v.key or k end end
end
assert((loadstring or load)(challenges_src))()
local CHALLENGES = G.CHALLENGES

local GameRules = require("context.game_rules")
local ContextCompact = require("context.context_compact")
local DisplayNames = require("facts.display_names")

local function by_id(id)
  for _, ch in ipairs(CHALLENGES) do if ch.id == id then return ch end end
end

local function screen_text(key, value)
  local raw = LOC.misc.v_text[key]
  local line = table.concat(raw, " "):gsub("#1#", function() return tostring(value) end)
  return (line:gsub("{[^{}]*}", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function enter_run(ch)
  G.STAGES = { RUN = 2 }
  G.STAGE = G.STAGES.RUN
  G.GAME = { challenge = ch.id, challenge_tab = ch, modifiers = {}, current_round = {}, round_resets = { ante = 1 },
    dollars = 4, hands = {} }
end

local function rule_frame()
  for _, frame in ipairs(ContextCompact.rule_frames()) do
    if tostring(frame.key):find("^challenge:") then return frame end
  end
end

for _, id in ipairs({ "c_omelette_1", "c_xray_1", "c_golden_needle_1", "c_fragile_1" }) do
  local ch = assert(by_id(id), id)
  enter_run(ch)
  local name = LOC.misc.challenge_names[id]
  local frame = rule_frame()
  local text = frame and frame.text or ""
  local missing = {}
  local function expect(piece) if not text:find(piece, 1, true) then missing[#missing + 1] = piece end end
  expect(name)
  for _, rule in ipairs(ch.rules.custom) do expect(screen_text("ch_c_" .. rule.id, rule.value)) end
  for _, mod in ipairs(ch.rules.modifiers) do expect(screen_text("ch_m_" .. mod.id, mod.value)) end
  for _, banned in ipairs(ch.restrictions.banned_cards) do expect(DisplayNames.center(banned.id)) end
  for _, banned in ipairs(ch.restrictions.banned_tags) do expect(DisplayNames.tag(banned.id)) end
  for _, banned in ipairs(ch.restrictions.banned_other) do expect(DisplayNames.blind(banned.id)) end
  check(id .. ": one rule context names the challenge and every rule its screen shows",
    frame ~= nil and #missing == 0, frame and table.concat(missing, " | ") or "no challenge rule frame")
  check(id .. ": the rule context is keyed by the challenge, so it is sent once per challenge",
    frame and frame.key == "challenge:" .. id, frame and frame.key)
  check(id .. ": no raw key reaches the text", not text:find("[%l]+_[%l%d_]+"), text)

  local state = GameRules.run_frame_text("SELECTING_HAND") or ""
  local absent = {}
  if not state:find(name, 1, true) then absent[#absent + 1] = name end
  for _, rule in ipairs(ch.rules.custom) do
    local piece = screen_text("ch_c_" .. rule.id, rule.value)
    if not state:find(piece, 1, true) then absent[#absent + 1] = piece end
  end
  check(id .. ": the force state names the challenge and its custom rules", #absent == 0,
    table.concat(absent, " | ") .. " || " .. state)
end

do
  local ch = by_id("c_xray_1")
  enter_run(ch)
  G.GAME.challenge_tab = { name = "ERROR" }
  local frame = rule_frame()
  check("a run restored from a save still names its challenge",
    frame ~= nil and frame.text:find(LOC.misc.challenge_names.c_xray_1, 1, true) ~= nil, frame and frame.text)
end

do
  local ch = by_id("c_golden_needle_1")
  enter_run(ch)
  local sent = {}
  G.NEURO = { send_context = function(_, text, silent, receipt)
    if receipt then receipt.status = "written" end
    sent[#sent + 1] = { text = text, silent = silent }
    return true
  end }
  require("core.context_delivery").reset_transport()
  require("core.window").emit_rules("BLIND_SELECT")
  require("core.context_delivery").step()
  local delivered
  for _, frame in ipairs(sent) do
    if frame.text:find(LOC.misc.challenge_names.c_golden_needle_1, 1, true)
        and frame.text:find(screen_text("ch_c_discard_cost", 1), 1, true) then delivered = frame end
  end
  check("the challenge rules are delivered as a silent context at run start",
    delivered ~= nil and delivered.silent == true, #sent .. " contexts sent")
  local before = #sent
  require("core.window").emit_rules("SHOP")
  require("core.context_delivery").step()
  local again = 0
  for i = before + 1, #sent do
    if sent[i].text:find(LOC.misc.challenge_names.c_golden_needle_1, 1, true) then again = again + 1 end
  end
  check("and not repeated on the next decision", again == 0, again)
end

do
  G.GAME = { modifiers = {}, current_round = {}, round_resets = { ante = 1 }, dollars = 4, hands = {} }
  check("a normal run has no challenge rule frame", rule_frame() == nil)
  check("and its state names no challenge",
    not (GameRules.run_frame_text("SELECTING_HAND") or ""):find("Challenge", 1, true))
end

do
  local loc, list = G.localization, G.CHALLENGES
  require("tests.fixtures.live_board").load("SELECTING_HAND", "Normal: 5 cards, 4 hands, 3 discards")
  G.localization, G.CHALLENGES = loc, list
  G.GAME.challenge = "c_xray_1"
  G.STAGES = G.STAGES or { RUN = 2 }
  G.STAGE = G.STAGES.RUN
  local state = require("core.window").build_payload("SELECTING_HAND", { actions = { "play_hand", "discard_hand" } }) or ""
  check("the force state of a challenge run carries its custom rule",
    state:find("Challenge: " .. LOC.misc.challenge_names.c_xray_1 .. " -- "
      .. screen_text("ch_c_flipped_cards", 4), 1, true) ~= nil, state:sub(1, 400))
end

done()
