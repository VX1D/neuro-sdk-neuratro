
local clock = 10
if not love then love = {} end
love.timer = { getTime = function() return clock end }

local function noop() end
local IMG = { getWidth = function() return 64 end, getHeight = function() return 64 end,
  getDimensions = function() return 64, 64 end }
local gfxstub = setmetatable({
  getFont = function() return { getWidth = function(_, s) return #tostring(s or "") * 8 end,
    getHeight = function() return 12 end } end,
  newFont = function() return {} end,
  getWidth = function() return 1920 end,
  getHeight = function() return 1080 end,
  getShader = function() return nil end,
  getBlendMode = function() return "alpha", "alphamultiply" end,
  newQuad = function() return {} end,
  newImage = function() return IMG end,
  newMesh = function() return {} end,
}, { __index = function() return noop end })
love.graphics = gfxstub
love.filesystem = setmetatable({}, { __index = function() return function() return nil end end })

local area = require("tests.helpers").area
_G.G = {
  NEURO = { persona = "hiyori", state = "TAROT_PACK", enabled = true,
    purchase_showcase_queue = {}, last_action_at = 0, run_generation = 1,
    ai_highlighted = setmetatable({}, { __mode = "k" }) },
  GAME = { dollars = 20, pack_choices = 2, round = 1, round_resets = { ante = 1, blind_choices = {} },
    blind = {}, used_vouchers = {}, modifiers = {} },
  jokers = area({}), consumeables = area({}), hand = area({}),
  shop_jokers = area({}), shop_vouchers = area({}), shop_booster = area({}),
  FUNCS = {}, TIMERS = { REAL = 10 }, STATES = {},
  SETTINGS = { paused = false, GAMESPEED = 1 },
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
  ARGS = {}, P_CENTERS = {}, P_CENTER_POOLS = {}, P_BLINDS = {}, localization = {},
  ASSET_ATLAS = {}, SHADERS = {}, TILESCALE = 3.65, TILESIZE = 20, CANV_SCALE = 1,
  I = { MOVEABLE = {}, UIBOX = {}, NODE = {} },
}
_G.SMODS = { current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end }
_G.NFS = setmetatable({}, { __index = function() return noop end })

local check, done = require("tests.helpers").harness("choose_pack_card diagnostics and receipt")

local Config = require("core.config")
Config.init({ settings = {}, colours = {} }, function() return true end)

