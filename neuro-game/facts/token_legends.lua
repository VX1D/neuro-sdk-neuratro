local function has_jokers() return not not (G and G.jokers and G.jokers.cards and #G.jokers.cards > 0) end

local READABLE_SELECTING_HAND =
  "## Card rank chips\n2-10 = the printed number, J/Q/K = 10, A = 11 (before any enhancement/edition bonus)."
  .. "\n\n## Playing and confirming\nPlaying a hand spends nothing until the commit goes through: an unguarded play commits immediately, while a guarded play opens one review. Once that review is delivered, the only move is to answer it: yes commits the exact named cards, no cancels it. Playing or discarding again cannot replace or confirm the open review. No itself never plays, discards, or draws. Answering no spends the single review for this unchanged hand: discard next for a redraw, or play a specific alternative; that next play is final and commits immediately."
  .. "\n\n## Drawing\nAfter playing or discarding, the game draws according to the current blind and deck effects; normally it refills toward hand size."
  .. "\n\n## Reading the hand lines\nThe Shape, Ready to play now and One card away lines show shape only -- real value also depends on card enhancements/editions/seals, hand level, your jokers and debuffs. The (level N, N chips xN mult) figures are that hand type's CURRENT values. Under The Flint they are shown already halved -- do not halve them again. Under The Arm they are already what the hand scores at when you play it now: a hand above level 1 is shown one level lower, with The Arm's drop applied -- do not subtract it again -- and its Hand levels row also names the level it is at now; a level-1 hand is not lowered. Plasma deck is the exception: it balances chips and mult at scoring, so the shown split is pre-balance."
  .. "\n\n## Choosing a play\nThe cards listed on a Ready hand are the exact cards that form it (any hand type counts) -- play exactly those positions, no extra or missing cards, unless the decision states a boss minimum play size (add filler to reach it) or you own Splash (every played card scores, so spare cards may be added while the hand type stays the same). First check the chips remaining to clear the blind -- if a Ready hand's score reaches it, playing it now clears the blind. Judge each hand's value YOURSELF from its level and base values, your jokers and your card bonuses -- no number in the state does that for you. If every Ready hand is far below the per-hand chip target (a rough per-hand average, not a floor), a discard toward a one-card-away hand can upgrade it. Once the target is clearly reachable, winning in fewer hands pays more at cash-out."

local READABLE_COMMON =
  "## How to decide\nRead the situation and your available actions, drop any blocked by money, slots, hands, discards, or targets, then call exactly ONE structured action. Confirming a play means answering its review yes or no; yes commits the named cards, no cancels the review without discarding cards."
  .. "\n\n## Positions\nPositions and indices are 1-based -- the number before each card or row (card 1 is the first card in your hand)."
  .. "\n\n## Actions\nActions are structured tools selected from the registered action list. Put values in the action fields required by its schema; prose context is not an action serialization channel. "
  .. "Judge each play from your cards, the hand-type levels, and your jokers."

local READABLE_STATE = {
  SELECTING_HAND = READABLE_SELECTING_HAND,
}

local READABLE_JOKER_TAGS =
  "## Joker roles\nRecording joker roles says what each joker is for, using one of four tags -- CORE (the piece your build is built around), SCALING (it grows over time and pays off later), HOLD (useful for now, keep it while it earns its slot), CHANGE (you want to swap it out when something better shows up). A tag lasts the rest of the run and follows the card, not the slot; retag whenever your view changes. Tags show on each joker's row as 'your plan: TAG'."
  .. "\n\n## Selling jokers\nNo tag skips the joker sell review; the tag only changes what the review reminds you of."
  .. "\n\n## Notes on a joker\nAny tag can carry an optional `note` (your own words, why; up to 256 characters) -- it shows on that joker's row while shopping and is echoed back if you try to sell it later; a note persists across shop visits until you overwrite it or clear it with note: ''. If notes on several jokers would together run long, later-slot jokers may drop theirs from this view (the note itself is not lost, and still applies when you try to sell that joker)."
  .. "\n\n## Sold count\nYour joker list header also carries a running count, e.g. '2 sold this run' -- jokers you have sold since this run began; it does not reset between shops or antes, only when a new run starts."
local ACTION_SEMANTICS_V1_KEY = "permanent_rule:action_semantics:v1"
local ACTION_SEMANTICS_V1_MAX_BYTES = 5120
local ACTION_SEMANTICS_V1_MAX_TOKENS = 896
local ACTION_SEMANTICS_V1_TEXT =
  "## Command channel\nStructured actions are the only command channel: call exactly one "
  .. "registered action and put its values in the fields required by that action's schema; prose in "
  .. "context or query never serializes an action. Every card, hand, joker, shop, and pack position "
  .. "is 1-based (the first item is index 1). A force lists every action usable now: the moves that settle the current "
  .. "decision and the tools its state names. Using a tool ends the force without settling the decision, "
  .. "which is asked again right after with the board updated."
  .. "\n\n## Hands\nA play spends one hand when it commits; a discard spends a discard and not a hand. "
  .. "A play either commits at once or opens one review that costs no hand. "
  .. "Judge a hand from Your hand, "
  .. "the Hand levels, and the Ready to play now / One card away lines before playing. An answer to a review that no longer "
  .. "matches the offered play is acknowledged without changing anything. "
  .. "When a guarded play is offered, the only move is to answer its review: "
  .. "answer yes to commit the exact named hand indices, or no to cancel without playing, "
  .. "discarding, or drawing. After no, the next play is the final choice and commits "
  .. "immediately; discard for a redraw. Discards are the cheap redraw resource: throw away "
  .. "weak cards to draw toward a better hand, only while you have discards left."
  .. "\n\n## Shop\nIn SHOP, a buy targets the exact area and index (include name when offered). "
  .. "Use use=false for a normal targeted shop buy (especially a consumable kept in inventory); "
  .. "use=true is only for a direct-use consumable; a targeted consumable is bought with use=false and "
  .. "then used from your consumables. A shop voucher is reviewed first and is "
  .. "permanent for the run, with no sale or undo; after that review, the next legal buy "
  .. "for a voucher is FINAL even if it names a different voucher. Selling a joker is guarded the same "
  .. "way: the first joker sale opens a review without selling, and the next legal sale "
  .. "commits immediately, including a different joker. Selling a consumable never opens a review. "
  .. "Leaving the shop may first return a review when it would forfeit interest or your joker lineup changed; "
  .. "leaving again leaves. Every joker needs a role tag before you leave."
  .. "\n\n## Packs\nAn open pack is already paid for: take a card from it, "
  .. "do not buy it. A pack pick directly uses the picked "
  .. "card when the card is a consumable; it has no use=true field. In a directional action "
  .. "left_index is the hand card the effect applies to and right_index the card it takes from; any two different "
  .. "positions work, and the hand is rearranged for you when the effect needs the other order."
  .. "\n\n## Joker roles\nRecording joker roles takes a 1-based joker index, tag CORE, SCALING, HOLD, or CHANGE, and an "
  .. "optional note; tags follow the card, and notes persist until overwritten or cleared. Leaving note "
  .. "out keeps the note on file and an empty note clears it. A call names each joker index at most once."
  .. "\n\n## Plan fields\nDirect plan fields are structured under plan: hand_plan, build_plan, money_plan, and "
  .. "hand_focus; each states a committed decision, not analysis or a copy of the board, and hand_focus "
  .. "records your declaration without ever blocking a different play. "
  .. "boss_plan records your plan for this ante's boss: selecting a blind saves it once that boss is shown, "
  .. "and playing or discarding saves it only on the Boss round. It stops applying when the boss changes, so "
  .. "do not use it to carry an ordinary plan. Never restate live facts such as cash, "
  .. "the joker roster or the boss text in a plan field -- those are refreshed separately. When "
  .. "Your move asks for plan fields, fill only the ones it names; they describe the plan from "
  .. "that action onward and are saved with it."
  .. "\n\n" .. require("core.plan_requirements").guide_section()
  .. "\n\n## Fields\nUse each move's current schema, never an invented field. "
  .. "One action sent with the same parameters again and again on one screen is refused after a few tries, "
  .. "and a move that does not move the game on, such as recording a plan, is offered only a few times until you make one that does."

local function count_tokens(text)
  local count = 0
  for _ in text:gmatch("%S+") do count = count + 1 end
  return count
end

assert(#ACTION_SEMANTICS_V1_TEXT <= ACTION_SEMANTICS_V1_MAX_BYTES,
  "action semantics guide exceeds byte cap")
assert(count_tokens(ACTION_SEMANTICS_V1_TEXT) <= ACTION_SEMANTICS_V1_MAX_TOKENS,
  "action semantics guide exceeds token cap")

local ACTION_SEMANTICS_V1 = {
  key = ACTION_SEMANTICS_V1_KEY,
  text = ACTION_SEMANTICS_V1_TEXT,
  max_bytes = ACTION_SEMANTICS_V1_MAX_BYTES,
  max_tokens = ACTION_SEMANTICS_V1_MAX_TOKENS,
}

return {
  ACTION_SEMANTICS_V1 = ACTION_SEMANTICS_V1,
  READABLE_COMMON = READABLE_COMMON,
  READABLE_STATE = READABLE_STATE,
  READABLE_JOKER_TAGS = READABLE_JOKER_TAGS,
  has_jokers = has_jokers,
}

