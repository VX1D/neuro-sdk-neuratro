local Showcase = {}

local S = require("hud.state")
local Episode = require("hud.episode")
local StateKinds = require("core.state_kinds")
local NeuroState = require("core.state")
local Utils = require("util.utils")
local Prims = require("hud.prims")
local LevelDelta = require("util.level_delta")
local smoothstep01 = Prims.smoothstep01

Showcase.FOOTER_CYCLE = 4
Showcase.JOKER_SHOWCASE_DURATION = 4.8
Showcase.JOKER_SHOWCASE_FADE_IN = 0.30
Showcase.JOKER_SHOWCASE_FADE_OUT = 0.55
-- The engine hands several cards over in one frame (Riff-raff makes two jokers in one event func,
-- dump card.lua:2901-2914; The Emperor/High Priestess two consumables, game.lua:552,554), so the
-- corridor schedules the whole backlog against one budget instead of paying the full span per card.
Showcase.JOKER_SHOWCASE_BUDGET = 7.0
Showcase.JOKER_SHOWCASE_MIN = 1.2
Showcase.SHOWCASE_QUEUE_CAP =
  math.floor(Showcase.JOKER_SHOWCASE_BUDGET / Showcase.JOKER_SHOWCASE_MIN)
local FREEZE_FRESH = 0.25
Showcase.BUY_SHOWCASE_DURATION = 1.8
Showcase.BUY_SWAP_OUT = 0.10
Showcase.BUY_SWAP_IN = 0.10
Showcase.PURCHASE_QUEUE_CAP = 8
Showcase.VOUCHER_DRAWER_SAFETY = 12.0
local BUY_SHOWCASE_DURATION = Showcase.BUY_SHOWCASE_DURATION
local BUY_SHOWCASE_FADE_IN = 0.16
local BUY_SHOWCASE_FADE_OUT = 0.30
local BUY_SHOWCASE_MIN_DWELL = 0.9
Showcase.BUY_SHOWCASE_FADE_IN = BUY_SHOWCASE_FADE_IN
Showcase.BUY_SHOWCASE_FADE_OUT = BUY_SHOWCASE_FADE_OUT
Showcase.BUY_SHOWCASE_MIN_DWELL = BUY_SHOWCASE_MIN_DWELL

Showcase.REFUSAL_CODES = { INSUFFICIENT_FUNDS = true, NO_SLOT = true }
Showcase.REFUSAL_COOLDOWN = 6.0
Showcase.REFUSAL_GAP = 2.5
Showcase.LOST_CONFIRM = 0.6
Showcase.REMOVAL_GRACE = 4.0

local MONEY_DIR = {
  sell = "gain", booster_pick = "gain",
  shop = "spend", shop_jokers = "spend", shop_booster = "spend",
  shop_vouchers = "spend", shop_use = "spend",
}

function Showcase.money_direction(area)
  return MONEY_DIR[tostring(area or "")] or "none"
end

local in_flight = setmetatable({}, { __mode = "k" })

local function hold_card(card)
  if type(card) ~= "table" then return false end
  in_flight[card] = (in_flight[card] or 0) + 1
  return true
end

local function release_card(card, now)
  if type(card) ~= "table" then return false end
  local n = in_flight[card]
  if not n then return false end
  if n > 1 then in_flight[card] = n - 1; return false end
  in_flight[card] = nil
  local gate = S.voucher_drawer_gate
  if type(gate) == "table" then
    for _, gv in pairs(gate) do
      if gv.card == card then gv.release_at = tonumber(now) or 0 end
    end
  end
  return true
end

