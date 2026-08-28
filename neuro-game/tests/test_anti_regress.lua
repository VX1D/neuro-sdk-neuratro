_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local A = require("core.actions")
local D = require("core.dispatcher")
local Utils = require("util.utils")
local ActionResult = require("core.action_result")
local function action_error(value)
  return ActionResult.is_error(value) and ActionResult.normalize(value).message or tostring(value or "")
end
local ContextCompact = require("context.context_compact")
G.NEURO.dispatcher = D
G.NEURO.actions = A
local TD = require("tests.test_deadlock")

local check, done = require("tests.helpers").harness("anti-regress")
local function has(list, v)
  for _, x in ipairs(list or {}) do if x == v then return true end end
  return false
end
local function card(v, s, stone)
  return { base = { value = v, suit = s }, config = { center = { key = stone and "m_stone" or "c" } } }
end

do
  check("HUD masks: English cache initializes before localization", Utils.is_masked_name("Not Discovered"))
  local old_localize = _G.localize
  _G.localize = function(key)
    if key == "k_not_discovered" then return "Nicht entdeckt" end
    if key == "k_locked" then return "Gesperrt" end
    return key
  end
  check("HUD masks: localized undiscovered refreshes after early cache", Utils.is_masked_name("Nicht entdeckt"))
  check("HUD masks: localized locked refreshes after early cache", Utils.is_masked_name("Gesperrt"))
  _G.localize = old_localize
end

