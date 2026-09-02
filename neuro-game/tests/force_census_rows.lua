local M = {}

local LB = require("tests.fixtures.live_board")

local PACKS = { TAROT_PACK = true, BUFFOON_PACK = true, STANDARD_PACK = true,
  PLANET_PACK = true, SPECTRAL_PACK = true,
  SMODS_BOOSTER_OPENED = true }
local function states(...)
  local set = {}
  for _, s in ipairs({ ... }) do
    if s == "*PACK*" then for p in pairs(PACKS) do set[p] = true end else set[s] = true end
  end
  return set
end

local function norm(s) return (tostring(s):lower():gsub("[^%w]", "")) end
local function has(msg, token) return msg:find(token, 1, true) ~= nil end
local function has_loose(nmsg, token)
  token = norm(token)
  return token ~= "" and nmsg:find(token, 1, true) ~= nil
end

local function upcoming_boss_line()
  local rr = G and G.GAME and G.GAME.round_resets
  local key = rr and rr.blind_choices and rr.blind_choices.Boss
  local bdef = key and G.P_BLINDS and G.P_BLINDS[key]
  if not bdef then return nil end
  local ok, line = pcall(require("facts.boss.render").boss_line, "select", key, bdef)
  if ok and type(line) == "string" and #line > 40 then return line end
  return nil
end

