local Rewards = {}

local Utils = require("util.utils")
local ContextDelivery = require("core.context_delivery")
local CardUtil = require("facts.card_util")

local function once_per_run(key, message, spoken)
  local n = G and G.NEURO
  if not n then return message, spoken end
  local tagged = tostring(n.run_generation or 0) .. "|" .. tostring(key)
  if n.last_reward_outcome_key == tagged then return nil end
  n.last_reward_outcome_key = tagged
  return message, spoken
end

local function cleared_on_last_hand(gm)
  local cr = gm.current_round
  return (cr and tonumber(cr.hands_left)) == 0
end

local function blind_cleared(gm, blind)
  return (tonumber(gm.chips) or 0) >= (tonumber(blind.chips) or 0)
end

local function was_saved()
  if _G.SMODS and _G.SMODS.saved then return true end
  return not not (G and G.GAME and G.GAME.saved_text)
end

function Rewards.outcome(prev_state, state_name)
  local gm = G and G.GAME
  if not gm then return nil end
  if prev_state == nil then return nil end

  if state_name == "ROUND_EVAL" and prev_state ~= "ROUND_EVAL" then
    local blind = gm.blind
    if not blind then return nil end
    local name = blind.name or "the blind"
    local round = gm.round or "?"
    local ante_raw = tonumber(gm.round_resets and gm.round_resets.ante)
    local beaten = ante_raw and (blind.boss and (ante_raw - 1) or ante_raw) or nil
    local ante = beaten or "?"
    local win_ante = tonumber(gm.win_ante) or 8
    if not blind_cleared(gm, blind) then
      local saved_key = table.concat({ "saved", tostring(ante), tostring(round), tostring(name) }, "|")
      local rescue = was_saved() and "A save effect kept the run alive" or "Something kept the run alive"
      return once_per_run(saved_key, string.format(
        "You did NOT beat %s at ante %s -- you scored %s of the %s chips it needed. %s, but the blind stands unbeaten.",
        tostring(name), tostring(ante), Utils.fmt_num(gm.chips), Utils.fmt_num(blind.chips), rescue), true)
    end
    if gm.won and blind.boss and beaten == win_ante then
      return once_per_run("won|" .. tostring(beaten),
        string.format("You won the run -- beat the final boss, %s, at ante %s.", tostring(name), tostring(ante)), true)
    end
    local endless = (gm.won and beaten and beaten > win_ante) and " (endless)" or ""
    local key = table.concat({ "clear", tostring(ante), tostring(round), tostring(name) }, "|")
    if blind.boss then
      return once_per_run(key,
        string.format("You beat the Boss Blind, %s, at ante %s%s.", tostring(name), tostring(ante), endless), true)
    end
    return once_per_run(key,
      string.format("You cleared the %s (ante %s, round %s)%s.", tostring(name), tostring(ante), tostring(round), endless),
      cleared_on_last_hand(gm))
  end

  if state_name == "GAME_OVER" and prev_state ~= "GAME_OVER" then
    local ante = (gm.round_resets and gm.round_resets.ante) or "?"
    local blind = gm.blind
    local name = (blind and blind.name) or "the blind"
    local round = gm.round or "?"
    local key = table.concat({ "game_over", tostring(ante), tostring(round), tostring(name), tostring(gm.won) }, "|")
    if gm.won then
      return once_per_run(key,
        string.format("Your endless run ended -- %s beat you at ante %s, round %s.", tostring(name), tostring(ante), tostring(round)), true)
    end
    return once_per_run(key,
      string.format("You lost the run -- %s beat you at ante %s, round %s.", tostring(name), tostring(ante), tostring(round)), true)
  end

  return nil
end

local SPOKEN_RARITIES = { [3] = true, [4] = true }

-- A modded joker's rarity can be the string key rather than the vanilla number, which the engine itself normalizes (dump functions/common_events.lua:2248, SMODS game_object.lua:1330-1332).
local RARITY_TIER = { Common = 1, Uncommon = 2, Rare = 3, Legendary = 4 }
local function rarity_tier(rarity)
  if type(rarity) == "string" then return RARITY_TIER[rarity] or tonumber(rarity) end
  return tonumber(rarity)
end

function Rewards.rare_joker_message(card)
  local n = G and G.NEURO
  if not (n and card) then return nil end
  if n.rare_joker_announced then return nil end
  local center = card.config and card.config.center
  if not (center and center.set == "Joker") then return nil end
  local rarity = rarity_tier(center.rarity)
  if not (rarity and SPOKEN_RARITIES[rarity]) then return nil end
  n.rare_joker_announced = true
  return string.format("You pulled a %s joker: %s.",
    CardUtil.rarity_name(rarity), Utils.real_name_or(card))
end

function Rewards.announce_rare_joker(card)
  local msg = Rewards.rare_joker_message(card)
  if not msg then return false end
  return ContextDelivery.prompt_at("rare_joker", ContextDelivery.here(), msg)
end

local SELF_EXPIRING = {
  j_gros_michel = "Gros Michel was destroyed by its end-of-round extinction roll.",
  j_popcorn = "Popcorn was eaten after its Mult fell to 0 at the end of the round.",
}

local function joker_key(card)
  local center = card and card.config and card.config.center
  return center and center.key or nil
end

local function joker_roster_snapshot(state_name)
  local cards = {}
  for _, card in ipairs((G and G.jokers and G.jokers.cards) or {}) do
    local key = joker_key(card)
    if SELF_EXPIRING[key] then cards[card.sort_id or card] = key end
  end
  local gm = G and G.GAME
  return {
    state = state_name,
    ante = gm and gm.round_resets and gm.round_resets.ante,
    round = gm and gm.round,
    cards = cards,
  }
end

function Rewards.observe_self_expiring_jokers(state_name)
  local n = G and G.NEURO
  if not n or not (G and G.jokers and type(G.jokers.cards) == "table") then return {} end
  local previous = n.reward_joker_roster
  local current = joker_roster_snapshot(state_name)
  n.reward_joker_roster = current
  if state_name ~= "ROUND_EVAL" or type(previous) ~= "table"
      or type(previous.cards) ~= "table" then return {} end

  local events = {}
  for identity, key in pairs(previous.cards) do
    if current.cards[identity] == nil then
      events[#events + 1] = {
        key = key,
        coords = {
          "ante " .. tostring(previous.ante or "?"),
          "round " .. tostring(previous.round or "?"),
        },
        text = SELF_EXPIRING[key],
      }
    end
  end
  table.sort(events, function(a, b) return a.key < b.key end)
  return events
end

return Rewards
