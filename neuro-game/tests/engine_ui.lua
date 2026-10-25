local M = {}

local skip = require("tests.skip_ledger")
local read = require("tests.helpers").read_file

local function bail(label, lost, why) skip.bail(label, lost, why) end

local function top_fn(src, header, file)
  local s = src:find("\n" .. header, 1, true)
  assert(s, file .. ": no " .. header)
  local e = assert(src:find("\nend\n", s + 1, true), file .. ": no end after " .. header)
  local line = select(2, src:sub(1, s):gsub("\n", "")) + 1
  return string.rep("\n", line - 1) .. src:sub(s + 1, e + 4)
end

local function indented_fn(src, opener, file, from)
  local s = src:find(opener, from or 1, true)
  assert(s, file .. ": no " .. opener)
  local bol = s
  while bol > 1 and src:sub(bol - 1, bol - 1) ~= "\n" do bol = bol - 1 end
  local indent = src:sub(bol, s - 1)
  assert(indent:match("^%s*$"), file .. ": " .. opener .. " is not at the start of a line")
  local e = assert(src:find("\n" .. indent .. "end", s, true), file .. ": no end for " .. opener)
  local stop = src:find("\n", e + 1, true) or #src
  return src:sub(s, stop - 1), s
end

local function compile(chunk, name, env)
  local fn = assert((loadstring or load)(chunk, "@" .. name))
  if env then setfenv(fn, env) end
  return fn
end

local function merge(target, ref)
  for k, v in pairs(ref) do
    if type(v) == "table" and type(target[k]) == "table" and not (type(v[1]) == "string") then
      merge(target[k], v)
    else
      target[k] = v
    end
  end
end

