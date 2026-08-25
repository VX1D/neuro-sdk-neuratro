
local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
  getWrap = function(_, s, limit)
    s = tostring(s or "")
    local per = math.max(1, math.floor((limit or 999999) / 8))
    local lines, cur = {}, ""
    for word in s:gmatch("%S+") do
      local cand = (cur == "") and word or (cur .. " " .. word)
      if #cand <= per then cur = cand else lines[#lines + 1] = cur; cur = word end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    if #lines == 0 then lines = { "" } end
    return limit, lines
  end,
}
local function noop() end
local PRINTS = {}
love = setmetatable({
  graphics = setmetatable({
    getFont = function() return FONT end,
    newFont = function() return FONT end,
    getWidth = function() return 1920 end,
    getHeight = function() return 1080 end,
    print = function(text, x, y) PRINTS[#PRINTS + 1] = { text = tostring(text), x = x, y = y } end,
  }, { __index = function() return noop end }),
  timer = { getTime = function() return (G.TIMERS.REAL or 0) + 5000 end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

_G.G = {
  NEURO = { persona = "neuro", state = "MENU", ai_highlighted = {} },
  GAME = { dollars = 25 },
  TIMERS = { REAL = 100 },
  STAGE = 1, STAGES = { MAIN_MENU = 1, RUN = 2 },
  P_CENTERS = {}, C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
  FUNCS = {}, STATES = {}, SETTINGS = { paused = false },
  ASSET_ATLAS = {}, SHADERS = {}, TILESCALE = 3.65, TILESIZE = 20, CANV_SCALE = 1,
  I = { MOVEABLE = {}, UIBOX = {}, NODE = {} },
}
_G.SMODS = { current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end }

local check, done = require("tests.helpers").harness("dev scenario scenes")

local S = require("hud.state")
local Showcase = require("hud.showcase")
local Palette = require("render.palette")
local Dev = require("hud.dev_scenario")

local SCENES = Dev.SCENES
local function scene_index(id)
  for i, sc in ipairs(SCENES) do if sc.id == id then return i end end
end

local function mount(t)
  G.TIMERS.REAL = t
  Dev.mount()
  Showcase.update_buy(t)
end
local function unmount() Dev.unmount() end

local BASE = 100

local live_game, live_jokers = G.GAME, G.jokers
local saved_stage, saved_voucher_keys = G.STAGE, S.known_voucher_keys
local saved_state, saved_persona = G.NEURO.state, G.NEURO.persona
Dev.set(true)
check("dev scenario activates", Dev.active == true)
check("entering the harness parks the AI loop", G.NEURO.dev_preview_active == true)
check("the harness locks itself against hot reload while active",
  Dev._hot_reload_locked() == true)

local function voucher_count()
  local n = 0
  for _, v in pairs(G.GAME.used_vouchers or {}) do if v then n = n + 1 end end
  return n
end

local function showcase_key()
  local sc = S.joker_showcase
  if not sc then return "-" end
  local c = sc.card
  local key = c and c.config and c.config.center and c.config.center.key
  return tostring(sc.label) .. ":" .. tostring(key)
end

local function facedown_count()
  local n = 0
  for _, area in ipairs({ G.pack_cards, G.jokers, G.consumeables, G.hand }) do
    for _, c in ipairs((area and area.cards) or {}) do
      if c and c.facing == "back" then n = n + 1 end
    end
  end
  return n
end

local function fingerprint()
  return table.concat({
    tostring(G.NEURO.state),
    (G.STAGE == G.STAGES.RUN) and "run" or "norun",
    #G.jokers.cards, #G.consumeables.cards,
    #G.shop_jokers.cards, #G.shop_vouchers.cards, #G.shop_booster.cards,
    G.pack_cards and #G.pack_cards.cards or -1,
    facedown_count(),
    G.GAME.pack_choices or -1,
    S.buy_showcase and (tostring(S.buy_showcase.area) .. ":" .. tostring(S.buy_showcase.name)) or "-",
    showcase_key(),
    voucher_count(),
    (G.GAME.blind and (G.GAME.blind.boss and "boss" or "blind")) or "-",
    tostring(G.NEURO.seed_pasted),
    tostring(G.GAME.selected_back),
  }, "|")
end

local SAMPLES = { 0, 1.3, 2.6, 3.9, 5.2 }
local function replay(sig)
  sig = sig or fingerprint
  local seq = {}
  for _, dt in ipairs(SAMPLES) do
    mount(BASE + dt)
    seq[#seq + 1] = sig()
    unmount()
  end
  return table.concat(seq, "//")
end

local function bank_label(prefix)
  for i = #PRINTS, 1, -1 do PRINTS[i] = nil end
  Dev.draw_buttons()
  for _, e in ipairs(PRINTS) do
    if e.text:sub(1, #prefix) == prefix then return e end
  end
end

local function bank_exact(text)
  for i = #PRINTS, 1, -1 do PRINTS[i] = nil end
  Dev.draw_buttons()
  for _, e in ipairs(PRINTS) do
    if e.text == text then return e end
  end
end

local function open_tweak()
  local tb = bank_label("TWEAK")
  if tb then Dev.mousepressed(tb.x, tb.y, 1) end
end

local function set_bank(header, value)
  local prefix, want = header .. ": ", header .. ": " .. value
  if not bank_label(prefix) then open_tweak() end
  local hdr = bank_label(prefix)
  if not hdr then return false end
  if hdr.text == want then return true end
  for _ = 1, 80 do
    Dev.mousepressed(hdr.x, hdr.y, 1)
    local h = bank_label(prefix)
    if not h then return false end
    if h.text == want then return true end
    if h.text == hdr.text then
      local vb = bank_exact(value)
      if vb then Dev.mousepressed(vb.x, vb.y, 1) end
      h = bank_label(prefix)
      if h then Dev.mousepressed(h.x, h.y, 1) end
      h = bank_label(prefix)
      return h ~= nil and h.text == want
    end
    hdr = h
  end
  return false
end

local Acquire = require("render.panels.acquire")
local Pack = require("render.panels.pack")

local AFONT = FONT
local function acquire_ctx(now)
  local function ACLR() return { 0.6, 0.6, 0.6, 1 } end
  local APAL = setmetatable({}, { __index = function() return ACLR() end })
  return {
    theme = { pk = "hiyori", persona_evil = false, persona_neuro = false, _pal = APAL,
      WHITE = { 1, 1, 1, 1 }, p = ACLR(), pg = ACLR(), bg = ACLR(), ACC = ACLR(), FR = ACLR(),
      FRD = ACLR(), GOLD = ACLR(), DIM = ACLR(), font = AFONT, cfont = AFONT,
      cfont_title = AFONT, cfont_small = AFONT, cfont_micro = AFONT,
      panel_font_small = AFONT, font_title = AFONT },
    motion = { now = now, pulse = 0.5, dt = 0.05, shimr = 0.5, shimg = 0.5, shimb = 0.5 },
    metrics = { cn = function(v) return v end, sw = 1920, sh = 1080, U = 4, GUT = 12,
      TRACK = 2, TRACK_SM = 1, text_h = 12 },
    data = { sn = tostring(G.NEURO.state or "SHOP"), pack_rows = {} },
    draw = { trunc = function(str) return str end,
      wrapped_lines = function(str) return { tostring(str) } end,
      draw_colored_desc = function() end,
      draw_desc_lines = function() end, print_colored_desc = function() end,
      showcase_type_colors = function() return ACLR(), ACLR() end },
    center_max_w = 640, center_cx = 960, center_top_y = 8,
  }
end

G.TIMERS.REAL = BASE
Dev.select(scene_index("shop"))
check("the main row names the situation and the playback",
  bank_label("SCENE:") ~= nil and bank_label("PLAY:") ~= nil and bank_label("SPEED:") ~= nil
  and bank_label("PERSONA:") ~= nil and bank_exact("REPLAY") ~= nil
  and bank_exact("TWEAK") ~= nil)
check("the main row reads its current values without opening anything",
  bank_label("SCENE:").text == "SCENE: " .. SCENES[scene_index("shop")].label
  and bank_label("PLAY:").text == "PLAY: loop",
  bank_label("SCENE:").text .. " / " .. bank_label("PLAY:").text)
check("the axis machinery is not on screen until it is asked for",
  bank_label("STATE:") == nil and bank_label("MOD:") == nil and bank_label("CARD:") == nil
  and bank_label("VIEWPORT:") == nil and bank_label("MENU:") == nil)
check("no value list leaks out while nothing is open",
  bank_exact("BLIND_SELECT") == nil and bank_exact(SCENES[2].label) == nil)
local prints = {}
for i, sc in ipairs(SCENES) do
  G.TIMERS.REAL = BASE
  Dev.select(i)
  prints[sc.id] = replay()
end

local SUPPRESSION_TWINS = { packclaim = "pick" }
check("packclaim renders exactly like pick -- the claim's receipt adds nothing to the screen",
  prints.packclaim == prints.pick, "packclaim ~= pick")

for i, sc in ipairs(SCENES) do
  for j = i + 1, #SCENES do
    local other = SCENES[j]
    if SUPPRESSION_TWINS[sc.id] ~= other.id and SUPPRESSION_TWINS[other.id] ~= sc.id then
      check(sc.id .. " and " .. other.id .. " do not render the same thing",
        prints[sc.id] ~= prints[other.id], sc.id .. " == " .. other.id)
    end
  end
end

G.TIMERS.REAL = BASE
Dev.select(scene_index("shop"))
mount(BASE)
check("shop arms a showcase", S.joker_showcase ~= nil)
check("showcase is stamped on TIMERS.REAL, not love.timer",
  S.joker_showcase and S.joker_showcase.started == BASE, S.joker_showcase and S.joker_showcase.started)
check("buy receipt is stamped on TIMERS.REAL, not love.timer",
  S.buy_showcase and S.buy_showcase.started == BASE,
  S.buy_showcase and S.buy_showcase.started)

check("buy receipt came from the production queue",
  S.buy_showcase ~= nil and S.buy_showcase.area == "shop_jokers"
  and type(S.buy_showcase.name) == "string" and type(S.buy_showcase.started) == "number",
  S.buy_showcase and (tostring(S.buy_showcase.area) .. ":" .. tostring(S.buy_showcase.name)))
check("showcase label comes from the real classifier",
  S.joker_showcase ~= nil
  and S.joker_showcase.label == Showcase.card_set_label(S.joker_showcase.card),
  S.joker_showcase and S.joker_showcase.label)
check("the showcase card is the card the receipt bought",
  S.joker_showcase and S.buy_showcase and S.joker_showcase.card == S.buy_showcase.card)
check("the bought card really joined the joker row",
  (function()
    for _, c in ipairs(G.jokers.cards) do
      if c == (S.buy_showcase and S.buy_showcase.card) then return true end
    end
    return false
  end)())

check("preview runs with the run stage set", G.STAGE == G.STAGES.RUN, tostring(G.STAGE))
unmount()

mount(BASE + 0.5)
check("the played receipt keeps the start it was filed with",
  S.buy_showcase and S.buy_showcase.started == BASE,
  S.buy_showcase and S.buy_showcase.started)
unmount()
mount(BASE + Showcase.BUY_SHOWCASE_DURATION + 0.05)
check("the played receipt retires on the shipping schedule instead of hanging forever",
  S.buy_showcase == nil, S.buy_showcase and S.buy_showcase.started)
unmount()

G.TIMERS.REAL = BASE
Dev.select(scene_index("shop"))
do
  local paired, committed_at, receipt_gone_by, js_morphed = false, nil, nil, false
  for step = 0, 40 do
    local t = BASE + step * 0.05
    mount(t)
    paired = paired or (Acquire.pair(t) == true)
    Acquire.draw(acquire_ctx(t))
    local sc = S.buy_showcase
    if sc and sc._morph_at and not committed_at then committed_at = sc._morph_at - BASE end
    if committed_at and not sc and not receipt_gone_by then receipt_gone_by = t - BASE end
    js_morphed = js_morphed or (S.joker_showcase and S.joker_showcase._morphed) or false
    unmount()
  end
  check("the shop take pairs the receipt with its showcase", paired == true)
  check("the morph commits at the receipt's hold, not before",
    committed_at ~= nil and math.abs(committed_at - Acquire.TL.soft.HOLD) <= 0.06,
    tostring(committed_at))
  check("the receipt is consumed by the end of the morph",
    receipt_gone_by ~= nil
    and receipt_gone_by <= Acquire.TL.soft.HOLD + Acquire.TL.soft.MORPH + 0.11,
    tostring(receipt_gone_by))
  check("the showcase carries on as the morphed panel", js_morphed == true)
end

check("the hold pin clears the fade-in and stops short of the fade-out",
  Dev.BUY_PIN_PHASE > Showcase.BUY_SHOWCASE_FADE_IN
  and Dev.BUY_PIN_PHASE < (Showcase.BUY_SHOWCASE_DURATION - Showcase.BUY_SHOWCASE_FADE_OUT),
  Dev.BUY_PIN_PHASE)
do
  local ok_n, neuro_deco = pcall(require, "render.panels.acquire_neuro")
  local min_hold = math.min(Acquire.TL.soft.HOLD,
    ok_n and neuro_deco.TL.HOLD or math.huge)
  check("the hold pin never reaches any timeline's morph point",
    Dev.BUY_PIN_PHASE < min_hold, Dev.BUY_PIN_PHASE .. " vs " .. min_hold)
end
check("the showcase pin clears its own fade-in and stops short of its fade-out",
  Dev.SHOWCASE_PIN_PHASE > Showcase.JOKER_SHOWCASE_FADE_IN
  and Dev.SHOWCASE_PIN_PHASE
    < (Showcase.JOKER_SHOWCASE_DURATION - Showcase.JOKER_SHOWCASE_FADE_OUT),
  Dev.SHOWCASE_PIN_PHASE)

G.TIMERS.REAL = BASE
Dev.select(scene_index("shop"))
check("the bank offers a PLAY category", set_bank("PLAY", "hold") == true)
mount(BASE)
unmount()
mount(BASE + 0.5)
check("hold pins the receipt to a readable phase, not to its fade-in origin",
  S.buy_showcase and S.buy_showcase.started == BASE + 0.5 - Dev.BUY_PIN_PHASE,
  S.buy_showcase and S.buy_showcase.started)
check("the pinned receipt is actually visible",
  S.buy_showcase and Showcase.buy_alpha(S.buy_showcase, BASE + 0.5) > 0.9,
  S.buy_showcase and Showcase.buy_alpha(S.buy_showcase, BASE + 0.5))
check("hold pins the showcase on the same clock",
  S.joker_showcase and S.joker_showcase.started == BASE + 0.5 - Dev.SHOWCASE_PIN_PHASE,
  S.joker_showcase and S.joker_showcase.started)
unmount()
mount(BASE + 30)
check("a held receipt outlives its shipping duration, which is the point of holding it",
  S.buy_showcase ~= nil)
unmount()
set_bank("PLAY", "loop")

local src = io.open("hud/dev_scenario.lua", "rb"):read("*a")

for _, field in ipairs({ "hands_left", "discards_left" }) do
  check("no preset feeds " .. field .. ", which nothing renders", src:find(field, 1, true) == nil)
end

G.TIMERS.REAL = BASE
Dev.select(scene_index("shop"))
mount(BASE)
check("shop left a showcase to clear", S.joker_showcase ~= nil)
unmount()
G.TIMERS.REAL = BASE
Dev.select(scene_index("slots"))
mount(BASE)
check("slots clears the showcase it does not own", S.joker_showcase == nil)
check("slots clears the buy receipt it does not own", S.buy_showcase == nil)
unmount()

check("unmount hands the live G.GAME back", G.GAME == live_game, tostring(G.GAME))
check("unmount hands the live areas back", G.jokers == live_jokers, tostring(G.jokers))
check("unmount hands the live state back", G.NEURO.state == saved_state, tostring(G.NEURO.state))
check("unmount leaves no fixture in hud.state",
  S.buy_showcase == nil and S.joker_showcase == nil and S.voucher_game_ref == nil)
check("the AI loop stays parked while unmounted", G.NEURO.dev_preview_active == true)
check("the live G.GAME was never written through", live_game.dollars == 25
  and live_game.pseudorandom == nil and live_game.round_resets == nil, tostring(live_game.dollars))

local BUY_SCENES = { { id = "shop", steady = true }, { id = "toasts", steady = false } }
for _, bs in ipairs(BUY_SCENES) do
  G.TIMERS.REAL = 1000
  Dev.select(scene_index(bs.id))
  set_bank("PLAY", "hold")
  local gaps, areas = 0, {}
  for step = 1, 400 do
    mount(1000 + step * 0.05)
    if step > 1 then
      if S.buy_showcase == nil then gaps = gaps + 1
      else areas[tostring(S.buy_showcase.area)] = true end
    end
    unmount()
  end
  check(bs.id .. " keeps the banner on screen for the whole held preview", gaps == 0, gaps .. " gaps")
  local n = 0
  for _ in pairs(areas) do n = n + 1 end
  if bs.steady then
    check(bs.id .. " shows one steady banner variant while held", n == 1, n)
  else
    check(bs.id .. " cycles through several banner variants while held", n > 1, n)
  end
  set_bank("PLAY", "loop")
end

do
  G.TIMERS.REAL = 2000
  Dev.select(scene_index("shop"))
  local gaps, shown = 0, 0
  for step = 1, 300 do
    mount(2000 + step * 0.05)
    if S.buy_showcase == nil then gaps = gaps + 1 else shown = shown + 1 end
    unmount()
  end
  check("loop retires the banner and brings it back", gaps > 20 and shown > 20,
    shown .. " up / " .. gaps .. " down")
end

do
  G.TIMERS.REAL = 3000
  Dev.select(scene_index("shop"))
  set_bank("PLAY", "once")
  local late = 0
  for step = 1, 400 do
    local t = 3000 + step * 0.05
    mount(t)
    if t >= 3000 + Dev.EVENTS.buy.span + 0.5 and S.buy_showcase ~= nil then late = late + 1 end
    unmount()
  end
  check("once never re-fires the take", late == 0, late)
  set_bank("PLAY", "loop")
end

do
  G.TIMERS.REAL = 4000
  Dev.select(scene_index("shop"))
  for step = 1, 60 do mount(4000 + step * 0.05); unmount() end
  mount(4003)
  local aged = S.buy_showcase == nil and S.joker_showcase ~= nil
  unmount()
  check("the take has aged past its receipt before REPLAY", aged, tostring(aged))
  local rb = bank_label("REPLAY")
  check("the bank draws a REPLAY button", rb ~= nil)
  check("REPLAY takes the click", Dev.mousepressed(rb.x, rb.y, 1) == true)
  mount(4003.05)
  check("REPLAY refiles the receipt from the top",
    S.buy_showcase ~= nil and S.buy_showcase.started == 4003.05,
    S.buy_showcase and S.buy_showcase.started)
  unmount()
end

do
  local live_timers = G.TIMERS
  G.TIMERS.REAL = 5000
  Dev.select(scene_index("shop"))
  check("the bank offers a SPEED category", set_bank("SPEED", "1/4x") == true)
  mount(5000)
  check("a scaled take installs a clock override in place of the live table",
    G.TIMERS ~= live_timers, tostring(G.TIMERS))
  local t0 = S.buy_showcase and S.buy_showcase.started
  unmount()
  check("unmounting hands the live clock table back",
    G.TIMERS == live_timers, tostring(G.TIMERS))
  mount(5001)
  local held = S.buy_showcase ~= nil
  local elapsed = S.buy_showcase and (5000 + 0.25 - S.buy_showcase.started)
  unmount()
  check("a quarter-speed take is still on screen a full second in", held, tostring(held))
  check("a second of wall clock advanced the show clock by a quarter",
    t0 == 5000 and elapsed ~= nil and math.abs(elapsed - 0.25) < 1e-9,
    tostring(t0) .. " / " .. tostring(elapsed))
  set_bank("SPEED", "1x")
  G.TIMERS.REAL = 5100
  Dev.select(scene_index("shop"))
  mount(5100)
  check("1x leaves the show clock identical to the live clock",
    S.buy_showcase and S.buy_showcase.started == 5100,
    S.buy_showcase and S.buy_showcase.started)
  unmount()
  check("the clock override is gone once unmounted",
    G.TIMERS == live_timers and G.TIMERS.REAL == 5100, G.TIMERS.REAL)
end

local function motion_sig(t)
  local bs, js = S.buy_showcase, S.joker_showcase
  local anim, egg = G.NEURO.login_anim, G.NEURO.egg
  return table.concat({
    bs and string.format("%.2f|%s", Showcase.buy_alpha(bs, t), tostring(bs.area)) or "-",
    js and string.format("%.2f", t - (js.started or t)) or "-",
    anim and string.format("%.2f", t - (anim.start or t)) or "-",
    egg and string.format("%.2f", (egg.expires_at or t) - t) or "-",
    tostring(G.NEURO.state),
    tostring(G.GAME.dollars), tostring(G.GAME.pack_choices),
    #(S.pack_winners or {}), S.pack_losers and #S.pack_losers or -1,
    voucher_count(),
  }, "|")
end

local STEP_EVENTS = { leaveshop = true, leavepack = true, picklive = true, picklast = true }

local EVENT_FLOOR = {
  buy = 77,
  buyuse = 29,
  cookie = 74,
  crosscut = 8,
  gain = 8,
  lastcons = 48,
  leavepack = 2,
  leaveshop = 2,
  login = 87,
  money = 3,
  packclaim = 3,
  packfinal = 3,
  packtear = 3,
  pick = 3,
  picklast = 2,
  picklate = 3,
  picklive = 2,
  pickmore = 3,
  pickmorph = 29,
  shoptopack = 9,
  showcase = 77,
  swapcons = 32,
  toasts = 20,
  usecard = 29,
  usecons_shop = 9,
  voucher = 77,
  voucher_backlog = 73,
}

for _, ev in ipairs(Dev.axis("event").values) do
  G.TIMERS.REAL = 6000
  Dev.select(scene_index("shop"))
  check("EVENT " .. ev.id .. " is wired to a take", Dev.EVENTS[ev.id] ~= nil, ev.id)
  set_bank("EVENT", ev.label)
  local span = (Dev.EVENTS[ev.id] or {}).span or 4
  local seen, n_seen = {}, 0
  local steps = math.ceil((span * 2 + 0.4) / 0.05)
  for step = 0, steps do
    local t = 6000 + step * 0.05
    mount(t)
    local sig = motion_sig(t)
    if not seen[sig] then seen[sig] = true; n_seen = n_seen + 1 end
    unmount()
  end
  if ev.id == "none" then
    check("EVENT none is the only still frame in the category", n_seen == 1, n_seen)
  elseif ev.id == "boosteropen" then
    check("EVENT boosteropen draws nothing -- the pack cinematic owns that beat", n_seen == 1, n_seen)
  elseif STEP_EVENTS[ev.id] then
    local floor = EVENT_FLOOR[ev.id] or 2
    check("EVENT " .. ev.id .. " takes its step, and the take restores it (>= " .. floor .. ")",
      n_seen >= floor, n_seen)
  else
    local floor = EVENT_FLOOR[ev.id] or 3
    check("EVENT " .. ev.id .. " puts motion on screen when played (>= " .. floor .. ")",
      n_seen >= floor, n_seen)
  end
end
G.TIMERS.REAL = BASE
Dev.select(scene_index("shop"))

check("lost and refused are receipt-only", Acquire.RECEIPT_ONLY.lost == true
  and Acquire.RECEIPT_ONLY.refused == true)
check("a verb whose card the engine consumes is not morph-eligible",
  Acquire.MORPH_AREAS.use == nil and Acquire.MORPH_AREAS.shop_use == nil
  and Acquire.MORPH_AREAS.booster_pick == nil)
check("the buy verbs that keep the same card table are morph-eligible",
  Acquire.MORPH_AREAS.shop_jokers == true and Acquire.MORPH_AREAS.shop_vouchers == true)
G.TIMERS.REAL = 7000
Dev.select(scene_index("toasts"))
set_bank("PLAY", "hold")
local verb_seen, fold_hits = {}, 0
for step = 0, 700 do
  local t = 7000 + step * 0.05
  mount(t)
  if Acquire.pair(t) == true or (S.buy_showcase and S.buy_showcase._morph_at) then
    fold_hits = fold_hits + 1
  end
  local sc = S.buy_showcase
  if sc then
    local key = tostring(sc.area) .. "|" .. tostring(sc.name)
    local e = verb_seen[key] or { area = tostring(sc.area), name = tostring(sc.name) }
    e.cost = sc.cost
    e.card = sc.card
    e.code = e.code or sc.code
    if sc.effect then e.effect = sc.effect end
    if sc.levels then e.levels_pending = true end
    verb_seen[key] = e
  end
  unmount()
end
set_bank("PLAY", "loop")
check("the held receipt cycle never pairs or morphs", fold_hits == 0, fold_hits)
do
  if bank_label("STATE:") then open_tweak() end
  local tb = bank_exact("TWEAK")
  Dev.mousepressed(tb.x, tb.y, 1)
  check("TWEAK reveals the axes, values and all",
    bank_label("STATE:") ~= nil and bank_label("MOD:") ~= nil and bank_label("EVENT:") ~= nil
    and bank_label("VIEWPORT:") ~= nil)
  check("a revealed axis still reads its own value without opening a list",
    bank_label("STATE:").text == "STATE: SHOP", bank_label("STATE:").text)
  check("revealing the axes opens no list of its own", bank_exact("BLIND_SELECT") == nil)
  tb = bank_exact("TWEAK")
  Dev.mousepressed(tb.x, tb.y, 1)
  check("TWEAK puts the machinery away again", bank_label("STATE:") == nil)
end

local n_palettes = 0
for _ in pairs(Palette.PALETTES) do n_palettes = n_palettes + 1 end
local seen_personas, n_seen = {}, 0
for _ = 1, n_palettes do
  local btn = bank_label("PERSONA:")
  check("the persona button stays clickable", btn ~= nil)
  G.TIMERS.REAL = BASE
  Dev.mousepressed(btn.x, btn.y, 1)
  check("stepping the persona opens no list", bank_exact("evil") == nil)
  mount(BASE)
  local persona = G.NEURO.persona
  unmount()
  check("persona " .. tostring(persona) .. " is a real palette",
    Palette.PALETTES[persona] ~= nil, tostring(persona))
  if not seen_personas[persona] then
    seen_personas[persona] = true
    n_seen = n_seen + 1
  end
end
check("the persona button reaches every palette", n_seen == n_palettes, n_seen .. "/" .. n_palettes)

do
  local btn = bank_label("PERSONA:")
  G.TIMERS.REAL = BASE
  Dev.mousepressed(btn.x, btn.y, 1)
  local fwd = bank_label("PERSONA:").text
  G.TIMERS.REAL = BASE
  Dev.mousepressed(btn.x, btn.y, 2)
  check("right click walks the axis backwards", bank_label("PERSONA:").text == btn.text,
    fwd .. " -> " .. bank_label("PERSONA:").text)
end

do
  open_tweak()
  local hb = bank_label("STATE:")
  Dev.mousepressed(hb.x, hb.y, 1)
  check("a long axis opens its list", bank_exact("BLIND_SELECT") ~= nil)
  hb = bank_label("MOD:")
  Dev.mousepressed(hb.x, hb.y, 1)
  check("opening another axis closes the first",
    bank_exact("Polychrome") ~= nil and bank_exact("BLIND_SELECT") == nil)
  hb = bank_label("MOD:")
  Dev.mousepressed(hb.x, hb.y, 1)
  check("clicking the open header closes its list", bank_exact("Polychrome") == nil)
  local before = bank_label("STATE:").text
  hb = bank_label("STATE:")
  Dev.mousepressed(hb.x, hb.y, 2)
  check("right click steps a long axis without opening it",
    bank_label("STATE:").text ~= before and bank_exact("BLIND_SELECT") == nil,
    before .. " -> " .. bank_label("STATE:").text)
  open_tweak()
end

G.TIMERS.REAL = BASE
Dev.select(scene_index("shop"))
local scene_hdr = bank_label("SCENE:")
check("the bank draws a scene header", scene_hdr ~= nil)
Dev.mousepressed(scene_hdr.x, scene_hdr.y, 1)
for _, sc in ipairs(SCENES) do
  G.TIMERS.REAL = BASE
  local btn = bank_exact(sc.label)
  check("the scene list offers " .. sc.id, btn ~= nil, sc.label)
  if btn then
    check("scene button " .. sc.id .. " takes the click", Dev.mousepressed(btn.x, btn.y, 1) == true)
    check("scene button " .. sc.id .. " selects its own situation", replay() == prints[sc.id])
    local hdr = bank_label("SCENE:")
    check("the header names the situation you picked", hdr.text == "SCENE: " .. sc.label, hdr.text)
  end
end

do
  G.TIMERS.REAL = BASE
  Dev.select(scene_index("shop"))
  check("the open STATE list installs the value it names",
    set_bank("STATE", "BLIND_SELECT") == true)
  mount(BASE)
  check("clicking a value button installs that value", G.NEURO.state == "BLIND_SELECT",
    tostring(G.NEURO.state))
  unmount()
end

do
  G.TIMERS.REAL = BASE
  Dev.select(scene_index("shop"))
  check("the bank offers a viewport", set_bank("VIEWPORT", "1280x720") == true)
  mount(BASE)
  check("the viewport override rules the mounted window",
    love.graphics.getWidth() == 1280 and love.graphics.getHeight() == 720,
    love.graphics.getWidth() .. "x" .. love.graphics.getHeight())
  unmount()
  check("the viewport override restores on unmount",
    love.graphics.getWidth() == 1920 and love.graphics.getHeight() == 1080,
    love.graphics.getWidth() .. "x" .. love.graphics.getHeight())
  check("a viewport is framing, not content: a new situation never steals it back",
    (function()
      Dev.select(scene_index("toasts"))
      return bank_label("VIEWPORT:").text == "VIEWPORT: 1280x720"
    end)(), bank_label("VIEWPORT:") and bank_label("VIEWPORT:").text)
  check("the viewport walks back to native", set_bank("VIEWPORT", "native") == true)
end

local function card_sig(c)
  if not c then return "-" end
  local ab = c.ability or {}
  local ed = "-"
  if c.edition then for k in pairs(c.edition) do ed = k break end end
  return table.concat({
    tostring(c.config and c.config.center and c.config.center.key), ed, tostring(c.seal),
    tostring(ab.enhancement), tostring(ab.eternal), tostring(ab.rental), tostring(ab.perishable),
    tostring(c.debuff), tostring(c.facing), tostring(c.cost),
  }, ",")
end

local function world_sig()
  return table.concat({
    fingerprint(),
    tostring(G.NEURO.persona),
    tostring(G.NEURO.dev_preview_active),
    card_sig(G.shop_jokers.cards[1]),
    S.buy_showcase and tostring(S.buy_showcase.cost) or "-",
    tostring(G.GAME.dollars),
    G.NEURO.login_anim and "login" or "-",
    G.NEURO.egg and "egg" or "-",
    G.NEURO.dev_footer
      and (tostring(G.NEURO.dev_footer.phase) .. "@" .. tostring(G.NEURO.dev_footer.dur)) or "-",
    tostring(G.GAME.current_round.reroll_cost),
    #G.hand.cards, #G.deck.cards,
    tostring(love.graphics.getWidth()) .. "x" .. tostring(love.graphics.getHeight()),
  }, "|")
end

do
  mount(BASE)
  Dev.select(scene_index("shop"))
  local pc = G.playing_cards
  check("the harness gives the run a master playing-card list",
    type(pc) == "table" and #pc == #G.hand.cards + #G.deck.cards,
    type(pc) == "table" and (#pc .. " vs " .. (#G.hand.cards + #G.deck.cards)) or tostring(pc))
  local on_list = {}
  if type(pc) == "table" then for _, c in ipairs(pc) do on_list[c] = true end end
  local all = true
  for _, area in ipairs({ G.hand, G.deck }) do
    for _, c in ipairs(area.cards) do all = all and on_list[c] == true end
  end
  check("every card in hand and deck is on that list", all)
  unmount()
  check("the master list is handed back on unmount", G.playing_cards == nil,
    tostring(G.playing_cards))
end

local AXIS_WALKS = { "STATE", "CARD", "MOD", "LAYOUT", "PERSONA", "EVENT", "MENU", "VIEWPORT", "PINS" }
for _, header in ipairs(AXIS_WALKS) do
  local prefix = header .. ": "
  G.TIMERS.REAL = BASE
  Dev.select(scene_index("shop"))
  if bank_label(prefix) == nil then open_tweak() end
  check("the bank draws header " .. header, bank_label(prefix) ~= nil)
  local first, sigs, n_values, dupe = nil, {}, 0, nil
  while n_values < 64 do
    local btn = bank_label(prefix)
    if not btn then break end
    if first == nil then first = btn.text
    elseif btn.text == first then break end
    n_values = n_values + 1
    local sig = replay(world_sig)
    local function is_twin(t) return t ~= nil and t:find("Claim %+ receipt") ~= nil end
    if sigs[sig] and not (is_twin(btn.text) or is_twin(sigs[sig])) then
      dupe = dupe or (sigs[sig] .. " == " .. btn.text)
    end
    sigs[sig] = btn.text
    G.TIMERS.REAL = BASE
    btn = bank_label(prefix)
    Dev.mousepressed(btn.x, btn.y, 2)
  end
  check("axis " .. header .. " offers more than one value", n_values > 1, n_values)
  check("axis " .. header .. " has no value the renderer cannot tell apart", dupe == nil, dupe)
  check("axis " .. header .. " returns to where it started", bank_label(prefix).text == first)
  check("axis " .. header .. " reaches every value it declares",
    n_values == #Dev.axis(header:lower()).values,
    n_values .. "/" .. #Dev.axis(header:lower()).values)
end

local function acq_tl()
  local ok, deco = pcall(require, "render.panels.acquire_neuro")
  return (ok and type(deco) == "table" and deco.TL) or Acquire.TL.soft
end

local function beat_ids()
  local ids = {}
  for _, v in ipairs(Dev.axis("beat").values) do ids[#ids + 1] = v.id end
  return table.concat(ids, ",")
end

do
  G.TIMERS.REAL = 9000
  Dev.select(scene_index("shop"))
  check("the main row offers BEAT", bank_label("BEAT:") ~= nil)
  check("BEAT defaults to off", bank_label("BEAT:").text == "BEAT: off",
    bank_label("BEAT:").text)
  check("a morph scene exposes the acquire phases",
    beat_ids() == "off,a_in,a_hold,a_morph,a_full,a_out", beat_ids())
  G.TIMERS.REAL = 9000
  Dev.select(scene_index("pick"))
  check("a pack scene exposes the pack beats",
    beat_ids() == "off,p_anoint,p_glide,p_shrink,p_hold,p_exit", beat_ids())
  G.TIMERS.REAL = 9000
  Dev.select(scene_index("slots"))
  check("a scene with no cinematic offers only off", beat_ids() == "off", beat_ids())
  check("an unreachable beat cannot be selected", set_bank("BEAT", "MORPH") == false)
end

do
  G.TIMERS.REAL = 9100
  Dev.select(scene_index("shop"))
  check("the bank walks BEAT to MORPH", set_bank("BEAT", "MORPH") == true)
  check("picking a beat keeps the scene preset",
    bank_label("SCENE:").text == "SCENE: " .. SCENES[scene_index("shop")].label,
    bank_label("SCENE:").text)
  local shows, morph_at, started = {}, nil, nil
  for step = 1, 120 do
    G.TIMERS.REAL = 9100 + step * 0.05
    Dev.mount()
    local show = G.TIMERS.REAL
    Showcase.update_buy(show)
    Acquire.draw(acquire_ctx(show))
    local sc = S.buy_showcase
    if step > 60 then
      shows[#shows + 1] = show
      morph_at = sc and sc._morph_at
      started = sc and sc.started
    end
    Dev.unmount()
  end
  local frozen = #shows > 1
  for i = 2, #shows do if shows[i] ~= shows[1] then frozen = false end end
  check("BEAT MORPH freezes the show clock", frozen, tostring(shows[1]) .. ".." .. tostring(shows[#shows]))
  local morph_d = acq_tl().MORPH
  check("the frozen instant is inside the morph, not on its edge",
    morph_at ~= nil and shows[#shows] > morph_at and shows[#shows] < morph_at + morph_d,
    tostring(shows[#shows]) .. " vs [" .. tostring(morph_at) .. ", " .. tostring(morph_at and morph_at + morph_d) .. "]")
  check("the morph boundary is the exported HOLD, not a copied number",
    started ~= nil and morph_at ~= nil and math.abs((morph_at - started) - acq_tl().HOLD) < 1e-9,
    tostring(morph_at and started and (morph_at - started)))
  check("the wall clock is untouched while frozen", G.TIMERS.REAL == 9100 + 120 * 0.05,
    G.TIMERS.REAL)
end

do
  G.TIMERS.REAL = 9200
  Dev.select(scene_index("shop"))
  set_bank("BEAT", "FULL")
  local show_last, js_started, js_morphed, sc_gone
  for step = 1, 120 do
    G.TIMERS.REAL = 9200 + step * 0.05
    Dev.mount()
    show_last = G.TIMERS.REAL
    Showcase.update_buy(show_last)
    Acquire.draw(acquire_ctx(show_last))
    if step > 60 then
      local js = S.joker_showcase
      js_started = js and js.started
      js_morphed = js and js._morphed or false
      sc_gone = S.buy_showcase == nil
    end
    Dev.unmount()
  end
  check("BEAT FULL parks at the first full frame", js_morphed and sc_gone
    and js_started ~= nil and show_last == js_started,
    tostring(show_last) .. " vs " .. tostring(js_started))
  check("the full boundary is HOLD + MORPH from the exports",
    js_started ~= nil and math.abs((js_started - 9200.05) - (acq_tl().HOLD + acq_tl().MORPH)) < 0.06,
    tostring(js_started and (js_started - 9200.05)))

  set_bank("BEAT", "off")
  local a, b
  G.TIMERS.REAL = 9260
  Dev.mount(); a = G.TIMERS.REAL; Dev.unmount()
  G.TIMERS.REAL = 9261
  Dev.mount(); b = G.TIMERS.REAL; Dev.unmount()
  check("BEAT off thaws the clock", b - a > 0.9, tostring(b - a))
end

do
  G.TIMERS.REAL = 9300
  Dev.select(scene_index("pick"))
  check("the pack scene walks BEAT to SHRINK", set_bank("BEAT", "SHRINK") == true)
  G.TIMERS.REAL = 9300
  Dev.select(scene_index("shop"))
  check("a new scene resets BEAT to off", bank_label("BEAT:").text == "BEAT: off",
    bank_label("BEAT:").text)
end

do
  G.TIMERS.REAL = 9400
  Dev.select(scene_index("picklate"))
  check("a late-claim pack scene exposes REFREEZE",
    beat_ids() == "off,p_anoint,p_glide,p_refreeze,p_shrink,p_hold,p_exit", beat_ids())
  check("the bank walks BEAT to REFREEZE", set_bank("BEAT", "REFREEZE") == true)

  local base = 9400
  local shows, saw_two, ct, winners, snap_loser_max = {}, false, nil, nil, nil
  local HUD = require("render.hud_overlay")
  for step = 1, 300 do
    G.TIMERS.REAL = base + step / 60
    Dev.mount()
    HUD.draw_indicator()
    if #S.pack_winners >= 2 then saw_two = true end
    if step > 250 then
      shows[#shows + 1] = G.TIMERS.REAL
      ct = S.pack_collapse_t
      snap_loser_max = S.pack_collapse_snap and S.pack_collapse_snap.loser_max
      winners = {}
      for i, w in ipairs(S.pack_winners) do winners[i] = { t0 = w.t0, _anoint = w._anoint } end
    end
    Dev.unmount()
  end
  check("BEAT REFREEZE reaches the second claim", saw_two)

  local frozen = #shows > 1
  for i = 2, #shows do if shows[i] ~= shows[1] then frozen = false end end
  check("BEAT REFREEZE freezes the show clock", frozen,
    tostring(shows[1]) .. ".." .. tostring(shows[#shows]))
  check("the frozen instant carries both claims", winners ~= nil and #winners == 2,
    winners and #winners)

  local pk_tl = require("render.panels.pack_neuro").TL
  local loser_max = snap_loser_max
    or (Pack.LOSER_D + math.max(0, (S.pack_initial_count or 1) - 1) * Pack.LOSER_SPREAD)
  local shrink_at = ct + pk_tl.ANOINT + math.max(pk_tl.GLIDE, loser_max)
  for _, w in ipairs(winners or {}) do
    local e = (w.t0 or ct) + (w._anoint or pk_tl.ANOINT) + pk_tl.GLIDE
    if e > shrink_at then shrink_at = e end
  end
  local expected = shrink_at + pk_tl.SHRINK * 0.5
  check("the refreeze boundary is the exported SHRINK midpoint, not a copied number",
    shows[1] ~= nil and math.abs(shows[1] - expected) < 1e-6,
    tostring(shows[1] and (shows[1] - expected)))

  G.TIMERS.REAL = 9500
  Dev.select(scene_index("pick"))
  check("REFREEZE is unreachable on a single-claim pack scene",
    set_bank("BEAT", "REFREEZE") == false)

  G.TIMERS.REAL = 9500
  Dev.select(scene_index("shop"))
end

Dev.set(false)
check("dev scenario deactivates", Dev.active == false)
check("leaving the harness releases the AI loop", G.NEURO.dev_preview_active == false)
check("the harness unlocks hot reload when off", Dev._hot_reload_locked() == false)
check("exit restores the run stage", G.STAGE == saved_stage, tostring(G.STAGE))
check("exit restores the engine state name", G.NEURO.state == saved_state, tostring(G.NEURO.state))
check("exit restores the persona", G.NEURO.persona == saved_persona, tostring(G.NEURO.persona))
check("exit restores the live G.GAME", G.GAME == live_game, tostring(G.GAME))
check("exit restores the voucher bookkeeping", S.known_voucher_keys == saved_voucher_keys,
  tostring(S.known_voucher_keys))
check("exit restores the showcases", S.buy_showcase == nil and S.joker_showcase == nil)

done()
