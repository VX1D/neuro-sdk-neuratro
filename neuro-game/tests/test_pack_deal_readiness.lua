require("tests.stubs").setup({ love = "timers" })

local H = require("tests.helpers")
local check, done = H.harness("pack_deal_readiness")

local STATES = require("tests.engine_cards").states()
local EngineCards = require("tests.engine_cards")
local Config = require("core.config")
local Guard = require("core.validate")
local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local Window = require("core.window")
local HudState = require("hud.state")

local forces
local function board(kind, draw_hand)
  forces = {}
  H.orch_board({ kind = "club", state = "SMODS_BOOSTER_OPENED", states = STATES, edit = function(g)
    g.GAME.last_tarot_planet, g.GAME.pack_choices = "c_pluto", 1
    g.shop_jokers, g.shop_vouchers, g.shop_booster, g.blind_select = nil, nil, nil, nil
    g.FUNCS.select_blind, g.FUNCS.use_card, g.FUNCS.skip_booster = nil, H.noop, H.noop
  end })
  for i, v in ipairs({ "2", "5", "7", "9", "Jack", "Queen", "King", "Ace" }) do
    G.deck.cards[i] = EngineCards.playing(v, "Hearts", { sort_id = i })
  end
  local pack = { EngineCards.consumable("c_magician"), EngineCards.consumable("c_death"), EngineCards.consumable("c_star") }
  G.pack_cards = { cards = pack, config = { card_limit = #pack } }
  _G.SMODS = _G.SMODS or {}
  SMODS.OPENED_BOOSTER = { ability = { extra = #pack, choose = 1 },
    config = { center = { key = "p_" .. kind:lower() .. "_normal_1", kind = kind, draw_hand = draw_hand } } }
  G.NEURO = H.orch_neuro({
    dispatcher = Dispatcher, actions = Actions, plan = { hand_plan = "x", build_plan = "y" },
    state = "SMODS_BOOSTER_OPENED", register_actions = "true", send_context = "written", send_action_result = "noop",
  })
  function G.NEURO:force_actions(ctx, _query, actions)
    forces[#forces + 1] = { actions = table.concat(actions, ","), state = ctx }
    return true
  end
  Window.reset()
  Guard.reset_run_state()
  HudState.state_changed_at_game = G.TIMERS.REAL
end

local function settle_steps()
  local entry = Config.get("NEURO_ENTRY_CD_SMODS_BOOSTER_OPENED")
  for _, kind in ipairs({ "TAROT_PACK", "SPECTRAL_PACK", "PLANET_PACK", "BUFFOON_PACK" }) do
    entry = math.max(entry, Config.get("NEURO_ENTRY_CD_" .. kind) or 0)
  end
  G.TIMERS.REAL = G.TIMERS.REAL + entry + 1
  Window.step("SMODS_BOOSTER_OPENED")
  G.TIMERS.REAL = G.TIMERS.REAL + Config.get("NEURO_FORCE_DEBOUNCE") + 0.1
  Window.step("SMODS_BOOSTER_OPENED")
end

local function deal()
  while #G.hand.cards < G.hand.config.card_limit and #G.deck.cards > 0 do
    G.hand.cards[#G.hand.cards + 1] = table.remove(G.deck.cards)
  end
end

for _, kind in ipairs({ "Arcana", "Spectral" }) do
  board(kind, true)
  settle_steps()
  check(kind .. " pack before the game's deal arms no force", #forces == 0,
    #forces > 0 and forces[1].actions or "none")
  check("and opens no window", Window.current() == nil)
  deal()
  settle_steps()
  check(kind .. " pack after the deal arms exactly one force", #forces == 1, #forces)
  local state = forces[1] and forces[1].state or ""
  check("that force carries the dealt hand", state:find("## Your hand", 1, true) ~= nil, state:sub(1, 400))
end

do
  board("Arcana", true)
  deal()
  table.remove(G.pack_cards.cards)
  G.hand.cards = {}
  settle_steps()
  check("a pack already picked from is not held for a deal that already happened", #forces == 1, #forces)
end

for _, kind in ipairs({ "Celestial", "Buffoon" }) do
  board(kind, nil)
  settle_steps()
  check(kind .. " pack (no hand) is forced without waiting for a deal", #forces == 1, #forces)
end

done()
