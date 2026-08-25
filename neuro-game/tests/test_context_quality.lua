_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local A = require("core.actions")
local D = require("core.dispatcher")
local ContextCompact = require("context.context_compact")
G.NEURO.dispatcher = D
G.NEURO.actions = A
local TD = require("tests.test_deadlock")

local check, done = require("tests.helpers").harness("context-quality")

local CEIL_VOLATILE = 2500
local CEIL_STABLE = 3400
local CEIL_FULL = 5150

local function header_id(line)
  if line:find("^STATE:") then return "STATE" end
  return line:match("^([A-Z][A-Z_0-9]*)[:|%[%(]")
end

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
      if #line > 8 then
        if line_seen[line] then dup_line[#dup_line + 1] = line:sub(1, 48) end
        line_seen[line] = true
      end
    end
  end
  return dup_hdr, dup_line, hdr_count
end

local function assert_clean(tag, vol, sta, full)
  local vdh, vdl = scan(vol)
  local sdh, sdl = scan(sta)
  local fdh, fdl, fset = scan(full)

  check(tag .. ": no duplicate section in volatile", #vdh == 0, table.concat(vdh, ","))
  check(tag .. ": no duplicate line in volatile", #vdl == 0, vdl[1])
  check(tag .. ": no duplicate section in stable", #sdh == 0, table.concat(sdh, ","))
  check(tag .. ": no duplicate line in stable", #sdl == 0, sdl[1])
  check(tag .. ": no duplicate section in full (no cross-channel resend)", #fdh == 0, table.concat(fdh, ","))
  check(tag .. ": no duplicate line in full", #fdl == 0, fdl[1])
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

local seen, swept = {}, 0
local worst_vol, worst_full = 0, 0
for _, sc in ipairs(TD.SCENARIOS) do
  local key = sc.state .. "|" .. sc.desc
  if not seen[key] then
    seen[key] = true
    reset_g()
    local ok = pcall(function()
      TD.apply_mock(sc.mock())
      G.NEURO.persona = "neuro";
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
G.NEURO.persona = "neuro";

local acts = A.get_valid_actions_for_state("SELECTING_HAND")
local mvol = ContextCompact.build("SELECTING_HAND", acts, { split = "volatile", no_cache = true }) or ""
local msta = ContextCompact.build("SELECTING_HAND", acts, { split = "stable", no_cache = true }) or ""
local mfull = ContextCompact.build("SELECTING_HAND", acts, { no_cache = true }) or ""
print(string.format("   [maximal] volatile=%d stable=%d full=%d chars", #mvol, #msta, #mfull))
assert_clean("MAXIMAL/full-board", mvol, msta, mfull)
check("MAXIMAL: volatile carries jokers section", mvol:find("Your jokers (", 1, true) ~= nil, mvol:sub(1, 80))
check("MAXIMAL: volatile carries the hand", mvol:find("Your hand:", 1, true) ~= nil)

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
check("MAXIMAL SHOP: carries shop items (I:)", svol:find("Shop items:", 1, true) ~= nil)
check("MAXIMAL SHOP: carries owned jokers (J) and consumables (C)",
  svol:find("Your jokers (", 1, true) ~= nil and svol:find("\nC", 1, true) ~= nil, svol:sub(1, 80))

do
  local CtxHand = require("context.ctx_hand")
  reset_g()

  G.GAME.hands = {
    Pair = { visible = true, level = 1, chips = 10, mult = 2, played = 0 },
    Flush = { visible = true, level = 1, chips = 35, mult = 4, played = 0 },
  }
  local l_all1 = CtxHand.levels_section() or ""
  check("all level 1 formats as single compact line", l_all1 == "Hand levels: all level 1.", l_all1)

  G.GAME.hands = {
    Pair = { visible = true, level = 3, chips = 30, mult = 4, played = 5 },
    Flush = { visible = true, level = 1, chips = 35, mult = 4, played = 0 },
  }
  local l_up = CtxHand.levels_section() or ""
  check("upgraded hand is listed", l_up:find("Pair: level 3, 30 chips x 4 mult = 120 before any card or joker, played 5.", 1, true) ~= nil, l_up)
  check("base hands summarized in delta", l_up:find("(all other hands: level 1)", 1, true) ~= nil, l_up)
  check("un-upgraded Flush not listed individually", l_up:find("Flush: level 1", 1, true) == nil, l_up)

  G.GAME.blind = { key = "bl_flint", name = "The Flint", in_blind = true, disabled = false, loc_txt = { text = { "Flint text" } } }
  local l_notes = CtxHand.levels_section() or ""
  check("note_str shows full table with note", l_notes:find("Flush: level 1", 1, true) ~= nil, l_notes)
end

done()
