-- Synthetic context-quality gate: builds the real assembled context for every mock state (plus a
-- constructed maximal board) and asserts the model is never fed duplicated or bloated context.
-- Since budget-dropping was removed (full context always), this guards the two things that policy
-- can regress: the same fact/section appearing twice, and a section ballooning. Run: luajit tests/test_context_quality.lua
package.path = "./?.lua;;" .. package.path
_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local A = require("core.actions")
local D = require("core.dispatcher")
local ContextCompact = require("context.context_compact")
G.NEURO.dispatcher = D
G.NEURO.actions = A
local TD = require("tests.test_deadlock")

local fails, total = 0, 0
local function check(name, cond, detail)
  total = total + 1
  if cond then
    print("PASS  " .. name)
  else
    fails = fails + 1
    print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or ""))
  end
end

-- absolute ceilings: base Balatro context is naturally bounded (observed worst-case ~1.2k volatile /
-- ~3k full on a maximal board), so these sit ~2x above reality -- loose enough for normal growth, tight
-- enough to trip on a real runaway (a section repeating, an unbounded blob, a doubled legend).
local CEIL_VOLATILE = 2500
local CEIL_STABLE = 3000
local CEIL_FULL = 5000

local function header_id(line)
  if line:find("^STATE:") then return "STATE" end
  return line:match("^([A-Z][A-Z_0-9]*)[:|%[%(]")
end

