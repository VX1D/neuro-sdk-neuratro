_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local GATE = os.getenv("FAIL_ON_FINDINGS") == "1"
local OUT = (arg and arg[1])
  or (GATE and (require("tests.tmp_workdir").open("context_dump") .. "/context_dump.txt"))
  or "tests/context_dump.txt"

local CONTEXT_CHANNELS = { GLOSS = true, ["STABLE(FRAME/RUN/V/JD)"] = true, BOARD = true }
local function gated(a, b) return CONTEXT_CHANNELS[a] and CONTEXT_CHANNELS[b] end

local A = require("core.actions")
local D = require("core.dispatcher")
local TokenLegends = require("facts.token_legends")
local ContextCompact = require("context.context_compact")
local ContextReadable = require("context.context_readable")
G.NEURO.dispatcher = D
G.NEURO.actions = A
local TD = require("tests.test_deadlock")

local MOCK_RESET = {
  "GAME", "hand", "jokers", "consumeables", "deck", "playing_cards",
  "shop_jokers", "shop_vouchers", "shop_booster", "shop",
  "pack_cards", "booster_pack", "blind_select_opts", "blind_select",
  "OVERLAY_MENU", "challenge_tab", "CHALLENGES",
  "STATES", "STATE", "TIMERS", "P_CENTER_POOLS", "P_TAGS", "P_BLINDS", "SETTINGS",
}
local NEURO_RESET = {
  "persona", "deck_chosen", "reserved_dollars", "shop_reroll_count",
  "blind_info_sig", "blind_info_seen", "state_entry_hints",
  "force_inflight", "force_state", "force_window", "force_sent_at",
  "last_failed_action", "last_failed_reason", "last_failed_at", "once_serials",
  "gameover_hold", "gameover_hold_until", "gameover_recovery", "gameover_exited_at",
}
local function reset_g()
  for _, k in ipairs(MOCK_RESET) do G[k] = nil end
  for _, k in ipairs(NEURO_RESET) do G.NEURO[k] = nil end
  G.GAME = { current_round = {} }
  G.NEURO.reserved_dollars = 0
  G.NEURO.shop_reroll_count = 0
  G.NEURO.state_enter_serial = (tonumber(G.NEURO.state_enter_serial) or 0) + 1000
end

