local Utils = require("util.utils")
local DeckNames = require("facts.deck_names")
local get_back_display_name = DeckNames.get_back_display_name
local describe_deck = require("facts.deck_facts").describe_deck

local FRAME_HEAD =
  "RULES.\n\n## Scoring\nScore = Chips x Mult. A flat bonus adds to its own side of that product (+Chips to the chips, +Mult to the mult); an xMult -- a joker whose text shows 'X..Mult', an edition, or an enhancement -- multiplies the mult accumulated when that operation resolves, which is why multipliers scale a score far faster than flat bonuses. "
  .. "Two xMults do not add -- they multiply the running mult in their resolution order, so a second one is worth far more than the first was. "
  .. "A joker that feeds another joker, or that triggers on a hand type, compounds when you play into it. "
  .. "A discard swaps the selected cards for new draws and costs no hand (discards are a separate pool from hands). "
  .. "A Planet card permanently raises one hand type's starting chips and mult. Playing a hand raises its play count; its level changes only when an explicit card, boss, or other effect changes it."

local FRAME_TAIL =
  "## Round loop\nEach played hand costs one hand whatever it scores; reach the target before hands hit 0. "
  .. "Blind targets rise every ante. "
  .. "Each ante has a Small, Big, and Boss blind. You must BEAT the Boss to advance the ante; Small and Big can each be beaten OR skipped (skipping takes that blind's tag instead of its cash and the shop that would have followed). Beating the final ante's Boss wins the run (the blind line shows which ante). "
  .. "Pick a blind, beat its target before hands run out, cash out, then shop before the next blind."

local FRAME_ECONOMY =
  "## Economy\nWhile interest is enabled, held cash keeps earning it and funds rerolls, so avoid spending below your reserve unless the buy clearly advances the run more than the interest it would cost. "
  .. "Selling returns only the sell value shown (about half the price). A bought joker is placed in the rightmost joker slot, with no joker to its right. "
  .. "A recorded hand result may differ next time with other cards, Jokers, boss rules, and random effects."

local function score_order_sentence()
  local CardUtil = require("facts.card_util")
  local n = require("util.utils").fmt_num
  local glass = n(CardUtil.center_config_num("m_glass", "Xmult"))
  local poly = n(CardUtil.center_config_num("e_polychrome", "extra"))
  local steel = n(CardUtil.center_config_num("m_steel", "h_x_mult"))
  return "## Order of operations\nChips and mult build up together as one running pair, and an xMult multiplies the mult accumulated up to the moment it fires -- it is not a separate stage applied to the finished total. "
    .. "The engine scores your played cards first, one card at a time from left to right (that card's chips -- 2-10 are worth their number, J/Q/K 10, A 11 -- then its enhancement and edition -- Glass x" .. glass
    .. " Mult, Polychrome x" .. poly .. " Mult -- and any joker that triggers on that individual card), then the cards you still hold (Steel x" .. steel
    .. " Mult per copy held), and only after all of that your jokers. "
    .. "So a joker paying per scoring card has already multiplied before any joker's flat +Mult is added to the mult. "
end

local function invariant_frame()
  local order = score_order_sentence()
    .. "Reference: within that last joker pass your jokers fire left to right, so the slot of a joker whose xMult applies to the whole hand, relative to your flat +Mult jokers, changes the result -- a joker that pays per scoring card has already fired by then and its slot does not. "
    .. "Most jokers only pay when the played hand meets their condition. "
    .. "Normally only the cards forming the hand score -- extras are dumped like a discard. Card and Joker exceptions explicitly shown in the current decision override that normal rule. "
    .. "A joker paying per scoring card pays once per card that scores, not once per matching card you own."
  return table.concat({ FRAME_HEAD, order, FRAME_TAIL, FRAME_ECONOMY }, "\n\n")
end

local function run_is_committed()
  return not not (G and G.STAGES and G.STAGE and G.STAGE == G.STAGES.RUN)
end

local function deck_reference()
  if not run_is_committed() then return nil end
  local center = DeckNames.current_deck_center()
  if not center then return nil end
  local name = get_back_display_name(center) or "Unknown"
  local ok, desc = pcall(describe_deck, center)
  if not ok or type(desc) ~= "string" or desc == "" then return nil end
  local text = string.format("Deck rules -- %s: %s", name, desc)
  return "deck:" .. tostring(center.key or name), text
end

local function active_challenge()
  local game = G and G.GAME
  local id = game and game.challenge
  if not id then return nil end
  if type(game.challenge_tab) == "table" and game.challenge_tab.id == id then return game.challenge_tab end
  for _, ch in ipairs((G and G.CHALLENGES) or {}) do
    if type(ch) == "table" and ch.id == id then return ch end
  end
  return nil
end

local function challenge_line(prefix, rule)
  local v_text = G and G.localization and G.localization.misc and G.localization.misc.v_text
  local raw = type(v_text) == "table" and v_text[prefix .. tostring(rule.id)] or nil
  if type(raw) == "table" then raw = table.concat(raw, " ") end
  if type(raw) ~= "string" then return nil end
  return Utils.clean_plain((raw:gsub("#1#", function() return tostring(rule.value) end)))
end

