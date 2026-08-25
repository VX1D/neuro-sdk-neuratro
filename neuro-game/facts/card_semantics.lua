local M = {}

local NUMERIC_EFFECTS = require("facts.numeric_effects")
local Utils = require("util.utils")
local DynamicJokers = require("facts.dynamic_jokers")

local CONDITIONAL_WORDS = {
  " if ", " when ", " whenever ", " played ", " scored ", " held in hand",
  " contains ", " for each ", " per ", " remaining", " every ", " after ",
  " before ", " first ", " final ", " suit", " rank", "10s", "4s",
}

local UI_HINT_VERBS = {}
for verb in ("[dD]rag|[Cc]lick|[Pp]ress|[Hh]over|[Mm]ouse|[Tt]ap|[Ss]croll"):gmatch("[^|]+") do
  UI_HINT_VERBS[#UI_HINT_VERBS + 1] = verb
end
local function strip_ui_hints(text)
  return (text:gsub("(%s*)%(([^()]*)%)", function(space, inner)
    for _, verb in ipairs(UI_HINT_VERBS) do
      if inner:find(verb) then return "" end
    end
    return space .. "(" .. inner .. ")"
  end))
end

local function normalize(text)
  text = tostring(text or ""):gsub("%c", " ")
  text = strip_ui_hints(text)
  return (text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function raw_description(card)
  local ok, text = pcall(Utils.card_description_with_fallback, card)
  if ok then
    text = normalize(text)
    if text ~= "" and not text:find("^No detailed description available") then return text end
  end
  local center = card and card.config and card.config.center
  local loc = center and center.loc_txt and center.loc_txt.description
  if type(loc) == "table" then return normalize(table.concat(loc, " ")) end
  if type(loc) == "string" then return normalize(loc) end
  return ""
end

local function description_is_conditional(description)
  local padded = " " .. tostring(description or ""):lower() .. " "
  for _, word in ipairs(CONDITIONAL_WORDS) do
    if padded:find(word, 1, true) then return true end
  end
  return false
end

local function gate_text(gate)
  return NUMERIC_EFFECTS.gate_text_of(gate, "prose", gate and gate.kind)
end

local EMPTY = {}

local function hand_type_order(r)
  if type(r) ~= "table" or type(r.per_type) ~= "table" then return EMPTY end
  if type(r.order) == "table" then return r.order end
  local names = {}
  for name in pairs(r.per_type) do names[#names + 1] = name end
  table.sort(names)
  return names
end

local SCOPES = { hand = true, scoring_card = true, held_card = true, other_joker = true, retrigger = true }

local function add_row(out, row)
  if not SCOPES[row.scope] then
    error("effect row without a scope: " .. tostring(row.kind) .. "/" .. tostring(row.source))
  end
  local rate = tonumber(row.rate)
  if not rate then return nil end
  if (row.kind == "xmult" or row.kind == "xchips") and (rate <= 0 or rate == 1) then return nil end
  if row.kind ~= "xmult" and row.kind ~= "xchips" and rate == 0 then return nil end
  row.rate = rate
  row.value = rate
  row.certainty = row.gate and "conditional" or "guaranteed"
  row.condition = row.gate and gate_text(row.gate) or nil
  row.hand_type = (row.gate and row.gate.kind == "hand_type") and row.gate.value or nil
  row.per_card = row.scope == "scoring_card" or nil
  out[#out + 1] = row
  return row
end

local KIND_BY_FIELD = {
  x_mult = "xmult", mult = "mult",
  h_mult = "mult", h_chips = "chips", h_x_mult = "xmult",
  t_mult = "mult", t_chips = "chips",
  s_mult = "mult", x_chips = "xchips",
}

local DERIVABLE = {
  x_mult  = { scope = "hand", ref = 4027 },
  x_chips = { scope = "hand", ref = 4027 },
  t_mult  = { scope = "hand", ref = 4034 },
  t_chips = { scope = "hand", ref = 4040 },
  s_mult  = { scope = "scoring_card", ref = 3596 },
}

local function generic_row(spec, ability, description, registered)
  local rule = DERIVABLE[spec.field]
  local scope = (spec.field == "h_mult" or spec.field == "h_chips" or spec.field == "h_x_mult")
    and "held_card" or (rule and rule.scope or "hand")
  local gate, match
  local declared = NUMERIC_EFFECTS.gate(ability, spec)
  if declared and declared.kind == "card_suit" then
    match = "suit:" .. tostring(declared.value)
    gate = { kind = "card_match", match = match, suit = declared.value,
      text = "played " .. tostring(declared.value or "matching") .. " cards" }
  elseif declared and declared.value then
    gate = { kind = "hand_type", value = declared.value }
  elseif declared then
    gate = { kind = "board_state", id = "unnamed_hand_type", text = "an unnamed hand type" }
  elseif scope == "held_card" then
    gate = { kind = "board_state", id = "held_card", text = "the cards you hold in hand" }
  end
  if not gate and not registered and description_is_conditional(description) then
    gate = { kind = "unmodelled", text = description ~= "" and description or "its own rule" }
    return { scope = scope, gate = gate, ref = rule and rule.ref, match = match, guessed = true }
  end
  return { scope = scope, gate = gate, ref = rule and rule.ref, match = match, guessed = not rule }
end

local EDITION_FIELDS = { { "chips", "chips" }, { "mult", "mult" }, { "xmult", "x_mult" } }

local function copy_target(card, kind)
  local cards = G and G.jokers and G.jokers.cards
  if type(cards) ~= "table" then return nil, false end
  local target
  if kind == "brainstorm" then
    target = cards[1]
  else
    for i = 1, #cards do if cards[i] == card then target = cards[i + 1] end end
  end
  if type(target) ~= "table" or target == card or target.debuff then return nil, false end
  if not require("facts.public_card_identity").is_public(target) then return nil, true end
  local center = target.config and target.config.center
  if not (type(center) == "table" and center.blueprint_compat) then return nil, false end
  return target, false
end

local function project(card, board, seen)
  local ability = card and card.ability or {}
  local center = card and card.config and card.config.center
  local key = center and center.key
  local description = raw_description(card)
  local effects, refusals = {}, {}
  local registry_rows = key and DynamicJokers.ROWS[key] or nil
  local claimed
  if registry_rows then
    claimed = {}
    for _, row in ipairs(registry_rows) do
      if type(row.from) == "string" then claimed[row.from] = true end
    end
  end

  for _, spec in ipairs(NUMERIC_EFFECTS) do
    if not (claimed and claimed[spec.field]) then
      local value = NUMERIC_EFFECTS.read(ability, spec)
      if value ~= nil and value ~= spec.skip then
        local g = generic_row(spec, ability, description, registry_rows ~= nil)
        add_row(effects, { kind = KIND_BY_FIELD[spec.field], scope = g.scope, rate = value,
          gate = g.gate, ref = g.ref, match = g.match, guessed = g.guessed, source = spec.field })
      end
    end
  end

  if ability.bonus and (ability.set == "Joker" or (center and center.set == "Joker")) then
    add_row(effects, { kind = "chips", scope = "hand", rate = ability.bonus, source = "bonus" })
  end

  for _, row in ipairs(registry_rows or EMPTY) do
    if row.per_hand_type then
      local r = DynamicJokers.per_hand_type(key)
      for _, handtype in ipairs(hand_type_order(r)) do
        local v = r.per_type[handtype]
        local e = add_row(effects, { kind = r.kind, scope = row.scope, rate = v, ref = row.ref,
          gate = { kind = "hand_type", value = handtype }, source = "registry" })
        if e then e.accumulator = true end
      end
    else
      local rate = DynamicJokers.read_from(card, row.from, board)
      if rate == nil then
        refusals[#refusals + 1] = { key = key, reason = gate_text(row.gate) or "state this joker does not expose" }
      else
        add_row(effects, { kind = row.kind, scope = row.scope, rate = rate, gate = row.gate,
          ref = row.ref, match = row.match, at_most_once = row.at_most_once,
          ceiling = row.ceiling_from and DynamicJokers.read_from(card, row.ceiling_from, board) or nil,
          source = "registry" })
      end
    end
  end

  local copy_kind = require("facts.card_util").copy_joker_kind(card)
  if copy_kind then
    seen = seen or {}
    seen[card] = true
    local target, unidentifiable = copy_target(card, copy_kind)
    if unidentifiable then
      refusals[#refusals + 1] = { key = key, reason = "a joker the blind turned face down" }
    elseif target and not seen[target] then
      local copied = project(target, board, seen)
      for _, e in ipairs(copied.effects) do
        if e.source ~= "edition" then
          e.copy_src = target
          effects[#effects + 1] = e
        end
      end
      for _, r in ipairs(copied.refusals) do
        refusals[#refusals + 1] = { key = key, modded = r.modded, reason = r.reason }
      end
    end
  end

  if not registry_rows and not copy_kind then
    local extra = ability.extra
    local xmult = (type(extra) == "table")
      and (tonumber(extra.Xmult) or tonumber(extra.x_mult) or tonumber(extra.xmult)) or nil
    if xmult then
      local gate
      if type(ability.type) == "string" and ability.type ~= "" then
        gate = { kind = "hand_type", value = ability.type }
      elseif description == "" or description_is_conditional(description) then
        gate = { kind = "unmodelled", text = description ~= "" and description or "its own rule" }
      end
      add_row(effects, { kind = "xmult", scope = "hand", rate = xmult, guessed = true,
        gate = gate, source = "extra.xmult" })
    end
    if type(center) == "table" and type(center.calculate) == "function" then
      refusals[#refusals + 1] = { key = key, modded = true, reason = "a modded joker's own code" }
    end
  end

  local edition = card and card.edition
  if type(edition) == "table" then
    local elabel = require("facts.card_util").edition_name(edition)
    for _, f in ipairs(EDITION_FIELDS) do
      add_row(effects, { kind = f[1], scope = "hand", rate = edition[f[2]], source = "edition", source_label = elabel })
    end
    if edition.polychrome and not edition.x_mult then
      add_row(effects, { kind = "xmult", scope = "hand", rate = 1.5, source = "edition", source_label = elabel })
    end
  end

  return { key = key, description = description, effects = effects, refusals = refusals }
end

function M.project(card, board) return project(card, board, nil) end

function M.description(card)
  return normalize(raw_description(card))
end

function M.full_description(card)
  local base = raw_description(card)
  if require("facts.card_util").copy_joker_kind(card) then
    local info = require("util.utils").card_info_text(card)
    if info and info ~= "" then
      base = (base ~= "" and (base .. " · Copying: " .. info)) or ("Copying: " .. info)
    end
  end
  return normalize(base)
end

local function effect_text(effect)
  local prefix = (effect.kind == "xmult" or effect.kind == "xchips") and "x" or "+"
  local unit = ({ xmult = " Mult", mult = " Mult", chips = " Chips", xchips = " Chips" })[effect.kind] or ""
  local text = prefix .. tostring(effect.value) .. unit
  if effect.certainty == "conditional" then text = text .. " (conditional)" end
  if effect.source == "edition" and effect.source_label and effect.source_label ~= "" then
    text = effect.source_label .. ": " .. text
  end
  return text
end

function M.summary(card, opts)
  opts = opts or {}
  local description = raw_description(card)
  if description ~= "" then
    local text = description
    if not opts.edition_in_flags then
      local edition = require("facts.card_util").edition_tag(card and card.edition)
      if edition ~= "" then text = text .. " · " .. edition end
    end
    return normalize(text)
  end
  local parts = {}
  for _, effect in ipairs(M.project(card).effects) do
    if not (opts.edition_in_flags and effect.source == "edition") then
      parts[#parts + 1] = effect_text(effect)
    end
  end
  if #parts == 0 then return "-" end
  return normalize(table.concat(parts, "; "))
end

function M.aggregate(cards, board)
  local result = {
    guaranteed = { chips = 0, mult = 0, xmult = 1, xchips = 1 },
    conditional = {},
    rows = {},
    refusals = {},
  }
  for _, card in ipairs(cards or EMPTY) do
    if not card.debuff then
      local projection = M.project(card, board)
      for _, r in ipairs(projection.refusals) do
        r.card = card
        result.refusals[#result.refusals + 1] = r
      end
      for _, effect in ipairs(projection.effects) do
        effect.joker_src = card
        result.rows[#result.rows + 1] = effect
        if effect.certainty == "guaranteed" and effect.scope == "hand" then
          if effect.kind == "xmult" or effect.kind == "xchips" then
            result.guaranteed[effect.kind] = result.guaranteed[effect.kind] * effect.value
          else
            result.guaranteed[effect.kind] = result.guaranteed[effect.kind] + effect.value
          end
        else
          result.conditional[#result.conditional + 1] = effect
        end
      end
    end
  end
  return result
end

function M.is_conditional(card)
  local projection = M.project(card)
  for _, e in ipairs(projection.effects) do
    if e.certainty == "conditional" then return true end
  end
  return description_is_conditional(projection.description)
end

function M.has_guaranteed_xmult(cards)
  return M.aggregate(cards).guaranteed.xmult > 1
end

function M.produces_flat_mult(card)
  for _, e in ipairs(M.project(card).effects) do
    if e.kind == "mult" and e.certainty == "guaranteed" and e.scope == "hand" and e.source ~= "edition" then return true end
  end
  return false
end

function M.produces_xmult(card)
  local key = card and card.config and card.config.center and card.config.center.key
  if key and DynamicJokers.declares(key, "xmult") then return true end
  for _, e in ipairs(M.project(card).effects) do
    if e.kind == "xmult" or e.kind == "xchips" then return true end
  end
  return false
end

return M