local function channels(state)
  local acts = A.get_valid_actions_for_state(state)
  local ch = {}

  ch[#ch + 1] = { "GLOSS", TokenLegends.READABLE_COMMON }

  local ok_s, stable = pcall(ContextCompact.build, state, nil,
    { split = "stable", full_jokers = true, no_cache = true })
  if ok_s and stable and stable ~= "" then
    ok_s, stable = pcall(ContextReadable.verbalize_stable, stable)
  end
  ch[#ch + 1] = {
    "STABLE(FRAME/RUN/V/JD)",
    ok_s and ((stable and stable ~= "") and stable or "(none)") or ("ERROR: " .. tostring(stable)),
  }

  local ok_b, board = pcall(ContextReadable.build, state, acts)
  ch[#ch + 1] = {
    "BOARD",
    ok_b and ((board and board ~= "") and board or "(none)") or ("ERROR: " .. tostring(board)),
  }

  local ok_f, force = pcall(D.get_force_for_state, state)
  if not ok_f then
    ch[#ch + 1] = { "FORCE_QUERY", "ERROR: " .. tostring(force) }
    ch[#ch + 1] = { "ACTIONS", "(not generated)" }
  elseif type(force) == "table" then
    ch[#ch + 1] = { "FORCE_QUERY", force.query or "(none)" }
    ch[#ch + 1] = { "ACTIONS", table.concat(force.actions or {}, ", ") }
  else
    ch[#ch + 1] = { "FORCE_QUERY", "(none)" }
    ch[#ch + 1] = { "ACTIONS", "(none)" }
  end
  return ch
end

local STOP = { the = true, a = true, an = true, to = true, of = true, and_ = true, ["and"] = true,
  ["or"] = true, ["in"] = true, ["on"] = true, ["is"] = true, ["it"] = true, ["you"] = true,
  ["your"] = true, ["for"] = true, ["with"] = true, ["that"] = true, ["this"] = true, ["are"] = true }

local function words_of(s)
  local w = {}
  for tok in s:gmatch("%S+") do
    local n = tok:lower():gsub("[^%w]", "")
    if n ~= "" then w[#w + 1] = n end
  end
  return w
end

local K = 6
local function shingle_index(words)
  local idx = {}
  for i = 1, #words - K + 1 do
    local content = 0
    for j = i, i + K - 1 do if not STOP[words[j]] then content = content + 1 end end
    if content >= 3 then
      local key = table.concat(words, " ", i, i + K - 1)
      idx[key] = idx[key] or i
    end
  end
  return idx
end

local function shared_phrases(wa, ia, ib)
  local starts = {}
  for key, pos in pairs(ia) do if ib[key] then starts[#starts + 1] = pos end end
  table.sort(starts)
  local phrases, cur_lo, cur_hi = {}, nil, nil
  for _, p in ipairs(starts) do
    if cur_hi and p <= cur_hi + 1 then
      cur_hi = p
    else
      if cur_lo then phrases[#phrases + 1] = table.concat(wa, " ", cur_lo, cur_hi + K - 1) end
      cur_lo, cur_hi = p, p
    end
  end
  if cur_lo then phrases[#phrases + 1] = table.concat(wa, " ", cur_lo, cur_hi + K - 1) end
  return phrases
end

local CONCEPTS = {
  { "discard toward a stronger hand", { "discard.-toward.-strong", "discard.-stronger", "draw.-toward.-a.-strong", "discard.-low cards and draw" } },
  { "prioritize xMult / multiplying", { "xmult joker", "multiply.-score", "x multiplier", "won.t scale", "grab%-bag" } },
  { "only played cards score / no extras", { "only the cards forming", "extra.-do not score", "no extra or missing", "extras are dumped" } },
  { "unused-hand payout", { "unused hand", "pay out at cash", "unused hands pay" } },
  { "pack already paid for", { "already paid for", "picking a card costs nothing" } },
  { "blind targets rise per ante", { "targets rise", "rising blind" } },
  { "discards are a separate pool", { "separate pool", "costs no hand", "spends a discard, not a hand" } },
  { "close hand not guaranteed", { "not guaranteed", "lucky draw" } },
  { "debt floor / credit card", { "debt floor", "credit card", "spend down to %-" } },
  { "joker order / left-to-right", { "left%-to%-right", "joker order", "copies the joker to its right", "position%-sensitive", "order matters" } },
  { "creator card needs open output slot", { "creator", "creates? a joker", "create.-consumable", "open output slot", "ok=n" } },
}
local function covers(text, patterns)
  local low = text:lower()
  for _, p in ipairs(patterns) do if low:find(p) then return true end end
  return false
end

local function norm_sentence(s)
  return (s:lower():gsub("[^%w%s]", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end
local function sentences(s)
  local out = {}
  for seg in (s .. " "):gmatch("(.-[%.;])%s") do
    local n = norm_sentence(seg)
    if select(2, n:gsub("%S+", "")) >= 5 then out[#out + 1] = { raw = (seg:gsub("^%s+", "")), norm = n } end
  end
  return out
end

local lines = {}
local function w(s) lines[#lines + 1] = s or "" end

local findings, gated_findings, errors = 0, 0, 0
for scenario_index, sc in ipairs(TD.SCENARIOS) do
    reset_g()
    local ok, scenario_err = pcall(function()
      TD.apply_mock(sc.mock())
      if G.NEURO.persona == nil then G.NEURO.persona = "neuro" end

    end)
    w(("="):rep(96))
    w(string.format("SCENARIO %03d/%03d   STATE %s   (%s%s)",
      scenario_index, #TD.SCENARIOS, sc.state, sc.desc, sc.no_force and "; no force expected" or ""))
    w(("="):rep(96))
    if ok then
      local ch = channels(sc.state)
      local total = 0
      local wlists, sidx = {}, {}
      for i, c in ipairs(ch) do
        total = total + #c[2]
        w(string.format("---- %s  (%d chars) ----", c[1], #c[2]))
        w(c[2])
        w("")
        wlists[i] = words_of(c[2])
        sidx[i] = shingle_index(wlists[i])
      end
      w(string.format(">> total prompt size: %d chars across %d channels", total, #ch))

      w(">> REDUNDANCY -- phrases (>=6 words) shared across channels:")
      local any = false
      for i = 1, #ch do
        for j = i + 1, #ch do
          for _, ph in ipairs(shared_phrases(wlists[i], sidx[i], sidx[j])) do
            any = true; findings = findings + 1
            if gated(ch[i][1], ch[j][1]) then gated_findings = gated_findings + 1 end
            w(string.format("   [%s <-> %s]  \"%s\"", ch[i][1], ch[j][1], ph))
          end
        end
      end
      if not any then w("   (none)") end

      local seen, dup = {}, {}
      for i, c in ipairs(ch) do
        for _, se in ipairs(sentences(c[2])) do
          if seen[se.norm] and seen[se.norm] ~= c[1] then
            if gated(seen[se.norm], c[1]) then gated_findings = gated_findings + 1 end
            dup[#dup + 1] = string.format("   [%s | %s]  \"%s\"", seen[se.norm], c[1], se.raw)
          else
            seen[se.norm] = c[1]
          end
        end
      end
      if #dup > 0 then
        w(">> REDUNDANCY -- duplicate sentences across channels:")
        for _, d in ipairs(dup) do w(d); findings = findings + 1 end
      end

      w(">> REDUNDANCY -- concepts covered by >=2 channels (paraphrase overlap):")
      local anyc = false
      for _, con in ipairs(CONCEPTS) do
        local hit = {}
        for _, c in ipairs(ch) do if covers(c[2], con[2]) then hit[#hit + 1] = c[1] end end
        if #hit >= 2 then
          anyc = true; findings = findings + 1
          local g = 0
          for _, name in ipairs(hit) do if CONTEXT_CHANNELS[name] then g = g + 1 end end
          if g >= 2 then gated_findings = gated_findings + 1 end
          w(string.format("   %-38s in: %s", con[1], table.concat(hit, ", ")))
        end
      end
      if not anyc then w("   (none)") end
      w("")
    else
      errors = errors + 1
      w("---- SCENARIO_ERROR ----")
      w(tostring(scenario_err))
      w("")
    end
end

local fh = io.open(OUT, "w")
fh:write(table.concat(lines, "\n"))
fh:close()

print(string.format("Wrote full-context dump for %d scenarios -> %s", #TD.SCENARIOS, OUT))
print(string.format(
  "Cross-channel redundancy findings: %d (%d between context channels, %d FORCE_QUERY by design); "
  .. "scenario errors: %d", findings, gated_findings, findings - gated_findings, errors))
print(string.format(
  "==== context-dump: %d scenarios, %d cross-prompt finding(s), %d by-design, %d FAIL ====",
  #TD.SCENARIOS, gated_findings, findings - gated_findings, (errors > 0 or gated_findings > 0) and 1 or 0))
if errors > 0 then
  print("FAIL  " .. errors .. " scenario(s) threw while rendering context")
end
if GATE and gated_findings > 0 then
  print("FAIL  " .. gated_findings
    .. " redundancy finding(s) between channels Neuro receives in the same prompt -- see " .. OUT)
end
if errors > 0 or (GATE and gated_findings > 0) then os.exit(1) end
if GATE and not (arg and arg[1]) then require("tests.tmp_workdir").close() end
