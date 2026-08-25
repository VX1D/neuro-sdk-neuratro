local M = {}

M.BOSS_NAMES = {
  bl_ox = "The Ox", bl_eye = "The Eye", bl_mouth = "The Mouth",
  bl_pillar = "The Pillar", bl_flint = "The Flint",
  bl_serpent = "The Serpent", bl_arm = "The Arm",
  bl_final_leaf = "Verdant Leaf", bl_final_bell = "Cerulean Bell",
  bl_house = "The House", bl_wheel = "The Wheel", bl_fish = "The Fish", bl_mark = "The Mark",
  bl_hook = "The Hook", bl_water = "The Water", bl_needle = "The Needle", bl_tooth = "The Tooth",
  bl_wall = "The Wall", bl_manacle = "The Manacle", bl_final_heart = "Crimson Heart",
  bl_final_vessel = "Violet Vessel", bl_final_acorn = "Amber Acorn",
  bl_club = "The Club", bl_head = "The Head", bl_goad = "The Goad", bl_window = "The Window",
  bl_plant = "The Plant", bl_psychic = "The Psychic",
}

local NAME_TO_KEY = {}
for key, name in pairs(M.BOSS_NAMES) do NAME_TO_KEY[name] = key end

local function blind_defs()
  local defs = G and G.P_BLINDS
  if type(defs) ~= "table" or next(defs) == nil then return nil end
  return defs
end

local function is_boss_key(key)
  if type(key) ~= "string" or key == "" then return false end
  local defs = blind_defs()
  local def = defs and defs[key]
  if type(def) == "table" then return def.boss ~= nil end
  return M.BOSS_NAMES[key] ~= nil
end

local function live_boss_name(key)
  local defs = blind_defs()
  local def = defs and defs[key]
  if type(def) == "table" and def.boss and type(def.name) == "string" and def.name ~= "" then
    return def.name
  end
  return nil
end

function M.boss_name(key)
  if type(key) ~= "string" then return nil end
  return live_boss_name(key) or M.BOSS_NAMES[key]
end

local function key_for_name(name)
  if type(name) ~= "string" or name == "" then return nil end
  local defs = blind_defs()
  if defs then
    for key, def in pairs(defs) do
      if type(def) == "table" and def.boss and def.name == name then
        return key
      end
    end
  end
  return NAME_TO_KEY[name]
end

function M.resolve_key(b)
  if type(b) ~= "table" then return nil end
  if is_boss_key(b.key) then return b.key end
  local center = b.config and b.config.blind
  if type(center) == "table" and is_boss_key(center.key) then
    return center.key
  end
  return key_for_name(b.name)
end

local SMEARED_PAIR = { Hearts = "Diamonds", Diamonds = "Hearts", Spades = "Clubs", Clubs = "Spades" }

local function suit_facts(suit)
  return function(v)
    local note = ""
    if v.smeared and SMEARED_PAIR[suit] then
      note = " You own Smeared Joker, so " .. SMEARED_PAIR[suit] .. " count as " .. suit .. " and are debuffed too."
    end
    return { suit = suit, smeared_note = note, db_in_hand = v.debuffed_in_hand }
  end
end

local SUIT_RULE = "All {suit} cards are debuffed this round (marked +DB): they score 0 chips and their abilities"
  .. " are off, but they still count toward forming a hand. Every Wild Card counts as every suit, so Wild Cards"
  .. " are debuffed too; Stone Cards have no suit and are not.{smeared_note}"

local function face_facts(v)
  local note = ""
  if v.pareidolia then
    note = " You own Pareidolia: every card counts as a face card, so every card in the deck is debuffed."
  end
  return { pareidolia_note = note }
end

local function facedown_facts(v)
  local note = ""
  if (v.facedown_in_hand or 0) > 0 then
    note = " " .. tostring(v.facedown_in_hand) .. " card(s) in your hand are face down."
  end
  return { fd_note = note }
end

local function arm_facts(v)
  local mp = v.most_played
  if type(mp) ~= "string" or mp == "" then return { arm_note = "" } end
  local level
  local ok, rows = pcall(function() return require("facts.hand_facts").levels() end)
  if ok and type(rows) == "table" then
    for _, r in ipairs(rows) do
      if r.name == mp then level = tonumber(r.level) end
    end
  end
  if level and level <= 1 then
    return { arm_note = " " .. mp .. " is the hand you have played most this run and is already at"
      .. " level 1, so it cannot be lowered further." }
  end
  return { arm_note = " " .. mp .. " is the hand you have played most this run"
    .. (level and (", at level " .. tostring(level)) or "")
    .. "; a level spent here is gone for the rest of the run." }
