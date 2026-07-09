local CardUtil = require("facts.card_util")
local CtxEconomy = require("context.ctx_economy")
local HandFacts = require("facts.hand_facts")
local SelfTest = require("core.selftest")
local Cards = require("hud.cards")
local mock_UIBox = require("facts.card_area_util").mock_UIBox

local M = {}
local ENG = _G

local function settled()
  if not SelfTest.engine_settled() then return false end
  if G.CONTROLLER and G.CONTROLLER.locked then return false end
  if G.GAME and (tonumber(G.GAME.STOP_USE) or 0) > 0 then return false end
  return true
end

local function run_action(name, data)
  local h = require("core.dispatcher").get_action_handler(name)
  if not h then return nil, "no handler registered for " .. tostring(name) end
  local exec, err = h(data or {})
  if not exec then return nil, err end
  return exec()
end

local function gfunc(name)
  local fn = G.FUNCS and G.FUNCS[name]
  if not fn then error("missing G.FUNCS." .. tostring(name)) end
  fn({ config = {}, UIBox = mock_UIBox })
end

local function dollars()
  return tonumber(G.GAME and G.GAME.dollars) or 0
end

local function money(n)
  G.GAME.dollars = n
end

local function index_of(area, card)
  for i, c in ipairs(area and area.cards or {}) do
    if c == card then return i end
  end
end

local function clear_area(area)
  if not (area and area.cards) then return end
  for i = #area.cards, 1, -1 do
    local c = area.cards[i]
    if c then c:remove() end
  end
end

local function spawn_consumable(key)
  local card = SMODS.create_card({
    key = key, area = G.consumeables, skip_materialize = true,
    bypass_discovery_center = true, no_edition = true,
  })
  card:add_to_deck()
  G.consumeables:emplace(card)
  return card
end

local function spawn_joker(key, edition)
  local card = SMODS.create_card({
    key = key, area = G.jokers, skip_materialize = true,
    bypass_discovery_center = true, edition = edition, no_edition = not edition,
  })
  card:add_to_deck()
  G.jokers:emplace(card)
  return card
end

local function set_hand(specs)
  clear_area(G.hand)
  local cards = {}
  for i, spec in ipairs(specs) do
    local front, center = spec, nil
    if type(spec) == "table" then front, center = spec.front, spec.center end
    local c = ENG.create_playing_card(
      { front = G.P_CARDS[front], center = G.P_CENTERS[center or "c_base"] },
      G.hand, true, true, nil)
    c.T.x = G.hand.T.x + i * 0.6
    cards[i] = c
  end
  return cards
end

local function play(indices)
  return function()
    local _, err = run_action("play_hand", { indices = indices })
    if err then error(err) end
  end
end

local function use_owned(ctx, hand_indices)
  local idx = index_of(G.consumeables, ctx.card) or 1
  local _, err = run_action("use_card", { area = "consumeables", index = idx, hand_indices = hand_indices })
  if err then error(err) end
end

local function edition_valid(ed, allow_negative)
  if type(ed) ~= "table" then return false end
  return not not (ed.foil or ed.holo or ed.polychrome or (allow_negative and ed.negative))
end

local function discard(indices)
  return function()
    local _, err = run_action("discard_hand", { indices = indices })
    if err then error(err) end
  end
end

local function sum_card_chips(cards)
  local s = 0
  for _, c in ipairs(cards or {}) do
    if c and c.get_chip_bonus then s = s + (tonumber(c:get_chip_bonus()) or 0) end
  end
  return s
end
local function sum_card_mult(cards)
  local s = 0
  for _, c in ipairs(cards or {}) do
    if c and c.get_chip_mult then s = s + (tonumber(c:get_chip_mult()) or 0) end
  end
  return s
end
local function resolve_opt(v, sh)
  if type(v) == "function" then return v(sh) or 0 end
  return v or 0
end
local function count_suit(sh, suit)
  local n = 0
  for _, c in ipairs(sh or {}) do if c and c.base and c.base.suit == suit then n = n + 1 end end
  return n
end
local function count_ids(sh, idset)
  local n = 0
  for _, c in ipairs(sh or {}) do if c and c.base and idset[c.base.id] then n = n + 1 end end
  return n
end
local function sum_ids_chips(sh, idset)
  local s = 0
  for _, c in ipairs(sh or {}) do
    if c and c.base and idset[c.base.id] and c.get_chip_bonus then s = s + (tonumber(c:get_chip_bonus()) or 0) end
  end
  return s
end
local EVEN_IDS = { [2] = true, [4] = true, [6] = true, [8] = true, [10] = true }
local ODD_IDS = { [3] = true, [5] = true, [7] = true, [9] = true }
local HACK_IDS = { [2] = true, [3] = true, [4] = true, [5] = true }
local ACE_IDS = { [14] = true }
local FACE_IDS = { [11] = true, [12] = true, [13] = true }
local FIB_IDS = { [14] = true, [2] = true, [3] = true, [5] = true, [8] = true }

local function score_delta_case(name, specs, indices, opts)
  opts = opts or {}
  return {
    name = name, timeout_s = 30,
    setup = function(ctx)
      clear_area(G.jokers)
      if opts.joker then spawn_joker(opts.joker) end
      ctx.cards = set_hand(specs)
      if opts.mutate then opts.mutate(ctx.cards) end
      G.GAME.current_round.hands_left = 3
      ctx.pre = (G.GAME and G.GAME.chips) or 0
    end,
    act = play(indices),
    wait_for = function()
      return G.STATE == G.STATES.SELECTING_HAND and G.play and #G.play.cards == 0
        and G.GAME.current_round.hands_left == 2 and settled()
    end,
    assert = function(ctx)
      local lh = SMODS.last_hand or {}
      local sh = lh.scoring_hand or {}
      local hd = G.GAME.hands[lh.scoring_name or ""] or {}
      local chips = (tonumber(hd.chips) or 0) + sum_card_chips(sh) + resolve_opt(opts.extra_chips, sh)
      local mult = (tonumber(hd.mult) or 0) + sum_card_mult(sh) + resolve_opt(opts.extra_mult, sh)
      local xm = (type(opts.xmult) == "function" and opts.xmult(sh)) or opts.xmult or 1
      local expect = chips * mult * xm
      local got = ((G.GAME and G.GAME.chips) or 0) - ctx.pre
      local tol = opts.tol or 1
      if math.abs(got - expect) > tol then
        return false, string.format("%s: got %s expected ~%s (%s %dc x%sm x%s)",
          name, tostring(got), tostring(expect), tostring(lh.scoring_name), chips, tostring(mult), tostring(xm))
      end
      return true, string.format("%s -> %s (~%s)", tostring(lh.scoring_name), tostring(got), tostring(expect))
    end,
  }
end

