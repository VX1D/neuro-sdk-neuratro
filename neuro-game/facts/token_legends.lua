local JOKER_F_LEGEND = "xM=xMult +M=+Mult +C=+Chips +NM/<suit>-card=+Mult per card of that suit +NC/<suit>-card=+Chips per card of that suit jh=hands-counter s=suit $/r=$-per-round song=that joker's song counter. "

local COMMON =
  "DECIDE=read STATE and each row's header first; use only currently-valid actions; reject options blocked by money/slots/hands/discards/picks/targets; compare the visible legal options; then call exactly one progress action. "
  .. "Each glossary entry below is written NAME=meaning, but in the actual context a token carries its own field delimiter -- ':' or '|' (e.g. 'V=owned vouchers' prints as V|..., 'J=joker rows' as J:..., 'H:' stays H:); match a token by its NAME, not the delimiter. Multi-column rows (e.g. I:, PC:, C[..]:, J:) then split their columns with ',' in the order named by that row's header. "
  .. "Common tokens. A column letter's meaning is local to its row/section: H=Hearts(card) or hands-left(B line); C=Clubs(card) or Common-rarity(shop row) or Consumables(C: section); D=discards-left(B line) or Diamonds(card) or deck(R line). Every index/indices in an action payload is 1-based -- it matches the i column and H: positions, which start at 1. STATE:=current game state. AVAIL=actions you can take right now. "
  .. "FRAME|=invariant game rules (natural language). RUN|=per-run deck/economy rules (natural language; distinct from the R= run-setup token). "
  .. "JK_ALL=your jokers' current aggregate totals (flat chips/mult/xmult plus COND(only if hand has X) bonuses); its value tokens read Nc=+chips Nm=+mult xN=xMult Nm/card=+mult per scoring card. "
  .. "ACTION_ERR|=why your last action was rejected; ALLOWED|=actions valid right now (these two are sent together after an invalid action). "
  .. "H:=your hand as indexed card tokens rank+suit (+enhancement/seal/edition tags; +DB=debuffed, scores 0; +LOCK=boss force-selected, always part of your played/discarded hand). "
  .. "Enhancements (the +Stone/+Gold/etc tag on H:/PC cards): Stone=+50 chips but no rank or suit; Bonus=+30 chips; Mult=+4 Mult; Wild=counts as every suit; Gold=+$3 if held in hand at end of round; Steel=x1.5 Mult while held in hand (not when scored); Glass=x2 Mult but 1-in-4 to shatter (destroyed) after scoring; Lucky=1-in-5 for +20 Mult and 1-in-15 for +$20. "
  .. "J=joker rows (i,n,f,flg,$; f=effect (a '·' separates independent effects; / inside an effect means 'per'), flg=flags: DEBUFFED (inactive this round, scores nothing), eternal (can't be sold/destroyed), perishable (debuffs after 5 rounds; shows live rounds-left), rental (loses $ each round), plus edition; $=sell value); "
  .. "the f field's [..] = that joker's scaling state: " .. JOKER_F_LEGEND
  .. "JD=joker full descriptions (i,n,d). JORD=current joker order left-to-right. PB=playbook joker rows. "
  .. "C=owned consumables (i,n,t,$,sel,ok,d; $=sell value, sel=hand cards the card needs selected or '-', ok=usable right now -- N means a creator card is blocked by a full joker/consumable output slot, so sell to free room first). "
  .. "V=owned vouchers shown name:effect. TAGS=active tags shown name:effect. ACTS=recent actions. "
  .. "L:=per-hand-type levels (n,lv,c,m,p; p=times played this run). "
  .. "DC=number of cards left in the draw pile. "

local SELECTING_HAND =
  "Tokens: B line N=blind name A=ante/win-ante S=score/target R=remaining-to-target H=hands-left D=discards-left $=money MOD=active run modifiers "
  .. "D (discards) spends a discard, not a hand: it swaps the chosen cards for new draws. "
  .. "PY=projected round payout (B blind-reward + hr hand-reward + dr discard-reward + I interest = T; this round's gain, NOT your ending balance -- current money is not added) "
  .. "ERN=end-of-round earnings (pending in SELECTING_HAND, realized at ROUND_EVAL). "
  .. "LP=last play/discard outcome (hand type|cards played, cards that scored|chips gained|score/target). "
  .. "HL=hand limits (MH=max selectable SEL=selected now HS=hand size CP/CD=can-play/can-discard). "
  .. "DK=deck info (N:deck name / DP:cards in discard pile; draw-pile count is the separate DC line). "
  .. "Structure=FULL-hand shape (a group of N same-rank cards also counts as every smaller group, so a 5-of-a-kind is also a pair and trips; top=highest repeated rank; suit_max=most cards of one suit; run_max=longest rank run). "
  .. "Ready=poker hands you can play right now; Close=hands one card away (only shown if you have discards); the [..] lists that hand's cards. "
  .. "Numbers in [..] after a Ready/Close hand are those cards' positions in H:; (lvN Nc xN)=that hand type's level, base chips, base mult; (N debuffed~0)=that many scoring cards are debuffed. "
  .. "(Jn applies)=that Ready hand triggers the condition of joker row n. "
  .. "BD=boss-debuff line (R:active rule as key=value pairs -- suit=<suit>/face=Y/min_cards=N/max_cards=N/value=<rank>/nominal=N/played_this_ante=Y/repeat_hand_type=N/single_hand_type=Y/most_played=<hand>/played_this_round=<hand>+<hand>|none / DB:how many of your hand cards are currently debuffed / TXT:plain-text description); distinct from the +DB card tag. PLAY=cards currently in the play area being resolved (card tokens). "
  .. "Card chips: 2-10 = printed rank, J/Q/K = 10, A = 11 (+enhancement/edition bonuses). "
  .. "After playing or discarding you draw back up to hand size. "
  .. "Structure/Ready/Close show shape only - the real value also depends on card enhancements/editions/seals, hand level (L:), your jokers and debuffs; judge it yourself. "