local function challenge_lines(prefix, rules)
  local out = {}
  for _, rule in ipairs(rules or {}) do
    if type(rule) == "table" and not rule.no_ui then
      out[#out + 1] = challenge_line(prefix, rule)
        or (tostring(rule.id):gsub("_", " ") .. (rule.value ~= nil and (" " .. tostring(rule.value)) or ""))
    end
  end
  return out
end

local function banned_names(list, name_of)
  local out = {}
  for _, entry in ipairs(type(list) == "table" and list or {}) do
    if type(entry) == "table" and entry.id then out[#out + 1] = name_of(entry) end
  end
  return out
end

local function challenge_reference()
  if not run_is_committed() then return nil end
  local ch = active_challenge()
  if not ch then return nil end
  local DisplayNames = require("facts.display_names")
  local rules, restrictions = ch.rules or {}, ch.restrictions or {}
  local custom = challenge_lines("ch_c_", rules.custom)
  local parts = { string.format("Challenge rules -- %s: this run is a challenge with its own rules.",
    DisplayNames.challenge(ch) or tostring(ch.id)) }
  parts[#parts + 1] = "Custom rules: " .. (#custom > 0 and table.concat(custom, "; ") or "none") .. "."
  local modifiers = challenge_lines("ch_m_", rules.modifiers)
  if #modifiers > 0 then parts[#parts + 1] = "Changed starting values: " .. table.concat(modifiers, "; ") .. "." end
  local bans = {
    { "cards", banned_names(restrictions.banned_cards, function(e) return DisplayNames.center(e.id) end) },
    { "tags", banned_names(restrictions.banned_tags, function(e) return DisplayNames.tag(e.id) end) },
    { "other", banned_names(restrictions.banned_other, function(e)
      return e.type == "blind" and DisplayNames.blind(e.id) or DisplayNames.humanize_key(e.id) end) },
  }
  for _, ban in ipairs(bans) do
    if #ban[2] > 0 then parts[#parts + 1] = "Banned " .. ban[1] .. ": " .. table.concat(ban[2], ", ") .. "." end
  end
  return "challenge:" .. tostring(ch.id), table.concat(parts, " ")
end

local function challenge_state_line()
  local ch = active_challenge()
  if not ch then return "" end
  local custom = challenge_lines("ch_c_", ch.rules and ch.rules.custom)
  return string.format("Challenge: %s%s\n", require("facts.display_names").challenge(ch) or tostring(ch.id),
    #custom > 0 and (" -- " .. table.concat(custom, "; ") .. ".") or ".")
end

local function build_game_rules_text(state_name)
  if state_name == "MENU" or state_name == "RUN_SETUP" or state_name == "GAME_OVER"
      or state_name == "SPLASH" then return nil end
  local CtxEconomy = require("facts.economy_facts")
  local modifiers = (G and G.GAME and G.GAME.modifiers) or {}
  local no_interest = CtxEconomy.no_interest()
  local per_hand = modifiers.no_extra_hand_money and 0 or (tonumber(modifiers.money_per_hand) or 1)
  local per_discard = tonumber(modifiers.money_per_discard) or 0
  local round_end = string.format(
    "At round end each unused hand pays %s%s.\n",
    Utils.money(per_hand),
    per_discard > 0 and (" and each unused discard pays " .. Utils.money(per_discard))
      or " (unused discards pay nothing)")
  local credit_line = ""
  local cc = CtxEconomy.credit_card_count()
  if cc and cc > 0 and CtxEconomy.spend_floor() < 0 then
    credit_line = "\nYou own a Credit Card joker: you may spend into debt down to "
      .. Utils.money(CtxEconomy.spend_floor())
      .. " (negative money after a purchase is allowed debt, not an error)."
  end
  local economy_line = round_end .. (no_interest
    and "Economy: no interest this run -- held cash earns nothing at end of round."
    or string.format(
      "Economy: %s interest per $5 held at end of round, max %s/round (only the first %s held count).",
      Utils.money_change(CtxEconomy.interest_amount()), Utils.money_change(CtxEconomy.max_interest()),
      Utils.money(CtxEconomy.interest_cap())))
    .. credit_line

  local deck_info = ""
  local center = DeckNames.current_deck_center()
  if center then
    deck_info = string.format("Your deck: %s. ", get_back_display_name(center) or "Unknown")
    local n, what = require("facts.deck_facts").start_filter_count(center)
    if n then
      deck_info = deck_info .. string.format("It now holds %d %s%s. ", n, what, n == 1 and "" or "s")
    end
    deck_info = deck_info .. "\n"
  end

  local exceptions = {}
  if require("facts.card_util").owns_live_joker("j_splash") then exceptions[#exceptions + 1] = "Splash scores every played card" end
  if require("facts.card_util").deck_has_stone() then exceptions[#exceptions + 1] = "Stone cards always score" end
  local exception_line = #exceptions > 0
    and ("\nCurrent scoring exceptions: " .. table.concat(exceptions, "; ") .. ".") or ""

  return challenge_state_line() .. deck_info .. economy_line .. exception_line
end

return {
  invariant_frame = invariant_frame,
  deck_reference = deck_reference,
  challenge_reference = challenge_reference,
  run_frame_text = build_game_rules_text,
}