end

local function plural(n, word)
  return tostring(n) .. " " .. word .. (n == 1 and "" or "s")
end

local function is_are(n) return (n == 1) and " is" or " are" end

local function resource_tax_facts(v)
  local key = M.resolve_key(v.blind)
  local note = ""
  if key == "bl_needle" and v.hands_left then
    note = " You have " .. plural(v.hands_left, "hand") .. " this round."
  elseif key == "bl_water" and v.discards_left then
    note = " You have " .. plural(v.discards_left, "discard") .. " this round."
  elseif key == "bl_manacle" and v.hand_size then
    note = " Your hand holds " .. plural(v.hand_size, "card") .. " this round."
  elseif key == "bl_hook" and v.hand_n then
    note = " You are holding " .. plural(v.hand_n, "card")
      .. ", with " .. plural(v.deck_n or 0, "card") .. " left in the deck to refill from."
  elseif key == "bl_tooth" then
    local cash = tonumber(G and G.GAME and G.GAME.dollars)
    note = " A five-card play costs $5."
    if cash then note = note .. " You hold $" .. tostring(cash) .. "." end
  end
  return { tax_note = note }
end

local function psychic_facts(v)
  if not v.hand_n then return { five_note = "" } end
  return { five_note = " You are holding " .. plural(v.hand_n, "card") .. "." }
end

local function acorn_facts(v)
  local n = v.facedown_jokers
  if not n or n == 0 then return { flip_note = "" } end
  return { flip_note = " " .. plural(n, "joker") .. is_are(n)
    .. " face down in a shuffled order." }
end

local function heart_facts(v)
  if not v.joker_n or v.joker_n == 0 then return { pick_note = "" } end
  if v.joker_n == 1 then return { pick_note = " You own 1 joker, so it is the one picked." } end
  return { pick_note = " The pick is drawn from your " .. plural(v.joker_n, "joker") .. "." }
end