local queued_events = {}
_G.Event = function(cfg) return cfg end
G.E_MANAGER = {
  add_event = function(_, e) queued_events[#queued_events + 1] = e end,
}

local Handle = require("handlers.use_card")
local Receipt = require("core.action_receipt")
local Showcase = require("hud.showcase")
local NeuroAnim = require("render.neuro-anim")

Receipt.reset("t11_start")

local function joker_card(key, name)
  return {
    config = { center = { key = key, set = "Joker", name = name, loc_txt = { name = name }, rarity = 1 } },
    ability = {},
    cost = 1,
    highlighted = false,
  }
end

local function reset_queue()
  G.NEURO.purchase_showcase_queue = {}
  G.NEURO.last_action_at = 0
  queued_events = {}
  Showcase.reset_run_state()
end

local function pack_setup(cards, fn_impl, pack_choices)
  reset_queue()
  G.GAME.pack_choices = pack_choices or 2
  G.booster_pack = { cards = cards, config = { card_limit = #cards } }
  G.pack_cards = nil
  G.FUNCS.use_card = fn_impl
end

local function make_receipt(pick_index, action_id)
  local exec = Handle.handle_use_card({ area = "booster_pack", index = pick_index, _action_id = action_id })
  local rc = exec()
  assert(rc and rc.name == "choose_pack_card", "expected receipt, got " .. tostring(rc))
  Receipt.transition(rc, "acknowledged")
  Receipt.transition(rc, "executing")
  Receipt.transition(rc, "verifying")
  return rc
end

local function poll(rc, now)
  local done_list = Receipt.update(now, 1)
  for _, r in ipairs(done_list) do if r == rc then return rc end end
  return nil
end

local c1 = joker_card("j_alpha", "Alpha")
G.E_MANAGER = nil
pack_setup({ c1 }, nil)
local rc_missing = make_receipt(1, "t11-missing")
check("missing callback settles the receipt as failed", poll(rc_missing, clock + 1) == rc_missing
  and rc_missing.phase == "failed")
check("missing callback diagnostic names the missing callback",
  rc_missing.details and rc_missing.details.reason == "use_card callback unavailable",
  rc_missing.details and rc_missing.details.reason)
check("missing callback enqueues no receipt", #G.NEURO.purchase_showcase_queue == 0,
  tostring(#G.NEURO.purchase_showcase_queue))

local c2 = joker_card("j_beta", "Beta")
G.E_MANAGER = nil
pack_setup({ c2 }, function() error("callback boom") end)
local rc_threw = make_receipt(1, "t11-threw")
check("throwing callback settles the receipt as failed", poll(rc_threw, clock + 1) == rc_threw
  and rc_threw.phase == "failed")
check("throwing callback diagnostic names the exception",
  rc_threw.details and rc_threw.details.reason == "use_card callback threw",
  rc_threw.details and rc_threw.details.reason)
check("throwing callback enqueues no receipt", #G.NEURO.purchase_showcase_queue == 0)

local c3 = joker_card("j_gamma", "Gamma")
G.E_MANAGER = nil
pack_setup({ c3 }, function() return false end)
local rc_declined = make_receipt(1, "t11-declined")
check("return false settles the receipt as failed", poll(rc_declined, clock + 1) == rc_declined
  and rc_declined.phase == "failed")
check("return false diagnostic names the controlled decline",
  rc_declined.details and rc_declined.details.reason == "use_card callback declined",
  rc_declined.details and rc_declined.details.reason)
check("return false enqueues no receipt", #G.NEURO.purchase_showcase_queue == 0)

local original_hover = NeuroAnim.hover_pack_card
local original_pick = NeuroAnim.pick_pack_card
local original_cancel = NeuroAnim.cancel_pending
NeuroAnim.hover_pack_card = nil
NeuroAnim.pick_pack_card = nil
NeuroAnim.cancel_pending = nil

local c4 = joker_card("j_delta", "Delta")
local calls_one = 0
pack_setup({ c4 }, function()
  calls_one = calls_one + 1
  for i = #G.booster_pack.cards, 1, -1 do
    if G.booster_pack.cards[i] == c4 then table.remove(G.booster_pack.cards, i) end
  end
  return true
end)
G.E_MANAGER = { add_event = function(_, e) queued_events[#queued_events + 1] = e end }
queued_events = {}
local exec_one = Handle.handle_use_card({ area = "booster_pack", index = 1, _action_id = "t11-one" })
local rc_one = exec_one()
assert(rc_one and rc_one.name == "choose_pack_card")
Receipt.transition(rc_one, "acknowledged")
Receipt.transition(rc_one, "executing")
Receipt.transition(rc_one, "verifying")
check("pack pick queues exactly one exec event, no watchdog", #queued_events == 1, #queued_events)
local pick_event = queued_events[1]
check("pick event runs on the game clock and keeps its blockable flags",
  pick_event.timer == "TOTAL" and pick_event.blocking == false and pick_event.blockable == true,
  tostring(pick_event.timer) .. "/" .. tostring(pick_event.blockable))
pick_event.func()
check("successful pick event invokes the callback exactly once", calls_one == 1, calls_one)
local probe_one = rc_one.probe()
check("successful pick probe reports applied", probe_one == "applied", tostring(probe_one))
local done_one = poll(rc_one, clock + 1)
check("successful pick settles as applied", done_one == rc_one and rc_one.phase == "applied")
check("successful pick enqueues exactly one booster_pick",
  #G.NEURO.purchase_showcase_queue == 1
    and G.NEURO.purchase_showcase_queue[1].area == "booster_pick",
  tostring(#G.NEURO.purchase_showcase_queue))
pick_event.func()
check("late rerun after applied does not invoke the callback again", calls_one == 1, calls_one)
local later = Receipt.update(clock + 2, 1)
check("repeated poll after applied finalizes nothing again", #later == 0
  and #G.NEURO.purchase_showcase_queue == 1, tostring(#later))

local c7 = joker_card("j_eta", "Eta")
local calls_pend = 0
pack_setup({ c7 }, function() calls_pend = calls_pend + 1; return true end)
G.E_MANAGER = { add_event = function(_, e) queued_events[#queued_events + 1] = e end }
queued_events = {}
local exec_pend = Handle.handle_use_card({ area = "booster_pack", index = 1, _action_id = "t11-pend" })
local rc_pend = exec_pend()
assert(rc_pend and rc_pend.name == "choose_pack_card")
Receipt.transition(rc_pend, "acknowledged")
Receipt.transition(rc_pend, "executing")
Receipt.transition(rc_pend, "verifying")
local late_event = queued_events[1]
local p1 = rc_pend.probe()
check("unexecuted pick stays pending before the deadline", p1 == "pending", tostring(p1))
local early = Receipt.update(clock + 1, 1)
check("pre-deadline poll completes nothing", #early == 0 and rc_pend.phase == "verifying", tostring(#early))
local at_deadline = Receipt.update(rc_pend.deadline, 1)
check("deadline ends no-proof as ambiguous", at_deadline ~= nil and rc_pend.phase == "ambiguous",
  tostring(rc_pend.phase))
check("ambiguous reason is deadline",
  rc_pend.details and rc_pend.details.reason == "deadline",
  rc_pend.details and tostring(rc_pend.details.reason))
local pack_before = #G.booster_pack.cards
local choices_before = G.GAME.pack_choices
local queue_before = #G.NEURO.purchase_showcase_queue
local calls_before = calls_pend
late_event.func()
check("late event after ambiguous does not invoke the callback", calls_pend == calls_before, calls_pend)
check("late event after ambiguous leaves pack, choices and queue unchanged",
  #G.booster_pack.cards == pack_before and G.GAME.pack_choices == choices_before
    and #G.NEURO.purchase_showcase_queue == queue_before,
  tostring(#G.booster_pack.cards) .. "/" .. tostring(G.GAME.pack_choices) .. "/"
    .. tostring(#G.NEURO.purchase_showcase_queue))
late_event.func()
late_event.func()
check("repeated late event runs never invoke the callback", calls_pend == calls_before, calls_pend)

local c8 = joker_card("j_theta", "Theta")
local calls_rst = 0
pack_setup({ c8 }, function() calls_rst = calls_rst + 1; return true end)
G.E_MANAGER = { add_event = function(_, e) queued_events[#queued_events + 1] = e end }
queued_events = {}
local exec_rst = Handle.handle_use_card({ area = "booster_pack", index = 1, _action_id = "t11-rst" })
local rc_rst = exec_rst()
assert(rc_rst and rc_rst.name == "choose_pack_card")
local rst_event = queued_events[1]
Receipt.reset("t11_mid_reset")
check("run reset terminalizes the prepared receipt as ambiguous", rc_rst.phase == "ambiguous"
  and rc_rst.details.reason == "t11_mid_reset")
local pack_r = #G.booster_pack.cards
local choices_r = G.GAME.pack_choices
local queue_r = #G.NEURO.purchase_showcase_queue
rst_event.func()
check("late event after run reset does not invoke the callback", calls_rst == 0, calls_rst)
check("late event after run reset leaves game state unchanged",
  #G.booster_pack.cards == pack_r and G.GAME.pack_choices == choices_r
    and #G.NEURO.purchase_showcase_queue == queue_r,
  tostring(#G.booster_pack.cards) .. "/" .. tostring(G.GAME.pack_choices) .. "/"
    .. tostring(#G.NEURO.purchase_showcase_queue))

NeuroAnim.hover_pack_card = original_hover
NeuroAnim.pick_pack_card = original_pick
NeuroAnim.cancel_pending = original_cancel

local function file_clean(rel, needle)
  local fh = io.open(rel, "rb")
  if not fh then return false end
  local body = fh:read("*a")
  fh:close()
  return not body:find(needle, 1, true)
end
check("no production watch_pending state", file_clean("handlers/use_card.lua", "watch_pending"))
check("no production did-not-complete diagnostic",
  file_clean("handlers/use_card.lua", "booster pick event did not complete"))
check("no production pack-pick grace setting",
  file_clean("core/config_schema.lua", "NEURO_PACK_PICK_WATCHDOG_GRACE"))

local c6 = joker_card("j_zeta", "Zeta")
G.E_MANAGER = nil
pack_setup({ c6 }, function()
  G.GAME.pack_choices = G.GAME.pack_choices - 1
  return true
end, 2)
local rc_choices = make_receipt(1, "t11-choices")
local probe_out, probe_det = rc_choices.probe()
check("pack_choices mutation is observed by the probe", probe_out == "applied"
  and probe_det.pack_choices_changed == true)
local done_choices = poll(rc_choices, clock + 1)
check("pack_choices mutation settles as applied", done_choices == rc_choices and rc_choices.phase == "applied")
check("pack_choices mutation enqueues exactly one booster_pick",
  #G.NEURO.purchase_showcase_queue == 1
    and G.NEURO.purchase_showcase_queue[1].area == "booster_pick",
  tostring(#G.NEURO.purchase_showcase_queue))
local q1 = #G.NEURO.purchase_showcase_queue
local second = Receipt.update(clock + 2, 1)
check("repeated poll after applied does not re-run on_applied",
  #second == 0 and #G.NEURO.purchase_showcase_queue == q1,
  tostring(#second) .. "/" .. tostring(#G.NEURO.purchase_showcase_queue))
check("applied receipt is removed from the registry", Receipt.get("t11-choices") == nil)

Receipt.reset("t11_end")
done()
