local DeckNames = require("facts.deck_names")
local get_back_display_name = DeckNames.get_back_display_name
local describe_deck = require("facts.deck_facts").describe_deck

local FRAME_HEAD =
  "RULES. Score = Chips x Mult. A flat bonus adds to its own side of that product (+Chips to the chips, +Mult to the mult); an xMult -- a joker whose text shows 'X..Mult', an edition, or an enhancement -- multiplies the mult present when that operation resolves, which is why multipliers scale a score far faster than flat bonuses and why an xMult is worth nothing while there is no mult to multiply. "
  .. "Two xMults do not add -- they multiply the running mult in their resolution order, so a second one is worth far more than the first was. "
  .. "A joker that feeds another joker, or that triggers on a hand type, compounds when you play into it. "
  .. "A discard swaps the selected cards for new draws and costs no hand (discards are a separate pool from hands). "
  .. "A Planet card permanently raises one hand type's starting chips and mult. Playing a hand raises its play count; its level changes only when an explicit card, boss, or other effect changes it. "

local FRAME_TAIL =
  "Each played hand costs one hand whatever it scores; reach the target before hands hit 0. "
  .. "Blind targets rise every ante. "
  .. "Each ante has a Small, Big, and Boss blind. You must BEAT the Boss to advance the ante; Small and Big can each be beaten OR skipped (skipping takes that blind's tag instead of its cash and the shop that would have followed). Beating the final ante's Boss wins the run (the blind line shows which ante). "
  .. "Round loop: pick a blind, beat its target before hands run out, cash out, then shop before the next blind."

local FRAME_ECONOMY =
  " While interest is enabled, held cash keeps earning it and funds rerolls, so avoid spending below your reserve unless the buy clearly advances the run more than the interest it would cost. "
  .. "Selling returns only the sell value shown (about half the price). A bought joker is placed in the rightmost joker slot, with no joker to its right. "
  .. "A recorded hand result may differ next time with other cards, Jokers, boss rules, and random effects."

local function score_order_sentence()
  local CardUtil = require("facts.card_util")
  local n = require("util.utils").fmt_num
  local glass = n(CardUtil.center_config_num("m_glass", "Xmult"))
  local poly = n(CardUtil.center_config_num("e_polychrome", "extra"))
  local steel = n(CardUtil.center_config_num("m_steel", "h_x_mult"))
  return "Order of operations: chips and mult build up together as one running pair, and an xMult multiplies the mult accumulated up to the moment it fires -- it is not a separate stage applied to the finished total. "
    -- The chips a rank is worth were stated nowhere: SMODS.Rank nominals (smods/src/game_object.lua
    -- :2189-2250) feed Card:get_chip_bonus (card.lua:1201). K=13/A=14 is the natural wrong guess.
    .. "The engine scores your played cards first, one card at a time from left to right (that card's chips -- 2-10 are worth their number, J/Q/K 10, A 11 -- then its enhancement and edition -- Glass x" .. glass
    .. " Mult, Polychrome x" .. poly .. " Mult -- and any joker that triggers on that individual card), then the cards you still hold (Steel x" .. steel
    .. " Mult per copy held), and only after all of that your jokers. "
    .. "So a joker paying per scoring card has already multiplied before any joker's flat +Mult is added to the mult. "
end

local function owns_joker(key)
  if not (G and G.jokers and G.jokers.cards) then return false end
  local PublicCard = require("facts.public_card_identity")
  local want = "center:" .. tostring(key)
  for i, j in ipairs(G.jokers.cards) do
    if not j.debuff and PublicCard.multiset_key(j, "jokers", i) == want then return true end
  end
  return false
end

local function build_invariant_frame()
  local parts = { FRAME_HEAD, score_order_sentence() }
  parts[#parts + 1] = "Reference: within that last joker pass your jokers fire left to right, so the slot of a joker whose xMult applies to the whole hand, relative to your flat +Mult jokers, changes the result -- a joker that pays per scoring card has already fired by then and its slot does not. "
  parts[#parts + 1] = "Most jokers only pay when the played hand meets their condition. "
  parts[#parts + 1] = "Normally only the cards forming the hand score -- extras are dumped like a discard. Card and Joker exceptions explicitly shown in the current decision override that normal rule. "
  parts[#parts + 1] = "A joker paying per scoring card pays once per card that scores, not once per matching card you own. "
  parts[#parts + 1] = FRAME_TAIL
  parts[#parts + 1] = FRAME_ECONOMY
  return table.concat(parts)
end

-- Outside a run G.GAME.selected_back is a menu preview: every deck the model looks at rewrites it
-- (handlers/menu_handlers.lua) and Game:main_menu resets it to Red (dump game.lua:1554-1566), so
-- without this gate a browse of the deck list stacked one unretractable deck frame per deck seen.
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

local function build_game_rules_text(state_name)
  if state_name == "MENU" or state_name == "RUN_SETUP" or state_name == "GAME_OVER"
      or state_name == "SPLASH" then return nil end
  local CtxEconomy = require("facts.economy_facts")
  local modifiers = (G and G.GAME and G.GAME.modifiers) or {}
  local no_interest = CtxEconomy.no_interest()
  local per_hand = modifiers.no_extra_hand_money and 0 or (tonumber(modifiers.money_per_hand) or 1)
  local per_discard = tonumber(modifiers.money_per_discard) or 0
  local round_end = string.format(
    "At round end each unused hand pays $%d%s. ",
    per_hand,
    per_discard > 0 and string.format(" and each unused discard pays $%d", per_discard)
      or " (unused discards pay nothing)")
  local credit_line = ""
  local cc = CtxEconomy.credit_card_count()
  if cc and cc > 0 then
    credit_line = " You own a Credit Card joker: you may spend into debt down to "
      .. require("util.utils").money_signed(CtxEconomy.spend_floor())
      .. " (negative money after a purchase is allowed debt, not an error)."
  end
  local economy_line = round_end .. string.format(
    "Economy: +$%d interest per $5 held at end of round, max +$%d/round (only the first $%d held count)%s.",
    CtxEconomy.interest_amount(),
    CtxEconomy.max_interest(),
    CtxEconomy.interest_cap(),
    no_interest and " (disabled this run)" or "")
    .. credit_line

  local deck_info = ""
  local center = DeckNames.current_deck_center()
  if center then
    deck_info = string.format("Your deck: %s. ", get_back_display_name(center) or "Unknown")
  end

  local exceptions = {}
  if owns_joker("j_splash") then exceptions[#exceptions + 1] = "Splash scores every played card" end
  if require("facts.card_util").deck_has_stone() then exceptions[#exceptions + 1] = "Stone cards always score" end
  local exception_line = #exceptions > 0
    and ("Current scoring exceptions: " .. table.concat(exceptions, "; ") .. ". ") or ""

  return deck_info .. economy_line .. " " .. exception_line
end

local function invariant_frame() return build_invariant_frame() end

return {
  invariant_frame = invariant_frame,
  deck_reference = deck_reference,
  run_frame_text = build_game_rules_text,
}
