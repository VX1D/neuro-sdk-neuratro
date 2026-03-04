local ContextCompact = {}
local Utils = require "utils"
local safe_name = Utils.safe_name
local flatten_description = Utils.flatten_description
local safe_description = Utils.safe_description
local card_description = Utils.card_description

local function compact_text(value, max_len)
  if value == nil then return "" end
  local s = value
  if type(s) == "table" then
    s = flatten_description(s) or ""
  else
    s = tostring(s)
  end
  s = s:gsub("[\r\n]+", " ")
  s = s:gsub("|", "/")
  s = s:gsub(",", ";")
  s = s:gsub("%s+", " ")
  s = s:match("^%s*(.-)%s*$") or s
  if max_len and #s > max_len then
    return s:sub(1, max_len - 3) .. "..."
  end
  return s
end

local STATE_BUDGET = {
  SELECTING_HAND = 1850,
  SHOP = 1450,
  BLIND_SELECT = 1600,
  ROUND_EVAL = 900,
  TAROT_PACK = 1500,
  PLANET_PACK = 1500,
  SPECTRAL_PACK = 1500,
  STANDARD_PACK = 1500,
  BUFFOON_PACK = 1500,
  SMODS_BOOSTER_OPENED = 1500,
  MENU = 1200,
  RUN_SETUP = 1400,
  SPLASH = 700,
  GAME_OVER = 700,
}

local function to_set(list)
  local out = {}
  if not list then return out end
  for _, key in ipairs(list) do out[key] = true end
  return out
end

local function has_action(action_set, name)
  if not action_set or not name then return false end
  return not not action_set[name]
end

local STATE_PRIORITY = {
  DEFAULT = {
    must_keep = { "CTX", "STATE" },
    drop_order = { "AH", "K", "PS", "FM", "M", "R", "DK", "CB", "C", "L", "J", "SD" },
  },
  SELECTING_HAND = {
    must_keep = { "CTX", "STATE", "B", "BD", "WIN", "HL", "HG", "H", "LA" },
    drop_order = { "PLAY", "V", "AH", "DC", "K", "PS", "FM", "M", "R", "DK", "C", "DSIM", "PLAY_PREV", "L", "CB", "J" },
  },
  SHOP = {
    must_keep = { "CTX", "STATE", "SH", "I", "LA" },
    drop_order = { "V", "H", "AH", "K", "PS", "FM", "M", "R", "C", "J" },
  },
  BLIND_SELECT = {
    must_keep = { "CTX", "STATE", "BS", "BA", "BO", "LA" },
    drop_order = { "BU", "V", "K", "PS", "FM", "M", "R", "BP", "J" },
  },
  ROUND_EVAL = {
    must_keep = { "CTX", "STATE", "RE", "REA" },
    drop_order = { "K", "PS", "FM", "M", "R" },
  },
  TAROT_PACK = {
    must_keep = { "CTX", "STATE", "PK", "PC" },
    drop_order = { "H", "K", "PS", "FM", "M", "R", "C", "J" },
  },
  PLANET_PACK = {
    must_keep = { "CTX", "STATE", "PK", "PC" },
    drop_order = { "L", "K", "PS", "FM", "M", "R", "C", "J" },
  },
  SPECTRAL_PACK = {
    must_keep = { "CTX", "STATE", "PK", "PC" },
    drop_order = { "H", "K", "PS", "FM", "M", "R", "C", "J" },
  },
  STANDARD_PACK = {
    must_keep = { "CTX", "STATE", "PK", "PC" },
    drop_order = { "DK", "H", "K", "PS", "FM", "M", "R", "C", "J" },
  },
  BUFFOON_PACK = {
    must_keep = { "CTX", "STATE", "PK", "PC" },
    drop_order = { "K", "PS", "FM", "M", "R", "C", "J" },
  },
  SMODS_BOOSTER_OPENED = {
    must_keep = { "CTX", "STATE", "PK", "PC" },
    drop_order = { "K", "PS", "FM", "M", "R", "C", "J" },
  },
  MENU = {
    must_keep = { "CTX", "STATE", "SD", "SDK" },
    drop_order = { "K", "PS", "FM", "M", "R" },
  },
  RUN_SETUP = {
    must_keep = { "CTX", "STATE", "SD", "SDK" },
    drop_order = { "K", "PS", "FM", "M", "R" },
  },
}

local function section_id(section)
  if not section then return nil end
  local first = section:match("([^\n]+)") or section
  if first:find("^STATE:") then return "STATE" end
  if first:find("^CTX_VER:") then return "CTX" end
  return first:match("^([A-Z_]+)")
end

local FP_KEYS = {
  SELECTING_HAND = { B = true, BD = true, WIN = true, HL = true, H = true, HG = true, J = true, L = true, CB = true, AH = true },
  SHOP = { SH = true, I = true, AH = true, H = true },
  BLIND_SELECT = { BS = true, BA = true, BO = true },
  ROUND_EVAL = { RE = true, REA = true },
  TAROT_PACK = { PK = true, PC = true, H = true },
  PLANET_PACK = { PK = true, PC = true, L = true },
  SPECTRAL_PACK = { PK = true, PC = true, H = true },
  STANDARD_PACK = { PK = true, PC = true, H = true, DK = true },
  BUFFOON_PACK = { PK = true, PC = true },
  SMODS_BOOSTER_OPENED = { PK = true, PC = true },
  MENU = { SD = true, SDC = true, SDK = true },
  RUN_SETUP = { SD = true, SDC = true, SDK = true },
}

FP_KEYS.SELECTING_HAND.LA = true
FP_KEYS.SHOP.LA = true
FP_KEYS.BLIND_SELECT.LA = true

local function get_pack_fallback(tbl, state_name)
  if tbl[state_name] then return tbl[state_name] end
  if state_name and (state_name:find("_PACK$") or state_name == "SMODS_BOOSTER_OPENED") then
    return tbl["BUFFOON_PACK"]
  end
  return nil
end

local function keep_fp_line(state_name, line)
  if not line or line == "" then return false end
  if line:find("^STATE:") then return true end
  if line:find("^CTX_VER:") then return true end
  local id = line:match("^([A-Z_]+)")
  if not id then return false end
  local allow = get_pack_fallback(FP_KEYS, state_name) or {}
  return not not allow[id]
end

