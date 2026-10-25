require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("wire-markdown")
local FW = require("tests.force_wire")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local SectionRows = require("tests.force_section_rows")
local Protocol = require("core.bridge").wire

FW.attach()

local texts = {}
local seen_context = {}
local function add(kind, label, text)
  texts[#texts + 1] = { kind = kind, label = label, text = text }
end

for _, board in ipairs(SectionRows.ALL_BOARDS) do
  LB.load(board.state, board.desc)
  local label = board.state .. "/" .. board.desc
  rawset(G.NEURO, "send_context", nil)
  setmetatable(G.NEURO, { __newindex = function(t, k, v)
    if k == "send_context" then
      v = function(_, message, silent)
        local frame = Protocol.context(message, silent == true)
        local wire = frame and frame.data.message
        if wire and not seen_context[wire] then
          seen_context[wire] = true
          add("context", label, wire)
        end
        return true
      end
    end
    rawset(t, k, v)
  end })
  local payload = FP.build(board.state)
  if payload and payload.wire then
    add("state", label, payload.wire.state)
    add("query", label, payload.wire.query)
  end
end
local guide = Protocol.context(require("facts.token_legends").ACTION_SEMANTICS_V1.text, true)
add("context", "action guide", guide.data.message)

local counts = {}
for _, t in ipairs(texts) do counts[t.kind] = (counts[t.kind] or 0) + 1 end
check("the corpus covers every channel",
  (counts.state or 0) >= 18 and (counts.query or 0) >= 18 and (counts.context or 0) >= 5,
  string.format("state=%s query=%s context=%s", tostring(counts.state), tostring(counts.query),
    tostring(counts.context)))

local function scan(rule, kinds)
  local hits = {}
  for _, t in ipairs(texts) do
    if kinds[t.kind] then
      local hit = rule(t.text)
      if hit then hits[#hits + 1] = t.kind .. " " .. t.label .. ": " .. hit end
    end
  end
  return hits
end
local ALL = { state = true, query = true, context = true }

local function engine_area_spelling(text)
  local at = text:find("consumeables", 1, true)
  return at and text:sub(math.max(1, at - 40), at + 20) or nil
end
local hits = scan(engine_area_spelling, ALL)
check("no channel spells the area the engine's way", #hits == 0, table.concat(hits, " | "))

local function trailing_space(text)
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if line:find("[ \t]$") then return "[" .. line:sub(-50) .. "]" end
  end
  return nil
end
hits = scan(trailing_space, ALL)
check("no line ends in whitespace", #hits == 0, table.concat(hits, " | "))

local function packed_list(text)
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local _, items = line:gsub("[%w ]+: [^;]+;", "")
    if items >= 3 then return "[" .. line:sub(1, 80) .. "]" end
  end
  return nil
end
hits = scan(packed_list, { context = true, state = true })
check("neither context nor state packs a list of labelled values into one line", #hits == 0,
  table.concat(hits, " | "))

local function packed_label(text)
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if line:find("^[-%s]*Legality:") or line:find("^[-%s]*History:") then return "[" .. line:sub(1, 60) .. "]" end
  end
  return nil
end
hits = scan(packed_label, { state = true })
check("state carries no semicolon-packed Legality or History line", #hits == 0, table.concat(hits, " | "))

local function loose_state(text)
  if not text:find("^## ") then return "does not open with a ## section [" .. text:sub(1, 40) .. "]" end
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if line:find("^#%s") or line:find("^#[^#]") then return "top-level heading [" .. line:sub(1, 40) .. "]" end
    if not (line:find("^## %S") or line:find("^%- %S") or line:find("^%d+%. %S") or line:find("^  %S")) then
      return "line outside the list structure [" .. line:sub(1, 60) .. "]"
    end
  end
  return nil
end
hits = scan(loose_state, { state = true })
check("every state opens with a ## section, has no top-level heading, and every line is a heading or an item",
  #hits == 0, table.concat(hits, " | "))

local function marked_query(text)
  if text:find("State: ", 1, true) then return "internal 'State: ' label" end
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if line:find("^%s*#") then return "heading [" .. line:sub(1, 40) .. "]" end
    if line:find("^%s*[-*+] ") or line:find("^%s*%d+[.)] ") then return "list line [" .. line:sub(1, 40) .. "]" end
  end
  if text:find("`", 1, true) then return "code span" end
  return nil
end
hits = scan(marked_query, { query = true })
check("no query carries the State label, a heading, a list line or a code span", #hits == 0,
  table.concat(hits, " | "))

local HAND_FINDINGS = { "Shape: ", "Ready to play now: ", "One card away: " }
local function packed_findings(text)
  local findings = 0
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local on_line = 0
    for _, label in ipairs(HAND_FINDINGS) do
      if line:find(label, 1, true) then
        on_line = on_line + 1
        if not line:find("^%- " .. label:gsub("%p", "%%%0")) then return "[" .. line:sub(1, 60) .. "]" end
      end
    end
    if on_line > 1 then return "[" .. line:sub(1, 60) .. "]" end
    findings = findings + on_line
  end
  return nil, findings
end
local listed = 0
hits = {}
for _, t in ipairs(texts) do
  if t.kind == "state" then
    local hit, n = packed_findings(t.text)
    if hit then hits[#hits + 1] = t.label .. ": " .. hit end
    listed = listed + (n or 0)
  end
end
check("each hand finding in state is its own list item", #hits == 0 and listed >= 6,
  table.concat(hits, " | ") .. " listed=" .. listed)

local QUERY_LINE_MAX = 800
local function run_on_query(text)
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if #line > QUERY_LINE_MAX then return #line .. " chars [" .. line:sub(1, 50) .. "]" end
    if line:find("; Use the ", 1, true) or line:find(" or Use the ", 1, true) then
      return "moves share a line [" .. line:sub(1, 50) .. "]"
    end
  end
  return nil
end
hits = scan(run_on_query, { query = true })
check("query moves sit one per line and no query line runs past " .. QUERY_LINE_MAX, #hits == 0,
  table.concat(hits, " | "))

local function index_before_quote(text)
  local at = text:find('index %d+, name "')
  return at and text:sub(at, at + 40) or nil
end
hits = scan(index_before_quote, { query = true })
check("no example puts a quoted name straight after a bare index", #hits == 0, table.concat(hits, " | "))

local function payload_word(text)
  local at = text:lower():find("payload", 1, true)
  return at and text:sub(math.max(1, at - 50), at + 20) or nil
end
hits = scan(payload_word, { state = true, query = true })
check("no force state or query mentions a payload", #hits == 0, table.concat(hits, " | "))

done()