-- returns: dup_headers[], dup_lines[], header_set{}
local function scan(blob)
  local hdr_count, dup_hdr = {}, {}
  local line_seen, dup_line = {}, {}
  for line in (blob .. "\n"):gmatch("([^\n]*)\n") do
    if line ~= "" then
      local id = header_id(line)
      if id then
        hdr_count[id] = (hdr_count[id] or 0) + 1
        if hdr_count[id] == 2 then dup_hdr[#dup_hdr + 1] = id end
      end
      -- a non-trivial line appearing verbatim twice is duplicated content (bloat)
      if #line > 8 then
        if line_seen[line] then dup_line[#dup_line + 1] = line:sub(1, 48) end
        line_seen[line] = true
      end
    end
  end
  return dup_hdr, dup_line, hdr_count
end

-- one scenario's worth of assertions on the three channels the model actually receives
local function assert_clean(tag, vol, sta, full)
  local vdh, vdl = scan(vol)
  local sdh, sdl = scan(sta)
  local fdh, fdl, fset = scan(full)

  check(tag .. ": no duplicate section in volatile", #vdh == 0, table.concat(vdh, ","))
  check(tag .. ": no duplicate line in volatile", #vdl == 0, vdl[1])
  check(tag .. ": no duplicate section in stable", #sdh == 0, table.concat(sdh, ","))
  check(tag .. ": no duplicate line in stable", #sdl == 0, sdl[1])
  -- full = stable+volatile concatenated; a duplicate header here == the same section on both channels
  check(tag .. ": no duplicate section in full (no cross-channel resend)", #fdh == 0, table.concat(fdh, ","))
  check(tag .. ": no duplicate line in full", #fdl == 0, fdl[1])
  check(tag .. ": no DROPPED marker (full context)", not vol:find("DROPPED:") and not full:find("DROPPED:"))
  check(tag .. ": volatile not bloated (<= " .. CEIL_VOLATILE .. ")", #vol <= CEIL_VOLATILE, #vol)
  check(tag .. ": stable not bloated (<= " .. CEIL_STABLE .. ")", #sta <= CEIL_STABLE, #sta)
  check(tag .. ": full not bloated (<= " .. CEIL_FULL .. ")", #full <= CEIL_FULL, #full)
  return fset
end

local MOCK_RESET = {
  "hand", "jokers", "consumeables", "deck",
  "shop_jokers", "shop_vouchers", "shop_booster",
  "pack_cards", "booster_pack", "blind_select_opts", "blind_select",
  "OVERLAY_MENU", "STATES", "STATE", "TIMERS", "P_CENTER_POOLS",
}
local function reset_g()
  for _, k in ipairs(MOCK_RESET) do G[k] = nil end
  G.GAME = { current_round = {} }
  G.NEURO.reserved_dollars = 0
  G.NEURO.shop_reroll_count = 0
end

-- ============ sweep: every distinct mock scenario ============
local seen, swept = {}, 0
local worst_vol, worst_full = 0, 0
for _, sc in ipairs(TD.SCENARIOS) do
  local key = sc.state .. "|" .. sc.desc
  if not seen[key] then
    seen[key] = true
    reset_g()
    local ok = pcall(function()
      TD.apply_mock(sc.mock())
      G.NEURO.persona = "neuro"; G.NEURO.rules_sent = true
    end)
    if ok then
      swept = swept + 1
      local acts = A.get_valid_actions_for_state(sc.state)
      local vol = ContextCompact.build(sc.state, acts, { split = "volatile", no_cache = true }) or ""
      local sta = ContextCompact.build(sc.state, acts, { split = "stable", no_cache = true }) or ""
      local full = ContextCompact.build(sc.state, acts, { no_cache = true }) or ""
      if #vol > worst_vol then worst_vol = #vol end
      if #full > worst_full then worst_full = #full end
      assert_clean(sc.state .. "/" .. sc.desc:sub(1, 20), vol, sta, full)
    end
  end
end
check("sweep: covered many scenarios", swept >= 40, swept)
print(string.format("   [sweep] %d scenarios, worst volatile=%d full=%d", swept, worst_vol, worst_full))

-- ============ constructed maximal board (the no-drop worst case) ============
-- 5 jokers with real effects, full hand, consumables, a full deck, levels -- everything the full-context
-- policy now keeps at once. Prove it stays de-duplicated and within the ceiling.
local function jk(name, key)
  return { ability = { name = name, set = "Joker" }, sell_cost = 3,
    config = { center = { key = key, set = "Joker", name = name, rarity = 1 } } }
end
local function pcard(v, s) return { base = { value = v, suit = s }, config = { center = { key = "c_base" } }, ability = {} } end

reset_g()
G.jokers = { cards = { jk("Joker", "j_joker"), jk("Greedy Joker", "j_greedy_joker"),
  jk("Blueprint", "j_blueprint"), jk("Brainstorm", "j_brainstorm"), jk("Baron", "j_baron") },
  config = { card_limit = 5 } }
G.consumeables = { cards = {
  { ability = { name = "The Fool", set = "Tarot" }, sell_cost = 1, config = { center = { key = "c_fool" } } },
  { ability = { name = "Pluto", set = "Planet" }, sell_cost = 1, config = { center = { key = "c_pluto" } } },
}, config = { card_limit = 2 } }
G.hand = { cards = { pcard("A", "Hearts"), pcard("K", "Hearts"), pcard("Q", "Hearts"),
  pcard("9", "Clubs"), pcard("5", "Diamonds"), pcard("3", "Spades"), pcard("2", "Spades"), pcard("7", "Clubs") },
  highlighted = {}, config = { card_limit = 8 } }
G.deck = { cards = {} }
for i = 1, 44 do G.deck.cards[i] = pcard("2", "Hearts") end
G.GAME = { current_round = { hands_left = 3, discards_left = 2 }, dollars = 12, round_resets = { ante = 3 },
  blind = { name = "The Wall", chips = 400, mult = 2 } }
G.NEURO.persona = "neuro"; G.NEURO.rules_sent = true

local acts = A.get_valid_actions_for_state("SELECTING_HAND")
local mvol = ContextCompact.build("SELECTING_HAND", acts, { split = "volatile", no_cache = true }) or ""
local msta = ContextCompact.build("SELECTING_HAND", acts, { split = "stable", no_cache = true }) or ""
local mfull = ContextCompact.build("SELECTING_HAND", acts, { no_cache = true }) or ""
print(string.format("   [maximal] volatile=%d stable=%d full=%d chars", #mvol, #msta, #mfull))
assert_clean("MAXIMAL/full-board", mvol, msta, mfull)
-- the fat board must actually carry the board (not silently empty), so the cleanliness means something
check("MAXIMAL: volatile carries jokers section", mvol:find("\nJ", 1, true) ~= nil, mvol:sub(1, 80))
check("MAXIMAL: volatile carries the hand", mvol:find("\nH:", 1, true) ~= nil)

-- same maximal board, but in the SHOP (the user's pain point): full board + a full shop to buy from
G.shop_jokers = { cards = {
  jk("Mime", "j_mime"), { ability = { name = "The Tower", set = "Tarot" }, cost = 3,
    config = { center = { key = "c_tower", set = "Tarot", kind = nil, loc_txt = { text = { "Enhances 1 card into Stone" } } } } } },
  config = { card_limit = 2 } }
G.shop_vouchers = { cards = { { ability = { name = "Overstock", set = "Voucher" }, cost = 10,
  config = { center = { key = "v_overstock", set = "Voucher" } } } } }
G.shop_booster = { cards = {
  { cost = 4, ability = { set = "Booster", name = "Buffoon Pack" }, config = { center = { kind = "Buffoon", set = "Booster", key = "p_buffoon_normal_1" } } },
  { cost = 4, ability = { set = "Booster", name = "Celestial Pack" }, config = { center = { kind = "Celestial", set = "Booster", key = "p_celestial_normal_1" } } } } }
local sacts = A.get_valid_actions_for_state("SHOP")
local svol = ContextCompact.build("SHOP", sacts, { split = "volatile", no_cache = true }) or ""
local ssta = ContextCompact.build("SHOP", sacts, { split = "stable", no_cache = true }) or ""
local sfull = ContextCompact.build("SHOP", sacts, { no_cache = true }) or ""
print(string.format("   [maximal SHOP] volatile=%d stable=%d full=%d chars", #svol, #ssta, #sfull))
assert_clean("MAXIMAL/shop-full", svol, ssta, sfull)
check("MAXIMAL SHOP: carries owned jokers (J) and consumables (C)",
  svol:find("\nJ", 1, true) ~= nil and svol:find("\nC", 1, true) ~= nil, svol:sub(1, 80))
check("MAXIMAL SHOP: carries shop items (I:)", svol:find("\nI:", 1, true) ~= nil)

print(string.format("==== context-quality: %d/%d PASS, %d FAIL ====", total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