local SHOP =
  "Token legend: SH=shop economy line (A=ante $=money SP=spendable-now(cash minus reservations minus money floor) "
  .. "IN=interest-now CAP=interest-$-threshold NI=no-interest-flag "
  .. "RR=reroll-cost RRN=next-reroll-cost(rises $1 per paid reroll) RRM=max-affordable-rerolls "
  .. "PY=projected round payout (B blind-reward + hr hand-reward + dr discard-reward + I interest = T; this round's gain, NOT your ending balance -- current money is not added). "
  .. "FR=free-rerolls DSC=discount INF=inflation "
  .. "FLOOR=lowest balance you may spend to (negative with Credit Card) NXT=$ until the next +interest step MAXED=interest already at cap. "
  .. "LA=legality (CB=can-buy-anything-now CR=can-afford-reroll CRS=reroll-still-leaves-enough-to-buy-cheapest(- = nothing buyable to protect) "
  .. "CS=can-sell CU=can-use-consumable), "
  .. "I=items rows, columns a,i,n,t,rar,$,ok,f,d = area,index,name,type,rarity,cost,buyable-now(cash+open-slot),effect,desc; rar=joker rarity C/U/R/L; d '-' = same as f. "
  .. "ACTS also carries SR=rerolls this shop visit. "
  .. "NOTE: the shop_jokers row also sells consumables (type Planet/Tarot/Spectral) - those use consumable slots (C:), not joker slots (J:). "
  .. "A shop_booster row's type is its pack kind: Buffoon=jokers (needs a joker slot to keep), Celestial=planets and Arcana/Spectral=used straight from the pack (no slot needed), Standard=playing cards. "

local PACK =
  "Tokens: PK=pack header (type|PICKS:n picks remaining). "
  .. "PC rows = visible pack cards, columns i,n,t,f,ok (index, name, type, effect, "
  .. "ok=Y means takeable now / N means blocked by a full slot). "
  .. "The pack is already paid for: picking a card costs nothing, and skip_booster forfeits the remaining pick(s). "

local BLIND_SELECT =
  "Tokens: BS=blind economy (A=ante $=money H=hands D=discards NI=no-interest PY=projected round payout as B blind-reward+hr hand-reward+dr discard-reward+I interest=T (this round's gain, not your ending balance)); "
  .. "BU=bosses already used this run; BP=blinds on deck (OD/SM/BG/BOSS = on-deck/Small/Big/Boss state); "
  .. "BA=action legality (SK=can-skip RB=can-reroll-boss RC=reroll-cost RE=reroll-enabled -- RE=N until you own the Director's Cut or Retcon voucher); "
  .. "BO=blind options (columns named in its header row); SKP=blinds skipped this run. "

local ROUND_EVAL =
  "Tokens: RE line A=ante RND=round $=money IN=interest earned now CAP=interest cap NI=no-interest-flag "
  .. "ERN=end-of-round earnings (pending in SELECTING_HAND, realized at ROUND_EVAL); PY=projected round payout (B blind-reward+hr hand-reward+dr discard-reward+I interest=T; this round's gain, not your ending balance). "

local RUN_SETUP =
  "Tokens: R=run setup (D=deck K=stake SEEDED=seeded-yes/no CH=challenge SE=seed). "
  .. "SD=deck-selection header (K:selected-deck-key N:name U:unlocked-deck-count); the rows after it list selectable decks. "
  .. "SDC=column schema (i,k,n,e) for those selectable-deck rows -- lowercase k is the deck key to pass to change_selected_back (distinct from R's uppercase K=stake). "
  .. "STK[change_stake to_key]=stake keys: the integer to pass as change_stake to_key for each stake. "
  .. "LA=legality (SR=can-start-run DS=can-switch-deck). "

local GAME_OVER =
  "Tokens: GO=game-over summary (outcome|A:ante reached|R:round reached). "

local BY_STATE = {
  SELECTING_HAND = { key = "selecting_hand", text = SELECTING_HAND },
  SHOP           = { key = "shop",           text = SHOP },
  BLIND_SELECT   = { key = "blind_select",   text = BLIND_SELECT },
  ROUND_EVAL     = { key = "round_eval",     text = ROUND_EVAL },
  RUN_SETUP      = { key = "run_setup",      text = RUN_SETUP },
  MENU           = { key = "run_setup",      text = RUN_SETUP },
  GAME_OVER      = { key = "game_over",      text = GAME_OVER },
}

local PACK_ENTRY = { key = "pack", text = PACK }

local function for_state(state_name)
  local entry = BY_STATE[state_name]
  if entry then return entry.key, entry.text end
  local ok, StateKinds = pcall(require, "core.state_kinds")
  if ok and StateKinds and StateKinds.is_pack_state and StateKinds.is_pack_state(state_name) then
    return PACK_ENTRY.key, PACK_ENTRY.text
  end
  return nil, nil
end

return { for_state = for_state, COMMON = COMMON }
