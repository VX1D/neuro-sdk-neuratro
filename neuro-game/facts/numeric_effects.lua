local M = {
  { field = "x_mult",   skip = 1, op = "x", unit = " Mult",  gate = "hand_type", gate_optional = true },
  { field = "mult",     skip = 0, op = "+", unit = " Mult" },
  { field = "h_mult",   skip = 0, op = "+", unit = " Mult",  where = "held in hand" },
  { field = "h_chips",  skip = 0, op = "+", unit = " Chips", where = "held in hand" },
  { field = "h_x_mult", skip = 0, op = "x", unit = " Mult",  where = "held in hand" },
  { field = "t_mult",   skip = 0, op = "+", unit = " Mult",  gate = "hand_type" },
  { field = "t_chips",  skip = 0, op = "+", unit = " Chips", gate = "hand_type" },
  { field = "s_mult",   skip = 0, op = "+", unit = " Mult",  gate = "suit", nest = "extra" },
  { field = "x_chips",  skip = 1, op = "x", unit = " Chips", gate = "hand_type", gate_optional = true },
}

local function extra_reps(card)
  local n = tonumber(card and card.ability and card.ability.extra)
  return (n and n > 0) and n or 0
end

local function one() return 1 end

local function is_face(card)
  local ok, face = pcall(function() return card:is_face() end)
  return (ok and face) and true or false
end

local function low_rank(card)
  local ok, id = pcall(function() return card:get_id() end)
  return ok and (id == 2 or id == 3 or id == 4 or id == 5) or false
end

local function last_hand()
  local r = G and G.GAME and G.GAME.current_round
  return (tonumber(r and r.hands_left) or 0) <= 1
end

M.RETRIGGER = {
  j_sock_and_buskin = { scope = "played", subject = "face",       reps = extra_reps, match = is_face },   -- 3727
  j_hanging_chad    = { scope = "played", subject = "first",      reps = extra_reps, first_only = true }, -- 3735
  j_dusk            = { scope = "played", subject = "every",      reps = extra_reps,
    gate = { active = last_hand, text = "only on the last hand of the round" } },                         -- 3743
  j_selzer          = { scope = "played", subject = "every",      reps = one },                           -- 3749
  j_hack            = { scope = "played", subject = "low_rank",   reps = extra_reps, match = low_rank },  -- 3756
  j_mime            = { scope = "held",   subject = "held_score", reps = extra_reps },                    -- 3769
}

function M.read(ability, spec)
  if type(ability) ~= "table" then return nil end
  local src = ability
  if spec.nest then
    src = ability[spec.nest]
    if type(src) ~= "table" then return nil end
  end
  return src[spec.field]
end

local GATE_READERS = {
  hand_type = function(ability)
    local t = ability.type
    return (type(t) == "string" and t ~= "") and { kind = "hand_type", value = t } or nil
  end,
  suit = function(ability)
    local extra = ability.extra
    local suit = type(extra) == "table" and extra.suit or nil
    return { kind = "card_suit", value = (type(suit) == "string" and suit ~= "") and suit or nil }
  end,
}

function M.gate(ability, spec)
  if not spec.gate or type(ability) ~= "table" then return nil end
  if type(spec.gate) == "table" then return spec.gate end
  local gate = GATE_READERS[spec.gate](ability)
  if not gate and not spec.gate_optional then return { kind = spec.gate } end
  return gate
end

local GATE_PHRASES = {
  hand_type = function(value) return "only if hand has " .. value end,
  card_suit = function(value) return "only on scored " .. value end,
}

local GATE_PROSE = {
  hand_type = function(value) return "a played hand containing a " .. value end,
}

function M.gate_phrase(kind, value, register)
  if value == nil then return nil end
  local table_for = (register == "prose") and GATE_PROSE or GATE_PHRASES
  local phrase = table_for[kind]
  return phrase and phrase(value) or nil
end

function M.gate_text_of(gate, register, fallback)
  if not gate then return nil end
  if gate.text then return gate.text end
  local phrase = M.gate_phrase(gate.kind, gate.value ~= nil and tostring(gate.value) or nil, register)
  return phrase or fallback
end

function M.gate_text(ability, spec)
  return M.gate_text_of(M.gate(ability, spec), nil, "conditional")
end

function M.label(ability, spec)
  local v = M.read(ability, spec)
  if not v or v == spec.skip then return nil end
  local num = tonumber(v)
  local op = (spec.op == "+" and num and num < 0) and "" or spec.op
  local text = op .. tostring(v) .. spec.unit
  if spec.where then text = text .. " (" .. spec.where .. ")" end
  local gate = M.gate_text(ability, spec)
  return gate and (text .. " (" .. gate .. ")") or text
end

return M
