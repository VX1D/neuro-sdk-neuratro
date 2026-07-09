local DeckNames = require("facts.deck_names")
local get_back_display_name = DeckNames.get_back_display_name
local get_deck_short_desc = require("facts.deck_facts").short_desc

local INVARIANT_FRAME =
  "RULES: Score = Chips x Mult; xMult multiplies the whole running score and multiple xMult sources stack. "
  .. "Jokers apply left-to-right, so where an xMult joker sits changes the result. "
  .. "Most jokers pay their bonus only when the played hand meets their condition, so the same cards score very differently by which hand you form. "
  .. "Because xMult sources stack, a run scales by assembling jokers that combine into a synergy "
  .. "(one joker feeding another, or a joker rewarding a hand type you keep playing) rather than by "
  .. "collecting unrelated flat bonuses; hunting for jokers that build on the ones you already own is "
  .. "one of the most important plans of a run. "
  .. "Blind targets rise every ante: a score that clears one blind will not clear later ones. "
  .. "Leveling a hand type with Planet cards permanently raises that hand type's base chips and mult for the rest of the run. "
  .. "Only the cards forming the played hand score; extra played cards add nothing but leave your hand like a discard "
  .. "(exceptions: the Splash joker makes every played card score; Stone cards always score). "
  .. "Discarding swaps selected cards for fresh draws without spending a hand; hands and discards are separate limited pools, and each played hand spends one hand regardless of its score. "
  .. "The blind target must be reached before hands reach 0. Boss debuffs can invalidate card groups or hand shapes. "
  .. "A run advances through the antes, each with a Small, Big, and Boss blind (only the Boss has a debuff): clear all three to advance. Beating the final ante's Boss wins the run; the blind line shows which ante that is. "
  .. "The loop each round is pick a blind, play hands to beat its target before hands run out, then cash out and use the shop before the next blind."

local function build_game_rules_text()
  local CtxEconomy = require("context.ctx_economy")
  local modifiers = (G and G.GAME and G.GAME.modifiers) or {}
  local no_interest = CtxEconomy.no_interest()
  local per_hand = tonumber(modifiers.money_per_hand) or 1
  local per_discard = tonumber(modifiers.money_per_discard) or 0
  local round_end = string.format(
    "At round end each unused hand pays $%d%s. ",
    per_hand,
    per_discard > 0 and string.format(" and each unused discard pays $%d", per_discard)
      or " (unused discards pay nothing)")
  local economy_line = round_end .. string.format(
    "Economy: +$%d interest per $5 held at end of round, max +$%d/round (only the first $%d held count)%s.",
    CtxEconomy.interest_amount(),
    CtxEconomy.max_interest(),
    CtxEconomy.interest_cap(),
    no_interest and " (disabled this run)" or "")
    .. " If you own a Credit Card joker you may spend down to -$20 per copy; negative money after a purchase is allowed debt, not an error."

  local deck_info = ""
  local center = DeckNames.current_deck_center()
  if center then
    local deck_name = get_back_display_name(center) or "Unknown"
    local ok, desc = pcall(get_deck_short_desc, center)
    if not ok then desc = nil end
    if desc then
      deck_info = string.format("Your deck: %s (%s). ", deck_name, desc)
    else
      deck_info = string.format("Your deck: %s. ", deck_name)
    end
  end

  -- only per-run-varying bits here; invariant facts belong on the stable FRAME| line
  return deck_info .. economy_line .. " "
end

local function invariant_frame() return INVARIANT_FRAME end

return {
  invariant_frame = invariant_frame,
  run_frame_text = build_game_rules_text,
}