do
  local Cards = require("hud.cards")
  local ModifierBadges = require("render.modifier_badges")
  local masked_blueprint = {
    config = { center = { key = "j_blueprint", set = "Joker", name = "Blueprint",
      loc_txt = { name = "Blueprint" } } },
    ability = { set = "Joker", name = "Not Discovered", eternal = true, rental = true },
    edition = { holo = true },
    seal = "Gold",
    generate_UIBox_ability_table = function() return { name = "Not Discovered" } end,
  }
  local shown = Cards.card_display_name(masked_blueprint)
  check("HUD identity: masked Blueprint resolves real name", shown == "Blueprint", shown)
  check("HUD identity: rendered name is never a discovery mask",
    shown ~= "Not Discovered" and shown ~= "Locked", shown)

  local fixture_badges = ModifierBadges.collect(masked_blueprint)
  check("HUD badges: Buffoon fixture has four distinct modifiers in priority order",
    #fixture_badges == 4
      and fixture_badges[1].text == "Eternal"
      and fixture_badges[1].fx == nil
      and fixture_badges[2].text == "Rental"
      and fixture_badges[2].fx == "-$3"
      and fixture_badges[3].text == "Holo"
      and fixture_badges[3].fx == "+10m"
      and fixture_badges[3].key == "Holo"
      and fixture_badges[4].text == "Gold Seal",
    table.concat((function()
      local out = {}
      for _, badge in ipairs(fixture_badges) do out[#out + 1] = badge.text end
      return out
    end)(), ","))
  check("HUD badges: edition is not appended to fixture title",
    shown == "Blueprint" and not shown:find("Holo", 1, true), shown)

  local enhanced = {
    base = { value = "7", suit = "Hearts" },
    config = { center = { key = "m_gold", set = "Enhanced" } },
    ability = { set = "Enhanced" },
    edition = { holo = true },
    seal = "Red",
  }
  local badges = ModifierBadges.collect(enhanced)
  check("HUD badges: edition seal enhancement order",
    #badges == 3 and badges[1].text == "Holo" and badges[1].fx == "+10m"
      and badges[2].text == "Red Seal" and badges[2].fx == "x2"
      and badges[3].text == "Gold" and badges[3].fx == "+$3")

  local font_stub = {
    getWidth = function(_, text) return 8 * #text end,
    getHeight = function() return 12 end,
  }
  local function fixed_trunc(text, max_width)
    local max_chars = math.max(0, math.floor(max_width / 8))
    if #text <= max_chars then return text end
    if max_chars <= 1 then return text:sub(1, max_chars) end
    return text:sub(1, max_chars - 1) .. "…"
  end
  local layout = ModifierBadges.layout(badges, font_stub, 155, 1, 2, fixed_trunc)
  local all_inside = layout.rows <= 2 and #layout.items == 3
  for _, item in ipairs(layout.items) do
    all_inside = all_inside and item.x + item.w <= 155 and not item.text:match("^%+%d+$")
  end
  check("HUD badge layout: three normal badges fit two rows without overflow", all_inside)

  local oversized = ModifierBadges.layout({
    { kind = "enhancement", text = "Custom Enhancement With An Extremely Long Name" },
  }, font_stub, 80, 1, 2, fixed_trunc)
  check("HUD badge layout: oversized custom label truncates inside pill",
    #oversized.items == 1 and oversized.items[1].text ~= "Custom Enhancement With An Extremely Long Name"
      and oversized.items[1].x + oversized.items[1].w <= 80,
    oversized.items[1] and oversized.items[1].text)

  local seven = {}
  for i = 1, 7 do seven[i] = { kind = "sticker", text = "Badge" .. tostring(i) } end
  local overflow = ModifierBadges.layout(seven, font_stub, 100, 1, 2, fixed_trunc)
  local last = overflow.items[#overflow.items]
  local overflow_inside = overflow.rows <= 2 and last ~= nil
    and (#overflow.items == 7 or last.text:match("^%+%d+$") ~= nil)
  for _, item in ipairs(overflow.items) do overflow_inside = overflow_inside and item.x + item.w <= 100 end
  check("HUD badge layout: pathological stack ends in bounded overflow pill", overflow_inside,
    last and last.text)
end
local MOCK_RESET = {
  "hand", "jokers", "consumeables", "deck",
  "shop_jokers", "shop_vouchers", "shop_booster",
  "pack_cards", "booster_pack",
  "blind_select_opts", "blind_select",
  "OVERLAY_MENU", "STATES", "STATE", "TIMERS", "P_CENTER_POOLS",
}
local function mock_state(desc_match, state)
  require("core.action_receipt").reset("mock_state")
  for _, k in ipairs(MOCK_RESET) do G[k] = nil end
  G.GAME = { current_round = {} }
  G.FUNCS.get_poker_hand_info = nil
  G.NEURO.reserved_dollars = 0
  G.NEURO.shop_reroll_count = 0
  for _, sc in ipairs(TD.SCENARIOS) do
    if sc.state == state and sc.desc:find(desc_match, 1, true) then
      TD.apply_mock(sc.mock())
      G.NEURO.persona = "neuro"; G.NEURO.state_entry_hints = nil
      return
    end
  end
  error(string.format("mock_state: no scenario matching %q in state %s", desc_match, state))
end

do
  local statics = {}
  for _, d in ipairs(A.get_static_actions()) do statics[d.name] = true end
  for _, r in ipairs({ "draw_from_deck", "highlight_card", "unhighlight_all" }) do
    check("removed/" .. r .. " not in static defs", not statics[r])
  end
end

for _, st in ipairs({ "SELECTING_HAND", "SHOP", "TAROT_PACK" }) do
  check("card_click not in " .. st, not has(A.get_action_names_for_state(st), "card_click"))
  check("end_consumeable not in " .. st, not has(A.get_action_names_for_state(st), "end_consumeable"))
end

check("start_challenge_run in MENU", has(A.get_action_names_for_state("MENU"), "start_challenge_run"))
check("change_challenge_description in MENU", has(A.get_action_names_for_state("MENU"), "change_challenge_description"))
for _, st in ipairs({ "RUN_SETUP", "GAME_OVER" }) do
  check("start_challenge_run not in " .. st, not has(A.get_action_names_for_state(st), "start_challenge_run"))
  check("change_challenge_description not in " .. st, not has(A.get_action_names_for_state(st), "change_challenge_description"))
end

do
  mock_state("With overlay present", "GAME_OVER")
  local f = D.get_force_for_state("GAME_OVER")
  check("GAME_OVER+overlay force omits the flaky exit_overlay_menu",
    f and not has(f.actions, "exit_overlay_menu"), f and table.concat(f.actions or {}, ","))
  check("GAME_OVER+overlay force offers setup_run (new-run path)",
    f and has(f.actions, "setup_run"))
end

do
  mock_state("With overlay present", "GAME_OVER")
  check("GAME_OVER offers setup_run immediately (no hold)",
    (D.get_force_for_state("GAME_OVER") or {}).actions ~= nil
      and has((D.get_force_for_state("GAME_OVER") or {}).actions, "setup_run"))
end

do
  mock_state("With unlock popup", "GAME_OVER")
  local f = D.get_force_for_state("GAME_OVER")
  check("GAME_OVER+unlock popup forces exit_overlay_menu",
    f and has(f.actions, "exit_overlay_menu"), f and table.concat(f.actions or {}, ","))
  check("GAME_OVER+unlock popup force is exit-only (not setup_run under the popup)",
    f and not has(f.actions, "setup_run"))
end

do
  mock_state("Overlay blocks during hand selection", "SELECTING_HAND")
  local valid = A.get_valid_actions_for_state("SELECTING_HAND")
  check("blocking overlay publishes only exit_overlay_menu",
    #valid == 1 and valid[1] == "exit_overlay_menu", table.concat(valid, ","))
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("5", "Hearts"), card("5", "Spades"), card("9", "Clubs") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 3
  local sh = A.get_action_names_for_state("SELECTING_HAND")
  check("commit action play_cards_from_highlighted de-registered", not has(sh, "play_cards_from_highlighted"))
  check("commit action discard_cards_from_highlighted de-registered", not has(sh, "discard_cards_from_highlighted"))
  check("legacy set_hand_highlight de-registered", not has(sh, "set_hand_highlight"))
  check("legacy clear_hand_highlight de-registered", not has(sh, "clear_hand_highlight"))
  check("play_hand offered in SELECTING_HAND", has(sh, "play_hand"))
  check("discard_hand offered in SELECTING_HAND", has(sh, "discard_hand"))
  check("play_hand valid with hand + hands_left>0", A.is_action_valid("play_hand"))
  check("discard_hand valid with hand + discards_left>0", A.is_action_valid("discard_hand"))
  G.GAME.current_round.hands_left = 0
  check("play_hand invalid with 0 hands left", not A.is_action_valid("play_hand"))
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 0
  check("discard_hand invalid with 0 discards left", not A.is_action_valid("discard_hand"))
  G.GAME.current_round.discards_left = 3
  G.hand = { cards = {}, highlighted = {} }
  check("play_hand invalid with empty hand", not A.is_action_valid("play_hand"))
  check("discard_hand invalid with empty hand", not A.is_action_valid("discard_hand"))
end

do
  mock_state("sell", "SHOP")
  G.jokers = { cards = {
    { ability = { name = "Joker" }, sell_cost = 3, config = { center = { key = "j_joker" } } },
    { ability = { name = "Blueprint" }, sell_cost = 3, config = { center = { key = "j_blueprint" } } },
  }, config = { card_limit = 5 } }
  local avail = A.get_available_actions_for_state("SHOP")
  check("available actions include set_joker_order (2 jokers)", has(avail, "set_joker_order"))
  check("available actions are exactly the valid ones (nothing is filtered out any more)",
    #avail == #A.get_valid_actions_for_state("SHOP"),
    #avail .. "/" .. #A.get_valid_actions_for_state("SHOP"))
end

do
  mock_state("Normal", "SHOP")
  G.jokers = { cards = {
    { ability = { name = "Joker" }, sell_cost = 3, config = { center = { key = "j_joker" } } },
    { ability = { name = "Blueprint" }, sell_cost = 3, config = { center = { key = "j_blueprint" } } },
  }, config = { card_limit = 5 } }
  local f = D.get_force_for_state("SHOP")
  check("SHOP force offers set_joker_order", f and has(f.actions, "set_joker_order"))
  check("SHOP force offers set_plan whenever planning is on", f and has(f.actions, "set_plan"))
end

do
  mock_state("Small blind selectable", "BLIND_SELECT")
  G.jokers = { cards = {
    { ability = { name = "Joker" }, config = { center = { key = "j_joker" } } },
    { ability = { name = "Blueprint" }, config = { center = { key = "j_blueprint" } } },
  }, config = { card_limit = 5 } }
  local f = require("force.force_blind_select").build()
  check("TW-01: blind force offers set_joker_order when advice can recommend it",
    f and has(f.actions, "set_joker_order"))
  check("TW-01: blind force offers set_plan whenever planning is on",
    f and has(f.actions, "set_plan"))
end

do
  local CU = require("facts.card_util")
  check("booster_kind: reads center.kind", CU.booster_kind({ config = { center = { kind = "Celestial" } } }) == "Celestial")
  check("booster_kind: empty for a non-pack", CU.booster_kind({ ability = { name = "Joker" }, config = { center = { key = "j_joker" } } }) == "")
end

do
  local function buffoon()
    return { cost = 4, ability = { set = "Booster", name = "Buffoon Pack" },
      config = { center = { kind = "Buffoon", set = "Booster", key = "p_buffoon_normal_1" } } }
  end
  local function arcana()
    return { cost = 4, ability = { set = "Booster", name = "Arcana Pack" },
      config = { center = { kind = "Arcana", set = "Booster", key = "p_arcana_normal_1" } } }
  end
  local function full_jokers()
    G.jokers = { cards = { { ability = { name = "Joker" }, sell_cost = 3, config = { center = { key = "j_joker" } } } },
      config = { card_limit = 1 } }
  end
  local WARN = "Buffoon pack"

  mock_state("Normal", "SHOP")
  full_jokers()
  G.shop_booster = { cards = { buffoon() } }
  local q_full = (D.get_force_for_state("SHOP") or {}).query or ""
  check("shop force warns: Buffoon pack + joker slots full",
    q_full:find(WARN, 1, true) ~= nil and q_full:find("selling a joker", 1, true) ~= nil)

  local blob = ContextCompact.build("SHOP", A.get_valid_actions_for_state("SHOP"), { no_cache = true })
  local row = blob:match("shop booster[^\n]*")
  check("ctx: shop_booster type column = Buffoon (not generic Booster)",
    row ~= nil and row:find("(Buffoon)", 1, true) ~= nil, row)

  mock_state("Normal", "SHOP")
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.shop_booster = { cards = { buffoon() } }
  local q_open = (D.get_force_for_state("SHOP") or {}).query or ""
  check("shop force: no Buffoon warning when joker slots open", q_open:find(WARN, 1, true) == nil)

  mock_state("Normal", "SHOP")
  full_jokers()
  G.shop_booster = { cards = { arcana() } }
  local q_arc = (D.get_force_for_state("SHOP") or {}).query or ""
  check("shop force: no Buffoon warning for a non-joker pack", q_arc:find(WARN, 1, true) == nil)
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("2", "Hearts"), card("5", "Hearts"), card("7", "Hearts"), card("9", "Hearts"), card("King", "Spades") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2
  local q = (D.get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("Close: near Flush (4 of a suit)", q:find("One card away: Flush") ~= nil, q:match("Shape:[^\n]*"))
  G.FUNCS.get_poker_hand_info = function(_)
    local hc = G.hand.cards
    return "Flush", nil, { Flush = { hc[1], hc[2], hc[3], hc[4] }, ["High Card"] = { hc[1] } }, { hc[1], hc[2], hc[3], hc[4] }, nil
  end
  local q2 = (D.get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("Ready: Flush shown", q2:find("Ready to play now:[^\n]*Flush") ~= nil)
  check("near Flush deduped when ready", q2:find("One card away") == nil)
  G.FUNCS.get_poker_hand_info = nil
  G.GAME.current_round.discards_left = 0
  local q3 = (D.get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("no Close when discards=0", q3:find("Close:") == nil)
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("2", "Hearts"), card("5", "Hearts"), card("7", "Hearts"), card("9", "Hearts"), card("?", "?", true) }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2
  local q = (D.get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("stone not counted (suit_max=4, near Flush)", q:find("most cards of one suit 4") and q:find("One card away: Flush"))
end

do
  local function dyna(arr) return { config = { string = arr } } end
  local r = {}; for i = 0, 23 do r[#r + 1] = tostring(i) end
  local mis = { ability = { name = "Misprint" }, config = { center = { key = "j_misprint" } },
    generate_UIBox_ability_table = function() return { main = {
      { config = { text = "  +" } }, { config = { object = dyna(r) } },
      { config = { object = dyna({ "Mult", "#@11D", "rand()" }) } } } } end }
  local desc = Utils.card_description(mis) or ""
  check("Misprint desc has range 0 to 23", desc:find("0 to 23") ~= nil, desc)
  check("Misprint desc filters easter-egg", not desc:find("#@"), desc)
end

do
  local function H(name) return D.get_action_handler(name) end
  check("play_hand handler accessor works", type(H("play_hand")) == "function")
  check("discard_hand handler accessor works", type(H("discard_hand")) == "function")

  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("5", "Hearts"), card("5", "Spades"), card("9", "Clubs") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 3
  local _, first_play_err = H("play_hand")({ indices = { 1, 2 } })
  check("atomic play first requests review", ActionResult.is_error(first_play_err))

  local c1, e1 = H("play_hand")({})
  check("play_hand no indices -> error", c1 == nil and ActionResult.is_error(e1))
  local c_hl = H("play_hand")({ indices = { 1, 2 } })
  local ok_hl, r_hl = pcall(c_hl)
  check("atomic play -> closure runs to a string", type(c_hl) == "function" and ok_hl and type(r_hl) == "string", r_hl)

  G.GAME.blind = { debuff = { h_size_ge = 4 } }
  local c4, e4 = H("play_hand")({ indices = { 1 } })
  check("SH-2: boss min-cards rejects undersized play", c4 == nil and ActionResult.is_error(e4), e4)
  G.GAME.blind = nil

  local c_dis = H("discard_hand")({ indices = { 1 } })
  local ok_dis, r_dis = pcall(c_dis)
  check("atomic discard -> closure runs to a string", type(c_dis) == "function" and ok_dis and type(r_dis) == "string", r_dis)
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  local c5, e5 = H("sell_card")({ area = "jokers", index = 1 })
  check("sell_card empty area -> error", c5 == nil and ActionResult.is_error(e5))

  local expensive = card("A", "Spades"); expensive.cost = 100
  G.shop_jokers = { cards = { expensive } }
  G.GAME.dollars = 4; G.NEURO.reserved_dollars = 0
  local c6, e6 = H("buy_from_shop")({ area = "shop_jokers", index = 1 })
  check("buy_from_shop unaffordable -> error", c6 == nil and ActionResult.is_error(e6) and action_error(e6):find("afford") ~= nil)

  local tarot = { ability = { consumeable = { max_highlighted = 1, min_highlighted = 1 } }, config = { center = { key = "c_tarot" } } }
  G.consumeables = { cards = { tarot } }
  G.hand = { cards = {} }
  local c7, e7 = H("use_card")({ area = "consumeables", index = 1 })
  check("use_card needs hand target but no hand -> error", c7 == nil and ActionResult.is_error(e7))
  local planet = { ability = { consumeable = {} }, config = { center = { key = "c_planet" } } }
  G.consumeables = { cards = { planet } }
  local c_uc = H("use_card")({ area = "consumeables", index = 1 })
  local ok_uc, r_uc = pcall(c_uc)
  check("use_card no-target -> closure runs to a string", type(c_uc) == "function" and ok_uc and type(r_uc) == "string", r_uc)

end

do
  local SV = require("util.schema_validate")
  local sch = { type = "object", required = { "index" }, properties = {
    index = { type = "integer", minimum = 1 },
    area = { type = "string", enum = { "jokers", "consumeables" } },
  } }
  local ok1 = SV.validate_value(sch, { index = 2, area = "jokers" }, "parameters")
  check("schema valid payload -> true", ok1 == true)
  local ok2, e2 = SV.validate_value(sch, { area = "jokers" }, "parameters")
  check("schema missing required -> error", ok2 == false and type(e2) == "string" and e2:find("index") ~= nil)
  local ok3 = SV.validate_value(sch, { index = 1.5 }, "parameters")
  check("schema non-integer -> false", ok3 == false)
  local ok4 = SV.validate_value(sch, { index = 1, area = "shop" }, "parameters")
  check("schema enum violation -> false", ok4 == false)
  local ok5 = SV.validate_value(sch, { index = 0 }, "parameters")
  check("schema minimum bound -> false", ok5 == false)
end

do
  local CH = require("context.ctx_helpers")
  check("short_value resolves rank", CH.short_value("Ace") == "A")
  check("short_value passthrough unknown", CH.short_value("Foo") == "Foo")
  check("short_suit resolves suit", CH.short_suit("Hearts") == "H")
  check("short_enh resolves enhancement", CH.short_enh({ ability = { enhancement = "m_gold" } }):find("Gold") ~= nil)
  check("short_seal resolves seal", CH.short_seal({ seal = "Red" }):find("Red") ~= nil)
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = {
    { base = { value = "Ace", suit = "Hearts" }, ability = { enhancement = "m_gold" }, seal = "Red", config = { center = { key = "c" } } },
    { base = { value = "King", suit = "Spades" }, config = { center = { key = "c" } } },
  }, highlighted = {}, config = { card_limit = 8 } }
  local ok_build, ctx = pcall(function() return ContextCompact.build("SELECTING_HAND") end)
  check("context build does not crash formatting cards", ok_build, ctx)
  if ok_build then
    local blob = type(ctx) == "table" and (ctx.query or ctx.text or table.concat(ctx, "\n")) or tostring(ctx)
    check("context names the card (Ace of Hearts)", blob:find("Ace of Hearts", 1, true) ~= nil)
  end
end

do
  local State = require("core.state")
  G.STATES = { MENU = 1 }
  G.STATE = 1
  G.OVERLAY_MENU = { get_UIE_by_ID = function(_, id) return (id == "run_setup_seed") and {} or nil end }
  check("RUN_SETUP reachable via overlay detector", State.get_state_name() == "RUN_SETUP")
  local f = D.get_force_for_state("RUN_SETUP")
  check("run-setup force offers start_setup_run (no deck-pick trap)", has((f or {}).actions, "start_setup_run"))
  G.STATES = { MENU = 1, GAME_OVER = 4 }; G.STATE = 4
  check("GAME_OVER + open run-setup overlay resolves to RUN_SETUP", State.get_state_name() == "RUN_SETUP")
  check("GAME_OVER-hosted run-setup force offers start_setup_run",
    has((D.get_force_for_state(State.get_state_name()) or {}).actions, "start_setup_run"))
  G.STATES = { MENU = 1, BLIND_SELECT = 7 }; G.STATE = 7
  local ok_bs, fbs = pcall(D.get_force_for_state, "BLIND_SELECT")
  check("BLIND_SELECT with a lingering run-setup overlay does NOT serve the RUN_SETUP force",
    not (ok_bs and has((fbs or {}).actions, "start_setup_run")))
  G.STATES = { MENU = 1 }; G.STATE = 1
  G.OVERLAY_MENU = nil
  check("no overlay -> not RUN_SETUP", State.get_state_name() ~= "RUN_SETUP")
  G.STATES = nil; G.STATE = nil
end

do
  local CU = require("facts.card_util")
  local tarot = { ability = { set = "Tarot" }, config = { center = { key = "c_tarot" } } }
  G.consumeables = { cards = { {}, {} }, config = { card_limit = 2 } }
  check("Tarot not takeable when consumables full", CU.can_take_pack_card(tarot) == false)
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  check("Tarot takeable when consumable space", CU.can_take_pack_card(tarot) == true)

  local H = D.get_action_handler
  mock_state("Normal", "SELECTING_HAND")
  G.consumeables = { cards = { {}, {} }, config = { card_limit = 2 } }
  G.pack_cards = { cards = { tarot } }
  G.booster_pack = G.pack_cards
  local c, e = H("use_card")({ area = "pack_cards", index = 1 })
  check("use_card rejects full-consumable pack pick with consumable message",
    c == nil and ActionResult.is_error(e) and action_error(e):find("consumable") ~= nil, e)
  G.pack_cards = nil; G.booster_pack = nil
end

do
  mock_state("Normal", "SELECTING_HAND")
  local jA = { ability = { set = "Joker" }, config = { center = { key = "j_joker", set = "Joker" } }, sell_cost = 3 }
  local jB = { ability = { set = "Joker" }, config = { center = { key = "j_blueprint", set = "Joker" } }, sell_cost = 3 }
  G.jokers = { cards = { jA, jB }, config = { card_limit = 5 } }
  local ctx1 = ContextCompact.build("SELECTING_HAND", nil, { no_cache = true })
  G.jokers.cards = { jB, jA }
  local ctx2 = ContextCompact.build("SELECTING_HAND", nil, { no_cache = true })
  check("set_joker_order changes the context the model sees", ctx1 ~= ctx2)
end

do
  local Enforce = require("core.enforce")
  G.STATES = { SHOP = 5 }; G.STATE = 5
  G.GAME = G.GAME or {}
  G.GAME.dollars = 6
  G.GAME.current_round = G.GAME.current_round or {}
  G.GAME.current_round.reroll_cost = 3
  G.NEURO.force_inflight = false
  G.NEURO.force_window = nil
  require("core.force_state").arm("SHOP", { "reroll_shop", "buy_from_shop" },
    { reroll_shop = true, buy_from_shop = true }, 1)
  G.NEURO.econ_plan_ok = true
  local reroll_blocked = false
  for _ = 1, 8 do
    if not Enforce.pre_action(nil, "reroll_shop") then reroll_blocked = true break end
  end
  check("forced reroll_shop spam is repeat-capped", reroll_blocked)
  local buy_blocked = false
  for _ = 1, 5 do
    if not Enforce.pre_action(nil, "buy_from_shop") then buy_blocked = true break end
  end
  check("forced buy_from_shop not throttled at 5 (generous cap)", not buy_blocked)
  G.NEURO.force_inflight = nil; G.NEURO.force_state = nil; G.NEURO.force_window = nil
  G.NEURO.econ_plan_ok = nil
  G.STATES = nil; G.STATE = nil
end

do
  local Enforce = require("core.enforce")
  G.STATES = { BUFFOON_PACK = 9 }; G.STATE = 9
  G.GAME = G.GAME or {}; G.GAME.STOP_USE = nil
  G.NEURO.force_inflight = false
  G.NEURO.force_window = nil
  require("core.force_state").arm("BUFFOON_PACK", { "use_card", "skip_booster", "sell_card" }, { use_card = true, skip_booster = true, sell_card = true }, 1)
  G.NEURO.state_enter_serial = 42
  require("core.decision_window").reset_field("pack_review")
  local ok1, msg1 = Enforce.pre_action(nil, "use_card")
  check("pack think-gate pauses first pick", ok1 == false and type(msg1) == "string"
    and msg1:find("This is a booster pack", 1, true) ~= nil, msg1)
  check("pack think-gate latches to this pack entry",
    G.NEURO._decision_windows.pack_review.armed_at == "BUFFOON_PACK|42")
  check("pack think-gate lets the repeat pick through", Enforce.pre_action(nil, "use_card") == true)
  check("pack think-gate not re-triggered by skip in same entry",
    Enforce.pre_action(nil, "skip_booster") == true)
  G.NEURO.state_enter_serial = 43
  local ok4, msg4 = Enforce.pre_action(nil, "skip_booster")
  check("pack think-gate re-arms on a new pack entry",
    ok4 == false and type(msg4) == "string" and msg4:find("This is a booster pack", 1, true) ~= nil)
  G.STATES = { MODDED_PACK = 10 }; G.STATE = 10
  G.NEURO.force_state = "MODDED_PACK"
  G.NEURO.state_enter_serial = 44
  require("core.decision_window").reset_field("pack_review")
  local ok_mod, msg_mod = Enforce.pre_action(nil, "use_card")
  check("pack think-gate covers modded *_PACK states",
    ok_mod == false and type(msg_mod) == "string"
      and msg_mod:find("This is a booster pack", 1, true) ~= nil, msg_mod)
  G.STATES = { BUFFOON_PACK = 9 }; G.STATE = 9
  G.NEURO.force_state = "BUFFOON_PACK"
  G.NEURO.force_inflight = nil; G.NEURO.force_state = nil; G.NEURO.force_window = nil
  G.NEURO.state_enter_serial = nil
  require("core.decision_window").reset_field("pack_review")
  G.STATES = nil; G.STATE = nil

do
  mock_state("BUFFOON_PACK variant with pack cards", "BUFFOON_PACK")
  local normal_force = D.get_force_for_state("BUFFOON_PACK")
  G.NEURO.pack_exit_pending = true
  check("terminal pack pick suppresses stale follow-up force",
    normal_force ~= nil and D.get_force_for_state("BUFFOON_PACK") == nil)
  G.NEURO.pack_exit_pending = nil
end
end

do
  local Enforce = require("core.enforce")
  local DecisionWindow = require("core.decision_window")
  G.STATES = { TAROT_PACK = 9 }; G.STATE = 9
  G.GAME = G.GAME or {}; G.GAME.STOP_USE = nil
  G.NEURO.force_inflight = false
  G.NEURO.force_window = nil
  require("core.force_state").arm("TAROT_PACK", { "use_card" }, { use_card = true }, 1)
  G.NEURO.state_enter_serial = 45
  DecisionWindow.reset_field("pack_review")
  local bridge = { is_transition_cooldown = function() return true end }
  local ok, msg, transient, code = Enforce.pre_action(bridge, "use_card")
  check("TW-07: transition cooldown still blocks execution before the decision window",
    ok == false and transient == true and msg:find("transitioning", 1, true) ~= nil, msg)
  check("TW-07: transition rejection does not arm the pack window",
    not (G.NEURO._decision_windows and G.NEURO._decision_windows.pack_review))
  check("TW-07: a forced action's transition block acknowledges, so the force is not retried into it",
    code == "TRANSITION_ACKNOWLEDGED" and ActionResult.acknowledges(code) == true, tostring(code))
  check("TW-07: the acknowledged prose tells Neuro nothing applied and to choose again",
    msg:find("nothing was applied", 1, true) ~= nil and msg:find("choose again", 1, true) ~= nil, msg)
  G.GAME.STOP_USE = 1
  local ok_su, _, _, code_su = Enforce.pre_action({ }, "use_card")
  check("TW-07: the engine-busy guard acknowledges for a forced action too",
    ok_su == false and code_su == "TRANSITION_ACKNOWLEDGED", tostring(code_su))
  G.GAME.STOP_USE = nil
  G.NEURO.force_inflight = nil; G.NEURO.force_state = nil; G.NEURO.force_window = nil
  local ok2, msg2, transient2, code2 = Enforce.pre_action(bridge, "use_card")
  check("TW-07: outside a force the same block stays a plain failure",
    ok2 == false and transient2 == true and code2 == "TRANSITION_PENDING"
      and ActionResult.acknowledges(code2) == false, tostring(code2) .. " / " .. tostring(msg2))
  G.NEURO.state_enter_serial = nil; G.STATES = nil; G.STATE = nil
end

do
  local HandHandlers = require("handlers.hand_handlers")
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("5", "Hearts"), card("9", "Clubs") }, highlighted = {} }
  G.play = { cards = { card("K", "Spades") } }
  G.NEURO.force_inflight = false
  G.NEURO.force_window = nil
  require("core.force_state").arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
  local exec, err = HandHandlers.handle_play_hand({ indices = { 1 } })
  check("TW-08: a hand still resolving does not execute play_hand",
    exec == nil and ActionResult.is_error(err), tostring(err))
  check("TW-08: the forced play_hand acknowledges instead of retrying the force into the same wall",
    err and err.reason_code == "TRANSITION_ACKNOWLEDGED"
      and ActionResult.acknowledges(err.reason_code) == true,
    err and tostring(err.reason_code))
  G.NEURO.force_inflight = nil; G.NEURO.force_state = nil; G.NEURO.force_window = nil
  local _, err_free = HandHandlers.handle_play_hand({ indices = { 1 } })
  check("TW-08: outside a force the same block stays a plain failure",
    err_free and err_free.reason_code == "TRANSITION_PENDING"
      and ActionResult.acknowledges(err_free.reason_code) == false,
    err_free and tostring(err_free.reason_code))
  G.play = nil
end

do
  mock_state("Normal", "SELECTING_HAND")
  local dh1 = card("5", "Hearts"); dh1.debuff = true
  local dh2 = card("5", "Spades"); dh2.debuff = true
  G.hand = { cards = { dh1, dh2, card("9", "Clubs") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2
  G.FUNCS.get_poker_hand_info = function(_)
    return "Pair", nil, { Pair = { dh1, dh2 }, ["High Card"] = { dh1 } }, { dh1, dh2 }, nil
  end
  local q = (D.get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("all-debuffed Ready hand dropped (scores 0)", q:find("Ready:[^\n]*Pair") == nil, q:match("Ready:[^\n]*") or "(no Ready line)")
  check("debuffed-card count surfaced", q:find("DEBUFFED") ~= nil)

  local pd = card("5", "Diamonds")
  G.hand = { cards = { dh1, pd, card("9", "Clubs") }, highlighted = {} }
  G.FUNCS.get_poker_hand_info = function(_)
    return "Pair", nil, { Pair = { dh1, pd }, ["High Card"] = { dh1 } }, { dh1, pd }, nil
  end
  local qp = (D.get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("partial-debuff Ready hand kept + annotated", qp:find("Ready to play now: Pair (cards 1, 2) (1 debuffed", 1, true) ~= nil, qp:match("Ready[^\n]*"))
  G.FUNCS.get_poker_hand_info = nil
end

do
  mock_state("Normal", "SELECTING_HAND")
  local cl = {}
  for _, r in ipairs({ "2", "5", "7", "9" }) do local c = card(r, "Clubs"); c.debuff = true; cl[#cl + 1] = c end
  G.hand = { cards = { cl[1], cl[2], cl[3], cl[4], card("King", "Spades") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2
  G.FUNCS.get_poker_hand_info = nil
  local q = (D.get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("debuffed-suit near-Flush not advertised in Close", q:find("near Flush") == nil, q:match("Close:[^\n]*") or "(no Close line)")
end

do
  mock_state("Normal", "SELECTING_HAND")
  local c5a, c5b = card("5", "Hearts"), card("5", "Spades")
  local c9a, c9b = card("9", "Clubs"), card("9", "Diamonds")
  local ck = card("K", "Hearts")
  G.hand = { cards = { c5a, c5b, c9a, c9b, ck }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2
  G.GAME.hands = { Pair = { visible = true, level = 1, chips = 10, mult = 2, played = 0 },
                   ["Two Pair"] = { visible = true, level = 1, chips = 20, mult = 2, played = 0 } }
  G.FUNCS.get_poker_hand_info = function(cards)
    local by, order = {}, {}
    for _, c in ipairs(cards) do
      local r = c.base.value
      if not by[r] then by[r] = {}; order[#order + 1] = r end
      table.insert(by[r], c)
    end
    table.sort(order)
    local cores = {}
    for _, r in ipairs(order) do if #by[r] >= 2 then cores[#cores + 1] = { by[r][1], by[r][2] } end end
    local ph = {}
    for _, k in ipairs({ "High Card", "Pair", "Two Pair", "Three of a Kind", "Straight", "Flush",
      "Full House", "Four of a Kind", "Straight Flush", "Five of a Kind", "Flush House", "Flush Five" }) do ph[k] = {} end
    ph["High Card"] = { cards[1] }
    local text = "High Card"
    if #cores >= 2 then
      text = "Two Pair"; local tp = {}
      for _, pc in ipairs(cores) do for _, c in ipairs(pc) do tp[#tp + 1] = c end end
      ph["Two Pair"] = { tp }; ph["Pair"] = { cores[1] }
    elseif #cores == 1 then text = "Pair"; ph["Pair"] = { cores[1] } end
    return text, nil, ph, cards, nil
  end
  local function boss(name, debuff, hands, only_hand)
    return { name = name, disabled = false, debuff = debuff or {}, hands = hands, only_hand = only_hand,
      debuff_hand = function(self, cards, hand, handname, check_only)
        if self.disabled then return end
        if self.debuff then
          if self.debuff.h_size_ge and #cards < self.debuff.h_size_ge then return true end
          if self.debuff.h_size_le and #cards > self.debuff.h_size_le then return true end
          if self.name == "The Eye" then
            if self.hands[handname] then return true end
            if not check_only then self.hands[handname] = true end
          elseif self.name == "The Mouth" then
            if self.only_hand and self.only_hand ~= handname then return true end
            if not check_only then self.only_hand = handname end
          end
        end
      end }
  end
  local HF = require("facts.hand_facts")

  local CtxBlind5 = require("context.ctx_blind")

  G.GAME.blind = boss("The Mouth", {}, nil, "Pair")
  local m = HF.summary()
  check("Mouth locked: off-type Two Pair stays in Ready with a boss-attributed annotation",
    m:find("Two Pair%[[%d,]+%][^;]* %-%- zeroed by The Mouth %(locked to Pair%)") ~= nil, m:match("Ready:[^\n]*"))
  check("Mouth locked: on-type Pair kept in Ready without annotation",
    m:find("Pair%[1,2%]") ~= nil and m:match("Pair%[1,2%][^;%.]*") :find("zeroed", 1, true) == nil,
    m:match("Ready:[^\n]*"))
  check("Mouth locked: off-type Close entries stay listed with the annotation",
    m:find("Close:") ~= nil and (m:match("Close:[^\n]*") or ""):find("zeroed by The Mouth", 1, true) ~= nil, m)
  local m_bd = CtxBlind5.blind_debuff_line() or ""
  check("Mouth locked: FACT line carries the engine's locked type every decision",
    m_bd:find("Locked hand type: Pair", 1, true) ~= nil, m_bd)

  G.GAME.blind = boss("The Mouth", {}, nil, false)
  local mu = HF.summary()
  check("Mouth unlocked: nothing annotated yet (both Ready)",
    mu:find("Two Pair%[") ~= nil and mu:find("Pair%[1,2%]") ~= nil and mu:find("zeroed", 1, true) == nil)
  local mu_bd = CtxBlind5.blind_debuff_line() or ""
  check("Mouth unlocked: FACT line states the rule and that no type is locked yet",
    mu_bd:find("first hand type you play this round locks", 1, true) ~= nil
      and mu_bd:find("Locked hand type: none yet", 1, true) ~= nil, mu_bd)

  G.GAME.blind = boss("The Eye", {}, { ["Two Pair"] = true }, nil)
  local e = HF.summary()
  check("Eye: already-used Two Pair stays in Ready with a boss-attributed annotation",
    e:find("Two Pair%[[%d,]+%][^;]* %-%- zeroed by The Eye %(already played this round%)") ~= nil,
    e:match("Ready:[^\n]*"))
  check("Eye: unused Pair kept in Ready without annotation",
    e:find("Pair%[1,2%]") ~= nil and e:match("Pair%[1,2%][^;%.]*"):find("zeroed", 1, true) == nil)
  local e_bd = CtxBlind5.blind_debuff_line() or ""
  check("Eye: FACT line carries the live used-set every decision",
    e_bd:find("Hand types already played this round: Two Pair", 1, true) ~= nil, e_bd)

  G.GAME.blind = boss("The Psychic", { h_size_ge = 5 })
  local p = HF.summary()
  check("Psychic: size rule does NOT drop a paddable Pair", p:find("Pair%[1,2%]") ~= nil, p:match("Ready:[^\n]*"))
  check("Psychic: size rule keeps Two Pair too", p:find("Two Pair%[") ~= nil, p:match("Ready:[^\n]*"))
  local p_bd = CtxBlind5.blind_debuff_line() or ""
  check("Psychic: FACT line states the size-rule consequence",
    p_bd:find("fewer than 5 cards scores 0", 1, true) ~= nil, p_bd)
  check("Psychic: size-rule number on per-hand tag", p:find("play 5%+ cards") ~= nil, p)

  G.GAME.blind = nil
  G.FUNCS.get_poker_hand_info = nil
end

do
  local DF = require("facts.debuff_facts")
  local HF = require("facts.hand_facts")
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("5", "Hearts"), card("9", "Clubs"), card("King", "Spades") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 3

  local CtxBlindPN = require("context.ctx_blind")
  G.GAME.blind = { name = "The Serpent", disabled = false, debuff = {} }
  G.deck = G.deck or { cards = {} }
  check("Serpent FACT line surfaced per decision",
    (CtxBlindPN.blind_debuff_line() or ""):find("The Serpent", 1, true) ~= nil, CtxBlindPN.blind_debuff_line())
  G.GAME.blind = { name = "The Arm", disabled = false, debuff = {} }
  check("Arm FACT line surfaced per decision",
    (CtxBlindPN.blind_debuff_line() or ""):find("lowers that hand type's level") ~= nil)
  G.GAME.blind = { name = "Verdant Leaf", disabled = false, debuff = {} }
  check("Verdant Leaf FACT line states the sell-a-joker unlock",
    (CtxBlindPN.blind_debuff_line() or ""):find("until you sell a Joker", 1, true) ~= nil,
    CtxBlindPN.blind_debuff_line())

  G.hand.cards[2].ability = { forced_selection = true }
  G.GAME.blind = { name = "Cerulean Bell", disabled = false, debuff = {} }
  check("forced_selection_index finds locked card", DF.forced_selection_index() == 2)
  check("Cerulean FACT line names the locked position",
    (CtxBlindPN.blind_debuff_line() or ""):find("The %+LOCK card is at position 2") ~= nil,
    CtxBlindPN.blind_debuff_line())

  local CtxHand = require("context.ctx_hand")
  check("LOCK token on the forced card", CtxHand.card_token(G.hand.cards[2], true):find("LOCK") ~= nil)
  check("no LOCK token on a free card", CtxHand.card_token(G.hand.cards[1], true):find("LOCK") == nil)

  local H = D.get_action_handler
  -- Spend the weak budget so the accepted play is not also paused for weak-hand advice.
  G.NEURO.weak_fired_serial = tonumber(G.NEURO.decision_serial) or 0
  local c_omit, e_omit = H("play_hand")({ indices = { 1, 3 } })
  check("play omitting locked card rejected", c_omit == nil and ActionResult.is_error(e_omit) and action_error(e_omit):find("force%-selected") ~= nil, e_omit)
  local c_ok = H("play_hand")({ indices = { 1, 2, 3 } })
  check("play including locked card accepted", type(c_ok) == "function")

  local c_disc, e_disc = H("discard_hand")({ indices = { 1 } })
  check("discard omitting locked card rejected", c_disc == nil and ActionResult.is_error(e_disc), e_disc)

  G.hand.cards[2].ability = nil
  G.GAME.blind = nil
end

do
  local H = D.get_action_handler
  mock_state("Normal", "SHOP")
  local function shop_item(c) local it = card("A", "Spades"); it.cost = c; return it end

  G.jokers = { cards = {} }; G.GAME.dollars = 0; G.GAME.bankrupt_at = 0; G.NEURO.reserved_dollars = 0
  G.shop_jokers = { cards = { shop_item(5) } }
  local b0, e0 = H("buy_from_shop")({ area = "shop_jokers", index = 1 })
  check("buy with $0 rejected (floor $0)", b0 == nil and ActionResult.is_error(e0))

  G.GAME.dollars = 5; G.NEURO.reserved_dollars = 0
  G.shop_jokers = { cards = { shop_item(5), shop_item(5) } }
  local saved_manager, saved_Event = G.E_MANAGER, rawget(_G, "Event")
  local queued = {}
  G.E_MANAGER = { add_event = function(_, event) queued[#queued + 1] = event end }
  _G.Event = function(event) return event end
  local b1 = H("buy_from_shop")({ area = "shop_jokers", index = 1 })
  if type(b1) == "function" then b1() end
  check("first buy execution reserves $5", type(b1) == "function" and (tonumber(G.NEURO.reserved_dollars) or 0) == 5)
  local b2, e2 = H("buy_from_shop")({ area = "shop_jokers", index = 2 })
  check("second rapid buy rejected (reserved-aware)", b2 == nil and ActionResult.is_error(e2))
  G.NEURO._reservation_epoch = (tonumber(G.NEURO._reservation_epoch) or 0) + 1
  G.NEURO.reserved_dollars = 5
  if queued[2] and queued[2].func then queued[2].func() end
  check("stale purchase event does not release a new shop reservation", G.NEURO.reserved_dollars == 5)
  G.E_MANAGER, _G.Event = saved_manager, saved_Event

  G.GAME.bankrupt_at = -20
  G.GAME.dollars = 0; G.NEURO.reserved_dollars = 0
  G.shop_jokers = { cards = { shop_item(5) } }
  check("Credit Card allows buying into debt (floor -$20)", type(H("buy_from_shop")({ area = "shop_jokers", index = 1 })) == "function")
  G.NEURO.reserved_dollars = 0
  G.shop_jokers = { cards = { shop_item(25) } }
  local b3, e3 = H("buy_from_shop")({ area = "shop_jokers", index = 1 })
  check("Credit Card caps debt at -$20 ($25 rejected)", b3 == nil and ActionResult.is_error(e3))

  G.jokers = { cards = {} }; G.NEURO.reserved_dollars = 0
end

do
  local DF = require("facts.debuff_facts")
  local d1 = card("5", "Hearts"); d1.debuff = true
  local d2 = card("5", "Spades"); d2.debuff = true
  local ok3 = card("9", "Clubs")
  check("debuff_facts.count", DF.count({ d1, d2, ok3 }) == 2)
  check("debuff_facts.all_debuffed true", DF.all_debuffed({ d1, d2 }) == true)
  check("debuff_facts.all_debuffed false (mixed)", DF.all_debuffed({ d1, ok3 }) == false)
end

do
  local CtxHand = require("context.ctx_hand")
  mock_state("Normal", "SELECTING_HAND")

  local ed = card("A", "Spades"); ed.edition = { name = "Foil" }
  G.playing_cards = nil
  G.hand = { cards = { ed, card("2", "Hearts") } }
  G.deck = { cards = {} }
  local cm = tostring(CtxHand.deck_modifiers_section())
  check("card modifiers report a per-card edition", cm:find("Foil", 1, true) ~= nil, cm)
  check("and name the fallback scope honestly when playing_cards is unpopulated",
    cm:find("hand + draw pile", 1, true) ~= nil, cm)

  local ed2 = card("K", "Diamonds"); ed2.edition = { name = "Polychrome" }
  G.playing_cards = { ed2, card("3", "Clubs") }
  G.hand = { cards = { card("2", "Hearts") } }
  G.deck = { cards = {} }
  local cm2 = tostring(CtxHand.deck_modifiers_section())
  check("card modifiers scan the full deck (playing_cards), not just hand+draw",
    cm2:find("Polychrome", 1, true) ~= nil and cm2:find("full deck", 1, true) ~= nil, cm2)
  G.playing_cards = nil
end

do
  local DeckFacts = require("facts.deck_facts")
  G.P_CENTERS = { b_red = { key = "b_red", loc_txt = { name = "Czerwona Talia" } } }
  local desc = DeckFacts.describe_deck({ key = "b_red" })
  check("deck info resolves by key under a non-English display name",
    desc ~= nil and desc:find("discard", 1, true) ~= nil, tostring(desc))
  G.P_CENTERS = nil
end

do
  local FH = require("force.force_helpers")
  G.NEURO.last_failed_action = nil; G.NEURO.last_failed_reason = nil
  check("warning empty with no failure", FH.failed_action_warning() == "")
  G.NEURO.last_failed_action = "use_card"
  G.NEURO.last_failed_reason = "the consumable could not be used"
  local w = FH.failed_action_warning()
  check("warning names the action", w:find("use_card") ~= nil, w)
  check("warning carries last_failed_reason", w:find("the consumable could not be used") ~= nil, w)

  mock_state("Small blind selectable", "BLIND_SELECT")
  local okb, rb = pcall(require("force.force_blind_select").build, "")
  check("BLIND_SELECT force prepends failure warning",
    okb and type(rb) == "table" and tostring(rb.query):find("use_card") ~= nil, okb and rb and rb.query)

  G.GAME.pack_choices = 1
  G.pack_cards = { cards = { card("2", "Hearts") } }
  local okp, rp = pcall(require("force.force_pack").build, "", "TAROT_PACK")
  check("PACK force prepends failure warning",
    okp and type(rp) == "table" and tostring(rp.query):find("Previous action rejected") ~= nil, okp and rp and rp.query)
  G.GAME.pack_choices = nil; G.pack_cards = nil
  G.NEURO.last_failed_action = nil; G.NEURO.last_failed_reason = nil
end

do
  local Router = require("force.force_router")
  local TG = require("core.transition_guard")
  mock_state("BUFFOON_PACK variant", "BUFFOON_PACK")
  G.jokers = { cards = {} }
  TG.reset(); Router._guard_defer_at = nil
  G.GAME.STOP_USE = 0
  local f0 = D.get_force_for_state("BUFFOON_PACK")
  check("pack offers use_card once settled (STOP_USE=0)", f0 and has(f0.actions or {}, "use_card"),
    f0 and table.concat(f0.actions or {}, ","))

  TG.reset(); Router._guard_defer_at = nil
  G.GAME.STOP_USE = 4
  local f1 = D.get_force_for_state("BUFFOON_PACK")
  local skip_only = f1 and f1.actions and #f1.actions == 1 and f1.actions[1] == "skip_booster"
  check("pack NEVER ships skip-only while use_card settles (defers instead)", not skip_only,
    f1 and table.concat(f1.actions or {}, ",") or "nil (deferred)")
  G.GAME.STOP_USE = 0; TG.reset(); Router._guard_defer_at = nil
end

do
  local Router = require("force.force_router")
  local TG = require("core.transition_guard")
  local jk = function(k) return { ability = { set = "Joker", name = k }, config = { center = { key = k, set = "Joker" } }, sell_cost = 3 } end
  mock_state("BUFFOON_PACK variant", "BUFFOON_PACK")
  G.jokers = { cards = { jk("j_a"), jk("j_b"), jk("j_c"), jk("j_d"), jk("j_e") }, config = { card_limit = 5 } }
  TG.reset(); Router._guard_defer_at = nil
  G.GAME.STOP_USE = 0
  local f0 = D.get_force_for_state("BUFFOON_PACK")
  check("settled full-slot pack offers sell_card", f0 and has(f0.actions or {}, "sell_card"),
    f0 and table.concat(f0.actions or {}, ",") or "nil")
  TG.reset(); Router._guard_defer_at = nil
  G.GAME.STOP_USE = 4
  local f1 = D.get_force_for_state("BUFFOON_PACK")
  local sell_only = f1 and f1.actions and #f1.actions == 1 and f1.actions[1] == "sell_card"
  check("pack NEVER ships sell-only while use_card settles (defers)", not sell_only,
    f1 and table.concat(f1.actions or {}, ",") or "nil (deferred)")
  G.GAME.STOP_USE = 0; TG.reset(); Router._guard_defer_at = nil
end

do
  local Router = require("force.force_router")
  local TG = require("core.transition_guard")
  local function move_tokens(q)
    local seg = q:match("Your move:%s*(.-)%.%s*$") or q:match("Your move:%s*(.*)$") or ""
    local names = {}
    for bit in (seg .. ";"):gmatch("([^;]+);") do
      local nm = bit:match("^%s*([%a_]+)")
      if nm then names[#names + 1] = nm end
    end
    return names
  end
  mock_state("Normal", "SHOP")
  TG.reset(); Router._guard_defer_at = nil
  G.CONTROLLER = nil; G.GAME.STOP_USE = 0
  local f_open = D.get_force_for_state("SHOP")
  local adv_open = move_tokens((f_open or {}).query or "")
  local aset = {}; for _, n in ipairs((f_open or {}).actions or {}) do aset[n] = true end
  local subset_ok = true
  for _, n in ipairs(adv_open) do if not aset[n] then subset_ok = false break end end
  check("advertised move list is subset of accepted actions (open shop)", #adv_open > 0 and subset_ok,
    table.concat(adv_open, ",") .. " vs " .. table.concat((f_open or {}).actions or {}, ","))

  TG.reset(); Router._guard_defer_at = nil
  G.CONTROLLER = { locks = { toggle_shop = true } }
  local f_lock = D.get_force_for_state("SHOP")
  local adv_lock = move_tokens((f_lock or {}).query or "")
  check("guard-locked toggle_shop not advertised", not has(adv_lock, "toggle_shop"),
    table.concat(adv_lock, ","))
  check("guard-locked toggle_shop not in accepted set", not has((f_lock or {}).actions or {}, "toggle_shop"),
    table.concat((f_lock or {}).actions or {}, ","))
  G.CONTROLLER = nil; TG.reset(); Router._guard_defer_at = nil
end

do
  local HH = require("handlers.hand_handlers")
  local CA = require("facts.card_area_util")
  local HF = require("facts.hand_facts")

  _G.SMODS = { four_fingers = function(t) return (t == "flush" or t == "straight") and 4 or 5 end }
  mock_state("Normal", "SELECTING_HAND")
  local hh = { card("2", "Hearts"), card("5", "Hearts"), card("9", "Hearts"), card("K", "Hearts"), card("3", "Clubs") }
  G.hand = { cards = hh, highlighted = {}, config = { card_limit = 8 } }
  local shape = HF.shape(G.hand.cards)
  check("Four Fingers makes a 4-suit a Flush (not Near)", shape.flush_ready and not shape.near_flush)
  _G.SMODS = nil
  local shape2 = HF.shape(G.hand.cards)
  check("default (no four_fingers) 4-suit stays Near Flush", shape2.near_flush and not shape2.flush_ready)

  mock_state("Normal", "SELECTING_HAND")
  local cc = { card("2", "Hearts"), card("3", "Hearts"), card("4", "Hearts"), card("5", "Hearts") }
  G.hand = { cards = cc, highlighted = { cc[1], cc[2], cc[3], cc[4] } }
  G.GAME.current_round.hands_left = 3
  G.GAME.blind = { debuff = { h_size_le = 3 } }
  -- Spend the weak budget so the accepted play is not also paused for weak-hand advice.
  G.NEURO.weak_fired_serial = tonumber(G.NEURO.decision_serial) or 0
  local fn_over, err_over = HH.handle_play_hand({ indices = { 1, 2, 3, 4 } })
  check("h_size_le rejects oversized play", fn_over == nil and ActionResult.is_error(err_over) and action_error(err_over):find("at most 3") ~= nil, err_over)
  check("h_size_le allows a play within the limit", type(HH.handle_play_hand({ indices = { 1, 2, 3 } })) == "function")

  G.GAME.blind = nil

  G.hand = { cards = {}, config = { highlighted_limit = 8 } }
  for i = 1, 9 do G.hand.cards[i] = card("2", "Hearts") end
  local _, f14_err = CA.validate_hand_indices({ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, 9)
  check("highlighted_limit>5 honored", tostring(f14_err):find("at most 8", 1, true) ~= nil, f14_err)
  G.hand = nil
  local _, f14_def = CA.validate_hand_indices({ 1, 2, 3, 4, 5, 6, 7 }, 7)
  check("default cap 5 with no hand config", tostring(f14_def):find("at most 5", 1, true) ~= nil, f14_def)

  check("blind_select_signature removed", require("force.force_helpers").blind_select_signature == nil)

  local LD = require("util.level_delta")
  local hands0 = { Pair = { level = 1 }, Flush = { level = 1 } }
  local msg0, snap0 = LD.brief(hands0, nil), LD.snapshot(hands0)
  check("first snapshot emits nothing", msg0 == nil and snap0.Pair == 1)
  local hands1 = { Pair = { level = 3 }, Flush = { level = 1 } }
  local msg1, snap1 = LD.brief(hands1, snap0), LD.snapshot(hands1)
  check("level raise reported once", msg1 ~= nil and msg1:find("Pair leveled up from 1 to 3", 1, true) ~= nil, msg1)
  local msg2 = LD.brief(hands1, snap1)
  check("unchanged levels stay silent", msg2 == nil)
end

do
  local CardUtil = require("facts.card_util")
  local CtxEconomy = require("facts.economy_facts")
  local HandFacts = require("facts.hand_facts")
  local DebuffFacts = require("facts.debuff_facts")

  check("edition_name Foil (flag)", CardUtil.edition_name({ foil = true }) == "Foil")
  check("edition_name Negative (flag)", CardUtil.edition_name({ negative = true }) == "Negative")
  check("edition_name Polychrome (flag)", CardUtil.edition_name({ polychrome = true }) == "Polychrome")
  check("edition_name nil when none", CardUtil.edition_name({}) == nil)
  check("enhancement_name m_bonus", CardUtil.enhancement_name("m_bonus") == "Bonus")
  check("enhancement_short m_bonus", CardUtil.enhancement_short("m_bonus") == "Bonus(+30c)")
  check("seal_name Red", CardUtil.seal_name("Red") == "Red")

  mock_state("Normal", "SHOP")
  G.GAME.dollars = 10; G.NEURO.reserved_dollars = 3; G.GAME.bankrupt_at = 0
  check("spend_floor $0 no credit", CtxEconomy.spend_floor() == 0)
  check("spendable = dollars-reserved-floor", CtxEconomy.spendable() == 7)
  G.GAME.bankrupt_at = -20
  check("spend_floor -20 with Credit Card", CtxEconomy.spend_floor() == -20)
  check("spendable extends by credit", CtxEconomy.spendable() == 27)
  G.GAME.bankrupt_at = 0
  G.jokers = { cards = { { config = { center = { key = "j_credit_card" } }, ability = { name = "Credit Card" } } } }
  check("spend_floor detects live spawned Credit Card", CtxEconomy.spend_floor() == -20)
  G.jokers = nil

  do
    local CtxBlind = require("context.ctx_blind")
    mock_state("Normal", "SELECTING_HAND")
    G.GAME.dollars = -2; G.GAME.bankrupt_at = 0
    local bl = CtxBlind.blind_line() or ""
    check("blind_line: below-floor balance names it as a boss penalty, not a purchase",
      bl:find("-$2 in the bank", 1, true) ~= nil
      and bl:find("spend floor", 1, true) == nil
      and bl:find("below floor from a boss blind's money penalty, not a purchase", 1, true) ~= nil, bl)

    mock_state("Normal", "SELECTING_HAND")
    G.GAME.dollars = 12; G.GAME.bankrupt_at = 0
    local bl2 = CtxBlind.blind_line() or ""
    check("blind_line: normal balance has no below-floor clause",
      bl2:find("below floor", 1, true) == nil, bl2)
    check("blind_line: a default floor of zero is not quoted",
      bl2:find("spend floor", 1, true) == nil, bl2)

    G.GAME.bankrupt_at = -20
    local bl3 = CtxBlind.blind_line() or ""
    check("blind_line: a real debt floor is still quoted",
      bl3:find("spend floor -$20", 1, true) ~= nil, bl3)
    G.GAME.bankrupt_at = 0
  end
  G.GAME.dollars = -8; G.GAME.interest_amount = 1; G.GAME.interest_cap = 25
  check("interest never negative under debt", CtxEconomy.calc_interest(G.GAME.dollars) == 0)
  G.GAME.dollars = 10

  local five_h = { card("2","Hearts"), card("5","Hearts"), card("9","Hearts"), card("K","Hearts"), card("3","Hearts") }
  local sh5 = HandFacts.shape(five_h)
  check("5-suit is flush_ready (default thr 5)", sh5.flush_ready and not sh5.near_flush)
  local four_h = { card("2","Hearts"), card("5","Hearts"), card("9","Hearts"), card("K","Hearts"), card("3","Clubs") }
  local sh4 = HandFacts.shape(four_h)
  check("4-suit is near_flush (default thr 5)", sh4.near_flush and not sh4.flush_ready)

  local gap = { card("2","Hearts"), card("4","Clubs"), card("6","Spades"), card("8","Diamonds"), card("10","Hearts") }
  _G.SMODS = { shortcut = function() return true end }
  local sh_sc = HandFacts.shape(gap)
  check("Shortcut makes 2-4-6-8-10 straight_ready", sh_sc.straight_ready, "max_run=" .. tostring(sh_sc.max_run))
  _G.SMODS = nil
  local sh_no = HandFacts.shape(gap)
  check("without Shortcut, 2-4-6-8-10 is neither straight nor near", not sh_no.straight_ready and not sh_no.near_straight, "max_run=" .. tostring(sh_no.max_run))

  mock_state("Normal", "SELECTING_HAND")
  G.GAME.hands = {
    ["Flush"]    = { visible = true, level = 3, chips = 35, mult = 7 },
    ["Pair"]     = { visible = true, level = 1, chips = 10, mult = 2 },
    ["Straight"] = { visible = false, level = 1, chips = 30, mult = 4 },
  }
  local rows = HandFacts.levels()
  check("levels() drops non-visible", #rows == 2)
  check("levels() sorted play-order (Pair before Flush)", rows[1].name == "Pair" and rows[2].name == "Flush")

  check("boss_debuff_text via engine method",
    DebuffFacts.boss_debuff_text({ get_loc_debuff_text = function() return "No face cards" end }) == "No face cards")
  check("boss_debuff_text via loc_txt fallback",
    DebuffFacts.boss_debuff_text({ loc_txt = { text = { "a", "b" } } }) == "a b")
  check("boss_debuff_text empty when nothing", DebuffFacts.boss_debuff_text({}) == "")
end

do
  local CardUtil = require("facts.card_util")
  local CtxEconomy = require("facts.economy_facts")
  local FH = require("force.force_helpers")

  G.TIMERS = { REAL = 42 }
  check("Utils.now prefers G.TIMERS.REAL", Utils.now() == 42)
  G.TIMERS = nil

  G.NEURO.last_failed_action = nil; G.NEURO.last_failed_reason = nil; G.NEURO.last_failed_at = nil
  FH.record_failure("buy_from_shop", "the purchase could not be completed")
  check("record_failure sets action", G.NEURO.last_failed_action == "buy_from_shop")
  check("record_failure sets reason (was dropped)", G.NEURO.last_failed_reason == "the purchase could not be completed")
  check("record_failure sets at", type(G.NEURO.last_failed_at) == "number")
  G.NEURO.last_failed_action = nil; G.NEURO.last_failed_reason = nil; G.NEURO.last_failed_at = nil

  mock_state("Normal", "SHOP")
  G.GAME.dollars = 10; G.NEURO.reserved_dollars = 8; G.jokers = { cards = {}, config = { card_limit = 5 } }
  local cheap = { cost = 3, config = { center = { set = "Joker" } } }
  check("reserved dollars block a nominally-cheap buy", CtxEconomy.item_afford_status(cheap, "shop_jokers").ok == false)
  G.NEURO.reserved_dollars = 0
  check("affordable + space => ok", CtxEconomy.item_afford_status(cheap, "shop_jokers").ok == true)
  G.jokers = { cards = { {}, {}, {}, {}, {} }, config = { card_limit = 5 } }
  check("no joker slot => not ok even if affordable", CtxEconomy.item_afford_status(cheap, "shop_jokers").ok == false)
  G.jokers = nil

  check("edition_tag Foil", CardUtil.edition_tag({ foil = true }) == "Foil(+50c)")
  check("edition_tag Negative (was dropped)", CardUtil.edition_tag({ negative = true }) == "Negative(free_slot)")
  check("edition_tag empty when none", CardUtil.edition_tag({}) == "")

  check("hand_visible true", require("facts.hand_facts").hand_visible({ visible = true }) == true)
  check("hand_visible nil => false", require("facts.hand_facts").hand_visible({}) == false)

  local CtxHelpers = require("context.ctx_helpers")
  local ep = CtxHelpers.effect_parts({ x_mult = 2, h_mult = 4, t_mult = 3 })
  check("effect_parts formats x_mult", ep[1] == "x2 Mult")
  check("effect_parts t_mult => hand-type conditional, not per-trigger", table.concat(ep, "|"):find("+3 Mult %(conditional%)") ~= nil and table.concat(ep, "|"):find("/trigger") == nil)
  check("effect_parts skips identity x_mult=1", #CtxHelpers.effect_parts({ x_mult = 1 }) == 0)

  G.NEURO.force_inflight = false; G.NEURO.force_window = nil
  require("core.force_state").arm("X", { "play_hand" }, { play_hand = true }, 1)
  FH.clear_force_state()
  check("clear_force_state clears inflight", G.NEURO.force_inflight == false
    and G.NEURO.force_state == nil and G.NEURO.force_sent_at == nil
    and G.NEURO.force_window.phase == "ended")

  local mn, mx = CardUtil.consumable_target_range({ ability = { consumeable = { max_highlighted = 2 } } })
  check("target range min defaults to 1", mn == 1 and mx == 2)
  check("no consumeable => nil range", select("#", CardUtil.consumable_target_range({})) >= 1 and (CardUtil.consumable_target_range({})) == nil)

  G.jokers = { cards = { {}, {} }, config = { card_limit = 5 } }
  local jss = CardUtil.joker_slot_status()
  check("joker_slot_status", jss.count == 2 and jss.limit == 5 and jss.full == false)
  G.jokers = nil

  check("NON_PROGRESS includes a stated-intent action", require("core.action_policy").NON_PROGRESS.set_plan == true)
  check("NON_PROGRESS includes a non-advancing action", require("core.action_policy").NON_PROGRESS.set_joker_order == true)

  G.NEURO.once_serials = nil
  check("once_until first true", FH.once_until("t", 1) == true)
  check("once_until same epoch false", FH.once_until("t", 1) == false)
  check("once_until new epoch true", FH.once_until("t", 2) == true)

  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("5","Hearts"), card("5","Spades") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 3
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  local list16, set16 = FH.collect_actions({ "sell_card", "play_hand" })
  check("collect_actions excludes invalid (no jokers, nothing to sell)", set16.sell_card ~= true)
  check("collect_actions returns exactly {play_hand}",
    #list16 == 1 and list16[1] == "play_hand" and set16.play_hand == true,
    table.concat(list16, ","))
  G.jokers = nil

  local DeckFacts = require("facts.deck_facts")
  check("DECK_INFO has curated Plasma formula", (DeckFacts.DECK_INFO["Plasma Deck"] or ""):find("chips%+mult") ~= nil)
  check("short_desc from config flags", (DeckFacts.short_desc({ config = { discards = 1 } }) or ""):find("discard") ~= nil)

  local missing, algebra, toolong = {}, {}, {}
  for name in pairs(DeckFacts.DECK_INFO) do
    local hud = DeckFacts.HUD_INFO[name]
    if not hud then missing[#missing + 1] = name
    else
      if hud:find("[%(%)%^=]") or hud:find("floor", 1, true) then algebra[#algebra + 1] = name end
      if #hud > 56 then toolong[#toolong + 1] = name .. "(" .. #hud .. ")" end
    end
  end
  check("every deck the model knows has a HUD phrasing too",
    #missing == 0, table.concat(missing, ", "))
  check("no HUD deck line carries a formula",
    #algebra == 0, table.concat(algebra, ", "))
  check("HUD deck lines stay one clause long",
    #toolong == 0, table.concat(toolong, ", "))
  local blank, algebra2 = {}, {}
  for key, name in pairs({ b_red = "Red Deck", b_plasma = "Plasma Deck",
    b_checkered = "Checkered Deck", b_zodiac = "Zodiac Deck", b_erratic = "Erratic Deck" }) do
    local hud = DeckFacts.describe_deck_hud({ key = key })
    if type(hud) ~= "string" or hud == "" then blank[#blank + 1] = key
    else
      if hud ~= DeckFacts.HUD_INFO[name] then blank[#blank + 1] = key .. "(wrong text)" end
      if hud:find("floor", 1, true) then algebra2[#algebra2 + 1] = key end
    end
  end
  check("a back known only by its key still describes itself",
    #blank == 0, table.concat(blank, ", "))
  check("the overlay's register never carries the model's algebra",
    #algebra2 == 0, table.concat(algebra2, ", "))
end

do
  local DF = require("facts.debuff_facts")
  local d1 = card("5", "Hearts"); d1.debuff = true
  local d2 = card("5", "Spades"); d2.debuff = true
  local ok3 = card("9", "Clubs")
  check("all_debuffed nested: all-debuffed group detected", DF.all_debuffed({ { d1, d2 } }) == true)
  check("all_debuffed nested: mixed group not flagged", DF.all_debuffed({ { d1, ok3 } }) == false)
  check("all_debuffed nested: multiple groups all debuffed", DF.all_debuffed({ { d1 }, { d2 } }) == true)
end

do
  local H = D.get_action_handler
  mock_state("Normal", "SHOP")
  G.GAME.dollars = 20; G.NEURO.reserved_dollars = 0
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  local called, captured_id, use_called
  G.FUNCS.buy_from_shop = function(e) called = true; captured_id = e.config.id end
  G.FUNCS.use_card = function(e) use_called = true end

  local voucher = { cost = 5, ability = { set = "Voucher" }, config = { center = { key = "v_overstock" } } }
  G.shop_vouchers = { cards = { voucher } }
  local first = H("buy_from_shop")({ area = "shop_vouchers", index = 1 })
  check("voucher buy asks for confirmation first", type(first) ~= "function", type(first))
  local cv = H("buy_from_shop")({ area = "shop_vouchers", index = 1 })
  check("voucher buy -> exec closure", type(cv) == "function")
  if cv then pcall(cv) end
  check("voucher routed via use_card, not buy_from_shop", use_called == true and called == nil)

  use_called = nil
  G.NEURO.reserved_dollars = 0
  local pack = { cost = 4, ability = { set = "Booster" }, config = { center = { key = "p_arcana" } } }
  G.shop_booster = { cards = { pack } }
  local cb = H("buy_from_shop")({ area = "shop_booster", index = 1 })
  if cb then pcall(cb) end
  check("booster routed via use_card, not buy_from_shop", use_called == true and called == nil)

  called, captured_id = nil, nil
  G.NEURO.reserved_dollars = 0
  local plain = card("A", "Spades"); plain.cost = 5
  G.shop_jokers = { cards = { plain } }
  local cj = H("buy_from_shop")({ area = "shop_jokers", index = 1 })
  if cj then pcall(cj) end
  check("plain buy carries no buy_and_use id", called == true and captured_id == nil)

  G.NEURO.reserved_dollars = 0
  local tarot = { cost = 5, ability = { set = "Tarot", consumeable = { max_highlighted = 1 } }, config = { center = { key = "c_tarot" } } }
  G.shop_jokers = { cards = { tarot } }
  local ct, et = H("buy_from_shop")({ area = "shop_jokers", index = 1, use = true })
  check("hand-targeting consumable use=true rejected", ct == nil and ActionResult.is_error(et) and action_error(et):find("targets hand") ~= nil, et)

  called, captured_id = nil, nil
  local planet = { cost = 5, ability = { set = "Planet", consumeable = {} }, config = { center = { key = "c_pluto" } } }
  G.shop_jokers = { cards = { planet } }
  local cp = H("buy_from_shop")({ area = "shop_jokers", index = 1, use = true })
  check("Planet use=true accepted", type(cp) == "function")
  if cp then pcall(cp) end
  check("Planet use=true routed with id=buy_and_use", called == true and captured_id == "buy_and_use")
  G.FUNCS.buy_from_shop = nil
  G.FUNCS.use_card = nil
  G.NEURO.reserved_dollars = 0
end

do
  local H = D.get_action_handler
  mock_state("Small blind selectable", "BLIND_SELECT")
  G.P_BLINDS = { bl_small = { name = "Small Blind" }, bl_custom_small = { name = "Custom Small" } }
  G.GAME.round_resets.blind_choices = { Small = "bl_custom_small" }
  local captured
  G.FUNCS.select_blind = function(e) captured = e.config.ref_table end
  local c1 = H("select_blind")({ blind = "small" })
  local ok1, r1 = pcall(c1)
  check("select_blind resolves blind_choices override", type(c1) == "function" and ok1 and captured == G.P_BLINDS.bl_custom_small, r1)
  check("select_blind names the custom blind", ok1 and type(r1) == "string" and r1:find("Custom Small") ~= nil, r1)
  captured = nil
  G.GAME.round_resets.blind_choices = nil
  local c2 = H("select_blind")({ blind = "small" })
  if c2 then pcall(c2) end
  check("select_blind falls back to bl_small", captured == G.P_BLINDS.bl_small)
  G.FUNCS.select_blind = nil
  G.P_BLINDS = nil
end

do
  local Enforce = require("core.enforce")
  local H = D.get_action_handler
  mock_state("Small blind selectable", "BLIND_SELECT")
  G.STATES = { BLIND_SELECT = 4 }; G.STATE = 4
  local saved_ante = G.GAME.round_resets.ante
  G.P_BLINDS = { bl_ox = { name = "The Ox" } }
  G.GAME.round_resets.blind_choices = { Boss = "bl_ox" }
  G.GAME.round_resets.blind_states = { Boss = "Select" }
  G.GAME.round_resets.ante = 3
  G.GAME.blind_on_deck = "Boss"
  G.NEURO.blind_plan_ok = false
  G.NEURO.force_inflight = false
  G.NEURO.force_window = nil
  require("core.force_state").arm("BLIND_SELECT", { "select_blind" }, { select_blind = true }, 1)
  local DecisionWindow = require("core.decision_window")
  DecisionWindow.reset_field("boss_review")
  local ok1, e1 = Enforce.pre_action(nil, "select_blind")
  local captured
  G.FUNCS.select_blind = function(e) captured = e.config.ref_table end
  local exec = ok1 and H("select_blind")({ blind = "boss" })
  if type(exec) == "function" then pcall(exec) end
  check("inline blind plan removes separate boss-review bounce",
    ok1 == true and e1 == nil and type(exec) == "function" and captured == G.P_BLINDS.bl_ox, e1)
  G.FUNCS.select_blind = nil; G.P_BLINDS = nil
  G.GAME.round_resets.blind_choices = nil; G.GAME.round_resets.blind_states = nil
  G.GAME.round_resets.ante = saved_ante
  G.GAME.blind_on_deck = nil; G.NEURO.blind_plan_ok = nil
  G.NEURO.force_inflight = nil; G.NEURO.force_state = nil; G.NEURO.force_window = nil
  DecisionWindow.reset_field("blind_plan")
  DecisionWindow.reset_field("boss_review")
end

do
  local H = D.get_action_handler
  mock_state("Small blind selectable", "BLIND_SELECT")
  G.GAME.round_resets.blind_states = { Small = "Select" }
  G.GAME.round_resets.blind_tags = { Small = "tag_handy", Big = "tag_handy" }
  G.GAME.blind_on_deck = "Small"
  G.blind_select_opts = { small = { get_UIE_by_ID = function() return { config = { ref_table = {} } } end } }
  local skipped = false
  G.FUNCS.skip_blind = function() skipped = true end
  local c1 = H("skip_blind")({})
  if type(c1) == "function" then pcall(c1) end
  check("skip executes immediately (no think gate)", type(c1) == "function" and skipped == true)
  G.FUNCS.skip_blind = nil; G.blind_select_opts = nil
  G.GAME.round_resets.blind_states = nil; G.GAME.blind_on_deck = nil
end

do
  local Enforce = require("core.enforce")
  G.STATES = { SHOP = 5 }; G.STATE = 5
  G.GAME = G.GAME or {}
  G.NEURO.force_inflight = false
  G.NEURO.force_window = nil
  require("core.force_state").arm("SHOP", { "toggle_shop" }, { toggle_shop = true }, 1)
  local DW_ot = require("core.decision_window")
  DW_ot.reset_field("order_think")
  local function roster(specs)
    local cards = {}
    for _, s in ipairs(specs) do
      cards[#cards + 1] = { config = { center = { key = s[1] } }, ability = s[2] }
    end
    return { cards = cards, config = { card_limit = 5 } }
  end
  G.jokers = roster({ { "j_joker", { mult = 4 } }, { "j_greedy_joker", { mult = 3 } } })
  check("joker-order think stays silent on an all-additive roster (order is a no-op)",
    Enforce.pre_action(nil, "toggle_shop") == true)
  DW_ot.reset_field("order_think")
  G.jokers = roster({ { "j_scary_face", { set = "Joker", bonus = 50 } }, { "j_cavendish", { x_mult = 3 } } })
  check("joker-order think stays silent on chips+xMult (chips position is irrelevant)",
    Enforce.pre_action(nil, "toggle_shop") == true)
  DW_ot.reset_field("order_think")
  G.jokers = roster({ { "j_joker", { mult = 4 } }, { "j_cavendish", { x_mult = 3 } } })
  local ok1, msg1 = Enforce.pre_action(nil, "toggle_shop")
  check("joker-order think fires when an xMult sits with additive jokers",
    ok1 == false and type(msg1) == "string" and msg1:find("Your joker lineup changed", 1, true) ~= nil, msg1)
  G.jokers = roster({ { "j_cavendish", { x_mult = 3 } }, { "j_joker", { mult = 4 } } })
  check("joker-order think silent on reorder-only (composition unchanged, repeat commits)",
    Enforce.pre_action(nil, "toggle_shop") == true)
  G.jokers = roster({ { "j_joker", { mult = 4 } }, { "j_blueprint", {} } })
  check("joker-order think re-fires when the joker set changes",
    Enforce.pre_action(nil, "toggle_shop") == false)
  G.jokers = nil
  G.NEURO.force_inflight = nil; G.NEURO.force_state = nil; G.NEURO.force_window = nil
  require("core.decision_window").reset_field("order_think")
  G.STATES = nil; G.STATE = nil
end

do
  mock_state("Normal", "SHOP")
  G.STATES = { SHOP = 5 }; G.STATE = 5
  G.shop = G.shop or {}
  G.jokers = { cards = {
    { ability = { name = "Joker" }, config = { center = { key = "j_joker" } }, states = {} },
    { ability = { name = "Blueprint" }, config = { center = { key = "j_blueprint" } }, states = {} },
  }, config = { card_limit = 5 } }
  local DecisionWindow = require("core.decision_window")
  DecisionWindow.reset_field("shop_economy")
  DecisionWindow.reset_field("shop_plan_revision")
  DecisionWindow.reset_field("order_think")
  G.NEURO.econ_plan_ok = false
  G.NEURO.shop_plan_revision_required = true
  local results = {}
  local bridge = {
    send_action_result = function(_, _, ok, msg, reason)
      results[#results + 1] = { ok = ok, msg = msg, reason = reason }
    end,
  }
  local function dispatch(id, name, data)
    G.NEURO.force_inflight = false
    G.NEURO.force_window = nil
    require("core.force_state").arm("SHOP", { "set_plan", "set_joker_order", "toggle_shop" }, { set_plan = true, set_joker_order = true, toggle_shop = true }, 1)
    D.handle_message({ command = "action", data = { id = id, name = name, data = data or {} } }, bridge)
  end
  local toggled = false
  G.FUNCS.toggle_shop = function() toggled = true end
  require("tests.helpers").stage_registered(nil, { "toggle_shop", "set_plan", "set_joker_order" })
  dispatch("shop-revision-leave-early", "toggle_shop")
  local toggled_early = toggled
  dispatch("shop-revision-partial", "set_plan", { money_plan = "hold enough for interest" })
  dispatch("shop-revision-full", "set_plan", {
    hand_plan = "play the upgraded hand",
    build_plan = "two jokers now, seek xMult",
    money_plan = "hold enough for interest",
  })
  dispatch("tw05-order", "set_joker_order", { from_index = 1, to_index = 2 })
  dispatch("tw05-leave", "toggle_shop")
  check("shop exit requires a complete post-shop plan revision",
    #results == 5 and results[1].ok == true and results[1].reason == "CONFIRMATION_REQUIRED"
      and toggled_early == false and results[2].ok == false
      and results[3].ok == true and results[4].ok == true
      and results[5].ok == true and toggled == true,
    results[1] and (tostring(results[1].reason) .. " / " .. tostring(results[1].msg)))
  G.FUNCS.toggle_shop = nil; G.shop = nil; G.jokers = nil
  G.NEURO.force_inflight = nil; G.NEURO.force_state = nil; G.NEURO.force_window = nil
  G.NEURO.econ_plan_ok = nil; G.NEURO.shop_plan_revision_required = nil
  G.STATES = nil; G.STATE = nil
  DecisionWindow.reset_field("shop_economy")
  DecisionWindow.reset_field("shop_plan_revision")
  DecisionWindow.reset_field("order_think")
end

do
  local Enforce = require("core.enforce")
  Enforce.reset_run_state()
  mock_state("Normal", "SHOP")
  G.STATES = { SHOP = 5 }; G.STATE = 5
  G.shop = G.shop or {}
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.NEURO.shop_plan_revision_required = nil -- no missing-field branch, only the fully-empty one
  G.NEURO.plan = nil
  local results = {}
  local bridge = {
    send_action_result = function(_, _, ok, msg, reason)
      results[#results + 1] = { ok = ok, msg = msg, reason = reason }
    end,
  }
  require("tests.helpers").stage_registered(nil, { "set_plan" })
  for i = 1, 4 do
    G.NEURO.force_inflight = false
    G.NEURO.force_window = nil
    require("core.force_state").arm("SHOP", { "set_plan" }, { set_plan = true }, 1)
    D.handle_message({ command = "action", data = { id = "n3f7-" .. i, name = "set_plan", data = {} } }, bridge)
  end
  check("four set_plan|{} rejections are recorded",
    #results == 4, tostring(#results))
  check("the first three set_plan|{} rejections carry PRECONDITION_FAILED and success=false",
    results[1].ok == false and results[1].reason == "PRECONDITION_FAILED"
      and results[2].ok == false and results[2].reason == "PRECONDITION_FAILED"
      and results[3].ok == false and results[3].reason == "PRECONDITION_FAILED",
    string.format("%s/%s %s/%s %s/%s",
      tostring(results[1].ok), tostring(results[1].reason),
      tostring(results[2].ok), tostring(results[2].reason),
      tostring(results[3].ok), tostring(results[3].reason)))
  check("the fourth rejection is acknowledged after the rejection streak threshold",
    results[4].ok == true and results[4].reason == "PRECONDITION_FAILED",
    tostring(results[4].ok) .. "/" .. tostring(results[4].reason))

  G.shop = nil; G.jokers = nil
  G.NEURO.force_inflight = nil; G.NEURO.force_state = nil; G.NEURO.force_window = nil
  G.NEURO.shop_plan_revision_required = nil
  G.STATES = nil; G.STATE = nil
  Enforce.reset_run_state()
end

do
  local J = require("util.neuro_json")
  local ok_arr = pcall(J.decode, '[1,null,3]')
  check("null in array errors", ok_arr == false)
  local ok_obj, obj = pcall(J.decode, '{"a":null}')
  check("null object value drops the key", ok_obj and type(obj) == "table" and obj.a == nil and next(obj) == nil)
  check("dense array encodes as array", J.encode({ 1, 2, 3 }) == "[1,2,3]")
  local rt = J.decode(J.encode({ 10, 20, 30 }))
  check("dense array round-trips as array", type(rt) == "table" and #rt == 3 and rt[1] == 10 and rt[3] == 30)
  local sp = J.encode({ [1] = "a", [3] = "c" })
  check("sparse integer table encodes as object", sp:sub(1, 1) == "{" and sp:find('"3":"c"', 1, true) ~= nil, sp)
end

do
  local Enforce = require("core.enforce")
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("5", "Hearts"), card("5", "Spades") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 3
  G.NEURO.force_inflight = nil; G.NEURO.force_state = nil; G.NEURO.force_window = nil
  G.STATES = { SELECTING_HAND = 7 }; G.STATE = 7
  G.jokers = { cards = {
    { sort_id = 901, ability = { set = "Joker", name = "A" }, sell_cost = 1,
      config = { center = { key = "j_a", set = "Joker" } } },
    { sort_id = 902, ability = { set = "Joker", name = "B" }, sell_cost = 1,
      config = { center = { key = "j_b", set = "Joker" } } },
  }, config = { card_limit = 5 } }
  Enforce.post_action(nil, false)
  G.TIMERS = { REAL = 1000 }
  local ok1 = Enforce.pre_action(nil, "set_joker_order")
  check("first spaced attempt passes", ok1 == true)
  local cooldown_denied = 0
  for i = 1, 6 do
    G.TIMERS.REAL = 1000 + i * 0.01
    local ok, err = Enforce.pre_action(nil, "set_joker_order")
    if ok == false and type(err) == "string" and err:find("wait") then cooldown_denied = cooldown_denied + 1 end
  end
  check("rapid retries all cooldown-denied (never repeat-capped)", cooldown_denied == 6)
  G.TIMERS.REAL = 1100
  local ok2 = Enforce.pre_action(nil, "set_joker_order")
  G.TIMERS.REAL = 1200
  local ok3 = Enforce.pre_action(nil, "set_joker_order")
  check("spaced attempts still pass (streak untouched by denials)", ok2 == true and ok3 == true)
  G.TIMERS.REAL = 1300
  local ok4, e4 = Enforce.pre_action(nil, "set_joker_order")
  check("4th committed repeat hits the cap", ok4 == false and type(e4) == "string" and e4:find("repeated") ~= nil, e4)
  Enforce.post_action(nil, true)
  G.TIMERS.REAL = 1400
  local ok5 = Enforce.pre_action(nil, "set_joker_order")
  check("post_action(true) does NOT reset the streak (still capped)", ok5 == false)
  G.TIMERS.REAL = 1500
  check("a different action passes (streak resets on name change)",
    Enforce.pre_action(nil, "discard_hand") == true)
  G.TIMERS.REAL = 1600
  check("original action passes again after the streak-breaker",
    Enforce.pre_action(nil, "set_joker_order") == true)
  G.jokers = nil
  G.TIMERS = nil; G.STATES = nil; G.STATE = nil
end

do
  local HF = require("facts.hand_facts")
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("King", "Hearts"), card("King", "Spades"), card("King", "Clubs"),
    card("4", "Diamonds"), card("8", "Clubs"), card("Queen", "Hearts"), card("Queen", "Diamonds") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2
  local hc = G.hand.cards
  G.FUNCS.get_poker_hand_info = function(_)
    return "Full House", nil, {
      ["Full House"] = { { hc[1], hc[2], hc[3], hc[6], hc[7] } },
      ["Pair"] = { { hc[6], hc[7] } },
    }, { hc[1], hc[2], hc[3], hc[6], hc[7] }, nil
  end
  local s = HF.summary()
  check("ready indices: Full House[1,2,3,6,7]", s:find("Full House[1,2,3,6,7]", 1, true) ~= nil, s:match("Ready:[^%.]*"))
  check("ready indices: Pair[6,7]", s:find("Pair[6,7]", 1, true) ~= nil, s:match("Ready:[^%.]*"))
  local q = (D.get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("force query carries ready indices", q:find("Full House (cards 1, 2, 3, 6, 7)", 1, true) ~= nil)

  local foreign = card("2", "Spades")
  G.FUNCS.get_poker_hand_info = function(_)
    return "Pair", nil, { ["Pair"] = { { hc[6], foreign, hc[7] } } }, { hc[6], hc[7] }, nil
  end
  local ok_f, s2 = pcall(HF.summary)
  check("nested-shape: foreign ref skipped, no crash", ok_f and s2:find("Pair[6,7]", 1, true) ~= nil, tostring(s2))

  G.FUNCS.get_poker_hand_info = nil
  G.hand = { cards = { card("2", "Hearts"), card("5", "Spades"), card("9", "Clubs") }, highlighted = {} }
  local s3 = HF.summary()
  check("no ready hands -> no Ready line, no brackets", s3:find("Ready:") == nil and s3:find("%[") == nil, s3)

  G.hand = { cards = { card("2", "Hearts"), card("5", "Hearts"), card("7", "Hearts"), card("9", "Hearts"), card("King", "Spades") }, highlighted = {} }
  local s4 = HF.summary()
  check("near Flush carries suit + indices", s4:find("near Flush: 4 Hearts keep[1,2,3,4]/other[5]", 1, true) ~= nil, s4:match("Close:[^%.]*"))

  G.hand = { cards = { card("2", "Hearts"), card("3", "Spades"), card("4", "Clubs"), card("5", "Diamonds"), card("King", "Spades") }, highlighted = {} }
  local s5 = HF.summary()
  check("near Straight carries run indices", s5:find("near Straight keep[1,2,3,4]/other[5]", 1, true) ~= nil, s5:match("Close:[^%.]*"))
end

do
  local function H(name) return D.get_action_handler(name) end
  mock_state("Normal", "SELECTING_HAND")
  G.NEURO.last_play = nil
  G.hand = { cards = { card("King", "Hearts"), card("King", "Spades"), card("9", "Clubs"),
    card("4", "Diamonds"), card("8", "Clubs") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 0
  G.GAME.chips = 100
  G.GAME.blind = { chips = 600 }
  G.FUNCS.get_poker_hand_info = function(cards)
    return "Pair", nil, { Pair = { { cards[1], cards[2] } } }, { cards[1], cards[2] }, nil
  end
  H("play_hand")({ indices = { 1, 2, 3 } })
  local c = H("play_hand")({ indices = { 1, 2, 3 } })
  local ok_play = type(c) == "function" and pcall(c)
  local lp = G.NEURO.last_play
  check("LP stash on play commit", ok_play and type(lp) == "table" and lp.hand_type == "Pair"
    and lp.played == 3 and lp.scored == 2 and lp.pre_chips == 100 and lp.hands_left_after == 2)

  local blob = ContextCompact.build("SELECTING_HAND", nil, { no_cache = true })
  check("LP renders without chips part pre-score", blob:find("Last hand: Pair, played 3 cards, 2 scored.", 1, true) ~= nil
    and blob:find("Last hand: Pair, played 3 cards, 2 scored, +", 1, true) == nil, blob:match("Last hand:[^\n]*"))

  G.GAME.chips = 420
  blob = ContextCompact.build("SELECTING_HAND", nil, { no_cache = true })
  check("LP delta + score/target once chips land", blob:find("Last hand: Pair, played 3 cards, 2 scored, +320 chips, now 420/600, 180 short.", 1, true) ~= nil, blob:match("Last hand:[^\n]*"))

  G.GAME.current_round.discards_left = 3
  local cd = H("discard_hand")({ indices = { 4, 5 } })
  pcall(cd)
  check("LP discard stash", type(G.NEURO.last_play) == "table" and G.NEURO.last_play.kind == "discard"
    and G.NEURO.last_play.played == 2 and G.NEURO.last_play.discards_left_after == 2)
  blob = ContextCompact.build("SELECTING_HAND", nil, { no_cache = true })
  check("LP discard reports replacement result and remaining resource",
    blob:find("Last discard: replaced 2 cards, 2 discards remain. The current hand below is the result.", 1, true) ~= nil,
    blob:match("Last discard:[^\n]*"))

  require("context.ctx_hand").clear_last_play()
  check("LP cleared on round-reset path", G.NEURO.last_play == nil)
  blob = ContextCompact.build("SELECTING_HAND", nil, { no_cache = true })
  check("no LP line after clear", blob:find("Last hand:", 1, true) == nil and blob:find("Last discard:", 1, true) == nil)

  G.GAME.chips = nil; G.GAME.blind = nil; G.FUNCS.get_poker_hand_info = nil
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.GAME.round_resets = { ante = 1 }
  G.NEURO.once_serials = {}
  local frame = require("context.game_rules").invariant_frame()
  check("rules: extra-played-cards sentence",
    frame:find("Normally only the cards forming the hand score -- extras are dumped like a discard", 1, true) ~= nil)
  check("rules: joker-synergy fact (no imperative)",
    frame:find("feeds another joker, or that triggers on a hand type", 1, true) ~= nil
    and frame:find("Three priorities", 1, true) == nil
    and frame:find("main plan", 1, true) == nil)
  check("rules: the xMult-vs-flat consequence is stated, not left to be inferred",
    frame:find("multipliers scale a score far faster than flat bonuses", 1, true) ~= nil
    and frame:find("Two xMults do not add", 1, true) ~= nil)

  check("rules: FRAME win clause is generic (no hardcoded Ante-8)",
    frame:find("Ante-8", 1, true) == nil and frame:find("final ante's Boss wins", 1, true) ~= nil)
  check("rules: FRAME carries no generic debuff prose (now dynamic)",
    frame:find("Boss debuffs can void", 1, true) == nil and frame:find("only the Boss debuffs", 1, true) == nil)
end

do
  mock_state("Normal", "SHOP")
  local blob = ContextCompact.build("SHOP", A.get_valid_actions_for_state("SHOP"), { no_cache = true })
  check("assembly: the action list is not duplicated into the state text -- actions/force carries action_names",
    blob:find("AVAIL:", 1, true) == nil, blob:sub(1, 90))
end

local Tuning = require("core.config")
do
  local defs = Tuning.entries()
  check("config: entries ordered, SPEED_MULT first", defs[1] and defs[1].key == "NEURO_SPEED_MULT")
  check("config: deterministic action cooldown default", Tuning.default("NEURO_ACTION_COOLDOWN") == 0.08)
  check("config: deterministic global shop gap default", Tuning.default("NEURO_GLOBAL_THROTTLE_SHOP") == 6.0)
  check("config: set clamps to max", Tuning.set("NEURO_SPEED_MULT", 99) == 2.0)
  check("config: set clamps to min", Tuning.set("NEURO_SPEED_MULT", -5) == 0.1)
  check("config: set rejects unknown key", Tuning.set("NEURO_NOT_A_KNOB", 1) == nil)
end

do
  local rt = Tuning.runtime_entries()
  check("config: system entries present", #rt > 0)
  check("config: persona is first system row", rt[1] and rt[1].key == "NEURO_PERSONA")
  check("config: process-only SDK key is not a setting", Tuning.definition("NEURO_ENABLE") == nil)
  check("config: all shipped personas are accepted", Tuning.set("NEURO_PERSONA", "hiyori") == "hiyori")
  Tuning.set("NEURO_AI_CARD_GLOW", "off")
  check("config: system enum set", Tuning.get_raw("NEURO_AI_CARD_GLOW") == "off")
  Tuning.set("NEURO_SELFTEST_FILTER", "abc")
  check("config: string key set", Tuning.get("NEURO_SELFTEST_FILTER") == "abc")
  Tuning.reset("NEURO_PERSONA")
  Tuning.reset("NEURO_AI_CARD_GLOW")
  Tuning.reset("NEURO_SELFTEST_FILTER")
end

do
  local prev_settings = G.SETTINGS
  G.SETTINGS = { GAMESPEED = 1 }
  Tuning.reset("NEURO_AUTO_TUNE")
  Tuning.reset("NEURO_CD_PRESET")
  Tuning.reset("NEURO_COOLDOWN_SCALE")
  local base = Tuning.get_raw("NEURO_GLOBAL_COOLDOWN")
  check("cdpreset: no-op at GAMESPEED 1 (auto)", math.abs(Tuning.get("NEURO_GLOBAL_COOLDOWN") - base) < 1e-9)

  G.SETTINGS.GAMESPEED = 4
  check("cdpreset: auto applies 4x stream factor 0.5", math.abs(Tuning.get("NEURO_GLOBAL_COOLDOWN") - base * 0.5) < 1e-9)
  for _, key in ipairs({ "NEURO_SHOP_BUY_DELAY", "NEURO_PACK_PICK_DELAY" }) do
    local raw = Tuning.get_raw(key)
    Tuning.set("NEURO_COOLDOWN_SCALE", 2)
    Tuning.set("NEURO_SPEED_MULT", 2.0)
    local scaled = Tuning.get(key)
    Tuning.reset("NEURO_COOLDOWN_SCALE")
    Tuning.reset("NEURO_SPEED_MULT")
    check("commit beat " .. key .. " is an engine constant, not a cooldown",
      math.abs(scaled - raw) < 1e-9 and math.abs(Tuning.get(key) - raw) < 1e-9, scaled)
    local def = require("core.config_schema").by_key[key]
    check("commit beat " .. key .. " carries no cooldown or event flag",
      def ~= nil and not def.cd and not def.event)
  end

  Tuning.set("NEURO_AUTO_TUNE", "off")
  check("cdpreset: auto-tune off = our values (no scaling) at GAMESPEED 4", math.abs(Tuning.get("NEURO_GLOBAL_COOLDOWN") - base) < 1e-9)
  Tuning.set("NEURO_AUTO_TUNE", "on")

  G.SETTINGS.GAMESPEED = 1
  Tuning.set("NEURO_CD_PRESET", "4x")
  check("cdpreset: pinned 4x applies stream factor regardless of native speed", math.abs(Tuning.get("NEURO_GLOBAL_COOLDOWN") - base * 0.5) < 1e-9)
  Tuning.set("NEURO_CD_PRESET", "2x")
  check("cdpreset: pinned 2x applies 2x stream factor 0.7", math.abs(Tuning.get("NEURO_GLOBAL_COOLDOWN") - base * 0.7) < 1e-9)
  Tuning.set("NEURO_CD_PRESET", "auto")

  G.SETTINGS.GAMESPEED = 99
  check("cdpreset: GAMESPEED clamps to 4", Tuning.game_speed() == 4)
  Tuning.reset("NEURO_AUTO_TUNE")
  Tuning.reset("NEURO_CD_PRESET")
  G.SETTINGS = prev_settings
end

do
  mock_state("Normal", "SHOP")
  local E = require("core.enforce")
  G.STATES = { SHOP = 5 }
  G.STATE = 5
  G.TIMERS = { REAL = 50000 }
  Tuning.set("NEURO_GLOBAL_THROTTLE_SHOP", 6.0)
  Tuning.set("NEURO_THROTTLE_SHOP", 1.2)
  check("enforce: first action passes cooldowns", E.pre_action(nil, "buy_from_shop") == true)
  G.TIMERS.REAL = 50003
  local ok2, err2 = E.pre_action(nil, "buy_from_shop")
  check("enforce: throttled inside global shop gap", ok2 == false and tostring(err2):find("wait") ~= nil, err2)
  Tuning.set("NEURO_GLOBAL_THROTTLE_SHOP", 2.0)
  check("enforce: Tuning.set lowers gap live, same call now passes", E.pre_action(nil, "buy_from_shop") == true)
  Tuning.reset("NEURO_GLOBAL_THROTTLE_SHOP")
  Tuning.reset("NEURO_THROTTLE_SHOP")
end

do
  mock_state("Normal", "SELECTING_HAND")
  local Staging = require("core.staging")
  G.hand = { cards = { card("5", "Hearts"), card("9", "Clubs") }, highlighted = {} }
  G.TIMERS = { REAL = 0 }
  G.STATES = { SELECTING_HAND = 1 }
  G.STATE = 1
  G.NEURO.state = "SELECTING_HAND"
  G.GAME.current_round.hands_left = 1
  G.GAME.current_round.discards_left = 0
  G.FUNCS.get_poker_hand_info = nil
  G.NEURO.force_inflight = false
  G.NEURO.force_window = nil
  require("core.force_state").arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
  local results = {}
  local bridge = {
    send_action_result = function(self, id, ok, msg, reason)
      results[#results + 1] = { id = id, ok = ok, msg = msg, reason = reason }
    end,
  }
  Tuning.set("NEURO_STAGING_FAILSAFE", 60)
  Staging._test.set_validator(nil)
  require("tests.helpers").stage_registered(nil, { "play_hand" })
  local queued = Staging.queue({ command = "action", data = { id = "tp_stage1", name = "play_hand", data = '{"indices":[1]}' } }, bridge)
  check("staging: queue accepted", queued == true,
    tostring(results[1] and (results[1].reason or results[1].msg)) .. " state=" .. tostring(require("core.state").get_state_name()))
  check("staging: queue emits the real early success ack",
    #results == 1 and results[1].id == "tp_stage1" and results[1].ok == true,
    tostring(results[1] and (results[1].reason or results[1].msg)))
  G.TIMERS.REAL = 30
  Staging.update()
  check("staging: within raised failsafe, still staged", Staging.is_busy() and #results == 1)
  Tuning.set("NEURO_STAGING_FAILSAFE", 10)
  Staging.update()
  check("staging: lowered failsafe cancels live without a duplicate result",
    not Staging.is_busy() and #results == 1)
  Tuning.reset("NEURO_STAGING_FAILSAFE")
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("5", "Hearts") }, highlighted = {} }
  G.STATES = { SELECTING_HAND = 1 }
  G.STATE = 1
  G.TIMERS = { REAL = 90000 }
  G.NEURO.state = "SELECTING_HAND"
  local results, ctxs = {}, {}
  local bridge = {
    send_action_result = function(self, id, ok, msg) results[#results + 1] = { id = id, ok = ok, msg = msg } end,
    send_context = function(self, msg, silent) ctxs[#ctxs + 1] = tostring(msg) end,
  }
  local Staging = require("core.staging")
  Staging.reset_run_state()
  G.OVERLAY_MENU = { popup = true }
  G.FUNCS = G.FUNCS or {}
  G.FUNCS.exit_overlay_menu = function() G.OVERLAY_MENU = nil end
  G.NEURO.llm_paused = true
  require("tests.helpers").stage_registered(nil, { "exit_overlay_menu" })
  local msg = { command = "action", data = { id = "tp_pause1", name = "exit_overlay_menu" } }
  D.route_message(msg, bridge)
  check("pause: paused reply is success=true with operator message",
    #results == 1 and results[1].ok == true and results[1].msg:find("Paused by operator") ~= nil,
    results[1] and results[1].msg)
  check("pause: handler not dispatched", Staging.is_busy() == false, tostring(Staging.is_busy()))
  D.route_message(msg, bridge)
  check("pause: redelivery while paused replays the settled reply",
    #results == 2 and results[2].id == "tp_pause1" and results[2].ok == true
      and results[2].msg:find("Paused", 1, true) ~= nil)
  G.NEURO.llm_paused = nil
  D.route_message(msg, bridge)
  check("pause: same id after resume replays paused reply (no ghost exec)",
    #results == 3 and results[3].ok == true and results[3].msg:find("Paused", 1, true) ~= nil,
    results[3] and results[3].msg)
  check("pause: replay did not dispatch the handler", Staging.is_busy() == false, tostring(Staging.is_busy()))
  local msg2 = { command = "action", data = { id = "tp_pause2", name = "exit_overlay_menu" } }
  D.route_message(msg2, bridge)
  check("pause: fresh id after resume executes normally",
    #results == 4 and results[4].ok == true
      and tostring(results[4].msg or ""):find("Paused", 1, true) == nil,
    results[4] and tostring(results[4].msg))
  check("pause: fresh-id execution really dispatched the action",
    Staging.is_busy() == true, tostring(Staging.is_busy()))
  Staging.reset_run_state()
end

do
  local P = require("hud.tuning_panel")
  local defs = Tuning.entries()
  local all_described = true
  for _, d in ipairs(defs) do
    if not P._test.description(d.key) then all_described = false; break end
  end
  for _, d in ipairs(Tuning.runtime_entries()) do
    if not P._test.description(d.key) then all_described = false; break end
  end
  check("panel: every setting has a user-facing description", all_described)
  G.NEURO.force_dirty = false
  Tuning.save()

  check("panel: open pauses LLM", P.toggle() == true and G.NEURO.llm_paused == true)
  check("panel: swallows own keys while open", P.keypressed("down") == true)
  check("panel: leaves other keys alone", P.keypressed("f9") == false)
  local d2 = defs[2]
  P._test.reveal(d2.key)
  local _, selected_row = P._test.state()
  check("panel: selected row labels its default value",
    P._test.rows()[selected_row].def == "1x", P._test.rows()[selected_row].def)
  local before = Tuning.get(d2.key)
  P.keypressed("right")
  check("panel: right adjusts selected by step", math.abs(Tuning.get(d2.key) - math.min(d2.max, before + d2.step)) < 1e-9)
  P.keypressed("r")
  check("panel: R resets selected to default", Tuning.get(d2.key) == d2.default)
  check("panel: close resumes LLM", P.toggle() == false and G.NEURO.llm_paused == nil)
  check("panel: resume marks force dirty + clears fingerprint",
    G.NEURO.force_dirty == true)
  check("panel: close persists native config", not Tuning._test.is_dirty())
  check("panel: closed panel ignores keys", P.keypressed("down") == false)
end

do
  local P = require("hud.tuning_panel")
  local failed_data = { settings = {}, colours = {} }
  Tuning.init(failed_data, function() return false, "write denied" end)
  Tuning.set("NEURO_SPEED_MULT", 1.5)
  P.toggle()
  check("panel: failed save keeps the panel open",
    P.toggle() == true and P.is_open() and Tuning._test.is_dirty())
  Tuning.init(failed_data, function() return true end)
  Tuning.set("NEURO_SPEED_MULT", 1.5)
  check("panel: successful retry closes the panel", P.toggle() == false and not P.is_open())
  Tuning.reset("NEURO_SPEED_MULT")
end

do
  for _, k in ipairs({ "NEURO_OVERLAY_SCALE_RIGHT", "NEURO_OVERLAY_SCALE_LEFT" }) do
    local d
    for _, e in ipairs(Tuning.entries()) do if e.key == k then d = e end end
    check("scale: " .. k .. " registered 0.5-1.5 step 0.05 default 1",
      d and d.min == 0.5 and d.max == 1.5 and d.step == 0.05 and d.default == 1.0)
    check("scale: " .. k .. " clamps high", Tuning.set(k, 9) == 1.5)
    check("scale: " .. k .. " clamps low", Tuning.set(k, 0) == 0.5)
    Tuning.reset(k)
    check("scale: " .. k .. " reset to 1.0", Tuning.get(k) == 1.0)
  end
end

do
  local defs = {}
  for _, d in ipairs(Tuning.entries()) do defs[d.key] = d end
  local anchor = defs.NEURO_OVERLAY_ANCHOR
  check("position: anchor exposes every supported placement with AUTO default",
    anchor and anchor.default == "auto" and #anchor.values == 7
      and anchor.values[1] == "auto" and anchor.values[2] == "top-left"
      and anchor.values[7] == "bottom-right")
  check("position: anchor accepts a listed value",
    Tuning.set("NEURO_OVERLAY_ANCHOR", "middle-left") == "middle-left")
  check("position: anchor rejects an unknown value",
    Tuning.set("NEURO_OVERLAY_ANCHOR", "over-avatar") == nil)
  Tuning.reset("NEURO_OVERLAY_ANCHOR")
  check("position: anchor resets to AUTO", Tuning.get("NEURO_OVERLAY_ANCHOR") == "auto")
  for _, key in ipairs({ "NEURO_OVERLAY_OFFSET_X", "NEURO_OVERLAY_OFFSET_Y" }) do
    local d = defs[key]
    check("position: " .. key .. " registered -40..40 step 1 default 0",
      d and d.min == -40 and d.max == 40 and d.step == 1 and d.default == 0)
    check("position: " .. key .. " clamps high", Tuning.set(key, 90) == 40)
    check("position: " .. key .. " clamps low", Tuning.set(key, -90) == -40)
    Tuning.reset(key)
    check("position: " .. key .. " resets to zero", Tuning.get(key) == 0)
  end
end

do
  local HUD = require("render.hud_overlay")
  local place = HUD._test and HUD._test.panel_layout
  local available = HUD._test and HUD._test.panel_available_height
  check("position: geometry seam is available in tests", type(place) == "function" and type(available) == "function")
  local anchors = {
    { "top-left", "left" }, { "middle-left", "left" }, { "bottom-left", "left" },
    { "top-right", "right" }, { "middle-right", "right" }, { "bottom-right", "right" },
  }
  for _, size in ipairs({ { 1280, 720 }, { 1920, 1080 }, { 2560, 1080 } }) do
    for _, item in ipairs(anchors) do
      local x, y, side = place(item[1], 0, 0, size[1], size[2], 320, 300, 0)
      check("position: " .. item[1] .. " stays inside " .. size[1] .. "x" .. size[2],
        x >= 8 and y >= 8 and x + 320 <= size[1] - 8 and y + 300 <= size[2] - 8)
      check("position: " .. item[1] .. " resolves its side at " .. size[1] .. "x" .. size[2],
        side == item[2], side)
    end
  end
  local ax, ay, aside = place("auto", 0, 0, 1280, 720, 320, 300, 0)
  check("position: AUTO preserves the original right-side geometry",
    ax == 952 and ay == math.max(120, math.floor(720 * 0.38)) and aside == "right",
    tostring(ax) .. "/" .. tostring(ay) .. "/" .. tostring(aside))
  local lx = place("middle-left", 10, 0, 1280, 720, 320, 300, 0)
  local rx = place("middle-right", 10, 0, 1280, 720, 320, 300, 0)
  check("position: positive horizontal offset moves both anchors inward",
    lx == 136 and rx == 824, tostring(lx) .. "/" .. tostring(rx))
  local _, by = place("bottom-right", 0, 0, 1280, 720, 320, 300, 80)
  check("position: bottom anchor reserves the voucher drawer", by == 332, tostring(by))
  local ex, ey = place("middle-left", 40, 40, 1280, 720, 900, 650, 0)
  check("position: extreme size and offsets remain clamped to the viewport",
    ex >= 8 and ey >= 8 and ex + 900 <= 1272 and ey + 650 <= 712,
    tostring(ex) .. "/" .. tostring(ey))
  check("position: middle and bottom anchors lay out against the full safe height",
    available("middle-left", 40, 720, 80) == 624
      and available("bottom-right", -40, 720, 80) == 624)
end

do
  local defs = {}
  for _, d in ipairs(Tuning.entries()) do defs[d.key] = d end
  local sa = defs.NEURO_SHOP_ANCHOR
  check("shop position: anchor exposes every supported placement with AUTO default",
    sa and sa.group == "LAYOUT" and sa.default == "auto" and #sa.values == 7
      and sa.values[1] == "auto" and sa.values[2] == "top-left"
      and sa.values[7] == "bottom-right")
  check("shop position: anchor accepts a listed value",
    Tuning.set("NEURO_SHOP_ANCHOR", "bottom-right") == "bottom-right")
  check("shop position: anchor rejects an unknown value",
    Tuning.set("NEURO_SHOP_ANCHOR", "over-avatar") == nil)
  Tuning.reset("NEURO_SHOP_ANCHOR")
  check("shop position: anchor resets to AUTO", Tuning.get("NEURO_SHOP_ANCHOR") == "auto")
  for _, key in ipairs({ "NEURO_SHOP_OFFSET_X", "NEURO_SHOP_OFFSET_Y" }) do
    local d = defs[key]
    check("shop position: " .. key .. " registered -40..40 step 1 default 0",
      d and d.group == "LAYOUT" and d.min == -40 and d.max == 40
        and d.step == 1 and d.default == 0 and d.unit == "%")
    check("shop position: " .. key .. " clamps high", Tuning.set(key, 90) == 40)
    check("shop position: " .. key .. " clamps low", Tuning.set(key, -90) == -40)
    Tuning.reset(key)
    check("shop position: " .. key .. " resets to zero", Tuning.get(key) == 0)
  end
  local seen, split, last = {}, nil, nil
  for _, d in ipairs(Tuning.entries()) do
    if d.group ~= last then
      if seen[d.group] then split = d.group end
      seen[d.group] = true
      last = d.group
    end
  end
  check("shop position: every settings group stays one contiguous block", split == nil, split)
end

do
  local prev_gfx, prev_mouse = love.graphics, love.mouse
  local prev_shared = package.loaded["render.hud_shared"]
  local prev_shop = package.loaded["render.panels.shop"]
  local scr_w, scr_h = 1920, 1080
  local function noop() end
  local stub_font = {
    getHeight = function() return 12 end,
    getWidth = function(_, s) return 6 * #tostring(s or "") end,
  }
  love.graphics = setmetatable({
    getFont = function() return stub_font end,
    newFont = function() return stub_font end,
    getWidth = function() return scr_w end,
    getHeight = function() return scr_h end,
    getScissor = function() return nil end,
  }, { __index = function() return noop end })
  love.mouse = { getPosition = function() return -1, -1 end }
  package.loaded["render.hud_shared"] = nil
  package.loaded["render.panels.shop"] = nil
  local Shop = require("render.panels.shop")
  local HUDo = require("render.hud_overlay")
  local Rows = require("hud.rows")
  local HS = require("hud.state")
  local W = Shop.PANEL_BASE_W
  local function CLR() return { 0.6, 0.6, 0.6, 1 } end
  local function id(v) return v or 0 end
  local function place(o)
    scr_w, scr_h = o.sw or 1920, o.sh or 1080
    HS.shop_x_current, HS.shop_y_current = nil, nil
    HS.lp_compact = false
    local theme = {
      p = CLR(), pg = CLR(), bg = CLR(), ACC = CLR(), FR = CLR(), FRD = CLR(),
      ROW = CLR(), SEL = CLR(), ORANGE = CLR(), GREEN = CLR(), DIM = CLR(),
      WHITE = CLR(), CYAN = CLR(), GOLD = CLR(),
      persona_evil = false, persona_neuro = false, persona_name = "Hiyori", pk = "hiyori",
      font = stub_font, panel_font_small = stub_font, lfont = stub_font,
      lfont_small = stub_font, lfont_title = stub_font,
    }
    local metrics = {
      ln = id, lp_sh = 1, sw = scr_w, sh = scr_h, U = 6, GUT = 12, ACCENT_W = 3, TRACK = 1,
      p_x = o.p_x or (scr_w - 320 - 8), p_y = o.p_y or 120, pw_total = o.pw_total or 320,
      card_line_h = 28, sep_h = 6,
      main_side = o.main_side or "right", anchor = o.anchor or "auto", offset_y = o.offset_y or 0,
      shop_anchor = o.shop_anchor or "auto",
      shop_offset_x = o.shop_offset_x or 0, shop_offset_y = o.shop_offset_y or 0,
    }
    local data = {
      shop_rows = {
        Rows.header(CLR(), "Shop: Jokers"),
        Rows.shopcard(CLR(), "card", {}, 3, true, nil, {}),
        Rows.note(CLR(), "note"),
        Rows.sep(),
      },
    }
    local draw = {
      trunc = function(s) return s end,
      wrapped_lines = function() return { "a" } end,
      draw_colored_desc = noop,
      draw_desc_lines = noop, print_colored_desc = noop,
    }
    Shop.draw({ theme = theme, motion = { now = 0, pulse = 0.5, dt = 0.016,
      shimr = 0.5, shimg = 0.5, shimb = 0.5 }, metrics = metrics, data = data, draw = draw })
    return HS.shop_x_current, HS.shop_y_current
  end

  local _, probe_y = place({ shop_anchor = "bottom-left" })
  local SH_H = 1080 - 8 - (probe_y or 0)
  check("shop position: the probe panel has a measurable height", SH_H > 0 and SH_H < 1080, SH_H)

  local ax, ay = place({ main_side = "right", p_x = 1592, pw_total = 320, p_y = 120 })
  check("shop position: AUTO stays opposite a right-anchored HUD and tracks its y",
    ax == 8 and ay == 120, tostring(ax) .. "/" .. tostring(ay))
  local bx, by = place({ main_side = "left", p_x = 8, pw_total = 320, p_y = 140 })
  check("shop position: AUTO clears a left-anchored HUD",
    bx == 1920 - W - 8 and bx >= 8 + 320 + 8 and by == 140, tostring(bx) .. "/" .. tostring(by))
  local _, cy = place({ anchor = "bottom-right", p_y = 500 })
  check("shop position: AUTO still follows the main panel's bottom anchor",
    cy == 1080 - SH_H - 8, tostring(cy))
  local _, my = place({ anchor = "middle-right", p_y = 500 })
  check("shop position: AUTO still follows the main panel's middle anchor",
    my == math.floor((1080 - SH_H) / 2 + 0.5), tostring(my))
  local ox, oy = place({ shop_offset_x = 40, shop_offset_y = 40 })
  check("shop position: AUTO applies the shop's offsets",
    ox == 776 and oy == 552, tostring(ox) .. "/" .. tostring(oy))

  local ex1, ey1 = place({ shop_anchor = "top-left" })
  local ex2, ey2 = place({ shop_anchor = "top-left", main_side = "left", p_x = 8,
    pw_total = 640, p_y = 700, anchor = "bottom-left", offset_y = 30 })
  check("shop position: an explicit anchor places the shop independently of the main HUD",
    ex1 == 8 and ey1 == 8 and ex2 == ex1 and ey2 == ey1,
    tostring(ex1) .. "/" .. tostring(ey1) .. " vs " .. tostring(ex2) .. "/" .. tostring(ey2))
  local px, py = place({ shop_anchor = "top-left", shop_offset_x = 10, shop_offset_y = 10 })
  check("shop position: explicit offsets move the shop from its own anchor",
    px == 200 and py == 116, tostring(px) .. "/" .. tostring(py))
  local rx = place({ shop_anchor = "top-right", main_side = "right", p_x = 1592, pw_total = 320 })
  check("shop position: an explicit anchor may share a side with the main HUD",
    rx == 1920 - W - 8 and rx + W > 1592, tostring(rx))
  local qx, qy = place({ shop_anchor = "middle-right", shop_offset_x = 15, shop_offset_y = -10 })
  local lx, ly = HUDo._test.panel_layout("middle-right", 15, -10, 1920, 1080, W, SH_H, 0)
  check("shop position: explicit placement reuses the production anchor math",
    qx == lx and qy == ly, tostring(qx) .. "/" .. tostring(qy) .. " vs " .. tostring(lx) .. "/" .. tostring(ly))

  local anchors = { "auto", "top-left", "middle-left", "bottom-left",
    "top-right", "middle-right", "bottom-right" }
  local bad
  for _, size in ipairs({ { 1280, 720 }, { 1920, 1080 }, { 2560, 1080 } }) do
    local _, base_y = place({ shop_anchor = "bottom-left", sw = size[1], sh = size[2] })
    local hh = size[2] - 8 - base_y
    for _, a in ipairs(anchors) do
      for _, dx in ipairs({ -40, 0, 40 }) do
        for _, dy in ipairs({ -40, 0, 40 }) do
          local x, y = place({ shop_anchor = a, shop_offset_x = dx, shop_offset_y = dy,
            sw = size[1], sh = size[2] })
          if not (x >= 8 and y >= 8 and x + W <= size[1] - 8 and y + hh <= size[2] - 8) then
            bad = string.format("%s %d/%d @%dx%d -> %s,%s", a, dx, dy, size[1], size[2],
              tostring(x), tostring(y))
          end
        end
      end
    end
  end
  check("shop position: every anchor and offset extreme stays on screen", bad == nil, bad)

  package.loaded["render.hud_shared"] = prev_shared
  package.loaded["render.panels.shop"] = prev_shop
  love.graphics, love.mouse = prev_gfx, prev_mouse
  HS.shop_x_current, HS.shop_y_current = nil, nil
end

do
  local P = require("hud.tuning_panel")
  local DS = require("render.debug_stats")
  local d
  local defs = Tuning.entries()
  local sel_idx
  for i, e in ipairs(defs) do if e.key == "NEURO_DEBUG_OVERLAY" then d = e sel_idx = i end end
  check("enum: NEURO_DEBUG_OVERLAY entry has mode list off/compact/expanded",
    d and d.values and d.values[1] == "off" and d.values[2] == "compact" and d.values[3] == "expanded")
  check("enum: set accepts listed value", Tuning.set("NEURO_DEBUG_OVERLAY", "expanded") == "expanded")
  check("enum: set rejects unlisted value", Tuning.set("NEURO_DEBUG_OVERLAY", "loud") == nil)
  Tuning.set("NEURO_DEBUG_OVERLAY", "off")

  local applied = {}
  local orig_smn = DS.set_mode_name
  DS.set_mode_name = function(name) applied[#applied + 1] = name end
  P.toggle()
  P._test.reveal("NEURO_DEBUG_OVERLAY")
  P.keypressed("right")
  P.keypressed("right")
  P.keypressed("right")
  DS.set_mode_name = orig_smn
  P.toggle()
  check("enum: panel right cycles through full mode list and wraps",
    #applied == 3 and applied[1] == "compact" and applied[2] == "expanded" and applied[3] == "off")
  check("enum: panel applies the tuned value to DebugStats", applied[#applied] == Tuning.get("NEURO_DEBUG_OVERLAY"))
  check("enum: set_mode_name drives visible mode", (function()
    DS.set_mode_name("compact")
    local vis = DS.visible()
    DS.set_mode_name("off")
    return vis and not DS.visible()
  end)())
  Tuning.set("NEURO_DEBUG_OVERLAY", "off")
end

do
  local prior_smods = _G.SMODS
  _G.SMODS = {
    current_mod = { path = "./", config = { settings = {}, colours = {} } },
    save_mod_config = function() return true end,
    Mods = {},
  }

  local ok_ng, ng_err = pcall(require, "neuro-game")
  check("f8: neuro-game loads offline", ok_ng, ng_err)
  check("f8: love.keypressed hook installed", type(love.keypressed) == "function")
  check("f8: love.mousemoved hook installed", type(love.mousemoved) == "function")
  check("f8: love.mousereleased hook installed", type(love.mousereleased) == "function")
  local P = require("hud.tuning_panel")
  if P.is_open() then P.toggle() end
  G.NEURO.login_anim = nil
  G.NEURO.llm_paused = nil
  G.NEURO.force_inflight = true
  G.NEURO.force_state = "MENU"
  G.NEURO.force_sent_at = 1
  G.NEURO.force_dirty = false
  G.NEURO.login_anim = {}
  love.keypressed("f8")
  check("f8: login animation swallows F8 without opening or pausing",
    not P.is_open() and G.NEURO.llm_paused == nil)
  G.NEURO.login_anim = nil
  love.keypressed("f8")
  check("f8: first press pauses LLM + opens panel", G.NEURO.llm_paused == true and P.is_open())
  P.keypressed("tab"); P.keypressed("tab"); P.keypressed("tab")
  check("f8: test reached the COLOURS page", (P._test.state()) == 4)
  check("f8: an idle c on COLOURS is returned to the game instead of swallowed",
    P.keypressed("c") == false)
  love.keypressed("f8")
  check("f8: second press resumes (llm_paused cleared)", not G.NEURO.llm_paused and not P.is_open())
  check("f8: resume re-arms force (dirty + fingerprint cleared)",
    G.NEURO.force_dirty == true)
  check("f8: resume clears stale inflight force so re-force can send",
    G.NEURO.force_inflight == false and G.NEURO.force_sent_at == nil)

  _G.SMODS = prior_smods
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.STATES = { MENU = 1 }
  G.STATE = 1
  G.GAME = { current_round = {} }
  G.OVERLAY_MENU = nil
  G.run_setup_seed = nil
  G.setup_seed = nil

  local f = D.get_force_for_state("MENU")
  check("seed chain: MENU force offers setup_run", f and has(f.actions, "setup_run"))
  check("seed chain: MENU force omits toggle_seeded_run (fails without overlay)",
    not has((f or {}).actions, "toggle_seeded_run"))
  check("seed chain: MENU force omits paste_seed (wiped by overlay rebuild)",
    not has((f or {}).actions, "paste_seed"))
  check("seed chain: MENU force omits start_setup_run (dispatcher rejects it)",
    not has((f or {}).actions, "start_setup_run"))
  check("seed chain: toggle_seeded_run invalid without overlay", not A.is_action_valid("toggle_seeded_run"))
  check("seed chain: start_setup_run invalid without overlay", not A.is_action_valid("start_setup_run"))

  G.OVERLAY_MENU = { get_UIE_by_ID = function(_, id) return (id == "run_setup_seed") and {} or nil end }
  local rs = D.get_force_for_state("RUN_SETUP")
  check("seed chain: run-setup force offers toggle_seeded_run", rs and has(rs.actions, "toggle_seeded_run"))
  check("seed chain: run-setup force offers paste_seed", rs and has(rs.actions, "paste_seed"))
  check("seed chain: run-setup force offers start_setup_run", rs and has(rs.actions, "start_setup_run"))
  local rq = (rs or {}).query or ""
  check("seed chain: run-setup force shows seeded mode fact", rq:find("Seeded mode: OFF", 1, true) ~= nil, rq)
  check("seed chain: run-setup force gives paste_seed payload example",
    rq:find('paste_seed|{"seed":"ABC123XY"}', 1, true) ~= nil, rq)

  local toggle = D.get_action_handler("toggle_seeded_run")
  local run = toggle({})
  check("seed chain: toggle_seeded_run executes on overlay", type(run) == "function" and run():find("ON") ~= nil)
  check("seed chain: toggle flips engine flag", G.run_setup_seed == true)

  local paste = D.get_action_handler("paste_seed")
  local bad_prun, bad_err = paste({ seed = "ab-cd!" })
  check("seed chain: paste_seed rejects invalid characters", bad_prun == nil and bad_err ~= nil)

  local dash_prun, dash_err = paste({ seed = "abc-123xy" })
  check("seed chain: paste_seed rejects a dash instead of stripping it silently",
    dash_prun == nil and dash_err ~= nil, dash_err)

  local prun = paste({ seed = "abc123xy" })
  check("seed chain: paste_seed normalizes + reports seed",
    type(prun) == "function" and prun() == "Seed set to: ABC123XY")
  check("seed chain: paste_seed arms engine seed", G.setup_seed == "ABC123XY" and G.run_setup_seed == true)

  local rs2 = D.get_force_for_state("RUN_SETUP")
  local rq2 = (rs2 or {}).query or ""
  check("seed chain: force reflects seeded ON + pasted seed",
    rq2:find("Seeded mode: ON", 1, true) ~= nil and rq2:find("Pasted seed: ABC123XY", 1, true) ~= nil, rq2)
  check("seed chain: start_setup_run valid with overlay open", A.is_action_valid("start_setup_run"))

  G.OVERLAY_MENU = nil
  G.run_setup_seed = nil
  G.setup_seed = nil
  G.STATES = nil; G.STATE = nil
end

do
  local old_event_manager = G.E_MANAGER
  G.E_MANAGER = { queues = { base = {} } }
  check("race gate: empty engine queue is settled", Utils.engine_settled())
  G.E_MANAGER.queues.base[1] = { blocking = true, blockable = false }
  check("race gate: queued gameplay event blocks a force", not Utils.engine_settled())
  G.E_MANAGER.queues.base[1] = { blocking = false, blockable = false }
  check("race gate: permanent cosmetic event does not deadlock forces", Utils.engine_settled())
  G.E_MANAGER.queues.unlock = { { blocking = true } }
  check("race gate: unlock queue does not block gameplay decisions", Utils.engine_settled())
  G.E_MANAGER = old_event_manager
end

do
  local red = { key = "b_red", name = "Red Deck" }
  local blue = { key = "b_blue", name = "Blue Deck" }
  local function back(center)
    return {
      effect = { center = center },
      change_to = function(self, next_center) self.effect.center = next_center end,
    }
  end
  G.P_CENTER_POOLS = G.P_CENTER_POOLS or {}
  local old_backs = G.P_CENTER_POOLS.Back
  G.P_CENTER_POOLS.Back = { red, blue }
  G.GAME = { viewed_back = back(red), selected_back = back(red) }
  G.SETTINGS = { profile = 1 }
  G.PROFILES = { [1] = { MEMORY = {} } }
  G.OVERLAY_MENU = { get_UIE_by_ID = function(_, id) return id == "run_setup_seed" and {} or nil end }
  local choose = D.get_action_handler("change_selected_back")({ back = "b_blue" })
  choose()
  G.GAME.viewed_back:change_to(red)
  G.GAME.selected_back:change_to(red)
  local started_with
  local old_start_run = G.FUNCS.start_run
  local injected_start_run = function(_, args)
    started_with = args and args.deck_choice and args.deck_choice.key
  end
  G.FUNCS.start_run = injected_start_run
  G.FUNCS.start_setup_run = function(e)
    G.FUNCS.start_run(e, { stake = 1 })
  end
  G.STATES = { RUN_SETUP = 7 }; G.STATE = 7
  G.NEURO.state = "RUN_SETUP"
  G.NEURO.setup_acknowledged = true
  G.NEURO.force_inflight = false
  G.NEURO.force_window = nil
  require("core.force_state").arm("RUN_SETUP", { "start_setup_run" }, { start_setup_run = true }, 1)
  require("tests.helpers").stage_registered(nil, { "start_setup_run" })
  D.handle_message({ command = "action", data = {
    id = "deck-start-persistence", name = "start_setup_run", data = {},
  } }, { send_action_result = function() end })
  check("selected deck is injected into start_run despite stale menu state", started_with == "b_blue", started_with)
  check("start_run hook is restored after run start", G.FUNCS.start_run == injected_start_run, tostring(G.FUNCS.start_run))
  G.FUNCS.start_setup_run = nil
  G.FUNCS.start_run = old_start_run
  G.P_CENTER_POOLS.Back = old_backs
  G.OVERLAY_MENU = nil
  G.NEURO.selected_back_key = nil
  G.STATES = nil; G.STATE = nil
end

do
  mock_state("Normal", "SELECTING_HAND")
  local CtxHand = require("context.ctx_hand")
  local d = { card("Ace", "Spades"), card("King", "Hearts"), card("5", "Hearts") }
  G.deck = { cards = { d[1], d[2], d[3] } }
  local dc1 = CtxHand.deck_cards_section()
  check("DC is size only", dc1 == "3 cards left in the draw pile.", dc1)
  check("DC exposes no suit/rank breakdown", not dc1:find("|") and not dc1:find("Hearts") and not dc1:find("Spades"), dc1)
  G.deck = { cards = { d[3], d[1], d[2] } }
  check("DC identical under reordering (no draw-order leak)", CtxHand.deck_cards_section() == dc1)
  G.deck = nil
end

do
  mock_state("Small blind selectable", "BLIND_SELECT")
  local CtxBlind = require("context.ctx_blind")
  G.GAME.bosses_used = { boss = { bl_ox = 0, bl_wall = 1 }, small = { bl_small = 3 }, big = {} }
  local s = CtxBlind.blind_select_section() or ""
  check("bosses_used drives no roster line", s:lower():find("beaten", 1, true) == nil, s)
  G.GAME.bosses_used = { bl_ox = 0, bl_wall = 1 }
  s = CtxBlind.blind_select_section() or ""
  check("a flat bosses_used mock names no boss either",
    s:find("The Wall", 1, true) == nil, s)

  local marked = false
  for _, def in pairs(G.P_BLINDS or {}) do
    if type(def) == "table" then
      def.debuff = def.debuff or {}
      def.debuff.text = "Your hand size is 1 lower for this round."
      marked = true
    end
  end
  local sd = CtxBlind.blind_select_section() or ""
  check("the fixture actually put an effect on a blind row",
    marked and sd:find("Effect: ", 1, true) ~= nil, sd)
  check("a row whose effect already ends in a full stop gets no second one",
    sd:find("%.%.") == nil, sd:match("[^\n]*%.%.[^\n]*") or sd)

  local saved_choices = G.GAME.round_resets and G.GAME.round_resets.blind_choices
  G.GAME.round_resets = G.GAME.round_resets or {}
  G.GAME.round_resets.blind_choices = { Boss = "bl_wall" }
  G.GAME.bosses_used = { boss = { bl_wall = 1, bl_ox = 1 } }
  s = CtxBlind.blind_select_section() or ""
  check("no boss roster is reconstructed from draw counts",
    s:lower():find("beaten", 1, true) == nil and s:find("The Ox", 1, true) == nil, s)
  G.GAME.round_resets.blind_choices = saved_choices
  G.GAME.bosses_used = nil
end

do
  mock_state("Normal", "SHOP")
  G.jokers = { cards = {
    { ability = { name = "Joker" }, sell_cost = 3, config = { center = { key = "j_joker" } } },
    { ability = { name = "Blueprint" }, sell_cost = 3, config = { center = { key = "j_blueprint" } } },
  }, config = { card_limit = 5 } }
  local f = D.get_force_for_state("SHOP")
  local ctx = ContextCompact.build("SHOP", f.actions, { force_phase = true, no_cache = true })
  local ctx2 = ContextCompact.build("SHOP", f.actions, { no_cache = true })
  check("the action list never rides in the state text -- actions/force carries action_names",
    ctx:find("AVAIL:", 1, true) == nil and ctx2:find("AVAIL:", 1, true) == nil, ctx2:sub(1, 200))
  check("the force still ships a non-empty action list", #f.actions > 0, #f.actions)
end

do
  local FH = require("force.force_helpers")
  mock_state("Normal", "SELECTING_HAND")
  G.STATES = { SELECTING_HAND = 1, SHOP = 5 }
  G.STATE = 1
  check("force for the current state is not stale", FH.force_is_stale("SELECTING_HAND", {}) == false)
  check("force built for a superseded state is stale", FH.force_is_stale("SHOP", {}) == true)
  G.STATES = nil; G.STATE = nil

  mock_state("Small blind selectable", "BLIND_SELECT")
  G.STATES = { BLIND_SELECT = 3 }; G.STATE = 3
  check("blind force matching the selectable blind is not stale",
    FH.force_is_stale("BLIND_SELECT", { blind = "small" }) == false)
  G.GAME.blind_on_deck = "Big"
  G.GAME.round_resets.blind_states = { Small = "Defeated", Big = "Select", Boss = "Upcoming" }
  check("blind force naming a superseded selectable is stale",
    FH.force_is_stale("BLIND_SELECT", { blind = "small" }) == true)
  G.STATES = nil; G.STATE = nil
end

do
  local HF = require("facts.hand_facts")
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("King", "Hearts"), card("King", "Spades"), card("7", "Clubs"),
    card("7", "Diamonds"), card("7", "Hearts"), card("4", "Clubs"), card("4", "Spades") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2
  local hc = G.hand.cards
  G.FUNCS.get_poker_hand_info = function(_)
    return "Full House", nil, {
      ["Full House"] = { { hc[3], hc[4], hc[5], hc[1], hc[2] }, { hc[3], hc[4], hc[5], hc[6], hc[7] } },
      ["Three of a Kind"] = { { hc[3], hc[4], hc[5] } },
      ["Two Pair"] = { { hc[1], hc[2], hc[6], hc[7] } },
      ["Pair"] = { { hc[1], hc[2] }, { hc[6], hc[7] } },
    }, { hc[3], hc[4], hc[5], hc[1], hc[2] }, nil
  end
  local s = HF.summary()
  local ready_ix = {}
  for name, ix in (s:match("Ready:[^%.]*") or ""):gmatch("([%a ]+)%[([%d,]+)%]") do
    ready_ix[name:gsub("^[%s,]+", "")] = ix
  end
  check("Full House = exactly the KK+777 positions [1,2,3,4,5]",
    ready_ix["Full House"] == "1,2,3,4,5", s:match("Ready:[^%.]*"))
  check("Pair = highest pair only [1,2] (not the union of all pairs)",
    ready_ix["Pair"] == "1,2", s:match("Ready:[^%.]*"))
  for name, ix in pairs(ready_ix) do
    local n = 0
    for _ in ix:gmatch("%d+") do n = n + 1 end
    check("ready list for " .. name .. " never exceeds 5", n <= 5, ix)
  end

  G.hand = { cards = { card("2", "Hearts"), card("King", "Hearts"), card("5", "Hearts"),
    card("9", "Hearts"), card("Ace", "Hearts"), card("Jack", "Hearts"), card("3", "Clubs") }, highlighted = {} }
  local fc = G.hand.cards
  G.FUNCS.get_poker_hand_info = function(_)
    return "Flush", nil, { ["Flush"] = { { fc[1], fc[2], fc[3], fc[4], fc[5], fc[6] } } },
      { fc[2], fc[4], fc[5], fc[6], fc[3] }, nil
  end
  local s2 = HF.summary()
  check("6-card Flush trimmed to the 5 highest of the suit [2,3,4,5,6]",
    s2:find("Flush[2,3,4,5,6]", 1, true) ~= nil, s2:match("Ready:[^%.]*"))
  G.FUNCS.get_poker_hand_info = nil
end

do
  local HF = require("facts.hand_facts")
  mock_state("Normal", "SELECTING_HAND")
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2
  G.hand = { cards = { card("King", "Hearts"), card("King", "Spades"), card("4", "Diamonds"),
    card("9", "Clubs"), card("Queen", "Hearts") }, highlighted = {} }
  local s = HF.summary()
  check("near Three of a Kind carries the pair's positions",
    s:find("near Three of a Kind keep[1,2]", 1, true) ~= nil, s:match("Close:[^%.]*"))
  check("near Two Pair carries the pair's positions",
    s:find("near Two Pair keep[1,2]", 1, true) ~= nil, s:match("Close:[^%.]*"))

  G.hand = { cards = { card("7", "Clubs"), card("7", "Diamonds"), card("7", "Hearts"),
    card("King", "Spades"), card("2", "Clubs") }, highlighted = {} }
  local s2 = HF.summary()
  check("near Four of a Kind carries the trips' positions",
    s2:find("near Four of a Kind keep[1,2,3]", 1, true) ~= nil, s2:match("Close:[^%.]*"))
  check("near Full House carries the trips' positions",
    s2:find("near Full House keep[1,2,3]", 1, true) ~= nil, s2:match("Close:[^%.]*"))
end

do
  local CtxEconomy = require("facts.economy_facts")
  mock_state("Normal", "SELECTING_HAND")
  G.GAME.dollars = 0
  G.GAME.modifiers = {}
  G.GAME.current_round.hands_left = 1; G.GAME.current_round.discards_left = 0
  check("default projection counts all hands (H1)", CtxEconomy.economy_projection().hands_bonus == 1)
  check("selecting-hand projection excludes the deciding hand (H0)",
    CtxEconomy.economy_projection({ selecting_hand = true }).hands_bonus == 0)
  G.GAME.current_round.hands_left = 3
  check("selecting-hand projection = hands_left-1",
    CtxEconomy.economy_projection({ selecting_hand = true }).hands_bonus == 2)
  G.GAME.blind = { in_blind = true, dollars = 3, chips = 300 }
  G.hand = { cards = { card("5", "Hearts") }, highlighted = {}, config = { card_limit = 8 } }
  G.GAME.current_round.hands_left = 1
  local blob = ContextCompact.build("SELECTING_HAND", nil, { no_cache = true })
  check("last-hand B line projects H0", blob:find("blind $3 + hands $0 +", 1, true) ~= nil, blob:match("Cash%-out[^\n]*"))
  G.GAME.blind = nil
end

do
  mock_state("Small blind selectable", "BLIND_SELECT")
  G.GAME.blind_on_deck = nil
  check("get_selectable_blind_key falls back to blind_states Select",
    A.get_selectable_blind_key() == "Small")
  local f = D.get_force_for_state("BLIND_SELECT")
  check("force still built from states fallback (names small)",
    f ~= nil and tostring(f.query):find("Currently selectable: small", 1, true) ~= nil, f and f.query)
  check("force carries the blind it was built for", f and f.blind == "small")
  G.GAME.blind_on_deck = nil
  G.GAME.round_resets.blind_states = { Small = "Upcoming", Big = "Upcoming", Boss = "Upcoming" }
  check("unresolved on-deck AND states -> no force (delay, never OD:?)",
    require("force.force_blind_select").build("") == nil)
end

do
  mock_state("Normal", "SELECTING_HAND")
  local hidden = {
    ability = { consumeable = {}, set = "Spectral", name = "c_ankh" },
    config = { center = { key = "c_ankh", loc_txt = { name = "Ankh" }, discovered = false } },
    generate_UIBox_ability_table = function() return { name = "Not Discovered", main = {} } end,
  }
  check("safe_name unmasks the undiscovered name", Utils.safe_name(hidden) == "Ankh", Utils.safe_name(hidden))
  check("real_name reveals the owned card's center name", Utils.real_name(hidden) == "Ankh")
  G.consumeables = { cards = { hidden }, config = { card_limit = 2 } }
  G.FUNCS.use_card = function() end
  local c = D.get_action_handler("use_card")({ area = "consumeables", index = 1 })
  local ok_u, r_u = pcall(c)
  check("use feedback names the card", ok_u and r_u == "Used: Ankh", tostring(r_u))
  G.FUNCS.use_card = nil

  mock_state("Normal", "SHOP")
  local shop_hidden = {
    cost = 4, ability = { set = "Joker" },
    config = { center = { key = "j_x", loc_txt = { name = "Mystery Joker" }, set = "Joker" } },
    generate_UIBox_ability_table = function() return { name = "Not Discovered", main = {} } end,
  }
  G.GAME.dollars = 10; G.NEURO.reserved_dollars = 0
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.shop_jokers = { cards = { shop_hidden } }
  G.FUNCS.buy_from_shop = function() end
  local cb = D.get_action_handler("buy_from_shop")({ area = "shop_jokers", index = 1 })
  local ok_b, r_b = pcall(cb)
  check("buy feedback names the card", ok_b and r_b == "Buying: Mystery Joker for $4", tostring(r_b))
  G.FUNCS.buy_from_shop = nil; G.NEURO.reserved_dollars = 0
end

do
  mock_state("Normal", "SHOP")
  local function jk(nm)
    return { ability = { set = "Joker", name = nm }, sell_cost = 2,
      config = { center = { key = "j_" .. nm:lower():gsub(" ", "_"), set = "Joker", loc_txt = { name = nm } } } }
  end
  G.jokers = { cards = { jk("Green Joker"), jk("Abstract Joker"), jk("Ice Cream") },
    config = { card_limit = 5 } }
  G.FUNCS.sell_card = function() end
  local c, err = D.get_action_handler("sell_card")({ area = "jokers", index = 2, name = "Green Joker" })
  check("SELL: name mismatch rejected with both names",
    c == nil and action_error(err):find("'Abstract Joker', not 'Green Joker'", 1, true) ~= nil, tostring(err))
  local c2, err2 = D.get_action_handler("sell_card")({ area = "jokers", index = 2, name = "Abstract Joker" })
  check("SELL: matching name passes validation", c2 ~= nil, tostring(err2))
  G.FUNCS.sell_card = nil
  G.jokers = nil
end

do
  mock_state("Normal", "SHOP")
  local item = { cost = 3, ability = { set = "Joker" }, sell_cost = 1,
    config = { center = { key = "j_gros_michel", set = "Joker", loc_txt = { name = "Gros Michel" } } } }
  G.GAME.dollars = 10; G.NEURO.reserved_dollars = 0
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.shop_jokers = { cards = { item } }
  local c, err = D.get_action_handler("buy_from_shop")({ area = "shop_jokers", index = 1, name = "Wee Joker" })
  check("BUY: name mismatch rejected", c == nil and action_error(err):find("'Gros Michel', not 'Wee Joker'", 1, true) ~= nil, tostring(err))
  local c2 = D.get_action_handler("buy_from_shop")({ area = "shop_jokers", index = 1, name = "gros michel" })
  check("BUY: case-insensitive name match passes", c2 ~= nil)

  mock_state("Normal", "SELECTING_HAND")
  local tarot = { ability = { set = "Tarot", consumeable = {}, name = "The Fool" },
    config = { center = { key = "c_fool", set = "Tarot", loc_txt = { name = "The Fool" } } } }
  G.consumeables = { cards = { tarot }, config = { card_limit = 2 } }
  local c3, err3 = D.get_action_handler("use_card")({ area = "consumeables", index = 1, name = "The Hermit" })
  check("USE: name mismatch rejected", c3 == nil and action_error(err3):find("'The Fool', not 'The Hermit'", 1, true) ~= nil, tostring(err3))
  G.consumeables = nil; G.shop_jokers = nil; G.jokers = nil
end

do
  local GR = require("context.game_rules")
  local ok_f, frame = pcall(GR.invariant_frame)
  check("FRAME: sell economics fact present",
    ok_f and frame and frame:find("Selling returns only the sell value shown", 1, true) ~= nil
    and frame:find("placed in the rightmost joker slot, with no joker to its right", 1, true) ~= nil,
    tostring(frame))
  local ok_r, txt = pcall(GR.run_frame_text)
  check("RUN: sell economics no longer repeated on the ephemeral channel",
    ok_r and txt and txt:find("Selling returns only the sell value shown", 1, true) == nil,
    tostring(txt))
end

do
  mock_state("Normal", "SHOP")
  local shop_j = { cost = 4, ability = { set = "Joker" },
    config = { center = { key = "j_y", loc_txt = { name = "Test Joker" }, set = "Joker" } } }
  G.GAME.dollars = 10; G.NEURO.reserved_dollars = 0
  G.NEURO.last_failed_action = nil; G.NEURO.last_failed_reason = nil; G.NEURO.last_failed_at = nil
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.shop_jokers = { cards = { shop_j } }
  G.FUNCS.buy_from_shop = nil
  local cb = D.get_action_handler("buy_from_shop")({ area = "shop_jokers", index = 1 })
  local ok_b, r_b = pcall(cb)
  check("F-005: missing buy callback returns corrective, not optimistic",
    ok_b and type(r_b) == "string" and r_b:find("Could not buy", 1, true) ~= nil, tostring(r_b))
  check("F-005: missing buy callback records a failure", G.NEURO.last_failed_action == "buy_from_shop")
  G.NEURO.reserved_dollars = 0
  G.NEURO.last_failed_action = nil; G.NEURO.last_failed_reason = nil; G.NEURO.last_failed_at = nil
end

do
  mock_state("Normal", "SHOP")
  local CtxShop = require("context.ctx_shop")
  local shop_j = { cost = 3, ability = { set = "Joker" },
    config = { center = { key = "j_z", loc_txt = { name = "Slot Joker" }, set = "Joker" } } }
  G.GAME.dollars = 20; G.NEURO.reserved_dollars = 0
  G.jokers = { cards = { {}, {}, {}, {}, {} }, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.shop_jokers = { cards = { shop_j } }
  G.shop_vouchers = { cards = {} }
  G.shop_booster = { cards = {} }
  G.GAME.current_round.reroll_cost = 5
  local la = CtxShop.legality_section("SHOP") or ""
  check("F-007: cash-affordable but full-slot joker is not buyable (CB:N)",
    la:find("can buy something: no", 1, true) ~= nil, la)
  check("F-007: CRS is '-' when nothing is buyable to protect",
    la:find("still affordable after: no", 1, true) ~= nil, la)
  local sec = CtxShop.shop_section() or ""
  check("F-007: shop row separates cash from slot on a full-slot joker",
    sec:find("Slot Joker", 1, true) ~= nil
      and sec:find("affordable now: yes, free slot: no", 1, true) ~= nil, sec)
  check("F-007: LOCKED never rewrites CB/CRS affordability",
    la:find("can buy something: no", 1, true) ~= nil and la:find("still affordable after: no", 1, true) ~= nil, la)
end

do
  mock_state("Normal", "SHOP")
  local CtxShop = require("context.ctx_shop")
  local rare_joker = { cost = 6, ability = { set = "Joker" },
    config = { center = { key = "j_rare", set = "Joker", rarity = 3, loc_txt = { name = "Rare J" } } } }
  G.GAME.dollars = 12; G.NEURO.reserved_dollars = 0
  G.GAME.current_round.reroll_cost = 5; G.GAME.current_round.free_rerolls = 0
  G.GAME.modifiers = {}; G.GAME.bankrupt_at = 0
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.shop_jokers = { cards = { rare_joker } }
  G.shop_vouchers = { cards = {} }; G.shop_booster = { cards = {} }
  local sec = CtxShop.shop_section() or ""
  check("I header carries rar column", sec:find("Shop items:", 1, true) ~= nil, sec)
  check("rare joker row shows rarity R", sec:find("(Joker, Rare) $6", 1, true) ~= nil, sec)
  check("SH line carries SP spendable=12", sec:find("$12 in bank.", 1, true) ~= nil, sec)
  check("SH line carries RRN next-reroll=6", sec:find("next $6", 1, true) ~= nil, sec)
  check("SH line carries NXT to next interest step=3", sec:find(", $3 to next step", 1, true) ~= nil, sec)
  G.jokers = { cards = { { config = { center = { key = "j_credit_card", set = "Joker" } },
    ability = { set = "Joker", name = "Credit Card" } } }, config = { card_limit = 5 } }
  local sec2 = CtxShop.shop_section() or ""
  check("Credit Card surfaces FLOOR:-20", sec2:find("Spend floor -$20.", 1, true) ~= nil, sec2)
end

do
  mock_state("Normal", "SHOP")
  local CtxShop = require("context.ctx_shop")
  local Eco = require("facts.economy_facts")
  G.GAME.dollars = 20; G.NEURO.reserved_dollars = 0
  G.GAME.current_round.reroll_cost = 7; G.GAME.current_round.free_rerolls = 0
  G.GAME.modifiers = {}; G.GAME.interest_cap = 25; G.GAME.interest_amount = 1
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.shop_jokers = { cards = {} }; G.shop_vouchers = { cards = {} }; G.shop_booster = { cards = {} }

  check("economy_facts reroll_cost reads live value", Eco.reroll_cost() == 7)
  check("reroll_facts effective == cost when no free reroll", Eco.reroll_facts().effective == 7)
  check("compact SH RR uses helper (RR:7)", (CtxShop.shop_section() or ""):find("Reroll costs $7", 1, true) ~= nil)

  G.GAME.current_round.reroll_cost = nil
  local sh2 = CtxShop.shop_section() or ""
  check("unknown reroll shows RR:? (no fake 5)",
    sh2:find("Reroll costs $?", 1, true) ~= nil and sh2:find("Reroll costs $5", 1, true) == nil, sh2)
  G.GAME.current_round.reroll_cost = 5

  G.GAME.current_round.reroll_cost = 0; G.GAME.current_round.free_rerolls = 1
  G.GAME.current_round.reroll_cost_increase = 0; G.GAME.round_resets = { reroll_cost = 5 }
  local rf = Eco.reroll_facts()
  check("free reroll shown as $0 effective", rf.effective == 0)
  check("first paid reroll after a free one is base+increase (paid=5, next=5)", rf.paid == 5 and rf.next == 5)
  G.GAME.current_round.free_rerolls = 0; G.GAME.current_round.reroll_cost = 5
end

do
  local by_name = {}
  for _, def in ipairs(require("core.actions").get_static_actions()) do by_name[def.name] = def end
  check("evaluate_play is no longer registered", by_name.evaluate_play == nil)
  check("simulate_hand is no longer registered", by_name.simulate_hand == nil)
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("5", "Hearts"), card("5", "Spades"), card("9", "Clubs") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 3
  G.NEURO.once_serials = {}
  local q = (D.get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("B-C1: query omits the shape-only caveat", q:find("shape only", 1, true) == nil, q)
  check("B-C4: query omits evaluate_play prose", q:find("evaluate_play|", 1, true) == nil)
  check("B-C2: query omits the duplicated Active debuff line", q:find("Active debuff:", 1, true) == nil)
  check("query omits the once-per-entry deck strategy hint", q:find("Deck: ", 1, true) == nil, q)
  check("B-O1: commit ask is the query tail", q:find("Your move: ", 1, true) ~= nil
    and q:gsub("%s+$", ""):find("uses a %w+%)%.$") ~= nil, q)
  check("economy rules gone from the query", q:find("At round end each unused hand", 1, true) == nil)
  local state = ContextCompact.build("SELECTING_HAND", nil, { split = "state", no_cache = true })
  check("economy rules ride the ephemeral RUN| state", state:find("RUN|", 1, true) ~= nil
    and state:find("At round end each unused hand", 1, true) ~= nil)
end

do
  mock_state("Normal", "SHOP")
  local blob = ContextCompact.build("SHOP", nil, { no_cache = true })
  local sh = blob:match("SH|[^\n]*")
  check("SH economy line dropped the duplicated J:/C: slot pair",
    not (sh and sh:find("|J:%d+/%d+|C:%d+/%d+")), sh)
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("2", "Hearts"), card("5", "Hearts"), card("7", "Hearts"), card("9", "Hearts"), card("King", "Spades") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3
  G.GAME.current_round.discards_left = 2
  G.NEURO.once_serials = {}
  local q = ((D.get_force_for_state("SELECTING_HAND") or {}).query or "") .. require("tests.helpers").drain_hints()
  check("FRAME: principle line present", q:find("the exact cards that form it", 1, true) ~= nil, q)
  check("FRAME: does not prescribe a hand type (High Card/Pair builds stay valid)",
    q:find("any hand type counts", 1, true) ~= nil and q:find("Prefer a Ready hand", 1, true) == nil, q)
  check("FRAME: no computed Pace line", q:find("Pace:", 1, true) == nil, q)
  check("FRAME: no DB/LOCK line without a debuffed/forced card", q:find("DB cards score 0", 1, true) == nil, q)

  G.GAME.current_round.discards_left = 0
  G.NEURO.once_serials = {}
  local q2 = ((D.get_force_for_state("SELECTING_HAND") or {}).query or "") .. require("tests.helpers").drain_hints()
  check("FRAME: principle line still present without Close", q2:find("the exact cards that form it", 1, true) ~= nil, q2)

  G.GAME.current_round.discards_left = 2
  local dc = card("5", "Clubs"); dc.debuff = true
  G.hand = { cards = { dc, card("9", "Diamonds"), card("King", "Spades") }, highlighted = {} }
  local q3 = ((D.get_force_for_state("SELECTING_HAND") or {}).query or "") .. require("tests.helpers").drain_hints()
  check("FRAME: no duplicate DB sentence (Structure carries it)",
    q3:find("DB cards score 0", 1, true) == nil
    and q3:find("DEBUFFED (they score 0)", 1, true) ~= nil, q3)
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("2", "Hearts"), card("5", "Hearts"), card("7", "Hearts"),
    card("9", "Hearts"), card("King", "Spades") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3
  G.GAME.current_round.discards_left = 2
  G.GAME.blind = { chips = 700 }
  G.GAME.chips = 100
  G.deck = { cards = { card("6", "Hearts"), card("Jack", "Hearts"), card("3", "Spades"),
    card("3", "Clubs"), card("Ace", "Diamonds") } }
  G.deck.cards[1].config.center.key = "m_glass"
  G.deck.cards[3].seal = "Red"
  G.NEURO.once_serials = {}
  local q = ((D.get_force_for_state("SELECTING_HAND") or {}).query or "") .. require("tests.helpers").drain_hints()
  check("NEED: single canonical decision line (was NOW+NEED duplicated)", q:find("You still need 600 chips, with 3 hand(s) and 2 discard(s) left.", 1, true) ~= nil, q)
  check("FRAME: rules are numbered 1-4",
    q:find("Rules: 1)", 1, true) ~= nil and q:find("2)", 1, true) ~= nil
    and q:find("3)", 1, true) ~= nil and q:find("4)", 1, true) ~= nil, q)
  local blob = ContextCompact.build("SELECTING_HAND", A.get_valid_actions_for_state("SELECTING_HAND"), { no_cache = true })
  check("DD: draw-pile composition line present",
    blob:find("Unplayed pool by suit: 2 Hearts, 1 Spades, 1 Diamonds, 1 Clubs. Ranks in that pool: A x1, J x1, 6 x1, 3 x2.", 1, true) ~= nil,
    blob:match("Draw pile[^\n]*") or blob)
  check("DD: draw-pile modifier census is scoped to what is still unseen",
    blob:find("Modifiers in that pool: seals Red x1; enhancements Glass x1.", 1, true) ~= nil,
    blob:match("Modifiers in that pool[^\n]*") or blob)
  G.deck = nil
  G.GAME.blind = nil
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("2", "Hearts"), card("5", "Hearts"), card("7", "Hearts"),
    card("9", "Hearts"), card("King", "Spades") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3
  G.GAME.current_round.discards_left = 2
  G.GAME.blind = { chips = 700 }
  G.GAME.chips = 100
  local function frame()
    return ((D.get_force_for_state("SELECTING_HAND") or {}).query or "")
      .. require("tests.helpers").drain_hints()
  end
  G.NEURO.once_serials = {}
  G.NEURO.state_enter_serial = 1
  check("FRAME: the rules core is taught on the first entry",
    frame():find("Rules: 1)", 1, true) ~= nil)
  G.NEURO.state_enter_serial = 2
  check("FRAME: the current rules repeat on the next entry into the same state",
    frame():find("Rules: 1)", 1, true) ~= nil)
  G.NEURO.state_enter_serial = 7
  check("FRAME: current rules remain self-contained several entries later",
    frame():find("Rules: 1)", 1, true) ~= nil)
  G.NEURO.once_serials = {}
  check("FRAME: a new run teaches them again",
    frame():find("Rules: 1)", 1, true) ~= nil)
  G.GAME.blind = nil
end

do
  local U = require("util.utils")
  local function mk(valnode)
    return { generate_UIBox_ability_table = function()
      return { main = {
        { config = { text = "(Currently " } },
        { config = { object = { config = { string = { valnode } } } } },
        { config = { text = " Mult)" } },
      } }
    end }
  end
  check("JOKER0: numeric DynaText value 0 is kept (not dropped)",
    (U.card_description(mk({ string = 0 })) or ""):find("Currently 0 Mult", 1, true) ~= nil,
    U.card_description(mk({ string = 0 })))
  check("JOKER0: numeric DynaText value 5 is kept",
    (U.card_description(mk({ string = 5 })) or ""):find("Currently 5 Mult", 1, true) ~= nil,
    U.card_description(mk({ string = 5 })))
  check("JOKER0: two numeric values still collapse to a range",
    (U.card_description({ generate_UIBox_ability_table = function()
      return { main = { { config = { object = { config = { string = { { string = 1 }, { string = 6 } } } } } } } }
    end }) or ""):find("1 to 6", 1, true) ~= nil, "range")
end

do
  local Staging = require("core.staging")
  local CardArea = require("facts.card_area_util")
  check("SIZE: min-cards violation flagged", CardArea.blind_size_rule_error({ h_size_ge = 5 }, 2) ~= nil)
  check("SIZE: legal count passes", CardArea.blind_size_rule_error({ h_size_ge = 5 }, 5) == nil)
  check("SIZE: max-cards violation flagged", CardArea.blind_size_rule_error({ h_size_le = 3 }, 4) ~= nil)
  check("SIZE: no debuff passes", CardArea.blind_size_rule_error(nil, 2) == nil)
  local saved = G.GAME and G.GAME.blind
  local saved_hands = G.GAME and G.GAME.current_round and G.GAME.current_round.hands_left
  local saved_discards = G.GAME and G.GAME.current_round and G.GAME.current_round.discards_left
  local saved_gpi = G.FUNCS and G.FUNCS.get_poker_hand_info
  G.GAME = G.GAME or {}
  G.GAME.current_round = G.GAME.current_round or {}
  G.GAME.current_round.hands_left, G.GAME.current_round.discards_left = 1, 0
  G.GAME.blind = { disabled = false, debuff = { h_size_ge = 5 } }
  if G.FUNCS then G.FUNCS.get_poker_hand_info = nil end
  check("SIZE: should_stage=false for 2 cards vs must-play-5 (instant reject)",
    Staging.should_stage({ command = "action", data = { name = "play_hand", indices = { 1, 2 }, id = "sz1" } }) == false)
  check("SIZE: should_stage=true for a legal forced 5-card play",
    Staging.should_stage({ command = "action", data = { name = "play_hand", indices = { 1, 2, 3, 4, 5 }, id = "sz2" } }) == true)
  G.GAME.blind = saved
  G.GAME.current_round.hands_left, G.GAME.current_round.discards_left = saved_hands, saved_discards
  if G.FUNCS then G.FUNCS.get_poker_hand_info = saved_gpi end
end

do
  local Staging = require("core.staging")
  local c1 = card("King", "Hearts"); c1.sort_id = 901
  local c2 = card("King", "Spades");  c2.sort_id = 902
  local c3 = card("9", "Clubs");      c3.sort_id = 903
  local saved_blind = G.GAME and G.GAME.blind
  local saved_hand = G.hand
  local saved_gpi = G.FUNCS and G.FUNCS.get_poker_hand_info
  G.GAME = G.GAME or {}; G.GAME.blind = { disabled = true }
  G.GAME.current_round = G.GAME.current_round or {}
  G.GAME.current_round.discards_left = 2
  G.hand = { cards = { c1, c2, c3 }, highlighted = {} }
  G.FUNCS = G.FUNCS or {}
  G.FUNCS.get_poker_hand_info = function(_) return "Pair", nil, { Pair = { c1, c2 } }, { c1, c2 }, nil end
  G.NEURO.play_confirm = nil
  G.NEURO.weak_fired_serial = nil
  local msg = { command = "action", data = { name = "play_hand", indices = { 1, 2 }, id = "wk1" } }
  check("WEAK: should_stage=false for a first play with discards left (no card-lift on the pause)",
    Staging.should_stage(msg) == false)
  G.NEURO.play_confirm = {
    signature = "901,902",
    content = require("handlers.hand_handlers").play_content({ c1, c2 }),
    indices = { 1, 2 }, decision_serial = tonumber(G.NEURO.decision_serial) or 0,
    run_generation = tonumber(G.NEURO.run_generation) or 0,
  }
  G.NEURO.weak_fired_serial = tonumber(G.NEURO.decision_serial) or 0
  check("WEAK: should_stage=true on the re-send (cards lift for the real play)",
    Staging.should_stage(msg) == true)
  G.NEURO.play_confirm = nil
  G.NEURO.weak_fired_serial = nil
  G.GAME.current_round.discards_left = 0
  check("CONFIRM: first play at 0 discards still requests review",
    Staging.should_stage(msg) == false)
  G.NEURO.play_confirm = {
    signature = "901,902",
    content = require("handlers.hand_handlers").play_content({ c1, c2 }),
    indices = { 1, 2 }, decision_serial = tonumber(G.NEURO.decision_serial) or 0,
    run_generation = tonumber(G.NEURO.run_generation) or 0,
  }
  check("CONFIRM: re-send at 0 discards stages the reviewed play",
    Staging.should_stage(msg) == true)
  G.GAME.blind = saved_blind; G.hand = saved_hand
  if G.FUNCS then G.FUNCS.get_poker_hand_info = saved_gpi end
  G.NEURO.play_confirm = nil
  G.NEURO.weak_fired_serial = nil

end

do
  local J = require("util.neuro_json")
  local Staging = require("core.staging")
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("King", "Hearts"), card("King", "Spades"), card("9", "Clubs"),
    card("4", "Diamonds"), card("8", "Clubs") }, highlighted = {} }
  G.GAME.current_round.discards_left = 3; G.GAME.current_round.hands_left = 4
  G.GAME.blind = {}
  G.FUNCS.get_poker_hand_info = function(_) return "Pair", nil, { Pair = { {} } }, {}, nil end
  G.NEURO.play_confirm = nil
  G.NEURO.weak_fired_serial = nil
  local real = { command = "action",
    data = { name = "play_hand", id = "j1", data = J.encode({ indices = { 1, 2 } }) } }
  check("JANK: real-shape (nested data.data) play_hand to be rejected is NOT staged",
    Staging.should_stage(real) == false)
end

do
  local J = require("util.neuro_json")
  local Staging = require("core.staging")
  mock_state("BUFFOON_PACK variant", "BUFFOON_PACK")
  G.STATES = { BUFFOON_PACK = 9 }; G.STATE = 9
  G.NEURO.state_enter_serial = 4
  require("core.decision_window").reset_field("pack_review")
  local pk = { command = "action",
    data = { name = "use_card", id = "b1", data = J.encode({ area = "booster_pack", index = 1 }) } }
  check("JANK: booster pick with pack-think pending is NOT staged", Staging.should_stage(pk) == false)
  require("core.decision_window").evaluate("use_card")
  check("JANK: booster pick on confirm re-send IS staged", Staging.should_stage(pk) == true)
  require("core.decision_window").reset_field("pack_review")
end

do
  local Staging = require("core.staging")
  local J = require("util.neuro_json")
  mock_state("Normal", "SELECTING_HAND")
  G.STATES = { SHOP = 5 }; G.STATE = 5
  G.shop_jokers = { cards = { { ability = { name = "Mad Joker", set = "Joker" },
    config = { center = { key = "j_mad" } }, cost = 4 } } }
  G.NEURO.econ_plan_ok = true
  local function buy_msg(nm)
    return { command = "action", data = { name = "buy_from_shop", id = "b",
      data = J.encode({ area = "shop_jokers", index = 1, name = nm }) } }
  end
  check("SHOP-JANK: buy with matching name stages", Staging.should_stage(buy_msg("Mad Joker")) == true)
  check("SHOP-JANK: buy with mismatched name does NOT stage (no wrong-card hover)",
    Staging.should_stage(buy_msg("Luchador")) == false)
  local saved_plan = G.NEURO.plan
  G.NEURO.econ_plan_ok = nil
  G.NEURO.plan = nil
  local _, tx_err = require("core.plan_transaction").prepare("buy_from_shop",
    { area = "shop_jokers", index = 1, name = "Mad Joker" })
  local tx_code = require("core.action_result").normalize(tx_err).reason_code
  check("SHOP-JANK: a buy with no money plan is refused by the plan gate, and staging is not the gate",
    tx_code == "PRECONDITION_FAILED" and Staging.should_stage(buy_msg("Mad Joker")) == true,
    tostring(tx_code))
  G.shop_jokers = nil; G.STATES = nil; G.STATE = nil; G.NEURO.econ_plan_ok = nil; G.NEURO.plan = saved_plan
end

do
  local DF = require("facts.debuff_facts")
  local CtxBlind = require("context.ctx_blind")
  local CtxMisc = require("context.ctx_misc")
  _G.localize = function(args)
    if type(args) == "table" and args.type == "raw_descriptions" then
      if args.set == "Blind" and args.key == "bl_pillar" then
        return { "Cards played previously this ante are debuffed" }
      end
      if args.set == "Tag" and args.key == "tag_charm" then
        return { "Gives a free Mega Arcana Pack" }
      end
      if args.set == "Voucher" and args.key == "v_grabber" then
        return { "Permanently gain +" .. tostring(args.vars and args.vars[1] or "?") .. " hand per round" }
      end
    end
    return nil
  end

  mock_state("Small blind selectable", "BLIND_SELECT")
  G.P_BLINDS = {
    bl_small = { name = "Small Blind", dollars = 3, debuff = {} },
    bl_big = { name = "Big Blind", dollars = 4, debuff = {} },
    bl_pillar = { name = "The Pillar", dollars = 5, debuff = {}, boss = { min = 1 } },
  }
  G.P_TAGS = { tag_charm = { name = "Charm Tag", config = {} } }
  G.GAME.round_resets.blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_pillar" }
  G.GAME.round_resets.blind_tags = { Small = "tag_charm" }
  local s = CtxBlind.blind_select_section() or ""
  check("CW1: BO boss row suppresses the native desc once boss_brief covers Pillar",
    s:find("Cards played previously this ante are debuffed", 1, true) == nil, s:match("Boss[^\n]*"))
  check("CW2: BO tag_effect carries localized tag text",
    s:find("Gives a free Mega Arcana Pack", 1, true) ~= nil, s:match("Small[^\n]*"))

  local f = require("force.force_blind_select").build("")
  local q = (f or {}).query or ""
  check("CW1: the boss row carries the Pillar advisory instead of the native desc",
    s:find("during the Small and Big blinds) are debuffed", 1, true) ~= nil, s:match("Boss[^\n]*"))
  check("CW1: force offers select_blind and points at that row rather than repeating it",
    has((f or {}).actions, "select_blind")
      and q:find('Boss rule is stated in full on the "Boss blind The Pillar" row above', 1, true) ~= nil
      and q:find("during the Small and Big blinds) are debuffed", 1, true) == nil
      and q:find("Cards played previously this ante", 1, true) == nil, q)
  check("CW2: force query does not duplicate the tag reward text",
    q:find("Skip reward:", 1, true) == nil and q:find("Gives a free Mega Arcana Pack", 1, true) == nil, q)

  G.GAME.tags = { { key = "tag_charm", config = {} } }
  local ts = CtxMisc.tags_section() or ""
  check("CW2: owned TAGS carries localized effect", ts:find("Gives a free Mega Arcana Pack", 1, true) ~= nil, ts)
  G.GAME.tags = nil
  G.P_CENTERS = { v_grabber = { name = "Grabber", key = "v_grabber", set = "Voucher", config = { extra = 1 } } }
  G.GAME.used_vouchers = { v_grabber = true }
  local vs = CtxMisc.vouchers_section() or ""
  check("CW8: V| carries localized voucher effect with engine vars",
    vs:find("Permanently gain +1 hand per round", 1, true) ~= nil, vs)
  G.GAME.used_vouchers = nil; G.P_CENTERS = nil

  _G.localize = nil
  check("CW1: P_BLINDS loc_txt fallback still works",
    DF.blind_effect_text("bl_mod", { name = "Mod Blind", loc_txt = { text = { "Modded effect" } } }) == "Modded effect")
  G.P_BLINDS = nil; G.P_TAGS = nil
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.GAME.hands = { Pair = { visible = true, level = 1, chips = 10, mult = 2, played = 4 } }
  G.GAME.pack_choices = 1
  local planet = { ability = { set = "Planet", name = "Pluto" }, config = { center = { key = "c_pluto" } } }
  G.pack_cards = { cards = { planet } }
  local blob = ContextCompact.build("SMODS_BOOSTER_OPENED", nil, { no_cache = true, split = "volatile" })
  local _, levels_count = blob:gsub("Hand levels:", "Hand levels:")
  check("CW3: planet card visible -> L: attached exactly once", levels_count == 1, blob)

  local playing = card("9", "Hearts")
  G.pack_cards = { cards = { playing } }
  G.deck = { cards = { card("Ace", "Spades"), card("King", "Hearts") } }
  blob = ContextCompact.build("SMODS_BOOSTER_OPENED", nil, { no_cache = true, split = "volatile" })
  check("CW3: playing card visible -> DC aggregate attached", blob:find("2 cards left in the draw pile", 1, true) ~= nil, blob)
  local _, n0 = blob:gsub("Hand levels:", "Hand levels:")
  check("CW3: booster context always attaches L: exactly once", n0 == 1, blob)
  G.pack_cards = nil; G.deck = nil
end

do
  mock_state("Normal", "SHOP")
  G.GAME.hands = {
    Pair = { visible = true, level = 2, chips = 20, mult = 3, played = 6 },
    Flush = { visible = true, level = 1, chips = 35, mult = 4, played = 0 },
  }
  G.shop_jokers = { cards = {}, config = { card_limit = 2 } }
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  local blob_plan = ContextCompact.build("SHOP", nil, { no_cache = true, split = "volatile" })
  local _, np = blob_plan:gsub("Hand levels:", "Hand levels:")
  check("CW4: SHOP always shows the L: table exactly once", np == 1, blob_plan)
  G.shop_jokers = { cards = { { ability = { set = "Planet", name = "Pluto" }, config = { center = { key = "c_pluto" } } } }, config = { card_limit = 2 } }
  local blob = ContextCompact.build("SHOP", nil, { no_cache = true, split = "volatile" })
  local _, nb = blob:gsub("Hand levels:", "Hand levels:")
  check("CW4: SHOP with a buyable Planet has L: table exactly once", nb == 1, blob)
  check("CW4: SHOP L: upgraded hands listed and base summarized", blob:find("Pair: level 2, 20 chips x 3 mult = 60 before any card or joker, played 6.", 1, true) ~= nil
    and blob:find("all other hands: level 1", 1, true) ~= nil, blob:match("Hand levels:[^\n]*\n[^\n]*\n[^\n]*"))
  G.shop_jokers = nil; G.jokers = nil
end

do
  local CtxHand = require("context.ctx_hand")
  local CtxBlind = require("context.ctx_blind")
  mock_state("Normal", "SELECTING_HAND")
  G.GAME.hands = { Pair = { visible = true, level = 2, chips = 20, mult = 4, played = 7, played_this_round = 1 } }
  local ls = CtxHand.levels_section() or ""
  check("CW5: L row has p column (times played this run)", ls:find("Pair: level 2, 20 chips x 4 mult = 80 before any card or joker, played 7.", 1, true) ~= nil, ls)

  G.GAME.blind = { name = "The Ox", debuff = {}, loc_txt = { text = { "Ox flavor text" } } }
  G.GAME.current_round.most_played_poker_hand = "Flush"
  local bd = CtxBlind.blind_debuff_line() or ""
  check("CW5: Ox FACT line names the engine most-played snapshot",
    bd:find("Playing a Flush sets your money to $0", 1, true) ~= nil, bd)
  G.GAME.current_round.most_played_poker_hand = nil
  local bd2 = CtxBlind.blind_debuff_line() or ""
  check("CW5: Ox line never recomputes the snapshot -- no hand name is invented when the engine field is unset",
    bd2:find("Flush", 1, true) == nil and bd2:find("Playing a ?", 1, true) ~= nil, bd2)

  G.GAME.blind = { name = "The Eye", debuff = {}, hands = { Pair = true } }
  local bd3 = CtxBlind.blind_debuff_line() or ""
  check("CW5: Eye FACT line renders every decision and carries the engine used-set",
    bd3:find("Hand types already played this round: Pair", 1, true) ~= nil, bd3)
  G.GAME.blind.hands = {}
  local bd4 = CtxBlind.blind_debuff_line() or ""
  check("CW5: Eye FACT line before the first play states an empty used-set, not nothing",
    bd4:find("Hand types already played this round: none", 1, true) ~= nil, bd4)
  G.GAME.blind = nil

  mock_state("Small blind selectable", "BLIND_SELECT")
  G.P_BLINDS = { bl_ox = { name = "The Ox", dollars = 5, debuff = {}, boss = { min = 6 } } }
  G.GAME.round_resets.blind_choices = { Boss = "bl_ox" }
  G.GAME.current_round.most_played_poker_hand = "Two Pair"
  local q = (require("force.force_blind_select").build("") or {}).query or ""
  local ox_row = CtxBlind.blind_select_section() or ""
  check("CW5: known Ox boss names most_played on the row the force points at",
    ox_row:find("Playing a Two Pair sets your money to $0", 1, true) ~= nil, ox_row)
  check("CW5: the force names that row",
    q:find('Boss rule is stated in full on the "Boss blind The Ox" row above', 1, true) ~= nil, q)
  G.P_BLINDS = nil
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("5", "Hearts"), card("5", "Spades"), card("9", "Clubs") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 3
  local f = D.get_force_for_state("SELECTING_HAND")
  check("CW6: force does NOT offer simulate_hand (progress-only force set)", f and not has(f.actions, "simulate_hand"))
  check("CW6: simulate_hand no longer registered for SELECTING_HAND",
    not has(A.get_valid_actions_for_state("SELECTING_HAND"), "simulate_hand"))
  check("CW6: simulate_hand no longer in NON_PROGRESS", require("core.action_policy").NON_PROGRESS.simulate_hand == nil)
  check("CW6: simulate_hand is not registered at all",
    require("core.action_registry").get("simulate_hand") == nil)
end

do
  local HF = require("facts.hand_facts")
  mock_state("Normal", "SELECTING_HAND")
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2
  G.GAME.hands = {
    ["Full House"] = { visible = true, level = 1, chips = 40, mult = 4, played = 2 },
    ["Pair"] = { visible = true, level = 1, chips = 10, mult = 2, played = 5 },
  }
  G.jokers = { cards = {
    { ability = { name = "Joker", mult = 4 }, config = { center = { key = "j_joker" } } },
    { ability = { name = "Supernova", type = "Full House", t_mult = 3 }, config = { center = { key = "j_x" } } },
  }, config = { card_limit = 5 } }
  G.hand = { cards = { card("King", "Hearts"), card("King", "Spades"), card("King", "Clubs"),
    card("4", "Diamonds"), card("8", "Clubs"), card("Queen", "Hearts"), card("Queen", "Diamonds") }, highlighted = {} }
  local hc = G.hand.cards
  G.FUNCS.get_poker_hand_info = function(_)
    return "Full House", nil, {
      ["Full House"] = { { hc[1], hc[2], hc[3], hc[6], hc[7] } },
      ["Pair"] = { { hc[6], hc[7] } },
    }, { hc[1], hc[2], hc[3], hc[6], hc[7] }, nil
  end
  local s = HF.summary()
  check("D1+D2: Ready row = base facts + valued joker note",
    s:find("Full House[1,2,3,6,7](lv1 40c x4)(J2 +3m)", 1, true) ~= nil, s:match("Ready:[^%.]*"))
  check("non-conditional hand gets base facts only, no joker note",
    s:find("Pair[6,7](lv1 10c x2)", 1, true) ~= nil and s:find("Pair%[6,7%]%(lv1 10c x2%)%(J", 1) == nil,
    s:match("Ready:[^%.]*"))

  G.jokers.cards[2].ability = { name = "Joker2", mult = 2 }
  local s0 = HF.summary()
  check("no conditional joker -> no joker note", s0:find("(J", 1, true) == nil, s0:match("Ready:[^%.]*"))
  G.jokers.cards[2].ability = { name = "Supernova", type = "Full House", t_mult = 3 }

  hc[1].debuff = true; hc[2].debuff = true
  local s2 = HF.summary()
  check("partial debuff count on Ready row",
    s2:find("Full House[1,2,3,6,7](lv1 40c x4)(J2 +3m)(2 debuffed~0)", 1, true) ~= nil, s2:match("Ready:[^%.]*"))
  hc[1].debuff = nil; hc[2].debuff = nil

  G.jokers.cards[1].config.center.key = "j_splash"
  local s3 = HF.summary()
  check("Splash fact appended", s3:find("All played cards score (Splash)", 1, true) ~= nil, s3)
  check("Splash fact states the play cap", s3:find("play at most 5", 1, true) ~= nil, s3)
  G.FUNCS.get_poker_hand_info = nil
  G.jokers = nil
end

do
  mock_state("Normal", "SHOP")
  local long_desc = "Adds the number of times poker hand has been played this run to Mult when scoring"
  local jk = {
    cost = 5, ability = { set = "Joker", name = "LongDesc" },
    config = { center = { key = "j_long", set = "Joker" } },
    generate_UIBox_ability_table = function()
      return { name = "LongDesc", main = { { config = { text = long_desc } } } }
    end,
  }
  G.GAME.dollars = 10; G.NEURO.reserved_dollars = 0
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.shop_jokers = { cards = { jk } }
  local s = require("context.ctx_shop").shop_section() or ""
  check("trunc: >56-char shop description renders whole", s:find(long_desc, 1, true) ~= nil, s:match("shop_jokers[^\n]*"))
  G.shop_jokers = nil; G.jokers = nil
end

do
  local P = require("render.palette")
  local Tn = require("core.config")
  P.reset_all_colors("neuro"); P.reset_all_colors("evil"); P.reset_all_colors("hiyori")
  local live = P.get_color("neuro", "ACCENT")
  local dft = P.default_color("neuro", "ACCENT")
  check("colour: defaults snapshotted", dft ~= nil and type(dft[1]) == "number")
  local function near(a, b) return math.abs(a - b) < 1e-9 end
  P.set_override("neuro", "ACCENT", 10 / 255, 20 / 255, 30 / 255)
  check("colour: override mutates live table in place",
    near(live[1], 10 / 255) and near(live[2], 20 / 255) and near(live[3], 30 / 255))
  check("colour: override is stored in native config",
    Tn._test.get_colour("neuro", "ACCENT") == "0A141E")
  P.reset_all_colors("neuro")
  check("colour: reset-all restores snapshot values",
    near(live[1], dft[1]) and near(live[2], dft[2]) and near(live[3], dft[3]))
  check("colour: reset-all removes native override",
    Tn._test.get_colour("neuro", "ACCENT") == nil)
  local evil = P.get_color("evil", "ACCENT")
  local evil_d = P.default_color("evil", "ACCENT")
  check("colour: neuro override does not leak into evil",
    near(evil[1], evil_d[1]) and near(evil[2], evil_d[2]) and near(evil[3], evil_d[3]))
  check("colour: color_keys skips non-colour entries (NAME/MOTION)", (function()
    for _, k in ipairs(P.color_keys("neuro")) do
      if k == "NAME" or k == "MOTION" then return false end
    end
    return #P.color_keys("neuro") > 0
  end)())
  P.reset_all_colors("neuro")
end

do
  local real_selftest = require("core.selftest")
  local real_panel = package.loaded["hud.tuning_panel"]
  package.loaded["hud.tuning_panel"] = nil
  local st_started = 0
  package.loaded["core.selftest"] = {
    available = function() return false end,
    start = function() st_started = st_started + 1 return true end,
    running = function() return false end,
    status = function() return "selftest: idle" end,
    abort = function() end,
    results = function() return {} end,
    report_path = function() return nil end,
  }
  local Panel = require("hud.tuning_panel")
  check("selftest row: panel opens on BASICS", Panel.toggle() == true and (Panel._test.state()) == 1)
  Panel.keypressed("up")
  Panel.keypressed("up")
  Panel.keypressed("return")
  check("basics: advanced action opens ADVANCED", (Panel._test.state()) == 2)
  Panel.keypressed("up")
  Panel.keypressed("return")
  check("selftest row: start NOT called while unavailable", st_started == 0)
  package.loaded["core.selftest"].available = function() return true end
  Panel.keypressed("return")
  check("selftest row: start called once available", st_started == 1)
  check("selftest row: 'a' not swallowed when idle", Panel.keypressed("a") == false)
  package.loaded["core.selftest"].running = function() return true end
  check("selftest row: 'a' swallowed while running", Panel.keypressed("a") == true)
  G.NEURO.llm_paused = nil
  package.loaded["core.selftest"] = real_selftest
  package.loaded["hud.tuning_panel"] = real_panel
end

do
  local made = 0
  local prev_graphics = love.graphics
  love.graphics = { newFont = function(path, px) made = made + 1 return { path = path, px = px } end }
  local U2 = require("util.utils")
  local s1, b1 = U2.load_font_pair("f.ttf", 12, 14, 1.15)
  local s2, b2 = U2.load_font_pair("f.ttf", 12, 14, 1.15)
  check("font cache: same scaled request returns same objects", s1 == s2 and b1 == b2)
  check("font cache: px rounds to integer (14 x 1.15 -> 16)", b1.px == 16)
  local made_before = made
  U2.load_font_pair("f.ttf", 12, 14, 1.15)
  check("font cache: cached request allocates no new font", made == made_before)
  local s3, b3 = U2.load_font_pair("f.ttf", 12, 14, 0.5)
  check("font cache: different scale is a different size", s3 ~= s1 and s3.px == 6 and b3.px == 7)
  check("font cache: unscaled equals scale 1.0", select(2, U2.load_font_pair("f.ttf", 12, 14))
    == select(2, U2.load_font_pair("f.ttf", 12, 14, 1.0)))
  love.graphics = prev_graphics
end

do
  local real_panel = package.loaded["hud.tuning_panel"]
  package.loaded["hud.tuning_panel"] = nil
  local prev_graphics = love.graphics
  local prev_mouse = love.mouse
  local rect_calls = {}
  local color_calls = {}
  local font_sizes = {}
  local scissor_calls = {}
  local scissor = nil
  local print_colors = {}
  local circle_calls = {}
  local line_calls = {}
  local polygon_calls = {}
  local rounded_rects = 0
  local cur_color = ""
  local screen_w, screen_h = 1280, 720
  local stub_font = {
    getHeight = function() return 14 end,
    getWidth = function(_, s) return 7 * #tostring(s) end,
  }
  love.graphics = {
    getFont = function() return stub_font end,
    setFont = function() end,
    getWidth = function() return screen_w end,
    getHeight = function() return screen_h end,
    setColor = function(r, g, b)
      cur_color = table.concat({ r or 0, g or 0, b or 0 }, ",")
      color_calls[#color_calls + 1] = cur_color
    end,
    newFont = function(px)
      font_sizes[#font_sizes + 1] = px
      return stub_font
    end,
    setLineWidth = function() end,
    line = function() line_calls[#line_calls + 1] = true end,
    print = function() print_colors[#print_colors + 1] = cur_color end,
    rectangle = function(mode, _x, _y, _w, _h, rx)
      rect_calls[#rect_calls + 1] = mode
      if rx and rx > 0 then rounded_rects = rounded_rects + 1 end
    end,
    circle = function(mode) circle_calls[#circle_calls + 1] = mode end,
    polygon = function() polygon_calls[#polygon_calls + 1] = true end,
    setScissor = function(x, y, w, h)
      scissor = x and { x, y, w, h } or nil
      scissor_calls[#scissor_calls + 1] = x and table.concat({ x, y, w, h }, ",") or "clear"
    end,
    getScissor = function()
      if not scissor then return nil end
      return scissor[1], scissor[2], scissor[3], scissor[4]
    end,
  }
  love.mouse = { getPosition = function() return -1, -1 end }
  local Shud = require("hud.state")
  local pf, pfs = Shud.panel_font, Shud.panel_font_small
  Shud.panel_font, Shud.panel_font_small = stub_font, stub_font
  local Tn = require("core.config")
  local real_save = Tn.save
  Tn.save = function() return true end
  local Panel = require("hud.tuning_panel")

  check("mouse: closed panel ignores clicks", Panel.mousepressed(640, 360, 1) == false)
  Panel.toggle()
  local prior_persona = G.NEURO.persona
  ;(function()
    local sty0 = Panel._test.style
    local function style_snap()
      return table.concat(sty0.accent, ","),
        table.concat(sty0.panel, ",") .. "|" .. table.concat(sty0.surface, ",")
        .. "|" .. table.concat(sty0.border, ",") .. "|" .. table.concat(sty0.text, ",")
        .. "|" .. table.concat(sty0.muted, ",") .. "|" .. table.concat(sty0.faint, ",")
    end
    color_calls = {}
    Panel.draw()
    local neuro_style = table.concat(color_calls, "|")
    local accent_a, chrome_a = style_snap()
    G.NEURO.persona = (prior_persona == "evil") and "neuro" or "evil"
    color_calls = {}
    Panel.draw()
    local other_style = table.concat(color_calls, "|")
    local accent_b, chrome_b = style_snap()
    G.NEURO.persona = prior_persona
    Panel.draw()
    check("style: the accent follows the active persona",
      neuro_style ~= other_style and accent_a ~= accent_b
        and neuro_style:find(accent_a, 1, true) ~= nil
        and other_style:find(accent_b, 1, true) ~= nil)
    check("style: the neutral chrome does not change with persona", chrome_a == chrome_b)
  end)()
  local H = Panel._test.hit
  local stable_ph = H.ph
  local function u_ref(v) return math.floor(v * Panel._test.scale() + 0.5) end
  local function channel(v)
    if v <= 0.04045 then return v / 12.92 end
    return ((v + 0.055) / 1.055) ^ 2.4
  end
  local function luminance(c)
    return 0.2126 * channel(c[1]) + 0.7152 * channel(c[2]) + 0.0722 * channel(c[3])
  end
  local function contrast(a, b)
    local la, lb = luminance(a), luminance(b)
    if la < lb then la, lb = lb, la end
    return (la + 0.05) / (lb + 0.05)
  end
  local sty = Panel._test.style
  check("style: primary text contrast is at least 7:1", contrast(sty.text, sty.panel) >= 7)
  check("style: accent contrast is at least 4.5:1", contrast(sty.accent, sty.panel) >= 4.5)
  check("style: muted text contrast is at least 4.5:1", contrast(sty.muted, sty.panel) >= 4.5)
  ;(function()
    local floor_ok, floor_worst = true, nil
    for _, pk in ipairs({ "neuro", "evil", "hiyori" }) do
      G.NEURO.persona = pk
      Panel.draw()
      local c = contrast(sty.accent, sty.panel)
      if c < 4.5 then
        floor_ok = false
        floor_worst = floor_worst or string.format("%s -> %.2f:1", pk, c)
      end
    end
    G.NEURO.persona = prior_persona
    Panel.draw()
    check("style: every persona's resolved accent clears 4.5:1 on the panel",
      floor_ok, floor_worst)
  end)()
  local LY = Panel._test.layout
  check("mouse: wider layout valid after draw", H.valid == true and H.pw == LY.PANEL_W)
  local px_tiers, min_px, distinct = Panel._test.fonts(), 99, {}
  for _, px in pairs(px_tiers) do
    if px < min_px then min_px = px end
    distinct[px] = true
  end
  local n_distinct = 0
  for _ in pairs(distinct) do n_distinct = n_distinct + 1 end
  check("style: panel defines at least four readable font tiers at 1280x720",
    screen_w == 1280 and screen_h == 720 and n_distinct >= 4 and min_px >= 12)
  check("style: body text tier stays comfortable at 1280x720",
    screen_w == 1280 and screen_h == 720
      and px_tiers.label >= 15 and px_tiers.desc >= 14 and px_tiers.title > px_tiers.label)
  local pixel_font_requested, all_numeric = false, true
  for _, req in ipairs(font_sizes) do
    if type(req) ~= "number" then all_numeric = false end
    if tostring(req):find("m6x11", 1, true) then pixel_font_requested = true end
  end
  check("style: panel asks LOVE for a vector face, never the pixel font",
    #font_sizes > 0 and all_numeric and not pixel_font_requested)
  local requested = {}
  for _, px in ipairs(font_sizes) do requested[px] = true end
  local tiers_used = true
  for _, px in pairs(px_tiers) do
    if not requested[px] then tiers_used = false end
  end
  check("style: every declared font tier is actually created", tiers_used)
  check("basics: curated view has 2 settings, 1 group and one advanced action",
    H.n == 4 and H.n == #Panel._test.rows())
  ;(function()
    local budget = H.ch - (LY.BASICS_INTRO_H + LY.BASICS_INTRO_GAP)
      - LY.PLACEMENT_H - LY.PLACEMENT_GAP
    local need = math.ceil(H.n / LY.MAX_COLS)
    check("basics: the position card leaves room for every settings row",
      math.floor(budget / LY.BASICS_ROW_H) >= need,
      "budget=" .. budget .. "px fits=" .. math.floor(budget / LY.BASICS_ROW_H)
        .. " need=" .. need .. " rows")
    local roomy = true
    for i = 1, H.n do
      if H.vis[i] and H.itemh[i] ~= LY.BASICS_ROW_H then roomy = false end
    end
    check("basics: settings rows keep the roomier page-1 pitch",
      roomy and select(1, Panel._test.grid()) <= LY.MAX_COLS,
      "itemh=" .. tostring(H.itemh[1]) .. " cols=" .. tostring(select(1, Panel._test.grid())))
  end)()
  local POSITION_CARD_KEYS = {
    NEURO_OVERLAY_ANCHOR = true,
    NEURO_OVERLAY_OFFSET_X = true,
    NEURO_OVERLAY_OFFSET_Y = true,
    NEURO_OVERLAY_SCALE_RIGHT = true,
    NEURO_OVERLAY_SCALE_LEFT = true,
    NEURO_SHOP_ANCHOR = true,
    NEURO_SHOP_OFFSET_X = true,
    NEURO_SHOP_OFFSET_Y = true,
  }
  ;(function()
  check("position card: occupies one bounded BASICS region",
    H.place_w > 0 and H.place_h > 0
      and H.place_x >= H.cx and H.place_x + H.place_w <= H.cx + H.cw
      and H.place_y >= H.cy and H.place_y + H.place_h <= H.cy + H.ch)
  local first_row_y = math.huge
  for i = 1, H.n do
    if H.vis[i] and H.rows[i] then first_row_y = math.min(first_row_y, H.rows[i]) end
  end
  check("position card: settings grid starts below the preview",
    H.place_y + H.place_h < first_row_y)
  local shipped_positions = {
    auto = true, ["top-left"] = true, ["middle-left"] = true, ["bottom-left"] = true,
    ["top-right"] = true, ["middle-right"] = true, ["bottom-right"] = true,
  }
  check("position card: all seven anchors have direct hit targets",
    #H.place_anchors == 7)
  local every_anchor_clicks, failed_anchor, seen_positions = true, nil, {}
  for i, r in ipairs(H.place_anchors) do
    local consumed = Panel.mousepressed(r.x + r.w / 2, r.y + r.h / 2, 1) == true
    local got = Tn.get("NEURO_OVERLAY_ANCHOR")
    seen_positions[r.value] = true
    if not consumed or got ~= r.value then
      every_anchor_clicks = false
      failed_anchor = string.format("%d expected=%s got=%s consumed=%s",
        i, tostring(r.value), tostring(got), tostring(consumed))
    end
  end
  for value in pairs(shipped_positions) do
    if not seen_positions[value] then every_anchor_clicks = false end
  end
  check("position card: clicking each anchor applies it live", every_anchor_clicks, failed_anchor)

  local sx, sy = H.place_slider_x[1], H.place_slider_y[1]
  local sw, sh = H.place_slider_w[1], H.place_slider_h[1]
  Panel.mousepressed(sx, sy + sh / 2, 1)
  check("position card: horizontal slider reaches -40%", Tn.get("NEURO_OVERLAY_OFFSET_X") == -40)
  Panel.mousemoved(sx + sw, sy + sh / 2)
  check("position card: dragging horizontal slider reaches +40%", Tn.get("NEURO_OVERLAY_OFFSET_X") == 40)
  check("position card: releasing ends the drag", Panel.mousereleased(sx + sw, sy, 1) == true)

  local vy, vh = H.place_slider_y[2], H.place_slider_h[2]
  Panel.mousepressed(H.place_slider_x[2] + H.place_slider_w[2] / 2, vy + vh / 2, 1)
  check("position card: vertical slider centre is 0%", Tn.get("NEURO_OVERLAY_OFFSET_Y") == 0)
  check("position card: reset is a direct click target", H.place_reset ~= nil)
  local msx, msw = H.place_slider_x[3], H.place_slider_w[3]
  local msy, msh = H.place_slider_y[3], H.place_slider_h[3]
  check("position card: both scale sliders are direct click targets",
    msw > 0 and H.place_slider_w[4] > 0 and msx and H.place_slider_x[4])
  Panel.mousepressed(msx, msy + msh / 2, 1)
  check("position card: main scale slider bottoms out at 0.50x",
    Tn.get("NEURO_OVERLAY_SCALE_RIGHT") == 0.5)
  Panel.mousemoved(msx + msw, msy + msh / 2)
  check("position card: dragging main scale slider tops out at 1.50x",
    Tn.get("NEURO_OVERLAY_SCALE_RIGHT") == 1.5)
  Panel.mousereleased(msx + msw, msy, 1)
  Panel.mousepressed(msx + msw / 2, msy + msh / 2, 1)
  check("position card: main scale slider centre is the 1.00x default",
    Tn.get("NEURO_OVERLAY_SCALE_RIGHT") == 1.0)
  Panel.mousereleased(msx + msw / 2, msy, 1)
  local ssx, ssw = H.place_slider_x[4], H.place_slider_w[4]
  local ssy, ssh = H.place_slider_y[4], H.place_slider_h[4]
  Panel.mousepressed(ssx + ssw / 2, ssy + ssh / 2, 1)
  check("position card: shop scale slider centre is the 1.00x default",
    Tn.get("NEURO_OVERLAY_SCALE_LEFT") == 1.0)
  Panel.mousereleased(ssx + ssw / 2, ssy, 1)
  local quantised, off_grid = true, nil
  for step = 0, 37 do
    local f = step / 37
    Panel.mousepressed(msx + f * msw, msy + msh / 2, 1)
    Panel.mousereleased(msx + f * msw, msy, 1)
    local v = Tn.get("NEURO_OVERLAY_SCALE_RIGHT")
    if math.abs(v * 20 - math.floor(v * 20 + 0.5)) > 1e-6 or v < 0.5 or v > 1.5 then
      quantised = false
      off_grid = off_grid or string.format("f=%.4f -> %.17g", f, v)
    end
  end
  check("position card: scale slider always snaps to the 0.05 grid", quantised, off_grid)
  check("position card: reveal selects the main scale slot",
    Panel._test.reveal("NEURO_OVERLAY_SCALE_RIGHT") and select(2, Panel._test.state()) == -5)
  Tn.set("NEURO_OVERLAY_SCALE_RIGHT", 1.0)
  Panel.keypressed("right")
  check("position card: keyboard steps the scale by exactly 0.05",
    Tn.get("NEURO_OVERLAY_SCALE_RIGHT") == 1.05, tostring(Tn.get("NEURO_OVERLAY_SCALE_RIGHT")))
  Panel.keypressed("left")
  Panel.keypressed("left")
  check("position card: keyboard steps the scale down past the default",
    Tn.get("NEURO_OVERLAY_SCALE_RIGHT") == 0.95, tostring(Tn.get("NEURO_OVERLAY_SCALE_RIGHT")))
  check("position card: reveal selects the shop scale slot",
    Panel._test.reveal("NEURO_OVERLAY_SCALE_LEFT") and select(2, Panel._test.state()) == -4)
  Panel._test.reveal("NEURO_OVERLAY_ANCHOR")
  Panel.keypressed("up")
  local walk = {}
  for i = 1, 8 do
    walk[i] = select(2, Panel._test.state())
    Panel.keypressed("down")
  end
  check("position card: keyboard walks every card slot in visual order",
    table.concat(walk, ",") == "-6,-3,-2,-1,-5,-4,-7,0", table.concat(walk, ","))
  check("position card: DOWN past the last card slot enters the settings grid",
    select(2, Panel._test.state()) == 1)
  Panel.keypressed("up")
  check("position card: UP from the first settings row returns to the last card slot",
    select(2, Panel._test.state()) == 0)
  check("position card: the centre toast scale is reachable from the keyboard",
    Panel._test.reveal("NEURO_CENTER_SCALE") and select(2, Panel._test.state()) == -7)
  Tn.set("NEURO_OVERLAY_ANCHOR", "bottom-right")
  Tn.set("NEURO_OVERLAY_OFFSET_X", 27)
  Tn.set("NEURO_OVERLAY_OFFSET_Y", -19)
  Tn.set("NEURO_OVERLAY_SCALE_RIGHT", 1.35)
  Tn.set("NEURO_OVERLAY_SCALE_LEFT", 0.6)
  Tn.set("NEURO_SHOP_ANCHOR", "middle-right")
  Tn.set("NEURO_SHOP_OFFSET_X", -22)
  Tn.set("NEURO_SHOP_OFFSET_Y", 13)
  Tn.set("NEURO_CENTER_SCALE", 1.25)
  Panel.mousepressed(H.place_reset.x + H.place_reset.w / 2, H.place_reset.y + H.place_reset.h / 2, 1)
  check("position card: reset restores every placement key of both panels",
    Tn.get("NEURO_OVERLAY_ANCHOR") == "auto"
      and Tn.get("NEURO_OVERLAY_OFFSET_X") == 0
      and Tn.get("NEURO_OVERLAY_OFFSET_Y") == 0
      and Tn.get("NEURO_OVERLAY_SCALE_RIGHT") == 1.0
      and Tn.get("NEURO_OVERLAY_SCALE_LEFT") == 1.0
      and Tn.get("NEURO_SHOP_ANCHOR") == "auto"
      and Tn.get("NEURO_SHOP_OFFSET_X") == 0
      and Tn.get("NEURO_SHOP_OFFSET_Y") == 0)
  check("position card: reveal selects anchor without a duplicate settings row",
    Panel._test.reveal("NEURO_OVERLAY_ANCHOR") and select(2, Panel._test.state()) == -3)
  Panel.keypressed("right")
  check("position card: keyboard cycles the selected anchor",
    Tn.get("NEURO_OVERLAY_ANCHOR") == "top-left")
  Tn.set("NEURO_OVERLAY_OFFSET_X", 12)
  Panel.keypressed("r")
  check("position card: R resets the selected slot only",
    Tn.get("NEURO_OVERLAY_ANCHOR") == "auto" and Tn.get("NEURO_OVERLAY_OFFSET_X") == 12)
  Panel._test.reveal("NEURO_OVERLAY_OFFSET_X")
  Panel.keypressed("r")
  check("position card: R on the offset slot resets that offset",
    Tn.get("NEURO_OVERLAY_OFFSET_X") == 0)
  Panel.draw()
  check("place target: the card opens targeting the MAIN panel",
    Panel._test.place_target() == "main")
  check("place target: both segments are direct click targets",
    #H.place_tabs == 2 and H.place_tabs[1].value == "main" and H.place_tabs[2].value == "shop")
  local seg = H.place_tabs[2]
  Panel.mousepressed(seg.x + 1, seg.y + 1, 1)
  check("place target: clicking SHOP retargets the position controls",
    Panel._test.place_target() == "shop" and select(2, Panel._test.state()) == -6)
  Panel.draw()
  local node = H.place_anchors[1]
  Panel.mousepressed(node.x + 1, node.y + 1, 1)
  check("place target: anchor clicks land on the shop key while SHOP is targeted",
    Tn.get("NEURO_SHOP_ANCHOR") == node.value
      and Tn.get("NEURO_OVERLAY_ANCHOR") == "auto")
  Panel.draw()
  local shx, shy = H.place_slider_x[1], H.place_slider_y[1]
  Panel.mousepressed(shx, shy + H.place_slider_h[1] / 2, 1)
  Panel.mousereleased(shx, shy, 1)
  check("place target: offset sliders drive the shop keys while SHOP is targeted",
    Tn.get("NEURO_SHOP_OFFSET_X") == -40 and Tn.get("NEURO_OVERLAY_OFFSET_X") == 0)
  check("place target: revealing a main key returns the target to MAIN",
    Panel._test.reveal("NEURO_OVERLAY_OFFSET_X") and Panel._test.place_target() == "main")
  check("place target: revealing a shop key selects its slot and targets SHOP",
    Panel._test.reveal("NEURO_SHOP_OFFSET_Y") and Panel._test.place_target() == "shop"
      and select(2, Panel._test.state()) == -1)
  Panel._test.reveal("NEURO_SHOP_ANCHOR")
  Panel.keypressed("up")
  Panel.keypressed("left")
  check("place target: LEFT on the switch selects MAIN", Panel._test.place_target() == "main")
  Panel.keypressed("right")
  check("place target: RIGHT on the switch selects SHOP", Panel._test.place_target() == "shop")
  Panel.keypressed("return")
  check("place target: ENTER toggles the switch back to MAIN",
    Panel._test.place_target() == "main")
  Tn.reset("NEURO_SHOP_ANCHOR")
  Tn.reset("NEURO_SHOP_OFFSET_X")
  Tn.reset("NEURO_SHOP_OFFSET_Y")
  Panel._test.reveal("NEURO_OVERLAY_ANCHOR")
  Panel.draw()
  local no_position_rows = true
  for _, row in ipairs(Panel._test.rows()) do
    if row.d and POSITION_CARD_KEYS[row.d.key] then no_position_rows = false end
  end
  check("position card: generic position and scale rows are removed", no_position_rows)
  end)()
  ;(function()
  local geo = Panel._test.preview_geometry
  local HUDo = require("render.hud_overlay")
  local g = geo("middle-left", 10, 0, 1.0, 1.0, 1280, 720)
  local ex, ey, eside = HUDo._test.panel_layout("middle-left", 10, 0, 1280, 720, 320, g.main_h, 0)
  check("preview: main rect comes from the production anchor math",
    g.main_x == ex and g.main_y == ey and g.side == eside and g.main_w == 320,
    string.format("%d/%d vs %d/%d side=%s", g.main_x, g.main_y, ex, ey, tostring(g.side)))
  check("preview: shop takes the opposite side and clears the main panel",
    g.shop_side == "right" and g.shop_x >= g.main_x + g.main_w + 8)
  local a = geo("auto", 0, 25, 1, 1, 1280, 720)
  check("preview: auto anchor gives the shop the main panel's y", a.shop_y == a.main_y)
  local off0 = geo("middle-left", 0, 0, 1, 1, 1920, 1080)
  local off0_shop = off0.shop_x
  local off40 = geo("middle-left", 40, 0, 1, 1, 1920, 1080)
  check("preview: horizontal offset never pulls the shop off its edge",
    off40.shop_x <= off0_shop)
  local big = geo("auto", 0, 0, 1.5, 0.5, 1920, 1080)
  check("preview: HUD scale keys drive the preview widths",
    big.main_w == 480 and big.shop_w == 190,
    "main=" .. big.main_w .. " shop=" .. big.shop_w)
  ;(function()
    local function snap(...)
      local r = geo(...)
      return { x = r.shop_x, y = r.shop_y, side = r.shop_side }
    end
    local base = snap("auto", 0, 0, 1, 1, 1920, 1080, "middle-right", 0, 0)
    local dy = snap("auto", 0, 0, 1, 1, 1920, 1080, "middle-right", 0, 30)
    local dx = snap("auto", 0, 0, 1, 1, 1920, 1080, "middle-right", 20, 0)
    check("preview: an explicit shop anchor answers to its own vertical offset",
      dy.y - base.y == math.floor(1080 * 30 / 100),
      string.format("%d -> %d", base.y, dy.y))
    check("preview: an explicit shop anchor answers to its own horizontal offset",
      base.x - dx.x == math.floor(1920 * 20 / 100),
      string.format("%d -> %d", base.x, dx.x))
    local m1 = snap("top-left", 0, 0, 1, 1, 1920, 1080, "middle-right", 0, 0)
    local m2 = snap("bottom-right", 40, 40, 1, 1, 1920, 1080, "middle-right", 0, 0)
    check("preview: an explicit shop anchor ignores the main panel entirely",
      m1.x == m2.x and m1.y == m2.y and m1.side == m2.side,
      string.format("%d,%d vs %d,%d", m1.x, m1.y, m2.x, m2.y))
    local auto1 = snap("top-left", 0, 0, 1, 1, 1920, 1080, "auto", 0, 0)
    local auto2 = snap("top-right", 0, 0, 1, 1, 1920, 1080, "auto", 0, 0)
    check("preview: an auto shop still tracks the main panel to the opposite side",
      auto1.side ~= auto2.side,
      tostring(auto1.side) .. " / " .. tostring(auto2.side))
  end)()
  check("preview: result table is reused, not reallocated",
    geo("auto", 0, 0, 1, 1, 1920, 1080) == geo("bottom-left", 0, 0, 1, 1, 1920, 1080))
  local bounded, worst = true, nil
  local sizes = { { 1280, 720 }, { 1920, 1080 }, { 2560, 1080 }, { 1024, 768 } }
  for _, anc in ipairs({ "auto", "top-left", "top-right", "middle-left",
    "middle-right", "bottom-left", "bottom-right" }) do
    for _, dx in ipairs({ -40, 0, 40 }) do
      for _, dy in ipairs({ -40, 0, 40 }) do
        for _, ms in ipairs({ 0.5, 1.0, 1.5 }) do
          for _, ss in ipairs({ 0.5, 1.0, 1.5 }) do
            for _, size in ipairs(sizes) do
              local w, h = size[1], size[2]
              local r = geo(anc, dx, dy, ms, ss, w, h)
              local rects = {
                { r.main_x, r.main_y, r.main_w, r.main_h },
                { r.shop_x, r.shop_y, r.shop_w, r.shop_h },
              }
              for _, q in ipairs(rects) do
                local ok = q[1] == q[1] and q[2] == q[2] and q[3] == q[3] and q[4] == q[4]
                  and q[1] >= 8 and q[2] >= 8
                  and q[1] + q[3] <= w - 8 and q[2] + q[4] <= h - 8
                if not ok and bounded then
                  bounded = false
                  worst = string.format("%s dx=%d dy=%d ms=%.1f ss=%.1f %dx%d -> %d,%d %dx%d",
                    anc, dx, dy, ms, ss, w, h, q[1], q[2], q[3], q[4])
                end
              end
            end
          end
        end
      end
    end
  end
  check("preview: every rect stays on screen at every anchor, offset and scale",
    bounded, worst)
  end)()
  local r3x, r3y = Panel._test.item_rect(3)
  check("mouse: row 3 resolves at its own cell", Panel._test.row_at(r3x + 4, r3y + 2) == 3)
  check("mouse: title area resolves no row", Panel._test.row_at(r3x + 4, H.py + 1) == nil)
  check("mouse: outside panel x resolves nil", Panel._test.row_at(H.px - 5, r3y + 2) == nil)
  Panel.mousepressed(r3x + 4, r3y + 2, 1)
  local _, sel_now = Panel._test.state()
  check("mouse: click selects row 3", sel_now == 3)
  local gameplay_groups = {
    MASTER = true,
  }
  local explained = 0
  for _, d in ipairs(Tn.entries()) do
    if gameplay_groups[d.group] then
      explained = explained + 1
      local desc = Panel._test.description(d.key)
      local example = Panel._test.description("EXAMPLE_" .. d.key)
      check("panel: real description for " .. d.key,
        type(desc) == "string" and #desc >= 40)
      check("panel: gameplay example for " .. d.key,
        type(example) == "string" and example:sub(1, 8) == "Example:")
    end
  end
  check("panel: all pacing settings covered", explained == 4)
  stable_ph = H.ph
  Panel.mousepressed(H.tab_x[2] + 2, H.tab_y + 2, 1)
  check("mouse: header tab switches to ADVANCED", (Panel._test.state()) == 2)
  Panel.draw()
  check("layout: changing tabs keeps panel height stable", H.ph == stable_ph)
  local advanced_open_rows = 0
  for _, row in ipairs(Panel._test.rows()) do
    if row.kind == "row" then advanced_open_rows = advanced_open_rows + 1 end
  end
  check("advanced: the first group starts unfolded", advanced_open_rows >= 2)

  local layout_count, display_count, dup_group = nil, nil, nil
  local seen_group = {}
  for _, row in ipairs(Panel._test.rows()) do
    if row.kind == "header" then
      if seen_group[row.group] then dup_group = dup_group or row.group end
      seen_group[row.group] = true
      if row.group == "LAYOUT" then layout_count = row.count end
      if row.group == "DISPLAY" then display_count = row.count end
    end
  end
  check("advanced: every placement key lives on the position card, no LAYOUT group remains",
    layout_count == nil, "LAYOUT group holds " .. tostring(layout_count) .. " rows")
  check("advanced: DEBUG OVERLAY lives under DISPLAY",
    display_count ~= nil and display_count >= 2,
    "DISPLAY group holds " .. tostring(display_count) .. " rows")
  check("advanced: no group is split into two headers",
    dup_group == nil, "duplicated group " .. tostring(dup_group))

  local orig_speed = Tn.get("NEURO_SPEED_MULT")
  Tn.set("NEURO_SPEED_MULT", 2.0)
  stable_ph = H.ph
  check("timing: reveal opens a specific setting",
    Panel._test.reveal("NEURO_SPEED_MULT") and (Panel._test.state()) == 3)
  Panel.draw()
  check("layout: revealing options keeps panel height stable", H.ph == stable_ph)
  local _, speed_row = Panel._test.state()
  local spx, spy = Panel._test.item_rect(speed_row)
  love.mouse.getPosition = function() return spx + 4, spy + 2 end
  check("wheel: consumed over panel", Panel.wheelmoved(0, 1) == true)
  check("wheel: adjust clamps at max", Tn.get("NEURO_SPEED_MULT") == 2.0)
  Panel.wheelmoved(0, -1)
  check("wheel: steps down from max", math.abs(Tn.get("NEURO_SPEED_MULT") - 1.95) < 1e-9)
  love.mouse.getPosition = function() return 0, 0 end
  check("wheel: not consumed outside panel", Panel.wheelmoved(0, 1) == false)
  Tn.set("NEURO_SPEED_MULT", orig_speed)

  Panel.mousepressed(H.tab_x[3] + 2, H.tab_y + 2, 1)
  check("mouse: header tab switches to TIMING", (Panel._test.state()) == 3)
  Panel.draw()
  do
    local function group_size(g)
      local n = 0
      for _, def in ipairs(Tn.entries()) do
        if def.group == g then n = n + 1 end
      end
      return n
    end
    local page = {}
    for _, t in ipairs({ 2, 3 }) do
      Panel.mousepressed(H.tab_x[t] + 2, H.tab_y + 2, 1)
      Panel.draw()
      local groups, settings, n = {}, 0, 0
      for _, row in ipairs(Panel._test.rows()) do
        if row.kind == "header" and not groups[row.group] then
          groups[row.group] = true
          n = n + 1
          settings = settings + group_size(row.group)
        end
      end
      page[t] = { groups = groups, n = n, settings = settings }
    end
    for _, t in ipairs({ 2, 3 }) do
      check(string.format("pages: tab %d is not degenerate (%d groups, %d settings)",
        t, page[t].n, page[t].settings), page[t].n >= 2 and page[t].settings >= 2)
    end
    local overlap = {}
    for g in pairs(page[2].groups) do
      if page[3].groups[g] then overlap[#overlap + 1] = g end
    end
    check("pages: no group appears on both ADVANCED and TIMING ("
      .. table.concat(overlap, ",") .. ")", #overlap == 0)
    local ratio = math.min(page[2].settings, page[3].settings)
      / math.max(page[2].settings, page[3].settings)
    check(string.format("pages: neither page is starved (%d vs %d, ratio %.2f)",
      page[2].settings, page[3].settings, ratio), ratio >= 0.25)
    check("pages: reveal jumps to whichever page owns the setting",
      Panel._test.reveal("NEURO_STATE_COOLDOWN")
        and ((Panel._test.state()) == 2 or (Panel._test.state()) == 3))
  end
  Panel.draw()

  Panel.mousepressed(H.tab_x[4] + 2, H.tab_y + 2, 1)
  check("mouse: header tab switches to COLOURS", (Panel._test.state()) == 4)
  Panel.draw()
  local ckeys = require("render.palette").color_keys(require("render.palette").persona())
  check("mouse: colour hitboxes rebuilt",
    H.n == #ckeys + 1 and H.hex_x[1] > H.row_x[1] and H.hexw > 0)
  local footer_top = H.py + H.ph - LY.FOOTER_H
  local desc_top = footer_top - LY.DESC_H
  local colour_bottom = 0
  for i = 1, H.n do
    if H.vis[i] then colour_bottom = math.max(colour_bottom, H.rows[i] + H.itemh[i]) end
  end
  check("layout: colour rows stay above the description band", colour_bottom <= desc_top)
  local swatch_right, swatch_bottom = 0, 0
  for i = 1, H.sw_n do
    local r = Panel._test.swatch_rect(i)
    swatch_right = math.max(swatch_right, r[1] + r[3])
    swatch_bottom = math.max(swatch_bottom, r[2] + r[4])
  end
  check("layout: colour swatches stay inside the panel",
    swatch_right <= H.px + H.pw - LY.PAD and swatch_bottom <= desc_top)
  check("layout: swatch strip never overlaps the reset button",
    swatch_right <= H.ra_x and H.ra_x + H.ra_w <= H.px + H.pw - LY.PAD)
  local hex1x, hex1y = H.hex_x[1], H.rows[1]
  Panel.mousepressed(hex1x + H.hexw + H.hgap + 1, hex1y + 2, 1)
  local _, _, em, ec = Panel._test.state()
  check("mouse: hex segment click enters edit on channel 2", em == true and ec == 2)
  Panel.mousepressed(H.row_x[1] + 4, hex1y + 2, 2)
  local _, _, em2 = Panel._test.state()
  check("mouse: right-click exits colour edit", em2 == false)

  local Pal = require("render.palette")
  Panel.keypressed("return")
  local _, sel_c = Panel._test.state()
  local swallowed = Panel.keypressed("0")
  Panel.keypressed("a"); Panel.keypressed("1"); Panel.keypressed("4"); Panel.keypressed("1"); Panel.keypressed("e")
  check("hex: typing is swallowed during colour edit", swallowed == true)
  check("hex: buffer holds the typed code", Panel._test.edit_hex() == "0a141e")
  local ckA = Pal.color_keys(Pal.persona())[sel_c]
  local colA = Pal.get_color(Pal.persona(), ckA)
  check("hex: typed code applies live to the row",
    math.abs(colA[1] - 0x0a / 255) < 1e-6 and math.abs(colA[2] - 0x14 / 255) < 1e-6
    and math.abs(colA[3] - 0x1e / 255) < 1e-6)
  Panel.keypressed("return")
  local _, _, emH = Panel._test.state()
  check("hex: enter exits edit and clears buffer", emH == false and Panel._test.edit_hex() == "")

  local sw = Panel._test.swatches
  local sr6 = Panel._test.swatch_rect(6)
  local sx6, sy6 = sr6[1] + 1, sr6[2] + 1
  check("swatch: 6th chip resolves at its rect", Panel._test.swatch_at(sx6, sy6) == 6)
  Panel.mousepressed(sx6, sy6, 1)
  local _, sel_s = Panel._test.state()
  local ckB = Pal.color_keys(Pal.persona())[sel_s]
  local colB = Pal.get_color(Pal.persona(), ckB)
  local hx6 = sw[6]
  check("swatch: click applies preset hex to selected row",
    math.abs(colB[1] - tonumber(hx6:sub(1, 2), 16) / 255) < 1e-6
    and math.abs(colB[2] - tonumber(hx6:sub(3, 4), 16) / 255) < 1e-6
    and math.abs(colB[3] - tonumber(hx6:sub(5, 6), 16) / 255) < 1e-6)

  local bd = Panel._test.bool_def
  check("checkbox: on/off enum detected", bd({ values = { "off", "on" } }) and bd({ values = { "on", "off" } }))
  check("checkbox: 3-state enum is a cycle chip, not a checkbox",
    not bd({ values = { "off", "compact", "expanded" } }))
  check("checkbox: numeric def is not a checkbox", not bd({ step = 1, min = 0, max = 1 }))
  check("checkbox: state helper", Panel._test.checkbox_on("on") and not Panel._test.checkbox_on("off"))
  local n0, c0 = #rect_calls, #circle_calls
  color_calls = {}
  local knob_on = Panel._test.draw_toggle(0, 0, 40, 20, true, 1)
  local rect_on, circ_on = #rect_calls - n0, #circle_calls - c0
  local on_colours = table.concat(color_calls, "|")
  n0, c0 = #rect_calls, #circle_calls
  color_calls = {}
  local knob_off = Panel._test.draw_toggle(0, 0, 40, 20, false, 1)
  local rect_off, circ_off = #rect_calls - n0, #circle_calls - c0
  local off_colours = table.concat(color_calls, "|")

  check("toggle: track is a capsule and the knob is a circle over a shadow",
    rect_on == 1 and circ_on == 4 and circ_off == 4)
  check("toggle: the empty track carries a recess lip the filled one does not",
    rect_off == rect_on + 1)
  check("toggle: the two states differ in colour, not just in shape",
    on_colours ~= off_colours)
  check("toggle: knob sits right when on and left when off", knob_on > knob_off)
  local sty_accent = table.concat(Panel._test.style.accent, ",")
  local sty_text = table.concat(Panel._test.style.text, ",")
  check("toggle: enabled state is the accent, disabled is neutral",
    on_colours:find(sty_accent, 1, true) ~= nil and off_colours:find(sty_accent, 1, true) == nil)
  check("toggle: the enabled knob is bright enough to read against the accent",
    on_colours:find(sty_text, 1, true) ~= nil)
  check("toggle: the pill is a proper touch-sized control",
    screen_w == 1280 and screen_h == 720
      and LY.TOGGLE_W >= 32 and LY.TOGGLE_H >= 18 and LY.TOGGLE_W > LY.TOGGLE_H)

  local mid_knob = Panel._test.draw_toggle(0, 0, 40, 20, true, 1, 0.5)
  local start_knob = Panel._test.draw_toggle(0, 0, 40, 20, true, 1, 0)
  check("toggle: a flip slides the knob instead of teleporting it",
    start_knob < mid_knob and mid_knob < knob_on)
  check("toggle: a settled toggle sits exactly at its end stop",
    Panel._test.draw_toggle(0, 0, 40, 20, true, 1, 1) == knob_on
    and Panel._test.draw_toggle(0, 0, 40, 20, false, 1, 1) == knob_off)
  check("toggle: the slide starts from the opposite end stop", start_knob == knob_off)
  color_calls = {}
  Panel._test.draw_toggle(0, 0, 40, 20, true, 1, 1, true)
  local hot_colours = table.concat(color_calls, "|")
  check("toggle: hovering the row lifts the control", hot_colours ~= on_colours)
  color_calls = {}
  Panel._test.draw_toggle(0, 0, 40, 20, false, 1, 1, true)
  check("toggle: hover reads on the disabled state too",
    table.concat(color_calls, "|") ~= off_colours)

  Panel.mousepressed(H.tab_x[5] + 2, H.tab_y + 2, 1)
  check("mouse: header tab switches to SYSTEM", (Panel._test.state()) == 5)
  Panel.draw()
  local rdefs = Tn.runtime_entries()
  check("system: hitbox rows == visible items", H.n == #Panel._test.rows())
  local glow_i
  for i, d in ipairs(rdefs) do if d.key == "NEURO_AI_CARD_GLOW" then glow_i = i end end
  local glow_before = Tn.get_raw("NEURO_AI_CARD_GLOW")
  local gx, gy = Panel._test.item_rect(glow_i + 1)
  love.mouse.getPosition = function() return gx + 4, gy + 2 end
  Panel.wheelmoved(0, 1)
  check("runtime: editable enum row toggles via wheel", Tn.get_raw("NEURO_AI_CARD_GLOW") ~= glow_before)
  Tn.set("NEURO_AI_CARD_GLOW", glow_before)
  love.mouse.getPosition = function() return -1, -1 end

  local function goto_tab(t)
    Panel.mousepressed(H.tab_x[t] + 2, H.tab_y + 2, 1)
    Panel.draw()
  end
  local function geom()
    return H.px .. "," .. H.py .. "," .. H.pw .. "," .. H.ph
  end
  local function all_items_placed()
    local _, _, _, capacity = Panel._test.grid()
    if H.n > capacity then return false end
    for i = 1, H.n do
      if not H.vis[i] then return false end
    end
    return true
  end
  local function all_items_inside()
    local cx, cy, cw, ch = Panel._test.content_rect()
    for i = 1, H.n do
      if H.vis[i] then
        local x, y, w, h = Panel._test.item_rect(i)
        if not (x >= cx and x + w <= cx + cw and y >= cy and y + h <= cy + ch) then return false end
      end
    end
    return true
  end

  goto_tab(1)
  local base_geom = geom()
  local tabs_same, tabs_fit, tabs_inside = true, true, true
  for t = 1, 5 do
    goto_tab(t)
    if geom() ~= base_geom then tabs_same = false end
    if not all_items_placed() then tabs_fit = false end
    if not all_items_inside() then tabs_inside = false end
  end
  check("layout: panel rectangle is identical on all five tabs", tabs_same, base_geom)
  check("layout: every tab fits without scrolling", tabs_fit)
  check("layout: no item is placed outside the content viewport", tabs_inside)

  local bands_ok = true
  do
    local cx, cy, cw, ch = Panel._test.content_rect()
    local ftop = H.py + H.ph - LY.FOOTER_H
    local dtop = ftop - LY.DESC_H
    bands_ok = cy >= H.py + LY.HEADER_H + LY.TABS_H
      and cy + ch <= dtop
      and dtop + LY.DESC_H <= ftop + LY.FOOTER_H
      and ftop + LY.FOOTER_H <= H.py + H.ph
      and cx >= H.px and cx + cw <= H.px + H.pw

    bands_ok = bands_ok
      and H.cl_y + H.cl_h <= H.py + LY.HEADER_H
      and H.pr_x + H.pr_w <= H.cl_x
      and H.tab_y >= H.py + LY.HEADER_H
      and H.tab_y + H.tab_h <= H.py + LY.HEADER_H + LY.TABS_H
      and H.tab_x[5] + H.tab_w[5] <= H.px + H.pw - LY.PAD
  end
  check("layout: header, tabs, content, description and footer never overlap", bands_ok)

  goto_tab(3)
  check("layout: clicks above the content viewport hit no row",
    Panel._test.row_at(H.row_x[1] + 4, H.tab_y + 2) == nil)
  check("layout: clicks below the content viewport hit no row",
    Panel._test.row_at(H.row_x[1] + 4, H.py + H.ph - LY.FOOTER_H - 4) == nil)

  local function header_index(group)
    for i, r in ipairs(Panel._test.rows()) do
      if r.kind == "header" and r.group == group then return i end
    end
  end
  local function open_groups()
    local n = 0
    for _, r in ipairs(Panel._test.rows()) do
      if r.kind == "header" and not r.collapsed then n = n + 1 end
    end
    return n
  end
  local accordion_ok, worst_fits, worst_geom = true, true, true
  for _, tab in ipairs({ 2, 3 }) do
    goto_tab(tab)
    local groups = {}
    for _, r in ipairs(Panel._test.rows()) do
      if r.kind == "header" then groups[#groups + 1] = r.group end
    end
    for _, g in ipairs(groups) do
      local hi = header_index(g)
      local hx, hy = Panel._test.item_rect(hi)
      Panel.mousepressed(hx + 4, hy + 2, 1)
      Panel.draw()
      if open_groups() ~= 1 then accordion_ok = false end
      if not (all_items_placed() and all_items_inside()) then worst_fits = false end
      if geom() ~= base_geom then worst_geom = false end
    end
    Panel.keypressed("c")
    Panel.draw()
    if open_groups() ~= 0 then accordion_ok = false end
  end
  check("accordion: exactly one group is open at a time on ADVANCED and TIMING", accordion_ok)
  check("layout: worst-case expanded group still fits every tab", worst_fits)
  check("layout: expanding a group does not resize the panel", worst_geom, base_geom)

  local before_expand
  do
    local _tp_clock = (love.timer.getTime and love.timer.getTime()) or 0
    local function settle()
      for _ = 1, 60 do
        _tp_clock = _tp_clock + 1 / 60
        love.timer.getTime = function() return _tp_clock end
        Panel.draw()
      end
      return geom()
    end
    local fold_tab, fold_group
    for _, t in ipairs({ 2, 3 }) do
      goto_tab(t)
      for _, r in ipairs(Panel._test.rows()) do
        if r.kind == "header" and r.collapsed and not fold_group then
          fold_tab, fold_group = t, r.group
        end
      end
      if fold_group then break end
    end
    check("layout: some group starts folded on ADVANCED or TIMING", fold_group ~= nil)
    goto_tab(fold_tab or 3)
    local settled = settle()
    local hx1, hy1 = Panel._test.item_rect(header_index(fold_group))
    Panel.mousepressed(hx1 + 4, hy1 + 2, 1)
    local after_unfold = settle()
    check("layout: settled panel geometry survives unfolding " .. tostring(fold_group),
      after_unfold == settled, after_unfold .. " want " .. settled)
    local first_row
    for i, r in ipairs(Panel._test.rows()) do
      if r.kind == "row" then first_row = i break end
    end
    local vx, vy = Panel._test.item_rect(first_row)
    Panel.mousepressed(vx + 4, vy + 2, 1)
    Panel.keypressed("right")
    local after_value = settle()
    check("layout: settled panel geometry survives changing a value",
      after_value == settled, after_value .. " want " .. settled)
    Panel.keypressed("r")
    settle()
  end

  goto_tab(4)
  local colour_geom = geom()
  local Pal2 = require("render.palette")
  local real_keys = Pal2.color_keys
  local doubled = {}
  for _, k in ipairs(real_keys(Pal2.persona())) do doubled[#doubled + 1] = k end
  for _, k in ipairs(real_keys(Pal2.persona())) do doubled[#doubled + 1] = k end
  Pal2.color_keys = function(p) return (p == Pal2.persona()) and doubled or real_keys(p) end
  Panel.keypressed("r")
  Panel.draw()
  local doubled_rows = #Panel._test.crows()
  local doubled_geom = geom()
  local doubled_inside = all_items_inside()
  Pal2.color_keys = real_keys
  Panel.keypressed("r")
  Panel.draw()
  check("colours: doubling the palette does not resize the panel",
    doubled_rows == #doubled and doubled_geom == colour_geom, doubled_geom)
  check("colours: doubled palette still paints inside the viewport", doubled_inside)

  local colour_bounds = true
  for i = 1, H.n - 1 do
    if H.vis[i] then
      local x, y, w = Panel._test.item_rect(i)
      local hx = H.hex_x[i]
      if not (x >= H.px + LY.PAD and x + w <= H.px + H.pw - LY.PAD) then colour_bounds = false end
      if not (hx and hx >= x and hx + H.hexw * 3 + H.hgap * 2 <= x + w) then colour_bounds = false end
      if y < H.py or y > H.py + H.ph then colour_bounds = false end
    end
  end
  check("colours: rows, hex fields and chips stay inside the panel", colour_bounds)
  check("colours: RESET ALL COLOURS stays reachable and inside the panel",
    H.ra_w > 0 and H.ra_x >= H.px + LY.PAD and H.ra_x + H.ra_w <= H.px + H.pw - LY.PAD
    and Panel._test.row_at(H.ra_x + 2, H.ra_y + 2) == H.n)

  check("scissor: the content viewport is clipped while drawing", #scissor_calls > 0)
  check("scissor: the previous scissor is restored after draw", scissor == nil)

  local function groups_share_column()
    local items = Panel._test.rows()
    local pageno = Panel._test.state()
    if pageno == 2 or pageno == 3 then
      local cx = select(1, Panel._test.content_rect())
      local rail_right = cx + LY.RAIL_W
      for i, r in ipairs(items) do
        if H.vis[i] then
          local x, _, w = Panel._test.item_rect(i)
          if r.kind == "row" then
            if x < rail_right then return false end
          else
            if x ~= cx or w ~= LY.RAIL_W then return false end
          end
        end
      end
      return true
    end
    local cols, _, _, cap = Panel._test.grid()
    local per = math.floor(cap / math.max(1, cols))
    local i = 1
    while i <= #items do
      local len = 1
      if items[i].kind == "header" then
        local j = i + 1
        while j <= #items and items[j].kind == "row" do len = len + 1; j = j + 1 end
        if len <= per and H.vis[i] then
          local hx = Panel._test.item_rect(i)
          for k = i + 1, i + len - 1 do
            if H.vis[k] and Panel._test.item_rect(k) ~= hx then return false end
          end
        end
      end
      i = i + len
    end
    return true
  end

  local groups_intact = true
  for _, tab in ipairs({ 1, 2, 3, 5 }) do
    goto_tab(tab)
    if not groups_share_column() then groups_intact = false end
    local snapshot = {}
    for _, r in ipairs(Panel._test.rows()) do
      if r.kind == "header" then snapshot[#snapshot + 1] = r.group end
    end
    for _, g in ipairs(snapshot) do
      local hi = header_index(g)
      if hi and H.vis[hi] then
        local hx, hy = Panel._test.item_rect(hi)
        Panel.mousepressed(hx + 4, hy + 2, 1)
        Panel.draw()
        if not groups_share_column() then groups_intact = false end
      end
    end
    Panel.keypressed("c")
    Panel.draw()
  end
  check("layout: a group header is never stranded away from its settings", groups_intact)

  local rail_ok, rail_never_empties = true, true
  for _, tab in ipairs({ 2, 3 }) do
    goto_tab(tab)
    local heads, panes = 0, 0
    for i, r in ipairs(Panel._test.rows()) do
      if H.vis[i] then
        if r.kind == "header" then heads = heads + 1 elseif r.kind == "row" then panes = panes + 1 end
      end
    end
    local total_groups = 0
    for _, r in ipairs(Panel._test.rows()) do
      if r.kind == "header" then total_groups = total_groups + 1 end
    end

    if heads ~= total_groups or heads < 1 then rail_ok = false end
    if not all_items_inside() then rail_ok = false end

    local open_g
    for _, r in ipairs(Panel._test.rows()) do
      if r.kind == "header" and not r.collapsed then open_g = r.group end
    end
    if not open_g then
      local hi = header_index(Panel._test.rows()[1].group)
      local hx, hy = Panel._test.item_rect(hi)
      Panel.mousepressed(hx + 4, hy + 2, 1)
      Panel.draw()
      for _, r in ipairs(Panel._test.rows()) do
        if r.kind == "header" and not r.collapsed then open_g = r.group end
      end
    end
    local hi = header_index(open_g)
    local hx, hy = Panel._test.item_rect(hi)
    Panel.mousepressed(hx + 4, hy + 2, 1)
    Panel.draw()
    local still = 0
    for i, r in ipairs(Panel._test.rows()) do
      if r.kind == "row" and H.vis[i] then still = still + 1 end
    end
    if still == 0 then rail_never_empties = false end
    local _ = panes
  end
  check("rail: every group is listed at once on ADVANCED and TIMING", rail_ok)
  check("rail: re-picking the open group does not empty the detail pane", rail_never_empties)

  local accent_key = table.concat(Panel._test.style.accent, ",")
  local text_in_accent = false
  for _, tab in ipairs({ 1, 2, 3, 4, 5 }) do
    goto_tab(tab)
    print_colors = {}
    Panel.draw()
    for _, c in ipairs(print_colors) do
      if c == accent_key then text_in_accent = true end
    end
  end
  check("style: no text is ever painted in the accent colour", not text_in_accent)
  check("style: text really was sampled during the sweep", #print_colors > 10)
  goto_tab(1)
  color_calls = {}
  Panel.draw()
  local accent_used = false
  for _, c in ipairs(color_calls) do
    if c == accent_key then accent_used = true end
  end
  check("style: the accent is still present as a state colour", accent_used)

  local function near(c, r, g, b)
    return math.abs(c[1] - r) < 0.04 and math.abs(c[2] - g) < 0.04 and math.abs(c[3] - b) < 0.04
  end
  local no_defaults = Panel._test.style.on == nil
  for _, col in pairs(Panel._test.style) do
    if near(col, 0.290, 0.871, 0.502) or near(col, 0.545, 0.486, 1.000) then no_defaults = false end
  end
  check("style: no stock framework green or violet left in the palette", no_defaults)

  local NL = Panel._test.nice_label
  check("labels: sentence case keeps initialisms", NL("AI CARD GLOW") == "AI card glow")
  check("labels: two-letter initialism survives", NL("CD SPEED PRESET") == "CD speed preset")
  check("labels: trailing initialism survives", NL("CONTEXT CACHE TTL") == "Context cache TTL")
  check("labels: hyphen keeps the tail lowercase", NL("AUTO-TUNE (STREAM)") == "Auto-tune (stream)")
  check("labels: hyphenated lead word", NL("RE-REGISTER THROTTLE") == "Re-register throttle")
  check("labels: colon prefix", NL("ENTRY: SMODS BOOSTER") == "Entry: SMODS booster")
  check("labels: parenthetical", NL("COOLDOWN SCALE (ALL)") == "Cooldown scale (all)")
  check("labels: version-ish enum values are not sentence cased",
    Panel._test.nice_value("0.5X") == "0.5x" and Panel._test.nice_value("AUTO") == "Auto")
  local labels_ok = true
  for _, d in ipairs(Tn.entries()) do
    local nl = NL(d.label)
    if type(nl) ~= "string" or #nl ~= #d.label then labels_ok = false end
  end
  for _, d in ipairs(Tn.runtime_entries()) do
    if #NL(d.label) ~= #d.label then labels_ok = false end
  end
  check("labels: every shipped label transforms without changing length", labels_ok)

  goto_tab(4)
  local keys_raw = true
  for _, cr in ipairs(Panel._test.crows()) do
    if cr.key ~= cr.key:upper() then keys_raw = false end
  end
  check("labels: colour keys stay raw config identifiers",
    keys_raw and NL("PANEL_BG") == "Panel_bg")

  goto_tab(1)
  local seg_contiguous, seg_inside = true, true
  for t = 1, 4 do
    if H.tab_x[t] + H.tab_w[t] ~= H.tab_x[t + 1] then seg_contiguous = false end
  end
  if H.tab_x[1] < H.px + LY.PAD then seg_inside = false end
  if H.tab_x[5] + H.tab_w[5] > H.px + H.pw - LY.PAD then seg_inside = false end
  if H.tab_y < H.py + LY.HEADER_H then seg_inside = false end
  if H.tab_y + H.tab_h > H.py + LY.HEADER_H + LY.TABS_H then seg_inside = false end
  check("tabs: segments form one contiguous track", seg_contiguous)
  check("tabs: the track sits inside the panel and inside its own band", seg_inside)
  check("tabs: every segment is a real click target", (function()
    for t = 1, 5 do
      if not (H.tab_w[t] and H.tab_w[t] >= u_ref(60) and H.tab_h >= u_ref(24)) then return false end
    end
    return true
  end)())

  local WR = Panel._test.wrap_lines
  check("desc: the band is tall enough for a wrapped description plus meta",
    LY.DESC_H >= px_tiers.desc * 2 + px_tiers.micro + u_ref(30))
  check("desc: description text uses the body size, not the caption size",
    px_tiers.desc >= px_tiers.label and px_tiers.desc > px_tiers.micro)
  local long = "Blocks shop exit until every owned joker has an explicit keep-or-sell role."
  local wrapped = WR(long, stub_font, 200, 2)
  check("desc: a long description wraps instead of being cut at one line", #wrapped == 2)
  check("desc: wrapping keeps whole words", wrapped[1]:sub(-1) ~= " " and not wrapped[1]:find("%s%s"))
  check("desc: overflow past the line budget ends in an ellipsis",
    WR(long, stub_font, 90, 2)[2]:sub(-3) == "...")
  check("desc: a short description needs no wrapping",
    #WR("Short one.", stub_font, 400, 2) == 1)
  local desc_top_now = H.py + H.ph - LY.FOOTER_H - LY.DESC_H
  check("desc: the band still clears the content viewport",
    select(2, Panel._test.content_rect()) + select(4, Panel._test.content_rect()) <= desc_top_now)

  polygon_calls, line_calls = {}, {}
  for t = 1, 5 do goto_tab(t) end
  check("marks: nothing is drawn as a filled polygon any more", #polygon_calls == 0)
  check("marks: strokes really are used, so the check is not vacuous", #line_calls > 0)

  rounded_rects = 0
  for t = 1, 5 do goto_tab(t) end
  check("shape: no corner radius is drawn anywhere in the panel",
    rounded_rects == 0 and LY.RADIUS == 0 and LY.ROW_R == 0)
  check("shape: the switch is still a capsule built from circles", (function()
    local circle_before = #circle_calls
    Panel._test.draw_toggle(0, 0, 40, 20, true, 1)
    return #circle_calls - circle_before == 4
  end)())

  check("sections: headings get their own tier above the caption size",
    px_tiers.section and px_tiers.section >= u_ref(13) and px_tiers.section > px_tiers.micro
    and px_tiers.section < px_tiers.label)

  local optical_ok = true
  for _, h in ipairs({ 20, 27, 30, 46 }) do
    if Panel._test.text_mid(stub_font, 0, h) ~= math.floor((h - stub_font:getHeight()) / 2 + 0.5) - 1 then
      optical_ok = false
    end
  end
  check("type: vertical centring carries the one-pixel optical correction", optical_ok)

  local style_clean = true
  for _, col in pairs(Panel._test.style) do
    for _, pal in pairs(Pal2.PALETTES) do
      for _, v in pairs(pal) do
        if v == col then style_clean = false end
      end
    end
  end
  check("style: panel palette shares no table with any persona palette", style_clean)

  local res_ok = true
  for _, res in ipairs({ { 1280, 720 }, { 1680, 1050 } }) do
    screen_w, screen_h = res[1], res[2]
    for t = 1, 5 do
      goto_tab(t)
      if H.px ~= math.floor((screen_w - H.pw) / 2) then res_ok = false end

      if math.abs(H.py - math.floor((screen_h - H.ph) / 2)) > LY.OPEN_SLIDE then res_ok = false end
      if H.px < 0 or H.py < 0 or H.px + H.pw > screen_w or H.py + H.ph > screen_h then res_ok = false end
      if not (all_items_placed() and all_items_inside()) then res_ok = false end
    end
  end
  screen_w, screen_h = 1280, 720
  goto_tab(5)
  check("layout: centred and contained at 1280x720 and 1680x1050", res_ok)

  ;(function()
    screen_w, screen_h = 1280, 720
    goto_tab(1)
    check("scale: the reference resolution is exactly 1.0 and does not move",
      Panel._test.scale() == 1.0 and H.pw == 940 and H.ph == 560
        and H.ch == 302 and H.itemh[1] == 30,
      string.format("scale=%s panel=%dx%d ch=%d rowh=%s",
        tostring(Panel._test.scale()), H.pw, H.ph, H.ch, tostring(H.itemh[1])))

    local sizes = {
      { 800, 480 }, { 1024, 768 }, { 1280, 600 }, { 1280, 720 }, { 1366, 768 },
      { 1600, 900 }, { 1920, 1080 }, { 2560, 1440 }, { 3440, 1440 }, { 3840, 2160 },
    }
    local placed_ok, placed_worst = true, nil
    local fits_ok, fits_worst = true, nil
    local grid_ok, grid_worst = true, nil
    local quant_ok = true
    local tiers_ok, tiers_worst = true, nil
    for _, sz in ipairs(sizes) do
      screen_w, screen_h = sz[1], sz[2]
      goto_tab(1)
      local sc = Panel._test.scale()
      if math.abs(sc * 20 - math.floor(sc * 20 + 0.5)) > 1e-9 then quant_ok = false end
      local px = Panel._test.fonts()
      if not (px.title >= px.label and px.label >= px.desc and px.desc >= px.section
        and px.section >= px.micro and px.micro >= 8) then
        tiers_ok = false
        tiers_worst = tiers_worst or string.format("%dx%d %d/%d/%d/%d/%d",
          sz[1], sz[2], px.title, px.label, px.desc, px.section, px.micro)
      end
      local budget = H.ch - (LY.BASICS_INTRO_H + LY.BASICS_INTRO_GAP)
        - LY.PLACEMENT_H - LY.PLACEMENT_GAP
      if math.floor(budget / LY.BASICS_ROW_H) < math.ceil(H.n / LY.MAX_COLS) then
        grid_ok = false
        grid_worst = grid_worst or string.format("%dx%d budget=%d", sz[1], sz[2], budget)
      end
      for t = 1, 5 do
        goto_tab(t)
        if not (all_items_placed() and all_items_inside()) then
          placed_ok = false
          placed_worst = placed_worst or string.format("%dx%d tab %d", sz[1], sz[2], t)
        end
        if H.px < 0 or H.py < 0
          or H.px + H.pw > screen_w or H.py + H.ph > screen_h then
          fits_ok = false
          fits_worst = fits_worst or string.format("%dx%d tab %d -> %d,%d %dx%d",
            sz[1], sz[2], t, H.px, H.py, H.pw, H.ph)
        end
      end
    end
    screen_w, screen_h = 1280, 720
    goto_tab(1)
    check("scale: no item is hidden on any page at any resolution", placed_ok, placed_worst)
    check("scale: the panel always fits inside the window", fits_ok, fits_worst)
    check("scale: page-1 grid capacity is invariant across resolutions", grid_ok, grid_worst)
    check("scale: every scale lands on the 0.05 grid", quant_ok)
    check("scale: font tiers keep their order and stay legible at every scale",
      tiers_ok, tiers_worst)

    local mono_ok, mono_worst, prev = true, nil, nil
    for _, mul in ipairs({ 0.6, 0.8, 1.0, 1.25, 1.5, 2.0, 3.0 }) do
      screen_w, screen_h = math.floor(1280 * mul), math.floor(720 * mul)
      goto_tab(1)
      local sc = Panel._test.scale()
      if prev and sc < prev then
        mono_ok = false
        mono_worst = mono_worst or string.format("%dx%d gave %.2f after %.2f",
          screen_w, screen_h, sc, prev)
      end
      prev = sc
    end
    screen_w, screen_h = 1280, 720
    goto_tab(1)
    check("scale: growing the window never shrinks the scale", mono_ok, mono_worst)

    screen_w, screen_h = 1920, 1080
    goto_tab(1)
    local auto_scale, auto_pw = Panel._test.scale(), H.pw
    local user_ok, user_worst = true, nil
    for _, mult in ipairs({ 1.0, 0.9, 0.75, 0.5 }) do
      Tn.set("NEURO_PANEL_SCALE", mult)
      for t = 1, 5 do
        goto_tab(t)
        if not (all_items_placed() and all_items_inside()) then
          user_ok = false
          user_worst = user_worst or string.format("%.2fx tab %d", mult, t)
        end
        if H.px < 0 or H.py < 0
          or H.px + H.pw > screen_w or H.py + H.ph > screen_h then
          user_ok = false
          user_worst = user_worst or string.format("%.2fx tab %d overflows", mult, t)
        end
      end
    end
    Tn.set("NEURO_PANEL_SCALE", 0.5)
    goto_tab(1)
    local small_pw = H.pw
    Tn.reset("NEURO_PANEL_SCALE")
    goto_tab(1)
    check("scale: the panel size setting shrinks the panel", small_pw < auto_pw,
      string.format("%d vs %d", small_pw, auto_pw))
    check("scale: nothing is hidden or clipped at any panel size setting",
      user_ok, user_worst)
    check("scale: resetting the panel size setting restores the automatic scale",
      Panel._test.scale() == auto_scale and H.pw == auto_pw)
    screen_w, screen_h = 1280, 720
    goto_tab(1)
  end)()

  ;(function()
    local real_height = stub_font.getHeight
    screen_w, screen_h = 1280, 720
    goto_tab(1)
    local base_offset = H.rows[1] - H.cy
    local font_ok, font_worst = true, nil
    local static_ok = true
    for _, gh in ipairs({ 10, 14, 21, 22, 30, 40 }) do
      stub_font.getHeight = function() return gh end
      goto_tab(1)
      if not all_items_placed() then
        font_ok = false
        font_worst = font_worst or ("line height " .. gh)
      end
      if H.rows[1] - H.cy ~= base_offset then static_ok = false end
    end
    stub_font.getHeight = real_height
    goto_tab(1)
    check("basics: no settings row is hidden at any description line height",
      font_ok, font_worst)
    check("basics: the grid starts at the same offset for every font metric",
      static_ok, "offset drifted from " .. base_offset)

    local short_ok, short_worst = true, nil
    for _, h in ipairs({ 720, 700, 680, 660, 640 }) do
      screen_h = h
      goto_tab(1)
      if not all_items_placed() then
        short_ok = false
        short_worst = short_worst or (screen_w .. "x" .. h)
      end
    end
    screen_w, screen_h = 1280, 720
    goto_tab(1)
    check("basics: no settings row is hidden down to a 640px tall window",
      short_ok, short_worst)
  end)()

  screen_w, screen_h = 1280, 720
  goto_tab(5)

  check("mouse: [X] closes panel", (function()
    Panel.mousepressed(H.cl_x + 2, H.cl_y + 2, 1)
    return Panel.is_open() == false and H.valid == false
  end)())
  check("mouse: clicks pass through after close", Panel.mousepressed(H.px + 10, H.py + 10, 1) == false)

  Tn.save = real_save
  Shud.panel_font, Shud.panel_font_small = pf, pfs
  love.graphics = prev_graphics
  love.mouse = prev_mouse
  G.NEURO.llm_paused = nil
  package.loaded["hud.tuning_panel"] = real_panel
end

do
  local U = require("util.utils")
  check("fmt_num: exact integer below 1e15", U.fmt_num(123456789) == "123456789")
  check("fmt_num: no scientific just under 1e15", U.fmt_num(999999999999999) == "999999999999999")
  check("fmt_num: 1e19 does not wrap to a negative INT64", U.fmt_num(1e19):sub(1, 1) ~= "-")
  check("fmt_num: 1e19 is compact scientific", U.fmt_num(1.23456e19) == "1.235e+19")
  check("fmt_num: huge negative keeps its sign", U.fmt_num(-9.9e20):sub(1, 1) == "-")
  check("fmt_num: zero and negative-zero both '0'", U.fmt_num(0) == "0" and U.fmt_num(-0.0) == "0")
  check("fmt_num: nil/nan coerce to '0'", U.fmt_num(nil) == "0" and U.fmt_num(0 / 0) == "0")
  local ok, res = pcall(string.format, "%d", 1e19)
  check("fmt_num: raw %d WOULD wrap or error (proves the bug exists)", not ok or res:sub(1, 1) == "-")
end

do
  local SV = require("util.schema_validate")
  local arr = { type = "array", items = { type = "integer", minimum = 1 }, minItems = 1, maxItems = 5, uniqueItems = true }
  check("valid indices pass", SV.validate_value(arr, { 1, 2, 3 }, "indices") == true)
  check("minItems rejects empty", SV.validate_value(arr, {}, "indices") == false)
  check("maxItems rejects >5", SV.validate_value(arr, { 1, 2, 3, 4, 5, 6 }, "indices") == false)
  check("uniqueItems rejects dupes", SV.validate_value(arr, { 1, 1, 2 }, "indices") == false)
end

do
  local V = require("facts.card_area_util").validate_hand_indices
  local a = V({ 1, 2, 3 }, 8, 5); check("clean indices accepted", type(a) == "table" and #a == 3)
  check("out-of-range rejected (no silent drop of 99)", (V({ 1, 99 }, 8, 5)) == nil)
  check("duplicate rejected", (V({ 1, 1 }, 8, 5)) == nil)
  check("over-cap rejected", (V({ 1, 2, 3, 4, 5, 6 }, 8, 5)) == nil)
  check("empty rejected", (V({}, 8, 5)) == nil)
end

do
  local by = {}; for _, dd in ipairs(A.get_static_actions()) do by[dd.name] = dd end
  local ph = by.play_hand and by.play_hand.schema and by.play_hand.schema.properties
    and by.play_hand.schema.properties.indices
  check("play_hand schema has minItems/maxItems/uniqueItems",
    ph and ph.minItems == 1 and ph.maxItems == 5 and ph.uniqueItems == true)
end

do
  G.NEURO.persona = "neuro"
  check("choose_persona invalid once persona locked", A.is_action_valid("choose_persona") == false)
  G.NEURO.persona = "hiyori"
  check("choose_persona valid at the identity gate", A.is_action_valid("choose_persona") == true)
  G.NEURO.persona = nil
end

do
  local Bridge = require("core.bridge")
  local sent = {}
  local fake = setmetatable({ send = function(_, msg) sent[#sent + 1] = msg.command end }, { __index = Bridge })
  fake:register_actions({ { name = "foo", description = "first", schema = { type = "object" } } })
  check("first register sends actions/register", has(sent, "actions/register"))
  sent = {}; fake:register_actions({ { name = "foo", description = "first", schema = { type = "object" } } })
  check("identical contract does not resend", #sent == 0)
  sent = {}; fake:register_actions({ { name = "foo", description = "SECOND", schema = { type = "object" } } })
  check("changed description unregisters the stale action", has(sent, "actions/unregister"))
  check("changed description re-registers", has(sent, "actions/register"))
end

do
  local HandFacts = require("facts.hand_facts")
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = {
    card("King", "Hearts"), card("King", "Spades"),
    card("4", "Clubs"), card("4", "Diamonds"), card("4", "Hearts"),
    card("9", "Spades"), card("2", "Clubs"),
  }, highlighted = {} }
  G.GAME.current_round.hands_left = 4; G.GAME.current_round.discards_left = 4
  local all = G.hand.cards
  G.FUNCS = G.FUNCS or {}
  G.FUNCS.get_poker_hand_info = function(_) return "Full House", nil, { ["Full House"] = { all } } end
  local s = HandFacts.summary()
  G.FUNCS.get_poker_hand_info = nil
  local function count_idx(label)
    local m = s:match(label .. "%[([%d,]+)%]")
    if not m then return nil end
    local n = 1; for _ in m:gmatch(",") do n = n + 1 end; return n
  end
  check("Full House index is exactly 5 (not the over-inclusive engine group)", count_idx("Full House") == 5, s)
  check("Two Pair is listed and its index is exactly 4", count_idx("Two Pair") == 4, s)
end

do
  local CtxHelpers = require("context.ctx_helpers")
  check("the truncating entry point is gone", CtxHelpers.compact_text == nil)

  local long = "8 of Hearts (x1.5 Mult while in hand, Blue(holo edition), stacks with other mults)"
  local out = CtxHelpers.normalize_text(long)
  check("normalize_text keeps every semantic unit of a long value",
    out == "8 of Hearts (x1.5 Mult while in hand; Blue(holo edition); stacks with other mults)", out)
  check("normalize_text never ellipsizes", out:find("...", 1, true) == nil, out)

  local huge = string.rep("rule clause; ", 400)
  check("a 5200-char value survives at full length",
    #CtxHelpers.normalize_text(huge) >= #huge - 1, #CtxHelpers.normalize_text(huge))

  local messy = "  a,b|c\r\nd   e  "
  check("newline/pipe/comma/whitespace normalisation still applies",
    CtxHelpers.normalize_text(messy) == "a;b/c d e", CtxHelpers.normalize_text(messy))
  check("a table value is still flattened",
    CtxHelpers.normalize_text({ "one", "two" }) == "one two", CtxHelpers.normalize_text({ "one", "two" }))

  local led = { sources = {} }
  for i = 1, 9 do
    led.sources[i] = { name = "Source" .. i, kind = "mult", total = { n = i }, why = "reason " .. i }
  end
  local rows = CtxHelpers.ledger_gated_sources(led)
  check("every gated ledger source is rendered", #rows == 9, #rows)
  check("ledger_gated_sources returns the row list and nothing else, on both its paths",
    select("#", CtxHelpers.ledger_gated_sources(led)) == 1
      and select("#", CtxHelpers.ledger_gated_sources(nil)) == 1,
    select("#", CtxHelpers.ledger_gated_sources(led)) .. "/"
      .. select("#", CtxHelpers.ledger_gated_sources(nil)))
  check("the last source is present with its reason",
    rows[9] == "Source9 +9 Mult -- reason 9", rows[9])

  local CALLERS = { "handlers/hand_handlers.lua", "context/ctx_helpers.lua" }
  local scanned = 0
  for _, path in ipairs(CALLERS) do
    local f = io.open(path, "r")
    local src = f and f:read("*a") or nil
    if f then f:close() end
    if not src or src == "" then
      check("" .. path .. " is readable (the argument scan would be vacuous)", false, path)
    else
      for args in src:gmatch("ledger_gated_sources%s*(%b())") do
        scanned = scanned + 1
        check("ledger_gated_sources is called with one argument in " .. path,
          not args:find(",", 1, true), args)
      end
    end
  end
  check("the argument scan found call sites to check", scanned > 0, scanned)
end

do
  local FSH = require("force.force_selecting_hand")
  local RID = require("tests.helpers").RID
  local VALN = require("tests.helpers").VALN
  local saved_G = _G.G
  local function leaf_card(v, suit)
    local id = RID[v]
    return { base = { value = VALN[v] or v, suit = suit },
      config = { center = { key = "c_base", set = "Default" } },
      get_id = function() return id end, is_suit = function(_, s) return s == suit end }
  end
  local function round_with_boss(key, name)
    _G.G = {
      STATES = { BLIND_SELECT = 1, SELECTING_HAND = 2 }, STATE = 2,
      hand = { cards = { leaf_card("3", "Spades"), leaf_card("7", "Clubs"), leaf_card("9", "Hearts") },
        config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {} },
      GAME = { chips = 0, round_resets = { ante = 1 },
        current_round = { hands_left = 4, discards_left = 3 },
        blind = { chips = 1000, boss = true, name = name, debuff = {},
          config = { blind = { key = key } } },
        hands = {} },
      FUNCS = { get_poker_hand_info = function() return nil, nil, {} end },
      NEURO = { once_serials = {}, state_enter_serial = 1 },
      jokers = { cards = { { ability = { set = "Joker", name = "Joker" }, sell_cost = 2,
        config = { center = { key = "j_joker", set = "Joker" } } } }, config = { card_limit = 5 } },
      consumeables = { cards = {}, config = { card_limit = 2 } },
    }
  end
  local function offers_sell()
    local f = FSH.build()
    for _, a in ipairs((f or {}).actions or {}) do if a == "sell_card" then return true end end
    return false
  end
  round_with_boss("bl_pillar", "The Pillar")
  check("mid-round sell stays unoffered under a boss that is not Verdant Leaf",
    not A.is_action_valid("sell_card") and not offers_sell())
  round_with_boss("bl_final_leaf", "Verdant Leaf")
  check("SELECTING_HAND force offers sell_card under Verdant Leaf (the only way to lift its all-debuff)",
    A.is_action_valid("sell_card") and offers_sell())

  local Legality = require("facts.boss.legality")
  local gate_ok, gate_worst = true, nil
  local expect = {
    ["The Pillar|1"] = false, ["The Pillar|2"] = true,
    ["Verdant Leaf|1"] = false, ["Verdant Leaf|2"] = false,
  }
  for _, boss in ipairs({ { "bl_pillar", "The Pillar" }, { "bl_final_leaf", "Verdant Leaf" } }) do
    for _, state in ipairs({ 1, 2 }) do
      round_with_boss(boss[1], boss[2])
      _G.G.STATE = state
      local blocked = Legality.sell_blocked_now()
      local want = expect[boss[2] .. "|" .. state]
      if blocked ~= want then
        gate_ok = false
        gate_worst = gate_worst or string.format("%s state=%d blocked=%s want=%s",
          boss[2], state, tostring(blocked), tostring(want))
      end
    end
  end
  check("the shared mid-round sell gate blocks only SELECTING_HAND outside Verdant Leaf",
    gate_ok, gate_worst)

  local listed_in = {}
  for _, sname in ipairs({ "SHOP", "SELECTING_HAND", "BLIND_SELECT", "MENU", "ROUND_EVAL" }) do
    for _, a in ipairs(A.get_action_names_for_state(sname) or {}) do
      if a == "toggle_shop" then listed_in[#listed_in + 1] = sname end
    end
  end
  local function source_of(path)
    local fh = io.open(path, "r")
    local body = fh and fh:read("*a") or ""
    if fh then fh:close() end
    check("source scan: " .. path .. " is readable and non-empty", #body > 0, "#body=" .. #body)
    return body
  end

  local Legends = require("facts.token_legends")
  local play_desc = ""
  for _, d in ipairs(A.get_action_definitions and A.get_action_definitions() or {}) do
    if d.name == "play_hand" then play_desc = tostring(d.description or "") end
  end
  if play_desc == "" then
    play_desc = source_of("core/actions.lua"):match('action_def%("play_hand", "(.-)", %{') or ""
  end
  check("the play_hand contract states the two-send commit protocol",
    play_desc:find("two sends", 1, true) ~= nil
      and play_desc:find("confirm_play", 1, true) ~= nil
      and play_desc:find("is FINAL", 1, true) == nil,
    play_desc:sub(1, 120))
  check("the play_hand contract documents the single-send corner",
    play_desc:find("last hand", 1, true) ~= nil, play_desc:sub(1, 120))

  local gloss = tostring((Legends.readable_state and Legends.readable_state("SELECTING_HAND"))
    or (Legends.READABLE and Legends.READABLE.SELECTING_HAND) or "")
  if gloss == "" then
    local fh = io.open("facts/token_legends.lua", "r")
    if fh then gloss = fh:read("*a") fh:close() end
  end
  check("the glossary teaches the commit protocol before the first play",
    gloss:find("two sends", 1, true) ~= nil, "glossary missing the protocol")

  local hh_body = source_of("handlers/hand_handlers.lua")
  check("the Cerulean Bell rejection does not claim the engine cannot execute the play",
    hh_body:find("the engine cannot execute it", 1, true) == nil
      and hh_body:find("keeps it highlighted", 1, true) ~= nil)
  check("the confirm message does not promise a free commit for other selections",
    hh_body:find("without another weak/general confirmation", 1, true) == nil)

  local en_body = source_of("core/enforce.lua")
  check("the mid-round sell block carries the honest base-game deviation note",
    en_body:find("base Balatro allows it", 1, true) ~= nil)

  local dp_body = source_of("core/dispatcher.lua")
  check("a confirmation is not recorded as a failed action",
    dp_body:find('reason_code ~= "CONFIRMATION_REQUIRED"', 1, true) ~= nil)

  local ds_body = source_of("render/debug_stats.lua")
  check("the perf log records the speed the cooldown gate keys off",
    ds_body:find('"gamespeed":', 1, true) ~= nil
      and ds_body:find('"speedfactor":', 1, true) ~= nil
      and ds_body:find("G.SETTINGS.GAMESPEED", 1, true) ~= nil
      and ds_body:find("G.SPEEDFACTOR", 1, true) ~= nil)

  check("toggle_shop is listed for the shop state and no other",
    #listed_in == 1 and listed_in[1] == "SHOP",
    "listed in: " .. table.concat(listed_in, ","))
  _G.G = saved_G
end

do
  local function source_of(path)
    local fh = io.open(path, "r")
    local body = fh and fh:read("*a") or ""
    if fh then fh:close() end
    check("source scan: " .. path .. " is readable and non-empty", #body > 0, "#body=" .. #body)
    return body
  end
  local prims_body = source_of("hud/prims.lua")
  check("persona: prims.lua no longer snapshots NEURO_PERSONA at module load",
    prims_body:find("Prims.NEURO_PERSONA", 1, true) == nil)

  local overlay_body = source_of("render/hud_overlay.lua")
  check("persona: hud_overlay no longer holds a frozen persona upvalue",
    overlay_body:find("Prims.NEURO_PERSONA", 1, true) == nil)
  check("persona: hud_overlay reads no persona field directly",
    overlay_body:find("G.NEURO.persona", 1, true) == nil)
  check("persona: hud_overlay's persona fallback delegates to the live-read helper",
    overlay_body:find("Palette%.[%w_]*persona%(%)") ~= nil)

  local Prims = require("hud.prims")
  check("persona: prims module exports no stale NEURO_PERSONA field", Prims.NEURO_PERSONA == nil)

  local Palette = require("render.palette")
  local Tn2 = require("core.config")
  local saved_persona, saved_G_persona = Tn2.get_raw("NEURO_PERSONA"), G.NEURO.persona
  G.NEURO.persona = nil
  Tn2.set("NEURO_PERSONA", "neuro")
  check("persona: live read reflects a session change made after module load",
    Palette.persona() == "neuro")
  Tn2.set("NEURO_PERSONA", "evil")
  check("persona: live read reflects a second session change with no reload",
    Palette.persona() == "evil")
  G.NEURO.persona = "hiyori"
  check("persona: an active in-round persona still wins over the session default",
    Palette.persona() == "hiyori")
  Tn2.set("NEURO_PERSONA", saved_persona or "hiyori")
  G.NEURO.persona = saved_G_persona
end

do
  local PlanHandlers = require("handlers.plan_handlers")
  local res, res_err = PlanHandlers.prepare_plan({}, false)
  local msg = ActionResult.is_error(res_err) and ActionResult.normalize(res_err).message or tostring(res_err)
  check("a plan call without fields is rejected", res == nil and ActionResult.is_error(res_err))
  check("the missing-plan-fields error lists boss_plan consistently with prepare_plan",
    msg:find("boss_plan", 1, true) ~= nil, msg)
end

do
  local SeedHandlers = require("handlers.seed_run_handlers")

  local exec_ok, err_ok = SeedHandlers.handle_paste_seed({ seed = "ABC123XY" })
  check("a valid eight-character seed is accepted",
    type(exec_ok) == "function", tostring(err_ok))

  local seed_pasted_before = G.NEURO and G.NEURO.seed_pasted
  local exec_long, err_long = SeedHandlers.handle_paste_seed({ seed = "ABCDEFGHIJKL" })
  check("a seed longer than eight characters is rejected rather than truncated",
    exec_long == nil and type(err_long) == "string" and err_long:find("too long", 1, true) ~= nil,
    tostring(exec_long) .. " / " .. tostring(err_long))
  check("a rejected long seed does not silently change G.NEURO.seed_pasted",
    G.NEURO.seed_pasted == seed_pasted_before, tostring(G.NEURO.seed_pasted))
end

do
  local SeedHandlers = require("handlers.seed_run_handlers")
  local saved_clipboard = G.CLIPBOARD

  G.CLIPBOARD = "Seed: ABC12345 have fun"
  local run1, err1 = SeedHandlers.handle_paste_seed({})
  check("clipboard prose around a seed is rejected rather than normalized",
    run1 == nil and type(err1) == "string", tostring(run1) .. " / " .. tostring(err1))
  check("rejection does not produce the obsolete 'SEEDABC1' result",
    G.setup_seed ~= "SEEDABC1")

  G.CLIPBOARD = "my seed is 8LB3RD9X"
  local run2, err2 = SeedHandlers.handle_paste_seed({})
  check("'my seed is X' clipboard prose is rejected rather than normalized to MYSEEDIS",
    run2 == nil and type(err2) == "string", tostring(run2) .. " / " .. tostring(err2))
  check("rejection does not produce the obsolete 'MYSEEDIS' result",
    G.setup_seed ~= "MYSEEDIS")

  G.setup_seed = nil
  G.CLIPBOARD = "ABC12345"
  local run3 = SeedHandlers.handle_paste_seed({})
  check("a bare clipboard seed remains valid", type(run3) == "function")
  if type(run3) == "function" then run3() end
  check("a bare clipboard seed is preserved exactly", G.setup_seed == "ABC12345",
    tostring(G.setup_seed))

  G.setup_seed = nil
  G.CLIPBOARD = "  ABC12345\n"
  local run4 = SeedHandlers.handle_paste_seed({})
  check("a bare clipboard seed with surrounding whitespace remains valid", type(run4) == "function")
  if type(run4) == "function" then run4() end
  check("surrounding whitespace does not change a bare clipboard seed", G.setup_seed == "ABC12345",
    tostring(G.setup_seed))

  G.CLIPBOARD = saved_clipboard
end

do
  local FactHints = require("facts.fact_hints")
  local Once = require("util.once")
  local saved_neuro = G.NEURO
  G.NEURO = { session_once_serials = {}, once_serials = {}, state_enter_serial = 1, decision_serial = 1 }
  FactHints.reset_pending()

  local TAG = "n3f6_hint"
  local KEY = "shint:" .. TAG

  local buffered_receipt
  G.NEURO.send_context = function(_self, _msg, _silent, receipt)
    buffered_receipt = receipt
    return true, true
  end
  local queued_text = FactHints.once_per_session_hint(TAG, "HINT TEXT")
  check("the first call queues a hint", queued_text == "")
  check("the hint is pending in the queue", FactHints.pending_count() == 1,
    tostring(FactHints.pending_count()))

  local sent1 = FactHints.flush_pending()
  check("flushing a frame into the backlog reports acceptance rather than commit",
    sent1 == 1, tostring(sent1))
  check("the gate is not recorded when the frame only reached the backlog",
    Once.peek(KEY, "session") == true)

  buffered_receipt.status = "rejected"
  local requeued = FactHints.once_per_session_hint(TAG, "HINT TEXT")
  check("the hint is offered again after an undelivered flush", requeued == "")
  check("the reoffered hint returns to the queue", FactHints.pending_count() == 1,
    tostring(FactHints.pending_count()))

  G.NEURO.send_context = function(_self, _msg, _silent, receipt)
    receipt.status = "written"
    return true
  end
  local sent2 = FactHints.flush_pending()
  check("a delivered flush reports one sent frame", sent2 == 1, tostring(sent2))
  check("the gate is recorded only after actual delivery",
    Once.peek(KEY, "session") == false)

  G.NEURO = saved_neuro
  FactHints.reset_pending()
end

do
  local FactHints = require("facts.fact_hints")
  local Once = require("util.once")
  local saved_neuro = G.NEURO
  G.NEURO = { session_once_serials = {}, once_serials = {}, state_enter_serial = 1, decision_serial = 1 }
  FactHints.reset_pending()

  FactHints.once_per_session_hint("n3f7_shint", "SESSION HINT TEXT")
  check("hint_is_pending sees a queued session hint",
    FactHints.hint_is_pending("n3f7_shint") == true)

  FactHints.drop_hint("n3f7_shint")
  check("drop_hint removes a session hint from hint_is_pending",
    FactHints.hint_is_pending("n3f7_shint") == false)
  check("dropping a session hint empties the queue",
    FactHints.pending_count() == 0, tostring(FactHints.pending_count()))

  check("drop_hint does not record the session gate",
    Once.peek("shint:n3f7_shint", "session") == true)
  local requeued = FactHints.once_per_session_hint("n3f7_shint", "SESSION HINT TEXT")
  check("a session hint can be queued again after drop_hint",
    requeued == "" and FactHints.pending_count() == 1, tostring(FactHints.pending_count()))

  G.NEURO = saved_neuro
  FactHints.reset_pending()
end

do
  local BridgeInit = require("core.bridge_init")
  local saved_love = _G.love
  local quit_called, fallback_called = false, false
  _G.love = { quit = function() quit_called = true end }
  G.NEURO = { unregister_actions = function(_self, _names) fallback_called = true end }
  BridgeInit.hook_love_quit()
  love.quit()
  check("love.quit contains no obsolete unregister-actions catalog fallback",
    fallback_called == false)
  check("the original love.quit is still called", quit_called == true)
  _G.love = saved_love
end

done()