local function names_of(area)
  local out = {}
  for _, c in ipairs((area and area.cards) or {}) do
    local n = c.ability and c.ability.name
    if n then out[#out + 1] = n end
  end
  return out
end

local function facedown_identity()
  local out = {}
  for _, c in ipairs((G and G.jokers and G.jokers.cards) or {}) do
    if c.facing == "back" then
      out[#out + 1] = c.ability.name
      local sigil = LB.SIGIL[c.config and c.config.center and c.config.center.key]
      if sigil then out[#out + 1] = sigil end
    end
  end
  for _, c in ipairs((G and G.hand and G.hand.cards) or {}) do
    if c.facing == "back" and c.base then
      out[#out + 1] = tostring(c.base.value) .. " of " .. tostring(c.base.suit)
    end
  end
  return out
end

local ROWS = {
  {
    id = "joker roster",
    states = states("SELECTING_HAND", "SHOP", "BLIND_SELECT", "ROUND_EVAL", "*PACK*"),
    header = "Your jokers (",
    data = function() return G.jokers and G.jokers.cards and #G.jokers.cards > 0 end,
    values = function()
      local want = {}
      for _, c in ipairs(G.jokers.cards) do
        if c.facing ~= "back" then
          want[#want + 1] = c.ability.name
          local sigil = LB.SIGIL[c.config.center.key]
          if sigil then want[#want + 1] = sigil end
        end
      end
      return want
    end,
  },
  {
    id = "face-down cards stay unnamed",
    states = states("SELECTING_HAND"),
    header = "face-down (hidden)",
    data = function() return #facedown_identity() > 0 end,
    forbidden = function() return facedown_identity() end,
  },
  {
    id = "joker stickers",
    states = states("SHOP"),
    data = function()
      for _, c in ipairs((G.jokers and G.jokers.cards) or {}) do
        if c.debuff or (c.ability and c.ability.eternal) then return true end
      end
      return false
    end,
    values = function()
      local want = {}
      for _, c in ipairs(G.jokers.cards) do
        if c.debuff then want[#want + 1] = "debuffed (inactive)" end
        if c.ability.eternal then want[#want + 1] = "cannot be sold" end
      end
      return want
    end,
  },
  {
    id = "roster plan rows",
    states = states("SHOP"),
    header = "-- your plan: ",
    data = function()
      return G.NEURO and G.NEURO.joker_intents and next(G.NEURO.joker_intents) ~= nil
    end,
    values = function()
      local want = {}
      for _, c in ipairs(G.jokers.cards) do
        local entry = G.NEURO.joker_intents[c.sort_id]
        if entry and entry.tag then want[#want + 1] = "your plan: " .. entry.tag end
        if entry and entry.note and entry.note ~= "" then
          want[#want + 1] = "your note: " .. entry.note
        end
        if entry and entry.provenance then
          want[#want + 1] = "written by you, Ante " .. tostring(entry.provenance.ante)
            .. ", decision " .. tostring(entry.provenance.decision_serial)
        end
      end
      return want
    end,
  },
  {
    id = "cash in bank",
    states = states("SELECTING_HAND", "SHOP", "BLIND_SELECT", "ROUND_EVAL", "*PACK*"),
    bank = true,
    data = function() return G.GAME and tonumber(G.GAME.dollars) ~= nil end,
  },
  {
    id = "draw pile size",
    states = states("SELECTING_HAND"),
    header = "draw pile",
    data = function() return G.deck and G.deck.cards and #G.deck.cards > 0 end,
    values = function() return { tostring(#G.deck.cards) } end,
  },
  {
    id = "shop stock",
    states = states("SHOP"),
    header = "Shop items",
    data = function() return G.shop_jokers and G.shop_jokers.cards and #G.shop_jokers.cards > 0 end,
    values = function() return names_of(G.shop_jokers) end,
  },
  {
    id = "shop legality",
    states = states("SHOP"),
    header = "Legality",
    data = function() return true end,
    values = function()
      local Economy = require("facts.economy_facts")
      local Actions = require("core.actions")
      local rf = Economy.reroll_facts()
      local _, can_buy = Economy.cheapest_buyable(Economy.spendable())
      local function yn(b) return b and "yes" or "no" end
      return {
        "can buy something: " .. yn(can_buy),
        "can reroll: " .. yn(rf.can_reroll),
        "can sell: " .. yn(Actions.is_action_valid("sell_card")),
        "can use a consumable: " .. yn(Actions.is_action_valid("use_consumable")
          or Actions.is_action_valid("use_directional_consumable")),
      }
    end,
  },
  {
    id = "boss rule in play",
    states = states("SELECTING_HAND"),
    data = function()
      local line = require("context.ctx_blind").blind_debuff_line()
      return type(line) == "string" and #line > 40
    end,
    values = function()
      return { require("context.ctx_blind").blind_debuff_line():sub(1, 90) }
    end,
  },
  {
    id = "upcoming boss rule",
    states = states("BLIND_SELECT", "SHOP"),
    data = function() return upcoming_boss_line() ~= nil end,
    values = function()
      local line = upcoming_boss_line()
      local name, body = line:match("^Boss %((.-)%): (.+)$")
      return { name or "Boss", (body or line):sub(1, 90) }
    end,
  },
  {
    id = "hand levels",
    states = states("SELECTING_HAND", "SHOP", "BLIND_SELECT", "*PACK*"),
    header = "Hand levels",
    data = function() return G.GAME and G.GAME.hands and next(G.GAME.hands) ~= nil end,
    values = function()
      local want = {}
      for name, h in pairs(G.GAME.hands) do
        if (tonumber(h.level) or 1) > 1 then
          want[#want + 1] = name
          want[#want + 1] = "level " .. tostring(h.level)
        end
      end
      return want
    end,
  },
  {
    id = "owned consumables",
    states = states("SHOP", "BLIND_SELECT", "*PACK*"),
    header = "Consumables (",
    data = function() return G.consumeables and G.consumeables.cards and #G.consumeables.cards > 0 end,
    values = function() return names_of(G.consumeables) end,
  },
  {
    id = "owned vouchers",
    states = states("SELECTING_HAND", "SHOP", "BLIND_SELECT", "*PACK*"),
    header = "Vouchers you own",
    data = function() return G.GAME and G.GAME.used_vouchers and next(G.GAME.used_vouchers) ~= nil end,
    values = function()
      local want = {}
      for key in pairs(G.GAME.used_vouchers) do want[#want + 1] = (key:gsub("^v_", "")) end
      return want
    end,
  },
  {
    id = "the hand",
    states = states("SELECTING_HAND"),
    header = "Your hand",
    data = function() return G.hand and G.hand.cards and #G.hand.cards > 0 end,
    values = function() return { tostring(#G.hand.cards) .. ")" } end,
  },
  {
    id = "current run economy rules",
    states = states("SELECTING_HAND", "SHOP", "BLIND_SELECT", "ROUND_EVAL", "*PACK*"),
    header = "At round end each unused hand pays",
    data = function() return true end,
    values = function()
      local E = require("facts.economy_facts")
      return { "+$" .. tostring(E.interest_amount()) .. " interest per $5 held",
        "max +$" .. tostring(E.max_interest()) .. "/round",
        "only the first $" .. tostring(E.interest_cap()) .. " held count" }
    end,
  },
  {
    id = "run setup summary",
    states = states("MENU", "RUN_SETUP"),
    header = "Run setup:",
    data = function() return G.GAME ~= nil end,
    values = function() return { "stake " .. tostring(G.GAME.stake or 1) } end,
  },
  {
    id = "selectable decks",
    states = states("RUN_SETUP"),
    header = "Decks you can select",
    data = function()
      return G.P_CENTER_POOLS ~= nil and G.P_CENTER_POOLS.Back ~= nil
        and #require("facts.deck_facts").list_selectable_backs() > 0
    end,
    values = function()
      local want = {}
      for _, d in ipairs(require("facts.deck_facts").list_selectable_backs()) do
        want[#want + 1] = d.name
        want[#want + 1] = "key " .. d.key
      end
      return want
    end,
  },
  {
    id = "run result",
    states = states("GAME_OVER"),
    header = "Result:",
    data = function() return G.GAME ~= nil end,
    values = function()
      return { "Final ante " .. tostring(require("facts.game_facts").ante("?")),
        "round " .. tostring(G.GAME.round or "?") }
    end,
  },
  {
    id = "splash notice",
    states = states("SPLASH"),
    header = "splash screen",
    data = function() return true end,
    values = function() return { "no run is in progress" } end,
  },
  {
    id = "pack contents",
    states = states("*PACK*"),
    header = "Cards in the pack",
    data = function()
      local bp = require("facts.card_util").pack_area()
      return bp and bp.cards and #bp.cards > 0
    end,
    values = function()
      local bp = require("facts.card_util").pack_area()
      return { '"area":"booster_pack","index":' .. tostring(#bp.cards) }
    end,
  },
}

local function bank_claims(text)
  local out = {}
  for v in text:gmatch("(%-?%$%d+) in the bank") do out[#out + 1] = v end
  for v in text:gmatch("(%-?%$%d+) in bank") do out[#out + 1] = v end
  return out
end

M.ROWS = ROWS
M.states = states
M.norm = norm
M.has = has
M.has_loose = has_loose
M.bank_claims = bank_claims

M.ALL_BOARDS = {}
for _, list in ipairs({ LB.BOARDS, LB.BLOCKED, LB.OUT_OF_RUN }) do
  for _, b in ipairs(list) do M.ALL_BOARDS[#M.ALL_BOARDS + 1] = b end
end

return M