function Showcase.enqueue_purchase(item)
  if not (G and G.NEURO and type(item) == "table") then return false end
  if Showcase.PACK_CINEMATIC_ALWAYS[tostring(item.area or "")] then return false end
  local q = G.NEURO.purchase_showcase_queue
  if type(q) ~= "table" then q = {} end
  q[#q + 1] = item
  hold_card(item.card)
  while #q > Showcase.PURCHASE_QUEUE_CAP do
    local dropped = table.remove(q, 1)
    local head = q[1]
    head.merged = (head.merged or 0) + 1 + (dropped.merged or 0)
    local spend = (tonumber(dropped.merged_spend) or 0)
    local gain = (tonumber(dropped.merged_gain) or 0)
    local dir = Showcase.money_direction(dropped.area)
    if dir == "spend" then spend = spend + (tonumber(dropped.cost) or 0)
    elseif dir == "gain" then gain = gain + (tonumber(dropped.cost) or 0) end
    if spend > 0 then head.merged_spend = (tonumber(head.merged_spend) or 0) + spend end
    if gain > 0 then head.merged_gain = (tonumber(head.merged_gain) or 0) + gain end
    release_card(dropped.card, tonumber(item.at))
    Utils.diag_once("purchase_queue_overflow",
      "purchase toast queue overflowed, oldest pending merged into a +N chip")
  end
  G.NEURO.purchase_showcase_queue = q
  return true
end

local refusal_gate = {}
local refusal_last_at = nil

function Showcase.enqueue_refusal(item)
  if not (G and G.NEURO and type(item) == "table") then return false end
  local code = tostring(item.code or "")
  if not Showcase.REFUSAL_CODES[code] then return false end
  if item.action_id == nil or G.NEURO._candidate_probe then return false end
  local now = tonumber(item.at) or Utils.gate_now("showcase_grace")
  local q = G.NEURO.purchase_showcase_queue
  if type(q) == "table" and #q > 0 then return false end
  if refusal_last_at and (now - refusal_last_at) < Showcase.REFUSAL_GAP then return false end
  local key = code .. "|" .. tostring(item.name or "")
  for k, until_at in pairs(refusal_gate) do
    if until_at <= now then refusal_gate[k] = nil end
  end
  if refusal_gate[key] then return false end
  refusal_gate[key] = now + Showcase.REFUSAL_COOLDOWN
  refusal_last_at = now
  return Showcase.enqueue_purchase({
    card = item.card,
    name = tostring(item.name or "Card"),
    cost = tonumber(item.cost) or 0,
    area = "refused",
    code = code,
    at = now,
  })
end

local function apply_item(sc, item, now)
  sc._born, sc._pair_at, sc._Lr, sc._Lr_sig, sc._defer_seen = nil, nil, nil, nil, nil
  sc.hold_at, sc.hold_elapsed = nil, nil
  sc.born_at = now
  sc.card = item.card
  sc.name = tostring(item.name or "Purchase")
  sc.cost = tonumber(item.cost) or 0
  sc.area = tostring(item.area or "shop")
  sc.merged = tonumber(item.merged) or nil
  sc.merged_spend = tonumber(item.merged_spend) or nil
  sc.merged_gain = tonumber(item.merged_gain) or nil
  sc.code = item.code
  sc.levels = item.levels
  sc.effect = nil
  return sc
end

local function resolve_effect(sc)
  if not sc or sc.effect or not sc.levels then return end
  local text = LevelDelta.brief(G and G.GAME and G.GAME.hands, sc.levels)
  if text then sc.effect, sc.levels = text, nil end
end

local receipt_suppressed

local function scan_showable(now, take)
  local q = G and G.NEURO and G.NEURO.purchase_showcase_queue
  if type(q) ~= "table" then return nil end
  while #q > 0 do
    local head = q[1]
    if type(head) ~= "table" or receipt_suppressed(head, now) then
      table.remove(q, 1)
      release_card(head and head.card, now)
    elseif take then
      return table.remove(q, 1)
    else
      return head
    end
  end
  return nil
end

local function peek_showable(now) return scan_showable(now, false) end
local function take_showable(now) return scan_showable(now, true) end

function Showcase.has_pending(now) return peek_showable(now) ~= nil end

function Showcase.retire_receipt(now)
  local sc = S.buy_showcase
  if not sc then return false end
  release_card(sc.card, now)
  S.buy_showcase = nil
  return true
end

local function begin_exit(sc, now)
  local out_at = BUY_SHOWCASE_DURATION - BUY_SHOWCASE_FADE_OUT
  if (now - (sc.started or now)) < out_at then sc.started = now - out_at end
end

function Showcase.hold_receipt(sc, now)
  if type(sc) ~= "table" then return false end
  sc.hold_at = tonumber(now) or 0
  return true
end

function Showcase.release_receipt(sc)
  if type(sc) ~= "table" then return false end
  sc.hold_at, sc.hold_elapsed = nil, nil
  return true
end

local function receipt_held(sc, now)
  return sc.hold_at ~= nil and (now - sc.hold_at) < FREEZE_FRESH
end

local function freeze_receipt(sc, now)
  sc.hold_elapsed = sc.hold_elapsed or (now - (sc.started or now))
  sc.started = now - sc.hold_elapsed
end

function Showcase.receipt_ends_at(sc)
  if type(sc) ~= "table" then return nil end
  local at = (sc.started or 0) + BUY_SHOWCASE_DURATION
  if sc.swap_started then
    local out = sc.swap_started + Showcase.BUY_SWAP_OUT
    if out < at then at = out end
  end
  return at
end

local function pull_buy_showcase(now)
  if not (G and G.NEURO) then return end
  if S.buy_showcase then return end
  local item = take_showable(now)
  if type(item) ~= "table" then return end
  S.buy_showcase = apply_item({ started = now or 0 }, item, now or 0)
  resolve_effect(S.buy_showcase)
end

function Showcase.buy_alpha(sc, now)
  if not sc then return 0 end
  now = now or 0
  local elapsed = now - (sc.started or 0)
  if elapsed < BUY_SHOWCASE_FADE_IN then
    return smoothstep01(elapsed / BUY_SHOWCASE_FADE_IN)
  elseif elapsed > (BUY_SHOWCASE_DURATION - BUY_SHOWCASE_FADE_OUT) then
    return smoothstep01((BUY_SHOWCASE_DURATION - elapsed) / BUY_SHOWCASE_FADE_OUT)
  end
  return 1
end

function Showcase.buy_content_alpha(sc, now)
  if not sc then return 0, 1 end
  now = now or 0
  local out01 = sc.swap_started
    and (1 - smoothstep01((now - sc.swap_started) / Showcase.BUY_SWAP_OUT)) or 1
  local in01 = sc.content_in_at
    and smoothstep01((now - sc.content_in_at) / Showcase.BUY_SWAP_IN) or 1
  return math.min(out01, in01), in01
end

function Showcase.update_buy(now)
  now = now or 0
  pull_buy_showcase(now)
  local sc = S.buy_showcase
  if not sc then return end
  if not sc._morph_at and receipt_held(sc, now) then
    freeze_receipt(sc, now)
    resolve_effect(sc)
    return
  end
  sc.hold_elapsed = nil
  if not sc._morph_at and not sc.swap_started and receipt_suppressed(sc, now) then
    if peek_showable(now) then sc.swap_started = now else begin_exit(sc, now) end
  end
  local elapsed = now - (sc.started or 0)

  resolve_effect(sc)

  if sc._morph_at then
    if (now - sc._morph_at) > 8 then
      Showcase.retire_receipt(now)
      pull_buy_showcase(now)
    end
    return
  end

  if sc.swap_started then
    if (now - sc.swap_started) >= Showcase.BUY_SWAP_OUT then
      local item = take_showable(now)
      if type(item) == "table" then
        release_card(sc.card, now)
        apply_item(sc, item, now)
        sc.started = now - BUY_SHOWCASE_FADE_IN
        sc.content_in_at = now
        resolve_effect(sc)
      elseif receipt_suppressed(sc, now) then
        begin_exit(sc, now)
      end
      sc.swap_started = nil
    end
    return
  end

  if peek_showable(now) and elapsed >= BUY_SHOWCASE_MIN_DWELL
    and elapsed < (BUY_SHOWCASE_DURATION - BUY_SHOWCASE_FADE_OUT) then
    sc.swap_started = now
    return
  end

  if elapsed >= BUY_SHOWCASE_DURATION then
    Showcase.retire_receipt(now)
    pull_buy_showcase(now)
  end
end

function Showcase.card_set_label(c)
  local set = c and c.config and c.config.center and c.config.center.set
  if set == "Joker"    then return "NEW JOKER"
  elseif set == "Planet"   then return "NEW PLANET"
  elseif set == "Tarot"    then return "NEW TAROT"
  elseif set == "Spectral" then return "NEW SPECTRAL"
  elseif set == "Voucher"  then return "VOUCHER"
  else return "NEW CARD" end
end

local function is_in_pack_state()
  if not G then return false end
  local sn = (G.NEURO and (G.NEURO.force_state or G.NEURO.state)) or ""
  return StateKinds.is_pack_state(sn)
end

Showcase.PACK_CINEMATIC_AREAS = { booster_pick = true, shop_booster = true }
Showcase.PACK_CINEMATIC_ALWAYS = { shop_booster = true }
Showcase.PACK_CLAIM_TAIL = 6.0

function Showcase.pack_stage_owned(now)
  local latched = Episode.pack_on_screen()
  if latched ~= nil then
    if latched then return true end
  elseif is_in_pack_state() then
    return true
  end
  if S.pack_collapse_req or S.pack_collapse_t then return true end
  if type(S.pack_winners) == "table" and #S.pack_winners > 0 then return true end
  local at = S.pack_claim_at
  return at ~= nil and (tonumber(now) or 0) - at < Showcase.PACK_CLAIM_TAIL
end

function receipt_suppressed(item, now)
  local area = item and tostring(item.area or "")
  if Showcase.PACK_CINEMATIC_ALWAYS[area] then return true end
  return Showcase.PACK_CINEMATIC_AREAS[area] == true and Showcase.pack_stage_owned(now)
end

local function showcase_push(list, item, now)
  list[#list + 1] = item
  while #list > Showcase.SHOWCASE_QUEUE_CAP do
    local dropped = table.remove(list, 1)
    local head = list[1]
    head.merged = (head.merged or 0) + 1 + (dropped.merged or 0)
    release_card(dropped.card, now)
    Utils.diag_once("showcase_queue_overflow",
      "showcase queue overflowed, oldest pending gain merged into a +N chip")
  end
end

local function push_showcase(c, label, now)
  local item = {card = c, label = label or Showcase.card_set_label(c)}
  hold_card(c)
  showcase_push(is_in_pack_state() and S.pack_gained_q or S.joker_showcase_q, item, now)
end

local function stall_ceiling(now)
  return (tonumber(now) or Utils.gate_now("voucher_drawer_safety"))
    + (Utils.gate_seconds("voucher_drawer_safety") or Showcase.VOUCHER_DRAWER_SAFETY)
end

function Showcase.enqueue_voucher(card, now)
  local center = card and card.config and card.config.center
  local key = center and center.key
  if type(key) ~= "string" or key == "" then return false end
  now = tonumber(now) or Utils.gate_now("showcase_grace")
  push_showcase(card, Showcase.card_set_label(card), now)
  local gate = S.voucher_drawer_gate
  if type(gate) ~= "table" then gate = {}; S.voucher_drawer_gate = gate end
  gate[key] = { card = card, safety_at = stall_ceiling(now) }
  return true
end

function Showcase.card_in_flight(card)
  return type(card) == "table" and in_flight[card] ~= nil
end

local known_joker_ids = nil
local pending_lost = {}
local removal_expected = {}

Showcase.CLAIM_GRACE = 8.0
local claim_expected = setmetatable({}, { __mode = "k" })
local claim_expected_sid = {}

function Showcase.note_claimed(card, now)
  if type(card) ~= "table" then return false end
  local until_at = (tonumber(now) or Utils.gate_now("showcase_grace")) + Showcase.CLAIM_GRACE
  claim_expected[card] = until_at
  if card.sort_id ~= nil then claim_expected_sid[card.sort_id] = until_at end
  return true
end

local function claim_consumed(card, now)
  if type(card) ~= "table" then return false end
  local until_at = claim_expected[card]
  local sid = card.sort_id
  if until_at == nil and sid ~= nil then until_at = claim_expected_sid[sid] end
  if until_at == nil then return false end
  claim_expected[card] = nil
  if sid ~= nil then claim_expected_sid[sid] = nil end
  return (tonumber(now) or Utils.gate_now("showcase_grace")) <= until_at
end

function Showcase.note_removal(card, now)
  local sid = card and card.sort_id
  if sid == nil then return false end
  removal_expected[sid] = (tonumber(now) or Utils.gate_now("showcase_grace")) + Showcase.REMOVAL_GRACE
  pending_lost[sid] = nil
  return true
end

local NO_LOSS_STATES = { MENU = true, SPLASH = true, GAME_OVER = true, RUN_SETUP = true, UNKNOWN = true }

local function count_keys(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local snapshot_spare = {}

local function recycle(key)
  local t = snapshot_spare[key]
  if not t then return {} end
  snapshot_spare[key] = nil
  for k in pairs(t) do t[k] = nil end
  return t
end

local function drop_snapshot(key)
  local t = snapshot_spare[key]
  if t then for k in pairs(t) do t[k] = nil end end
end

local function scan_joker_losses(now)
  now = now or 0
  local in_run = G.STAGE == (G.STAGES and G.STAGES.RUN)
    and not NO_LOSS_STATES[NeuroState.get_state_name()]
  if (G.NEURO and G.NEURO.dev_preview_active) or not in_run
    or not (G.jokers and G.jokers.cards) then
    known_joker_ids = nil
    drop_snapshot("ids")
    if next(pending_lost) ~= nil then pending_lost = {} end
    return
  end
  local prev = known_joker_ids
  local cur = recycle("ids")
  local cur_n = 0
  for _, c in ipairs(G.jokers.cards) do
    local sid = c.sort_id
    if sid ~= nil then
      if cur[sid] == nil then cur_n = cur_n + 1 end
      cur[sid] = c
    end
  end
  known_joker_ids = cur
  if not prev then
    if next(pending_lost) ~= nil then pending_lost = {} end
    return
  end
  snapshot_spare.ids = prev
  if cur_n == 0 and count_keys(prev) >= 2 then
    if next(pending_lost) ~= nil then pending_lost = {} end
    return
  end
  for sid, card in pairs(prev) do
    if cur[sid] == nil then
      local expected = removal_expected[sid]
      if expected and expected > now then
        removal_expected[sid] = nil
      elseif not pending_lost[sid] then
        pending_lost[sid] = { card = card, name = Utils.safe_name_or(card), at = now }
      end
    end
  end
  for sid, p in pairs(pending_lost) do
    if cur[sid] ~= nil then
      pending_lost[sid] = nil
    elseif (now - p.at) >= Showcase.LOST_CONFIRM then
      pending_lost[sid] = nil
      Showcase.enqueue_purchase({ card = p.card, name = p.name, cost = 0, area = "lost", at = now })
    end
  end
  for sid, until_at in pairs(removal_expected) do
    if until_at <= now then removal_expected[sid] = nil end
  end
  -- Only claim_expected is weak-keyed. Apart from a consumed claim the sid half shrinks here,
  -- which the earlier returns can skip; reset_run_state bounds it per run.
  for sid, until_at in pairs(claim_expected_sid) do
    if until_at <= now then claim_expected_sid[sid] = nil end
  end
end

local showcase_deadline = nil
local stage_frozen_at = nil

function Showcase.note_stage_frozen(now)
  stage_frozen_at = tonumber(now) or 0
end

local acquire_mod = nil
local function receipt_pressure(now)
  if Showcase.has_pending(now) then return true end
  if S.buy_showcase == nil then return false end
  if not acquire_mod then
    local ok, mod = pcall(require, "render.panels.acquire")
    if not ok then return true end
    acquire_mod = mod
  end
  return not acquire_mod.pair(now)
end

local function corridor_out_at(js, now)
  local started = js.started or now
  local elapsed = now - started
  local fout = js._fout or Showcase.JOKER_SHOWCASE_FADE_OUT
  if js._exiting then return (js._out_at or elapsed), fout end
  if showcase_deadline == nil then
    showcase_deadline = started + Showcase.JOKER_SHOWCASE_BUDGET
  end
  local span = (showcase_deadline - started) / (1 + #S.joker_showcase_q)
  if span > Showcase.JOKER_SHOWCASE_DURATION then span = Showcase.JOKER_SHOWCASE_DURATION end
  if span < Showcase.JOKER_SHOWCASE_MIN then span = Showcase.JOKER_SHOWCASE_MIN end
  local out_at = span - fout
  if receipt_pressure(now) then
    out_at = math.min(out_at, math.max(Showcase.JOKER_SHOWCASE_MIN, elapsed))
  end
  if out_at <= elapsed then
    out_at = elapsed
    js._exiting = true
  end
  js._out_at = out_at
  return out_at, fout
end

local function freeze_corridor(js, now)
  js.hold_elapsed = js.hold_elapsed or (now - (js.started or now))
  local started = now - js.hold_elapsed
  if showcase_deadline then showcase_deadline = showcase_deadline + (started - (js.started or started)) end
  js.started = started
  local gate = S.voucher_drawer_gate
  if type(gate) == "table" then
    for _, gv in pairs(gate) do
      if Showcase.card_in_flight(gv.card) then
        gv.safety_at = stall_ceiling(now)
      end
    end
  end
end

local function advance_showcase(now)
  local js = S.joker_showcase
  if not js then
    if #S.joker_showcase_q == 0 then showcase_deadline = nil end
    return
  end
  local sc = S.buy_showcase
  if sc and sc._morph_at and sc.card == js.card then return end
  if stage_frozen_at and (now - stage_frozen_at) < FREEZE_FRESH then
    freeze_corridor(js, now)
    return
  end
  js.hold_elapsed = nil
  local out_at, fout = corridor_out_at(js, now)
  if (now - (js.started or now)) >= out_at + fout then
    release_card(js.card, now)
    S.joker_showcase = nil
  end
end

local function pull_showcase(now)
  if not S.joker_showcase and #S.joker_showcase_q > 0 then
    local item = table.remove(S.joker_showcase_q, 1)
    S.joker_showcase = {card = item.card, label = item.label, merged = item.merged,
      started = now or 0}
  end
end

local function scan_gains(area, key, label, now)
  local cards = area and area.cards
  if not cards then S[key] = nil; drop_snapshot(key); return end
  local prev = S[key]
  local cur = recycle(key)
  for _, c in ipairs(cards) do cur[c] = true end
  if prev then
    for _, c in ipairs(cards) do
      if not prev[c] and not claim_consumed(c, now) then push_showcase(c, label, now) end
    end
    snapshot_spare[key] = prev
  end
  S[key] = cur
end

function Showcase.update_joker(now)
  if not G then S.known_joker_refs = nil; S.known_cons_refs = nil; return end

  scan_joker_losses(now)

  scan_gains(G.jokers, "known_joker_refs", "NEW JOKER", now)
  scan_gains(G.consumeables, "known_cons_refs", nil, now)

  if #S.pack_gained_q > 0 and not Showcase.pack_stage_owned(now) then
    for _, item in ipairs(S.pack_gained_q) do
      showcase_push(S.joker_showcase_q, item, now)
    end
    S.pack_gained_q = {}
  end

  advance_showcase(now)
  pull_showcase(now)
end

function Showcase.reset_run_state()
  Episode.reset()
  in_flight = setmetatable({}, { __mode = "k" })
  showcase_deadline = nil
  stage_frozen_at = nil
  known_joker_ids = nil
  snapshot_spare = {}
  pending_lost = {}
  removal_expected = {}
  claim_expected = setmetatable({}, { __mode = "k" })
  claim_expected_sid = {}
  refusal_gate = {}
  refusal_last_at = nil
  S.known_joker_refs = nil
  S.known_cons_refs = nil
  S.joker_showcase = nil
  S.joker_showcase_q = {}
  S.pack_gained_q = {}
  S.pack_claim_at = nil
  S.buy_showcase = nil
  S.voucher_drawer_gate = {}
  S.pack_last_sn = nil
  S.pack_appear_t = nil
  S.pack_card_indices = {}
  S.pack_hidden_indices = {}
  S.pack_initial_count = 0
  S.pack_hl = false
  S.pack_hl_t = 0
  S.pack_relight_t = nil
  S.pack_leave_t = nil
  S.pack_leave_snap = nil
  S.pack_leave_n = 0
  S.pack_winners = {}
  S.pack_collapse_t = nil
  S.pack_collapse_snap = nil
  S.pack_collapse_req = nil
  S.pack_collapse_done = nil
  S.pack_losers = nil
  S.pack_exit_last = nil
  S.pack_env_last = nil
  S.pack_h_last = nil
  S.pack_disp = nil
end

return Showcase
