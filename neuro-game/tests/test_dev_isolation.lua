rawset(_G, "NEURO_TEST", true)

local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local function noop() end
love = setmetatable({
  graphics = setmetatable({
    getFont = function() return FONT end,
    newFont = function() return FONT end,
    getWidth = function() return 1920 end,
    getHeight = function() return 1080 end,
    getScissor = function() return nil end,
    print = noop,
  }, { __index = function() return noop end }),
  timer = { getTime = function() return (G.TIMERS.REAL or 0) + 5000 end },
  math = { random = math.random, noise = function() return 0 end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

local function card(name, cost)
  return {
    config = { center = { key = "j_" .. name, set = "Joker", name = name, pos = {},
                          rarity = 1, loc_txt = { name = name } } },
    ability = { set = "Joker", name = name, mult = 0, h_mult = 0, h_mod = 0,
                t_mult = 0, t_chips = 0, x_mult = 1, extra = 0 },
    base = { name = name }, cost = cost or 4, sell_cost = 2, debuff = false,
  }
end
local area = require("tests.helpers").area

_G.G = {
  NEURO = {
    persona = "neuro", state = "SELECTING_HAND", ai_highlighted = {},
    force_inflight = false, shop_reroll_count = 2, seed_pasted = "LIVE",
  },
  GAME = {
    dollars = 41, round = 6, chips = 1200,
    seeded = false,
    pseudorandom = { seed = "REALSEED", shuffle = 0.5, hashed_seed = 12345 },
    round_resets = {
      ante = 5,
      blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" },
      blind_ante = 5,
    },
    current_round = { reroll_cost = 7, hands_left = 3, discards_left = 2 },
    used_vouchers = { v_overstock_norm = true },
    blind = { name = "The Hook", boss = true, chips = 3000, dollars = 5 },
    selected_back = { name = "Red Deck", key = "b_red" },
    pack_choices = nil,
  },
  jokers = area({ card("LiveJoker", 6) }, 5),
  consumeables = area({ card("LiveTarot", 3) }, 2),
  shop_jokers = area({ card("ShopJoker", 5) }, 2),
  shop_vouchers = area({ card("ShopVoucher", 10) }, 1),
  shop_booster = area({ card("ShopBooster", 4) }, 2),
  pack_cards = nil,
  TIMERS = { REAL = 100, TOTAL = 100, UPTIME = 100 },
  STAGE = 2, STAGES = { MAIN_MENU = 1, RUN = 2 },
  P_CENTERS = { b_red = { name = "Red Deck", key = "b_red" } },
  P_CENTER_POOLS = {}, localization = {},
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
  ARGS = {}, FUNCS = {}, STATES = { SELECTING_HAND = 1, SHOP = 2 },
  SETTINGS = { paused = false },
}
_G.SMODS = {
  current_mod = { path = "./", config = { settings = {}, colours = {} } },
  save_mod_config = function() return true end,
  Mods = {}, findModByID = function() return nil end,
}
_G.NFS = setmetatable({}, { __index = function() return function() return nil end end })

local check, done = require("tests.helpers").harness("dev isolation")

local S = require("hud.state")
local Dev = require("hud.dev_scenario")

if type(Dev.mount) ~= "function" or type(Dev.unmount) ~= "function" then
  check("hud.dev_scenario exposes mount() and unmount()", false,
    "mount=" .. type(Dev.mount) .. " unmount=" .. type(Dev.unmount))
  done()
end

local STOP = { [_G] = true, [package] = true, [package.loaded] = true, [love] = true,
               [string] = true, [table] = true, [math] = true, [os] = true, [io] = true }

local function capture(root, label, extra_stop)
  local fields, paths = {}, {}
  local stack = { root }
  paths[root] = label
  while #stack > 0 do
    local t = table.remove(stack)
    if not fields[t] then
      local rec = {}
      for k, v in pairs(t) do
        rec[k] = v
        if type(v) == "table" and not paths[v] and not STOP[v]
          and not (extra_stop and extra_stop[v]) then
          paths[v] = paths[t] .. "." .. tostring(k)
          stack[#stack + 1] = v
        end
      end
      fields[t] = rec
    end
  end
  return { fields = fields, paths = paths, root = root }
end

local function sorted_keys(t)
  local ks = {}
  for k in pairs(t) do ks[#ks + 1] = k end
  table.sort(ks, function(a, b) return tostring(a) < tostring(b) end)
  return ks
end

local IGNORE = {
  [G.TIMERS] = { REAL = true, TOTAL = true },
  [G.NEURO] = { dev_preview_active = true },
}

local function ignored(t, k)
  local set = IGNORE[t]
  return set ~= nil and set[k] == true
end

local function diff(snap)
  local tables = {}
  for t in pairs(snap.fields) do tables[#tables + 1] = t end
  table.sort(tables, function(a, b) return tostring(snap.paths[a]) < tostring(snap.paths[b]) end)
  for _, t in ipairs(tables) do
    local rec = snap.fields[t]
    local path = snap.paths[t] or tostring(t)
    for _, k in ipairs(sorted_keys(rec)) do
      local now = t[k]
      if now ~= rec[k] and not ignored(t, k) then
        return path .. "." .. tostring(k) .. ": was " .. tostring(rec[k]) ..
          ", now " .. tostring(now)
      end
    end
    for _, k in ipairs(sorted_keys(t)) do
      if rec[k] == nil and not ignored(t, k) then
        return path .. "." .. tostring(k) .. ": key added (" .. tostring(t[k]) .. ")"
      end
    end
  end
  return nil
end

local G_TABLE = G.GAME
local JOKERS = G.jokers
local BLIND_CHOICES = G.GAME.round_resets.blind_choices
local PSEUDO = G.GAME.pseudorandom

local Panel = require("hud.tuning_panel")
if Panel.is_open() then Panel.toggle() end
local panel_snap = capture(G, "G")
Panel.toggle()
local panel_paused = G.NEURO.llm_paused
G.NEURO.llm_paused = nil
local panel_open_div = diff(panel_snap)
G.NEURO.llm_paused = panel_paused
check("opening F8 changes the live world only by applying the operator pause",
  panel_paused == true and panel_open_div == nil, panel_open_div)
Panel.toggle()
check("closing F8 restores the pause and preserves live gameplay table identities",
  G.NEURO.llm_paused == nil and G.GAME == G_TABLE and G.jokers == JOKERS
    and G.GAME.pseudorandom == PSEUDO)

local g_snap = capture(G, "G")
local s_snap = capture(S, "S", { [G] = true })

check("live world snapshot is non-trivial",
  g_snap.fields[G] ~= nil and g_snap.paths[G.GAME.round_resets] == "G.GAME.round_resets",
  g_snap.paths[G.GAME.round_resets])
check("the snapshot agrees with itself before the harness runs", diff(g_snap) == nil, diff(g_snap))

local clock = 100
local function advance(dt)
  clock = clock + (dt or 1.3)
  G.TIMERS.REAL = clock
  G.TIMERS.TOTAL = clock
end

Dev.set(true)
check("dev harness activates", Dev.active == true)
check("dev_preview_active is set while the harness is on",
  G.NEURO.dev_preview_active == true, G.NEURO.dev_preview_active)

local scene_count = #(Dev.SCENES or {})
check("the harness exposes scene presets", scene_count > 0, scene_count)

local live_leak, preview_off = nil, nil
for i = 1, scene_count do
  local id = Dev.SCENES[i].id or i
  Dev.select(i)
  for _ = 1, 3 do
    advance(1.3)
    Dev.mount()
    advance(0.7)
    Dev.draw_buttons()
    advance(1.1)
    Dev.unmount()
    if G.jokers ~= JOKERS then live_leak = live_leak or (id .. ": G.jokers") end
    if G.GAME ~= G_TABLE then live_leak = live_leak or (id .. ": G.GAME") end
    if G.GAME.pseudorandom.seed ~= "REALSEED" then
      live_leak = live_leak or (id .. ": pseudorandom.seed=" .. tostring(G.GAME.pseudorandom.seed))
    end
    if G.NEURO.dev_preview_active ~= true then preview_off = preview_off or id end
  end
end

check("while unmounted mid-session the live world is back (love.update must not tick fixtures)",
  live_leak == nil, live_leak)
check("dev_preview_active stays true while unmounted (orchestrator reads it to hold the AI loop)",
  preview_off == nil, preview_off)

advance(1.3)
Dev.mount()
advance(1.3)
Dev.set(false)

check("dev harness deactivates", Dev.active == false)
check("dev_preview_active is cleared after set(false)",
  not G.NEURO.dev_preview_active, G.NEURO.dev_preview_active)

local g_div = diff(g_snap)
check("the live G is byte-for-byte the table it was before the harness ran", g_div == nil, g_div)

local s_div = diff(s_snap)
check("hud.state comes back untouched (the live animation state survives)", s_div == nil, s_div)

check("G.GAME is still the SAME table object", G.GAME == G_TABLE)
check("G.GAME.pseudorandom is still the same table", G.GAME.pseudorandom == PSEUDO)
check("G.GAME.pseudorandom.seed is still REALSEED", G.GAME.pseudorandom.seed == "REALSEED",
  G.GAME.pseudorandom.seed)
check("G.GAME.round_resets.blind_choices is still the same table",
  G.GAME.round_resets.blind_choices == BLIND_CHOICES)
check("G.GAME.round_resets.blind_choices still has its contents",
  BLIND_CHOICES.Small == "bl_small" and BLIND_CHOICES.Big == "bl_big"
    and BLIND_CHOICES.Boss == "bl_hook",
  tostring(BLIND_CHOICES.Small) .. "/" .. tostring(BLIND_CHOICES.Big) .. "/" ..
    tostring(BLIND_CHOICES.Boss))
check("G.GAME.round_resets.ante is still 5", G.GAME.round_resets.ante == 5, G.GAME.round_resets.ante)
check("G.GAME.current_round.reroll_cost is still 7", G.GAME.current_round.reroll_cost == 7,
  G.GAME.current_round.reroll_cost)
check("G.jokers is still the original area table", G.jokers == JOKERS)
check("G.NEURO.state is still the live state", G.NEURO.state == "SELECTING_HAND", G.NEURO.state)

check("hud.dev_scenario declares _hot_reload_locked (reloading it mid-mount strands live tables)",
  type(rawget(Dev, "_hot_reload_locked")) == "function",
  type(rawget(Dev, "_hot_reload_locked")))

done()