local function deep(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = deep(x) end
  return setmetatable(out, getmetatable(v))
end

local ANY = setmetatable({}, { __index = function(t) return t end, __call = function(t) return t end })

local loaded = nil

function M.load(label, lost_if_skipped)
  if loaded then return loaded end
  local dump = os.getenv("BALATRO_DUMP")
  if not dump or dump == "" then bail(label, lost_if_skipped, "BALATRO_DUMP is unset") end
  local smods_dir = dump .. "/../../smods"
  local src = {
    misc = read(dump .. "/functions/misc_functions.lua"),
    common = read(dump .. "/functions/common_events.lua"),
    card = read(dump .. "/card.lua"),
    tag = read(dump .. "/tag.lua"),
    back = read(dump .. "/back.lua"),
    blind = read(dump .. "/blind.lua"),
    game = read(dump .. "/game.lua"),
    s_utils = read(smods_dir .. "/src/utils.lua"),
    s_go = read(smods_dir .. "/src/game_object.lua"),
    s_loc = read(smods_dir .. "/localization/en-us.lua"),
  }
  for k, v in pairs(src) do
    if not v then bail(label, lost_if_skipped, "game dump or Steamodded source unreadable (" .. k .. ")") end
  end
  local exe = os.getenv("BALATRO_EXE")
  if not exe or exe == "" then
    local steamapps = dump:match("^(.*/steamapps)/compatdata/")
    exe = steamapps and (steamapps .. "/common/Balatro/Balatro.exe") or nil
  end
  local loc_src
  if exe and read(exe) ~= nil and not exe:find("'", 1, true) then
    local pipe = io.popen("unzip -p '" .. exe .. "' localization/en-us.lua 2>/dev/null")
    loc_src = pipe and pipe:read("*a")
    if pipe then pipe:close() end
  end
  if not loc_src or loc_src == "" then
    bail(label, lost_if_skipped, "game localization unreadable; set BALATRO_EXE to Balatro.exe")
  end

  local LOC = assert((loadstring or load)(loc_src, "@en-us.lua"))()
  merge(LOC, assert((loadstring or load)(src.s_loc, "@smods/en-us.lua"))())

  local shade = 0
  local function colour() shade = shade + 1; return { shade / 1000, 0, 0, 1 } end
  local function palette() return setmetatable({}, { __index = function(t, k)
    local c = colour(); rawset(t, k, c); return c end }) end
  local C = palette()
  C.UI, C.SUITS, C.SECONDARY_SET, C.RARITY, C.DYN_UI, C.HAND_LEVELS = palette(), palette(), palette(),
    palette(), palette(), palette()
  local UI = { G = G, C = C, UIT = { T = 1, B = 2, C = 3, R = 4, O = 5, ROOT = 6 },
    LANG = { font = { DESCSCALE = 1 } }, FONTS = {}, ARGS = {} }
  M.UI = UI

  local env = setmetatable({}, { __index = _G, __newindex = _G })
  local chunks = {
    top_fn(src.misc, "function loc_colour(_c, _default)", "misc_functions.lua"),
    top_fn(src.misc, "function loc_parse_string(line)", "misc_functions.lua"),
    top_fn(src.misc, "function init_localization()", "misc_functions.lua"),
    top_fn(src.misc, "function localize(args, misc_cat)", "misc_functions.lua"),
    top_fn(src.misc, "function number_format(num, e_switch_point)", "misc_functions.lua"),
    top_fn(src.misc, "function copy_table(O)", "misc_functions.lua"),
    top_fn(src.misc, "function EMPTY(t)", "misc_functions.lua"),
    top_fn(src.misc, "function get_challenge_int_from_id(_id)", "misc_functions.lua"),
    top_fn(src.s_utils, "function round_number(num, precision)", "smods/utils.lua"),
    top_fn(src.s_utils, "function format_ui_value(value)", "smods/utils.lua"),
  }
  for i, c in ipairs(chunks) do compile(c, "engine_ui:" .. i, env)() end
  M.vanilla_localize = localize

  local SM = {}
  for _, name in ipairs({ "localize_box", "signed", "signed_dollars", "localize_perma_bonuses",
      "info_queue_desc_from_rows", "merge_defaults", "get_probability_vars" }) do
    local header = "function SMODS." .. name .. "("
    local s = assert(src.s_utils:find("\n" .. header, 1, true), "smods/utils.lua: no " .. header)
    local args = src.s_utils:match("%b()", s)
    compile(top_fn(src.s_utils, header .. args:sub(2), "smods/utils.lua"), "smods:" .. name, env)()
  end

  local oldlocalize = localize
  _G.localize = function(args, misc_cat)
    local ret = oldlocalize(args, misc_cat)
    if type(args) == "table" and type(ret) == "string" and args.type == "name_text" and args.vars then
      for k, v in pairs(args.vars) do
        if type(k) == "number" then ret = ret:gsub("#" .. tostring(k) .. "#", tostring(v)) end
      end
    end
    return ret
  end
  M.localize = _G.localize

  compile(top_fn(src.common, "function generate_card_ui(_c, full_UI_table, specific_vars, card_type, badges, hide_desc, main_start, main_end, card)",
    "common_events.lua"), "common_events.lua", env)()

  local EngineCards = require("tests.engine_cards")
  local Card = setmetatable({}, { __index = EngineCards.Card })
  Card.__index = Card
  M.Card = Card
  rawset(env, "Card", Card)
  local card_env = setmetatable({ Card = Card }, { __index = _G })
  compile("local Card = ...;" .. top_fn(src.card, "function Card:generate_UIBox_ability_table(vars_only)", "card.lua"),
    "card.lua", card_env)(Card)
  compile("local Card = ...;" .. top_fn(src.card, "function Card:get_h_dollars()", "card.lua"), "card.lua", card_env)(Card)
  do
    local upd = top_fn(src.card, "function Card:update(dt)", "card.lua")
    local opener = "    if G.STAGE == G.STAGES.RUN then\n"
    local s = assert(upd:find(opener, 1, true), "card.lua: Card:update has no in-run block")
    local e = assert(upd:find("\n    else\n", s, true), "card.lua: Card:update in-run block has no else")
    local lead = string.rep("\n", select(2, upd:sub(1, s + #opener - 1):gsub("\n", "")))
    M.refresh = compile("local self = ...;" .. lead .. upd:sub(s + #opener, e), "card.lua", card_env)
  end
  local Tag = {}
  compile("local Tag = ...;" .. top_fn(src.tag, "function Tag:get_uibox_table(tag_sprite, vars_only)", "tag.lua"), "tag.lua", env)(Tag)
  M.Tag = Tag
  rawset(env, "Tag", Tag)
  local Back = {}
  compile("local Back = ...;" .. top_fn(src.back, "function Back:generate_UI(other, ui_scale, min_dims, challenge)", "back.lua"), "back.lua", env)(Back)
  M.Back = Back
  local Blind = {}
  compile("local Blind = ...;" .. top_fn(src.blind, "function Blind:set_text()", "blind.lua"), "blind.lua", env)(Blind)
  M.Blind = Blind

  local go = src.s_go
  local function class_method(class_opener, method_opener)
    local at = assert(go:find(class_opener, 1, true), "game_object.lua: no " .. class_opener)
    return (indented_fn(go, method_opener, "game_object.lua", at))
  end
  local go_env = setmetatable({}, { __index = function(_, k)
    local v = rawget(_G, k)
    if v ~= nil then return v end
    return ANY
  end })
  local function method(class_opener, method_opener)
    local body = class_method(class_opener, method_opener)
    local fn_src = body:gsub("^[%w_]+%s*=%s*", "return ", 1):gsub(",%s*$", "")
    return compile(fn_src, "game_object.lua:" .. class_opener, go_env)()
  end
  local Center = { generate_ui = method("SMODS.Center = SMODS.GameObject:extend {", "generate_ui = function(self"),
    create_fake_card = function(self) return { ability = copy_table(self.config), fake_card = self.key } end }
  local Booster = { generate_ui = method("SMODS.Booster = SMODS.Center:extend {", "generate_ui = function(self") }
  local Enhancement = { generate_ui = method("SMODS.Enhancement = SMODS.Center:extend {", "generate_ui = function(self"),
    super = Center }
  local card_limit_key = method("SMODS.Edition = SMODS.Center:extend {", "card_limit_key = function(self, card)")
  local Seal = { generate_ui = method("SMODS.Seal = SMODS.GameObject:extend {", "generate_ui = function(self"),
    create_fake_card = function(self) return { ability = { seal = copy_table(self.config) }, fake_card = self.key } end }

  SMODS.Fonts, SMODS.DynaTextEffects = SMODS.Fonts or {}, SMODS.DynaTextEffects or {}
  for _, k in ipairs({ "Rarity", "Gradient", "ConsumableType" }) do
    SMODS[k] = SMODS[k] or {}
    SMODS[k].obj_buffer = SMODS[k].obj_buffer or {}
  end
  SMODS.Gradients = SMODS.Gradients or {}
  SMODS.UndiscoveredCompat = SMODS.UndiscoveredCompat or {}
  SMODS.compat_0_9_8 = SMODS.compat_0_9_8 or {}
  SMODS.Suits, SMODS.Ranks = SMODS.Suits or {}, SMODS.Ranks or {}
  SMODS.Seal = SMODS.Seal or {}
  SMODS.Seal.badge_to_key = { red_seal = "Red", blue_seal = "Blue", gold_seal = "Gold", purple_seal = "Purple" }
  SMODS.Edition = SMODS.Edition or {}
  SMODS.Enhancement = Enhancement
  SMODS.Edition.get_card_limit_key = function(card) return G.P_CENTERS[card.edition.key]:card_limit_key(card) end
  SMODS.Sticker = { obj_buffer = { "eternal", "perishable", "rental", "pinned" } }
  SMODS.Stickers = {
    eternal = { key = "eternal", hide_badge = true },
    perishable = { key = "perishable", hide_badge = true, loc_vars = function(_, _, card)
      return { vars = { card.ability.perishable_rounds or 5, card.ability.perish_tally or G.GAME.perishable_rounds } }
    end },
    rental = { key = "rental", hide_badge = true, loc_vars = function()
      return { vars = { G.GAME.rental_rate or 1 } }
    end },
    pinned = { key = "pinned" },
  }
  SMODS.calculate_context = function(ctx)
    if ctx.mod_probability then
      local n = ctx.numerator
      for _ in ipairs(SMODS.find_card("j_oops")) do n = n * 2 end
      return { numerator = n }
    end
    return {}
  end
  SMODS.find_card = function(key)
    local out = {}
    for _, j in ipairs((G.jokers and G.jokers.cards) or {}) do
      if j.config.center.key == key and not j.debuff then out[#out + 1] = j end
    end
    return out
  end
  _G.DynaText = function(args) return { config = args } end
  _G.desc_from_rows = function(rows) return { n = UI.UIT.R, nodes = rows } end
  _G.UIBox_button = function(args) return { n = UI.UIT.C, config = args } end
  _G.Node = _G.Node or {}

  local OWNED = {}
  local pack_src = indented_fn(go, "local pack_loc_vars = function(self, info_queue, card)", "game_object.lua")
  local pack_loc_vars = compile(pack_src:gsub("^local pack_loc_vars = ", "return ", 1), "game_object.lua:pack_loc_vars", go_env)()
  for at, class, key, body in go:gmatch("()SMODS%.(%w+):take_ownership%('([%w_]+)',%s*(%b{})") do
    local bol = at
    while bol > 1 and go:sub(bol - 1, bol - 1) ~= "\n" do bol = bol - 1 end
    if body:find("loc_vars", 1, true) and not go:sub(bol, at):find("--", 1, true) then
      OWNED[#OWNED + 1] = { class = class, key = key,
        obj = compile("return " .. body, "game_object.lua:" .. class .. ":" .. key, go_env)() }
    end
  end
  M.OWNED = OWNED

  local PREFIX = { Edition = "e_", Enhancement = "m_", Consumable = "c_", Voucher = "v_", Joker = "j_", Back = "b_" }
  function M.install_centers(centers)
    for _, o in ipairs(OWNED) do
      local key = (PREFIX[o.class] or "") .. o.key
      local c = centers[key]
      if c then
        c.loc_vars = o.obj.loc_vars
        if o.class == "Enhancement" then
          c.generate_ui, c.create_fake_card = Enhancement.generate_ui, Center.create_fake_card
        end
      end
    end
    local neg = centers.e_negative
    if neg then
      neg.card_limit_key = card_limit_key
      neg.card_limit_keys = { joker = "negative_SMODS_INTERNAL", consumable = "negative_consumable_SMODS_INTERNAL",
        playing_card = "negative_playing_card_SMODS_INTERNAL", generic = "negative_generic_SMODS_INTERNAL" }
    end
    for _, c in pairs(centers) do
      if type(c) == "table" then
        c.discovered, c.unlocked = true, true
        if c.set == "Booster" then
          c.generate_ui = Booster.generate_ui
          c.loc_vars = pack_loc_vars
          c.create_fake_card = Center.create_fake_card
        end
      end
    end
    return centers
  end

  function M.install_seals(seals)
    for _, s in pairs(seals) do
      s.generate_ui, s.create_fake_card, s.discovered = Seal.generate_ui, Seal.create_fake_card, true
    end
    return seals
  end

  function M.install(g)
    g.C = C
    g.UIT, g.LANG, g.FONTS, g.ARGS = UI.UIT, UI.LANG, UI.FONTS, UI.ARGS
    g.E_SWITCH_POINT = g.E_SWITCH_POINT or 100000000000
    g.localization = M.LOC
    _G.localize = M.localize
  end

  function M.proto(field)
    local body = src.game:match("self%." .. field .. "%s*=%s*(%b{})")
    assert(body, field .. " not found in game.lua")
    local t = assert((loadstring or load)("local HEX = function(s) return s end "
      .. "local localize = function(...) return M_localize(...) end return " .. body, "@game.lua:" .. field))
    setfenv(t, setmetatable({ M_localize = function(...) return M.localize(...) end }, { __index = _G }))
    local out = t()
    for k, v in pairs(out) do if type(v) == "table" then v.key = v.key or k end end
    return out
  end

  local set_ability = require("tests.fixtures.vanilla_jokers").set_ability
  function M.card(key, t)
    t = t or {}
    local center = assert(G.P_CENTERS[key], "engine_ui.card: no center " .. tostring(key))
    local ability = set_ability(center)
    if center.consumeable then ability.consumeable = deep(center.config) end
    if center.set == "Booster" or center.set == "Voucher" then
      for k, v in pairs(center.config or {}) do ability[k] = deep(v) end
    end
    t.ability = ability
    t.config = { center = center, center_key = key }
    t.cost = t.cost or center.cost
    t.sell_cost = t.sell_cost or math.max(1, math.floor((center.cost or 2) / 2))
    t.facing = t.facing or "front"
    t.base = t.base or { nominal = 0, suit_nominal = 0, face_nominal = 0, times_played = 0, suit_nominal_original = 0 }
    t.children = t.children or {}
    t.T = t.T or { x = 0, y = 0, w = 1, h = 1 }
    return setmetatable(t, Card)
  end

  function M.playing(value, suit, opts)
    opts = opts or {}
    local card = EngineCards.playing(value, suit, opts)
    local key = opts.enhancement or "c_base"
    card.config.center = G.P_CENTERS[key]
    for k, v in pairs(card.config.center.config or {}) do
      if card.ability[k] == nil then card.ability[k] = deep(v) end
    end
    card.base.colour = G.C.SUITS[suit]
    card.T = { x = 0, y = 0, w = 1, h = 1 }
    for _, f in ipairs({ "perma_x_chips", "perma_h_chips", "perma_h_x_chips", "perma_h_mult", "perma_h_x_mult",
        "perma_p_dollars", "perma_h_dollars", "perma_score", "perma_h_score", "perma_x_score", "perma_h_x_score",
        "perma_blind_size", "perma_h_blind_size", "perma_x_blind_size", "perma_h_x_blind_size", "perma_repetitions" }) do
      card.ability[f] = card.ability[f] or 0
    end
    return setmetatable(card, Card)
  end

  M.LOC = LOC
  local saved = _G.G
  _G.G = setmetatable({ localization = LOC, C = C, ARGS = {}, LANG = UI.LANG, FONTS = {}, UIT = UI.UIT },
    { __index = saved })
  init_localization()
  _G.G = saved
  M.src = src
  M.deep = deep
  loaded = M
  return M
end

local function walk(node, out, depth)
  if depth > 40 or type(node) ~= "table" then return end
  local cfg = node.config
  if type(cfg) == "table" then
    if cfg.text ~= nil then out[#out + 1] = tostring(cfg.text) end
    if cfg.text == nil and type(cfg.ref_table) == "table" and cfg.ref_value ~= nil then
      out[#out + 1] = tostring(cfg.ref_table[cfg.ref_value] or "")
    end
    local obj = cfg.object
    if type(obj) == "table" and type(obj.config) == "table" and type(obj.config.string) == "table" then
      local parts = {}
      for _, s in ipairs(obj.config.string) do
        parts[#parts + 1] = type(s) == "table" and tostring(s.string or "") or tostring(s)
      end
      out[#out + 1] = table.concat(parts, "|")
    end
  end
  if type(node.nodes) == "table" then walk(node.nodes, out, depth + 1) end
  for i = 1, #node do walk(node[i], out, depth + 1) end
end

function M.rows_text(rows)
  local out = {}
  for _, row in ipairs(rows or {}) do
    local parts = {}
    walk(row, parts, 0)
    local line = table.concat(parts):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if line ~= "" then out[#out + 1] = line end
  end
  return out
end

function M.tooltip(ui)
  local t = { name = nil, main = {}, info = {} }
  if type(ui) ~= "table" then return t end
  if type(ui.name) == "string" then
    t.name = ui.name
  elseif type(ui.name) == "table" then
    local parts = {}
    walk(ui.name, parts, 0)
    t.name = table.concat(parts, " ")
  end
  t.main = M.rows_text(ui.main)
  for _, box in ipairs(ui.info or {}) do
    t.info[#t.info + 1] = { name = box.name, rows = M.rows_text(box) }
  end
  return t
end

function M.described(set, key, vars, kind)
  local nodes = {}
  M.localize({ type = kind or "descriptions", set = set, key = key, nodes = nodes, vars = vars or {} })
  return M.rows_text(nodes)
end

return M
