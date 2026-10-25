local M = {}

local Utils = require("util.utils")
local PublicCard = require("facts.public_card_identity")
local DisplayNames = require("facts.display_names")

local MAX_EVENTS = 32
local ITSELF = {}

local causes = setmetatable({}, { __mode = "k" })
local events_of = setmetatable({}, { __mode = "k" })
local consumable_in_use = nil

local function store()
  return require("core.neuro_lifecycle").neuro_table("destruction_log",
    function() return { next_sequence = 1, events = {} } end)
end

function M.cursor()
  local s = G and G.NEURO and G.NEURO.destruction_log
  return type(s) == "table" and math.max(0, (tonumber(s.next_sequence) or 1) - 1) or 0
end

local function area_of(card)
  local a = card.area
  local named = G and ((a == G.jokers and "jokers") or (a == G.consumeables and "consumables")
    or (a == G.hand and "hand") or (a == G.play and "play")) or nil
  if not named then
    return G and ((a == G.deck and "deck") or (a == G.discard and "discard pile")) or "area", nil
  end
  local index
  for i, c in ipairs(type(a) == "table" and type(a.cards) == "table" and a.cards or {}) do
    if c == card then index = i; break end
  end
  return named, index
end

local function face(card)
  local CardUtil = require("facts.card_util")
  local mods = {}
  local enh = CardUtil.enhancement_key(card)
  if enh then mods[#mods + 1] = CardUtil.enhancement_name(enh) end
  if type(card.seal) == "string" then mods[#mods + 1] = DisplayNames.seal(card.seal) end
  local ed = CardUtil.edition_name(card.edition)
  if ed then mods[#mods + 1] = ed end
  local head = enh == "m_stone" and table.remove(mods, 1) or Utils.playing_card_label(card)
  return #mods > 0 and (head .. " (" .. table.concat(mods, ", ") .. ")") or head
end

local function label(card)
  local area, index = area_of(card)
  if not (PublicCard.is_public(card) and Utils.is_playing_card(card)) then
    return PublicCard.label(card, area, index)
  end
  return face(card)
end
M.card_label = label
M.card_face = face

local function shatters(card)
  if card.shattered then return true end
  local ok, v = pcall(function() return SMODS.shatters(card) end)
  return ok and v == true
end

local function cause_label(card, src)
  if src == nil then return nil end
  if src == card then return ITSELF end
  return label(src)
end

local function text_of(e)
  if e.cause == ITSELF then return e.label .. " destroyed itself" end
  if e.cause then return e.label .. " destroyed by " .. e.cause end
  return e.label .. (e.shattered and " shattered" or " destroyed")
end

function M.record(card)
  if type(card) ~= "table" or events_of[card] then return false end
  local s = store()
  if not s then return false end
  local src = causes[card]
  if src == nil and consumable_in_use and G and G.TAROT_INTERRUPT ~= nil then src = consumable_in_use end
  local e = { sequence = s.next_sequence, run_generation = tonumber(G.NEURO.run_generation) or 0,
    label = label(card), shattered = shatters(card), cause = cause_label(card, src) }
  s.next_sequence = s.next_sequence + 1
  s.events[#s.events + 1] = e
  while #s.events > MAX_EVENTS do table.remove(s.events, 1) end
  events_of[card] = e
  return true
end

local function attribute(card, src)
  if causes[card] ~= nil then return end
  causes[card] = src
  local e = events_of[card]
  if e and e.cause == nil then e.cause = cause_label(card, src) end
end

function M.between(after, through)
  after, through = tonumber(after) or 0, tonumber(through) or 0
  if through <= after then return nil end
  local s = G and G.NEURO and G.NEURO.destruction_log
  local generation = tonumber(G and G.NEURO and G.NEURO.run_generation) or 0
  local out, first_kept = {}, nil
  for _, e in ipairs(type(s) == "table" and s.events or {}) do
    first_kept = first_kept or e.sequence
    if e.sequence > after and e.sequence <= through and e.run_generation == generation then
      out[#out + 1] = text_of(e)
    end
  end
  local lost = first_kept and math.max(0, math.min(first_kept - 1, through) - after) or 0
  if lost > 0 then table.insert(out, 1, tostring(lost) .. " earlier destruction(s) not listed") end
  return #out > 0 and out or nil
end

local function note_joker(self, context, ret, pre_sliced)
  if type(context) == "table" and (ret == true or (type(ret) == "table" and ret.remove)) then
    local target = context.destroy_card or context.destroying_card
      or (context.discard and context.other_card) or nil
    if type(target) == "table" then attribute(target, self) end
  end
  for _, j in ipairs(G and G.jokers and G.jokers.cards or {}) do
    if j.getting_sliced and not (pre_sliced and pre_sliced[j]) then attribute(j, self) end
  end
end

local function already_sliced()
  local out
  for _, j in ipairs(G and G.jokers and G.jokers.cards or {}) do
    if j.getting_sliced then out = out or {}; out[j] = true end
  end
  return out
end

function M.install()
  local SM, Card = rawget(_G, "SMODS"), rawget(_G, "Card")
  if not (type(SM) == "table" and type(SM.calculate_context) == "function" and type(Card) == "table") then
    return false
  end
  if SM.__neuro_destruction_log then return false end
  SM.__neuro_destruction_log = true

  local calculate_context = SM.calculate_context
  SM.calculate_context = function(context, ...)
    if type(context) == "table" and context.remove_playing_cards and type(context.removed) == "table" then
      for _, card in ipairs(context.removed) do pcall(M.record, card) end
    end
    local flags, a, b = calculate_context(context, ...)
    if type(context) == "table" and context.joker_type_destroyed
        and not (type(flags) == "table" and flags.no_destroy) then
      pcall(M.record, context.card)
    end
    return flags, a, b
  end

  local calculate_joker = Card.calculate_joker
  Card.calculate_joker = function(self, context, ...)
    local pre = already_sliced()
    local ret, triggered = calculate_joker(self, context, ...)
    pcall(note_joker, self, context, ret, pre)
    return ret, triggered
  end

  local use_consumeable = Card.use_consumeable
  Card.use_consumeable = function(self, ...)
    consumable_in_use = self
    return use_consumeable(self, ...)
  end
  return true
end

return M
