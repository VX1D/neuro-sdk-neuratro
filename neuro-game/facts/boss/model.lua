local M = {}
local Utils = require("util.utils")

local NAME_TO_KEY = {}

local function record_name(key)
  local rec = M.RECORDS[key]
  return rec and rec.name or nil
end

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
  return record_name(key) ~= nil
end

function M.display_name(key)
  if type(key) ~= "string" then return nil end
  local defs = blind_defs()
  local def = defs and defs[key]
  if type(def) ~= "table" and not record_name(key) then return nil end
  return require("facts.display_names").of("Blind", key,
    type(def) == "table" and def or { name = record_name(key) })
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

function M.upcoming_is_public(rr)
  local st = rr and rr.blind_states
  if type(st) ~= "table" then return true end
  return st.Boss ~= "Hide"
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

function M.active_key(in_blind)
  local b = G and G.GAME and G.GAME.blind
  if type(b) ~= "table" or b.disabled or (in_blind and not b.in_blind) then return nil end
  return M.resolve_key(b)
end

local SMEARED_PAIR = { Hearts = "Diamonds", Diamonds = "Hearts", Spades = "Clubs", Clubs = "Spades" }

local function suit_facts(suit)
  return function(v)
    local note = ""
    if v.smeared and SMEARED_PAIR[suit] then
      note = " You own Smeared Joker, so " .. SMEARED_PAIR[suit] .. " count as " .. suit .. " and are debuffed too."
    end
    return { suit = suit, smeared_note = note }
  end
end

local SUIT_RULE = "All {suit} cards are debuffed {this_round} (marked +DB): they score 0 chips and their abilities"
  .. " are off, but they still count toward forming a hand. Every Wild Card counts as every suit, so Wild Cards"
  .. " are debuffed too; Stone Cards have no suit and are not.{smeared_note}"

local function face_facts(v)
  local note = ""
  if v.pareidolia then
    note = " You own Pareidolia: every card counts as a face card, so every card in the deck is debuffed."
  end
  return { pareidolia_note = note }
end

-- Discarded cards retain their facing.
local FD_HIDDEN = "A face-down card's identity is hidden until it is played; discarding it does not reveal it."
  .. " It scores normally when played."

local function facedown_facts(v)
  local note = ""
  if (v.facedown_in_hand or 0) > 0 then
    note = " " .. tostring(v.facedown_in_hand) .. " card(s) in your hand are face down."
  end
  return { fd_note = note, fd_hidden = FD_HIDDEN }
end

