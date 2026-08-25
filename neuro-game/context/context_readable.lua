local ContextReadable = {}

local ContextCompact = require("context.context_compact")
local CtxHelpers = require("context.ctx_helpers")

local SUPPORTED = {
  SELECTING_HAND = true, SHOP = true, BLIND_SELECT = true, ROUND_EVAL = true,
  TAROT_PACK = true, PLANET_PACK = true, SPECTRAL_PACK = true, STANDARD_PACK = true,
  BUFFOON_PACK = true, SMODS_BOOSTER_OPENED = true,
  MENU = true, RUN_SETUP = true, GAME_OVER = true, SPLASH = true,
}
ContextReadable.SUPPORTED = SUPPORTED

local VALUE_LONG = CtxHelpers.VALUE_LONG

local function v_FRAME(line) local t = line:gsub("^FRAME|", ""); return (t ~= "" and t) or nil end
local function v_RUN(line) local t = line:gsub("^RUN|", ""); return (t ~= "" and t) or nil end

local HANDLERS = {
  FRAME = v_FRAME, RUN = v_RUN,
  STATE = function() return nil end,
}

local function line_id(line)
  if line:find("^STATE:") then return "STATE" end
  return line:match("^([A-Z][A-Z_0-9]*)[:|%[%(]")
end

local function process_lines(board, out)
  for line in (board .. "\n"):gmatch("([^\n]*)\n") do
    if line ~= "" then
      local id = line_id(line)
      local h = id and HANDLERS[id]
      if h then
        local s = h(line)
        if s and s ~= "" then out[#out + 1] = s end
      else
        out[#out + 1] = line
      end
    end
  end
end

local function verbalize(board)
  local out = {}
  process_lines(board, out)
  return table.concat(out, "\n")
end

local function verbalize_sections(list)
  local out = {}
  for _, section in ipairs(list) do
    if section and section ~= "" then process_lines(section, out) end
  end
  return table.concat(out, "\n")
end

function ContextReadable.structure_prose(s)
  if type(s) ~= "string" or s == "" then return s end
  s = s:gsub("Structure: pairs>=2:(%d+) trips>=3:(%d+) quads>=4:(%d+) top:(%S+) suit_max:(%d+) run_max:(%d+)%.",
    function(p, t, q, top, sm, rm)
      local topw = (top == "-" and "none") or (VALUE_LONG[top] or top)
      return string.format(
        "Shape: %s pair or better, %s three-of-a-kind or better, %s four-of-a-kind; highest repeated rank %s; most cards of one suit %s; longest run %s.",
        p, t, q, topw, sm, rm)
    end)
  s = s:gsub("%(lv([%d%.]+) ([%d%.e%+]+)c x([%d%.e%+]+)%)", "(level %1, %2 chips x%3 mult)")
  s = s:gsub("%(J([%dJ,]+) appl%a+%)", function(js)
    local nums = js:gsub("J", ""):gsub(",", ", ")
    local verb = js:find(",", 1, true) and "apply" or "applies"
    return "(joker " .. nums .. " " .. verb .. ")"
  end)
  s = s:gsub("%(J([%dJ,]+) ([%+x][%d%.%+cmx ]*)%)", function(js, vals)
    local nums = js:gsub("J", ""):gsub(",", ", ")
    local parts = {}
    for v in vals:gmatch("%S+") do
      if v:find("^%+") and v:find("c$") then parts[#parts + 1] = v:gsub("c$", " chips")
      elseif v:find("^%+") and v:find("m$") then parts[#parts + 1] = v:gsub("m$", " mult")
      elseif v:find("^x") then parts[#parts + 1] = v .. " mult"
      else parts[#parts + 1] = v end
    end
    return "(joker " .. nums .. " adds " .. table.concat(parts, " ") .. ")"
  end)
  s = s:gsub("%(jokers: ([%+x][%d%.%+cmx ]*)%)", function(vals)
    local parts = {}
    for v in vals:gmatch("%S+") do
      if v:find("^%+") and v:find("c$") then parts[#parts + 1] = v:gsub("c$", " chips")
      elseif v:find("^%+") and v:find("m$") then parts[#parts + 1] = v:gsub("m$", " mult")
      elseif v:find("^x") then parts[#parts + 1] = v .. " mult"
      else parts[#parts + 1] = v end
    end
    return "(your jokers add " .. table.concat(parts, " ") .. ")"
  end)
  s = s:gsub("%(draw (%d+)/(%d+)=(%d+)%%%)",
    "(%1 of the %2 draw-pile cards complete it; %3%% chance to hit one if you discard the others listed)")
  s = s:gsub("%(discard at most (%d+)%)", " (you may discard at most %1 of them)")
  s = s:gsub("keep%[([%d,]+)%]/other%[([%d,]+)%]", function(k, o)
    return "keep cards " .. k:gsub(",", ", ") .. ", the others are " .. o:gsub(",", ", ")
  end)
  s = s:gsub("keep%[([%d,]+)%]", function(k) return "keep cards " .. k:gsub(",", ", ") end)
  s = s:gsub("%[([%d,]+)%]", function(list) return " (cards " .. (list:gsub(",", ", ")) .. ")" end)
  s = s:gsub("%((%d+) debuffed~0%)", "(%1 debuffed, score 0)")
  s = s:gsub("%(all debuffed~0%)", "(all debuffed, score 0)")
  s = s:gsub("%(play (%d+)%+ cards%)", "(this boss needs %1+ cards played - add spare cards)")
  s = s:gsub("%(open draw%)", "(completes on either end)")
  s = s:gsub("%(inside draw%)", "(needs one exact rank)")
  s = s:gsub("Ready:", "Ready to play now:")
  s = s:gsub("Close: near ", "One card away: ")
  s = s:gsub("; near ", "; ")
  s = s:gsub("%)%(", ") (")
  s = s:gsub("(%d)%(", "%1 (")
  return s
end

function ContextReadable.build(state_name, allowed_actions)
  if not SUPPORTED[state_name] then return nil end
  local ok, sections = pcall(ContextCompact.build, state_name, allowed_actions, { split = "state", no_cache = true, return_list = true })
  if not ok or type(sections) ~= "table" or #sections == 0 then return nil end
  local prose = verbalize_sections(sections)
  if prose == "" then return nil end
  return prose
end

function ContextReadable.verbalize_stable(board)
  if type(board) ~= "string" or board == "" then return board end
  local ok, prose = pcall(verbalize, board)
  return (ok and prose ~= "" and prose) or board
end

if _G.NEURO_TEST then
  ContextReadable._verbalize = verbalize
end

return ContextReadable
