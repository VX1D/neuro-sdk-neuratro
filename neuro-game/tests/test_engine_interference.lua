_G.NEURO_TEST = true

_CLOCK = 1000
love = {
  timer = { getTime = function() return _CLOCK or 0 end },
  event = { quit = function() end },
}

local STATES = { SELECTING_HAND = 1, GAME_OVER = 4, MENU = 11, SHOP = 5, BLIND_SELECT = 7 }

local function fresh_G()
  return {
    STATE = STATES.MENU, STATES = STATES, STATE_COMPLETE = true,
    SETTINGS = { GAMESPEED = 1 },
    GAME = { current_round = {}, dollars = 4, round_resets = { ante = 1 } },
    FUNCS = {},
    NEURO = { enabled = false, ai_highlighted = {}, ai_glow = {}, update = function() end },
    TIMERS = { REAL = _CLOCK },
    E_MANAGER = { queues = {} },
  }
end

_G.G = fresh_G()

local check, done = require("tests.helpers").harness("engine interference")

local Orch = require("core.orchestrator")
local Staging = require("core.staging")
local GameActions = require("core.game_actions")

local area_guard = Orch._step_area_nil_guard

local function live_area()
  return { cards = {}, children = {} }
end

local function tombstone_area()
  return { cards = nil, children = nil, REMOVED = true }
end

do
  check("area guard is exported for test", type(area_guard) == "function")
end

do
  G = fresh_G()
  local dead = tombstone_area()
  G.shop_jokers = dead
  G.shop_vouchers = tombstone_area()
  G.shop_booster = tombstone_area()
  area_guard()
  check("tombstoned shop_jokers global is nilled, not resurrected", G.shop_jokers == nil,
    "shop_jokers=" .. tostring(G.shop_jokers))
  check("tombstoned shop_vouchers global is nilled", G.shop_vouchers == nil)
  check("tombstoned shop_booster global is nilled", G.shop_booster == nil)
  check("the removed CardArea itself keeps cards == nil", dead.cards == nil,
    "cards=" .. tostring(dead.cards))
end

do
  G = fresh_G()
  G.pack_cards = { cards = nil, children = nil }
  G.booster_pack = { cards = nil, children = nil }
  area_guard()
  check("cards+children both nil is treated as a tombstone (pack_cards)", G.pack_cards == nil)
  check("cards+children both nil is treated as a tombstone (booster_pack)", G.booster_pack == nil)
end

do
  G = fresh_G()
  local fresh = { children = {} }
  G.hand = fresh
  area_guard()
  check("genuinely uninitialised area still gets cards = {}", G.hand == fresh and type(fresh.cards) == "table",
    "hand=" .. tostring(G.hand) .. " cards=" .. tostring(fresh.cards))
end