-- The Arm lowers whichever hand type is played, so list every type it could lower.
local function arm_facts()
  local ok, rows = pcall(function() return require("facts.hand_facts").levels() end)
  if not ok or type(rows) ~= "table" then return { arm_note = "" } end
  local up = {}
  for _, r in ipairs(rows) do
    if (tonumber(r.level) or 1) > 1 then up[#up + 1] = tostring(r.name) .. " (level " .. tostring(r.level) .. ")" end
  end
  if #up == 0 then return { arm_note = " Every hand type is at level 1, so no play here lowers a level." } end
  return { arm_note = " Hand types above level 1, which lose a level for the rest of the run if played here: "
    .. table.concat(up, ", ") .. "." }
end

local plural = require("facts.text").plural

local function is_are(n) return (n == 1) and " is" or " are" end

local function wheel_odds()
  local b = G and G.GAME and G.GAME.blind
  return require("facts.dynamic_jokers").chance(type(b) == "table" and b or nil, 1, 7, "wheel")
end

local function odds_num(x)
  x = tonumber(x) or 0
  return (x == math.floor(x)) and string.format("%d", x) or (string.format("%.2f", x):gsub("0+$", ""))
end

local function odds_text(n, d) return odds_num(n) .. " in " .. odds_num(d) end

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
    if cash then note = note .. " You hold " .. Utils.money(cash) .. "." end
  end
  return { tax_note = note }
end

local function psychic_facts(v)
  if not v.hand_n then return { five_note = "" } end
  local note = " You are holding " .. plural(v.hand_n, "card") .. "."
  local ok, relaxed = pcall(function() return require("facts.boss.legality").play_floor_relaxed() end)
  if ok and relaxed then note = note .. " Five cards cannot be selected now, so any hand you play scores 0." end
  return { five_note = note }
end

local function acorn_facts(v)
  local n = v.facedown_jokers
  if not n or n == 0 then return { flip_note = "" } end
  return { flip_note = " " .. plural(n, "joker") .. is_are(n)
    .. " face down in a shuffled order." }
end

local function heart_facts(v)
  local pool = v.heart_pool or v.joker_n
  if not pool or pool == 0 then return { pick_note = "" } end
  if pool < (v.joker_n or pool) then
    if pool == 1 then return { pick_note = " Only 1 of your jokers is not debuffed, so it is the one picked." } end
    return { pick_note = " The pick is drawn from the " .. plural(pool, "joker") .. " of yours that are not debuffed." }
  end
  if pool == 1 then return { pick_note = " You own 1 joker, so it is the one picked." } end
  return { pick_note = " The pick is drawn from your " .. plural(pool, "joker") .. "." }
end

-- Before blind selection in the shop, “this round” would refer to the round in progress.
M.ROUND_PHRASE = {
  default = { this_round = "this round", for_this_round = "for this round" },
  upcoming = { this_round = "during that blind", for_this_round = "during that blind" },
}

local PILLAR_TAIL = "It is a set of specific cards, not of ranks."
local ACORN_TAIL = "They flip back up only when the blind is defeated or disabled; there is no mid-round reveal."

M.RECORDS = {

  bl_hook = {
    key = "bl_hook", name = "The Hook",
    horizon = { select = true, round = true },
    rule = "Each time you play a hand, 2 random cards still in your hand are discarded before the hand"
      .. " scores, so held-card effects (Steel Cards, Baron, Shoot the Moon, Raised Fist, Mime) lose them."
      .. " These discards do not use up your own, yet they fire on-discard effects such as Green Joker, Ramen,"
      .. " Castle, Hit the Road, Yorick, Mail-In Rebate and Purple Seals (Burnt Joker ignores them), and"
      .. " happen on every hand, including the last.",
    facts = resource_tax_facts,
    templates = { status = "{rule}{tax_note}" },
  },

  bl_ox = {
    key = "bl_ox", name = "The Ox",
    horizon = { shop = true, select = true, round = true },
    rule = "Playing a {most_played} sets your money to $0 (not negative); the hand itself still scores."
      .. " That is the game's most-played-hand snapshot from the end of the previous ante's boss round;"
      .. " hands played since do not change it.",
    facts = function(v) return { most_played = tostring(v.most_played or "?") } end,
  },

  bl_house = {
    key = "bl_house", name = "The House",
    horizon = { select = true, round = true, draw = true },
    rule = "Your opening draw {this_round} is dealt face down; the first hand you play or discard ends the"
      .. " effect for later draws. {fd_hidden}",
    draw_rule = { play = false, discard = false },
    facts = facedown_facts,
    templates = { status = "{rule}{fd_note}" },
  },

  bl_wall = {
    key = "bl_wall", name = "The Wall",
    horizon = { select = true },
    rule = "This blind has no debuff. Its chip target is double a normal boss target (blind mult 4 instead of 2).",
    templates = { status = "{rule}" },
  },

  bl_wheel = {
    key = "bl_wheel", name = "The Wheel",
    horizon = { select = true, round = true, draw = true },
    rule = "Each card you draw has a {p} in {d} chance of arriving face down, on every draw {this_round}."
      .. " {fd_hidden}",
    draw_rule = function()
      local n, d = wheel_odds()
      return { play = "chance", discard = "chance", odds = { n, d } }
    end,
    facts = function(v)
      local f = facedown_facts(v)
      local n, d = wheel_odds()
      f.p, f.d = odds_num(n), odds_num(d)
      return f
    end,
    templates = { status = "{rule}{fd_note}" },
  },

  bl_arm = {
    key = "bl_arm", name = "The Arm",
    horizon = { select = true, round = true },
    rule = "Each hand you play permanently lowers that hand type's level by 1 for the rest of the run, down"
      .. " to a minimum of level 1. The reduction is applied before scoring, so the hand that triggers it"
      .. " already scores at the lowered level. Hand types at level 1 are not lowered.",
    facts = arm_facts,
    templates = { select = "{rule}{arm_note}", status = "{rule}{arm_note}" },
  },

  bl_club = {
    key = "bl_club", name = "The Club",
    horizon = { select = true, round = true },
    rule = SUIT_RULE, facts = suit_facts("Clubs"), marks = { "+DB" },
  },

  bl_fish = {
    key = "bl_fish", name = "The Fish",
    horizon = { select = true, round = true, draw = true },
    rule = "After each hand you play, the replacement cards are drawn face down. Draws after a discard are"
      .. " face up, and so is the opening draw. {fd_hidden}",
    draw_rule = function(round)
      return { play = (tonumber(round and round.hands_left) or 0) > 0 and "all" or false, discard = false }
    end,
    facts = facedown_facts,
    templates = { status = "{rule}{fd_note}" },
  },

  bl_psychic = {
    key = "bl_psychic", name = "The Psychic",
    horizon = { select = true, hand = true },
    rule = "A hand that plays fewer than 5 cards scores 0 and still uses a hand. Five is also the selection"
      .. " cap, so a hand that scores plays exactly 5 cards; the extra cards do not have to contribute"
      .. " to the scoring hand.",
    facts = psychic_facts,
    templates = { status = "{rule}{five_note}" },
  },

  bl_goad = {
    key = "bl_goad", name = "The Goad",
    horizon = { select = true, round = true },
    rule = SUIT_RULE, facts = suit_facts("Spades"), marks = { "+DB" },
  },

  bl_water = {
    key = "bl_water", name = "The Water",
    horizon = { select = true, round = true },
    rule = "When the round starts, this blind sets your discards to 0. Discards granted by jokers after that"
      .. " are kept.",
    facts = resource_tax_facts,
    templates = { status = "{rule}{tax_note}" },
  },

  bl_window = {
    key = "bl_window", name = "The Window",
    horizon = { select = true, round = true },
    rule = SUIT_RULE, facts = suit_facts("Diamonds"), marks = { "+DB" },
  },

  bl_manacle = {
    key = "bl_manacle", name = "The Manacle",
    horizon = { select = true, round = true },
    rule = "Your hand size is 1 lower {for_this_round}.",
    facts = resource_tax_facts,
    templates = { status = "{rule}{tax_note}" },
  },

  bl_eye = {
    key = "bl_eye", name = "The Eye",
    horizon = { select = true, hand = true },
    rule = "Each poker hand type scores only the first time you play it {this_round}; every later hand of a"
      .. " type already played scores 0 and still uses a hand. Types count by base hand: a Royal Flush is"
      .. " a Straight Flush here.",
    facts = function(v) return { used = v.eye_used } end,
    templates = {
      status = "{rule} Hand types already played this round: {used}.",
      hand = "Hand types already played this round: {used}.",
      rejection = "BOSS ({boss}): {handname} was already played this round -- under this boss it scores 0."
        .. " Hand types already played this round: {used}.",
    },
  },

  bl_mouth = {
    key = "bl_mouth", name = "The Mouth",
    horizon = { select = true, hand = true },
    rule = "The first hand type you play {this_round} locks the type: every later hand of a different type"
      .. " scores 0 and still uses a hand. Types count by base hand: a Royal Flush is a Straight Flush here.",
    facts = function(v) return { locked = v.mouth_locked or "none yet" } end,
    templates = {
      status = "{rule} Locked hand type: {locked}.",
      hand = "Locked hand type: {locked}.",
      rejection = "BOSS ({boss}): this round is locked to {locked}; {handname} is a different type --"
        .. " under this boss it scores 0.",
    },
  },

  bl_plant = {
    key = "bl_plant", name = "The Plant",
    horizon = { select = true, round = true },
    rule = "All face cards (J/Q/K) are debuffed (marked +DB): they score 0 chips and their abilities are"
      .. " off, but they still count toward forming a hand.{pareidolia_note}",
    facts = face_facts, marks = { "+DB" },
  },

  bl_serpent = {
    key = "bl_serpent", name = "The Serpent",
    horizon = { select = true, round = true },
    rule = "After each hand you play or discard, you draw exactly 3 cards (or all remaining deck cards if"
      .. " fewer than 3 are left), ignoring your hand-size cap. The opening draw of the round is a normal"
      .. " full draw.",
    facts = function(v) return { deck_n = v.deck_n, draw_n = v.draw_n } end,
    templates = {
      status = "{rule} The deck has {deck_n} card(s) left, so the next such draw is {draw_n} card(s).",
    },
  },

  bl_pillar = {
    key = "bl_pillar", name = "The Pillar",
    horizon = { ante = true, select = true, round = true },
    rule = "The specific cards you played earlier this ante (during the Small and Big blinds) are debuffed"
      .. " {for_this_round}, marked +DB and +USED: they score 0 chips and their abilities are off, but they"
      .. " still count toward forming a hand. The set was fixed when this blind started and does not grow"
      .. " during the round. " .. PILLAR_TAIL,
    facts = function(v) return {
      db_count = v.debuffed_card_count,
      used_in_hand = v.pillar_used_in_hand,
      ante_count = v.played_this_ante_count,
      fd_note = ((v.facedown_in_hand or 0) > 0) and " Face-down cards in your hand are not counted." or "",
    } end,
    templates = {
      select = "The specific cards you played earlier this ante (during the Small and Big blinds) will be"
        .. " debuffed {for_this_round}, marked +DB and +USED: they score 0 chips and their abilities are off, but"
        .. " they still count toward forming a hand. The set is fixed when this blind starts and does not grow"
        .. " during the round. " .. PILLAR_TAIL,
      status = "{rule} {db_count} card(s) in your deck are +DB this round; {used_in_hand} of them are in"
        .. " your hand.{fd_note}",
      ante = "{ante_count} card(s) in your deck are flagged as played this ante. This ante's Boss is"
        .. " The Pillar, which debuffs exactly those cards.",
    },
    marks = { "+DB", "+USED" },
  },

  bl_needle = {
    key = "bl_needle", name = "The Needle",
    horizon = { select = true, round = true },
    data = { hands_at_start = 1 },
    rule = "When the round starts, this blind sets your hands for the round to {hands_at_start}; hands granted"
      .. " by jokers when the blind starts are added on top of that {hands_at_start}. Its chip target is half a normal boss target, the same target as this"
      .. " ante's Small Blind.",
    facts = resource_tax_facts,
    templates = { status = "{rule}{tax_note}" },
  },

  bl_head = {
    key = "bl_head", name = "The Head",
    horizon = { select = true, round = true },
    rule = SUIT_RULE, facts = suit_facts("Hearts"), marks = { "+DB" },
  },

  bl_tooth = {
    key = "bl_tooth", name = "The Tooth",
    horizon = { select = true, round = true },
    rule = "You lose $1 per card played, counting every card in the play area whether it scores or not, on"
      .. " every hand {this_round}. Money can go negative.",
    facts = resource_tax_facts,
    templates = { status = "{rule}{tax_note}" },
  },

  bl_flint = {
    key = "bl_flint", name = "The Flint",
    horizon = { select = true },
    rule = "The base chips and base mult of each played hand are halved (rounded half up; mult no lower"
      .. " than 1, chips no lower than 0) before card and joker effects are added. While this blind is"
      .. " active, the Hand levels list shows the halved values.",
    templates = { status = "{rule}" },
  },

  bl_mark = {
    key = "bl_mark", name = "The Mark",
    horizon = { select = true, round = true, draw = true },
    rule = "Every face card (J/Q/K) you draw is dealt face down for the whole round, so a card drawn face"
      .. " down under this boss is known to be a face card. It scores normally when"
      .. " played.{pareidolia_note}",
    draw_rule = function()
      local df = M.debuff_facts()
      local k = df.owns_joker("Pareidolia") and "all" or "faces"
      return { play = k, discard = k }
    end,
    facts = function(v)
      local f = facedown_facts(v)
      f.pareidolia_note = v.pareidolia
        and " You own Pareidolia: every card counts as a face card, so every card is drawn face down." or ""
      return f
    end,
    templates = { status = "{rule}{fd_note}" },
  },

  bl_final_acorn = {
    key = "bl_final_acorn", name = "Amber Acorn",
    horizon = { select = true, round = true },
    rule = "Your jokers were flipped face down and shuffled into a random order when this blind started."
      .. " They are not debuffed: they still trigger normally, in their current left-to-right order. " .. ACORN_TAIL,
    facts = acorn_facts,
    templates = {
      select = "When this blind starts, your jokers are flipped face down and shuffled into a random order."
        .. " They are not debuffed: they still trigger normally, in that new left-to-right order. " .. ACORN_TAIL,
      status = "{rule}{flip_note}",
    },
  },

  bl_final_leaf = {
    key = "bl_final_leaf", name = "Verdant Leaf",
    horizon = { shop = true, select = true, round = true },
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
    key = "bl_final_vessel", name = "Violet Vessel",
    horizon = { select = true },
    rule = "This blind has no debuff. Its chip target is 3x a normal boss target (blind mult 6 instead of 2).",
    templates = { status = "{rule}" },
  },

  bl_final_heart = {
    key = "bl_final_heart", name = "Crimson Heart",
    horizon = { select = true, round = true },
    rule = "One of your jokers that is not already debuffed, picked at random, is debuffed (disabled) until"
      .. " the next pick. The first pick happens on the opening draw and a new one on the draw after every"
      .. " hand you play; discards do not trigger a pick. The same joker is not picked twice in a row unless"
      .. " no other joker can be picked.",
    facts = heart_facts,
    templates = { status = "{rule}{pick_note}" },
  },

  bl_final_bell = {
    key = "bl_final_bell", name = "Cerulean Bell",
    horizon = { select = true, hand = true },
    rule = "One card in your hand is always force-selected (marked +LOCK): it is part of every hand you"
      .. " play and every discard, and it fills one of the 5 selection slots. After every play or discard,"
      .. " a new card is force-selected at random from all the cards then in your hand.",
    facts = function(v) return { lock_index = tostring(v.lock_index or "?") } end,
    templates = {
      status = "{rule} The +LOCK card is at position {lock_index}.",
      hand = "The +LOCK card is at position {lock_index}; it is part of every play and every discard.",
    },
    marks = { "+LOCK" },
  },

}
for key, rec in pairs(M.RECORDS) do NAME_TO_KEY[rec.name] = key end

-- A modded `stay_flipped` value is unknown; only mirror the base blind and flipped-card modifier.
function M.next_draw_facedown()
  local out = { play = false, discard = false, chance = 0 }
  local sources = {}
  local b = G and G.GAME and G.GAME.blind
  if type(b) == "table" and not b.disabled then
    local rec = M.RECORDS[M.resolve_key(b) or ""]
    local obj = b.config and b.config.blind
    local rule = rec and rec.draw_rule
    if type(rule) == "function" then rule = rule(G.GAME.current_round) end
    if type(rule) == "table" then
      out.play, out.discard = rule.play, rule.discard
      if rule.odds then sources[#sources + 1] = rule.odds end
    elseif type(obj) == "table" and type(obj.stay_flipped) == "function" then
      out.play, out.discard = "unknown", "unknown"
    end
  end
  local mods = G and G.GAME and G.GAME.modifiers
  local fc = type(mods) == "table" and tonumber(mods.flipped_cards) or nil
  if fc and fc > 0 then
    for _, k in ipairs({ "play", "discard" }) do out[k] = out[k] or "chance" end
    sources[#sources + 1] = { 1, fc }
  end
  local seen = 1
  for _, o in ipairs(sources) do
    local n, d = tonumber(o[1]) or 0, tonumber(o[2]) or 0
    seen = seen * (1 - ((d > 0) and math.max(0, math.min(1, n / d)) or 1))
  end
  out.chance = 1 - seen
  if #sources == 1 then
    out.chance_text = odds_text(tonumber(sources[1][1]) or 0, tonumber(sources[1][2]) or 0)
  elseif #sources > 1 then
    out.chance_text = string.format("%d%%", math.floor(out.chance * 100 + 0.5))
  end
  return out
end

function M.get(key)
  return key and M.RECORDS[key] or nil
end

function M.round_hands(key, hands)
  local rec = M.get(key)
  local set = rec and rec.data and tonumber(rec.data.hands_at_start)
  return set or hands
end

function M.debuff_facts()
  return require("facts.debuff_facts")
end

return M
