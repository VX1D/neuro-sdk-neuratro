require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("stone-identity-corpus")
local TD = require("tests.test_deadlock")
local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local ContextReadable = require("context.context_readable")
local CardArea = require("facts.card_area_util")
local Utils = require("util.utils")

Actions.get_static_actions()

local SENT_RANK, SENT_SUIT = "Zevenrank", "Qlubsuit"
local STONE = { key = "m_stone", set = "Enhanced", name = "Stone Card", effect = "Stone Card",
  config = { bonus = 50 } }

local function stone(card)
  if type(card) ~= "table" or type(card.base) ~= "table" or card.base.value == nil then return end
  card.base = { value = SENT_RANK, suit = SENT_SUIT, id = 7, nominal = 7, suit_nominal = 0.01 }
  card.config = card.config or {}
  card.config.center = STONE
  card.ability = card.ability or {}
  card.ability.effect, card.ability.name, card.ability.set = "Stone Card", "Stone Card", "Enhanced"
  card.ability.bonus = 50
end

local AREAS = { "hand", "pack_cards", "booster_pack", "deck", "discard", "play", "shop_jokers" }
local RESET = { "GAME", "hand", "jokers", "consumeables", "deck", "playing_cards", "shop_jokers",
  "shop_vouchers", "shop_booster", "shop", "pack_cards", "booster_pack", "blind_select_opts",
  "blind_select", "OVERLAY_MENU", "challenge_tab", "CHALLENGES", "STATES", "STATE", "TIMERS",
  "P_CENTER_POOLS", "P_TAGS", "P_BLINDS", "SETTINGS", "discard", "play" }

local function leaks(text)
  return type(text) == "string" and (text:find(SENT_RANK, 1, true) or text:find(SENT_SUIT, 1, true)) ~= nil
end

local scanned, stones, leaked, public_ok, public_seen = 0, 0, {}, true, 0
for i, sc in ipairs(TD.SCENARIOS) do
  if not sc.xfail then
    for _, key in ipairs(RESET) do G[key] = nil end
    G.GAME = { current_round = {} }
    G.NEURO = { dispatcher = Dispatcher, actions = Actions, persona = "neuro", reserved_dollars = 0,
      shop_reroll_count = 0, state_enter_serial = i * 1000 }
    require("core.validate").reset_run_state()
    TD.apply_mock(sc.mock())
    G.STATES = require("tests.engine_cards").states()
    G.STATE = G.STATES[sc.state]
    local seen = {}
    for _, name in ipairs(AREAS) do
      for _, c in ipairs((type(G[name]) == "table" and G[name].cards) or {}) do
        if not seen[c] and type(c) == "table" and type(c.base) == "table" then
          seen[c] = true; stone(c); stones = stones + 1
        end
      end
    end
    for _, c in ipairs(G.playing_cards or {}) do if not seen[c] then seen[c] = true; stone(c) end end
    local texts = {}
    local ok_b, board = pcall(ContextReadable.build, sc.state, Actions.get_valid_actions_for_state(sc.state))
    if ok_b then texts[#texts + 1] = tostring(board) end
    local ok_f, f = pcall(require("force.force_router").get_force_for_state, sc.state)
    if ok_f and type(f) == "table" then
      texts[#texts + 1] = tostring(f.query or "")
      texts[#texts + 1] = tostring(f.state_extra or "")
    end
    for _, name in ipairs({ "hand", "booster_pack", "shop_jokers" }) do
      local area = CardArea.get_area(name)
      for idx, c in ipairs((area and area.cards) or {}) do
        if type(c) == "table" and c.config and c.config.center == STONE then
          texts[#texts + 1] = tostring(Utils.safe_name(c)) .. " " .. tostring(Utils.real_name(c))
          local _, _, _, _, err = CardArea.resolve_target({ area = name, index = idx, name = "Blueprint" },
            { exact_name = true })
          texts[#texts + 1] = tostring(err)
          if not require("facts.card_util").is_hidden(c) then
            public_seen = public_seen + 1
            local _, hit = CardArea.resolve_target({ area = name, index = idx, name = "Stone Card" },
              { exact_name = true })
            if hit ~= c then public_ok = false end
          end
        end
      end
    end
    scanned = scanned + 1
    for _, t in ipairs(texts) do
      if leaks(t) then
        leaked[#leaked + 1] = string.format("%03d %s: %s", i, sc.state,
          (t:match(".-" .. SENT_RANK .. ".-\n") or t:match(".-" .. SENT_SUIT .. ".-\n") or t):sub(-200))
        break
      end
    end
  end
end

check("the corpus turned cards to Stone", scanned >= 100 and stones >= 100, scanned .. "/" .. stones)
check("no channel renders a Stone Card's base rank or suit", #leaked == 0,
  #leaked .. ": " .. table.concat(leaked, " || "):sub(1, 1500))
check("the public name the rows show resolves the Stone Card", public_seen > 0 and public_ok,
  tostring(public_seen))

local s1 = { base = { value = "8", suit = "Clubs" }, config = { center = STONE }, ability = { effect = "Stone Card" } }
check("the playing-card label of a Stone Card is its enhancement's name",
  Utils.playing_card_label(s1) == "Stone Card", Utils.playing_card_label(s1))
local modded = { base = { value = "8", suit = "Clubs" }, ability = {},
  config = { center = { key = "m_custom", set = "Enhanced", name = "Brick Card", replace_base_card = true } } }
check("any enhancement that hides the face is labelled by its own name",
  Utils.playing_card_label(modded) == "Brick Card", Utils.playing_card_label(modded))
G.pack_cards = { cards = {
  { base = { value = "9", suit = "Hearts" }, ability = {}, config = { center = { key = "c_base", set = "Default" } } },
  { base = { value = "3", suit = "Diamonds" }, ability = {}, config = { center = { key = "c_base", set = "Default" } } },
  s1 } }
require("tests.helpers").in_engine_state("SMODS_BOOSTER_OPENED")
local _, _, _, _, err = CardArea.resolve_target({ area = "booster_pack", index = 1, name = "Stone Card" },
  { exact_name = true })
check("the refusal lists names in position order and names the Stone by its public name",
  type(err) == "string" and err:find("9 of Hearts, 3 of Diamonds, Stone Card", 1, true) ~= nil
    and not err:find("8 of Clubs", 1, true), tostring(err))

done()