do
  G = fresh_G()
  local a = live_area()
  a.cards[1] = { id = 1 }
  G.jokers = a
  area_guard()
  check("live area is left completely alone", G.jokers == a and #a.cards == 1)
end

do
  G = fresh_G()
  local dead = tombstone_area()
  G.consumeables = dead
  area_guard()
  local skip_pred = function(self) return not (self and self.cards) end
  check("after the guard, crash_guards' align/emplace predicate can fire on the tombstone",
    skip_pred(dead) == true)
  check("guard no longer disarms that predicate", G.consumeables == nil)
end

local function stub_card(opts)
  opts = opts or {}
  local card = {
    highlighted = false,
    children = {},
    ability = { set = "Joker" },
    area = opts.area,
    highlight_calls = 0,
  }
  if not opts.no_method then
    card.highlight = function(self, on)
      self.highlight_calls = self.highlight_calls + 1
      self.highlighted = on
      if opts.throws then error("card.lua:4960: boom") end
      if on then
        self.children.use_button = { built = true }
      else
        self.children.use_button = nil
      end
    end
  end
  return card
end

do
  G = fresh_G()
  local card = stub_card()
  GameActions.set_highlight(card, true)
  check("set_highlight prefers Card:highlight", card.highlight_calls == 1)
  check("Card:highlight built children.use_button", card.children.use_button ~= nil,
    "use_button=" .. tostring(card.children.use_button))
  check("flag still set", card.highlighted == true)
  check("ai_highlighted tracks the highlight", G.NEURO.ai_highlighted[card] == true)

  GameActions.set_highlight(card, false)
  check("unhighlight tears down children.use_button", card.children.use_button == nil)
  check("unhighlight clears the flag", card.highlighted == false)
  check("unhighlight clears ai_highlighted", G.NEURO.ai_highlighted[card] == nil)
end

do
  G = fresh_G()
  local card = stub_card({ no_method = true })
  GameActions.set_highlight(card, true)
  check("no highlight method -> raw write fallback still sets the flag", card.highlighted == true)
  check("fallback still tracks ai_highlighted", G.NEURO.ai_highlighted[card] == true)
end

do
  G = fresh_G()
  local card = stub_card({ throws = true })
  local ok = pcall(GameActions.set_highlight, card, true)
  check("a throwing Card:highlight does not propagate", ok, "set_highlight re-threw")
  check("a throwing Card:highlight still leaves the flag correct", card.highlighted == true)
  check("a throwing Card:highlight still updates ai_highlighted", G.NEURO.ai_highlighted[card] == true)
end

do
  G = fresh_G()
  local card = stub_card()
  local area = {
    highlighted = {},
    add_to_highlighted = nil,
  }
  card.area = area
  GameActions.add_area_highlight(area, card)
  check("add_area_highlight fallback goes through Card:highlight", card.highlight_calls == 1)
  check("add_area_highlight fallback builds use_button", card.children.use_button ~= nil)
  check("add_area_highlight fallback appends to area.highlighted", area.highlighted[1] == card)
end

do
  G = fresh_G()
  local card = stub_card()
  card.highlighted = true
  card.children.use_button = { built = true }
  local area = { highlighted = { card } }
  GameActions.clear_area_highlight(area)
  check("clear_area_highlight fallback goes through Card:highlight", card.highlight_calls == 1)
  check("clear_area_highlight fallback tears down use_button", card.children.use_button == nil)
end

local function juicy_card(stationary)
  local c = stub_card()
  c.STATIONARY = stationary
  c.juiced = 0
  c.juice_up = function(self) self.juiced = self.juiced + 1 end
  return c
end

do
  G = fresh_G()
  local settled = Staging._juice_target_settled
  check("predicate: both signals green", settled({ STATIONARY = true }) == true)
  check("predicate: STATIONARY alone is not enough", (function()
    G.E_MANAGER.queues = { base = { { blocking = true, blockable = true } } }
    local v = settled({ STATIONARY = true })
    G.E_MANAGER.queues = {}
    return v
  end)() == false)
  check("predicate: an idle queue alone is not enough", settled({ STATIONARY = false }) == false)
end

do
  G = fresh_G()
  local c = juicy_card(true)
  Staging._hover_card(c)
  check("settled + STATIONARY -> juice fires", c.juiced == 1, "juiced=" .. tostring(c.juiced))
  check("juice latch set", c._neuro_juiced == true)
end

do
  G = fresh_G()
  local c = juicy_card(nil)
  Staging._hover_card(c)
  check("STATIONARY nil (never moved) -> no juice", c.juiced == 0, "juiced=" .. tostring(c.juiced))
  check("no latch, so it can retry", c._neuro_juiced == nil)
  check("highlight is NOT gated by the settle check", c.highlighted == true)
end

do
  G = fresh_G()
  local c = juicy_card(false)
  Staging._hover_card(c)
  check("mid-spring card (STATIONARY false) -> no juice", c.juiced == 0)
end

do
  G = fresh_G()
  G.E_MANAGER.queues = { base = { { blocking = true, blockable = true } } }
  local c = juicy_card(true)
  Staging._hover_card(c)
  check("engine not settled (blocking event queued) -> no juice", c.juiced == 0)
  G.E_MANAGER.queues = { base = {} }
  Staging._hover_card(c)
  check("once the queue drains, the deferred juice fires", c.juiced == 1)
end

do
  G = fresh_G()
  local c = juicy_card(true)
  Staging._hover_card(c)
  Staging._hover_card(c)
  check("latch still prevents re-juicing every frame", c.juiced == 1)
end

do
  G = fresh_G()
  local c = juicy_card(true)
  Staging._hover_card(c)
  Staging._unhover_card(c)
  check("hover writes no card.hovering field", rawget(c, "hovering") == nil,
    "hovering=" .. tostring(rawget(c, "hovering")))
  check("unhover clears the juice latch", c._neuro_juiced == nil)
  check("unhover unhighlights through Card:highlight", c.highlighted == false)
end

local function constructor_body(src, from)
  local depth, i, n = 0, from, #src
  local started = false
  while i <= n do
    local ch = src:sub(i, i)
    if ch == "(" or ch == "{" then depth = depth + 1; started = true
    elseif ch == ")" or ch == "}" then
      depth = depth - 1
      if started and depth <= 0 then return src:sub(from, i) end
    end
    i = i + 1
  end
  return src:sub(from)
end

do
  local fh = io.open("handlers/use_card.lua", "r")
  local src = fh:read("a")
  fh:close()
  local sites, explicit, all_true = 0, 0, true
  local pos = 1
  while true do
    local s = src:find("add_event%s*%(%s*Event%s*%(%s*{", pos)
    if not s then break end
    sites = sites + 1
    local body = constructor_body(src, s)
    if body:find("blockable") then
      explicit = explicit + 1
      if not body:find("blockable%s*=%s*true") then all_true = false end
    end
    pos = s + 1
  end
  check("use_consumable has Event constructions to check (" .. sites .. ")", sites == 1, "sites=" .. sites)
  check("every use_consumable Event declares blockable explicitly", explicit == sites,
    "explicit=" .. explicit .. "/" .. sites)
  check("use_consumable keeps the conservative blockable = true", all_true)
end

do
  _G.Event = {}
  function _G.Event.handle(self, results)
    results.completed = self.func()
    results.time_done = true
  end
  local CG = require("core.crash_guards")
  CG.install()

  local before = CG._test.drop_stats().total
  local ev = { func = function() error("card.lua:1429: boom", 0) end, complete = false }
  local res = {}
  local ok = pcall(_G.Event.handle, ev, res)
  local after = CG._test.drop_stats()
  check("swallow behaviour unchanged: no propagation", ok, "handle re-threw")
  check("swallow behaviour unchanged: event force-completed",
    res.completed == true and res.time_done == true and ev.complete == true)
  check("drop counter incremented", after.total == before + 1,
    "before=" .. before .. " after=" .. after.total)
  check("drop counter is attributed per site", after.by_site["card.lua:1429"] == 1,
    "site=" .. tostring(after.by_site["card.lua:1429"]))

  for _ = 1, 4 do
    pcall(_G.Event.handle, { func = function() error("card.lua:1429: boom", 0) end }, {})
  end
  local s2 = CG._test.drop_stats()
  check("repeat drops at the same site keep counting past the once-per-site log",
    s2.by_site["card.lua:1429"] == 5, "site=" .. tostring(s2.by_site["card.lua:1429"]))
  check("total tracks every drop", s2.total == before + 5, "total=" .. s2.total)

  pcall(_G.Event.handle, { func = function() error("cardarea.lua:266: boom", 0) end }, {})
  local s3 = CG._test.drop_stats()
  check("a second site gets its own bucket", s3.by_site["cardarea.lua:266"] == 1 and s3.total == before + 6)

  local snap = CG._test.drop_stats()
  snap.total = 999
  snap.by_site["card.lua:1429"] = 999
  check("drop_stats returns a copy, not the live table",
    CG._test.drop_stats().total == before + 6 and CG._test.drop_stats().by_site["card.lua:1429"] == 5,
    "site=" .. tostring(CG._test.drop_stats().by_site["card.lua:1429"]))

  local good = { func = function() return true end }
  local gres = {}
  _G.Event.handle(good, gres)
  check("a successful event does not touch the counter", CG._test.drop_stats().total == before + 6)
end

do
  local GA = require("core.game_actions")
  G.NEURO = G.NEURO or {}
  G.NEURO.ai_highlighted = setmetatable({}, { __mode = "k" })

  local function make_area(limit)
    return {
      highlighted = {},
      config = { highlighted_limit = limit },
      add_to_highlighted = function(self, card)
        if #self.highlighted >= self.config.highlighted_limit then
          card.highlighted = false
          return
        end
        self.highlighted[#self.highlighted + 1] = card
        card.highlighted = true
      end,
    }
  end
  local function card() return { highlighted = false } end

  local area = make_area(2)
  local a, b, c = card(), card(), card()
  local ok_a, live_a = GA.add_area_highlight(area, a)
  local ok_b, live_b = GA.add_area_highlight(area, b)
  local ok_c, live_c = GA.add_area_highlight(area, c)

  check("cards within the limit are taken", ok_a and live_a and ok_b and live_b)
  check("the flag is set for cards the engine took",
    G.NEURO.ai_highlighted[a] == true and G.NEURO.ai_highlighted[b] == true)
  check("a card the engine refused is reported as not highlighted", live_c == false)
  check("no flag is set for a card the engine refused",
    G.NEURO.ai_highlighted[c] == nil)
  check("a refusal still counts as handled, so callers do not override the engine",
    ok_c == true)

  local errored = { highlighted = false }
  local bad = { add_to_highlighted = function() error("boom") end }
  local ok_err = GA.add_area_highlight(bad, errored)
  check("a genuine failure is reported as unhandled so the fallback can run",
    ok_err == false)
  check("a genuine failure leaves no flag behind",
    G.NEURO.ai_highlighted[errored] == nil)

  local src = io.open("handlers/hand_handlers.lua", "r"):read("a")
  check("the selection report separates refused cards from selected ones",
    src:find("refused_cards", 1, true) ~= nil
      and src:find("local _, live = add_area_highlight", 1, true) ~= nil)
end

done()