M.RECORDS = {

  bl_hook = {
    key = "bl_hook", name = "The Hook", class = "C5_RESOURCE_TAX",
    horizon = { select = true, round = true }, since = 1,
    rule = "After each hand you play, 2 random cards are discarded from your remaining hand automatically."
      .. " These automatic discards do not use up your own discards. This happens on every hand played,"
      .. " including the last.",
    facts = resource_tax_facts,
    templates = { status = "{rule}{tax_note}" },
  },

  bl_ox = {
    key = "bl_ox", name = "The Ox", class = "C5_RESOURCE_TAX",
    horizon = { shop = true, select = true, round = true }, since = 6,
    rule = "Playing a {most_played} sets your money to $0 (not negative); the hand itself still scores."
      .. " That is the game's most-played-hand snapshot from the end of the previous ante's boss round;"
      .. " hands played since do not change it.",
    facts = function(v) return { most_played = tostring(v.most_played or "?") } end,
  },

  bl_house = {
    key = "bl_house", name = "The House", class = "C7_INFO_DENIAL",
    horizon = { select = true, round = true, draw = true }, since = 2,
    rule = "Your opening draw this round is dealt face down; the first hand you play or discard ends the"
      .. " effect for later draws. A face-down card's identity is hidden until it is played or discarded,"
      .. " but it scores normally when played.",
    facts = facedown_facts,
    templates = { status = "{rule}{fd_note}" },
  },

  bl_wall = {
    key = "bl_wall", name = "The Wall", class = "C6_STAT_CHECK",
    horizon = { select = true }, since = 2,
    rule = "This blind has no debuff. Its chip target is double a normal boss target (blind mult 4 instead of 2).",
    templates = { status = "{rule}" },
  },

  bl_wheel = {
    key = "bl_wheel", name = "The Wheel", class = "C7_INFO_DENIAL",
    horizon = { select = true, round = true, draw = true }, since = 2,
    rule = "Each card you draw has a {p} in 7 chance of arriving face down, on every draw this round."
      .. " A face-down card's identity is hidden until it is played or discarded, but it scores normally"
      .. " when played.",
    facts = function(v)
      local f = facedown_facts(v)
      f.p = v.probability_normal
      return f
    end,
    templates = { status = "{rule}{fd_note}" },
  },

  bl_arm = {
    key = "bl_arm", name = "The Arm", class = "C5_RESOURCE_TAX",
    horizon = { select = true, round = true }, since = 2,
    rule = "Each hand you play permanently lowers that hand type's level by 1 for the rest of the run, down"
      .. " to a minimum of level 1. The reduction is applied before scoring, so the hand that triggers it"
      .. " already scores at the lowered level. Hand types at level 1 are not lowered.",
    facts = arm_facts,
    templates = { select = "{rule}{arm_note}", status = "{rule}{arm_note}" },
  },

  bl_club = {
    key = "bl_club", name = "The Club", class = "C1_STATIC_CARD_DEBUFF",
    horizon = { select = true, round = true }, since = 1,
    rule = SUIT_RULE, facts = suit_facts("Clubs"), marks = { "+DB" },
  },

  bl_fish = {
    key = "bl_fish", name = "The Fish", class = "C7_INFO_DENIAL",
    horizon = { select = true, round = true, draw = true }, since = 2,
    rule = "After each hand you play, the replacement cards are drawn face down. Draws after a discard are"
      .. " face up, and so is the opening draw. A face-down card's identity is hidden until it is played or"
      .. " discarded, but it scores normally when played.",
    facts = facedown_facts,
    templates = { status = "{rule}{fd_note}" },
  },

  bl_psychic = {
    key = "bl_psychic", name = "The Psychic", class = "C4_SELECTION_CONSTRAINT",
    horizon = { select = true, hand = true }, since = 1,
    rule = "A hand that plays fewer than 5 cards scores 0 and still uses a hand. Five is also the selection"
      .. " cap, so every hand this round plays exactly 5 cards; the extra cards do not have to contribute"
      .. " to the scoring hand.",
    affordance = true,
    facts = psychic_facts,
    templates = { status = "{rule}{five_note}" },
  },

  bl_goad = {
    key = "bl_goad", name = "The Goad", class = "C1_STATIC_CARD_DEBUFF",
    horizon = { select = true, round = true }, since = 1,
    rule = SUIT_RULE, facts = suit_facts("Spades"), marks = { "+DB" },
  },

  bl_water = {
    key = "bl_water", name = "The Water", class = "C5_RESOURCE_TAX",
    horizon = { select = true, round = true }, since = 2,
    rule = "This blind set your discards to 0 when the round started. Discards granted by jokers after the"
      .. " blind was set are kept.",
    facts = resource_tax_facts,
    templates = { status = "{rule}{tax_note}" },
  },

  bl_window = {
    key = "bl_window", name = "The Window", class = "C1_STATIC_CARD_DEBUFF",
    horizon = { select = true, round = true }, since = 1,
    rule = SUIT_RULE, facts = suit_facts("Diamonds"), marks = { "+DB" },
  },

  bl_manacle = {
    key = "bl_manacle", name = "The Manacle", class = "C5_RESOURCE_TAX",
    horizon = { select = true, round = true }, since = 1,
    rule = "Your hand size is 1 lower for this round.",
    facts = resource_tax_facts,
    templates = { status = "{rule}{tax_note}" },
  },

  bl_eye = {
    key = "bl_eye", name = "The Eye", class = "C3_HAND_TYPE_GATE",
    horizon = { select = true, hand = true }, since = 3,
    rule = "Each poker hand type scores only the first time you play it this round; every later hand of a"
      .. " type already played scores 0 and still uses a hand. Types count by base hand: a Royal Flush is"
      .. " a Straight Flush here.",
    facts = function(v) return { used = v.eye_used } end,
    templates = {
      status = "{rule} Hand types already played this round: {used}.",
      hand = "Hand types already played this round: {used}.",
      rejection = "BOSS ({boss}): {handname} was already played this round -- under this boss it scores 0."
        .. " Hand types already played this round: {used}.",
    },
    rejection_vars = { "handname" },
  },

  bl_mouth = {
    key = "bl_mouth", name = "The Mouth", class = "C3_HAND_TYPE_GATE",
    horizon = { select = true, hand = true }, since = 2,
    rule = "The first hand type you play this round locks the type: every later hand of a different type"
      .. " scores 0 and still uses a hand. Types count by base hand: a Royal Flush is a Straight Flush here.",
    facts = function(v) return { locked = v.mouth_locked or "none yet" } end,
    templates = {
      status = "{rule} Locked hand type: {locked}.",
      hand = "Locked hand type: {locked}.",
      rejection = "BOSS ({boss}): this round is locked to {locked}; {handname} is a different type --"
        .. " under this boss it scores 0.",
    },
    rejection_vars = { "handname" },
  },

  bl_plant = {
    key = "bl_plant", name = "The Plant", class = "C1_STATIC_CARD_DEBUFF",
    horizon = { select = true, round = true }, since = 4,
    rule = "All face cards (J/Q/K) are debuffed (marked +DB): they score 0 chips and their abilities are"
      .. " off, but they still count toward forming a hand.{pareidolia_note}",
    facts = face_facts, marks = { "+DB" },
  },

  bl_serpent = {
    key = "bl_serpent", name = "The Serpent", class = "C5_RESOURCE_TAX",
    horizon = { select = true, round = true }, since = 5,
    rule = "After each hand you play or discard, you draw exactly 3 cards (or all remaining deck cards if"
      .. " fewer than 3 are left), ignoring your hand-size cap. The opening draw of the round is a normal"
      .. " full draw.",
    facts = function(v) return { deck_n = v.deck_n, draw_n = v.draw_n } end,
    templates = {
      status = "{rule} The deck has {deck_n} card(s) left, so the next such draw is {draw_n} card(s).",
    },
  },

  bl_pillar = {
    key = "bl_pillar", name = "The Pillar", class = "C2_HISTORY_CARD_DEBUFF",
    horizon = { ante = true, select = true, round = true }, since = 1,
    rule = "The specific cards you played earlier this ante (during the Small and Big blinds) are debuffed"
      .. " for this round, marked +DB and +USED: they score 0 chips and their abilities are off, but they"
      .. " still count toward forming a hand. The set was fixed when this blind started and does not grow"
      .. " during the round. It is a set of specific cards, not of ranks.",
    facts = function(v) return {
      db_count = v.debuffed_card_count,
      used_in_hand = v.pillar_used_in_hand,
      ante_count = v.played_this_ante_count,
    } end,
    templates = {
      status = "{rule} {db_count} card(s) in your deck are +DB this round; {used_in_hand} of them are in"
        .. " your hand.",
      ante = "{ante_count} card(s) in your deck are flagged as played this ante. This ante's Boss is"
        .. " The Pillar, which debuffs exactly those cards.",
    },
    marks = { "+DB", "+USED" },
  },

  bl_needle = {
    key = "bl_needle", name = "The Needle", class = "C5_RESOURCE_TAX",
    horizon = { select = true, round = true }, since = 2,
    rule = "This blind set your hands for the round to 1; hands granted by jokers when the blind starts are"
      .. " added on top of that 1. Its chip target is half a normal boss target, the same target as this"
      .. " ante's Small Blind.",
    facts = resource_tax_facts,
    templates = { status = "{rule}{tax_note}" },
  },

  bl_head = {
    key = "bl_head", name = "The Head", class = "C1_STATIC_CARD_DEBUFF",
    horizon = { select = true, round = true }, since = 1,
    rule = SUIT_RULE, facts = suit_facts("Hearts"), marks = { "+DB" },
  },

  bl_tooth = {
    key = "bl_tooth", name = "The Tooth", class = "C5_RESOURCE_TAX",
    horizon = { select = true, round = true }, since = 3,
    rule = "You lose $1 per card played, counting every card in the play area whether it scores or not, on"
      .. " every hand this round. Money can go negative.",
    facts = resource_tax_facts,
    templates = { status = "{rule}{tax_note}" },
  },

  bl_flint = {
    key = "bl_flint", name = "The Flint", class = "C6_STAT_CHECK",
    horizon = { select = true }, since = 2,
    rule = "The base chips and base mult of each played hand are halved (rounded half up; mult no lower"
      .. " than 1, chips no lower than 0) before card and joker effects are added. While this blind is"
      .. " active, the Hand levels list shows the halved values.",
    templates = { status = "{rule}" },
  },

  bl_mark = {
    key = "bl_mark", name = "The Mark", class = "C7_INFO_DENIAL",
    horizon = { select = true, round = true, draw = true }, since = 2,
    rule = "Every face card (J/Q/K) you draw is dealt face down for the whole round, so a card drawn face"
      .. " down under this boss is known to be a face card. It scores normally when"
      .. " played.{pareidolia_note}",
    facts = function(v)
      local f = facedown_facts(v)
      f.pareidolia_note = v.pareidolia
        and " You own Pareidolia: every card counts as a face card, so every card is drawn face down." or ""
      return f
    end,
    templates = { status = "{rule}{fd_note}" },
  },

  bl_final_acorn = {
    key = "bl_final_acorn", name = "Amber Acorn", class = "C7_INFO_DENIAL",
    horizon = { select = true, round = true }, since = 8,
    rule = "Your jokers were flipped face down and shuffled into a random order when this blind started."
      .. " They are not debuffed: they still trigger normally, in their current left-to-right order. They"
      .. " flip back up only when the blind is defeated or disabled; there is no mid-round reveal.",
    facts = acorn_facts,
    templates = { status = "{rule}{flip_note}" },
  },

  bl_final_leaf = {
    key = "bl_final_leaf", name = "Verdant Leaf", class = "C1_STATIC_CARD_DEBUFF",
    horizon = { shop = true, select = true, round = true }, since = 8,
    rule = "Every playing card, including Stone Cards, is debuffed (marked +DB): it scores 0 chips with all"
      .. " abilities off, until you sell a Joker. Selling any one Joker lifts the debuff for the rest of"
      .. " the round. Consumables do not count, a Joker destroyed rather than sold does not count, and"
      .. " Eternal Jokers cannot be sold.",
    facts = function(v) return { sellable = v.sellable_jokers } end,
    templates = {
      status = "{rule} You have {sellable} sellable (non-Eternal) joker(s).",
    },
    marks = { "+DB" },
  },

  bl_final_vessel = {
    key = "bl_final_vessel", name = "Violet Vessel", class = "C6_STAT_CHECK",
    horizon = { select = true }, since = 8,
    rule = "This blind has no debuff. Its chip target is 3x a normal boss target (blind mult 6 instead of 2).",
    templates = { status = "{rule}" },
  },

  bl_final_heart = {
    key = "bl_final_heart", name = "Crimson Heart", class = "C8_JOKER_INTERFERENCE",
    horizon = { select = true, round = true }, since = 8,
    rule = "One of your jokers, picked at random at each draw to your hand, is debuffed (disabled) until"
      .. " the next pick. The first pick happens on the opening draw, and a new pick follows every hand"
      .. " you play. The same joker is not picked twice in a row unless it is your only one.",
    facts = heart_facts,
    templates = { status = "{rule}{pick_note}" },
  },

  bl_final_bell = {
    key = "bl_final_bell", name = "Cerulean Bell", class = "C4_SELECTION_CONSTRAINT",
    horizon = { select = true, hand = true }, since = 8,
    rule = "One card in your hand is always force-selected (marked +LOCK): it is part of every hand you"
      .. " play and every discard, and it fills one of the 5 selection slots. After it leaves your hand, a"
      .. " newly drawn card is force-selected.",
    facts = function(v) return { lock_index = tostring(v.lock_index or "?") } end,
    templates = {
      status = "{rule} The +LOCK card is at position {lock_index}.",
      hand = "The +LOCK card is at position {lock_index}; it is part of every play and every discard.",
    },
    marks = { "+LOCK" },
  },

}

function M.get(key)
  return key and M.RECORDS[key] or nil
end

local function template_vars(text, into)
  for var in tostring(text or ""):gmatch("{([%w_]+)}") do into[var] = true end
  return into
end

local function closure_errors(rec, sample_view)
  local errs = {}
  local allowed = { rule = true, boss = true }
  local ok_f, facts = true, {}
  if rec.facts then ok_f, facts = pcall(rec.facts, sample_view) end
  if not ok_f then
    errs[#errs + 1] = rec.key .. ": facts() errored: " .. tostring(facts)
    facts = {}
  end
  for k in pairs(facts) do allowed[k] = true end
  for _, var in ipairs(rec.rejection_vars or {}) do allowed[var] = true end
  local used = template_vars(rec.rule, {})
  for _, tpl in pairs(rec.templates or {}) do template_vars(tpl, used) end
  for var in pairs(used) do
    if not allowed[var] then
      errs[#errs + 1] = rec.key .. ": template variable {" .. var .. "} is not produced by facts()"
    end
  end
  return errs
end

if rawget(_G, "NEURO_TEST") then M._test = { closure_errors = closure_errors } end

return M