local function concat_sections(sections)
  local out = {}
  for _, section in ipairs(sections) do
    if section then out[#out + 1] = section end
  end
  return table.concat(out, "\n")
end

local function enforce_budget(state_name, sections)
  local budget = STATE_BUDGET[state_name] or get_pack_fallback(STATE_BUDGET, state_name)
  if not budget then return sections end

  local cfg = STATE_PRIORITY[state_name] or get_pack_fallback(STATE_PRIORITY, state_name) or STATE_PRIORITY.DEFAULT
  local protected = to_set(cfg.must_keep)
  protected.CTX = true
  protected.STATE = true
  local drop_order = cfg.drop_order or STATE_PRIORITY.DEFAULT.drop_order

  local output = sections
  local payload = concat_sections(output)
  if #payload <= budget then return output end

  for _, drop_id in ipairs(drop_order) do
    if #payload <= budget then break end
    if not protected[drop_id] then
      local next_sections = {}
      local removed = false
      for _, section in ipairs(output) do
        local sid = section_id(section)
        if sid == drop_id then
          removed = true
        else
          next_sections[#next_sections + 1] = section
        end
      end
      if removed then
        output = next_sections
        payload = concat_sections(output)
      end
    end
  end

  if #payload > budget then
    local next_sections = {}
    for _, section in ipairs(output) do
      local sid = section_id(section)
      if protected[sid] then
        next_sections[#next_sections + 1] = section
      end
    end
    output = next_sections
  end

  return output
end

local function maybe_dict_encode_rows(header, rows, specs)
  if #rows < 3 then
    local plain = { header }
    for _, row in ipairs(rows) do plain[#plain + 1] = table.concat(row, ",") end
    return table.concat(plain, "\n")
  end

  local encoded_rows = {}
  for i, row in ipairs(rows) do
    encoded_rows[i] = {}
    for j, v in ipairs(row) do encoded_rows[i][j] = v end
  end

  local dict_lines = {}
  local changed = false

  for _, spec in ipairs(specs) do
    local idx = spec.index
    local prefix = spec.prefix
    local seen = {}
    local ordered = {}

    for _, row in ipairs(encoded_rows) do
      local v = row[idx] or ""
      if v ~= "" and not seen[v] then
        seen[v] = #ordered + 1
        ordered[#ordered + 1] = v
      end
    end

    if #ordered >= 2 then
      local map_parts = {}
      for i, v in ipairs(ordered) do
        map_parts[#map_parts + 1] = string.format("%s%d:%s", prefix, i, v)
      end
      dict_lines[#dict_lines + 1] = string.format("D%s|%s", prefix, table.concat(map_parts, "|"))

      for _, row in ipairs(encoded_rows) do
        local v = row[idx] or ""
        if v ~= "" then
          row[idx] = string.format("@%s%d", prefix, seen[v])
          changed = true
        end
      end
    end
  end

  local plain = { header }
  for _, row in ipairs(rows) do plain[#plain + 1] = table.concat(row, ",") end
  local plain_payload = table.concat(plain, "\n")

  if not changed then return plain_payload end

  local packed = { header }
  for _, d in ipairs(dict_lines) do packed[#packed + 1] = d end
  for _, row in ipairs(encoded_rows) do packed[#packed + 1] = table.concat(row, ",") end
  local packed_payload = table.concat(packed, "\n")

  if #packed_payload + 8 < #plain_payload then
    return packed_payload
  end

  return plain_payload
end

local function calc_interest(money)
  if not G or not G.GAME then return 0 end
  if G.GAME.modifiers and G.GAME.modifiers.no_interest then
    return 0
  end
  local amount = G.GAME.interest_amount or 1
  local cap = G.GAME.interest_cap or 25
  local units = math.min(math.floor((money or 0) / 5), math.floor(cap / 5))
  return amount * units
end

local function economy_projection()
  if not G or not G.GAME then return nil end
  local money = G.GAME.dollars or 0
  local current_round = G.GAME.current_round or {}
  local modifiers = G.GAME.modifiers or {}
  local hands_left = current_round.hands_left or 0
  local discards_left = current_round.discards_left or 0
  local blind_reward = (G.GAME.blind and G.GAME.blind.dollars) or 0
  local hands_bonus = 0
  if hands_left > 0 and not modifiers.no_extra_hand_money then
    hands_bonus = hands_left * (modifiers.money_per_hand or 1)
  end
  local discard_bonus = 0
  if discards_left > 0 and modifiers.money_per_discard then
    discard_bonus = discards_left * modifiers.money_per_discard
  end
  local interest = calc_interest(money)
  local dollars_to_be_earned = current_round.dollars_to_be_earned or 0
  return {
    blind_reward = blind_reward,
    hands_bonus = hands_bonus,
    discard_bonus = discard_bonus,
    interest = interest,
    projected_total = blind_reward + hands_bonus + discard_bonus + interest,
    end_round_earnings = dollars_to_be_earned,
  }
end

local function card_effect_summary(card)
  if not card then return "-" end
  local ability = card.ability or {}
  local effects = {}
  if ability.x_mult then effects[#effects + 1] = "x" .. tostring(ability.x_mult) .. " Mult" end
  if ability.h_mult then effects[#effects + 1] = "+" .. tostring(ability.h_mult) .. " Mult" end
  if ability.h_mod then effects[#effects + 1] = "+" .. tostring(ability.h_mod) .. " Chips" end
  if ability.c_mult then effects[#effects + 1] = "+" .. tostring(ability.c_mult) .. " Mult/card" end
  if ability.t_mult then effects[#effects + 1] = "+" .. tostring(ability.t_mult) .. " Mult/trigger" end
  if ability.d_mult then effects[#effects + 1] = "+" .. tostring(ability.d_mult) .. " Mult/discard" end
  if ability.x_chips then effects[#effects + 1] = "x" .. tostring(ability.x_chips) .. " Chips" end
  if ability.extra then
    if type(ability.extra) ~= "table" then
      effects[#effects + 1] = "extra:" .. tostring(ability.extra)
    else
      local ex = ability.extra
      local ep = {}
      local xm = tonumber(ex.xmult or ex.Xmult or ex.x_mult)
      if xm and xm ~= 1 then ep[#ep+1] = "xM=" .. string.format("%.2f", xm) end
      local em = tonumber(ex.mult)
      if em and em ~= 0 then ep[#ep+1] = "+M=" .. tostring(em) end
      local ec = tonumber(ex.chips)
      if ec and ec ~= 0 then ep[#ep+1] = "+C=" .. tostring(ec) end
      local eh = tonumber(ex.hands)
      if eh and eh ~= 0 then ep[#ep+1] = "h=" .. tostring(eh) end
      if ex.suit then ep[#ep+1] = "s=" .. tostring(ex.suit) end
      if #ep > 0 then effects[#effects + 1] = "[" .. table.concat(ep, ",") .. "]" end
    end
  end
  if ability.eternal    then effects[#effects + 1] = "eternal"    end
  if ability.perishable then effects[#effects + 1] = "perishable" end
  if ability.rental     then effects[#effects + 1] = "rental"     end

  local edition = card.edition
  if edition and type(edition) == "table" and edition.name then
    effects[#effects + 1] = compact_text(edition.name, 20)
  end

  if #effects > 0 then
    return compact_text(table.concat(effects, "/"), 64)
  end

  local desc = card_description(card, 80)
  if desc then
    return compact_text(desc, 80)
  end
  return "-"
end

local function card_description_full(card, max_len)
  if not card then return "-" end
  local t = card_description(card, max_len)
  if t and t ~= "" then return compact_text(t, max_len) end
  return "-"
end

local function joker_tags(card)
  if not card then return "-" end
  local ability = card.ability or {}
  local tags = {}
  if ability.eternal then tags[#tags + 1] = "eternal(unsellable)" end
  if ability.perishable then
    local tally = ability.perish_tally
    if tally and tally <= 1 then
      tags[#tags + 1] = "perishable(GONE_END_OF_ROUND)"
    elseif tally then
      tags[#tags + 1] = "perishable(rounds_left=" .. tostring(tally) .. ")"
    else
      tags[#tags + 1] = "perishable"
    end
  end
  if ability.rental then tags[#tags + 1] = "rental($1_per_hand)" end
  if ability.blueprint then tags[#tags + 1] = "blueprint" end
  local edition = card.edition
  if type(edition) == "table" then
    if edition.polychrome then tags[#tags + 1] = "Poly(x1.5m)"
    elseif edition.holo     then tags[#tags + 1] = "Holo(+10m)"
    elseif edition.foil     then tags[#tags + 1] = "Foil(+50c)"
    elseif edition.filtered then tags[#tags + 1] = "Filtered(50/50:retrigger_or_debuff_EOround)"
    elseif edition.name     then tags[#tags + 1] = compact_text(tostring(edition.name), 16)
    end
  end
  if #tags == 0 then return "-" end
  return compact_text(table.concat(tags, "/"), 40)
end

local function jokers_signature()
  if not G or not G.jokers or not G.jokers.cards or #G.jokers.cards == 0 then
    return "none"
  end
  local parts = {}
  for i, card in ipairs(G.jokers.cards) do
    local center = card.config and card.config.center or {}
    local ability = card.ability or {}
    local key = center.key or center.name or safe_name(card) or "?"
    local extra = ability.extra
    if type(extra) == "table" then
      extra = flatten_description(extra) or "table"
    end
    parts[#parts + 1] = table.concat({
      tostring(i),
      tostring(key),
      tostring(extra or "-"),
      ability.eternal and "E" or "-",
      ability.perishable and "P" or "-",
      ability.rental and "R" or "-",
    }, ":")
  end
  return table.concat(parts, "|")
end

local function calc_blind_target(blind_key)
  if not (G and G.GAME and G.P_BLINDS and blind_key and G.P_BLINDS[blind_key]) then
    return nil
  end
  local base = nil
  if type(get_blind_amount) == "function" then
    local ante = (G.GAME.round_resets and G.GAME.round_resets.blind_ante)
      or (G.GAME.round_resets and G.GAME.round_resets.ante)
      or 1
    local ok, result = pcall(get_blind_amount, ante)
    if ok and type(result) == "number" then
      base = result
    end
  end
  if not base then return nil end

  local blind_def = G.P_BLINDS[blind_key]
  local mult = blind_def.mult or (blind_def.config and blind_def.config.mult) or 1
  local scaling = G.GAME.starting_params and G.GAME.starting_params.ante_scaling or 1
  return math.floor(base * mult * scaling + 0.5)
end

local VALUE_SHORT = {
  Ace = "A", King = "K", Queen = "Q", Jack = "J",
  ["10"] = "10", ["9"] = "9", ["8"] = "8", ["7"] = "7",
  ["6"] = "6", ["5"] = "5", ["4"] = "4", ["3"] = "3", ["2"] = "2",
}

local function short_value(v)
  if not v then return "?" end
  return VALUE_SHORT[v] or v
end

local VALUE_RANK = {
  ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6,
  ["7"] = 7, ["8"] = 8, ["9"] = 9, ["10"] = 10,
  Jack = 11, Queen = 12, King = 13, Ace = 14,
}

local SUIT_SHORT = {
  Hearts = "H", Diamonds = "D", Clubs = "C", Spades = "S",
}

local function short_suit(s)
  if not s then return "?" end
  return SUIT_SHORT[s] or s
end

local SUIT_ORDER = { Clubs = 1, Diamonds = 2, Hearts = 3, Spades = 4 }

local ENH_SHORT = {
  m_bonus = "Bonus(+30c)",
  m_gold  = "Gold(+$3_when_scored)",
  m_stone = "Stone(no_suit_no_rank+50c_always)",
  m_steel = "Steel(x1.5m_per_copy_held_not_played)",
  m_glass = "Glass(x2m_always_then_25%_destroyed)",
  m_lucky = "Lucky(1/5:+20m_or_1/15:+20$)",
  m_mult  = "Mult(+4m)",
  m_wild  = "Wild(counts_as_any_suit)",
  m_twin  = "Twin(+15c+2m)",
  m_dono  = "Dono($2_scored_or_xmult_if_Highlighted)",
  m_glorp = "Glorpy(breaks_EOround)",
}

local function short_enh(card)
  if not card then return "" end
  local ability = card.ability or {}
  local enh = ability.enhancement
  if not enh then return "" end
  return ENH_SHORT[enh] or enh
end

local SEAL_DESC = {
  Red               = "Red(x2_trigger_when_scored)",
  Blue              = "Blue(hold_in_hand=free_planet_EOround)",
  Gold              = "Gold(+$3_when_scored)",
  Purple            = "Purple(discard=free_tarot)",
  shoomiminion_seal = "Shoominion(destroyed=spawns_2_copies)",
  osu_seal          = "Osu!(+5m_per_play_reset_on_discard)",
}
local function short_seal(card)
  if not card then return "" end
  local seal = card.seal
  if not seal then return "" end
  local key
  if type(seal) == "table" then
    local raw = seal.key and seal.key:match("seal_(%a+)") or seal.name or ""
    -- Normalise to Title Case ("red" → "Red", "Red Seal" → "Red Seal")
    key = raw:sub(1, 1):upper() .. raw:sub(2)
  else
    key = tostring(seal)
  end
  -- Strip trailing " Seal" if present ("Red Seal" → "Red")
  key = key:match("^(%a+)%s+[Ss]eal$") or key
  return SEAL_DESC[key] or key or ""
end

local function short_edition(card)
  if not card then return "" end
  local edition = card.edition
  if not edition then return "" end
  if type(edition) == "table" then
    if edition.polychrome then return "Poly(x1.5m)"
    elseif edition.holo     then return "Holo(+10m)"
    elseif edition.foil     then return "Foil(+50c)"
    elseif edition.filtered then return "Filtered(50/50:retrigger_or_debuff_EOround)"
    elseif edition.name     then return tostring(edition.name)
    end
    return ""
  end
  return tostring(edition)
end

local function header_section(state_name)
  return "STATE:" .. state_name
end

local function version_section()
  return "CTX_VER:2|FORMAT:COMPACT"
end

local function run_section()
  if not (G and G.GAME) then return nil end
  local game = G.GAME
  local deck_name = "-"
  local _bobj = game.back or game.selected_back
  if _bobj then
    local bkey = _bobj.name
    if bkey and G.P_CENTERS and G.P_CENTERS[bkey] then
      local pc = G.P_CENTERS[bkey]
      deck_name = (pc.loc_txt and pc.loc_txt.name) or pc.name or bkey
    else
      deck_name = bkey or "-"
    end
    if type(deck_name) == "string" and deck_name:find("_") and not deck_name:find(" ") then
      deck_name = deck_name:gsub("^b_", ""):gsub("_", " ")
      deck_name = deck_name:gsub("(%a)([%w]*)", function(a,b) return a:upper()..b end)
    end
  end
  local stake = game.stake or 1
  local seeded = game.seeded and "Y" or "N"
  local challenge = game.challenge and (game.challenge.name or game.challenge.id or "Y") or "N"
  local seed = (game.pseudorandom and game.pseudorandom.seed) or "-"
  return string.format("R|D:%s|K:%s|SD:%s|CH:%s|SE:%s",
    compact_text(deck_name, 24), tostring(stake), seeded, compact_text(challenge, 24), compact_text(seed, 16))
end

local function setup_decks_section()
  if not (G and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Back) then return nil end

  local selected_key = "-"
  local selected_name = "-"
  if G.GAME and G.GAME.selected_back then
    local sb = G.GAME.selected_back
    selected_key = tostring(sb.key or sb.name or "-")
    selected_name = tostring(sb.name or sb.key or "-")
  elseif G.GAME and G.GAME.back then
    local b = G.GAME.back
    selected_key = tostring(b.key or b.name or "-")
    selected_name = tostring(b.name or b.key or "-")
  end

  local decks = {}
  local keys = {}
  for key, deck in pairs(G.P_CENTER_POOLS.Back) do
    if type(key) == "string" and type(deck) == "table" and deck.unlocked ~= false then
      local name = deck.name
      if deck.loc_txt and deck.loc_txt.name then
        name = deck.loc_txt.name
      end
      name = tostring(name or key)
      decks[#decks + 1] = { key = key, name = name }
      keys[#keys + 1] = key
    end
  end

  table.sort(decks, function(a, b) return a.key < b.key end)
  table.sort(keys)

  local lines = {}
  lines[#lines + 1] = string.format("SD|K:%s|N:%s|U:%d",
    compact_text(selected_key, 18), compact_text(selected_name, 24), #decks)

  if #keys > 0 then
    lines[#lines + 1] = "SDK:" .. compact_text(table.concat(keys, ","), 220)
  else
    lines[#lines + 1] = "SDK:-"
  end

  lines[#lines + 1] = "SDC:i,k,n"
  local max_rows = math.min(#decks, 24)
  for i = 1, max_rows do
    local d = decks[i]
    lines[#lines + 1] = string.format("%d,%s,%s",
      i, compact_text(d.key, 18), compact_text(d.name, 28))
  end

  return table.concat(lines, "\n")
end

local function blind_line()
  if not G or not G.GAME or not G.GAME.blind then return nil end
  local blind = G.GAME.blind
  local target = (blind.chips or 0) * (blind.mult or 1)
  local current_score = G.GAME.chips or 0
  local remaining = math.max(0, target - current_score)
  local hands = G.GAME.current_round and G.GAME.current_round.hands_left or 0
  local discards = G.GAME.current_round and G.GAME.current_round.discards_left or 0
  local money = G.GAME.dollars or 0
  local econ = economy_projection()
  local name = blind.name or "Unknown"
  local ante = G.GAME.round_resets and G.GAME.round_resets.ante or "?"
  local win_ante = G.GAME.win_ante or 8
  local ante_str = tostring(ante) .. "/" .. tostring(win_ante)
  local no_interest = G.GAME.modifiers and G.GAME.modifiers.no_interest and "Y" or "N"
  local discard_cost = G.GAME.modifiers and G.GAME.modifiers.discard_cost
  local scaling = G.GAME.modifiers and G.GAME.modifiers.scaling
  local mod_parts = {}
  if no_interest == "Y" then mod_parts[#mod_parts+1] = "no_interest" end
  if discard_cost and discard_cost > 0 then mod_parts[#mod_parts+1] = "discard_costs_$"..tostring(discard_cost) end
  if scaling and scaling ~= 1 then mod_parts[#mod_parts+1] = "ante_scaling_x"..tostring(scaling) end
  local mod_str = #mod_parts > 0 and ("|MOD:"..table.concat(mod_parts, ",")) or ""
  local ern = tonumber(econ and econ.end_round_earnings) or 0
  local ern_str = ern > 0 and ("|ERN:" .. tostring(ern)) or ""
  return string.format("B|N:%s|A:%s|S:%d/%d|R:%d|H:%d|D:%d|$:%d|PY:B%d+H%d+D%d+I%d=T%d",
    compact_text(name, 28), ante_str, current_score, target, remaining, hands, discards, money,
    econ and econ.blind_reward or 0,
    econ and econ.hands_bonus or 0,
    econ and econ.discard_bonus or 0,
    econ and econ.interest or 0,
    econ and econ.projected_total or 0) .. ern_str .. mod_str
end

local function blind_debuff_line()
  if not (G and G.GAME and G.GAME.blind) then return nil end
  local blind = G.GAME.blind
  local debuff = (type(blind.debuff) == "table") and blind.debuff or {}

  local rules = {}
  if debuff.suit then rules[#rules + 1] = "suit=" .. tostring(debuff.suit) end
  if debuff.is_face == "face" then rules[#rules + 1] = "face=Y" end
  if debuff.h_size_ge then rules[#rules + 1] = "min_cards=" .. tostring(debuff.h_size_ge) end
  if debuff.h_size_le then rules[#rules + 1] = "max_cards=" .. tostring(debuff.h_size_le) end
  if debuff.value then rules[#rules + 1] = "value=" .. tostring(debuff.value) end
  if debuff.nominal then rules[#rules + 1] = "nominal=" .. tostring(debuff.nominal) end

  local bname = tostring(blind.name or "")
  if bname == "The Pillar" then rules[#rules + 1] = "played_this_ante=Y" end
  if bname == "The Eye" then rules[#rules + 1] = "repeat_hand_type=N" end
  if bname == "The Mouth" then rules[#rules + 1] = "single_hand_type=Y" end

  local debuffed_cards = 0
  if G.hand and G.hand.cards then
    for _, card in ipairs(G.hand.cards) do
      if card and card.debuff then
        debuffed_cards = debuffed_cards + 1
      end
    end
  end

  local txt = ""
  if type(blind.get_loc_debuff_text) == "function" then
    local ok, v = pcall(blind.get_loc_debuff_text, blind)
    if ok and type(v) == "string" then txt = v end
  end
  if txt == "" and type(blind.loc_debuff_text) == "string" then
    txt = blind.loc_debuff_text
  end
  if txt == "" and blind.loc_txt then
    txt = safe_description(blind.loc_txt, nil, 92) or ""
  end

  if #rules == 0 and txt == "" and debuffed_cards == 0 then
    return nil
  end

  return string.format("BD|R:%s|DB:%d|TXT:%s",
    compact_text((#rules > 0 and table.concat(rules, "/") or "-"), 88),
    debuffed_cards,
    compact_text((txt ~= "" and txt or "-"), 120)
  )
end

local function hand_section()
  if not G or not G.hand or not G.hand.cards or #G.hand.cards == 0 then
    return nil
  end
  local parts = {}
  for i, card in ipairs(G.hand.cards) do
    local base = card.base or {}
    local v = short_value(base.value)
    local s = short_suit(base.suit)
    local mods = ""
    local enh = short_enh(card)
    local seal = short_seal(card)
    local ed = short_edition(card)
    if enh ~= "" then mods = mods .. "+" .. enh end
    if seal ~= "" then mods = mods .. "+" .. seal end
    if ed ~= "" then mods = mods .. "+" .. ed end
    if card.debuff then mods = mods .. "+DB" end
    parts[#parts + 1] = i .. "=" .. tostring(v) .. tostring(s) .. mods
  end
  return "H:" .. table.concat(parts, " ")
end

local function deck_cards_section()
  if not G or not G.deck or not G.deck.cards or #G.deck.cards == 0 then return nil end
  local n = #G.deck.cards
  local parts = {}
  for _, card in ipairs(G.deck.cards) do
    local base = card.base or {}
    local v = short_value(base.value)
    local s = short_suit(base.suit)
    local mods = ""
    local enh = short_enh(card)
    local seal = short_seal(card)
    local ed = short_edition(card)
    if enh ~= "" then mods = mods .. "+" .. enh end
    if seal ~= "" then mods = mods .. "+" .. seal end
    if ed ~= "" then mods = mods .. "+" .. ed end
    parts[#parts + 1] = tostring(v) .. tostring(s) .. mods
  end
  return "DC:" .. tostring(n) .. "|" .. table.concat(parts, ",")
end

local function jokers_section(include_full_desc)
  if not G or not G.jokers or not G.jokers.cards or #G.jokers.cards == 0 then
    return nil
  end

  local lines = { include_full_desc and "J:i,n,f,t,d" or "J:i,n,f,t" }
  for i, card in ipairs(G.jokers.cards) do
    local name = compact_text(safe_name(card) or "Unknown", 40)
    local effect_str = card_effect_summary(card)
    local row = {
      tostring(i),
      compact_text(name, 40),
      compact_text(effect_str, 80),
      joker_tags(card),
    }
    if include_full_desc then
      row[#row + 1] = compact_text(card_description_full(card, 320), 320)
    end
    lines[#lines + 1] = table.concat(row, ",")
  end

  return table.concat(lines, "\n")
end

local function legality_section(state_name, action_set)
  if not G then return nil end

  if state_name == "SELECTING_HAND" then
    local round = G.GAME and G.GAME.current_round or {}
    local hands_left = round and round.hands_left or 0
    local discards_left = round and round.discards_left or 0
    local highlighted = (G.hand and G.hand.highlighted and #G.hand.highlighted) or 0
    local can_play = hands_left > 0 and "Y" or "N"
    local can_discard = discards_left > 0 and "Y" or "N"
    return string.format("LA|CP:%s|CD:%s|H:%d", can_play, can_discard, highlighted)
  end

  if state_name == "SHOP" then
    local money = G.GAME and G.GAME.dollars or 0
    local reroll = G.GAME and G.GAME.current_round and G.GAME.current_round.reroll_cost or 5
    local free_rerolls = G.GAME and G.GAME.current_round and G.GAME.current_round.free_rerolls or 0
    local can_reroll = (free_rerolls > 0 or (type(reroll) == "number" and reroll > 0 and money >= reroll)) and "Y" or "N"
    local can_sell = (G.jokers and G.jokers.cards and #G.jokers.cards > 0) and "Y" or "N"
    local can_use = (G.consumeables and G.consumeables.cards and #G.consumeables.cards > 0) and "Y" or "N"

    local can_buy_any = "N"
    local cheapest = nil
    local areas = { G.shop_jokers, G.shop_vouchers, G.shop_booster }
    for _, area in ipairs(areas) do
      if area and area.cards then
        for _, card in ipairs(area.cards) do
          local cost = card and card.cost or 0
          if type(cost) == "number" and cost >= 0 then
            if not cheapest or cost < cheapest then
              cheapest = cost
            end
          end
          if type(cost) == "number" and cost <= money then
            can_buy_any = "Y"
          end
        end
      end
    end

    local reroll_safe = "N"
    if free_rerolls > 0 and type(cheapest) == "number" then
      reroll_safe = "Y"
    elseif type(cheapest) == "number" and type(reroll) == "number" and reroll > 0 then
      reroll_safe = ((money - reroll) >= cheapest) and "Y" or "N"
    end

    return string.format("LA|CB:%s|CR:%s|CRS:%s|CS:%s|CU:%s", can_buy_any, can_reroll, reroll_safe, can_sell, can_use)
  end

  if state_name == "BLIND_SELECT" then
    local can_skip = "N"
    local can_reroll_boss = "N"
    if G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_choices then
      local choices = G.GAME.round_resets.blind_choices
      local ante = tonumber(G.GAME.round_resets.ante or 1) or 1
      if (ante == 1 and choices.Small) or (ante > 1 and choices.Big) then
        can_skip = "Y"
      end
    end
    if G.GAME then
      local bankroll = (G.GAME.dollars or 0) - (G.GAME.bankrupt_at or 0)
      local used = G.GAME.used_vouchers or {}
      local has_retcon = used["v_retcon"]
      local has_directors_cut = used["v_directors_cut"]
      local boss_not_rerolled = not (G.GAME.round_resets and G.GAME.round_resets.boss_rerolled)
      local enabled = has_retcon or (has_directors_cut and boss_not_rerolled)
      if enabled and bankroll >= 10 then can_reroll_boss = "Y" end
    end
    return string.format("LA|SK:%s|RB:%s", can_skip, can_reroll_boss)
  end

  if state_name == "RUN_SETUP" or state_name == "MENU" then
    local has_deck_switch = has_action(action_set, "change_selected_back") and "Y" or "N"
    local can_start = has_action(action_set, "start_run") and "Y" or "N"
    return string.format("LA|SR:%s|DS:%s", can_start, has_deck_switch)
  end

  return nil
end

local function hand_limits_section()
  if not (G and G.hand and G.hand.config and G.GAME and G.GAME.current_round) then
    return nil
  end
  local max_highlight = G.hand.config.highlighted_limit or 5
  local hand_limit = G.hand.config.card_limit or 8
  local highlighted = G.hand.highlighted and #G.hand.highlighted or 0
  local hands_left = G.GAME.current_round.hands_left or 0
  local discards_left = G.GAME.current_round.discards_left or 0
  local can_play = hands_left > 0 and "Y" or "N"
  local can_discard = discards_left > 0 and "Y" or "N"
  return string.format("HL|MH:%d|HG:%d|L:%d|CP:%s|CD:%s",
    max_highlight, highlighted, hand_limit, can_play, can_discard)
end

local function highlighted_section()
  if not G or not G.hand or not G.hand.highlighted then
    return nil
  end
  if #G.hand.highlighted == 0 then
    return "HG:-"
  end

  local idx = {}
  for _, card in ipairs(G.hand.highlighted) do
    local found = nil
    if G.hand.cards then
      for i, hand_card in ipairs(G.hand.cards) do
        if hand_card == card then
          found = i
          break
        end
      end
    end
    if found then
      idx[#idx + 1] = tostring(found)
    end
  end

  if #idx == 0 then
    return "HG:-"
  end
  return "HG:" .. table.concat(idx, ",")
end

local function levels_section()
  if not G or not G.GAME or not G.GAME.hands then return nil end

  local order = {
    ["High Card"] = 1,
    ["Pair"] = 2,
    ["Two Pair"] = 3,
    ["Three of a Kind"] = 4,
    ["Straight"] = 5,
    ["Flush"] = 6,
    ["Full House"] = 7,
    ["Four of a Kind"] = 8,
    ["Straight Flush"] = 9,
    ["Five of a Kind"] = 10,
    ["Flush House"] = 11,
    ["Flush Five"] = 12,
    ["mix"] = 13, ["mixhouse"] = 14, ["straightmix"] = 15, ["mixed5"] = 16,
  }

  local rows = {}
  for hand_name, hand_data in pairs(G.GAME.hands) do
    if hand_data.visible then
      rows[#rows + 1] = {
        name = hand_name,
        level = hand_data.level or 1,
        chips = hand_data.chips or 0,
        mult = hand_data.mult or 0,
      }
    end
  end

  if #rows == 0 then return nil end

  table.sort(rows, function(a, b)
    local ao = order[a.name] or 999
    local bo = order[b.name] or 999
    if ao ~= bo then return ao < bo end
    return tostring(a.name) < tostring(b.name)
  end)

  local lines = {}
  lines[#lines + 1] = "L:n,lv,c,m"
  for _, row in ipairs(rows) do
    lines[#lines + 1] = string.format("%s,%d,%d,%d",
      compact_text(row.name, 24), row.level, row.chips, row.mult)
  end
  return table.concat(lines, "\n")
end

local function idx_str(indices)
  local parts = {}
  for _, idx in ipairs(indices) do parts[#parts + 1] = tostring(idx) end
  return "[" .. table.concat(parts, ",") .. "]"
end

local function tally_hand(cards)
  local value_counts, suit_counts = {}, {}
  local value_indices, suit_indices = {}, {}
  local wild_count, wild_indices = 0, {}
  for i, card in ipairs(cards) do
    if card.base then
      local v = card.base.value or "?"
      local s = card.base.suit or "?"
      local is_wild = card.ability and card.ability.enhancement == "m_wild"
      value_counts[v] = (value_counts[v] or 0) + 1
      value_indices[v] = value_indices[v] or {}
      value_indices[v][#value_indices[v] + 1] = i
      if is_wild then
        wild_count = wild_count + 1
        wild_indices[#wild_indices + 1] = i
      else
        suit_counts[s] = (suit_counts[s] or 0) + 1
        suit_indices[s] = suit_indices[s] or {}
        suit_indices[s][#suit_indices[s] + 1] = i
      end
    end
  end
  return value_counts, suit_counts, value_indices, suit_indices, wild_count, wild_indices
end

local function detect_value_combos(value_counts, value_indices, combos, combo_scoring)
  local pair_count = 0
  local has_trips = false
  local trips_value = nil
  local pair_values = {}

  local value_keys = {}
  for v in pairs(value_counts) do value_keys[#value_keys + 1] = v end
  table.sort(value_keys, function(a, b)
    local ac = value_counts[a] or 0
    local bc = value_counts[b] or 0
    if ac ~= bc then return ac > bc end
    local ar = VALUE_RANK[a] or -1
    local br = VALUE_RANK[b] or -1
    if ar ~= br then return ar > br end
    return tostring(a) < tostring(b)
  end)

  for _, v in ipairs(value_keys) do
    local count = value_counts[v] or 0
    local ids = value_indices[v] or {}
    if count >= 4 then
      combos[#combos + 1] = "Four " .. v .. "s " .. idx_str(ids)
      combo_scoring[#combo_scoring + 1] = {type = "Four of a Kind", indices = ids}
    elseif count >= 3 then
      combos[#combos + 1] = "Trips " .. v .. "s " .. idx_str(ids)
      combo_scoring[#combo_scoring + 1] = {type = "Three of a Kind", indices = ids}
      has_trips = true
      trips_value = v
    elseif count >= 2 then
      combos[#combos + 1] = "Pair " .. v .. "s " .. idx_str(ids)
      combo_scoring[#combo_scoring + 1] = {type = "Pair", indices = ids}
      pair_count = pair_count + 1
      pair_values[#pair_values + 1] = v
    end
  end

  if has_trips and pair_count >= 1 then
    local fh_idx = {}
    for _, idx in ipairs(value_indices[trips_value] or {}) do fh_idx[#fh_idx + 1] = idx end
    for _, idx in ipairs(value_indices[pair_values[1]] or {}) do fh_idx[#fh_idx + 1] = idx end
    combos[#combos + 1] = "Full House! " .. idx_str(fh_idx)
    combo_scoring[#combo_scoring + 1] = {type = "Full House", indices = fh_idx}
  elseif pair_count >= 2 then
    local tp_idx = {}
    for pi = 1, math.min(2, #pair_values) do
      for _, idx in ipairs(value_indices[pair_values[pi]] or {}) do tp_idx[#tp_idx + 1] = idx end
    end
    combos[#combos + 1] = "Two Pair " .. idx_str(tp_idx)
    combo_scoring[#combo_scoring + 1] = {type = "Two Pair", indices = tp_idx}
  end
end

local function detect_flush_combos(suit_counts, suit_indices, combos, combo_scoring, wild_count, wild_indices)
  wild_count = wild_count or 0
  wild_indices = wild_indices or {}
  local suit_keys = {}
  for s in pairs(suit_counts) do suit_keys[#suit_keys + 1] = s end
  table.sort(suit_keys, function(a, b)
    local ao = SUIT_ORDER[a] or 99
    local bo = SUIT_ORDER[b] or 99
    if ao ~= bo then return ao < bo end
    return tostring(a) < tostring(b)
  end)
  for _, s in ipairs(suit_keys) do
    local count = suit_counts[s] or 0
    local ids = suit_indices[s] or {}
    local effective = count + wild_count
    if effective >= 5 then
      local all_ids = {}
      for _, idx in ipairs(ids) do all_ids[#all_ids + 1] = idx end
      for _, idx in ipairs(wild_indices) do all_ids[#all_ids + 1] = idx end
      combos[#combos + 1] = "Flush " .. s .. " " .. idx_str(all_ids)
      combo_scoring[#combo_scoring + 1] = {type = "Flush", indices = all_ids}
    elseif effective >= 4 then
      local all_ids = {}
      for _, idx in ipairs(ids) do all_ids[#all_ids + 1] = idx end
      for _, idx in ipairs(wild_indices) do all_ids[#all_ids + 1] = idx end
      combos[#combos + 1] = "Near Flush " .. s .. "(" .. effective .. ") " .. idx_str(all_ids)
    end
  end
end

local function detect_straight_combos(cards, combos, combo_scoring)
  local rank_to_indices = {}
  for i, card in ipairs(cards) do
    if card.base and card.base.value then
      local r = VALUE_RANK[card.base.value]
      if r then
        rank_to_indices[r] = rank_to_indices[r] or {}
        rank_to_indices[r][#rank_to_indices[r] + 1] = i
      end
    end
  end
  if rank_to_indices[14] then rank_to_indices[1] = rank_to_indices[1] or rank_to_indices[14] end
  local best_run = 0
  local best_run_start = 0
  local run = 0
  local run_start = 0
  for r = 1, 14 do
    if rank_to_indices[r] then
      if run == 0 then run_start = r end
      run = run + 1
    else
      if run > best_run then best_run = run; best_run_start = run_start end
      run = 0
    end
  end
  if run > best_run then best_run = run; best_run_start = run_start end
  if best_run >= 5 then
    local st_idx = {}
    for r = best_run_start, best_run_start + 4 do
      if rank_to_indices[r] then st_idx[#st_idx + 1] = rank_to_indices[r][1] end
    end
    combos[#combos + 1] = "Straight! " .. idx_str(st_idx)
    combo_scoring[#combo_scoring + 1] = {type = "Straight", indices = st_idx}
  elseif best_run == 4 then
    local ns_idx = {}
    for r = best_run_start, best_run_start + 3 do
      if rank_to_indices[r] then ns_idx[#ns_idx + 1] = rank_to_indices[r][1] end
    end
    combos[#combos + 1] = "Near Straight(4) " .. idx_str(ns_idx)
  end
end

-- Numeric rank for hand types (used by conditional joker thresholds)
local HAND_RANK_NUM = {
  ["High Card"]=1, ["Pair"]=2, ["Two Pair"]=3,
  ["Three of a Kind"]=4, ["Straight"]=5, ["Flush"]=6,
  ["Full House"]=7, ["Four of a Kind"]=8, ["Straight Flush"]=9,
  ["Five of a Kind"]=10, ["Flush House"]=11, ["Flush Five"]=12,
}

local function joker_trigger_labels(hand_type_name, card_indices, cards)
  if not (G and G.jokers and G.jokers.cards) then return nil end
  local hr = HAND_RANK_NUM[hand_type_name] or 1
  local labels = {}
  for _, jc in ipairs(G.jokers.cards) do
    local nm = (jc.ability and jc.ability.name) or ""
    local lbl = nil
    if nm == "Jolly Joker"   and hr >= 2 then lbl = "+8m" end
    if nm == "Zany Joker"    and hr >= 4 then lbl = "+12m" end
    if nm == "Mad Joker"     and hr >= 3 then lbl = "+20m" end
    if nm == "Crazy Joker"   and hr >= 5 then lbl = "+15m" end
    if nm == "Droll Joker"   and hr >= 6 then lbl = "+10m" end
    if nm == "Sly Joker"     and hr >= 2 then lbl = "+50c" end
    if nm == "Wily Joker"    and hr >= 4 then lbl = "+100c" end
    if nm == "Clever Joker"  and hr >= 3 then lbl = "+80c" end
    if nm == "Devious Joker" and hr >= 5 then lbl = "+100c" end
    if nm == "Crafty Joker"  and hr >= 6 then lbl = "+80c" end
    if nm == "Half Joker" and card_indices and #card_indices <= 3 then lbl = "+20m" end
    if nm == "Abstract Joker" then lbl = "+" .. (3 * #G.jokers.cards) .. "m" end
    local suit_map = {
      ["Greedy Joker"]="Diamonds", ["Lusty Joker"]="Hearts",
      ["Wrathful Joker"]="Spades", ["Gluttonous Joker"]="Clubs",
    }
    local suit_target = suit_map[nm]
    if suit_target and card_indices then
      local cnt = 0
      for _, ci in ipairs(card_indices) do
        local c = cards and cards[ci]
        if c and c.base and c.base.suit == suit_target then cnt = cnt + 1 end
      end
      if cnt > 0 then lbl = "+" .. (cnt * 3) .. "m(" .. cnt .. suit_target:sub(1,3) .. ")" end
    end
    if nm == "Photograph" and card_indices then
      local pareidolia_l = G.GAME and G.GAME.used_vouchers and G.GAME.used_vouchers["v_pareidolia"] and true or false
      for _, ci in ipairs(card_indices) do
        local c = cards and cards[ci]
        local id = c and c.base and tonumber(c.base.id or 0) or 0
        if pareidolia_l or id >= 11 then lbl = "x2m(face)"; break end
      end
    end
    if nm == "Scholar" and card_indices then
      for _, ci in ipairs(card_indices) do
        local c = cards and cards[ci]
        local id = c and c.base and tonumber(c.base.id or 0) or 0
        if id == 14 then lbl = "+20c+4m(A)"; break end
      end
    end
    if nm == "MILC" and hr >= 2 then lbl = "x2m(pair+)" end
    if nm == "Drive" and card_indices and #card_indices == 4 then lbl = "+35m" end
    if nm == "Miniko Cute" and card_indices and #card_indices <= 3 then lbl = "+15m" end
    if nm == "Anny" and card_indices and #card_indices >= 5 then lbl = "+10m(gain)" end
    if nm == "Cave Stream" and card_indices and #card_indices >= 6 then lbl = "+30c" end
    if nm == "Kyoto" and card_indices then
      for _, ci in ipairs(card_indices) do
        local c = cards and cards[ci]
        if c and c.base and c.base.suit == "Spades" then lbl = "+50c+15m(Spade)"; break end
      end
    end
    if nm == "Teru" and card_indices then
      local cnt = 0
      for _, ci in ipairs(card_indices) do
        local c = cards and cards[ci]
        if c and c.base and c.base.suit == "Diamonds" then cnt = cnt + 1 end
      end
      if cnt > 0 then lbl = "+" .. (cnt * 20) .. "c(" .. cnt .. "Dia)" end
    end
    if nm == "Collab" and card_indices then
      local suits = {}
      for _, ci in ipairs(card_indices) do
        local c = cards and cards[ci]
        if c and c.base and c.base.suit then suits[c.base.suit] = true end
      end
      local unique = 0
      for _ in pairs(suits) do unique = unique + 1 end
      if unique > 0 then lbl = "+" .. (unique * 15) .. "m(" .. unique .. "suits)" end
    end
    if nm == "Hype" and card_indices then
      for _, ci in ipairs(card_indices) do
        local c = cards and cards[ci]
        local id = c and c.base and tonumber(c.base.id or 0) or 0
        if id == 14 then lbl = "+20m(Ace)"; break end
      end
    end
    if nm == "Queen PB" and card_indices then
      for _, ci in ipairs(card_indices) do
        local c = cards and cards[ci]
        local id = c and c.base and tonumber(c.base.id or 0) or 0
        if id == 12 then lbl = "x1.5m/Queen"; break end
      end
    end
    if nm == "Hiyori" and card_indices then
      for _, ci in ipairs(card_indices) do
        local c = cards and cards[ci]
        local id = c and c.base and tonumber(c.base.id or 0) or 0
        if id == 7 then lbl = "retrig(7s)"; break end
      end
    end
    if nm == "Four Toes" and card_indices then
      for _, ci in ipairs(card_indices) do
        local c = cards and cards[ci]
        local id = c and c.base and tonumber(c.base.id or 0) or 0
        if id == 4 then lbl = "retrig(4s)"; break end
      end
    end
    if nm == "heartheartheart" and hand_type_name == "Three of a Kind" and card_indices then
      local all_hearts = true
      for _, ci in ipairs(card_indices) do
        local c = cards and cards[ci]
        if not (c and c.base and c.base.suit == "Hearts") then all_hearts = false; break end
      end
      if all_hearts then lbl = "x1.45m(3H)" end
    end
    if nm == "Walkie Talkie" and card_indices then
      local cnt = 0
      for _, ci in ipairs(card_indices) do
        local c = cards and cards[ci]
        local id = c and c.base and tonumber(c.base.id or 0) or 0
        if id == 10 or id == 4 then cnt = cnt + 1 end
      end
      if cnt > 0 then lbl = "+" .. (cnt*10) .. "c+" .. (cnt*4) .. "m(" .. cnt .. "x10/4)" end
    end
    if nm == "Smiley Face" and card_indices then
      local pareidolia_l = G.GAME and G.GAME.used_vouchers and G.GAME.used_vouchers["v_pareidolia"] and true or false
      local cnt = 0
      for _, ci in ipairs(card_indices) do
        local c = cards and cards[ci]
        local id = c and c.base and tonumber(c.base.id or 0) or 0
        if pareidolia_l or (id >= 11 and id <= 13) then cnt = cnt + 1 end
      end
      if cnt > 0 then lbl = "+" .. (cnt*5) .. "m(" .. cnt .. "face)" end
    end
    if nm == "The Idol" and card_indices then
      local ts = jc.ability and jc.ability.extra and jc.ability.extra.suit
      local tv = jc.ability and jc.ability.extra and jc.ability.extra.value
      if ts and tv then
        for _, ci in ipairs(card_indices) do
          local c = cards and cards[ci]
          if c and c.base and c.base.suit == ts and c.base.value == tv then
            lbl = "x2m(" .. tostring(tv) .. short_suit(ts) .. ")"; break
          end
        end
      end
    end
    if nm == "Seeing Double" and card_indices then
      local has_club, has_other = false, false
      for _, ci in ipairs(card_indices) do
        local c = cards and cards[ci]
        if c and c.base then
          if c.base.suit == "Clubs" then has_club = true else has_other = true end
        end
      end
      if has_club and has_other then lbl = "x2m(Club+other)" end
    end
    if nm == "Hanging Chad" and card_indices and #card_indices > 0 then
      lbl = "retrig_first(x3)"
    end
    if nm == "Acrobat" then
      local hl = G.GAME and G.GAME.current_round and G.GAME.current_round.hands_left or 0
      if hl == 1 then lbl = "x3m(lasthand)" end
    end
    if nm == "Dusk" then
      local hl = G.GAME and G.GAME.current_round and G.GAME.current_round.hands_left or 0
      if hl == 1 then lbl = "retrig_last(lasthand)" end
    end
    if nm == "Driver's License" and G.playing_cards then
      local n = 0
      for _, pc in ipairs(G.playing_cards) do
        if pc.ability and pc.ability.enhancement and pc.ability.enhancement ~= "" then n = n + 1 end
      end
      if n >= 16 then lbl = "x3m(" .. n .. "enh)" end
    end
    if nm == "Cavendish" and G.playing_cards then
      for _, pc in ipairs(G.playing_cards) do
        if pc.base and pc.base.id == 6 and pc.base.suit == "Clubs" then lbl = "x3(6Cdeck)"; break end
      end
    end
    if nm == "Card Sharp" then
      local most_played, most_count = nil, 0
      if G.GAME and G.GAME.hands then
        for hname, hd in pairs(G.GAME.hands) do
          if (hd.played or 0) > most_count then most_count = hd.played; most_played = hname end
        end
      end
      if most_played and most_played == hand_type_name and most_count > 1 then lbl = "x3(repeat)" end
    end
    if nm == "Baseball Card" and G.jokers and G.jokers.cards then
      local rare_cnt = 0
      for _, j2 in ipairs(G.jokers.cards) do
        local rarity = j2.config and j2.config.center and j2.config.center.rarity
        if rarity == 3 then rare_cnt = rare_cnt + 1 end
      end
      if rare_cnt > 0 then lbl = "x" .. string.format("%.2g", 1.5^rare_cnt) .. "m(" .. rare_cnt .. "rare)" end
    end
    if nm == "Blueprint" or nm == "Brainstorm" then
      local j_idx = nil
      for ji, jcheck in ipairs(G.jokers.cards) do
        if jcheck == jc then j_idx = ji; break end
      end
      local target_jc = nil
      if nm == "Blueprint" and j_idx then
        target_jc = G.jokers.cards[j_idx + 1]
      elseif nm == "Brainstorm" then
        target_jc = G.jokers.cards[1]
        if target_jc == jc then target_jc = nil end
      end
      if target_jc then
        local tnm = (target_jc.ability and target_jc.ability.name) or "?"
        lbl = "copies_" .. compact_text(tnm, 16)
      end
    end
    if lbl then
      labels[#labels + 1] = compact_text(nm, 20) .. "=" .. lbl
    end
  end
  if #labels == 0 then return nil end
  return "JTRIG:" .. table.concat(labels, "|")
end

local function conditional_joker_bonus(hand_type_name, card_indices, cards)
  local bc, bm, bx = 0, 0, 1
  local hr = HAND_RANK_NUM[hand_type_name] or 1
  if not (G and G.jokers and G.jokers.cards) then return bc, bm, bx end

  local pareidolia = G.GAME and G.GAME.used_vouchers and G.GAME.used_vouchers["v_pareidolia"] and true or false
  for _, jc in ipairs(G.jokers.cards) do
    local nm = jc.ability and jc.ability.name or ""
    local ex = jc.ability.extra or {}

    -- Threshold jokers (mult)
    if nm == "Jolly Joker"  and hr >= 2  then bm = bm + 8  end
    if nm == "Zany Joker"   and hr >= 4  then bm = bm + 12 end
    if nm == "Mad Joker"    and hr >= 3  then bm = bm + 20 end
    if nm == "Crazy Joker"  and hr >= 5  then bm = bm + 15 end
    if nm == "Droll Joker"  and hr >= 6  then bm = bm + 10 end
    -- Threshold jokers (chips)
    if nm == "Sly Joker"     and hr >= 2 then bc = bc + 50  end
    if nm == "Wily Joker"    and hr >= 4 then bc = bc + 100 end
    if nm == "Clever Joker"  and hr >= 3 then bc = bc + 80  end
    if nm == "Devious Joker" and hr >= 5 then bc = bc + 100 end
    if nm == "Crafty Joker"  and hr >= 6 then bc = bc + 80  end
    -- Half Joker: +20m if ≤3 cards played
    if nm == "Half Joker" and card_indices and #card_indices <= 3 then bm = bm + 20 end
    -- Abstract Joker: +3m per joker owned
    if nm == "Abstract Joker" then bm = bm + 3 * #G.jokers.cards end
    -- Photograph: ×2m if highest-ranked played card is a face card
    if nm == "Photograph" then
      local has_face = false
      if card_indices then
        for _, ci in ipairs(card_indices) do
          local c = cards[ci]
          local id = c and c.base and c.base.id or 0
          if pareidolia or id >= 11 then has_face = true end
        end
      end
      if has_face then bx = bx * 2 end
    end
    -- Suit-based +mult jokers
    local suit_map = {
      ["Greedy Joker"]="Diamonds", ["Lusty Joker"]="Hearts",
      ["Wrathful Joker"]="Spades", ["Gluttonous Joker"]="Clubs",
    }
    local suit_target = suit_map[nm]
    if suit_target and card_indices then
      for _, ci in ipairs(card_indices) do
        local c = cards[ci]
        if c and c.base and c.base.suit == suit_target then bm = bm + 3 end
      end
    end
    -- Per-card rank jokers
    if nm == "Scholar" and card_indices then
      for _, ci in ipairs(card_indices) do
        local c = cards[ci]
        if c and c.base and c.base.value == "Ace" then bc=bc+20; bm=bm+4 end
      end
    end
    if nm == "Scary Face" and card_indices then
      for _, ci in ipairs(card_indices) do
        local c = cards[ci]
        local id = c and c.base and c.base.id or 0
        if pareidolia or id >= 11 then bc = bc + 30 end
      end
    end
    if nm == "Fibonacci" and card_indices then
      local fib = {[1]=true,[2]=true,[3]=true,[5]=true,[8]=true,[14]=true}
      for _, ci in ipairs(card_indices) do
        local c = cards[ci]
        local id = c and c.base and c.base.id or 0
        if fib[id] then bm = bm + 8 end
      end
    end
    -- Baron: ×1.5m per King held in hand (not played)
    if nm == "Baron" then
      for i, c in ipairs(cards) do
        local is_played = false
        if card_indices then for _, ci in ipairs(card_indices) do if ci == i then is_played=true end end end
        local id = c and c.base and c.base.id or 0
        if not is_played and id == 13 then bx = bx * 1.5 end
      end
    end
    -- Retrigger: Hack (2,3,4,5) and Sock and Buskin (face cards) double chip contribution
    if (nm == "Hack" or nm == "Sock and Buskin") and card_indices then
      for _, ci in ipairs(card_indices) do
        local c = cards[ci]
        local id = c and c.base and c.base.id or 0
        local triggers = (nm == "Hack" and (id >= 2 and id <= 5)) or
                         (nm == "Sock and Buskin" and (pareidolia or id >= 11))
        if triggers and c.base and c.base.value then
          local r = VALUE_RANK[c.base.value]
          if r then bc = bc + (r == 14 and 11 or math.min(r, 10)) end
        end
      end
    end

    -- === Base game: additional conditional jokers ===
    -- Per-suit scored card
    if nm == "Bloodstone" and card_indices then  -- ×1.5 per Heart (p=1/2 → EV ×1.25)
      for _, ci in ipairs(card_indices) do
        local c = cards[ci]
        if c and c.base and c.base.suit == "Hearts" then bx = bx * 1.25 end
      end
    end
    if nm == "Arrowhead" and card_indices then  -- +50c per Spade scored
      for _, ci in ipairs(card_indices) do
        local c = cards[ci]
        if c and c.base and c.base.suit == "Spades" then bc = bc + 50 end
      end
    end
    if nm == "Onyx Agate" and card_indices then  -- +7m per Club scored
      for _, ci in ipairs(card_indices) do
        local c = cards[ci]
        if c and c.base and c.base.suit == "Clubs" then bm = bm + 7 end
      end
    end
    -- Ancient Joker: ×1.5 per card matching current suit (stored in ability.suit)
    if nm == "Ancient Joker" and card_indices then
      local suit = jc.ability and jc.ability.suit
      for _, ci in ipairs(card_indices) do
        local c = cards[ci]
        if c and c.base then
          if suit and c.base.suit == suit then
            bx = bx * 1.5
          elseif not suit then
            bx = bx * 1.5^0.25  -- EV: 1/4 chance each card matches unknown suit
          end
        end
      end
    end
    -- Flower Pot: ×3 if one card of each suit in played hand
    if nm == "Flower Pot" and card_indices then
      local suits = {}
      for _, ci in ipairs(card_indices) do
        local c = cards[ci]
        if c and c.base and c.base.suit then suits[c.base.suit] = true end
      end
      if suits["Hearts"] and suits["Diamonds"] and suits["Spades"] and suits["Clubs"] then
        bx = bx * 3
      end
    end
    -- Triboulet: ×2 per King or Queen scored
    if nm == "Triboulet" and card_indices then
      for _, ci in ipairs(card_indices) do
        local c = cards[ci]
        local id = c and c.base and c.base.id or 0
        if id == 13 or id == 12 then bx = bx * 2 end
      end
    end
    -- Even Steven: +4m per even-ranked card scored (2,4,6,8,10)
    if nm == "Even Steven" and card_indices then
      for _, ci in ipairs(card_indices) do
        local c = cards[ci]
        local id = c and c.base and c.base.id or 0
        if id >= 2 and id <= 10 and id % 2 == 0 then bm = bm + 4 end
      end
    end
    -- Odd Todd: +31c per odd-ranked card scored (A,3,5,7,9)
    if nm == "Odd Todd" and card_indices then
      for _, ci in ipairs(card_indices) do
        local c = cards[ci]
        local id = c and c.base and c.base.id or 0
        if id == 14 or (id >= 3 and id <= 9 and id % 2 == 1) then bc = bc + 31 end
      end
    end
    -- Wee Joker: +8c per 2 scored
    if nm == "Wee Joker" and card_indices then
      for _, ci in ipairs(card_indices) do
        local c = cards[ci]
        if c and c.base and c.base.id == 2 then bc = bc + 8 end
      end
    end
    -- Square Joker: +4c if exactly 4 cards played
    if nm == "Square Joker" and card_indices and #card_indices == 4 then bc = bc + 4 end
    -- Held-card jokers
    -- Shoot the Moon: +13m per Queen held in hand (not played)
    if nm == "Shoot the Moon" then
      for i, c in ipairs(cards) do
        local is_played = false
        if card_indices then for _, ci in ipairs(card_indices) do if ci == i then is_played = true end end end
        if not is_played and c and c.base and c.base.id == 12 then bm = bm + 13 end
      end
    end
    -- Blackboard: ×3 if all held cards (not played) are Spades or Clubs
    if nm == "Blackboard" then
      local all_black, held_count = true, 0
      for i, c in ipairs(cards) do
        local is_played = false
        if card_indices then for _, ci in ipairs(card_indices) do if ci == i then is_played = true end end end
        if not is_played then
          held_count = held_count + 1
          local suit = c and c.base and c.base.suit
          if suit ~= "Spades" and suit ~= "Clubs" then all_black = false end
        end
      end
      if all_black and held_count > 0 then bx = bx * 3 end
    end
    -- Raised Fist: +mult = 2× rank chips of lowest-ranked held card
    if nm == "Raised Fist" then
      local min_id, min_chips = 99, 0
      for i, c in ipairs(cards) do
        local is_played = false
        if card_indices then for _, ci in ipairs(card_indices) do if ci == i then is_played = true end end end
        if not is_played and c and c.base and c.base.value then
          local id = c.base.id or 0
          local r  = VALUE_RANK[c.base.value]
          if r and id < min_id then min_id = id; min_chips = (r == 14 and 11 or math.min(r, 10)) end
        end
      end
      if min_chips > 0 then bm = bm + min_chips * 2 end
    end
    -- Hand-type xmult (The Duo / Trio / Family / Order / Tribe)
    if nm == "The Duo"    and (hand_type_name == "Pair" or hand_type_name == "Two Pair" or hand_type_name == "Full House") then bx = bx * 2 end
    if nm == "The Trio"   and (hand_type_name == "Three of a Kind" or hand_type_name == "Full House")                       then bx = bx * 3 end
    if nm == "The Family" and  hand_type_name == "Four of a Kind"                                                           then bx = bx * 4 end
    if nm == "The Order"  and (hand_type_name == "Straight" or hand_type_name == "Straight Flush")                         then bx = bx * 3 end
    if nm == "The Tribe"  and (hand_type_name == "Flush" or hand_type_name == "Straight Flush" or hand_type_name == "Flush House" or hand_type_name == "Flush Five") then bx = bx * 2 end
    -- Game-state jokers
    if nm == "Banner" then  -- +30c per discard remaining
      local d = G.GAME and G.GAME.current_round and G.GAME.current_round.discards_left or 0
      bc = bc + 30 * d
    end
    if nm == "Mystic Summit" then  -- +15m when 0 discards left
      local d = G.GAME and G.GAME.current_round and G.GAME.current_round.discards_left or 0
      if d == 0 then bm = bm + 15 end
    end
    if nm == "Bull" then  -- +2c per $1 owned
      bc = bc + 2 * math.max(0, math.floor(G.GAME and G.GAME.dollars or 0))
    end
    if nm == "Bootstraps" then  -- +2m per $5 owned
      bm = bm + 2 * math.floor(math.max(0, G.GAME and G.GAME.dollars or 0) / 5)
    end
    if nm == "Blue Joker" then  -- +2c per card remaining in draw pile
      bc = bc + 2 * (G.deck and #G.deck.cards or 0)
    end
    if nm == "Steel Joker" and G.playing_cards then  -- +0.2m per Steel card in deck
      for _, pc in ipairs(G.playing_cards) do
        if pc.ability and pc.ability.enhancement == "m_steel" then bm = bm + 0.2 end
      end
    end
    if nm == "Stone Joker" and G.playing_cards then  -- +25c per Stone card in deck
      for _, pc in ipairs(G.playing_cards) do
        if pc.ability and pc.ability.enhancement == "m_stone" then bc = bc + 25 end
      end
    end
    if nm == "Erosion" and G.playing_cards then  -- +4m per card below starting deck size
      local base    = G.GAME and G.GAME.starting_deck_size or 52
      local missing = math.max(0, base - #G.playing_cards)
      bm = bm + 4 * missing
    end
    if nm == "Swashbuckler" then  -- +mult = total joker sell values
      local total = 0
      for _, j2 in ipairs(G.jokers.cards) do total = total + (j2.sell_cost or 0) end
      bm = bm + total
    end
    if nm == "Constellation" then bx = bx * (tonumber(ex.xmult) or 1) end  -- per planet used (live)
    if nm == "Hologram"      then bx = bx * (tonumber(ex.xmult) or 1) end  -- per card added (live)
    if nm == "Glass Joker"   then bx = bx * (tonumber(ex.xmult) or 1) end  -- per glass destroyed (live)
    if nm == "Ice Cream"     then bc = bc + (tonumber(ex.chips)  or 0) end  -- shrinking chips (live)
    if nm == "Castle"        then bc = bc + (tonumber(ex.chips)  or 0) end  -- growing chips (live)
    if nm == "Spare Trousers" then bm = bm + (tonumber(ex.mult)  or 0) end  -- growing mult (live)
    if nm == "Ride the Bus"  then bm = bm + (tonumber(ex.mult)   or 0) end  -- growing mult (live)
    if nm == "Supernova" and G.GAME and G.GAME.hands then  -- +mult per times most-played hand played
      local most = 0
      for _, hd in pairs(G.GAME.hands) do if (hd.played or 0) > most then most = hd.played end end
      bm = bm + most
    end
    if nm == "Campfire"       then bx = bx * (tonumber(ex.xmult) or 1) end
    if nm == "Yorick"         then bm = bm + (tonumber(ex.mult)  or 0) end
    if nm == "Canio"          then bm = bm + (tonumber(ex.mult)  or 0) end
    if nm == "Ramen"          then bx = bx * (tonumber(ex.xmult) or 2) end
    if nm == "Mail-In Rebate" then bm = bm + (tonumber(ex.mult)  or 0) end
    if nm == "Hit the Road"   then bm = bm + (tonumber(ex.mult)  or 0) end
    if nm == "Cavendish" and G.playing_cards then
      for _, pc in ipairs(G.playing_cards) do
        if pc.base and pc.base.id == 6 and pc.base.suit == "Clubs" then bx = bx * 3; break end
      end
    end
    if nm == "Card Sharp" then
      local most_played, most_count = nil, 0
      if G.GAME and G.GAME.hands then
        for hname, hd in pairs(G.GAME.hands) do
          if (hd.played or 0) > most_count then most_count = hd.played; most_played = hname end
        end
      end
      if most_played and most_played == hand_type_name and most_count > 1 then bx = bx * 3 end
    end
    if nm == "Baseball Card" and G.jokers and G.jokers.cards then
      for _, j2 in ipairs(G.jokers.cards) do
        local rarity = j2.config and j2.config.center and j2.config.center.rarity
        if rarity == 3 then bx = bx * 1.5 end
      end
    end
    if nm == "Walkie Talkie" and card_indices then
      for _, ci in ipairs(card_indices) do
        local c = cards[ci]
        local id = c and c.base and c.base.id or 0
        if id == 10 or id == 4 then bc = bc + 10; bm = bm + 4 end
      end
    end
    if nm == "Smiley Face" and card_indices then
      for _, ci in ipairs(card_indices) do
        local c = cards[ci]
        local id = c and c.base and c.base.id or 0
        if pareidolia or (id >= 11 and id <= 13) then bm = bm + 5 end
      end
    end
    if nm == "The Idol" and card_indices then
      local ts, tv = ex.suit, ex.value
      if ts and tv then
        for _, ci in ipairs(card_indices) do
          local c = cards[ci]
          if c and c.base and c.base.suit == ts and c.base.value == tv then bx = bx * 2 end
        end
      end
    end
    if nm == "Seeing Double" and card_indices then
      local has_club, has_other = false, false
      for _, ci in ipairs(card_indices) do
        local c = cards[ci]
        if c and c.base then
          if c.base.suit == "Clubs" then has_club = true else has_other = true end
        end
      end
      if has_club and has_other then bx = bx * 2 end
    end
    if nm == "Hanging Chad" and card_indices and #card_indices > 0 then
      local c = cards[card_indices[1]]
      if c and c.base and c.base.value then
        local r = VALUE_RANK[c.base.value]
        if r then bc = bc + 2 * (r == 14 and 11 or math.min(r, 10)) end
      end
    end
    if nm == "Acrobat" then
      local hl = G.GAME and G.GAME.current_round and G.GAME.current_round.hands_left or 0
      if hl == 1 then bx = bx * 3 end
    end
    if nm == "Dusk" and card_indices and #card_indices > 0 then
      local hl = G.GAME and G.GAME.current_round and G.GAME.current_round.hands_left or 0
      if hl == 1 then
        local c = cards[card_indices[#card_indices]]
        if c and c.base and c.base.value then
          local r = VALUE_RANK[c.base.value]
          if r then bc = bc + (r == 14 and 11 or math.min(r, 10)) end
        end
      end
    end
    if nm == "Driver's License" and G.playing_cards then
      local n = 0
      for _, pc in ipairs(G.playing_cards) do
        if pc.ability and pc.ability.enhancement and pc.ability.enhancement ~= "" then n = n + 1 end
      end
      if n >= 16 then bx = bx * 3 end
    end
    if nm == "Fortune Teller" then
      local t = G.GAME and G.GAME.consumeable_usage_total and G.GAME.consumeable_usage_total.tarot or 0
      bm = bm + t
    end
    if nm == "Green Joker"  then bm = bm + (tonumber(ex.mult)  or 0) end
    if nm == "Runner"       then bc = bc + (tonumber(ex.chips) or 0) end
    if nm == "Throwback"    then bx = bx * (tonumber(ex.xmult) or 1) end
    if nm == "Red Card"     then bx = bx * (tonumber(ex.xmult) or 1) end
    if nm == "Madness"      then bx = bx * (tonumber(ex.xmult) or 1) end
    if nm == "Lucky Cat"    then bx = bx * (tonumber(ex.xmult) or 1) end
    if nm == "Obelisk"      then bx = bx * (tonumber(ex.xmult) or 1) end

    -- === Neuratro custom jokers ===
    -- Persistent xmult: read live value from ability.extra
    if nm == "Lava Lamp"              then bx = bx * (tonumber(ex.xmult)        or 1.5)  end
    if nm == "Get Harpooned!"         then bx = bx * (tonumber(ex.xmult)        or 3)    end
    if nm == "Abber Demon"            then bx = bx * (tonumber(ex.xmult)        or 1)    end
    if nm == "Evil's Second Birthday" then bx = bx * (tonumber(ex.xmult_bonus)  or 1.5)  end
    if nm == "Long Drive"             then bx = bx * (tonumber(ex.xmult)        or 1)    end
    if nm == "Queenpb"                then bx = bx * (tonumber(ex.xmult)        or 1)    end
    if nm == "Teru"                   then bx = bx * (tonumber(ex.xmult)        or 1)    end
    if nm == "Neuro"                  then bx = bx * (tonumber(ex.xmult)        or 1)    end
    if nm == "Evil"                   then bx = bx * (tonumber(ex.xmult)        or 1)    end
    if nm == "Nere"                   then bx = bx * (tonumber(ex.xmult)        or 1)    end
    if nm == "Anny"                   then bx = bx * (tonumber(ex.xmult)        or 1)    end
    if nm == "Vedal"                  then bx = bx * (tonumber(ex.xmult)        or 1)    end
    -- Random xmult: EV of distribution
    if nm == "Neuro Roulette" then
      bx = bx * (((tonumber(ex.xhigh) or 4) + (tonumber(ex.xlow) or 0.25)) / 2)
    end
    if nm == "xdx" then
      bx = bx * (((tonumber(ex.min) or 1) + (tonumber(ex.max) or 60)) / 20)  -- (min+max)/2/10
    end
    -- KYOTO AT ALL COSTS: EV = xmult/odds added to mult (Xmult_mod context)
    if nm == "KYOTO AT ALL COSTS" then
      bm = bm + (tonumber(ex.Xmult) or 100) / (tonumber(ex.odds) or 20)
    end
    -- Tutel Soup: random 1/4 each of mult/chips/money/xmult
    if nm == "Tutel Soup" then
      bm = bm + (tonumber(ex.mult)  or 15)  * 0.25
      bc = bc + (tonumber(ex.chips) or 100) * 0.25
      bx = bx * ((tonumber(ex.xmult) or 1.5) * 0.25 + 0.75)
    end
    -- Ellie: xmult per Neurodog joker owned
    if nm == "Ellie" then
      local res, upg = 1, tonumber(ex.upg) or 1
      if G.jokers then
        for _, j2 in ipairs(G.jokers.cards) do
          if j2.config and j2.config.center and j2.config.center.key == "j_neurodog" then
            res = res + upg
          end
        end
      end
      bx = bx * res
    end

    -- Persistent +mult: read live value
    if nm == "Neuro Fumo"            then bm = bm + (tonumber(ex.mult)      or 0)  end
    if nm == "Evil's First Birthday" then bm = bm + (tonumber(ex.mult_bonus) or 4)  end
    if nm == "Turtle At Work"        then bm = bm + (tonumber(ex.mult)      or 0)  end
    if nm == "Abandoned Archive 2"   then bm = bm + (tonumber(ex.mult)      or 0)  end
    if nm == "Yippee!"               then bm = bm + (tonumber(ex.mult)      or 0)  end
    if nm == "Neurodog"              then bm = bm + (tonumber(ex.mult)  or 10); bc = bc + (tonumber(ex.chips) or 9) end
    -- Lucy: only triggers on Flush or better
    if nm == "Lucy" and hr >= 6      then bm = bm + (tonumber(ex.mult)      or 0)  end

    -- Persistent +chips: read live value
    if nm == "Recycle Bin" then bc = bc + (tonumber(ex.bonus_chips) or 0) end
    -- Live DDOS: EV = chips * 2/3 (1/3 chance to self-debuff after play)
    if nm == "Live DDOS"   then bc = bc + math.floor((tonumber(ex.chips) or 150) * 0.67) end
    -- Banana Rum: EV ≈ midpoint of random range (destroys self if King of Clubs, skip that case)
    if nm == "Banana Rum"  then
      bc = bc + math.floor(((tonumber(ex.chips_min) or 20) + (tonumber(ex.chips_max) or 200)) / 2)
    end
    -- J0ker: chips per total joker count
    if nm == "J0ker" then
      bc = bc + (tonumber(ex.chips_bonus) or 15) * (G.jokers and #G.jokers.cards or 0)
    end
    -- Twins In Space: chips per planet card used this run
    if nm == "Twins In Space" then
      local p = G.GAME and G.GAME.consumeable_usage_total and G.GAME.consumeable_usage_total.planet or 0
      bc = bc + (tonumber(ex.chip_bonus) or 9) * p
    end
    -- Vedd's Store: chips per Ace of Clubs in full deck
    if nm == "Vedd's Store" and G.playing_cards then
      local n = 0
      for _, pc in ipairs(G.playing_cards) do
        if pc.base and pc.base.id == 14 and pc.base.suit == "Clubs" then n = n + 1 end
      end
      bc = bc + (tonumber(ex.chips) or 35) * n
    end

    -- Card-conditional Neuratro jokers
    -- heartheartheart: xmult if Three of a Kind and all played cards are Hearts
    if nm == "heartheartheart" and hand_type_name == "Three of a Kind" and card_indices then
      local all_hearts = true
      for _, ci in ipairs(card_indices) do
        local c = cards[ci]
        if not (c and c.base and c.base.suit == "Hearts") then all_hearts = false; break end
      end
      if all_hearts then bx = bx * (tonumber(ex.Xmult) or 1) end
    end
    -- CFRB: xmult per King of Spades in played hand
    if nm == "CFRB" and card_indices then
      for _, ci in ipairs(card_indices) do
        local c = cards[ci]
        if c and c.base and c.base.id == 13 and c.base.suit == "Spades" then
          bx = bx * (tonumber(ex.Xmult_bonus) or 1)
        end
      end
    end
    -- Cumilq: xmult per played 6
    if nm == "Cumilq" and card_indices then
      for _, ci in ipairs(card_indices) do
        local c = cards[ci]
        if c and c.base and c.base.id == 6 then bx = bx * (tonumber(ex.xmult) or 1.3) end
      end
    end
    -- Collab: xmult if 3+ face cards of different suits in scoring hand
    if nm == "Collab" and card_indices then
      local suit_faces = {}
      for _, ci in ipairs(card_indices) do
        local c = cards[ci]
        local id = c and c.base and c.base.id or 0
        if (pareidolia or id >= 11) and c.base and c.base.suit and not suit_faces[c.base.suit] then
          suit_faces[c.base.suit] = true
        end
      end
      local n = 0; for _ in pairs(suit_faces) do n = n + 1 end
      if n >= 3 then bx = bx * (tonumber(ex.xmult) or 4) end
    end
    -- Layna: xmult per played card if any 9 in scoring hand (destroys cards)
    if nm == "Layna" and card_indices then
      local has_nine = false
      for _, ci in ipairs(card_indices) do
        local c = cards[ci]
        if c and c.base and c.base.id == 9 then has_nine = true; break end
      end
      if has_nine then bx = bx * (tonumber(ex.xmult) or 3) ^ #card_indices end
    end
    -- Gym Bag: +mult/+chips per Ace held in hand (not played); doubled for Ace of Hearts
    if nm == "Gym Bag" then
      local added = tonumber(ex.added) or 12
      for i, c in ipairs(cards) do
        local is_played = false
        if card_indices then for _, ci in ipairs(card_indices) do if ci == i then is_played = true end end end
        if not is_played and c and c.base and c.base.id == 14 then
          if c.base.suit == "Hearts" then bm = bm + added*2; bc = bc + added*2
          else                            bm = bm + added;   bc = bc + added  end
        end
      end
    end
    -- Alex Void: xmult per negative-edition joker
    if nm == "Alex Void" and G.jokers and G.jokers.cards then
      local neg = 0
      for _, j2 in ipairs(G.jokers.cards) do
        if j2.edition and j2.edition.key == "e_negative" then neg = neg + 1 end
      end
      if neg > 0 then bx = bx * (tonumber(ex.xmult) or 2) ^ neg end
    end
    -- Envious Joker: +mult per Glorpsuit scored card
    if nm == "Envious Joker" and card_indices then
      for _, ci in ipairs(card_indices) do
        local c = cards[ci]
        if c and c.base and c.base.suit == "Glorpsuit" then bm = bm + (tonumber(ex.mult) or 6) end
      end
    end
    -- BTMC: xmult if any played card has osu_seal (read current streak xmult)
    if nm == "BTMC" and card_indices then
      for _, ci in ipairs(card_indices) do
        local c = cards[ci]
        if c and c.seal == "osu_seal" then bx = bx * (tonumber(ex.xmult) or 1); break end
      end
    end
    -- Plasma Globe: xmult per Spectral card used (live value in ability.extra.Xmult)
    if nm == "Plasma Globe" then bx = bx * (tonumber(ex.Xmult) or 1) end
    -- Technical Difficulties: ×0.5 first hand of round, ×1.5 all others
    if nm == "Technical Difficulties" then
      local hands_played = G.GAME and G.GAME.current_round and G.GAME.current_round.hands_played or 0
      bx = bx * (hands_played == 0 and (tonumber(ex.low) or 0.5) or (tonumber(ex.high) or 1.5))
    end
    -- Erm Fish: ^2 power on mult when Neurooper is present; approximate as strong xmult signal
    if nm == "Erm Fish" and G.jokers and G.jokers.cards then
      for _, j2 in ipairs(G.jokers.cards) do
        if j2.config and j2.config.center and j2.config.center.key == "j_nwooper" then
          bx = bx * 20; break  -- rough proxy: mult^2 is extreme; flag as very powerful
        end
      end
    end
    -- Blueprint/Brainstorm: copy static bonuses from adjacent joker
    if nm == "Blueprint" or nm == "Brainstorm" then
      local j_idx = nil
      for ji, jcheck in ipairs(G.jokers.cards) do
        if jcheck == jc then j_idx = ji; break end
      end
      local target_jc = nil
      if nm == "Blueprint" and j_idx then
        target_jc = G.jokers.cards[j_idx + 1]
      elseif nm == "Brainstorm" then
        target_jc = G.jokers.cards[1]
        if target_jc == jc then target_jc = nil end
      end
      if target_jc then
        local tab = target_jc.ability or {}
        bc = bc + (tab.h_mod or 0)
        bm = bm + (tab.h_mult or 0)
        local xm = tab.x_mult or 1
        if xm > 1 then bx = bx * xm end
      end
    end
  end
  return bc, bm, bx
end

local function estimate_score(hand_type_name, card_indices, cards)
  if not G.GAME or not G.GAME.hands then return nil end
  local hd = G.GAME.hands[hand_type_name]
  if not hd then return nil end
  local base_chips = hd.chips or 0
  local base_mult  = hd.mult  or 0

  -- Card chip value (rank-based) + enhancement/edition effects on played cards
  local card_chips  = 0
  local card_mult   = 0
  local card_xmult  = 1
  local played_set  = {}
  if card_indices then
    for _, ci in ipairs(card_indices) do
      played_set[ci] = true
      local c = cards[ci]
      if c then
        -- Red Seal: card triggers twice (double all per-card contributions)
        local seal = c.seal
        local has_red_seal = (seal == "Red")
          or (type(seal) == "table" and (seal.key == "seal_red" or (seal.name and seal.name:lower():find("red"))))
        local trigger_count = has_red_seal and 2 or 1
        -- Base rank chips
        if c.base and c.base.value then
          local r = VALUE_RANK[c.base.value]
          if r then card_chips = card_chips + (r == 14 and 11 or math.min(r, 10)) * trigger_count end
        end
        -- Enhancement effects
        local ef = c.ability and c.ability.enhancement or ""
        if ef == "m_bonus" then card_chips = card_chips + 30 * trigger_count         end
        if ef == "m_mult"  then card_mult  = card_mult  + 4  * trigger_count         end
        if ef == "m_glass" then card_xmult = card_xmult * (2 ^ trigger_count)        end  -- ×2/×4 avg
        if ef == "m_stone" then card_chips = card_chips + 50 * trigger_count         end
        if ef == "m_lucky" then card_mult  = card_mult  + 4  * trigger_count         end  -- EV of 1/5×+20
        -- Card editions
        local ed = c.edition or {}
        if ed.foil       then card_chips = card_chips + 50  * trigger_count  end
        if ed.holo       then card_mult  = card_mult  + 10  * trigger_count  end
        if ed.polychrome then card_xmult = card_xmult * (1.5 ^ trigger_count) end
      end
    end
  end

  -- Steel cards held in hand but NOT played: ×1.5 mult each
  for i, c in ipairs(cards) do
    if not played_set[i] then
      local ef = c and c.ability and c.ability.enhancement or ""
      if ef == "m_steel" then card_xmult = card_xmult * 1.5 end
    end
  end

  -- Joker static + edition effects
  local j_chips, j_mult, j_xmult = 0, 0, 1
  if G.jokers and G.jokers.cards then
    for _, jc in ipairs(G.jokers.cards) do
      local ab = jc.ability or {}
      j_chips = j_chips + (ab.h_mod or 0) + (ab.t_chips or 0)
      j_mult  = j_mult  + (ab.h_mult or 0) + (ab.t_mult or 0)
      local xm = ab.x_mult or 1
      if xm > 1 then j_xmult = j_xmult * xm end
      -- Joker editions
      local ed = jc.edition or {}
      if ed.foil       then j_chips = j_chips + 50  end
      if ed.holo       then j_mult  = j_mult  + 10  end
      if ed.polychrome then j_xmult = j_xmult * 1.5 end
    end
  end

  -- Conditional joker bonuses (hand-type aware)
  local cj_chips, cj_mult, cj_xmult = conditional_joker_bonus(hand_type_name, card_indices, cards)
  j_chips = j_chips + cj_chips
  j_mult  = j_mult  + cj_mult
  j_xmult = j_xmult * cj_xmult

  return math.floor(
    (base_chips + card_chips + j_chips) *
    (base_mult  + card_mult  + j_mult)  *
    j_xmult * card_xmult
  )
end

local function compute_outs(cards, sim1_score, target_remaining, discards_left)
  if not (G and G.deck and G.deck.cards) then return nil end
  if not discards_left or discards_left < 1 then return nil end

  local deck_remaining = #G.deck.cards
  if deck_remaining < 1 then return nil end

  -- Suit distribution in drawn hand
  local suit_counts = {}
  for _, c in ipairs(cards) do
    local s = c and c.base and c.base.suit
    if s then suit_counts[s] = (suit_counts[s] or 0) + 1 end
  end

  -- Suit and rank counts in remaining deck
  local deck_suits = {}
  local deck_ranks = {}
  for _, c in ipairs(G.deck.cards) do
    local s = c and c.base and c.base.suit
    local id = c and c.base and c.base.id
    if s then deck_suits[s] = (deck_suits[s] or 0) + 1 end
    if id then deck_ranks[id] = (deck_ranks[id] or 0) + 1 end
  end

  local outs_parts = {}
  local best_ev = 0

  -- Near-flush: exactly 4 of same suit in hand, need 1 more
  for suit, cnt in pairs(suit_counts) do
    if cnt == 4 then
      local outs = deck_suits[suit] or 0
      local p = outs / deck_remaining
      if p > 0.05 then
        local flush_hd = G.GAME and G.GAME.hands and G.GAME.hands["Flush"]
        local flush_est = flush_hd and
          math.floor((flush_hd.chips + 40) * (flush_hd.mult + 4)) or (sim1_score * 2)
        local ev = math.floor(p * flush_est + (1 - p) * sim1_score)
        if ev > best_ev then best_ev = ev end
        outs_parts[#outs_parts+1] = string.format("FLUSH:P=%.2f,EV=%d,OUTS=%d", p, ev, outs)
      end
    end
  end

  -- Open-ended straight draw: 4 consecutive ranks, 2 completion ranks
  local rank_set = {}
  for _, c in ipairs(cards) do
    local id = c and c.base and c.base.id
    if id then
      rank_set[id] = true
      if id == 14 then rank_set[1] = true end
    end
  end
  for low = 1, 10 do
    local run = true
    for r = low, low+3 do if not rank_set[r] then run=false; break end end
    if run then
      local low_outs   = deck_ranks[low-1] or 0
      local high_outs  = deck_ranks[low+4] or 0
      local total_outs = low_outs + high_outs
      local p = math.min(1, total_outs / deck_remaining)
      if p > 0.05 then
        local str_hd = G.GAME and G.GAME.hands and G.GAME.hands["Straight"]
        local str_est = str_hd and
          math.floor((str_hd.chips + 30) * (str_hd.mult + 4)) or (sim1_score * 1.6)
        local ev = math.floor(p * str_est + (1 - p) * sim1_score)
        if ev > best_ev then best_ev = ev end
        outs_parts[#outs_parts+1] = string.format("STR:P=%.2f,EV=%d,OUTS=%d", p, ev, total_outs)
      end
    end
  end

  if #outs_parts == 0 then
    G.NEURO.outs_ev = nil
    return nil
  end
  G.NEURO.outs_ev = best_ev
  return "OUTS|" .. table.concat(outs_parts, "|")
end

local function simulate_best_plays(cards, opts)
  if not (cards and #cards > 0 and G and G.GAME and G.GAME.hands) then
    return nil
  end

  opts = opts or {}

  local get_info = G and G.FUNCS and G.FUNCS.get_poker_hand_info
  local n = #cards
  local max_pick = math.min(5, n)
  local min_pick = 1

  if opts.respect_blind and G and G.GAME and G.GAME.blind and type(G.GAME.blind.debuff) == "table" then
    local debuff = G.GAME.blind.debuff
    local min_cards = tonumber(debuff.h_size_ge or 0) or 0
    local max_cards = tonumber(debuff.h_size_le or 0) or 0
    if min_cards > 0 then
      min_pick = math.max(min_pick, math.floor(min_cards))
    end
    if max_cards > 0 then
      max_pick = math.min(max_pick, math.floor(max_cards))
    end
  end

  local hand_has_non_debuffed = false
  for i = 1, n do
    if not cards[i].debuff then
      hand_has_non_debuffed = true
      break
    end
  end

  if min_pick > max_pick then
    return nil
  end

  local picks = {}
  local candidates = {}

  local function consider_current()
    local idxs = {}
    local selected = {}
    for i = 1, #picks do
      local idx = picks[i]
      idxs[#idxs + 1] = idx
      selected[#selected + 1] = cards[idx]
    end

    if opts.respect_blind and #selected > 0 and hand_has_non_debuffed then
      local selected_all_debuffed = true
      for i = 1, #selected do
        if not selected[i].debuff then
          selected_all_debuffed = false
          break
        end
      end
      if selected_all_debuffed then
        return
      end
    end

    local hand_type = "High Card"
    if get_info then
      local ok_info, info = pcall(get_info, selected)
      if ok_info and type(info) == "table" and type(info.type) == "string" and info.type ~= "" then
        hand_type = info.type
      end
    end

    local est = estimate_score(hand_type, idxs, cards)
    if type(est) == "number" and est >= 0 then
      candidates[#candidates + 1] = {
        indices = idxs,
        hand_type = hand_type,
        score = est,
      }
    end
  end

  local function rec(start_idx, need)
    if need == 0 then
      consider_current()
      return
    end
    for i = start_idx, n - need + 1 do
      picks[#picks + 1] = i
      rec(i + 1, need - 1)
      picks[#picks] = nil
    end
  end

  for k = min_pick, max_pick do
    rec(1, k)
  end

  if #candidates == 0 then
    return nil
  end

  table.sort(candidates, function(a, b)
    -- Different hand types: prefer higher score (Flush > Pair regardless of card count)
    if a.hand_type ~= b.hand_type then
      return a.score > b.score
    end
    -- Same hand type: prefer FEWER cards (conserve cards for future hands)
    if #a.indices ~= #b.indices then return #a.indices < #b.indices end
    -- Same hand type, same count: prefer higher score (better kickers)
    if a.score ~= b.score then return a.score > b.score end
    local sa = table.concat(a.indices, ",")
    local sb = table.concat(b.indices, ",")
    return sa < sb
  end)

  local unique = {}
  local out = {}
  for _, c in ipairs(candidates) do
    local sig = table.concat(c.indices, ",")
    if not unique[sig] then
      unique[sig] = true
      out[#out + 1] = c
      if #out >= 2 then break end
    end
  end

  return out
end

-- Returns PLAY_PREV: hand_type~est_score for the currently highlighted cards.
-- Lets Neuro see what scoring the current selection would produce before committing.
local _HAND_PRIORITY = {
  ["Flush Five"] = 1, ["Flush House"] = 2, ["Five of a Kind"] = 3,
  ["Straight Flush"] = 4, ["Four of a Kind"] = 5, ["Full House"] = 6,
  ["Flush"] = 7, ["Straight"] = 8, ["Three of a Kind"] = 9,
  ["Two Pair"] = 10, ["Pair"] = 11, ["High Card"] = 12,
  ["mixed5"] = 3, ["mixhouse"] = 6, ["straightmix"] = 8, ["mix"] = 7,
}
local function play_preview_section()
  if not (G and G.hand and G.hand.highlighted and #G.hand.highlighted > 0) then return nil end
  local hand_cards = G.hand.cards
  if not hand_cards then return nil end

  -- Resolve hand indices for highlighted cards
  local idx_nums = {}
  for _, card in ipairs(G.hand.highlighted) do
    for i, hc in ipairs(hand_cards) do
      if hc == card then idx_nums[#idx_nums + 1] = i; break end
    end
  end
  if #idx_nums == 0 then return nil end

  -- Run hand detection on the selected subset
  local sel = {}
  for _, i in ipairs(idx_nums) do sel[#sel + 1] = hand_cards[i] end
  local vc, sc, vi, si, wc, wi = tally_hand(sel)
  local combo_scoring = {}
  detect_value_combos(vc, vi, {}, combo_scoring)
  detect_flush_combos(sc, si, {}, combo_scoring, wc, wi)
  detect_straight_combos(sel, {}, combo_scoring)

  local best_type = "High Card"
  for _, cs in ipairs(combo_scoring) do
    local p = _HAND_PRIORITY[cs.type] or 99
    if p < (_HAND_PRIORITY[best_type] or 99) then best_type = cs.type end
  end

  local est = estimate_score(best_type, idx_nums, hand_cards)
  if not est then return nil end
  return string.format("PLAY_PREV:%s~%d", compact_text(best_type, 20), est)
end

local function combos_section()
  if not G or not G.hand or not G.hand.cards or #G.hand.cards == 0 then
    return nil
  end

  local cards = G.hand.cards
  local value_counts, suit_counts, value_indices, suit_indices, wild_count, wild_indices = tally_hand(cards)

  local combos = {}
  local combo_scoring = {}

  detect_value_combos(value_counts, value_indices, combos, combo_scoring)
  detect_flush_combos(suit_counts, suit_indices, combos, combo_scoring, wild_count, wild_indices)
  detect_straight_combos(cards, combos, combo_scoring)

  if #combos == 0 then
    combos[#combos + 1] = "High Card only"
  end

  local score_lines = {}
  local seen_types = {}
  for _, cs in ipairs(combo_scoring) do
    if not seen_types[cs.type] then
      seen_types[cs.type] = true
      local est = estimate_score(cs.type, cs.indices, cards)
      if est then
        score_lines[#score_lines + 1] = cs.type .. "~" .. est
      end
    end
  end
  if not seen_types["High Card"] then
    local hc_est = estimate_score("High Card", {1}, cards)
    if hc_est then score_lines[#score_lines + 1] = "High Card~" .. hc_est end
  end

  local target = ""
  local target_remaining = nil
  if G.GAME and G.GAME.blind then
    local t = (G.GAME.blind.chips or 0) * (G.GAME.blind.mult or 1)
    local score_so_far = G.GAME.chips or 0
    target_remaining = t - score_so_far
    target = "|TARGET:" .. target_remaining
  end

  local sim_tokens = ""
  local sim = simulate_best_plays(cards, { respect_blind = true })
  local best_score = 0
  local can_clear_now = "N"
  if sim and #sim > 0 then
    local best = sim[1]
    best_score = tonumber(best.score) or 0
    -- Cache SIM1 play indices for dispatcher to embed in DECIDE
    local sim1_idx_strs = {}
    for _, idx in ipairs(best.indices) do
      sim1_idx_strs[#sim1_idx_strs + 1] = tostring(idx)
    end
    G.NEURO.sim1_play = { indices = sim1_idx_strs, hand_type = best.hand_type, score = best.score }
    sim_tokens = sim_tokens
      .. "|SIM1:" .. table.concat(best.indices, ",")
      .. "~" .. compact_text(best.hand_type, 16)
      .. "~" .. tostring(best.score)
    if sim[2] then
      sim_tokens = sim_tokens
        .. "|SIM2:" .. table.concat(sim[2].indices, ",")
        .. "~" .. compact_text(sim[2].hand_type, 16)
        .. "~" .. tostring(sim[2].score)
    end

    local discards_left = G.GAME and G.GAME.current_round and G.GAME.current_round.discards_left or 0
    if type(target_remaining) == "number" and target_remaining > 0 and discards_left > 0 then
      local cutoff = math.max(120, math.floor(target_remaining * 0.4))
      local prefer_discard = best.score < cutoff
      sim_tokens = sim_tokens .. "|SIMD:" .. (prefer_discard and "Y-WEAK" or "N-OK")
    end
    local quality = "?"
    if type(target_remaining) == "number" and target_remaining > 0 then
      local ratio = best_score / target_remaining
      if ratio >= 1.0 then quality = "WIN"
      elseif ratio >= 0.6 then quality = "GOOD"
      elseif ratio >= 0.3 then quality = "WEAK"
      else quality = "POOR" end
    end
    sim_tokens = sim_tokens .. "|Q:" .. quality
    local rec_action = "PLAY"
    if discards_left > 0 and (quality == "WEAK" or quality == "POOR") then
      rec_action = "DISCARD"
    end
    sim_tokens = sim_tokens .. "|REC:" .. rec_action
    if type(target_remaining) == "number" and target_remaining > 0 and best_score >= target_remaining then
      can_clear_now = "Y"
    end
  else
    G.NEURO.sim1_play = nil
  end

  -- Draw outs for near-flush / straight draws
  do
    local discards_out = G.GAME and G.GAME.current_round and G.GAME.current_round.discards_left or 0
    local outs_str = compute_outs(cards, best_score, target_remaining, discards_out)
    if outs_str then sim_tokens = sim_tokens .. "|" .. outs_str end
  end

  local result = "CB:" .. table.concat(combos, "|")
  if #score_lines > 0 then
    result = result .. "\nSCORE_EST:" .. table.concat(score_lines, "|") .. target .. sim_tokens
  end
  if type(target_remaining) == "number" then
    local hands_left = G.GAME and G.GAME.current_round and G.GAME.current_round.hands_left or 0
    local discards_left = G.GAME and G.GAME.current_round and G.GAME.current_round.discards_left or 0
    local deck_sz = G.deck and G.deck.cards and #G.deck.cards or 0
    result = result .. string.format("\nWIN|REM:%d|BEST:%d|CLR:%s|H:%d|D:%d|DK:%d",
      math.max(0, math.floor(target_remaining)),
      math.max(0, math.floor(best_score or 0)),
      can_clear_now,
      math.max(0, math.floor(hands_left or 0)),
      math.max(0, math.floor(discards_left or 0)),
      deck_sz
    )
  end
  if G.GAME and G.GAME.hands then
    local hp_parts = {}
    for nm, hd in pairs(G.GAME.hands) do
      if hd.played and hd.played > 0 and hd.visible ~= false then
        hp_parts[#hp_parts + 1] = { name = nm, count = hd.played }
      end
    end
    table.sort(hp_parts, function(a, b) return a.count > b.count end)
    local hp_tokens = {}
    for i = 1, math.min(5, #hp_parts) do
      hp_tokens[#hp_tokens + 1] = hp_parts[i].name .. "=" .. hp_parts[i].count
    end
    if #hp_tokens > 0 then
      result = result .. "\nHP:" .. table.concat(hp_tokens, "|")
    end
  end

  if G.hand and G.hand.highlighted and #G.hand.highlighted > 0
      and G.hand.cards and G.FUNCS and G.FUNCS.get_poker_hand_info then
    local hl_idx = {}
    local hl_sel = {}
    for _, hc in ipairs(G.hand.highlighted) do
      for i, c in ipairs(cards) do
        if c == hc then hl_idx[#hl_idx + 1] = i; hl_sel[#hl_sel + 1] = c; break end
      end
    end
    if #hl_idx > 0 then
      local ok, info = pcall(G.FUNCS.get_poker_hand_info, hl_sel)
      if ok and type(info) == "table" and info.type then
        local est = estimate_score(info.type, hl_idx, cards)
        if est then
          result = result .. "\nHGS:" .. compact_text(info.type, 16) .. "~" .. tostring(est)
        end
        local jtrig = joker_trigger_labels(info.type, hl_idx, cards)
        if jtrig then result = result .. "\n" .. jtrig end
      end
    end
  end
  return result
end

local function consumables_section()
  if not G or not G.consumeables or not G.consumeables.cards or #G.consumeables.cards == 0 then
    return nil
  end
  local rows = {}
  for i, card in ipairs(G.consumeables.cards) do
    local name = compact_text(safe_name(card) or "Unknown", 28)
    local ability = card.ability or {}
    local set = compact_text(ability.set or "?", 20)
    local desc = compact_text(card_description(card, 88), 88)
    if not desc or desc == "" then
      desc = compact_text(safe_description((card.config and card.config.center and card.config.center.loc_txt) or ability.loc_txt, card, 88), 88)
    end
    if not desc or desc == "" then desc = "-" end
    rows[#rows + 1] = { tostring(i), name, set, desc }
  end
  return maybe_dict_encode_rows("C:i,n,t,d", rows, {
    { index = 2, prefix = "N" },
    { index = 3, prefix = "T" },
    { index = 4, prefix = "D" },
  })
end

local function discard_sim_section()
  if not (G and G.hand and G.hand.highlighted and #G.hand.highlighted > 0) then return nil end
  if not (G.hand.cards and G.deck and G.deck.cards and #G.deck.cards > 0) then return nil end
  local discards_left = G.GAME and G.GAME.current_round and G.GAME.current_round.discards_left or 0
  if discards_left <= 0 then return nil end

  local hl_set = {}
  for _, c in ipairs(G.hand.highlighted) do hl_set[c] = true end
  local kept = {}
  for _, c in ipairs(G.hand.cards) do
    if not hl_set[c] then kept[#kept + 1] = c end
  end

  local n_draw = #G.hand.highlighted
  local deck = G.deck.cards
  local deck_n = #deck

  local deck_suit_cnt, deck_rank_cnt = {}, {}
  for _, c in ipairs(deck) do
    local s = c.base and c.base.suit
    local id = c.base and tonumber(c.base.id or 0) or 0
    if s then deck_suit_cnt[s] = (deck_suit_cnt[s] or 0) + 1 end
    if id > 0 then deck_rank_cnt[id] = (deck_rank_cnt[id] or 0) + 1 end
  end

  local kept_suit_cnt, kept_rank_cnt, kept_ids, kept_wild = {}, {}, {}, 0
  for _, c in ipairs(kept) do
    local s = c.base and c.base.suit
    local id = c.base and tonumber(c.base.id or 0) or 0
    local is_wild = c.ability and c.ability.enhancement == "m_wild"
    if is_wild then
      kept_wild = kept_wild + 1
    elseif s then
      kept_suit_cnt[s] = (kept_suit_cnt[s] or 0) + 1
    end
    if id > 0 then kept_rank_cnt[id] = (kept_rank_cnt[id] or 0) + 1; kept_ids[#kept_ids + 1] = id end
  end

  local outs = {}

  local best_suit, best_suit_kept = nil, 0
  for suit, cnt in pairs(kept_suit_cnt) do
    if cnt > best_suit_kept then best_suit_kept = cnt; best_suit = suit end
  end
  if best_suit then
    local effective_kept = best_suit_kept + kept_wild
    local need = math.max(0, 5 - effective_kept)
    if need == 0 then
      outs[#outs + 1] = "Flush:HELD"
    elseif need <= n_draw then
      local avail = deck_suit_cnt[best_suit] or 0
      if avail > 0 then outs[#outs + 1] = "Flush:" .. avail .. "/" .. deck_n end
    end
  elseif kept_wild >= 5 then
    outs[#outs + 1] = "Flush:HELD(wild)"
  end

  if #kept_ids >= 4 then
    local unique_ids, seen_u = {}, {}
    for _, id in ipairs(kept_ids) do
      if not seen_u[id] then seen_u[id] = true; unique_ids[#unique_ids + 1] = id end
    end
    table.sort(unique_ids)
    if seen_u[14] and not seen_u[1] then
      table.insert(unique_ids, 1, 1)
      seen_u[1] = true
    end
    for i = 1, #unique_ids - 3 do
      local lo, hi = unique_ids[i], unique_ids[i + 3]
      local span = hi - lo
      if span == 4 then
        outs[#outs + 1] = "Straight:HELD"; break
      elseif span <= 4 and n_draw >= 1 then
        local gap_id = nil
        for r = lo, hi do
          if not seen_u[r] then gap_id = r; break end
        end
        if gap_id then
          local avail = deck_rank_cnt[gap_id] or 0
          if avail > 0 then outs[#outs + 1] = "Straight:" .. avail .. "/" .. deck_n end
          break
        end
      end
    end
  end

  for id, cnt in pairs(kept_rank_cnt) do
    local kind = nil
    if cnt == 1 and n_draw >= 1 then kind = "Pair"
    elseif cnt == 2 and n_draw >= 1 then kind = "Trips"
    elseif cnt == 3 and n_draw >= 1 then kind = "Quads"
    end
    if kind then
      local avail = deck_rank_cnt[id] or 0
      if avail > 0 then outs[#outs + 1] = kind .. ":" .. avail .. "/" .. deck_n end
    end
  end

  local kept_hand = nil
  if G.FUNCS and G.FUNCS.get_poker_hand_info and #kept > 0 then
    local ok, info = pcall(G.FUNCS.get_poker_hand_info, kept)
    if ok and type(info) == "table" and info.type then kept_hand = info.type end
  end

  local parts = { string.format("DSIM|K:%d|D:%d|DK:%d", #kept, n_draw, deck_n) }
  if kept_hand then parts[#parts + 1] = "|KH:" .. compact_text(kept_hand, 16) end
  if #outs > 0 then parts[#parts + 1] = "|OUTS:" .. table.concat(outs, ",") end
  return table.concat(parts)
end

local function item_rank(card)
  if not card then return "C" end
  local ab = card.ability or {}
  local score = 0
  if ab.x_mult and ab.x_mult > 1 then score = score + 40 end
  if ab.h_mult and ab.h_mult > 0 then score = score + math.min(20, ab.h_mult * 2) end
  if ab.h_mod and ab.h_mod > 0 then score = score + math.min(10, math.floor(ab.h_mod / 5)) end
  if ab.t_mult and ab.t_mult > 0 then score = score + 15 end
  local ed = card.edition
  if ed and type(ed) == "table" then
    if ed.polychrome then score = score + 35 end
    if ed.holo then score = score + 20 end
    if ed.foil then score = score + 10 end
  end
  if ab.set == "Booster" then score = score + 15 end
  if ab.set == "Voucher" then score = score + 25 end
  -- Planet cards level hand types permanently (no numeric stats, but always valuable)
  if ab.set == "Planet" then score = score + 15 end
  -- Tarot cards have useful effects (most have no numeric stats)
  if ab.set == "Tarot" then score = score + 10 end
  if score >= 35 then return "S"
  elseif score >= 20 then return "A"
  elseif score >= 10 then return "B"
  else return "C" end
end

local function vouchers_section()
  if not (G and G.GAME and G.GAME.used_vouchers) then return nil end
  local names = {}
  for k, v in pairs(G.GAME.used_vouchers) do
    if v then names[#names + 1] = k:gsub("^v_", "") end
  end
  if #names == 0 then return nil end
  table.sort(names)
  return "V|" .. table.concat(names, ",")
end

local function shop_section()
  if not G or not G.GAME then return nil end
  local money = G.GAME.dollars or 0
  local joker_count = G.jokers and #G.jokers.cards or 0
  local joker_limit = G.jokers and G.jokers.config and G.jokers.config.card_limit or 5
  local cons_count = G.consumeables and #G.consumeables.cards or 0
  local cons_limit = G.consumeables and G.consumeables.config and G.consumeables.config.card_limit or 2
  local reroll = G.GAME.current_round and G.GAME.current_round.reroll_cost or 5
  local free_rerolls = G.GAME.current_round and G.GAME.current_round.free_rerolls or 0
  local discount = G.GAME.discount_percent or 0
  local inflation = G.GAME.inflation or 0
  local interest = calc_interest(money)
  local no_interest = G.GAME.modifiers and G.GAME.modifiers.no_interest and "Y" or "N"
  local ante = G.GAME.round_resets and G.GAME.round_resets.ante or "?"
  local econ = economy_projection()
  local interest_cap = G.GAME.interest_cap or 25
  local paid_rerolls = reroll > 0 and math.floor(money / reroll) or 0
  local max_rerolls = free_rerolls + paid_rerolls
  local cheapest = nil

  local function update_cheapest(area)
    if not (area and area.cards) then return end
    for _, card in ipairs(area.cards) do
      local cost = card and card.cost
      if type(cost) == "number" and cost >= 0 then
        if not cheapest or cost < cheapest then
          cheapest = cost
        end
      end
    end
  end
  update_cheapest(G.shop_jokers)
  update_cheapest(G.shop_vouchers)
  update_cheapest(G.shop_booster)
  local reroll_safe = "N"
  if free_rerolls > 0 and type(cheapest) == "number" then
    reroll_safe = "Y"
  elseif type(cheapest) == "number" and type(reroll) == "number" and reroll > 0 then
    reroll_safe = ((money - reroll) >= cheapest) and "Y" or "N"
  end
  local effective_reroll = free_rerolls > 0 and 0 or reroll
  local can_afford_reroll = (free_rerolls > 0 or money >= reroll) and "Y" or "N"

  local lines = {}
  local sh_line = string.format("SH|A:%s|$:%d|IN:+%d|CAP:%d|NI:%s|RR:%d|RRA:%s|RRS:%s|RRM:%d|J:%d/%d|C:%d/%d|PY:B%d+H%d+D%d+I%d=T%d",
    tostring(ante), money, interest, interest_cap, no_interest, effective_reroll,
    can_afford_reroll, reroll_safe, max_rerolls,
    joker_count, joker_limit, cons_count, cons_limit,
    econ and econ.blind_reward or 0,
    econ and econ.hands_bonus or 0,
    econ and econ.discard_bonus or 0,
    econ and econ.interest or 0,
    econ and econ.projected_total or 0)
  if free_rerolls > 0 then sh_line = sh_line .. "|FR:" .. tostring(free_rerolls) end
  if discount > 0 then sh_line = sh_line .. "|DSC:" .. tostring(discount) .. "%" end
  if inflation > 0 then sh_line = sh_line .. "|INF:" .. tostring(inflation) end
  lines[#lines + 1] = sh_line
  local areas = {
    { area = G.shop_jokers, label = "shop_jokers" },
    { area = G.shop_vouchers, label = "shop_vouchers" },
    { area = G.shop_booster, label = "shop_booster" },
  }
  local has_items = false
  for _, entry in ipairs(areas) do
    if entry.area and entry.area.cards and #entry.area.cards > 0 then
      if not has_items then
        lines[#lines + 1] = "I:a,i,n,$,ok,r,f,d"
        has_items = true
      end
      for i, card in ipairs(entry.area.cards) do
        local name = compact_text(safe_name(card) or "Unknown", 28)
        local cost = card.cost or 0
        local can_afford = cost <= money and "Y" or "N"
        lines[#lines + 1] = string.format("%s,%d,%s,$%d,%s,%s,%s,%s",
          entry.label, i, name, cost, can_afford, item_rank(card), card_effect_summary(card), card_description_full(card, 56))
      end
    end
  end
  if not has_items then
    lines[#lines + 1] = "I:empty"
  end

  return table.concat(lines, "\n")
end

local function blind_select_section()
  if not G or not G.GAME then return nil end
  local ante = G.GAME.round_resets and G.GAME.round_resets.ante or "?"
  local ante_num = tonumber(ante)
  local money = G.GAME.dollars or 0
  local hands = G.GAME.current_round and G.GAME.current_round.hands_left or 0
  local discards = G.GAME.current_round and G.GAME.current_round.discards_left or 0
  local no_interest = G.GAME.modifiers and G.GAME.modifiers.no_interest and "Y" or "N"
  local econ = economy_projection()

  local skips = G.GAME.skips or 0

  local lines = {}
  local bs_line = string.format("BS|A:%s|$:%d|H:%d|D:%d|NI:%s|PY:B%d+H%d+D%d+I%d=T%d",
    tostring(ante), money, hands, discards, no_interest,
    econ and econ.blind_reward or 0,
    econ and econ.hands_bonus or 0,
    econ and econ.discard_bonus or 0,
    econ and econ.interest or 0,
    econ and econ.projected_total or 0)
  if skips > 0 then bs_line = bs_line .. "|SKP:" .. tostring(skips) end
  lines[#lines + 1] = bs_line

  -- Bosses already used this run (helps predict upcoming boss blinds)
  if G.GAME.bosses_used and next(G.GAME.bosses_used) then
    local boss_names = {}
    for k, v in pairs(G.GAME.bosses_used) do
      if v then boss_names[#boss_names + 1] = k:gsub("^bl_", "") end
    end
    if #boss_names > 0 then
      table.sort(boss_names)
      lines[#lines + 1] = "BU|" .. table.concat(boss_names, ",")
    end
  end

  if G.GAME.round_resets and G.GAME.round_resets.blind_states then
    local bs = G.GAME.round_resets.blind_states
    local on_deck = G.GAME.blind_on_deck or "?"
    lines[#lines + 1] = string.format("BP|OD:%s|S:%s|B:%s|BO:%s",
      compact_text(on_deck, 12),
      compact_text(bs.Small or "?", 12),
      compact_text(bs.Big or "?", 12),
      compact_text(bs.Boss or "?", 12))
  end

  local can_skip = "N"
  if G.GAME.round_resets and G.GAME.round_resets.blind_choices then
    local c = G.GAME.round_resets.blind_choices
    if (ante_num == 1 and c.Small) or (ante_num and ante_num > 1 and c.Big) then
      can_skip = "Y"
    end
  end
  local reroll_cost = 10
  local bankroll = (G.GAME.dollars or 0) - (G.GAME.bankrupt_at or 0)
  local has_retcon = G.GAME.used_vouchers and G.GAME.used_vouchers["v_retcon"]
  local has_directors_cut = G.GAME.used_vouchers and G.GAME.used_vouchers["v_directors_cut"]
  local boss_not_rerolled = not (G.GAME.round_resets and G.GAME.round_resets.boss_rerolled)
  local reroll_enabled = has_retcon or (has_directors_cut and boss_not_rerolled)
  local can_reroll_boss = (bankroll >= reroll_cost and reroll_enabled) and "Y" or "N"
  lines[#lines + 1] = string.format("BA|SK:%s|RB:%s|RC:%d|RE:%s",
    can_skip, can_reroll_boss, reroll_cost, (reroll_enabled and "Y" or "N"))

  if G.GAME.round_resets and G.GAME.round_resets.blind_choices then
    local choices = G.GAME.round_resets.blind_choices
    local states = G.GAME.round_resets.blind_states or {}
    local tags = G.GAME.round_resets.blind_tags or {}
    lines[#lines + 1] = "BO:t,k,n,s,tg,rw,tag,tag_effect,db"
    for _, btype in ipairs({"Small", "Big", "Boss"}) do
      local key = choices[btype]
      if key and G.P_BLINDS and G.P_BLINDS[key] then
        local blind_def = G.P_BLINDS[key]
        local debuff_text = "-"
        if blind_def.debuff or btype == "Boss" then
          if blind_def.debuff and blind_def.debuff.text then
            debuff_text = compact_text(blind_def.debuff.text, 60)
          elseif blind_def.loc_txt then
            debuff_text = compact_text(safe_description(blind_def.loc_txt, nil, 60), 60)
          end
        end

        local tag_key = tags[btype]
        local tag_name = "-"
        local tag_effect = "-"
        if tag_key then
          local tag_def = G.P_TAGS and G.P_TAGS[tag_key]
          if tag_def then
            tag_name = compact_text(tag_def.name or tag_key, 24)
            -- Try to extract description from loc_txt
            local desc = safe_description(tag_def.loc_txt, nil, 60)
            if not desc or desc == "" then
              -- Some tags store description in config.ref_table
              local rt = tag_def.config and tag_def.config.ref_table
              if rt and rt.loc_txt then
                desc = safe_description(rt.loc_txt, nil, 60)
              end
            end
            if desc and desc ~= "" then
              tag_effect = compact_text(desc, 60)
            end
          else
            tag_name = compact_text(tag_key, 24)
          end
        end

        local target = calc_blind_target(key)
        local reward = blind_def.dollars or 0
        lines[#lines + 1] = string.format("%s,%s,%s,%s,%s,$%d,%s,%s,%s",
          btype,
          compact_text(key, 24),
          compact_text(blind_def.name or key, 30),
          compact_text(states[btype] or "?", 16),
          target and tostring(target) or "?",
          reward,
          tag_name,
          tag_effect,
          debuff_text)
      end
    end
  end

  return table.concat(lines, "\n")
end

local function pack_section(state_name)
  local bp = G and (G.pack_cards or G.booster_pack)  -- SMODS uses G.pack_cards
  if not bp or not bp.cards then
    return nil
  end
  local pack_type = (state_name == "SMODS_BOOSTER_OPENED") and "BOOSTER" or state_name:gsub("_PACK", "")
  local picks_left = tonumber(G and G.GAME and G.GAME.pack_choices or 0) or 0
  local lines = {}
  lines[#lines + 1] = "PK:" .. pack_type .. "|PICKS:" .. tostring(picks_left)
  local rows = {}
  for i, card in ipairs(bp.cards) do
    local name = compact_text(safe_name(card) or "Unknown", 28)
    local ability = card.ability or {}
    local set = compact_text(ability.set or "?", 20)
    rows[#rows + 1] = { tostring(i), name, set, item_rank(card), card_effect_summary(card) }
  end
  -- Cache the best-ranked card for explicit LLM pick hint
  local best_idx = nil
  local best_rank_score = -1
  local rank_scores = { S = 4, A = 3, B = 2, C = 1 }
  for _, row in ipairs(rows) do
    local rs = rank_scores[row[4]] or 0
    if rs > best_rank_score then
      best_rank_score = rs
      best_idx = row[1]
    end
  end
  G.NEURO.pack_best = best_idx and { index = best_idx, rank = (best_rank_score >= 4 and "S" or best_rank_score >= 3 and "A" or best_rank_score >= 2 and "B" or "C") } or nil
  lines[#lines + 1] = maybe_dict_encode_rows("PC:i,n,t,r,f", rows, {
    { index = 2, prefix = "N" },
    { index = 3, prefix = "T" },
    { index = 4, prefix = "R" },
    { index = 5, prefix = "F" },
  })
  return table.concat(lines, "\n")
end

local function round_eval_section()
  if not G or not G.GAME then return nil end
  local money = G.GAME.dollars or 0
  local interest = calc_interest(money)
  local no_interest = G.GAME.modifiers and G.GAME.modifiers.no_interest and "Y" or "N"
  local ante = G.GAME.round_resets and G.GAME.round_resets.ante or "?"
  local round = G.GAME.round or "?"
  local interest_cap = G.GAME.interest_cap or 25
  local econ = economy_projection()
  return string.format("RE|A:%s|R:%s|$:%d|IN:+%d|CAP:%d|NI:%s|PY:B%d+H%d+D%d+I%d=T%d",
    tostring(ante), tostring(round), money, interest, interest_cap, no_interest,
    econ and econ.blind_reward or 0,
    econ and econ.hands_bonus or 0,
    econ and econ.discard_bonus or 0,
    econ and econ.interest or 0,
    econ and econ.projected_total or 0)
end

local function deck_size_line()
  if not G or not G.deck or not G.deck.cards then return nil end
  local deck_name = ""
  local deck_desc = ""
  if G.GAME and G.GAME.back then
    local b = G.GAME.back
    local bkey = b.name
    local pc = bkey and G.P_CENTERS and G.P_CENTERS[bkey]
    if pc then
      local raw_name = (pc.loc_txt and pc.loc_txt.name) or pc.name or bkey or ""
      if type(raw_name) == "string" and raw_name ~= "" then
        if raw_name:find("_") and not raw_name:find(" ") then
          raw_name = raw_name:gsub("^b_",""):gsub("_"," ")
          raw_name = raw_name:gsub("(%a)([%w]*)", function(a,b2) return a:upper()..b2 end)
        end
        deck_name = raw_name
      end
      local ok_d, d = pcall(safe_description, pc.loc_txt, pc, "Back", bkey)
      if ok_d and d and d ~= "" then
        deck_desc = compact_text(d, 80)
      end
    elseif b.name then
      deck_name = tostring(b.name)
    end
  end
  local discard_count = G.discard and G.discard.cards and #G.discard.cards or 0
  local out = "DK"
  if deck_name ~= "" then out = out .. "|N:" .. compact_text(deck_name, 24) end
  out = out .. "|SZ:" .. tostring(#G.deck.cards)
  out = out .. "|DP:" .. tostring(discard_count)
  if deck_desc ~= "" then out = out .. "|AB:" .. deck_desc end
  return out
end

local function action_memory_section(state_name)
  if not G then return nil end

  local parts = {}
  local recent = G.NEURO.recent_actions
  if type(recent) == "table" and #recent > 0 then
    local from = math.max(1, #recent - 3)
    local tokens = {}
    local i = from
    while i <= #recent do
      local name = tostring(recent[i] or "")
      local count = 1
      while (i + count) <= #recent and recent[i + count] == name do
        count = count + 1
      end
      if name ~= "" then
        tokens[#tokens + 1] = (count > 1) and (name .. "x" .. count) or name
      end
      i = i + count
    end
    if #tokens > 0 then
      parts[#parts + 1] = "L:" .. compact_text(table.concat(tokens, ">"), 84)
    end
  end

  if state_name == "SHOP" then
    local rr = tonumber(G.NEURO.shop_reroll_count or 0) or 0
    parts[#parts + 1] = "SR:" .. tostring(math.max(0, math.floor(rr)))
  end

  if #parts == 0 then return nil end
  return "AH|" .. table.concat(parts, "|")
end

local function play_area_section()
  if not (G and G.play and G.play.cards and #G.play.cards > 0) then return nil end
  local parts = {}
  for i, card in ipairs(G.play.cards) do
    local base = card.base or {}
    local v = short_value(base.value)
    local s = short_suit(base.suit)
    local mods = ""
    local enh = short_enh(card)
    local seal = short_seal(card)
    local ed = short_edition(card)
    if enh ~= "" then mods = mods .. "+" .. enh end
    if seal ~= "" then mods = mods .. "+" .. seal end
    if ed ~= "" then mods = mods .. "+" .. ed end
    parts[#parts + 1] = tostring(v) .. tostring(s) .. mods
  end
  return "PLAY|" .. table.concat(parts, ",")
end

local _ctx_cache = nil
local _ctx_cache_state = nil
local _ctx_cache_key = nil
local _ctx_cache_at = 0
local CTX_CACHE_TTL = 0.20
local _last_joker_sig_force = nil
local discard_heuristics_section

local function now_time()
  if G and G.TIMERS and G.TIMERS.REAL then return G.TIMERS.REAL end
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

function ContextCompact.build(state_name, allowed_actions, opts)
  opts = opts or {}
  local action_set = to_set(allowed_actions)
  local has_filters = allowed_actions ~= nil

  local action_key = "*"
  if has_filters then
    local parts = {}
    for _, a in ipairs(allowed_actions) do parts[#parts + 1] = tostring(a) end
    table.sort(parts)
    action_key = table.concat(parts, ",")
  end

  local joker_sig = jokers_signature()
  local jokers_changed_for_force = joker_sig ~= _last_joker_sig_force
  if opts.force_phase and jokers_changed_for_force then
    _last_joker_sig_force = joker_sig
  end
  local include_full_jokers = opts.full_jokers or (opts.force_phase and jokers_changed_for_force)

  local cache_key = table.concat({
    tostring(state_name or "?"),
    action_key,
    include_full_jokers and "J1" or "J0",
    joker_sig,
  }, "|")

  local t = now_time()
  if _ctx_cache and _ctx_cache_state == state_name and _ctx_cache_key == cache_key and (t - _ctx_cache_at) < CTX_CACHE_TTL then
    return _ctx_cache
  end

  local sections = {}
  sections[#sections + 1] = version_section()
  sections[#sections + 1] = header_section(state_name)
  sections[#sections + 1] = legality_section(state_name, action_set)
  sections[#sections + 1] = action_memory_section(state_name)

  if state_name == "MENU" or state_name == "RUN_SETUP" then
    sections[#sections + 1] = run_section()
    sections[#sections + 1] = setup_decks_section()
  end

  if state_name == "SELECTING_HAND" then
    sections[#sections + 1] = blind_line()
    sections[#sections + 1] = blind_debuff_line()
    sections[#sections + 1] = deck_size_line()
    sections[#sections + 1] = play_area_section()
    sections[#sections + 1] = vouchers_section()
    sections[#sections + 1] = hand_limits_section()
    sections[#sections + 1] = hand_section()
    if (not has_filters) or has_action(action_set, "set_hand_highlight") or has_action(action_set, "clear_hand_highlight")
      or has_action(action_set, "play_cards_from_highlighted") or has_action(action_set, "discard_cards_from_highlighted") then
      sections[#sections + 1] = highlighted_section()
      sections[#sections + 1] = play_preview_section()
    end
    if (not has_filters) or has_action(action_set, "set_hand_highlight") or has_action(action_set, "play_cards_from_highlighted")
      or has_action(action_set, "discard_cards_from_highlighted") or has_action(action_set, "reorder_hand_cards")
      or has_action(action_set, "joker_strategy") or has_action(action_set, "quick_status") then
      sections[#sections + 1] = jokers_section(include_full_jokers)
    end
    if (not has_filters) or has_action(action_set, "hand_levels_info") or has_action(action_set, "simulate_hand")
      or has_action(action_set, "set_hand_highlight") then
      sections[#sections + 1] = levels_section()
    end
    if (not has_filters) or has_action(action_set, "simulate_hand") or has_action(action_set, "set_hand_highlight")
      or has_action(action_set, "play_cards_from_highlighted") or has_action(action_set, "discard_cards_from_highlighted") then
      sections[#sections + 1] = combos_section()
    end
    if (not has_filters) or has_action(action_set, "discard_cards_from_highlighted") or has_action(action_set, "set_hand_highlight") then
      sections[#sections + 1] = discard_heuristics_section()
    end
    if (not has_filters) or has_action(action_set, "consumables_info") or has_action(action_set, "use_card") then
      sections[#sections + 1] = consumables_section()
    end
    sections[#sections + 1] = discard_sim_section()
    sections[#sections + 1] = deck_cards_section()

  elseif state_name == "SHOP" then
    sections[#sections + 1] = vouchers_section()
    sections[#sections + 1] = shop_section()
    if (not has_filters) or has_action(action_set, "buy_from_shop") or has_action(action_set, "sell_card")
      or has_action(action_set, "set_joker_order") or has_action(action_set, "joker_strategy") then
      sections[#sections + 1] = jokers_section(include_full_jokers)
    end
    if (not has_filters) or has_action(action_set, "consumables_info") or has_action(action_set, "use_card")
      or has_action(action_set, "sell_card") then
      sections[#sections + 1] = consumables_section()
    end
    -- Hand needed when using tarots/spectrals that require card targeting
    if (not has_filters) or has_action(action_set, "use_card") then
      sections[#sections + 1] = hand_section()
    end

  elseif state_name == "BLIND_SELECT" then
    sections[#sections + 1] = vouchers_section()
    sections[#sections + 1] = blind_select_section()
    if (not has_filters) or has_action(action_set, "joker_strategy") then
      sections[#sections + 1] = jokers_section(include_full_jokers)
    end

  elseif state_name == "ROUND_EVAL" then
    sections[#sections + 1] = round_eval_section()
    sections[#sections + 1] = "REA|N:cash_out"

  elseif state_name == "TAROT_PACK" or state_name == "PLANET_PACK" or
         state_name == "SPECTRAL_PACK" or state_name == "STANDARD_PACK" or
         state_name == "BUFFOON_PACK" or state_name == "SMODS_BOOSTER_OPENED" or
         (state_name and state_name:find("_PACK$")) then
    sections[#sections + 1] = pack_section(state_name)
    if (not has_filters) or has_action(action_set, "joker_strategy") then
      sections[#sections + 1] = jokers_section(include_full_jokers)
    end
    if (not has_filters) or has_action(action_set, "consumables_info") or has_action(action_set, "use_card") then
      sections[#sections + 1] = consumables_section()
    end
    -- Tarot/spectral packs: show hand so she can give correct hand_indices for targeting
    if state_name == "TAROT_PACK" or state_name == "SPECTRAL_PACK" then
      sections[#sections + 1] = hand_section()
    end
    -- Planet pack: show hand levels so she knows which hand type to prioritise upgrading
    if state_name == "PLANET_PACK" then
      sections[#sections + 1] = levels_section()
    end
    -- Standard pack: show hand + deck composition so she can pick cards that fill gaps
    if state_name == "STANDARD_PACK" then
      sections[#sections + 1] = hand_section()
      sections[#sections + 1] = deck_cards_section()
    end

  end

  local output = {}
  for _, section in ipairs(sections) do
    if section then
      output[#output + 1] = section
    end
  end

  output = enforce_budget(state_name, output)
  local result = concat_sections(output)
  _ctx_cache = result
  _ctx_cache_state = state_name
  _ctx_cache_key = cache_key
  _ctx_cache_at = t
  return result
end

local JOKER_HAND_SYNERGY = {
  j_jolly = "pair",    j_sly = "pair",
  j_zany = "trips",    j_wily = "trips",
  j_mad = "two_pair",  j_clever = "two_pair",
  j_crazy = "straight",j_devious = "straight",
  j_droll = "flush",   j_crafty = "flush",
  j_greedy = "Diamonds", j_lusty = "Hearts",
  j_wrathful = "Spades", j_gluttonous = "Clubs",
  j_lucy = "flush",
}

local function joker_dr_synergies()
  local syn = { pair = 0, trips = 0, flush = 0, straight = 0, suits = {} }
  if not (G and G.jokers and G.jokers.cards) then return syn end
  for _, card in ipairs(G.jokers.cards) do
    local key = card.config and card.config.center and card.config.center.key
    local s = key and JOKER_HAND_SYNERGY[key]
    if s == "pair" then syn.pair = syn.pair + 3
    elseif s == "trips" then syn.trips = syn.trips + 3
    elseif s == "two_pair" then syn.pair = syn.pair + 2
    elseif s == "flush" then syn.flush = syn.flush + 3
    elseif s == "straight" then syn.straight = syn.straight + 3
    elseif s then syn.suits[s] = (syn.suits[s] or 0) + 3
    end
  end
  return syn
end

discard_heuristics_section = function()
  if not (G and G.hand and G.hand.cards and #G.hand.cards > 0) then
    return nil
  end

  local cards = G.hand.cards
  local value_counts, suit_counts = {}, {}
  local rank_present = {}

  for _, card in ipairs(cards) do
    if card.ability and card.ability.enhancement == "m_stone" then
    else
      local base = card.base or {}
      local v = base.value or "?"
      local s = base.suit or "?"
      value_counts[v] = (value_counts[v] or 0) + 1
      suit_counts[s] = (suit_counts[s] or 0) + 1
      local r = VALUE_RANK[v]
      if r then
        rank_present[r] = true
        if r == 14 then rank_present[1] = true end
      end
    end
  end

  local jsyn = joker_dr_synergies()

  local has_camila, has_milc, has_layna, has_highlighted, has_cavestream = false, false, false, false, false
  if G.jokers and G.jokers.cards then
    for _, jc in ipairs(G.jokers.cards) do
      local jn = jc.ability and jc.ability.name or ""
      if jn == "Cumilq"              then has_camila     = true end
      if jn == "Milc"                then has_milc       = true end
      if jn == "Layna"               then has_layna      = true end
      if jn == "Highlighted Message" then has_highlighted = true end
      if jn == "Cave Stream"         then has_cavestream = true end
    end
  end

  -- Detect ranks participating in 4+ card runs
  local in_run4 = {}
  local run_start, run_len = 0, 0
  for r = 1, 14 do
    if rank_present[r] then
      if run_len == 0 then run_start = r end
      run_len = run_len + 1
    else
      if run_len >= 4 then
        for rr = run_start, run_start + run_len - 1 do in_run4[rr] = true end
      end
      run_len = 0
    end
  end
  if run_len >= 4 then
    for rr = run_start, run_start + run_len - 1 do in_run4[rr] = true end
  end

  local rows = {}
  for i, card in ipairs(cards) do
    local base = card.base or {}
    local v = base.value or "?"
    local s = base.suit or "?"
    local r = VALUE_RANK[v] or 0
    local is_stone = (card.ability and card.ability.enhancement == "m_stone")

    local keep = 0
    local reasons = {}

    if card.debuff then
      keep = keep - 10
      reasons[#reasons + 1] = "debuff"
    end

    local vc = value_counts[v] or 0
    local sc = suit_counts[s] or 0
    local near_seq = 0
    local enh, raw_ef, raw_seal, seal_key, seal, ed
    local discard_priority

    if is_stone then
      keep = keep + 4
      reasons[#reasons + 1] = "stone(+50c_always)"
      if has_cavestream then keep = keep + 5; reasons[#reasons + 1] = "cavestream(stone_retrig)" end
      goto continue_heuristic
    end
    if vc >= 4 then
      keep = keep + (r >= 11 and 20 or r >= 8 and 17 or 15)
      reasons[#reasons + 1] = "quad"
    elseif vc >= 3 then
      keep = keep + (r >= 11 and 16 or r >= 8 and 13 or 11)
      reasons[#reasons + 1] = "trips"
    elseif vc >= 2 then
      keep = keep + (r >= 11 and 12 or r >= 8 and 9 or 7)
      reasons[#reasons + 1] = "pair"
    end

    if vc >= 3 and jsyn.trips > 0 then
      keep = keep + jsyn.trips
      reasons[#reasons + 1] = "jsyn"
    elseif vc >= 2 and jsyn.pair > 0 then
      keep = keep + jsyn.pair
      reasons[#reasons + 1] = "jsyn"
    end

    if sc >= 4 then
      keep = keep + 6
      reasons[#reasons + 1] = "flush"
      if jsyn.flush > 0 then
        keep = keep + jsyn.flush
        reasons[#reasons + 1] = "jsyn"
      end
    elseif sc == 3 then
      keep = keep + 2
      reasons[#reasons + 1] = "suit"
    end

    if jsyn.suits[s] and jsyn.suits[s] > 0 then
      keep = keep + jsyn.suits[s]
      reasons[#reasons + 1] = "jsyn"
    end

    if r >= 11 then
      keep = keep + 3
      reasons[#reasons + 1] = "high"
    elseif r == 10 then
      keep = keep + 2
      reasons[#reasons + 1] = "ten"
    end

    if r > 0 then
      if rank_present[r - 1] then near_seq = near_seq + 1 end
      if rank_present[r + 1] then near_seq = near_seq + 1 end
      if near_seq >= 1 then
        keep = keep + near_seq
        reasons[#reasons + 1] = "seq"
      end
    end

    if r > 0 and in_run4[r] then
      keep = keep + 4
      reasons[#reasons + 1] = "str_draw"
      if jsyn.straight > 0 then
        keep = keep + jsyn.straight
        reasons[#reasons + 1] = "jsyn"
      end
    end

    if has_camila and r == 6 then
      keep = keep + 5; reasons[#reasons + 1] = "cumilq(6=x1.3m)" end
    if has_milc and ((r == 11 and s == "Diamonds") or r == 2) then
      keep = keep + 4; reasons[#reasons + 1] = "milc" end
    if has_layna and r == 9 then
      keep = keep + 6; reasons[#reasons + 1] = "layna(9=x3m_all)" end

    ::continue_heuristic::
    enh = short_enh(card)
    raw_ef = card.ability and card.ability.enhancement or ""
    raw_seal = card.seal
    seal_key = nil
    if type(raw_seal) == "table" then
      local raw = raw_seal.key and raw_seal.key:match("seal_(%a+)") or raw_seal.name or ""
      seal_key = raw:sub(1,1):upper() .. raw:sub(2)
      seal_key = seal_key:match("^(%a+)%s+[Ss]eal$") or seal_key
    elseif raw_seal then
      seal_key = tostring(raw_seal)
    end
    seal = short_seal(card)
    ed = short_edition(card)
    if enh ~= "" or ed ~= "" then
      keep = keep + 2
      reasons[#reasons + 1] = "mod"
    end
    if raw_ef == "m_steel" then
      keep = keep + 6
      reasons[#reasons + 1] = "steel(hold=x1.5m)"
    elseif raw_ef == "m_glass" then
      keep = keep + 3
      reasons[#reasons + 1] = "glass(play=x2m)"
    end
    if raw_ef == "m_dono" and has_highlighted then
      keep = keep + 5; reasons[#reasons + 1] = "highlighted(dono=x2m)" end
    -- Seal-specific weights: Blue=hold, Red/Gold=play, Purple=discard to get tarot
    if seal_key == "Blue" then
      keep = keep + 8  -- hold in hand at round end → free planet
      reasons[#reasons + 1] = "blue_seal(hold=planet)"
    elseif seal_key == "Red" then
      keep = keep + 5  -- retriggers on score = double value
      reasons[#reasons + 1] = "red_seal(play=x2)"
    elseif seal_key == "Gold" then
      keep = keep + 4  -- +$3 when scored
      reasons[#reasons + 1] = "gold_seal(play=$)"
    elseif seal_key == "Purple" then
      keep = keep - 3  -- discarding generates a free tarot
      reasons[#reasons + 1] = "purple_seal(discard=tarot)"
    elseif seal ~= "" then
      keep = keep + 2
      reasons[#reasons + 1] = "seal"
    end

    discard_priority = 20 - keep
    rows[#rows + 1] = {
      idx = i,
      keep = keep,
      discard = discard_priority,
      why = compact_text((#reasons > 0 and table.concat(reasons, "+") or "weak"), 22),
    }
  end

  table.sort(rows, function(a, b)
    if a.discard ~= b.discard then return a.discard > b.discard end
    return a.idx < b.idx
  end)

  local dc = G.GAME and G.GAME.modifiers and G.GAME.modifiers.discard_cost
  local dh_header = "DH:i,keep,disc,why"
  if dc and dc > 0 then
    dh_header = dh_header .. "|WARN:each_discard_costs_$" .. tostring(dc)
  end
  local lines = { dh_header }
  for _, row in ipairs(rows) do
    lines[#lines + 1] = string.format("%d,%d,%d,%s", row.idx, row.keep, row.discard, row.why)
  end

  local top = {}
  for i = 1, math.min(4, #rows) do
    top[#top + 1] = tostring(rows[i].idx)
  end

  local keep_sorted = {}
  for i = 1, #rows do
    keep_sorted[#keep_sorted + 1] = rows[i]
  end
  table.sort(keep_sorted, function(a, b)
    if a.keep ~= b.keep then return a.keep > b.keep end
    return a.idx < b.idx
  end)
  local top_keep = {}
  for i = 1, math.min(3, #keep_sorted) do
    top_keep[#top_keep + 1] = tostring(keep_sorted[i].idx)
  end

  if #top > 0 then
    lines[#lines + 1] = "DR:top_discard=" .. table.concat(top, ",") .. "|top_keep=" .. table.concat(top_keep, ",")
    -- Cache for dispatcher to read explicit DR indices
    G.NEURO.dr_top = { discard = top, keep = top_keep }
  else
    G.NEURO.dr_top = nil
  end

  return table.concat(lines, "\n")
end

function ContextCompact.invalidate_cache()
  _ctx_cache = nil
  _ctx_cache_key = nil
end

function ContextCompact.decision_fingerprint(state_name, payload)
  local source = payload
  if type(source) ~= "string" or source == "" then
    local allowed_actions = nil
    local ok_actions, Actions = pcall(require, "actions")
    if ok_actions and Actions and Actions.get_valid_actions_for_state then
      local ok_list, list = pcall(Actions.get_valid_actions_for_state, state_name)
      if ok_list and type(list) == "table" then
        allowed_actions = list
      end
    end
    source = ContextCompact.build(state_name, allowed_actions)
  end

  local kept = {}
  for line in tostring(source):gmatch("[^\n]+") do
    if keep_fp_line(state_name, line) then
      kept[#kept + 1] = line
    end
  end

  if #kept == 0 then
    return tostring(source)
  end
  return table.concat(kept, "\n")
end

return ContextCompact
