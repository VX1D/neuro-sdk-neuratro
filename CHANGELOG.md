# Changelog

### 1.2.0 -- 2026-10-26

// TODO

### 1.1.0 -- 2026-08-25

<details>
<summary><strong>Neuro reads the game in plain English</strong></summary>

- Game state is described in natural language instead of compact notation.
- Hands: levels, base chips and mult, straight and flush outs, draw odds; Smeared Joker and Wild Cards counted for every suit.
- Jokers: live scoring for each joker including retriggers and Blueprint/Brainstorm copies; eternal, perishable and rental flags; sell values; how often each joker triggered this run.
- Blinds: rules and counterplay for all 28 bosses, Director's Cut and Retcon rerolls.
- Economy: spendable cash (Credit Card debt floor), reroll prices, interest and end-of-round payout.
- A short summary of what changed since her last decision.

</details>

<details>
<summary><strong>Planning and safer actions</strong></summary>

- Neuro can record a plan for the current blind, her build and her money, carried between decisions.
- Playing a hand takes a confirmation step so cards are not submitted by accident; selling jokers mid-round is blocked unless a boss requires it.
- Duplicate or replayed actions are never executed twice.

</details>

<details>
<summary><strong>HUD</strong></summary>

- Voucher tray showing owned vouchers.
- One acquire animation for buys, picks and new jokers replaces the buy toast and centre showcase.
- Animated booster pack presentation with Neuro and Evil styles.
- Card minis show enhancements, seals, editions and stickers.
- F8: place the HUD (anchors, offsets, sizes), edit colours per persona, tune game speed and timing.

</details>

<details>
<summary><strong>Stability</strong></summary>

- An error in the mod no longer crashes Balatro; watchdogs keep long animations from stalling the game.
- Relay: checks messages against the Neuro SDK, restores registered actions after a reconnect, drops stale messages from a previous run and reports actions that went unanswered.

</details>

### 1.0.0 -- 2026-07-06

<details>
<summary><strong>Rebuilt for reliability</strong></summary>

- The mod was rebuilt from the ground up; behaviour is the same but far more stable.
- Joker and voucher context is re-sent only when it changes; hand level-ups are reported on their own.
- A repeated action id gets its earlier result instead of running again; messages from an old session are ignored.
- Safer file exchange with the relay (atomic writes).

</details>

<details>
<summary><strong>Settings</strong></summary>

- Every setting is documented in `neuro.conf.example` and can be changed live in the F8 tuning panel.

</details>

<details>
<summary><strong>HUD</strong></summary>

- Separate panels for the run, the shop and booster packs replace the single overlay.
- Cards drawn from the game's own sprites; dedicated voucher tray.
- Per-persona colour grading and smoother animation.

</details>

### 0.5.3 -- 2026-03-16

- Booster pack cards keep their positions after a pick, and the pack panel no longer resizes.
- Purchases show as a compact toast at the top centre instead of a large panel in the corner; several buys queue one after another.

### 0.5.2 -- 2026-03-04

- Fixed actions in Steamodded booster packs (including Spectral packs); skipping a pack is always offered.
- Modded cards show their names instead of internal keys.
- Overlay panels: drop shadow, single clean border, full coloured shop descriptions.
- Fixed the joker panel flashing blank when a joker is sold.

### 0.5.1 -- 2026-03-04

- Neuro now sees free rerolls, shop discounts, all owned vouchers, the discard pile, cards in the play area, blinds skipped, bosses already faced, price inflation and the end-of-round payout.

### 0.5.0 -- 2026-03-03

- Aces score 11 chips (were 10).
- Selling checks consumables too; buying covers vouchers and boosters.
- An unknown reroll price is no longer guessed.
- Fixed a crash when a debuffed hand was rejected.
- Less work every frame.
- Relay reconnects back off from 1 s up to 30 s.
- Profanity filter: fewer false positives.
- Seeded runs earn unlocks and stats again.
- Run seeds are no longer printed to the log.
- Card index checks on every action.

### 0.4.1 -- 2026-03-03

- Booster pack cards shown side by side with larger art; edition names shown ("Negative 9 of Clubs").
- Card minis show enhanced faces and a seal dot.
- Buying a voucher shows a "NEW VOUCHER" popup.
- Fixed: the pick overlay staying after a pick, right-panel rows flickering, a crash on a duplicate pick.

### 0.4.0 -- 2026-03-03

- Edition tags next to card names; clearer joker mult display.
- Deck names shown properly.
- Shop panel hides in every pack state.
- Darker Neuro palette; emotes per persona and moment; improved login animation.

### 0.3.1 -- 2026-03-03

- Fixed decisions not being sent to Neuro.
- Shop affordability uses the real balance.
- The strongest hand is shown as information, not as an order to play it.

### 0.3.0 -- 2026-03-03

- When no hands are left, Neuro is told the blind is lost and can still use discards.
- Targeting advice for all Tarot and Spectral cards (warnings on destructive ones) and the Neuratro consumables.
- Blueprint and Brainstorm show which joker they copy.
- Shop shows the projected end-of-round money and interest.
- Voucher upgrade pairs are tracked.

### 0.2.1 -- 2026-03-02

- Fixed a crash when the mod is not enabled.
- Profanity filter catches leetspeak.
- Blind selection no longer blocked in valid states.
- Joker synergy analysis.

### 0.2.0 -- 2026-03-02

- Strategy guidance for every deck.
- Consumables that target hand cards work in one action; usable consumables are highlighted.
- Enhanced cards in hand are shown.
- Cooldowns configurable in `.env`.
- Fixed several stuck states in the shop, game over and overlays; fixed crashes on missing card areas.
- Joker panel shows full descriptions; new Neuro palette.

### 0.1.0 -- 2026-02-26

- Full game integration from the title screen to game over.
- Score estimation and hand detection.
- Neuro-sama and Evil Neuro personas with their own palettes and emotes.
- Card glow for cards the AI is using.
- Profanity filter for stream safety.
- Action throttling and cooldowns.