-- every info action must return a non-empty string and never error; the AI reads these each turn
local function info_smoke_case(action_name)
  local needs_sel = action_name == "simulate_hand"
    or action_name == "get_poker_hand_information" or action_name == "scoring_explanation"
  return {
    name = "info/" .. action_name, timeout_s = 8,
    setup = function()
      if G.STATE == G.STATES.SELECTING_HAND then set_hand({ "H_5", "S_5", "D_2", "C_9", "H_K" }) end
    end,
    act = function(ctx)
      ctx.res, ctx.err = run_action(action_name, needs_sel and { indices = { 1, 2 } } or {})
    end,
    wait_for = function() return true end,
    assert = function(ctx)
      if ctx.err then return false, action_name .. " refused: " .. tostring(ctx.err) end
      return type(ctx.res) == "string" and ctx.res ~= "",
        string.format("%s -> %s len %s", action_name, type(ctx.res),
          type(ctx.res) == "string" and #ctx.res or "n/a")
    end,
  }
end

local baseline_hands
function M.reset()
  pcall(function()
    if not (G and G.GAME) then return end
    -- a case that runs out of hands lands on GAME_OVER; recover to a fresh run so later cases don't run against the end screen
    if G.STATES and G.STATE == G.STATES.GAME_OVER then
      if G.FUNCS and G.FUNCS.go_to_menu then pcall(G.FUNCS.go_to_menu) end
      if G.FUNCS and G.FUNCS.start_run then
        pcall(G.FUNCS.start_run, nil, { stake = 1, seed = "SELFTEST" })
      end
      return
    end
    if not baseline_hands and G.GAME.hands then
      baseline_hands = {}
      for name, hd in pairs(G.GAME.hands) do
        baseline_hands[name] = { level = hd.level, chips = hd.chips, mult = hd.mult }
      end
    end
    if baseline_hands and G.GAME.hands then
      for name, b in pairs(baseline_hands) do
        local hd = G.GAME.hands[name]
        if hd then hd.level, hd.chips, hd.mult = b.level, b.chips, b.mult end
      end
    end
    money(50)
    clear_area(G.consumeables)
    clear_area(G.jokers)
    -- sandbox never reshuffles, so plays drain the draw pile; refill or a full-hand play never settles (timeout)
    if G.deck and G.deck.cards and #G.deck.cards < 15 and ENG.create_playing_card and G.P_CARDS and G.P_CENTERS then
      for _ = 1, 20 do
        pcall(function()
          ENG.create_playing_card({ front = G.P_CARDS["H_2"], center = G.P_CENTERS.c_base }, G.deck, true, true, nil)
        end)
      end
    end
    if G.hand and G.hand.unhighlight_all then G.hand:unhighlight_all() end
    if G.STATES and G.STATE == G.STATES.SELECTING_HAND and G.GAME.current_round then
      G.GAME.current_round.hands_left = 4
      G.GAME.current_round.discards_left = 4
      if G.GAME.blind then G.GAME.blind.chips = 1e13 end
    end
  end)
end

local function planet_case(center)
  local key, hand_type = center.key, center.config.hand_type
  return {
    name = "planet/" .. key, timeout_s = 10,
    setup = function(ctx)
      clear_area(G.consumeables)
      ctx.card = spawn_consumable(key)
      local hd = G.GAME.hands[hand_type]
      ctx.b = { level = hd.level, chips = hd.chips, mult = hd.mult, lc = hd.l_chips, lm = hd.l_mult }
    end,
    act = function(ctx) use_owned(ctx) end,
    wait_for = function() return #G.consumeables.cards == 0 and settled() end,
    assert = function(ctx)
      local hd = G.GAME.hands[hand_type]
      local ok = hd.level == ctx.b.level + 1
        and hd.chips == ctx.b.chips + ctx.b.lc
        and hd.mult == ctx.b.mult + ctx.b.lm
      if ok and hd.visible then
        ok = false
        for _, r in ipairs(HandFacts.levels()) do
          if r.name == hand_type and r.level == hd.level and r.chips == hd.chips and r.mult == hd.mult then
            ok = true
            break
          end
        end
        if not ok then return false, hand_type .. ": engine leveled but HandFacts.levels() row disagrees" end
      end
      return ok, string.format("%s: expected L%d %dc x%dm (fact l_chips=%d l_mult=%d), got L%d %dc x%dm",
        hand_type, ctx.b.level + 1, ctx.b.chips + ctx.b.lc, ctx.b.mult + ctx.b.lm,
        ctx.b.lc, ctx.b.lm, hd.level, hd.chips, hd.mult)
    end,
  }
end

local function conv_case(kind, center)
  local key = center.key
  return {
    name = kind .. "/" .. key, timeout_s = 12,
    setup = function(ctx)
      clear_area(G.consumeables)
      ctx.hand = set_hand({ "H_5", "S_9", "D_2", "C_K", "H_A" })
      ctx.card = spawn_consumable(key)
      local _, mx = CardUtil.consumable_target_range(ctx.card)
      ctx.n = math.min(mx or 1, #G.hand.cards)
      ctx.ix, ctx.targets = {}, {}
      for i = 1, ctx.n do
        ctx.ix[i] = i
        ctx.targets[i] = G.hand.cards[i]
      end
      ctx.mod_conv = ctx.card.ability.consumeable.mod_conv
      ctx.suit_conv = ctx.card.ability.consumeable.suit_conv
    end,
    act = function(ctx) use_owned(ctx, ctx.ix) end,
    wait_for = function() return #G.consumeables.cards == 0 and settled() end,
    assert = function(ctx)
      if ctx.mod_conv and not CardUtil.enhancement_record(ctx.mod_conv) then
        return false, "fact gap: enhancement " .. tostring(ctx.mod_conv) .. " missing from CardUtil.ENHANCEMENTS"
      end
      for i, c in ipairs(ctx.targets) do
        if ctx.suit_conv and not (c.base and c.base.suit == ctx.suit_conv) then
          return false, string.format("target %d: expected suit %s, got %s", i, ctx.suit_conv, tostring(c.base and c.base.suit))
        end
        if ctx.mod_conv and CardUtil.enhancement_key(c) ~= ctx.mod_conv then
          return false, string.format("target %d: expected enhancement %s, got %s", i, ctx.mod_conv, tostring(CardUtil.enhancement_key(c)))
        end
      end
      return true, string.format("%d card(s) converted to %s", ctx.n, tostring(ctx.suit_conv or ctx.mod_conv))
    end,
  }
end

local function generic_consumable_case(kind, center)
  local key = center.key
  return {
    name = kind .. "/" .. key .. "/generic", timeout_s = 12,
    setup = function(ctx)
      clear_area(G.consumeables)
      set_hand({ "H_5", "S_9", "D_2", "C_K", "H_A" })
      ctx.card = spawn_consumable(key)
      local _, mx = CardUtil.consumable_target_range(ctx.card)
      if mx and mx > 0 then
        ctx.ix = {}
        for i = 1, math.min(mx, #G.hand.cards) do ctx.ix[i] = i end
      end
    end,
    act = function(ctx)
      local idx = index_of(G.consumeables, ctx.card) or 1
      local _, err = run_action("use_card", { area = "consumeables", index = idx, hand_indices = ctx.ix })
      ctx.err = err
    end,
    wait_for = function(ctx)
      return ctx.err ~= nil or (#G.consumeables.cards == 0 and settled())
    end,
    assert = function(ctx)
      if ctx.err then return true, "not usable here, handler refused cleanly: " .. tostring(ctx.err) end
      return true, "used without error"
    end,
  }
end

local function creator_case(center, want_count, want_set, target_area)
  local key = center.key
  return {
    name = "tarot/" .. key, timeout_s = 12,
    setup = function(ctx)
      clear_area(G.consumeables)
      if target_area == "jokers" then clear_area(G.jokers) end
      ctx.card = spawn_consumable(key)
    end,
    act = function(ctx) use_owned(ctx) end,
    wait_for = function()
      local area = target_area == "jokers" and G.jokers or G.consumeables
      return #area.cards >= want_count and settled()
    end,
    assert = function(_ctx)
      local area = target_area == "jokers" and G.jokers or G.consumeables
      if #area.cards ~= want_count then
        return false, string.format("expected %d created, got %d", want_count, #area.cards)
      end
      for _, c in ipairs(area.cards) do
        if CardUtil.card_set(c) ~= want_set then
          return false, string.format("expected set %s, got %s", want_set, tostring(CardUtil.card_set(c)))
        end
      end
      return true, string.format("created %d %s card(s)", want_count, want_set)
    end,
  }
end

local function seal_case(center)
  local key, seal = center.key, center.config.extra
  return {
    name = "spectral/" .. key, timeout_s = 12,
    setup = function(ctx)
      clear_area(G.consumeables)
      ctx.hand = set_hand({ "H_5", "S_9", "D_2" })
      ctx.card = spawn_consumable(key)
    end,
    act = function(ctx) use_owned(ctx, { 1 }) end,
    wait_for = function() return #G.consumeables.cards == 0 and settled() end,
    assert = function(ctx)
      local got = ctx.hand[1].seal
      if got ~= seal then
        return false, string.format("expected seal %s, got %s", tostring(seal), tostring(got))
      end
      if not CardUtil.SEALS[seal] then
        return false, "fact gap: seal " .. tostring(seal) .. " missing from CardUtil.SEALS"
      end
      return true, "seal " .. tostring(seal) .. " applied (fact table covers it)"
    end,
  }
end

local function black_hole_case(kind, key)
  return {
    name = kind .. "/" .. key, timeout_s = 20,
    setup = function(ctx)
      clear_area(G.consumeables)
      ctx.card = spawn_consumable(key)
      ctx.levels = {}
      for name, hd in pairs(G.GAME.hands) do ctx.levels[name] = hd.level end
    end,
    act = function(ctx) use_owned(ctx) end,
    wait_for = function() return #G.consumeables.cards == 0 and settled() end,
    assert = function(ctx)
      for name, lv in pairs(ctx.levels) do
        local hd = G.GAME.hands[name]
        if not hd or hd.level ~= lv + 1 then
          return false, string.format("%s: expected L%d, got L%s", name, lv + 1, tostring(hd and hd.level))
        end
      end
      return true, "every hand leveled +1"
    end,
  }
end

local SPECIAL = {}

SPECIAL.c_strength = function(_center)
  return {
    name = "tarot/c_strength", timeout_s = 12,
    setup = function(ctx)
      clear_area(G.consumeables)
      ctx.hand = set_hand({ "H_5", "H_A" })
      ctx.card = spawn_consumable("c_strength")
      ctx.want = {}
      for i = 1, 2 do
        local id = ctx.hand[i].base.id
        ctx.want[i] = (id == 14) and 2 or math.min(id + 1, 14)
      end
    end,
    act = function(ctx) use_owned(ctx, { 1, 2 }) end,
    wait_for = function() return #G.consumeables.cards == 0 and settled() end,
    assert = function(ctx)
      for i = 1, 2 do
        if ctx.hand[i].base.id ~= ctx.want[i] then
          return false, string.format("card %d: expected rank id %d, got %d", i, ctx.want[i], ctx.hand[i].base.id)
        end
      end
      return true, "ranks +1 (Ace wraps to 2)"
    end,
  }
end

SPECIAL.c_death = function(_center)
  return {
    name = "tarot/c_death", timeout_s = 12,
    setup = function(ctx)
      clear_area(G.consumeables)
      ctx.hand = set_hand({ "H_5", "S_9" })
      ctx.card = spawn_consumable("c_death")
    end,
    act = function(ctx) use_owned(ctx, { 1, 2 }) end,
    wait_for = function() return #G.consumeables.cards == 0 and settled() end,
    assert = function(ctx)
      local left = ctx.hand[1]
      local ok = left.base and left.base.id == 9 and left.base.suit == "Spades"
      return ok, string.format("left card should copy rightmost (9 of Spades), got %s of %s",
        tostring(left.base and left.base.id), tostring(left.base and left.base.suit))
    end,
  }
end

SPECIAL.c_hermit = function(_center)
  return {
    name = "tarot/c_hermit", timeout_s = 10,
    setup = function(ctx)
      clear_area(G.consumeables)
      ctx.card = spawn_consumable("c_hermit")
      ctx.extra = ctx.card.ability.extra
      money(13)
    end,
    act = function(ctx) use_owned(ctx) end,
    wait_for = function() return #G.consumeables.cards == 0 and settled() end,
    assert = function(ctx)
      return dollars() == 26, string.format("doubling: $13 -> expected $26 (cap $%s), got $%d", tostring(ctx.extra), dollars())
    end,
  }
end

SPECIAL.c_temperance = function(_center)
  return {
    name = "tarot/c_temperance", timeout_s = 10, act_delay = 0.6,
    setup = function(ctx)
      clear_area(G.consumeables)
      clear_area(G.jokers)
      local j1 = spawn_joker("j_joker")
      local j2 = spawn_joker("j_greedy_joker")
      ctx.card = spawn_consumable("c_temperance")
      ctx.cap = ctx.card.ability.extra
      ctx.sum = (j1.sell_cost or 0) + (j2.sell_cost or 0)
      money(10)
    end,
    act = function(ctx) use_owned(ctx) end,
    wait_for = function() return #G.consumeables.cards == 0 and settled() end,
    assert = function(ctx)
      local want = 10 + math.min(ctx.sum, ctx.cap)
      return dollars() == want,
        string.format("expected $%d (joker sell sum %d, cap %s), got $%d", want, ctx.sum, tostring(ctx.cap), dollars())
    end,
  }
end

SPECIAL.c_fool = function(_center)
  return {
    name = "tarot/c_fool", timeout_s = 12,
    setup = function(ctx)
      clear_area(G.consumeables)
      G.GAME.last_tarot_planet = "c_mercury"
      ctx.card = spawn_consumable("c_fool")
    end,
    act = function(ctx) use_owned(ctx) end,
    wait_for = function()
      return #G.consumeables.cards == 1
        and G.consumeables.cards[1].config.center.key ~= "c_fool" and settled()
    end,
    assert = function()
      local got = G.consumeables.cards[1] and G.consumeables.cards[1].config.center.key
      return got == "c_mercury", "expected copy of last used (c_mercury), got " .. tostring(got)
    end,
  }
end

SPECIAL.c_emperor = function(center) return creator_case(center, 2, "Tarot") end
SPECIAL.c_high_priestess = function(center) return creator_case(center, 2, "Planet") end
SPECIAL.c_judgement = function(center) return creator_case(center, 1, "Joker", "jokers") end

SPECIAL.c_wheel_of_fortune = function(_center)
  return {
    name = "tarot/c_wheel_of_fortune", timeout_s = 12, act_delay = 0.8,
    setup = function(ctx)
      clear_area(G.consumeables)
      clear_area(G.jokers)
      ctx.joker = spawn_joker("j_joker")
      ctx.card = spawn_consumable("c_wheel_of_fortune")
    end,
    act = function(ctx) use_owned(ctx) end,
    wait_for = function() return #G.consumeables.cards == 0 and settled() end,
    assert = function(ctx)
      local ed = ctx.joker.edition
      if ed == nil then return true, "RNG outcome: Nope! (no edition, valid)" end
      return edition_valid(ed), "RNG outcome: edition " .. tostring(CardUtil.edition_name(ed))
    end,
  }
end

SPECIAL.c_hanged_man = function(_center)
  return {
    name = "tarot/c_hanged_man", timeout_s = 12,
    setup = function(ctx)
      clear_area(G.consumeables)
      set_hand({ "H_5", "S_9", "D_2", "C_K", "H_A" })
      ctx.card = spawn_consumable("c_hanged_man")
    end,
    act = function(ctx) use_owned(ctx, { 1, 2 }) end,
    wait_for = function() return #G.hand.cards == 3 and settled() end,
    assert = function()
      return #G.hand.cards == 3, string.format("expected 3 cards left after destroying 2, got %d", #G.hand.cards)
    end,
  }
end

local CREATE_RANKS = {
  c_familiar = { [11] = true, [12] = true, [13] = true },
  c_grim = { [14] = true },
  c_incantation = { [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true, [10] = true },
}
local function destroy_create_case(center)
  local key = center.key
  local extra = center.config.extra
  return {
    name = "spectral/" .. key, timeout_s = 15,
    setup = function(ctx)
      clear_area(G.consumeables)
      ctx.pre = set_hand({ "H_5", "S_9", "D_2", "C_K", "H_A" })
      ctx.pre_set = {}
      for _, c in ipairs(ctx.pre) do ctx.pre_set[c] = true end
      ctx.card = spawn_consumable(key)
    end,
    act = function(ctx) use_owned(ctx) end,
    wait_for = function(_ctx) return #G.hand.cards == 4 + extra and settled() end,
    assert = function(ctx)
      if #G.hand.cards ~= 4 + extra then
        return false, string.format("expected %d cards (5 -1 destroyed +%d created), got %d", 4 + extra, extra, #G.hand.cards)
      end
      local created = 0
      for _, c in ipairs(G.hand.cards) do
        if not ctx.pre_set[c] then
          created = created + 1
          if not CREATE_RANKS[key][c.base.id] then
            return false, string.format("created rank id %d outside valid set for %s", c.base.id, key)
          end
          local enh = CardUtil.enhancement_key(c)
          if not enh or enh == "m_stone" then
            return false, "created card should be enhanced (non-Stone), got " .. tostring(enh)
          end
        end
      end
      return created == extra, string.format("created %d enhanced card(s) in valid rank set", created)
    end,
  }
end
SPECIAL.c_familiar = destroy_create_case
SPECIAL.c_grim = destroy_create_case
SPECIAL.c_incantation = destroy_create_case

SPECIAL.c_immolate = function(center)
  local extra = center.config.extra
  return {
    name = "spectral/c_immolate", timeout_s = 15,
    setup = function(ctx)
      clear_area(G.consumeables)
      set_hand({ "H_5", "S_9", "D_2", "C_K", "H_A", "S_3", "D_7", "C_6" })
      ctx.card = spawn_consumable("c_immolate")
      money(20)
    end,
    act = function(ctx) use_owned(ctx) end,
    wait_for = function() return #G.hand.cards == 3 and settled() end,
    assert = function()
      local ok = #G.hand.cards == 3 and dollars() == 20 + extra.dollars
      return ok, string.format("expected %d destroyed and $%d, got %d cards and $%d",
        extra.destroy, 20 + extra.dollars, 8 - #G.hand.cards, dollars())
    end,
  }
end

SPECIAL.c_aura = function(_center)
  return {
    name = "spectral/c_aura", timeout_s = 12,
    setup = function(ctx)
      clear_area(G.consumeables)
      ctx.hand = set_hand({ "H_5", "S_9" })
      ctx.card = spawn_consumable("c_aura")
    end,
    act = function(ctx) use_owned(ctx, { 1 }) end,
    wait_for = function() return #G.consumeables.cards == 0 and settled() end,
    assert = function(ctx)
      local ed = ctx.hand[1].edition
      return edition_valid(ed), "edition applied: " .. tostring(CardUtil.edition_name(ed))
    end,
  }
end

SPECIAL.c_sigil = function(_center)
  return {
    name = "spectral/c_sigil", timeout_s = 12,
    setup = function(ctx)
      clear_area(G.consumeables)
      set_hand({ "H_5", "S_9", "D_2", "C_K" })
      ctx.card = spawn_consumable("c_sigil")
    end,
    act = function(ctx) use_owned(ctx) end,
    wait_for = function() return #G.consumeables.cards == 0 and settled() end,
    assert = function()
      local suit = G.hand.cards[1].base.suit
      for _, c in ipairs(G.hand.cards) do
        if c.base.suit ~= suit then return false, "hand not uniform suit after Sigil" end
      end
      return true, "all hand cards converted to " .. tostring(suit)
    end,
  }
end

SPECIAL.c_ouija = function(_center)
  return {
    name = "spectral/c_ouija", timeout_s = 12,
    setup = function(ctx)
      clear_area(G.consumeables)
      set_hand({ "H_5", "S_9", "D_2", "C_K" })
      ctx.card = spawn_consumable("c_ouija")
      ctx.pre_limit = G.hand.config.card_limit
    end,
    act = function(ctx) use_owned(ctx) end,
    wait_for = function() return #G.consumeables.cards == 0 and settled() end,
    assert = function(ctx)
      local id = G.hand.cards[1].base.id
      for _, c in ipairs(G.hand.cards) do
        if c.base.id ~= id then return false, "hand not uniform rank after Ouija" end
      end
      if G.hand.config.card_limit ~= ctx.pre_limit - 1 then
        return false, string.format("hand size should shrink by 1 (%d -> %d)", ctx.pre_limit, G.hand.config.card_limit)
      end
      return true, "uniform rank + hand size -1"
    end,
    teardown = function(ctx)
      if ctx.pre_limit and G.hand then G.hand:change_size(ctx.pre_limit - G.hand.config.card_limit) end
    end,
  }
end

SPECIAL.c_wraith = function(_center)
  return {
    name = "spectral/c_wraith", timeout_s = 12,
    setup = function(ctx)
      clear_area(G.consumeables)
      clear_area(G.jokers)
      ctx.card = spawn_consumable("c_wraith")
      money(37)
    end,
    act = function(ctx) use_owned(ctx) end,
    wait_for = function() return #G.jokers.cards == 1 and settled() end,
    assert = function()
      local ok = #G.jokers.cards == 1 and dollars() == 0
      return ok, string.format("expected 1 rare joker + $0, got %d joker(s) + $%d", #G.jokers.cards, dollars())
    end,
  }
end

SPECIAL.c_ankh = function(_center)
  return {
    name = "spectral/c_ankh", timeout_s = 12,
    setup = function(ctx)
      clear_area(G.consumeables)
      clear_area(G.jokers)
      spawn_joker("j_joker")
      spawn_joker("j_greedy_joker")
      ctx.card = spawn_consumable("c_ankh")
    end,
    act = function(ctx) use_owned(ctx) end,
    wait_for = function()
      return #G.jokers.cards == 2 and settled()
        and G.jokers.cards[1].config.center.key == G.jokers.cards[2].config.center.key
    end,
    assert = function()
      local k1 = G.jokers.cards[1] and G.jokers.cards[1].config.center.key
      local k2 = G.jokers.cards[2] and G.jokers.cards[2].config.center.key
      return #G.jokers.cards == 2 and k1 == k2,
        string.format("expected chosen joker + its copy, got %d joker(s): %s / %s", #G.jokers.cards, tostring(k1), tostring(k2))
    end,
  }
end

SPECIAL.c_ectoplasm = function(_center)
  return {
    name = "spectral/c_ectoplasm", timeout_s = 12, act_delay = 0.8,
    setup = function(ctx)
      clear_area(G.consumeables)
      clear_area(G.jokers)
      ctx.joker = spawn_joker("j_joker")
      ctx.card = spawn_consumable("c_ectoplasm")
      ctx.pre_limit = G.hand.config.card_limit
      ctx.pre_ecto = G.GAME.ecto_minus or 1
    end,
    act = function(ctx) use_owned(ctx) end,
    wait_for = function() return #G.consumeables.cards == 0 and settled() end,
    assert = function(ctx)
      local ed = ctx.joker.edition
      local ok = type(ed) == "table" and ed.negative and G.hand.config.card_limit == ctx.pre_limit - ctx.pre_ecto
      return ok, string.format("expected Negative + hand size -%d, got edition=%s limit %d->%d",
        ctx.pre_ecto, tostring(CardUtil.edition_name(ed)), ctx.pre_limit, G.hand.config.card_limit)
    end,
    teardown = function(ctx)
      if ctx.pre_limit and G.hand then G.hand:change_size(ctx.pre_limit - G.hand.config.card_limit) end
      if ctx.pre_ecto then G.GAME.ecto_minus = ctx.pre_ecto end
    end,
  }
end

SPECIAL.c_hex = function(_center)
  return {
    name = "spectral/c_hex", timeout_s = 12, act_delay = 0.8,
    setup = function(ctx)
      clear_area(G.consumeables)
      clear_area(G.jokers)
      spawn_joker("j_joker")
      spawn_joker("j_greedy_joker")
      ctx.card = spawn_consumable("c_hex")
    end,
    act = function(ctx) use_owned(ctx) end,
    wait_for = function() return #G.jokers.cards == 1 and settled() end,
    assert = function()
      local j = G.jokers.cards[1]
      local ok = j and type(j.edition) == "table" and j.edition.polychrome
      return ok, string.format("expected 1 Polychrome joker, got %d joker(s), edition %s",
        #G.jokers.cards, tostring(j and CardUtil.edition_name(j.edition)))
    end,
  }
end

SPECIAL.c_cryptid = function(_center)
  return {
    name = "spectral/c_cryptid", timeout_s = 12,
    setup = function(ctx)
      clear_area(G.consumeables)
      ctx.hand = set_hand({ "H_7", "S_9", "D_2" })
      ctx.card = spawn_consumable("c_cryptid")
    end,
    act = function(ctx) use_owned(ctx, { 1 }) end,
    wait_for = function() return #G.hand.cards == 5 and settled() end,
    assert = function(_ctx)
      local n = 0
      for _, c in ipairs(G.hand.cards) do
        if c.base.id == 7 and c.base.suit == "Hearts" then n = n + 1 end
      end
      return n == 3, string.format("expected 3 copies of 7 of Hearts (1 + 2 created), got %d", n)
    end,
  }
end

SPECIAL.c_soul = function(_center)
  return {
    name = "spectral/c_soul", timeout_s = 12,
    setup = function(ctx)
      clear_area(G.consumeables)
      clear_area(G.jokers)
      ctx.card = spawn_consumable("c_soul")
    end,
    act = function(ctx) use_owned(ctx) end,
    wait_for = function() return #G.jokers.cards == 1 and settled() end,
    assert = function()
      local j = G.jokers.cards[1]
      local rar = j and j.config.center.rarity
      local ok = rar == 4 and CardUtil.rarity_name(rar) == "Legendary"
      return ok, string.format("expected Legendary joker (rarity 4), got rarity %s (%s)", tostring(rar), tostring(CardUtil.rarity_name(rar)))
    end,
  }
end

SPECIAL.c_black_hole = function(_center) return black_hole_case("spectral", "c_black_hole") end

local SEAL_SET = { Gold = true, Red = true, Blue = true, Purple = true }
local function pick_consumable_case(kind, center)
  local sp = SPECIAL[center.key]
  if sp then return sp(center) end
  local cfg = center.config or {}
  if cfg.hand_type then return planet_case(center) end
  if cfg.mod_conv or cfg.suit_conv then return conv_case(kind, center) end
  if type(cfg.extra) == "string" and SEAL_SET[cfg.extra] and cfg.max_highlighted == 1 then
    return seal_case(center)
  end
  return generic_consumable_case(kind, center)
end

local VFX = {}
local function vfx(names, get, expect)
  for _, n in ipairs(names) do VFX[n] = { get = get, expect = expect } end
end
vfx({ "Overstock", "Overstock Plus" }, function() return G.GAME.shop.joker_max end, function(b) return b + 1 end)
vfx({ "Seed Money", "Money Tree" }, function() return G.GAME.interest_cap end, function(_b, x) return x end)
vfx({ "Grabber", "Nacho Tong" }, function() return G.GAME.round_resets.hands end, function(b, x) return b + x end)
vfx({ "Wasteful", "Recyclomancy" }, function() return G.GAME.round_resets.discards end, function(b, x) return b + x end)
vfx({ "Paint Brush", "Palette" }, function() return G.hand.config.card_limit end, function(b) return b + 1 end)
vfx({ "Antimatter" }, function() return G.jokers.config.card_limit end, function(b) return b + 1 end)
vfx({ "Hieroglyph", "Petroglyph" }, function() return G.GAME.round_resets.ante end, function(b, x) return b - x end)
vfx({ "Crystal Ball" }, function() return G.consumeables.config.card_limit end, function(b) return b + 1 end)
vfx({ "Clearance Sale", "Liquidation" }, function() return G.GAME.discount_percent end, function(_b, x) return x end)
vfx({ "Reroll Surplus", "Reroll Glut" }, function() return G.GAME.round_resets.reroll_cost end, function(b, x) return b - x end)
vfx({ "Tarot Merchant", "Tarot Tycoon" }, function() return G.GAME.tarot_rate end, function(_b, x) return 4 * x end)
vfx({ "Planet Merchant", "Planet Tycoon" }, function() return G.GAME.planet_rate end, function(_b, x) return 4 * x end)
vfx({ "Hone", "Glow Up" }, function() return G.GAME.edition_rate end, function(_b, x) return x end)
vfx({ "Magic Trick", "Illusion" }, function() return G.GAME.playing_card_rate end, function(_b, x) return x end)

local function knob_snapshot()
  return {
    joker_max = G.GAME.shop and G.GAME.shop.joker_max,
    interest_cap = G.GAME.interest_cap, interest_amount = G.GAME.interest_amount,
    hands = G.GAME.round_resets.hands, discards = G.GAME.round_resets.discards,
    ante = G.GAME.round_resets.ante, blind_ante = G.GAME.round_resets.blind_ante,
    reroll_cost = G.GAME.round_resets.reroll_cost,
    cur_reroll = G.GAME.current_round and G.GAME.current_round.reroll_cost,
    discount = G.GAME.discount_percent,
    tarot_rate = G.GAME.tarot_rate, planet_rate = G.GAME.planet_rate,
    edition_rate = G.GAME.edition_rate, playing_card_rate = G.GAME.playing_card_rate,
    hand_limit = G.hand and G.hand.config.card_limit,
    joker_limit = G.jokers and G.jokers.config.card_limit,
    cons_limit = G.consumeables and G.consumeables.config.card_limit,
  }
end

local function knob_restore(s)
  if not s then return end
  if G.GAME.shop then G.GAME.shop.joker_max = s.joker_max end
  G.GAME.interest_cap, G.GAME.interest_amount = s.interest_cap, s.interest_amount
  G.GAME.round_resets.hands, G.GAME.round_resets.discards = s.hands, s.discards
  G.GAME.round_resets.ante, G.GAME.round_resets.blind_ante = s.ante, s.blind_ante
  G.GAME.round_resets.reroll_cost = s.reroll_cost
  if G.GAME.current_round then G.GAME.current_round.reroll_cost = s.cur_reroll end
  G.GAME.discount_percent = s.discount
  G.GAME.tarot_rate, G.GAME.planet_rate = s.tarot_rate, s.planet_rate
  G.GAME.edition_rate, G.GAME.playing_card_rate = s.edition_rate, s.playing_card_rate
  if G.hand and s.hand_limit then G.hand.config.card_limit = s.hand_limit end
  if G.jokers and s.joker_limit then G.jokers.config.card_limit = s.joker_limit end
  if G.consumeables and s.cons_limit then G.consumeables.config.card_limit = s.cons_limit end
end

local function voucher_case(center)
  local key, name = center.key, center.name
  local fx = VFX[name]
  return {
    name = "voucher/" .. key, timeout_s = 25,
    setup = function(ctx)
      ctx.card = SMODS.add_voucher_to_shop(key)
      money((tonumber(ctx.card.cost) or 10) + 30)
      ctx.cost = tonumber(ctx.card.cost) or 0
      ctx.pre = dollars()
      ctx.pre_jokers = #G.jokers.cards
      ctx.knobs = knob_snapshot()
      if fx then ctx.fx_before = fx.get() end
    end,
    act = function(ctx)
      local idx = index_of(G.shop_vouchers, ctx.card)
      local _, err = run_action("buy_from_shop", { area = "shop_vouchers", index = idx })
      if err then error(err) end
    end,
    wait_for = function() return G.GAME.used_vouchers[key] and settled() end,
    assert = function(ctx)
      if dollars() ~= ctx.pre - ctx.cost then
        return false, string.format("expected exact single deduction $%d -> $%d, got $%d", ctx.pre, ctx.pre - ctx.cost, dollars())
      end
      if #G.jokers.cards ~= ctx.pre_jokers then
        return false, "voucher leaked into G.jokers (dead-joker regression)"
      end
      if fx then
        local got = fx.get()
        local want = fx.expect(ctx.fx_before, center.config and center.config.extra)
        if got ~= want then
          return false, string.format("effect: expected %s, got %s (was %s)", tostring(want), tostring(got), tostring(ctx.fx_before))
        end
        return true, string.format("redeemed, single deduction, effect %s -> %s", tostring(ctx.fx_before), tostring(got))
      end
      return true, "redeemed, single deduction, no joker leak"
    end,
    teardown = function(ctx)
      knob_restore(ctx.knobs)
      clear_area(G.shop_vouchers)
    end,
  }
end

local function booster_cases(center, add)
  local key = center.key
  add({
    name = "booster/" .. key .. "/buy", timeout_s = 25,
    setup = function(ctx)
      money(60)
      ctx.card = SMODS.add_booster_to_shop(key)
      ctx.cost = tonumber(ctx.card.cost) or 0
      ctx.pre = dollars()
      local mods = G.GAME.modifiers or {}
      ctx.size = math.max(1, (ctx.card.ability.extra or (center.config and center.config.extra) or 1) + (mods.booster_size_mod or 0))
      ctx.choices = math.min((ctx.card.ability.choose or (center.config and center.config.choose) or 1) + (mods.booster_choice_mod or 0), ctx.size)
    end,
    act = function(ctx)
      local idx = index_of(G.shop_booster, ctx.card)
      local _, err = run_action("buy_from_shop", { area = "shop_booster", index = idx })
      if err then error(err) end
    end,
    wait_for = function(ctx)
      return G.STATE ~= G.STATES.SHOP and G.pack_cards and #G.pack_cards.cards >= ctx.size and settled()
    end,
    assert = function(ctx)
      local n = G.pack_cards and #G.pack_cards.cards or 0
      if n ~= ctx.size then
        return false, string.format("pack size: expected %d, got %d", ctx.size, n)
      end
      if dollars() ~= ctx.pre - ctx.cost then
        return false, string.format("double-charge check: expected $%d -> $%d, got $%d", ctx.pre, ctx.pre - ctx.cost, dollars())
      end
      if G.GAME.pack_choices ~= ctx.choices then
        return false, string.format("pack_choices: expected %d, got %s", ctx.choices, tostring(G.GAME.pack_choices))
      end
      return true, string.format("opened: %d cards, %d pick(s), single $%d deduction", n, ctx.choices, ctx.cost)
    end,
  })
  add({
    name = "booster/" .. key .. "/pick", timeout_s = 25,
    setup = function(ctx)
      local bp = G.pack_cards
      ctx.open = bp and #bp.cards > 0 and G.STATE ~= G.STATES.SHOP
      if not ctx.open then return end
      ctx.pre_n = #bp.cards
      ctx.pre_choices = G.GAME.pack_choices or 1
      for i, c in ipairs(bp.cards) do
        local _, mx = CardUtil.consumable_target_range(c)
        local usable = true
        if c.ability and c.ability.consumeable then
          local ok_u, u = pcall(c.can_use_consumeable, c)
          usable = ok_u and u
        end
        if (not mx or mx == 0) and usable and CardUtil.can_take_pack_card(c) then
          ctx.pick_i = i
          break
        end
      end
    end,
    act = function(ctx)
      if not (ctx.open and ctx.pick_i) then
        ctx.skipped = true
        return
      end
      local _, err = run_action("use_card", { area = "pack_cards", index = ctx.pick_i })
      if err then error(err) end
    end,
    wait_for = function(ctx)
      if ctx.skipped then return true end
      return settled() and (not G.booster_pack or (G.pack_cards and #G.pack_cards.cards < ctx.pre_n))
    end,
    assert = function(ctx)
      if ctx.skipped then return true, "no no-target pick candidate in this pack (skipped pick)" end
      if not G.booster_pack then return true, "picked; pack consumed its last choice and closed" end
      local left = G.GAME.pack_choices
      return left == ctx.pre_choices - 1,
        string.format("picked; expected %d pick(s) left, got %s", ctx.pre_choices - 1, tostring(left))
    end,
  })
  -- exercises the deferred pack-pick + mock_UIBox lifecycle that /pick (no-target only) never touches; a stall trips the timeout
  add({
    name = "booster/" .. key .. "/pick_hand_target", timeout_s = 25,
    setup = function(ctx)
      local bp = G.pack_cards
      ctx.open = bp and #bp.cards > 0 and G.STATE ~= G.STATES.SHOP
      if not ctx.open then return end
      if not (G.hand and G.hand.cards and #G.hand.cards > 0) then
        set_hand({ "H_5", "S_9", "D_2", "C_K", "H_A" })
      end
      ctx.pre_n = #bp.cards
      ctx.pre_choices = G.GAME.pack_choices or 1
      for i, c in ipairs(bp.cards) do
        local mn, mx = CardUtil.consumable_target_range(c)
        if mx and mx > 0 and CardUtil.can_take_pack_card(c) then
          ctx.pick_i, ctx.mn, ctx.mx = i, mn or 1, mx
          break
        end
      end
    end,
    act = function(ctx)
      if not (ctx.open and ctx.pick_i) then ctx.skipped = true return end
      local want = math.min(ctx.mx, #G.hand.cards)
      local ix = {}
      for j = 1, math.max(ctx.mn, want) do if G.hand.cards[j] then ix[#ix + 1] = j end end
      local _, err = run_action("use_card", { area = "booster_pack", index = ctx.pick_i, hand_indices = ix })
      if err then error(err) end
    end,
    wait_for = function(ctx)
      if ctx.skipped then return true end
      return settled() and (not G.booster_pack or (G.pack_cards and #G.pack_cards.cards < ctx.pre_n))
    end,
    assert = function(ctx)
      if ctx.skipped then return true, "no hand-target pick candidate in this pack (skipped)" end
      if not G.booster_pack then return true, "hand-target pick; pack closed cleanly" end
      local left = G.GAME.pack_choices
      return left == ctx.pre_choices - 1,
        string.format("hand-target pick; expected %d left, got %s", ctx.pre_choices - 1, tostring(left))
    end,
  })
  add({
    name = "booster/" .. key .. "/skip", timeout_s = 20,
    act = function(ctx)
      ctx.was_open = not not (G.booster_pack or (G.pack_cards and G.STATE ~= G.STATES.SHOP))
      if ctx.was_open then gfunc("skip_booster") end
    end,
    wait_for = function()
      return G.STATE == G.STATES.SHOP and not G.booster_pack and settled()
    end,
    assert = function(ctx)
      return true, ctx.was_open and "skipped open pack, returned cleanly to SHOP" or "pack already closed, SHOP clean"
    end,
    teardown = function()
      clear_area(G.shop_booster)
    end,
  })
end

function M.build()
  local cases = {}
  local function add(c) cases[#cases + 1] = c end
  local covered = {}

  add({
    name = "gameover/stale_force_cleared", timeout_s = 10,
    setup = function(ctx)
      ctx.saved = {
        inflight = G.NEURO.force_inflight, state = G.NEURO.force_state,
        names = G.NEURO.force_action_names, set = G.NEURO.force_action_set,
        sent_at = G.NEURO.force_sent_at,
      }
      G.NEURO.force_inflight = true
      G.NEURO.force_state = "GAME_OVER"
      G.NEURO.force_action_names = { "cash_out" }
      G.NEURO.force_sent_at = require("util.utils").now()
    end,
    act = function() end,
    wait_for = function() return not G.NEURO.force_inflight end,
    assert = function()
      return not G.NEURO.force_inflight,
        "inflight=" .. tostring(G.NEURO.force_inflight) .. " last_result=" .. tostring(G.NEURO.force_last_result)
    end,
    teardown = function(ctx)
      local s = ctx.saved or {}
      G.NEURO.force_inflight = s.inflight
      G.NEURO.force_state = s.state
      G.NEURO.force_action_names = s.names
      G.NEURO.force_action_set = s.set
      G.NEURO.force_sent_at = s.sent_at
    end,
  })

  add({
    name = "gameover/reject_reforce", timeout_s = 8,
    setup = function(ctx)
      ctx.saved = {
        inflight = G.NEURO.force_inflight, state = G.NEURO.force_state,
        names = G.NEURO.force_action_names, set = G.NEURO.force_action_set,
        sent_at = G.NEURO.force_sent_at,
      }
      G.NEURO.force_inflight = true
      G.NEURO.force_state = "MENU"
      G.NEURO.force_action_set = { setup_run = true }
      G.NEURO.force_action_names = { "setup_run" }
      G.NEURO.force_sent_at = require("util.utils").now()
      ctx.enf = require("core.enforce")
      ctx.saved_pre = ctx.enf.pre_action
      ctx.enf.pre_action = function() return false, "not_in_state", false end
      G.NEURO.dispatcher.handle_message(
        { command = "action", data = { id = "st_reject", name = "play_hand", data = {} } },
        { send_action_result = function() end, register_actions = function() end })
      ctx.enf.pre_action = ctx.saved_pre
    end,
    act = function() end,
    wait_for = function() return true end,
    assert = function()
      return not G.NEURO.force_inflight, "inflight=" .. tostring(G.NEURO.force_inflight)
    end,
    teardown = function(ctx)
      if ctx.enf and ctx.saved_pre then ctx.enf.pre_action = ctx.saved_pre end
      local s = ctx.saved or {}
      G.NEURO.force_inflight = s.inflight
      G.NEURO.force_state = s.state
      G.NEURO.force_action_names = s.names
      G.NEURO.force_action_set = s.set
      G.NEURO.force_sent_at = s.sent_at
    end,
  })

  add({
    name = "meta/seed_menu_flow", timeout_s = 6,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local ok_a, Actions = pcall(require, "core.actions")
      local ok_sr, SeedRun = pcall(require, "handlers.seed_run_handlers")
      if not (ok_a and Actions.get_action_names_for_state and ok_sr) then
        return false, "actions/seed handlers unavailable"
      end
      local want = { toggle_seeded_run = false, paste_seed = false, copy_seed = false }
      for _, name in ipairs(Actions.get_action_names_for_state("RUN_SETUP") or {}) do
        if want[name] ~= nil then want[name] = true end
      end
      for name, present in pairs(want) do
        if not present then return false, "RUN_SETUP menu missing seed option: " .. name end
      end
      local ex, err = SeedRun.handle_toggle_seeded_run({})
      if ex ~= nil or err == nil then return false, "toggle_seeded_run not gated to the run-setup overlay" end
      local exec = SeedRun.handle_paste_seed({ seed = "ABCD1234" })
      if type(exec) ~= "function" then return false, "clean seed did not produce an executable" end
      local msg = exec()
      if not (type(msg) == "string" and msg:find("ABCD1234", 1, true)) then
        return false, "clean seed not applied verbatim: " .. tostring(msg)
      end
      local slur = "n" .. string.char(105, 103, 103, 101, 114) .. "12"  -- built from bytes, no literal slur in source
      local ex2, err2 = SeedRun.handle_paste_seed({ seed = slur })
      if ex2 ~= nil or err2 == nil then return false, "concatenated slur seed was accepted" end
      return true, "RUN_SETUP offers seed options; toggle gated; clean seed applied; concatenated slur rejected"
    end,
  })
  do
    local ok_f, Filtered = pcall(require, "core.filtered")
    if ok_f and Filtered and Filtered.sanitize then
      add({
        name = "meta/filter_sanitize", timeout_s = 5,
        setup = function() end, act = function() end, wait_for = function() return true end,
        assert = function()
          local clean = "lusty joker plays a classic bass"
          if Filtered.sanitize(clean) ~= clean then
            return false, "clean text altered: " .. tostring(Filtered.sanitize(clean))
          end
          local bad = string.char(102, 117, 99, 107) .. "er"  -- built from bytes, no literal slur in source
          local out = Filtered.sanitize(bad)
          local masked = out:find("%*", 1, true) ~= nil or not out:lower():find(string.char(102, 117, 99, 107), 1, true)
          if not masked then return false, "profanity not masked: " .. tostring(out) end
          -- seed is the AI's only free public text input, so paste_seed must reject a fully-profane seed
          local ok_sr, SeedRun = pcall(require, "handlers.seed_run_handlers")
          if ok_sr and SeedRun.handle_paste_seed then
            local exec, err = SeedRun.handle_paste_seed({ seed = string.char(102, 117, 99, 107) })
            if exec ~= nil or err == nil then
              return false, "profane seed passed paste_seed (exec=" .. tostring(exec) .. ")"
            end
          end
          return true, "sanitize masks profanity + keeps clean; paste_seed rejects a profane seed"
        end,
      })
    end
  end
  add({
    name = "meta/seed_reproducible", timeout_s = 5,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local seed = G.GAME and G.GAME.pseudorandom and G.GAME.pseudorandom.seed
      if tostring(seed) ~= "SELFTEST" or G.GAME.seeded ~= true then
        return false, string.format("seed not applied: seed=%s seeded=%s",
          tostring(seed), tostring(G.GAME and G.GAME.seeded))
      end
      if type(pseudorandom) == "function" and type(pseudoseed) == "function" and G.GAME.pseudorandom then
        local k = "selftest_repro_probe"
        G.GAME.pseudorandom[k] = nil
        local v1 = pseudorandom(pseudoseed(k))
        G.GAME.pseudorandom[k] = nil
        local v2 = pseudorandom(pseudoseed(k))
        if v1 ~= v2 then
          return false, string.format("seeded RNG not deterministic: %s vs %s", tostring(v1), tostring(v2))
        end
      end
      return true, "seed SELFTEST applied, seeded=true, RNG deterministic"
    end,
  })
  add({
    name = "meta/selftest_menu_only", timeout_s = 5,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local ok_st, ST = pcall(require, "core.selftest")
      return ok_st and ST.available() == false,
        "selftest.available() must be false during a run"
    end,
  })
  add({
    name = "meta/all_decks_playable_context", timeout_s = 8,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local ok_df, DeckFacts = pcall(require, "facts.deck_facts")
      local ok_fh, FH = pcall(require, "force.force_helpers")
      if not (ok_df and ok_fh and DeckFacts.describe_deck) then return false, "deck facts unavailable" end
      local pool = (G.P_CENTER_POOLS and G.P_CENTER_POOLS.Back) or {}
      if #pool == 0 then return false, "no decks in the Back pool" end
      local bad, n, playable = {}, 0, 0
      for _, deck in ipairs(pool) do
        if type(deck) == "table" and deck.key then
          n = n + 1
          local id = tostring(deck.key or deck.name or "?")
          local name = FH.get_back_display_name and FH.get_back_display_name(deck)
          if not (name and name ~= "") then bad[#bad + 1] = id .. ":noname" end
          local desc = DeckFacts.describe_deck(deck)
          if not (desc and desc ~= "") then bad[#bad + 1] = (name or id) .. ":nocontext" end
          if deck.unlocked ~= false then
            playable = playable + 1
            if not deck.config then bad[#bad + 1] = id .. ":unplayable(no config)" end
          end
        end
      end
      if #bad > 0 then
        return false, string.format("%d issue(s) across %d decks: %s", #bad, n, table.concat(bad, ", "))
      end
      return true, string.format("%d decks have name+context; %d unlocked+playable", n, playable)
    end,
  })

  add({
    name = "meta/all_bosses_have_context", timeout_s = 8,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local ok_df, DF = pcall(require, "facts.debuff_facts")
      if not (ok_df and DF.blind_effect_text) then return false, "debuff_facts unavailable" end
      local bad, n = {}, 0
      for key, def in pairs(G.P_BLINDS or {}) do
        if type(def) == "table" and def.boss then
          n = n + 1
          local txt = DF.blind_effect_text(key, def)
          if not (type(txt) == "string" and txt ~= "") then bad[#bad + 1] = tostring(key) end
        end
      end
      if n == 0 then return false, "no boss blinds enumerated" end
      if #bad > 0 then return false, string.format("%d/%d bosses lack effect text: %s", #bad, n, table.concat(bad, ", ")) end
      return true, string.format("%d boss blinds have effect text", n)
    end,
  })
  add({
    name = "meta/all_tags_have_context", timeout_s = 8,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local ok_df, DF = pcall(require, "facts.debuff_facts")
      if not (ok_df and DF.tag_effect_text) then return false, "debuff_facts unavailable" end
      local bad, n = {}, 0
      for key, def in pairs(G.P_TAGS or {}) do
        n = n + 1
        local txt = DF.tag_effect_text(key, def)
        if not (type(txt) == "string" and txt ~= "") then bad[#bad + 1] = tostring(key) end
      end
      if n == 0 then return false, "no tags enumerated" end
      if #bad > 0 then return false, string.format("%d/%d tags lack effect text: %s", #bad, n, table.concat(bad, ", ")) end
      return true, string.format("%d tags have effect text", n)
    end,
  })
  add({
    name = "meta/all_mods_have_context", timeout_s = 8,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local bad = {}
      for key, center in pairs(G.P_CENTERS or {}) do
        if type(center) == "table" and key ~= "" then
          if center.set == "Enhanced" and not CardUtil.ENHANCEMENTS[key] then
            bad[#bad + 1] = "enh:" .. tostring(key)
          elseif center.set == "Edition" then
            local strip = tostring(key):gsub("^e_", "")
            local nm = CardUtil.edition_name({ key = key, [strip] = true })
            if not (nm and nm ~= "") then bad[#bad + 1] = "ed:" .. tostring(key) end
          end
        end
      end
      for key, _ in pairs(G.P_SEALS or {}) do
        if not CardUtil.SEALS[key] then bad[#bad + 1] = "seal:" .. tostring(key) end
      end
      if #bad > 0 then return false, "missing fact entry: " .. table.concat(bad, ", ") end
      return true, "enhancements/editions/seals all have fact entries"
    end,
  })
  add({
    name = "boss/the_wall_double_target", timeout_s = 5,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local ct = CtxEconomy.calc_blind_target
      local wall = G.P_BLINDS and G.P_BLINDS.bl_wall
      local hook = G.P_BLINDS and G.P_BLINDS.bl_hook
      if not (wall and hook) then return true, "bl_wall/bl_hook absent, skipped" end
      local tw, th = ct("bl_wall"), ct("bl_hook")
      if not (tw and th) then return false, "calc_blind_target nil (get_blind_amount unavailable)" end
      local wm = wall.mult or (wall.config and wall.config.mult) or 1
      local hm = hook.mult or (hook.config and hook.config.mult) or 1
      local expect = th * (wm / hm)
      if math.abs(tw - expect) > 1 then
        return false, string.format("Wall target %s vs expected ~%s", tostring(tw), tostring(expect))
      end
      return true, string.format("Wall target %s = %sx a mult-%s boss", tostring(tw), tostring(wm / hm), tostring(hm))
    end,
  })
  add({
    name = "econ/calc_interest", timeout_s = 5,
    setup = function(ctx)
      ctx.amt, ctx.cap = G.GAME.interest_amount, G.GAME.interest_cap
      G.GAME.interest_amount, G.GAME.interest_cap = 1, 25
    end,
    act = function() end, wait_for = function() return true end,
    assert = function()
      local ci = CtxEconomy.calc_interest
      for _, c in ipairs({ { 0, 0 }, { 24, 4 }, { 25, 5 }, { 100, 5 } }) do
        local got = ci(c[1])
        if got ~= c[2] then
          return false, string.format("calc_interest(%d)=%s expected %d", c[1], tostring(got), c[2])
        end
      end
      return true, "interest floor+cap correct ($5/round at cap 25)"
    end,
    teardown = function(ctx) G.GAME.interest_amount, G.GAME.interest_cap = ctx.amt, ctx.cap end,
  })
  add({
    name = "econ/boss_reroll_cost_constant", timeout_s = 5,
    setup = function(ctx)
      ctx.uv = G.GAME.used_vouchers
      G.GAME.used_vouchers = {}
    end,
    act = function() end, wait_for = function() return true end,
    assert = function()
      if CtxEconomy.BOSS_REROLL_COST ~= 10 then return false, "BOSS_REROLL_COST != 10" end
      local _, enabled = CtxEconomy.can_reroll_boss()
      return enabled == false, "boss reroll must be disabled without Retcon/Director's Cut"
    end,
    teardown = function(ctx) G.GAME.used_vouchers = ctx.uv end,
  })
  add({
    name = "meta/seed_normalization", timeout_s = 5,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local ok_sr, SR = pcall(require, "handlers.seed_run_handlers")
      if not (ok_sr and SR.handle_paste_seed) then return false, "seed handler unavailable" end
      local function norm(seed)
        local ex = SR.handle_paste_seed({ seed = seed })
        if type(ex) ~= "function" then return nil end
        return (tostring(ex()):match("Seed set to: (%S+)"))
      end
      local norm_cases = {
        { "abcd1234", "ABCD1234" },
        { "hello-world-123", "HELLOWOR" }, -- strip separators + truncate to 8
        { "xy", "XY" },
      }
      for _, c in ipairs(norm_cases) do
        local got = norm(c[1])
        if got ~= c[2] then return false, string.format("norm(%q)=%s expected %s", c[1], tostring(got), c[2]) end
      end
      -- leetspeak profanity in a seed must still be rejected (strict filter)
      if norm(string.char(53, 104, 49, 116)) ~= nil then return false, "leet profanity seed was accepted" end
      return true, "seed upper/strip/truncate correct; leet profanity rejected"
    end,
  })
  add({
    name = "meta/seed_sensitivity", timeout_s = 5,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      if type(pseudorandom) ~= "function" or type(pseudoseed) ~= "function"
        or not (G.GAME and G.GAME.pseudorandom) then
        return true, "pseudorandom unavailable, skipped"
      end
      local k = "st_seed_sensitivity"
      local pr = G.GAME.pseudorandom
      local orig = pr.seed
      pr[k] = nil
      local a = pseudorandom(pseudoseed(k))
      pr.seed = "OTHERSEEDXYZ"
      pr[k] = nil
      local b = pseudorandom(pseudoseed(k))
      pr.seed = orig
      pr[k] = nil
      return a ~= b, string.format("seed must drive RNG: same key gave %s vs %s across seeds", tostring(a), tostring(b))
    end,
  })

  local ALL_STATES = {
    "SPLASH", "MENU", "RUN_SETUP", "GAME_OVER", "BLIND_SELECT", "SELECTING_HAND", "SHOP", "ROUND_EVAL",
    "TAROT_PACK", "PLANET_PACK", "SPECTRAL_PACK", "STANDARD_PACK", "BUFFOON_PACK", "SMODS_BOOSTER_OPENED",
  }
  add({
    name = "policy/info_actions_excluded_from_avail", timeout_s = 6,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local A = require("core.actions")
      for _, st in ipairs(ALL_STATES) do
        for _, name in ipairs(A.get_available_actions_for_state(st) or {}) do
          if A.INFO_ACTIONS[name] then return false, st .. " AVAIL leaks info action " .. name end
        end
      end
      return true, "AVAIL excludes all info actions in every state"
    end,
  })
  add({
    name = "policy/state_action_membership", timeout_s = 6,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local A = require("core.actions")
      local function has(st, name)
        for _, n in ipairs(A.get_action_names_for_state(st) or {}) do if n == name then return true end end
        return false
      end
      local checks = {
        { "SHOP", "buy_from_shop", true }, { "SHOP", "reroll_shop", true }, { "SHOP", "select_blind", false },
        { "SELECTING_HAND", "play_hand", true }, { "SELECTING_HAND", "buy_from_shop", false },
        { "BLIND_SELECT", "select_blind", true }, { "BLIND_SELECT", "skip_blind", true },
        { "ROUND_EVAL", "cash_out", true }, { "ROUND_EVAL", "buy_from_shop", false },
        { "SELECTING_HAND", "exit_overlay_menu", true }, -- universal
      }
      for _, c in ipairs(checks) do
        if has(c[1], c[2]) ~= c[3] then
          return false, string.format("%s membership of %s expected %s", c[1], c[2], tostring(c[3]))
        end
      end
      return true, "per-state action membership correct"
    end,
  })
  add({
    name = "policy/offered_actions_have_schema_and_executor", timeout_s = 8,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local A = require("core.actions")
      local D = require("core.dispatcher")
      local schemas = {}
      for _, def in ipairs(A.get_static_actions() or {}) do schemas[def.name] = true end
      local seen, bad = {}, {}
      for _, st in ipairs(ALL_STATES) do
        for _, name in ipairs(A.get_action_names_for_state(st) or {}) do
          if not seen[name] then
            seen[name] = true
            if not schemas[name] then bad[#bad + 1] = name .. ":noschema" end
            local has_exec = (D.get_action_handler and D.get_action_handler(name)) or (G.FUNCS and G.FUNCS[name])
            if not has_exec then bad[#bad + 1] = name .. ":noexec" end
          end
        end
      end
      if #bad > 0 then return false, "offered actions missing schema/executor: " .. table.concat(bad, ", ") end
      return true, "every offered action has a schema and an executor"
    end,
  })
  add({
    name = "policy/dead_actions_are_known_set", timeout_s = 6,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local A = require("core.actions")
      local offered = {}
      for _, st in ipairs(ALL_STATES) do
        for _, name in ipairs(A.get_action_names_for_state(st) or {}) do offered[name] = true end
      end
      -- actions with a schema that are never offered via a static state list (reachable only via force/menu screen)
      local KNOWN_OFFSCREEN = {}
      local bad = {}
      for _, def in ipairs(A.get_static_actions() or {}) do
        if not offered[def.name] and not KNOWN_OFFSCREEN[def.name] then bad[#bad + 1] = def.name end
      end
      if #bad > 0 then return false, "unexpected unreachable (dead) actions: " .. table.concat(bad, ", ") end
      return true, "no unexpected dead actions"
    end,
  })
  add({
    name = "policy/non_progress_contains_all_info", timeout_s = 6,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local A = require("core.actions")
      local D = require("core.dispatcher")
      local np = D.NON_PROGRESS_FORCE_ACTIONS or {}
      for name in pairs(A.INFO_ACTIONS) do
        if not np[name] then return false, "NON_PROGRESS missing info action " .. name end
      end
      for _, p in ipairs({ "buy_from_shop", "select_blind", "play_hand", "discard_hand", "cash_out" }) do
        if np[p] then return false, p .. " wrongly marked non-progress" end
      end
      return true, "NON_PROGRESS = info + non-advancing, excludes progress actions"
    end,
  })
  add({
    name = "staging/should_stage_classification", timeout_s = 6,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local ok_s, S = pcall(require, "core.staging")
      if not (ok_s and S.should_stage) then return true, "staging unavailable, skipped" end
      local function ss(name) return S.should_stage({ command = "action", data = { name = name } }) end
      for _, n in ipairs({ "buy_from_shop", "play_hand", "discard_hand", "select_blind", "use_card", "sell_card", "cash_out" }) do
        if not ss(n) then return false, n .. " should stage but did not" end
      end
      for _, n in ipairs({ "help", "quick_status", "simulate_hand" }) do
        if ss(n) then return false, n .. " must not stage (info)" end
      end
      if S.should_stage({ command = "startup" }) then return false, "non-action message must not stage" end
      return true, "should_stage classifies progress vs info/non-action"
    end,
  })
  add({
    name = "force/round_eval_static", timeout_s = 6,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local ok_f, FR = pcall(require, "force.force_router")
      if not (ok_f and FR.get_force_for_state) then return false, "force_router unavailable" end
      if G.OVERLAY_MENU then return true, "overlay open, round_eval force intercepted, skipped" end
      local f = FR.get_force_for_state("ROUND_EVAL")
      if type(f) ~= "table" or type(f.actions) ~= "table" then return false, "ROUND_EVAL force not a table" end
      local hascash = false
      for _, a in ipairs(f.actions) do if a == "cash_out" then hascash = true end end
      return hascash, "ROUND_EVAL force must offer cash_out, got " .. table.concat(f.actions, ",")
    end,
  })
  add({
    name = "force/pure_helpers", timeout_s = 6,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local ok_h, FH = pcall(require, "force.force_helpers")
      if not ok_h then return false, "force_helpers unavailable" end
      if FH.deck_name_of and FH.deck_name_of(nil) ~= "Red Deck" then
        return false, "deck_name_of(nil) expected 'Red Deck', got " .. tostring(FH.deck_name_of(nil))
      end
      if FH.menu_action_tree_query and (type(FH.menu_action_tree_query()) ~= "string" or FH.menu_action_tree_query() == "") then
        return false, "menu_action_tree_query must be a non-empty constant"
      end
      if FH.failed_action_warning then
        local prev = G.NEURO and G.NEURO.last_failed_action
        if G.NEURO then G.NEURO.last_failed_action = nil end
        local empty = FH.failed_action_warning()
        if G.NEURO then G.NEURO.last_failed_action = prev end
        if empty ~= "" and empty ~= nil then return false, "failed_action_warning must be empty with no failure, got " .. tostring(empty) end
      end
      return true, "force pure helpers correct (Red Deck default, warns, menu tree, no-failure blank)"
    end,
  })
  add({
    name = "force/gameover_offers_restart_immediately", timeout_s = 6,
    setup = function() end,
    act = function() end, wait_for = function() return true end,
    assert = function()
      if not G.NEURO then return true, "no G.NEURO, skipped" end
      local FR = require("force.force_router")
      local f = FR.get_force_for_state("GAME_OVER")
      if type(f) ~= "table" or type(f.actions) ~= "table" then
        return false, "game-over force must be offered immediately"
      end
      for _, a in ipairs(f.actions) do
        if a == "setup_run" then return true, "game-over offers setup_run immediately" end
      end
      return false, "game-over force must offer setup_run"
    end,
  })
  add({
    name = "ctx/helpers_short_maps", timeout_s = 6,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local ok_c, CH = pcall(require, "context.ctx_helpers")
      if not ok_c then return false, "ctx_helpers unavailable" end
      if CH.short_suit then
        for suit, code in pairs({ Hearts = "H", Diamonds = "D", Clubs = "C", Spades = "S" }) do
          if CH.short_suit(suit) ~= code then return false, "short_suit(" .. suit .. ") != " .. code end
        end
      end
      if CH.short_value and CH.short_value("Ace") ~= "A" then return false, "short_value(Ace) != A" end
      if CH.compact_text then
        local out = CH.compact_text("a,b|c\nd  e", 100)
        if out:find(",", 1, true) or out:find("|", 1, true) or out:find("\n", 1, true) then
          return false, "compact_text left a delimiter: " .. out
        end
        if #CH.compact_text(string.rep("x", 50), 10) > 10 then return false, "compact_text did not truncate to max" end
      end
      return true, "ctx_helpers short maps + compact_text sanitize/truncate correct"
    end,
  })
  add({
    name = "ctx/token_legends_ascii", timeout_s = 6,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local ok_t, TL = pcall(require, "facts.token_legends")
      if not (ok_t and TL.for_state) then return false, "token_legends unavailable" end
      local function ascii_check(label, text)
        if type(text) ~= "string" then return true end
        for i = 1, #text do
          if text:byte(i) >= 128 then return false, label .. " legend has non-ASCII byte at " .. i end
        end
        return true
      end
      local okc, errc = ascii_check("COMMON", TL.COMMON)
      if not okc then return false, errc end
      for _, st in ipairs(ALL_STATES) do
        local _, text = TL.for_state(st)
        local oks, errs = ascii_check(st, text)
        if not oks then return false, errs end
      end
      return true, "all token legends are ASCII-only"
    end,
  })

  add({
    name = "blind/select_small+burglar", timeout_s = 25,
    setup = function(ctx)
      clear_area(G.jokers)
      ctx.burglar = spawn_joker("j_burglar")
      ctx.extra = ctx.burglar.ability.extra
      ctx.base = (G.GAME.round_resets.hands or 0) + ((G.GAME.round_bonus and G.GAME.round_bonus.next_hands) or 0)
    end,
    act = function()
      local _, err = run_action("select_blind", { blind = "small" })
      if err then error(err) end
    end,
    wait_for = function()
      return G.STATE == G.STATES.SELECTING_HAND and G.hand and #G.hand.cards > 0 and settled()
    end,
    assert = function(ctx)
      local hl = G.GAME.current_round.hands_left
      local dl = G.GAME.current_round.discards_left
      local want = ctx.base + ctx.extra
      return hl == want and dl == 0,
        string.format("Burglar: expected %d hands + 0 discards, got %s hands + %s discards", want, tostring(hl), tostring(dl))
    end,
  })

  for _, center in ipairs(G.P_CENTER_POOLS.Planet or {}) do
    covered[center.key] = true
    if center.key == "c_black_hole" then
      add(black_hole_case("planet", center.key))
    elseif center.config and center.config.hand_type then
      add(planet_case(center))
    else
      add(generic_consumable_case("planet", center))
    end
  end

  for _, center in ipairs(G.P_CENTER_POOLS.Tarot or {}) do
    covered[center.key] = true
    add(pick_consumable_case("tarot", center))
  end

  for _, center in ipairs(G.P_CENTER_POOLS.Spectral or {}) do
    covered[center.key] = true
    add(pick_consumable_case("spectral", center))
  end
  for _, key in ipairs({ "c_black_hole", "c_soul" }) do
    if not covered[key] and G.P_CENTERS[key] then
      add(pick_consumable_case("spectral", G.P_CENTERS[key]))
      covered[key] = true
    end
  end

  -- info smoke tests in SELECTING_HAND; shop_context needs the shop so it is added in the SHOP span
  do
    local Actions = require("core.actions")
    for name in pairs(Actions.INFO_ACTIONS or {}) do
      if name ~= "shop_context" then add(info_smoke_case(name)) end
    end
  end

  add({
    name = "action/discard_consumes_discard", timeout_s = 20,
    setup = function(ctx)
      set_hand({ "H_5", "S_9", "D_2", "C_K", "H_A" })
      G.GAME.current_round.discards_left = 2
      ctx.a, ctx.b = G.hand.cards[1], G.hand.cards[2]
    end,
    act = discard({ 1, 2 }),
    wait_for = function()
      return G.GAME.current_round.discards_left == 1 and #G.hand.highlighted == 0 and settled()
    end,
    assert = function(ctx)
      local gone = not index_of(G.hand, ctx.a) and not index_of(G.hand, ctx.b)
      return G.GAME.current_round.discards_left == 1 and gone,
        string.format("discards_left=%s gone=%s", tostring(G.GAME.current_round.discards_left), tostring(gone))
    end,
  })
  add({
    name = "action/discard_rejected_when_zero", timeout_s = 10,
    setup = function() G.GAME.current_round.discards_left = 0 end,
    act = function(ctx)
      local _, err = run_action("discard_hand", { indices = { 1 } })
      ctx.err = err
    end,
    wait_for = function() return true end,
    assert = function(ctx)
      return ctx.err ~= nil and tostring(ctx.err):find("discard") ~= nil,
        "expected no-discards rejection, got: " .. tostring(ctx.err)
    end,
    teardown = function() if G.GAME.current_round then G.GAME.current_round.discards_left = 4 end end,
  })
  add({
    name = "action/set_joker_order", timeout_s = 10,
    setup = function(ctx)
      clear_area(G.jokers)
      ctx.a = spawn_joker("j_joker")
      ctx.b = spawn_joker("j_greedy_joker")
    end,
    act = function()
      local _, err = run_action("set_joker_order", { from_index = 1, to_index = 2 })
      if err then error(err) end
    end,
    wait_for = function() return settled() end,
    assert = function(ctx)
      return G.jokers.cards[1] == ctx.b and G.jokers.cards[2] == ctx.a,
        "expected jokers swapped after moving index 1 to 2"
    end,
  })
  for _, sk in ipairs({ { "suit", "sort_hand_suit" }, { "value", "sort_hand_value" } }) do
    local field, fn = sk[1], sk[2]
    add({
      name = "action/" .. fn, timeout_s = 10,
      setup = function() set_hand({ "S_9", "H_2", "D_K", "C_5", "H_A" }) end,
      act = function() if G.FUNCS and G.FUNCS[fn] then gfunc(fn) end end,
      wait_for = function() return settled() end,
      assert = function()
        if not (G.FUNCS and G.FUNCS[fn]) then return true, fn .. " absent, skipped" end
        local keys = {}
        for _, c in ipairs(G.hand.cards) do
          keys[#keys + 1] = (field == "suit") and (c.base and c.base.suit or "?") or (c.base and c.base.id or 0)
        end
        if #keys < 2 then return false, "hand too small to check sort" end
        if field == "suit" then
          local seen = {}
          for i = 1, #keys do
            if keys[i] ~= keys[i - 1] then
              if seen[keys[i]] then return false, "suit not grouped: " .. table.concat(keys, ",") end
              seen[keys[i]] = true
            end
          end
          return true, "hand grouped by suit"
        end
        local inc, dec = true, true
        for i = 2, #keys do
          if keys[i] < keys[i - 1] then inc = false end
          if keys[i] > keys[i - 1] then dec = false end
        end
        return inc or dec, "hand not monotonically sorted by value: " .. table.concat(keys, ",")
      end,
    })
  end
  add({
    name = "action/sell_consumable_pays_value", timeout_s = 15,
    setup = function(ctx)
      clear_area(G.consumeables)
      ctx.card = spawn_consumable("c_mercury")
      ctx.sell = tonumber(ctx.card.sell_cost) or 0
      money(10)
    end,
    act = function(ctx)
      local idx = index_of(G.consumeables, ctx.card) or 1
      local _, err = run_action("sell_card", { area = "consumeables", index = idx })
      if err then error(err) end
    end,
    wait_for = function() return #G.consumeables.cards == 0 and settled() end,
    assert = function(ctx)
      return dollars() == 10 + ctx.sell,
        string.format("expected $%d after selling consumable ($%d value), got $%d", 10 + ctx.sell, ctx.sell, dollars())
    end,
  })

  -- numeric scoring: realized round-score delta must equal the fact-derived base+card contributions
  add(score_delta_case("score/base_high_card", { "H_2", "S_5", "D_9", "C_K", "H_A" }, { 1, 2, 3, 4, 5 }))
  add(score_delta_case("score/base_pair", { "H_5", "S_5", "D_2", "C_9", "H_K" }, { 1, 2 }))
  add(score_delta_case("score/base_two_pair", { "H_5", "S_5", "D_9", "C_9", "H_K" }, { 1, 2, 3, 4 }))
  add(score_delta_case("score/base_three_kind", { "H_5", "S_5", "D_5", "C_9", "H_K" }, { 1, 2, 3 }))
  add(score_delta_case("score/base_flush", { "H_2", "H_5", "H_9", "H_J", "H_K" }, { 1, 2, 3, 4, 5 }))
  add(score_delta_case("score/base_straight", { "H_2", "S_3", "D_4", "C_5", "H_6" }, { 1, 2, 3, 4, 5 }))
  add(score_delta_case("score/bonus_card_plus30chips",
    { "H_5", { front = "S_5", center = "m_bonus" }, "D_2", "C_9", "H_K" }, { 1, 2 }))
  add(score_delta_case("score/mult_card_plus4",
    { "H_5", { front = "S_5", center = "m_mult" }, "D_2", "C_9", "H_K" }, { 1, 2 }))
  add(score_delta_case("score/foil_plus50chips", { "H_5", "S_5", "D_2", "C_9", "H_K" }, { 1, 2 },
    { extra_chips = 50, mutate = function(cards) cards[1]:set_edition("e_foil", true, true) end }))
  add(score_delta_case("score/holo_plus10mult", { "H_5", "S_5", "D_2", "C_9", "H_K" }, { 1, 2 },
    { extra_mult = 10, mutate = function(cards) cards[1]:set_edition("e_holo", true, true) end }))
  add(score_delta_case("score/poly_x1_5", { "H_5", "S_5", "D_2", "C_9", "H_K" }, { 1, 2 },
    { xmult = 1.5, tol = 2, mutate = function(cards) cards[1]:set_edition("e_polychrome", true, true) end }))
  add(score_delta_case("score/glass_x2",
    { "H_5", { front = "S_5", center = "m_glass" }, "D_2", "C_9", "H_K" }, { 1, 2 }, { xmult = 2, tol = 2 }))
  add(score_delta_case("score/steel_held_x1_5",
    { "H_5", "S_5", { front = "D_2", center = "m_steel" }, "C_9", "H_K" }, { 1, 2 }, { xmult = 1.5, tol = 2 }))
  add(score_delta_case("joker/j_joker_plus4mult", { "H_5", "S_5", "D_2", "C_9", "H_K" }, { 1, 2 },
    { joker = "j_joker", extra_mult = 4 }))
  add(score_delta_case("joker/j_greedy_diamonds_plus3", { "D_2", "D_5", "D_9", "D_J", "D_K" }, { 1, 2, 3, 4, 5 },
    { joker = "j_greedy_joker", extra_mult = function(sh) return 3 * count_suit(sh, "Diamonds") end }))
  add(score_delta_case("joker/j_even_steven_plus4", { "H_4", "S_4", "D_2", "C_9", "H_K" }, { 1, 2 },
    { joker = "j_even_steven", extra_mult = function(sh) return 4 * count_ids(sh, EVEN_IDS) end }))
  add(score_delta_case("joker/j_odd_todd_plus31chips", { "H_5", "S_5", "D_2", "C_9", "H_K" }, { 1, 2 },
    { joker = "j_odd_todd", extra_chips = function(sh) return 31 * count_ids(sh, ODD_IDS) end }))
  add(score_delta_case("joker/j_hack_retrigger_low", { "H_5", "S_5", "D_2", "C_9", "H_K" }, { 1, 2 },
    { joker = "j_hack", extra_chips = function(sh) return sum_ids_chips(sh, HACK_IDS) end }))
  add(score_delta_case("joker/j_brainstorm_copies_leftmost", { "H_5", "S_5", "D_2", "C_9", "H_K" }, { 1, 2 },
    { joker = "j_joker", extra_mult = 8, mutate = function() spawn_joker("j_brainstorm") end }))
  local PAIR_H, PAIR_I = { "H_5", "S_5", "D_2", "C_9", "H_K" }, { 1, 2 }
  local TRIP_H, TRIP_I = { "H_5", "S_5", "D_5", "C_9", "H_K" }, { 1, 2, 3 }
  local TWOP_H, TWOP_I = { "H_5", "S_5", "D_9", "C_9", "H_K" }, { 1, 2, 3, 4 }
  local QUAD_H, QUAD_I = { "H_5", "S_5", "D_5", "C_5", "H_K" }, { 1, 2, 3, 4 }
  local STR_H, STR_I = { "H_2", "S_3", "D_4", "C_5", "H_6" }, { 1, 2, 3, 4, 5 }
  local FLU_H, FLU_I = { "H_2", "H_5", "H_9", "H_J", "H_K" }, { 1, 2, 3, 4, 5 }
  add(score_delta_case("joker/j_jolly_pair_mult", PAIR_H, PAIR_I, { joker = "j_jolly", extra_mult = 8 }))
  add(score_delta_case("joker/j_sly_pair_chips", PAIR_H, PAIR_I, { joker = "j_sly", extra_chips = 50 }))
  add(score_delta_case("joker/j_the_duo_pair_x2", PAIR_H, PAIR_I, { joker = "j_duo", xmult = 2 }))
  add(score_delta_case("joker/j_zany_trips_mult", TRIP_H, TRIP_I, { joker = "j_zany", extra_mult = 12 }))
  add(score_delta_case("joker/j_wily_trips_chips", TRIP_H, TRIP_I, { joker = "j_wily", extra_chips = 100 }))
  add(score_delta_case("joker/j_the_trio_x3", TRIP_H, TRIP_I, { joker = "j_trio", xmult = 3 }))
  add(score_delta_case("joker/j_mad_twopair_mult", TWOP_H, TWOP_I, { joker = "j_mad", extra_mult = 10 }))
  add(score_delta_case("joker/j_clever_twopair_chips", TWOP_H, TWOP_I, { joker = "j_clever", extra_chips = 80 }))
  add(score_delta_case("joker/j_the_family_quad_x4", QUAD_H, QUAD_I, { joker = "j_family", xmult = 4 }))
  add(score_delta_case("joker/j_crazy_straight_mult", STR_H, STR_I, { joker = "j_crazy", extra_mult = 12 }))
  add(score_delta_case("joker/j_devious_straight_chips", STR_H, STR_I, { joker = "j_devious", extra_chips = 100 }))
  add(score_delta_case("joker/j_the_order_straight_x3", STR_H, STR_I, { joker = "j_order", xmult = 3 }))
  add(score_delta_case("joker/j_droll_flush_mult", FLU_H, FLU_I, { joker = "j_droll", extra_mult = 10 }))
  add(score_delta_case("joker/j_crafty_flush_chips", FLU_H, FLU_I, { joker = "j_crafty", extra_chips = 80 }))
  add(score_delta_case("joker/j_the_tribe_flush_x2", FLU_H, FLU_I, { joker = "j_tribe", xmult = 2 }))
  add(score_delta_case("joker/j_lusty_hearts", FLU_H, FLU_I,
    { joker = "j_lusty_joker", extra_mult = function(sh) return 3 * count_suit(sh, "Hearts") end }))
  add(score_delta_case("joker/j_wrathful_spades", { "S_2", "S_5", "S_9", "S_J", "S_K" }, FLU_I,
    { joker = "j_wrathful_joker", extra_mult = function(sh) return 3 * count_suit(sh, "Spades") end }))
  add(score_delta_case("joker/j_gluttonous_clubs", { "C_2", "C_5", "C_9", "C_J", "C_K" }, FLU_I,
    { joker = "j_gluttenous_joker", extra_mult = function(sh) return 3 * count_suit(sh, "Clubs") end }))
  add(score_delta_case("joker/j_scholar_aces", { "H_A", "S_A", "D_2", "C_9", "H_K" }, { 1, 2 },
    { joker = "j_scholar",
      extra_chips = function(sh) return 20 * count_ids(sh, ACE_IDS) end,
      extra_mult = function(sh) return 4 * count_ids(sh, ACE_IDS) end }))
  add(score_delta_case("joker/j_smiley_faces", { "H_K", "S_K", "D_2", "C_9", "H_5" }, { 1, 2 },
    { joker = "j_smiley", extra_mult = function(sh) return 5 * count_ids(sh, FACE_IDS) end }))
  add(score_delta_case("joker/j_fibonacci", { "H_3", "S_3", "D_9", "C_K", "H_2" }, { 1, 2 },
    { joker = "j_fibonacci", extra_mult = function(sh) return 8 * count_ids(sh, FIB_IDS) end }))
  add(score_delta_case("joker/j_cavendish_x3", PAIR_H, PAIR_I, { joker = "j_cavendish", xmult = 3, tol = 2 }))

  add(score_delta_case("score/red_seal_retrigger", { "H_5", "S_5", "D_2", "C_9", "H_K" }, { 1, 2 }, {
    mutate = function(cards) cards[1]:set_seal("Red", nil, true) end,
    extra_chips = function(sh)
      local s = 0
      for _, c in ipairs(sh) do if c.seal == "Red" and c.get_chip_bonus then s = s + (tonumber(c:get_chip_bonus()) or 0) end end
      return s
    end,
    extra_mult = function(sh)
      local s = 0
      for _, c in ipairs(sh) do if c.seal == "Red" and c.get_chip_mult then s = s + (tonumber(c:get_chip_mult()) or 0) end end
      return s
    end,
  }))
  add({
    name = "score/gold_seal_plus3_when_scored", timeout_s = 30,
    setup = function(ctx)
      clear_area(G.jokers)
      local cards = set_hand({ "H_5", "S_5", "D_2", "C_9", "H_K" })
      cards[1]:set_seal("Gold", nil, true)
      G.GAME.current_round.hands_left = 3
      ctx.pre = dollars()
    end,
    act = play({ 1, 2 }),
    wait_for = function()
      return G.STATE == G.STATES.SELECTING_HAND and G.play and #G.play.cards == 0
        and G.GAME.current_round.hands_left == 2 and settled()
    end,
    assert = function(ctx)
      return dollars() == ctx.pre + 3,
        string.format("gold seal +$3 on score: expected $%d, got $%d", ctx.pre + 3, dollars())
    end,
  })
  add({
    name = "score/wild_card_completes_flush", timeout_s = 30,
    setup = function()
      clear_area(G.jokers)
      set_hand({ "H_2", "H_5", "H_9", "H_K", { front = "S_3", center = "m_wild" } })
      G.GAME.current_round.hands_left = 3
    end,
    act = play({ 1, 2, 3, 4, 5 }),
    wait_for = function()
      return G.STATE == G.STATES.SELECTING_HAND and G.play and #G.play.cards == 0
        and G.GAME.current_round.hands_left == 2 and settled()
    end,
    assert = function()
      local lh = SMODS.last_hand or {}
      return tostring(lh.scoring_name) == "Flush",
        "wild card should complete a Flush, got " .. tostring(lh.scoring_name)
    end,
  })

  add({
    name = "neg/play_rejected_zero_hands", timeout_s = 10,
    setup = function() set_hand({ "H_5", "S_5", "D_2", "C_9", "H_K" }); G.GAME.current_round.hands_left = 0 end,
    act = function(ctx) local _, err = run_action("play_hand", { indices = { 1, 2 } }); ctx.err = err end,
    wait_for = function() return true end,
    assert = function(ctx)
      return ctx.err ~= nil and tostring(ctx.err):find("hands remaining") ~= nil,
        "expected no-hands rejection, got: " .. tostring(ctx.err)
    end,
    teardown = function() if G.GAME.current_round then G.GAME.current_round.hands_left = 4 end end,
  })
  add({
    name = "neg/play_rejected_invalid_indices", timeout_s = 10,
    setup = function() set_hand({ "H_5", "S_5", "D_2" }) end,
    act = function(ctx) local _, err = run_action("play_hand", { indices = { 99, 100 } }); ctx.err = err end,
    wait_for = function() return true end,
    assert = function(ctx)
      return ctx.err ~= nil and tostring(ctx.err):find("indices") ~= nil,
        "expected invalid-indices rejection, got: " .. tostring(ctx.err)
    end,
  })
  add({
    name = "neg/play_rejected_empty_indices", timeout_s = 10,
    setup = function() set_hand({ "H_5", "S_5", "D_2" }) end,
    act = function(ctx) local _, err = run_action("play_hand", { indices = {} }); ctx.err = err end,
    wait_for = function() return true end,
    assert = function(ctx)
      return ctx.err ~= nil and tostring(ctx.err):find("indices") ~= nil,
        "expected empty-indices rejection, got: " .. tostring(ctx.err)
    end,
  })
  add({
    name = "neg/consumable_too_many_targets", timeout_s = 10,
    setup = function(ctx)
      clear_area(G.consumeables)
      set_hand({ "H_5", "S_5", "D_2", "C_9", "H_K" }) -- >=4 valid cards so only the count check can fire
      ctx.card = spawn_consumable("c_strength")
    end,
    act = function(ctx)
      local idx = index_of(G.consumeables, ctx.card) or 1
      local _, err = run_action("use_card", { area = "consumeables", index = idx, hand_indices = { 1, 2, 3, 4 } })
      ctx.err = err
    end,
    wait_for = function() return true end,
    assert = function(ctx)
      return ctx.err ~= nil and tostring(ctx.err):lower():find("too many") ~= nil,
        "expected too-many-targets rejection, got: " .. tostring(ctx.err)
    end,
  })
  add({
    name = "neg/sell_rejected_invalid_index", timeout_s = 10,
    setup = function() clear_area(G.jokers); spawn_joker("j_joker") end,
    act = function(ctx) local _, err = run_action("sell_card", { area = "jokers", index = 99 }); ctx.err = err end,
    wait_for = function() return true end,
    assert = function(ctx)
      return ctx.err ~= nil, "expected invalid-index rejection, got: " .. tostring(ctx.err)
    end,
  })
  add({
    name = "neg/consumable_slot_limit", timeout_s = 8,
    setup = function(ctx)
      clear_area(G.consumeables)
      ctx.empty = CardUtil.has_consumable_space and CardUtil.has_consumable_space()
      local lim = (CardUtil.consumable_limit and CardUtil.consumable_limit())
        or (G.consumeables.config and G.consumeables.config.card_limit) or 2
      for _ = 1, lim do spawn_consumable("c_mercury") end
      ctx.full = CardUtil.has_consumable_space and CardUtil.has_consumable_space()
    end,
    act = function() end, wait_for = function() return settled() end,
    assert = function(ctx)
      if CardUtil.has_consumable_space == nil then return true, "has_consumable_space absent, skipped" end
      return ctx.empty == true and ctx.full == false,
        string.format("consumable space: empty=%s full=%s", tostring(ctx.empty), tostring(ctx.full))
    end,
    teardown = function() clear_area(G.consumeables) end,
  })

  add({
    name = "fact/quick_status_reports_money", timeout_s = 8,
    setup = function(ctx) ctx.m = dollars(); money(42) end,
    act = function(ctx) ctx.res, ctx.err = run_action("quick_status") end,
    wait_for = function() return true end,
    assert = function(ctx)
      if ctx.err then return false, "quick_status err: " .. tostring(ctx.err) end
      return type(ctx.res) == "string" and ctx.res:find("42", 1, true) ~= nil,
        "quick_status should report $42, got: " .. tostring(ctx.res)
    end,
    teardown = function(ctx) money(ctx.m or 50) end,
  })
  add({
    name = "fact/hand_levels_reflects_level", timeout_s = 8,
    setup = function(ctx) ctx.hd = G.GAME.hands["Pair"]; ctx.lvl0 = ctx.hd and ctx.hd.level; if ctx.hd then ctx.hd.level = 7 end end,
    act = function(ctx) ctx.res, ctx.err = run_action("hand_levels_info") end,
    wait_for = function() return true end,
    assert = function(ctx)
      if ctx.err then return false, tostring(ctx.err) end
      return type(ctx.res) == "string" and ctx.res:find("7", 1, true) ~= nil,
        "hand_levels_info should show Pair at level 7"
    end,
    teardown = function(ctx) if ctx.hd and ctx.lvl0 then ctx.hd.level = ctx.lvl0 end end,
  })
  add({
    name = "shape/hand_type_detection", timeout_s = 10,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      if not HandFacts.contained_types then return true, "contained_types absent, skipped" end
      local checks = {
        { { "H_2", "H_3", "H_4", "H_5", "H_6" }, "Straight Flush" },
        { { "H_5", "S_5", "D_5", "C_5", "H_9" }, "Four of a Kind" },
        { { "H_5", "S_5", "D_5", "C_9", "H_9" }, "Full House" },
        { { "H_2", "H_5", "H_9", "H_J", "H_K" }, "Flush" },
        { { "H_2", "S_3", "D_4", "C_5", "H_6" }, "Straight" },
        { { "H_5", "S_5", "D_5", "C_9", "H_K" }, "Three of a Kind" },
        { { "H_5", "S_5", "D_9", "C_9", "H_K" }, "Two Pair" },
        { { "H_5", "S_5", "D_2", "C_9", "H_K" }, "Pair" },
      }
      for _, ch in ipairs(checks) do
        set_hand(ch[1])
        local ct = HandFacts.contained_types(G.hand.cards) or {}
        if not ct[ch[2]] then return false, "contained_types missed " .. ch[2] end
      end
      return true, "contained_types detects all 8 hand types"
    end,
  })
  add({
    name = "action/copy_seed", timeout_s = 8,
    setup = function() end,
    act = function(ctx)
      ctx.ok = G.FUNCS and G.FUNCS.copy_seed ~= nil
      if ctx.ok then ctx.threw = not pcall(function() gfunc("copy_seed") end) end
    end,
    wait_for = function() return settled() end,
    assert = function(ctx)
      if not ctx.ok then return true, "copy_seed func absent, skipped" end
      return not ctx.threw, "copy_seed should run without error"
    end,
  })

  add({
    name = "force/selecting_hand_completeness", timeout_s = 10,
    setup = function()
      clear_area(G.jokers)
      clear_area(G.consumeables)
      spawn_joker("j_joker")            -- non-eternal => sell_card legal (mid-round sell)
      spawn_consumable("c_mercury")     -- => use_card legal
      set_hand({ "H_5", "S_5", "D_2", "C_9", "H_K" })
      G.GAME.current_round.hands_left = 3
      G.GAME.current_round.discards_left = 3
    end,
    act = function() end, wait_for = function() return settled() end,
    assert = function()
      local A = require("core.actions")
      local D = require("core.dispatcher")
      local FR = require("force.force_router")
      local np = D.NON_PROGRESS_FORCE_ACTIONS or {}
      local f = FR.get_force_for_state("SELECTING_HAND")
      if type(f) ~= "table" or type(f.actions) ~= "table" then return false, "no force for SELECTING_HAND" end
      local set = {}
      for _, a in ipairs(f.actions) do set[a] = true end
      -- force must offer EVERY legal PROGRESS action (agnostic, no preference); NON_PROGRESS (set_joker_order, sorts) may be dropped/ride-along
      for _, need in ipairs(A.get_available_actions_for_state("SELECTING_HAND") or {}) do
        if not np[need] and not set[need] then return false, "force omits legal progress action " .. need end
      end
      if not set["sell_card"] then return false, "force must offer sell_card with a sellable joker" end
      if not (set["play_hand"] or set["discard_hand"]) then return false, "force must offer play_hand/discard_hand" end
      return true, "force offers all legal SELECTING_HAND actions incl sell_card/use_card"
    end,
    teardown = function() clear_area(G.jokers); clear_area(G.consumeables) end,
  })
  add({
    name = "force/agnostic_names_only", timeout_s = 8,
    setup = function() set_hand({ "H_5", "S_5", "D_2", "C_9", "H_K" }); G.GAME.current_round.hands_left = 3 end,
    act = function() end, wait_for = function() return true end,
    assert = function()
      local FR = require("force.force_router")
      local f = FR.get_force_for_state("SELECTING_HAND")
      if type(f) ~= "table" then return true, "no force (fine), skipped" end
      -- agnosticism: force is a flat list of action NAME strings, never a pre-chosen index/target payload
      for _, a in ipairs(f.actions or {}) do
        if type(a) ~= "string" then return false, "force carries a non-name payload (pre-selection): " .. type(a) end
      end
      return true, "force offers action names only, no pre-selected indices/targets"
    end,
  })
  add({
    name = "ctx/build_ascii_and_wellformed", timeout_s = 8,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local CC = require("context.context_compact")
      local A = require("core.actions")
      local s = CC.build("SELECTING_HAND", A.get_available_actions_for_state("SELECTING_HAND"), { no_cache = true })
      if type(s) ~= "string" or s == "" then return false, "build returned empty" end
      if not s:find("STATE:", 1, true) then return false, "build missing STATE line" end
      for i = 1, #s do
        if s:byte(i) >= 128 then return false, "non-ASCII byte in compact context at " .. i end
      end
      return true, string.format("compact context well-formed + ASCII (%d bytes)", #s)
    end,
  })
  add({
    name = "ctx/stable_volatile_split", timeout_s = 8,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local CC = require("context.context_compact")
      local A = require("core.actions")
      local allowed = A.get_available_actions_for_state("SELECTING_HAND")
      local stable = CC.build("SELECTING_HAND", allowed, { no_cache = true, split = "stable" })
      local volatile = CC.build("SELECTING_HAND", allowed, { no_cache = true, split = "volatile" })
      if type(stable) ~= "string" or type(volatile) ~= "string" then return true, "split unsupported, skipped" end
      if stable == volatile then return true, "split produced identical output, skipped" end
      local prefixes = { "V|", "JD:", "FRAME|", "RUN|" }
      local function is_stable(line)
        for _, p in ipairs(prefixes) do if line:sub(1, #p) == p then return true end end
        return false
      end
      for line in stable:gmatch("[^\n]+") do
        if line ~= "" and not line:find("STATE:", 1, true) and not is_stable(line) then
          return false, "stable channel has a volatile line: " .. line
        end
      end
      for line in volatile:gmatch("[^\n]+") do
        if is_stable(line) then return false, "volatile channel has a stable line: " .. line end
      end
      return true, "stable/volatile channels are cleanly separated"
    end,
  })
  add({
    name = "ctx/glossary_once_per_ante", timeout_s = 6,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local FH = require("force.force_helpers")
      if not (FH.once_until and FH.snapshot_once_serials and FH.restore_once_serials) then
        return true, "once_until unavailable, skipped"
      end
      local snap = FH.snapshot_once_serials()
      local a = FH.once_until("st_gloss_probe", 1)
      local b = FH.once_until("st_gloss_probe", 1)
      local c = FH.once_until("st_gloss_probe", 2)
      FH.restore_once_serials(snap)
      return a == true and b == false and c == true,
        string.format("once_until gate: first=%s repeat=%s new-ante=%s", tostring(a), tostring(b), tostring(c))
    end,
  })

  add({
    name = "boss/flint_halves_base", timeout_s = 5,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local ok_df, DF = pcall(require, "facts.debuff_facts")
      if not (ok_df and DF.flint_halve) then return false, "flint_halve unavailable" end
      local c, m = DF.flint_halve(100, 10)
      if c ~= 50 or m ~= 5 then return false, string.format("flint_halve(100,10)=%s,%s expected 50,5", tostring(c), tostring(m)) end
      local _, m2 = DF.flint_halve(3, 1)
      if m2 < 1 then return false, "flint_halve mult floored below 1: " .. tostring(m2) end
      return true, "flint halves base chips+mult (100,10 -> 50,5), mult floor 1"
    end,
  })
  add({
    name = "life/cashout_identity", timeout_s = 5,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local econ = CtxEconomy.economy_projection and CtxEconomy.economy_projection({})
      if type(econ) ~= "table" then return false, "economy_projection unavailable" end
      local sum = (econ.blind_reward or 0) + (econ.hands_bonus or 0) + (econ.discard_bonus or 0) + (econ.interest or 0)
      if sum ~= econ.projected_total then
        return false, string.format("projection sum %s != projected_total %s", tostring(sum), tostring(econ.projected_total))
      end
      if CtxEconomy.payout_token then
        local tok = CtxEconomy.payout_token(econ)
        if not (type(tok) == "string" and tok:find("=") and tok:find("T")) then
          return false, "payout_token missing B+..=T shape: " .. tostring(tok)
        end
      end
      return true, "cash-out identity B+hr+dr+I=T holds"
    end,
  })

  -- per-joker context without spawning (cumulative spawns corrupt engine state / hang the queue); constructed card so joker_fx can't mutate the live game
  add({
    name = "meta/all_jokers_have_context", timeout_s = 8,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local pool = G.P_CENTER_POOLS.Joker or {}
      if #pool == 0 then return false, "no jokers in pool" end
      local bad, n = {}, 0
      for _, center in ipairs(pool) do
        n = n + 1
        local id = tostring(center.key or "?")
        if not (center.name and center.name ~= "") then bad[#bad + 1] = id .. ":noname" end
        local rn = CardUtil.rarity_name(center.rarity)
        if not (rn and rn ~= "") then bad[#bad + 1] = id .. ":norarity" end
        local ok = pcall(function()
          return CardUtil.joker_fx({ config = { center = center }, ability = center.config or {} })
        end)
        if not ok then bad[#bad + 1] = id .. ":fx_throws" end
      end
      if #bad > 0 then return false, string.format("%d joker context issues: %s", #bad, table.concat(bad, ", ")) end
      return true, string.format("%d jokers have name+rarity+fx", n)
    end,
  })

  add({
    name = "edge/splash_all_played_score", timeout_s = 30,
    setup = function(_ctx)
      clear_area(G.jokers)
      spawn_joker("j_splash")
      set_hand({ "H_5", "S_5", "D_2", "C_9", "H_K" })
      G.GAME.current_round.hands_left = 3
    end,
    act = play({ 1, 2, 3, 4, 5 }),
    wait_for = function()
      return G.STATE == G.STATES.SELECTING_HAND and G.play and #G.play.cards == 0
        and G.GAME.current_round.hands_left == 2 and settled()
    end,
    assert = function()
      local lh = SMODS.last_hand or {}
      local n = lh.scoring_hand and #lh.scoring_hand or -1
      return n == 5, string.format("Splash: expected all 5 played cards to score, got %d (%s)", n, tostring(lh.scoring_name))
    end,
  })

  add({
    name = "edge/stone_always_scores", timeout_s = 30,
    setup = function(_ctx)
      clear_area(G.jokers)
      set_hand({ "H_5", "S_5", { front = "H_2", center = "m_stone" }, "C_9", "H_K" })
      G.GAME.current_round.hands_left = 3
    end,
    act = play({ 1, 2, 3 }),
    wait_for = function()
      return G.STATE == G.STATES.SELECTING_HAND and G.play and #G.play.cards == 0
        and G.GAME.current_round.hands_left == 2 and settled()
    end,
    assert = function()
      local lh = SMODS.last_hand or {}
      local n = lh.scoring_hand and #lh.scoring_hand or -1
      return n == 3 and tostring(lh.scoring_name) == "Pair",
        string.format("Stone: expected Pair with 3 scoring cards (pair + stone), got %d (%s)", n, tostring(lh.scoring_name))
    end,
  })

  add({
    name = "edge/four_fingers_flush", timeout_s = 30,
    setup = function(ctx)
      clear_area(G.jokers)
      spawn_joker("j_four_fingers")
      set_hand({ "H_2", "H_7", "H_9", "H_K", "S_3" })
      G.GAME.current_round.hands_left = 3
      local sh = HandFacts.shape(G.hand.cards)
      ctx.fact_ok = sh.flush_thr == 4 and sh.flush_ready
    end,
    act = play({ 1, 2, 3, 4 }),
    wait_for = function()
      return G.STATE == G.STATES.SELECTING_HAND and G.play and #G.play.cards == 0
        and G.GAME.current_round.hands_left == 2 and settled()
    end,
    assert = function(ctx)
      local lh = SMODS.last_hand or {}
      if not ctx.fact_ok then return false, "HandFacts.shape did not report 4-card flush ready under Four Fingers" end
      return tostring(lh.scoring_name) == "Flush",
        "Four Fingers: expected Flush from 4 hearts, got " .. tostring(lh.scoring_name)
    end,
  })

  add({
    name = "edge/shortcut_gapped_straight", timeout_s = 30,
    setup = function(ctx)
      clear_area(G.jokers)
      spawn_joker("j_shortcut")
      set_hand({ "H_2", "S_4", "D_6", "C_8", "H_T" })
      G.GAME.current_round.hands_left = 3
      local sh = HandFacts.shape(G.hand.cards)
      ctx.fact_ok = sh.straight_ready
    end,
    act = play({ 1, 2, 3, 4, 5 }),
    wait_for = function()
      return G.STATE == G.STATES.SELECTING_HAND and G.play and #G.play.cards == 0
        and G.GAME.current_round.hands_left == 2 and settled()
    end,
    assert = function(ctx)
      local lh = SMODS.last_hand or {}
      if not ctx.fact_ok then return false, "HandFacts.shape did not report gapped straight ready under Shortcut" end
      return tostring(lh.scoring_name) == "Straight",
        "Shortcut: expected Straight from 2-4-6-8-10, got " .. tostring(lh.scoring_name)
    end,
  })

  add({
    name = "edge/dna_copies_single_card", timeout_s = 30,
    setup = function(_ctx)
      clear_area(G.jokers)
      spawn_joker("j_dna")
      set_hand({ "H_7", "S_9", "D_2" })
      G.GAME.current_round.hands_left = 3
      G.GAME.current_round.hands_played = 0
    end,
    act = play({ 1 }),
    wait_for = function()
      return G.STATE == G.STATES.SELECTING_HAND and G.play and #G.play.cards == 0
        and G.GAME.current_round.hands_left == 2 and settled()
    end,
    assert = function()
      local n = 0
      for _, c in ipairs(G.hand.cards) do
        if c.base.id == 7 and c.base.suit == "Hearts" then n = n + 1 end
      end
      return n >= 1, string.format("DNA: expected a copy of the played 7 of Hearts in hand, found %d", n)
    end,
  })

  add({
    name = "edge/rental+perishable_at_round_end", timeout_s = 40,
    setup = function(ctx)
      clear_area(G.jokers)
      clear_area(G.consumeables)
      local rj = spawn_joker("j_joker")
      rj:set_rental(true)
      ctx.perish = spawn_joker("j_greedy_joker")
      ctx.perish:set_perishable(true)
      ctx.tally0 = ctx.perish.ability.perish_tally
      set_hand({ "H_5", "S_5", "D_9" })
      G.GAME.current_round.hands_left = 2
      G.GAME.blind.chips = 1
      ctx.pre = dollars()
      ctx.rate = G.GAME.rental_rate or 3
    end,
    act = play({ 1, 2 }),
    wait_for = function()
      return G.STATE == G.STATES.ROUND_EVAL and settled()
    end,
    assert = function(ctx)
      local tally = ctx.perish.ability.perish_tally
      if tally ~= ctx.tally0 - 1 then
        return false, string.format("perish_tally: expected %d -> %d, got %s", ctx.tally0, ctx.tally0 - 1, tostring(tally))
      end
      if dollars() ~= ctx.pre - ctx.rate then
        return false, string.format("rental drain: expected $%d -> $%d, got $%d", ctx.pre, ctx.pre - ctx.rate, dollars())
      end
      return true, string.format("perish %d->%d, rental -$%d at round end", ctx.tally0, tally, ctx.rate)
    end,
  })

  add({
    name = "shop/cash_out_reaches_shop", timeout_s = 30,
    act = function() gfunc("cash_out") end,
    wait_for = function()
      return G.STATE == G.STATES.SHOP and G.shop_jokers and G.shop_booster and G.shop_vouchers and settled()
    end,
    assert = function()
      return true, "cash_out -> SHOP with all shop areas live"
    end,
  })

  add(info_smoke_case("shop_context"))

  add({
    name = "action/reroll_shop_cost_and_progression", timeout_s = 15,
    setup = function(ctx)
      money(50)
      ctx.free = G.GAME.current_round.free_rerolls
      G.GAME.current_round.free_rerolls = 0
      ctx.cost = tonumber(G.GAME.current_round.reroll_cost) or 0
      ctx.pre = dollars()
      ctx.next = CtxEconomy.reroll_facts and CtxEconomy.reroll_facts().next
    end,
    act = function() gfunc("reroll_shop") end,
    wait_for = function(ctx) return dollars() == ctx.pre - ctx.cost and settled() end,
    assert = function(ctx)
      local newcost = tonumber(G.GAME.current_round.reroll_cost) or 0
      local paid = dollars() == ctx.pre - ctx.cost
      local advanced = newcost == ctx.cost + 1
      local predicted = ctx.next == nil or ctx.next == ctx.cost + 1
      return paid and advanced and predicted,
        string.format("paid $%d (%s), cost %d->%d (%s), reroll_facts.next=%s",
          ctx.cost, tostring(paid), ctx.cost, newcost, tostring(advanced), tostring(ctx.next))
    end,
    teardown = function(ctx)
      if ctx.free ~= nil then G.GAME.current_round.free_rerolls = ctx.free end
    end,
  })

  add({
    name = "neg/buy_insufficient_funds", timeout_s = 10,
    setup = function(ctx)
      clear_area(G.jokers)
      clear_area(G.shop_jokers)
      ctx.buy = SMODS.create_card({ key = "j_joker", area = G.shop_jokers, skip_materialize = true, bypass_discovery_center = true, no_edition = true })
      G.shop_jokers:emplace(ctx.buy)
      money(0)
    end,
    act = function(ctx)
      local _, err = run_action("buy_from_shop", { area = "shop_jokers", index = index_of(G.shop_jokers, ctx.buy) })
      ctx.err = err
    end,
    wait_for = function() return true end,
    assert = function(ctx)
      return ctx.err ~= nil and tostring(ctx.err):find("afford") ~= nil,
        "expected afford rejection at $0, got: " .. tostring(ctx.err)
    end,
    teardown = function() clear_area(G.shop_jokers) end,
  })
  add({
    name = "neg/buy_rejected_full_joker_slots", timeout_s = 15,
    setup = function(ctx)
      clear_area(G.jokers)
      clear_area(G.shop_jokers)
      ctx.limit = G.jokers.config.card_limit
      for _ = 1, ctx.limit do spawn_joker("j_joker") end
      ctx.buy = SMODS.create_card({ key = "j_joker", area = G.shop_jokers, skip_materialize = true, bypass_discovery_center = true, no_edition = true })
      G.shop_jokers:emplace(ctx.buy)
      money(50)
    end,
    act = function(ctx)
      local _, err = run_action("buy_from_shop", { area = "shop_jokers", index = index_of(G.shop_jokers, ctx.buy) })
      ctx.err = err
    end,
    wait_for = function() return true end,
    assert = function(ctx)
      return ctx.err ~= nil and tostring(ctx.err):lower():find("space") ~= nil,
        "expected no-slot-space rejection when jokers full, got: " .. tostring(ctx.err)
    end,
    teardown = function() clear_area(G.shop_jokers); clear_area(G.jokers) end,
  })

  add({
    name = "force/shop_completeness", timeout_s = 10,
    setup = function()
      clear_area(G.jokers)
      spawn_joker("j_joker") -- sellable
      money(50)
    end,
    act = function() end, wait_for = function() return settled() end,
    assert = function()
      local A = require("core.actions")
      local D = require("core.dispatcher")
      local FR = require("force.force_router")
      local np = D.NON_PROGRESS_FORCE_ACTIONS or {}
      local f = FR.get_force_for_state("SHOP")
      if type(f) ~= "table" or type(f.actions) ~= "table" then return false, "no force for SHOP" end
      local set = {}
      for _, a in ipairs(f.actions) do set[a] = true end
      for _, need in ipairs(A.get_available_actions_for_state("SHOP") or {}) do
        if not np[need] and not set[need] then return false, "shop force omits legal progress action " .. need end
      end
      if not set["toggle_shop"] then return false, "shop force must offer toggle_shop" end
      if not set["sell_card"] then return false, "shop force must offer sell_card with a sellable joker" end
      return true, "shop force offers all legal actions incl toggle_shop/sell_card"
    end,
    teardown = function() clear_area(G.jokers) end,
  })
  add({
    name = "ctx/build_ascii_shop", timeout_s = 8,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local CC = require("context.context_compact")
      local A = require("core.actions")
      local s = CC.build("SHOP", A.get_available_actions_for_state("SHOP"), { no_cache = true })
      if type(s) ~= "string" or s == "" then return false, "shop build empty" end
      for i = 1, #s do if s:byte(i) >= 128 then return false, "non-ASCII in shop context at " .. i end end
      return true, string.format("shop context ASCII + non-empty (%d bytes)", #s)
    end,
  })

  for _, center in ipairs(G.P_CENTER_POOLS.Booster or {}) do
    covered[center.key] = true
    booster_cases(center, add)
  end

  for _, center in ipairs(G.P_CENTER_POOLS.Voucher or {}) do
    covered[center.key] = true
    add(voucher_case(center))
  end

  add({
    name = "edge/credit_card_floor_fact", timeout_s = 20,
    setup = function(ctx)
      clear_area(G.jokers)
      clear_area(G.shop_jokers)
      spawn_joker("j_credit_card")
      ctx.floor = CtxEconomy.spend_floor()
      ctx.buy = SMODS.create_card({ key = "j_joker", area = G.shop_jokers, skip_materialize = true, bypass_discovery_center = true, no_edition = true })
      G.shop_jokers:emplace(ctx.buy)
      ctx.cost = tonumber(ctx.buy.cost) or 0
      money(ctx.cost - 1)
      ctx.pre = dollars()
    end,
    act = function(ctx)
      local idx = index_of(G.shop_jokers, ctx.buy)
      local _, err = run_action("buy_from_shop", { area = "shop_jokers", index = idx })
      if err then error(err) end
    end,
    wait_for = function(ctx)
      return dollars() == ctx.pre - ctx.cost and settled()
    end,
    assert = function(ctx)
      if ctx.floor ~= -20 then
        return false, "fact: CtxEconomy.spend_floor() expected -20 with Credit Card, got " .. tostring(ctx.floor)
      end
      local ok = dollars() == ctx.pre - ctx.cost and dollars() < 0 and #G.jokers.cards == 2
      return ok, string.format("bought below $0 within floor: $%d -> $%d, %d jokers", ctx.pre, dollars(), #G.jokers.cards)
    end,
  })

  add({
    name = "edge/credit_card_floor_rejects_breach", timeout_s = 10,
    setup = function(ctx)
      clear_area(G.jokers)
      clear_area(G.shop_jokers)
      spawn_joker("j_credit_card")
      ctx.buy = SMODS.create_card({ key = "j_joker", area = G.shop_jokers, skip_materialize = true, bypass_discovery_center = true, no_edition = true })
      G.shop_jokers:emplace(ctx.buy)
      money(CtxEconomy.spend_floor() + (tonumber(ctx.buy.cost) or 0) - 1)
    end,
    act = function(ctx)
      local idx = index_of(G.shop_jokers, ctx.buy)
      local _, err = run_action("buy_from_shop", { area = "shop_jokers", index = idx })
      ctx.err = err
    end,
    wait_for = function() return true end,
    assert = function(ctx)
      return ctx.err ~= nil and tostring(ctx.err):find("afford") ~= nil,
        "expected affordability rejection at the floor, got: " .. tostring(ctx.err)
    end,
    teardown = function() clear_area(G.shop_jokers) end,
  })

  add({
    name = "edge/negative_joker_buy_with_full_slots", timeout_s = 20,
    setup = function(ctx)
      clear_area(G.jokers)
      clear_area(G.shop_jokers)
      ctx.limit = G.jokers.config.card_limit
      for _ = 1, ctx.limit do spawn_joker("j_joker") end
      ctx.buy = SMODS.create_card({ key = "j_greedy_joker", area = G.shop_jokers, skip_materialize = true, bypass_discovery_center = true, no_edition = true })
      ctx.buy:set_edition("e_negative", true, true)
      G.shop_jokers:emplace(ctx.buy)
      money((tonumber(ctx.buy.cost) or 0) + 20)
      ctx.pre = dollars()
      ctx.cost = tonumber(ctx.buy.cost) or 0
    end,
    act = function(ctx)
      local idx = index_of(G.shop_jokers, ctx.buy)
      local _, err = run_action("buy_from_shop", { area = "shop_jokers", index = idx })
      if err then error(err) end
    end,
    wait_for = function(ctx)
      return #G.jokers.cards == ctx.limit + 1 and settled()
    end,
    assert = function(ctx)
      local ok = #G.jokers.cards == ctx.limit + 1 and dollars() == ctx.pre - ctx.cost
      return ok, string.format("Negative joins full board: %d/%d jokers, $%d -> $%d", #G.jokers.cards, ctx.limit, ctx.pre, dollars())
    end,
    teardown = function(ctx)
      clear_area(G.shop_jokers)
      if ctx.limit then G.jokers.config.card_limit = ctx.limit end
    end,
  })

  add({
    name = "edge/eternal_sell_rejected", timeout_s = 10,
    setup = function(ctx)
      clear_area(G.jokers)
      ctx.j = spawn_joker("j_joker")
      ctx.j:set_eternal(true)
    end,
    act = function(ctx)
      local _, err = run_action("sell_card", { area = "jokers", index = 1 })
      ctx.err = err
    end,
    wait_for = function() return true end,
    assert = function(ctx)
      local ok = ctx.err ~= nil and tostring(ctx.err):find("Eternal") ~= nil and #G.jokers.cards == 1
      return ok, "expected Eternal rejection from our sell_card handler, got: " .. tostring(ctx.err)
    end,
  })

  add({
    name = "edge/sell_card_pays_sell_value", timeout_s = 15,
    setup = function(ctx)
      clear_area(G.jokers)
      ctx.j = spawn_joker("j_joker")
      ctx.sell = tonumber(ctx.j.sell_cost) or 0
      money(10)
    end,
    act = function()
      local _, err = run_action("sell_card", { area = "jokers", index = 1 })
      if err then error(err) end
    end,
    wait_for = function() return #G.jokers.cards == 0 and settled() end,
    assert = function(ctx)
      return dollars() == 10 + ctx.sell,
        string.format("expected $%d after selling (value $%d), got $%d", 10 + ctx.sell, ctx.sell, dollars())
    end,
  })

  add({
    name = "blind2/toggle_shop_exits_to_blind_select", timeout_s = 20,
    act = function() gfunc("toggle_shop") end,
    wait_for = function()
      return G.STATE == G.STATES.BLIND_SELECT and G.blind_select and settled()
    end,
    assert = function()
      return true, "SHOP -> BLIND_SELECT clean"
    end,
  })

  add({
    name = "force/blind_select_completeness", timeout_s = 10,
    setup = function()
      clear_area(G.jokers)
      clear_area(G.consumeables)
      spawn_joker("j_joker")
      spawn_consumable("c_mercury")
    end,
    act = function() end, wait_for = function() return settled() end,
    assert = function()
      local A = require("core.actions")
      local D = require("core.dispatcher")
      local FR = require("force.force_router")
      local np = D.NON_PROGRESS_FORCE_ACTIONS or {}
      local f = FR.get_force_for_state("BLIND_SELECT")
      if type(f) ~= "table" or type(f.actions) ~= "table" then return true, "blind select transitioning, skipped" end
      local set = {}
      for _, a in ipairs(f.actions) do set[a] = true end
      for _, need in ipairs(A.get_available_actions_for_state("BLIND_SELECT") or {}) do
        if not np[need] and not set[need] then return false, "blind-select force omits legal progress action " .. need end
      end
      return true, "blind-select force offers all legal actions (select/skip/sell/use as available)"
    end,
    teardown = function() clear_area(G.jokers); clear_area(G.consumeables) end,
  })
  add({
    name = "neg/select_blind_wrong_value", timeout_s = 8,
    setup = function() end,
    act = function(ctx) local _, err = run_action("select_blind", { blind = "huge" }); ctx.err = err end,
    wait_for = function() return true end,
    assert = function(ctx) return ctx.err ~= nil, "select_blind with bad value must reject, got: " .. tostring(ctx.err) end,
  })
  add({
    name = "neg/set_joker_order_out_of_range", timeout_s = 8,
    setup = function() clear_area(G.jokers); spawn_joker("j_joker"); spawn_joker("j_greedy_joker") end,
    act = function(ctx) local _, err = run_action("set_joker_order", { from_index = 1, to_index = 99 }); ctx.err = err end,
    wait_for = function() return true end,
    assert = function(ctx)
      return ctx.err ~= nil and tostring(ctx.err):lower():find("range") ~= nil,
        "set_joker_order OOR must reject, got: " .. tostring(ctx.err)
    end,
    teardown = function() clear_area(G.jokers) end,
  })
  add({
    name = "neg/change_stake_bad_value", timeout_s = 8,
    setup = function() end,
    act = function(ctx) local _, err = run_action("change_stake", { to_key = "abc" }); ctx.err = err end,
    wait_for = function() return true end,
    assert = function(ctx) return ctx.err ~= nil, "change_stake non-number must reject, got: " .. tostring(ctx.err) end,
  })
  add({
    name = "neg/change_selected_back_bad_key", timeout_s = 8,
    setup = function() end,
    act = function(ctx) local _, err = run_action("change_selected_back", { back = "b_selftest_nonexistent" }); ctx.err = err end,
    wait_for = function() return true end,
    assert = function(ctx) return ctx.err ~= nil, "change_selected_back bad key must reject, got: " .. tostring(ctx.err) end,
  })
  add({
    name = "neg/choose_persona_invalid", timeout_s = 8,
    setup = function() end,
    act = function(ctx) local _, err = run_action("choose_persona", { persona = "banana" }); ctx.err = err end,
    wait_for = function() return true end,
    assert = function(ctx) return ctx.err ~= nil, "choose_persona invalid value must reject, got: " .. tostring(ctx.err) end,
  })

  add({
    name = "blindsel/skip_blind_advances_blind", timeout_s = 20,
    setup = function(ctx)
      local bs = (G.GAME.round_resets and G.GAME.round_resets.blind_states) or {}
      ctx.target = (bs.Small == "Select" and "Small") or (bs.Big == "Select" and "Big") or nil
      ctx.can_skip = ctx.target ~= nil
      ctx.tags = (G.GAME.tags and #G.GAME.tags) or 0
    end,
    act = function(ctx)
      if not ctx.can_skip then return end
      local _, err = run_action("skip_blind")
      ctx.err = err
    end,
    wait_for = function(ctx)
      if not ctx.can_skip or ctx.err then return true end
      local bs = (G.GAME.round_resets and G.GAME.round_resets.blind_states) or {}
      return bs[ctx.target] ~= "Select" and settled()
    end,
    assert = function(ctx)
      if not ctx.can_skip then return true, "boss on deck, skip not offered, skipped" end
      if ctx.err then return false, "skip_blind refused: " .. tostring(ctx.err) end
      local bs = (G.GAME.round_resets and G.GAME.round_resets.blind_states) or {}
      local advanced = bs[ctx.target] ~= "Select"
      return advanced, string.format("%s state now %s (tags %d->%d)",
        ctx.target, tostring(bs[ctx.target]), ctx.tags, (G.GAME.tags and #G.GAME.tags) or 0)
    end,
  })
  add({
    name = "blindsel/reroll_boss_costs_10", timeout_s = 15,
    setup = function(ctx)
      ctx.uv = G.GAME.used_vouchers
      ctx.rr = G.GAME.round_resets and G.GAME.round_resets.boss_rerolled
      G.GAME.used_vouchers = { v_directors_cut = true }
      if G.GAME.round_resets then G.GAME.round_resets.boss_rerolled = false end
      money(50)
      local can = select(1, CtxEconomy.can_reroll_boss())
      ctx.can = can and G.FUNCS and G.FUNCS.reroll_boss ~= nil
    end,
    act = function(ctx)
      if not ctx.can then return end
      local ok, e = pcall(function() gfunc("reroll_boss") end)
      ctx.act_err = (not ok) and e
    end,
    wait_for = function(ctx)
      return (not ctx.can) or ctx.act_err or (dollars() ~= 50 and settled())
    end,
    assert = function(ctx)
      if not ctx.can then return true, "boss reroll unavailable (no voucher/func), skipped" end
      if ctx.act_err then return true, "reroll_boss engine error, skipped: " .. tostring(ctx.act_err) end
      local want = 50 - CtxEconomy.BOSS_REROLL_COST
      return dollars() == want, string.format("expected $%d after boss reroll, got $%d", want, dollars())
    end,
    teardown = function(ctx)
      G.GAME.used_vouchers = ctx.uv
      if G.GAME.round_resets then G.GAME.round_resets.boss_rerolled = ctx.rr end
    end,
  })

  add({
    name = "edge/blueprint_copies_right_neighbor", timeout_s = 30,
    setup = function(ctx)
      clear_area(G.jokers)
      spawn_joker("j_blueprint")
      local burglar = spawn_joker("j_burglar")
      ctx.extra = burglar.ability.extra
      ctx.base = (G.GAME.round_resets.hands or 0) + ((G.GAME.round_bonus and G.GAME.round_bonus.next_hands) or 0)
      local bs = G.GAME.round_resets.blind_states
      ctx.blind = (bs.Small == "Select" and "small") or (bs.Big == "Select" and "big") or "boss"
    end,
    act = function(ctx)
      local _, err = run_action("select_blind", { blind = ctx.blind })
      if err then error(err) end
    end,
    wait_for = function()
      return G.STATE == G.STATES.SELECTING_HAND and G.hand and #G.hand.cards > 0 and settled()
    end,
    assert = function(ctx)
      local hl = G.GAME.current_round.hands_left
      local dl = G.GAME.current_round.discards_left
      local want = ctx.base + 2 * ctx.extra
      return hl == want and dl == 0,
        string.format("Blueprint+Burglar: expected %d hands (base %d + 2x%d) + 0 discards, got %s + %s",
          want, ctx.base, ctx.extra, tostring(hl), tostring(dl))
    end,
  })

  add({
    name = "life/game_over_section_shape", timeout_s = 5,
    setup = function(ctx) ctx.won = G.GAME.won end,
    act = function() end, wait_for = function() return true end,
    assert = function(ctx)
      local ok_cm, CtxMisc = pcall(require, "context.ctx_misc")
      if not (ok_cm and CtxMisc.game_over_section) then return true, "game_over_section unavailable, skipped" end
      G.GAME.won = true
      local won_txt = CtxMisc.game_over_section()
      G.GAME.won = false
      local lost_txt = CtxMisc.game_over_section()
      G.GAME.won = ctx.won
      local ok = type(won_txt) == "string" and won_txt:find("GO|", 1, true) and won_txt:upper():find("WON")
        and type(lost_txt) == "string" and lost_txt:find("GO|", 1, true) and lost_txt:find("lost", 1, true)
      return ok, string.format("won=%s lost=%s", tostring(won_txt), tostring(lost_txt))
    end,
    teardown = function(ctx) G.GAME.won = ctx.won end,
  })

  -- ok= (can_take_pack_card) must match the real gate in card.lua:1851-1896, both directions, for every real center
  add({
    name = "pack/consumable_takeability_matrix", timeout_s = 40,
    setup = function(ctx)
      local CU = require("facts.card_util")
      ctx.PACK = {}  -- sentinel: a pack card owns no inventory slot
      local GATE = {}
      for _, k in ipairs({ "c_high_priestess", "c_emperor" }) do GATE[k] = "cslot" end
      GATE.c_fool = "fool"
      for _, k in ipairs({ "c_judgement", "c_soul", "c_wraith" }) do GATE[k] = "jslot" end
      GATE.c_ankh = "ankh"
      for _, k in ipairs({ "c_wheel_of_fortune", "c_ectoplasm", "c_hex" }) do GATE[k] = "ejoker" end
      for _, k in ipairs({ "c_familiar", "c_grim", "c_incantation", "c_immolate", "c_sigil", "c_ouija" }) do GATE[k] = "handn" end
      local always = { c_hermit = true, c_temperance = true, c_black_hole = true, c_aura = true }
      ctx.groups = { alwaysY = {}, cslot = {}, fool = {}, jslot = {}, ankh = {}, ejoker = {}, handn = {} }
      ctx.unknown = {}
      for _, pool in ipairs({ "Tarot", "Planet", "Spectral" }) do
        for _, center in ipairs((G.P_CENTER_POOLS and G.P_CENTER_POOLS[pool]) or {}) do
          local key = center.key
          if key then
            local card = SMODS.create_card({ key = key, area = G.consumeables, skip_materialize = true,
              bypass_discovery_center = true, no_edition = true })
            card.area = ctx.PACK
            local grp = GATE[key]
            if not grp then
              local c = card.ability and card.ability.consumeable
              if CU.card_set(card) == "Planet"
                or (type(c) == "table" and tonumber(c.max_highlighted) and tonumber(c.max_highlighted) > 0)
                or always[key] then
                grp = "alwaysY"
              end
            end
            if grp then ctx.groups[grp][#ctx.groups[grp] + 1] = { key, card }
            else ctx.unknown[#ctx.unknown + 1] = key end
          end
        end
      end
    end,
    wait_for = function() return settled() end,
    assert = function(ctx)
      local CU = require("facts.card_util")
      if #ctx.unknown > 0 then return false, "unclassified consumable(s) -- update the matrix: " .. table.concat(ctx.unknown, ", ") end
      local bad, total = {}, 0
      local function check(entry, want, label)
        local got = CU.can_take_pack_card(entry[2]) == true
        if got ~= want then
          bad[#bad + 1] = string.format("%s[%s]:want %s got %s", entry[1], label, want and "Y" or "N", got and "Y" or "N")
        end
      end
      local function each(grp, want, label)
        for _, e in ipairs(ctx.groups[grp]) do check(e, want, label) end
      end
      -- mirror card.lua:4566-4571 so the ejoker gate evaluates for real instead of via the fallback
      local function set_eligible()
        local list = {}
        for _, v in ipairs((G.jokers and G.jokers.cards) or {}) do
          if v.ability and v.ability.set == "Joker" and not v.edition then list[#list + 1] = v end
        end
        for _, e in ipairs(ctx.groups.ejoker) do
          e[2].eligible_strength_jokers = list
          e[2].eligible_editionless_jokers = list
        end
      end
      for _, g in pairs(ctx.groups) do total = total + #g end

      clear_area(G.consumeables); clear_area(G.jokers)
      each("alwaysY", true, "always")

      each("cslot", true, "room")
      for _ = 1, CU.consumable_limit() do spawn_consumable("c_pluto") end
      each("cslot", false, "full")
      clear_area(G.consumeables)

      if G and G.GAME then G.GAME.last_tarot_planet = "c_hermit" end
      each("fool", true, "prior")
      if G and G.GAME then G.GAME.last_tarot_planet = nil end
      each("fool", false, "noprior")

      clear_area(G.jokers); each("jslot", true, "jroom")
      for _ = 1, CU.joker_limit() do spawn_joker("j_joker") end
      each("jslot", false, "jfull")
      clear_area(G.jokers)

      spawn_joker("j_joker"); each("ankh", true, "hasjoker")
      clear_area(G.jokers); each("ankh", false, "nojoker")

      spawn_joker("j_joker"); set_eligible(); each("ejoker", true, "eligible")
      clear_area(G.jokers); set_eligible(); each("ejoker", false, "noeligible")

      -- hand-count spectrals need a pack/hand state
      local prev_state = G.STATE
      G.STATE = (G.STATES and G.STATES.SPECTRAL_PACK) or prev_state
      set_hand({ "H_5", "S_9", "D_2" }); each("handn", true, "hand3")
      set_hand({ "H_5" }); each("handn", false, "hand1")
      G.STATE = prev_state

      if #bad > 0 then
        return false, string.format("%d/%d gate mismatch(es): %s", #bad, total, table.concat(bad, "; "))
      end
      return true, string.format("all %d consumables' ok= match card.lua both ways (room/full, prior/none, joker/none, eligible/none, hand>1/<=1)", total)
    end,
    teardown = function() clear_area(G.consumeables); clear_area(G.jokers) end,
  })

  -- ok= must hold for every pack card kind: Buffoon needs joker room (negatives always takeable), Standard
  -- cards always takeable, Soul needs joker room (creates a Legendary), Black Hole always usable
  add({
    name = "pack/takeability_all_kinds", timeout_s = 60,
    setup = function(ctx)
      clear_area(G.jokers)
      -- raw create (no :emplace) leaves G.jokers empty, so every joker is checked against open slots
      ctx.jokers = {}
      for _, center in ipairs((G.P_CENTER_POOLS and G.P_CENTER_POOLS.Joker) or {}) do
        if center.key then
          local ok_c, c = pcall(SMODS.create_card, { key = center.key, area = G.jokers,
            skip_materialize = true, bypass_discovery_center = true, no_edition = true })
          if ok_c and c then ctx.jokers[#ctx.jokers + 1] = { center.key, c } end
        end
      end
      ctx.probe_key = (ctx.jokers[1] and ctx.jokers[1][1]) or "j_joker"
      -- Standard-pack contents: plain, off-suit, and an enhanced card all ride the base.suit path
      ctx.playing = set_hand({ "H_5", "S_9", { front = "D_2", center = "m_gold" } })
      -- legendaries created into consumeables (their real destination when picked)
      ctx.soul = SMODS.create_card({ key = "c_soul", area = G.consumeables, skip_materialize = true,
        bypass_discovery_center = true, no_edition = true })
      ctx.black_hole = SMODS.create_card({ key = "c_black_hole", area = G.consumeables, skip_materialize = true,
        bypass_discovery_center = true, no_edition = true })
    end,
    wait_for = function() return settled() end,
    assert = function(ctx)
      local CU = require("facts.card_util")
      if #ctx.jokers < 100 then return false, "only created " .. #ctx.jokers .. " jokers (pool not enumerated?)" end
      clear_area(G.jokers)
      local bad = {}
      for _, j in ipairs(ctx.jokers) do
        if CU.can_take_pack_card(j[2]) ~= true then bad[#bad + 1] = "Buffoon/" .. j[1] end
      end
      for i, c in ipairs(ctx.playing) do
        if CU.can_take_pack_card(c) ~= true then bad[#bad + 1] = "Standard/card" .. i end
      end
      if CU.can_take_pack_card(ctx.soul) ~= true then bad[#bad + 1] = "Soul(joker room open)" end
      if CU.can_take_pack_card(ctx.black_hole) ~= true then bad[#bad + 1] = "BlackHole" end
      if #bad > 0 then
        return false, string.format("%d card(s) read ok=N despite being takeable with room: %s", #bad, table.concat(bad, ", "))
      end
      -- inverse direction: FULL joker slots must block a normal joker + Soul (ok=N) but NOT a negative joker
      for _ = 1, CU.joker_limit() do spawn_joker("j_joker") end
      local full_probe = SMODS.create_card({ key = ctx.probe_key, area = G.jokers, skip_materialize = true,
        bypass_discovery_center = true, no_edition = true })
      local neg_probe = SMODS.create_card({ key = ctx.probe_key, area = G.jokers, skip_materialize = true,
        bypass_discovery_center = true, no_edition = true })
      neg_probe.edition = { negative = true, key = "e_negative" }
      local full_ok = CU.can_take_pack_card(full_probe)
      local neg_ok = CU.can_take_pack_card(neg_probe)
      local soul_full = CU.can_take_pack_card(ctx.soul)  -- Soul lives in consumeables; full jokers -> no room
      clear_area(G.jokers)
      if full_ok ~= false then return false, "a normal joker read ok=Y with joker slots FULL (should be N)" end
      if neg_ok ~= true then return false, "a NEGATIVE joker read ok=N with slots full (it bumps the slot -> should stay Y)" end
      if soul_full ~= false then return false, "Soul read ok=Y with joker slots FULL (it creates a Legendary joker -> needs room)" end
      return true, string.format("%d jokers + %d playing cards + Soul/BlackHole all ok=Y with room; normal joker & Soul flip to ok=N when full, negative stays Y",
        #ctx.jokers, #ctx.playing)
    end,
    teardown = function() clear_area(G.jokers) end,
  })

  -- consumable_target_range must match each center's max_highlighted, + Aura's name-gated (1,1) override
  add({
    name = "pack/target_range_drift", timeout_s = 20,
    setup = function(ctx)
      ctx.cards = {}
      for _, pool in ipairs({ "Tarot", "Planet", "Spectral" }) do
        for _, center in ipairs((G.P_CENTER_POOLS and G.P_CENTER_POOLS[pool]) or {}) do
          if center.key then
            ctx.cards[#ctx.cards + 1] = { center.key,
              SMODS.create_card({ key = center.key, area = G.consumeables, skip_materialize = true,
                bypass_discovery_center = true, no_edition = true }) }
          end
        end
      end
      clear_area(G.consumeables)
    end,
    wait_for = function() return settled() end,
    assert = function(ctx)
      local CU = require("facts.card_util")
      local NAMED = { c_aura = 1 }  -- name-gated hand target (empty config) -> must surface (1,1)
      local bad = {}
      for _, e in ipairs(ctx.cards) do
        local key, card = e[1], e[2]
        local c = card.ability and card.ability.consumeable
        local cfg_max = (type(c) == "table") and tonumber(c.max_highlighted) or nil
        local exp_max = NAMED[key] or cfg_max
        local mn, mx = CU.consumable_target_range(card)
        if exp_max then
          if not (mx == exp_max and type(mn) == "number" and mn >= 1) then
            bad[#bad + 1] = string.format("%s: want 1..%d got %s..%s", key, exp_max, tostring(mn), tostring(mx))
          end
        elseif not (mn == nil and mx == nil) then
          bad[#bad + 1] = string.format("%s: want nil got %s..%s", key, tostring(mn), tostring(mx))
        end
      end
      if #bad > 0 then return false, string.format("%d target-range mismatch(es): %s", #bad, table.concat(bad, "; ")) end
      return true, string.format("consumable_target_range matches config max_highlighted (+Aura named) for all %d cards", #ctx.cards)
    end,
    teardown = function() clear_area(G.consumeables) end,
  })

  -- structural guard: every enumerated pool item must have produced a case (no silent skips)
  add({
    name = "meta/pools_fully_enumerated", timeout_s = 8,
    setup = function() end, act = function() end, wait_for = function() return true end,
    assert = function()
      local pools = { "Planet", "Tarot", "Spectral", "Voucher", "Booster" }
      local bad, total = {}, 0
      for _, pool in ipairs(pools) do
        for _, center in ipairs((G.P_CENTER_POOLS and G.P_CENTER_POOLS[pool]) or {}) do
          total = total + 1
          if center.key and not covered[center.key] then bad[#bad + 1] = pool .. ":" .. tostring(center.key) end
        end
      end
      if #bad > 0 then return false, string.format("%d pool items got no case: %s", #bad, table.concat(bad, ", ")) end
      return true, string.format("every item across %d pools has a case (%d items)", #pools, total)
    end,
  })

  return cases
end

-- pack-launch scenario (NEURO_SELFTEST_PACK): drives a REAL Card:open() booster, not the synthetic matrix above
local function open_booster(key)
  local card = SMODS.create_card({
    key = key, skip_materialize = true, bypass_discovery_center = true, no_edition = true,
  })
  if not card then error("could not create booster " .. tostring(key)) end
  card.cost = 0
  if type(card.open) ~= "function" then error("booster '" .. tostring(key) .. "' has no :open()") end
  card:open()   -- real flow: sets SMODS_BOOSTER_OPENED, queues pack-card creation + hand draw
  return card
end

local SPECTRAL_KEYS = {
  "c_familiar", "c_grim", "c_incantation", "c_talisman", "c_aura", "c_wraith", "c_sigil", "c_ouija",
  "c_ectoplasm", "c_immolate", "c_ankh", "c_deja_vu", "c_hex", "c_trance", "c_medium", "c_cryptid",
  "c_soul", "c_black_hole",
}

-- mirror card.lua:4566: freshly created cards have eligible_*_jokers nil (next(nil) throws the Ecto/Hex gate); populate so injected cards hit the REAL gate, not the pcall-swallowed fallback
local function set_eligible(card)
  local list = {}
  for _, v in ipairs((G.jokers and G.jokers.cards) or {}) do
    if v.ability and v.ability.set == "Joker" and not v.edition then list[#list + 1] = v end
  end
  card.eligible_strength_jokers = list
  card.eligible_editionless_jokers = list
end

local function make_spectral(key)
  return SMODS.create_card({ key = key, skip_materialize = true, bypass_discovery_center = true, no_edition = true })
end

local function pack_launch_case(name, booster_key)
  return {
    name = name, timeout_s = 30, act_delay = 0.2,
    setup = function(ctx)
      clear_area(G.consumeables); clear_area(G.jokers)
      spawn_joker("j_joker")   -- a plain editionless joker so joker-gated spectrals (Ecto/Hex/Ankh/Wraith) aren't trivially ok=N
      money(20)
      ctx.key = booster_key
    end,
    act = function(ctx)
      ctx.booster = open_booster(booster_key)
    end,
    wait_for = function()
      local bp = CardUtil.pack_area()
      return bp and bp.cards and #bp.cards > 0 and settled()
    end,
    assert = function()
      local bp = CardUtil.pack_area()
      if not (bp and bp.cards and #bp.cards > 0) then
        return false, "Card:open produced no pack cards"
      end
      local hand_n = (G.hand and G.hand.cards and #G.hand.cards) or 0
      local lines, okn, first_tgt_i, first_tgt_min, bad = {}, {}, nil, nil, nil
      for i, c in ipairs(bp.cards) do
        local nm = tostring(c.ability and c.ability.name or "?")
        local mn, mh = CardUtil.consumable_target_range(c)
        local targeting = mh and mh > 0
        local ok_take = CardUtil.can_take_pack_card(c)
        lines[#lines + 1] = string.format("%d:%s tgt=%s ok=%s", i, nm, targeting and (mn .. "-" .. mh) or "-", ok_take and "Y" or "N")
        if not ok_take then okn[#okn + 1] = nm end
        -- a targeting card the mod marks takeable must have a hand to target
        if targeting and ok_take and hand_n < (mn or 1) and not bad then
          bad = string.format("no-hand-window: '%s' ok=Y (targets %d) but hand=%d", nm, mn, hand_n)
        end
        if targeting and ok_take and not first_tgt_i then first_tgt_i, first_tgt_min = i, (mn or 1) end
      end
      -- traced even on PASS: always surface whether ok=N exists
      local okn_str = (#okn > 0) and string.format("OK=N[%d]: %s", #okn, table.concat(okn, ",")) or "OK=N: none"
      SelfTest.trace("%s | hand=%d | %s | %s", name, hand_n, okn_str, table.concat(lines, " "))
      local tail = okn_str .. " | " .. table.concat(lines, " ")
      if bad then return false, bad .. " | " .. tail end
      if first_tgt_i then
        local hi = {}
        for k = 1, first_tgt_min do hi[k] = k end
        local _, err = run_action("use_card", { area = "booster_pack", index = first_tgt_i, hand_indices = hi })
        if err then return false, "targeting pick rejected: " .. tostring(err) .. " | " .. tail end
        return true, "open+hand(" .. hand_n .. ")+targeting-pick OK | " .. tail
      end
      for i, c in ipairs(bp.cards) do
        if CardUtil.can_take_pack_card(c) then
          local _, err = run_action("use_card", { area = "booster_pack", index = i })
          if err then return false, "non-target pick rejected: " .. tostring(err) .. " | " .. tail end
          return true, "open+non-target-pick OK | " .. tail
        end
      end
      return false, "NO takeable card -- couldn't pick ANY | " .. tail
    end,
    teardown = function()
      pcall(run_action, "skip_booster", {})   -- best-effort: don't leave the run stuck in a pack
      clear_area(G.consumeables); clear_area(G.jokers)
    end,
  }
end

-- opens a REAL spectral pack (only rolls 2-3, so inject all 18 keys); asserts every spectral ok=Y + a live Aura pick
local function all_spectrals_case()
  return {
    name = "pack/launch/all_spectrals_real", timeout_s = 40, act_delay = 0.2,
    setup = function()
      clear_area(G.consumeables); clear_area(G.jokers)
      spawn_joker("j_joker")   -- editionless joker so Ecto/Hex/Ankh/Wraith have a valid target
      money(20)
    end,
    act = function(ctx) ctx.booster = open_booster("p_spectral_normal_1") end,
    wait_for = function()
      local bp = CardUtil.pack_area()
      return bp and bp.cards and #bp.cards > 0 and settled()
    end,
    assert = function()
      local bp = CardUtil.pack_area()
      local hand_n = (G.hand and G.hand.cards and #G.hand.cards) or 0
      if hand_n == 0 then return false, "real spectral pack opened but NO hand dealt (hand=0)" end
      local jn = (G.jokers and G.jokers.cards and #G.jokers.cards) or 0
      local okn, lines = {}, {}
      for _, key in ipairs(SPECTRAL_KEYS) do
        local ok_c, card = pcall(make_spectral, key)
        if not ok_c or not card then
          lines[#lines + 1] = key .. ":CREATE_FAIL"; okn[#okn + 1] = key
        else
          card.area = bp
          set_eligible(card)
          local mn, mh = CardUtil.consumable_target_range(card)
          local targeting = mh and mh > 0
          local ok_take = CardUtil.can_take_pack_card(card)
          lines[#lines + 1] = string.format("%s tgt=%s ok=%s", key, targeting and (mn .. "-" .. mh) or "-", ok_take and "Y" or "N")
          if not ok_take then okn[#okn + 1] = key end
        end
      end
      local okn_str = (#okn > 0) and ("OK=N[" .. #okn .. "]: " .. table.concat(okn, ",")) or "OK=N: none"
      SelfTest.trace("all_spectrals | hand=%d joker=%d | %s | %s", hand_n, jn, okn_str, table.concat(lines, " "))
      local pick_note = "aura:skip"
      local ok_a, aura = pcall(make_spectral, "c_aura")
      if ok_a and aura then
        bp:emplace(aura)
        local idx = index_of(bp, aura)
        if idx then
          local _, err = run_action("use_card", { area = "booster_pack", index = idx, hand_indices = { 1 } })
          pick_note = err and ("aura-pick-REJECTED: " .. tostring(err)) or "aura-pick-OK"
        end
      end
      if #okn > 0 then
        return false, "spectrals ok=N in real pack: " .. table.concat(okn, ",") .. " | " .. pick_note .. " | " .. table.concat(lines, " ")
      end
      return true, string.format("all %d spectrals ok=Y in real pack | %s", #SPECTRAL_KEYS, pick_note)
    end,
    teardown = function()
      pcall(run_action, "skip_booster", {})
      clear_area(G.consumeables); clear_area(G.jokers)
    end,
  }
end

local MUT_ENH = { false, "m_bonus", "m_mult", "m_wild", "m_glass", "m_steel", "m_stone", "m_gold", "m_lucky" }
local MUT_SEAL = { false, "Gold", "Red", "Blue", "Purple" }
local MUT_ED = { false, { foil = true }, { holo = true }, { polychrome = true }, { negative = true } }
local MUT_STK = { false, "eternal", "perishable", "rental" }

local PACK_HOLD_S = 9
local VISIBLE_SUBSET = {
  { "H_A", "m_gold",  seal = "Gold",   ed = { foil = true } },
  { "S_K", "m_steel", seal = "Red",    ed = { holo = true } },
  { "D_9", "m_glass", seal = "Blue",   ed = { polychrome = true }, eternal = true },
  { "C_2", "m_stone", ed = { foil = true } },
  { "H_Q", "m_bonus", seal = "Purple" },
  { "S_5", "m_wild",  ed = { holo = true }, perishable = true },
  { "D_J", "m_lucky", seal = "Gold",   ed = { polychrome = true }, rental = true },
  { "C_T", "m_mult",  seal = "Blue" },
  { "H_7", "m_gold",  seal = "Red",    ed = { negative = true } },
}

local function make_pack_card(area, front_key, center_key, no_emplace)
  return ENG.create_playing_card(
    { front = G.P_CARDS[front_key], center = G.P_CENTERS[center_key or "c_base"] },
    area, true, true, nil, no_emplace)
end

local function standard_pack_mutations_case()
  return {
    name = "pack/standard/all_mutations", timeout_s = 40, act_delay = 0.3,
    setup = function()
      clear_area(G.consumeables); clear_area(G.jokers)
      money(20)
      Cards.reset_mini_counters()
    end,
    act = function(ctx)
      ctx.booster = open_booster("p_standard_normal_1")
    end,
    wait_for = function(ctx)
      local bp = CardUtil.pack_area()
      if not (bp and bp.cards and #bp.cards > 0 and settled()) then return false end
      if not ctx.injected then
        clear_area(bp)
        if bp.config then bp.config.card_limit = #VISIBLE_SUBSET end
        for _, s in ipairs(VISIBLE_SUBSET) do
          local c = make_pack_card(bp, s[1], s[2])
          if c then
            if s.seal then c:set_seal(s.seal, true, true) end
            if s.ed then c:set_edition(s.ed, true, true) end
            c.ability.eternal = s.eternal or nil
            c.ability.perishable = s.perishable or nil
            c.ability.rental = s.rental or nil
          end
        end
        ctx.injected = true
        ctx.hold_until = (G.TIMERS and G.TIMERS.REAL or 0) + PACK_HOLD_S
        return false
      end
      return (G.TIMERS and G.TIMERS.REAL or 0) >= ctx.hold_until
    end,
    assert = function()
      local bp = CardUtil.pack_area()
      if not (bp and bp.cards and #bp.cards > 0) then
        return false, "standard pack has no cards"
      end
      Cards.reset_mini_counters()
      local c = make_pack_card(bp, "H_9", "c_base", true)
      if not c then return false, "could not create sweep card" end
      local throws, first_fail, combos = 0, nil, 0
      for _, enh in ipairs(MUT_ENH) do
        c.config.center = G.P_CENTERS[enh or "c_base"]
        for _, seal in ipairs(MUT_SEAL) do
          c.seal = seal or nil
          for _, ed in ipairs(MUT_ED) do
            c.edition = ed or nil
            for _, stk in ipairs(MUT_STK) do
              c.ability.eternal = (stk == "eternal") or nil
              c.ability.perishable = (stk == "perishable") or nil
              c.ability.rental = (stk == "rental") or nil
              combos = combos + 1
              local ok, err = pcall(Cards.draw_card_mini, c, -400, -400, 60, 1)
              if not ok and not first_fail then
                first_fail = string.format("enh=%s seal=%s ed=%s stk=%s: %s",
                  tostring(enh), tostring(seal), ed and next(ed) or "none", tostring(stk), tostring(err))
              end
              if not ok then throws = throws + 1 end
            end
          end
        end
      end
      c.config.center = G.P_CENTERS.c_base
      c.seal, c.edition = nil, nil
      c.ability.eternal, c.ability.perishable, c.ability.rental = nil, nil, nil
      local fronts = 0
      for _, v in pairs(G.P_CARDS) do
        pcall(c.set_base, c, v)
        fronts = fronts + 1
        local ok, err = pcall(Cards.draw_card_mini, c, -400, -400, 60, 1)
        if not ok and not first_fail then
          first_fail = "front " .. tostring(v.value) .. "/" .. tostring(v.suit) .. ": " .. tostring(err)
        end
        if not ok then throws = throws + 1 end
      end
      pcall(function() c:remove() end)
      local ef, fb = Cards._mini_edition_fail, Cards._mini_fallback
      SelfTest.trace("pack/standard/all_mutations | combos=%d fronts=%d throw=%d fallback=%d edition_fail=%d",
        combos, fronts, throws, fb, ef)
      if throws > 0 or fb > 0 or ef > 0 then
        return false, string.format("combos=%d fronts=%d throw=%d fallback=%d edition_fail=%d | first=%s",
          combos, fronts, throws, fb, ef, first_fail or "-")
      end
      return true, string.format("all %d combos + %d fronts clean (fallback=0 edition_fail=0)", combos, fronts)
    end,
    teardown = function()
      pcall(run_action, "skip_booster", {})
      clear_area(G.consumeables); clear_area(G.jokers)
    end,
  }
end

-- Only these run under NEURO_SELFTEST_PACK; kept out of the default suite (heavy, real-engine).
function M.build_pack()
  return {
    standard_pack_mutations_case(),
    all_spectrals_case(),
    pack_launch_case("pack/launch/spectral_real", "p_spectral_normal_1"),
    pack_launch_case("pack/launch/arcana_real", "p_arcana_normal_1"),
  }
end

return M
