local function has_jokers() return not not (G and G.jokers and G.jokers.cards and #G.jokers.cards > 0) end

local READABLE_SELECTING_HAND =
  "Card rank chips: 2-10 = the printed number, J/Q/K = 10, A = 11 (before any enhancement/edition bonus). "
  .. "Playing a hand takes two sends: the first play_hand answers with the engine verdict for that selection and spends nothing, and an identical re-send of the same indices commits it. Different indices start a fresh confirmation for that selection. On your last hand with no discards left and at most one ready hand the first send commits immediately. "
  .. "After playing or discarding, the game draws according to the current blind and deck effects; normally it refills toward hand size. "
  .. "Structure/Ready/Close show shape only -- real value also depends on card enhancements/editions/seals, hand level, your jokers and debuffs. The (lvN Nc xN) figures are that hand type's CURRENT values. Under The Flint they are shown already halved -- do not halve them again. Under The Arm they include every drop taken so far, and The Arm subtracts one more level from the hand you play at the moment you play it -- but only if that hand is above level 1, so a level-1 row scores exactly as shown. Plasma deck is the exception: it balances chips and mult at scoring, so the shown split is pre-balance. "

local READABLE_COMMON =
  "How to decide: read the situation and your available actions, drop any blocked by money, slots, hands, discards, or targets, then call exactly ONE action type. Confirming a play or a sell means sending that same action again with identical arguments -- that is the commit, not a second move. "
  .. "Positions and indices are 1-based -- the number before each card or row (card 1 is the first card in your hand). "
  .. "Actions are written NAME|{arguments} as JSON. A value already written out is literal -- send it exactly as shown. A value in <angle brackets> is yours to replace: <int 1+> is a whole number 1 or more, <\"a\"|\"b\"> means exactly one of those quoted values, and [<pick 1 to 5 different hand positions>] is an array of 1 to 5 positions -- that range is HOW MANY entries to send, not which positions exist. Never send an angle bracket. "
  .. "Judge each play from your cards, the hand-type levels, and your jokers."

local READABLE_STATE = {
  SELECTING_HAND = READABLE_SELECTING_HAND,
}

local READABLE_JOKER_TAGS =
  "Joker roles: set_joker_intents records what each joker is for, using one of four tags -- CORE (the piece your build is built around), SCALING (it grows over time and pays off later), HOLD (useful for now, keep it while it earns its slot), CHANGE (you want to swap it out when something better shows up). A tag lasts the rest of the run and follows the card, not the slot; retag whenever your view changes. Tags show on each joker's row as 'your plan: TAG'. "
  .. "Selling jokers: each joker is sell-protected -- the first sell_card on it is rejected with a reason and sells only on an identical re-send; nothing sells automatically. No tag skips that confirmation; the tag only changes what the confirmation reminds you of. "
  .. "Any tag can carry an optional `note` (your own words, why) -- it shows on that joker's row while shopping and is echoed back if you try to sell it later; a note persists across shop visits until you overwrite it or clear it with note: ''. If notes on several jokers would together run long, later-slot jokers may drop theirs from this view (the note itself is not lost, and still applies when you try to sell that joker). "
  .. "Your joker list header also carries a running count, e.g. '2 sold this run' -- jokers you have sold since this run began; it does not reset between shops or antes, only when a new run starts."

return {
  READABLE_COMMON = READABLE_COMMON,
  READABLE_STATE = READABLE_STATE,
  READABLE_JOKER_TAGS = READABLE_JOKER_TAGS,
  has_jokers = has_jokers,
}
