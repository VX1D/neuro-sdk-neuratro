local M = {}

local CLAIM_CHANNEL = {
  rule = "context",
  state = "query",
}

local CADENCE_FOR = {
  query = { always = true, round = true },
  context = { round = true, run = true, session = true },
}

local ENTRIES = {
  { tag = "voucher_chain:", prefix = true, claim = "rule", cadence = "session", owner = "facts/fact_hints.lua" },
  { tag = "voucher_basics_run", claim = "rule", cadence = "session", owner = "facts/fact_hints.lua" },
  { tag = "hand_base_values:", prefix = true, claim = "rule", cadence = "session", owner = "context/ctx_hand.lua" },

  { tag = "sh_rules_core", claim = "state", cadence = "round", owner = "force/force_selecting_hand.lua" },
  { tag = "sh_rules_brief", claim = "state", cadence = "always", owner = "force/force_selecting_hand.lua" },
  { tag = "sh_rules_boss", claim = "state", cadence = "always", owner = "force/force_selecting_hand.lua" },

  { tag = "scaling_curve:", prefix = true, claim = "state", cadence = "always", owner = "force/force_shop.lua" },
  { tag = "jokerless_priority", claim = "state", cadence = "always", owner = "force/force_shop.lua" },
  { tag = "scaling_gap", claim = "state", cadence = "always", owner = "force/force_shop.lua" },
  { tag = "spend_posture", claim = "state", cadence = "always", owner = "force/force_shop.lua" },
  { tag = "build_mgmt", claim = "state", cadence = "always", owner = "force/force_shop.lua" },
  { tag = "unleveled_hands", claim = "state", cadence = "always", owner = "force/force_shop.lua" },
  { tag = "level_played_type", claim = "state", cadence = "always", owner = "force/force_selecting_hand.lua" },
  { tag = "below_interest_step", claim = "state", cadence = "always", owner = "force/force_shop.lua" },
  { tag = "blind_select_advice", claim = "state", cadence = "always", owner = "force/force_blind_select.lua" },
  { tag = "shop_boss_primer", claim = "state", cadence = "always", owner = "force/force_shop.lua" },
  { tag = "consumable_slots", claim = "state", cadence = "always", owner = "force/force_selecting_hand.lua" },
  { tag = "pack_cons", claim = "state", cadence = "always", owner = "force/force_pack.lua" },
  { tag = "pack_std", claim = "state", cadence = "always", owner = "force/force_pack.lua" },
  { tag = "pack_blocked_cons", claim = "state", cadence = "always", owner = "force/force_pack.lua" },
  { tag = "pack_sell_then_take", claim = "state", cadence = "always", owner = "force/force_pack.lua" },
  { tag = "pack_pick_fit", claim = "state", cadence = "always", owner = "force/force_pack.lua" },
  { tag = "pack_planet", claim = "state", cadence = "always", owner = "force/force_pack.lua" },
  { tag = "pack_take", claim = "state", cadence = "always", owner = "force/force_pack.lua" },
  { tag = "pack_scaling", claim = "state", cadence = "always", owner = "force/force_pack.lua" },

  { tag = "bp_chain:", prefix = true, claim = "state", cadence = "always", owner = "facts/fact_hints.lua" },
  { tag = "shop_edition:", prefix = true, claim = "state", cadence = "always", owner = "facts/fact_hints.lua" },
  { tag = "joker_order_gap:", prefix = true, claim = "state", cadence = "always", owner = "context/ctx_jokers.lua" },
}

local by_tag, prefixes = {}, {}
for _, e in ipairs(ENTRIES) do
  if e.prefix then prefixes[#prefixes + 1] = e else by_tag[e.tag] = e end
end
table.sort(prefixes, function(a, b) return #a.tag > #b.tag end)

function M.lookup(tag)
  tag = tostring(tag or "")
  local exact = by_tag[tag]
  if exact then return exact end
  for _, e in ipairs(prefixes) do
    if tag:sub(1, #e.tag) == e.tag then return e end
  end
  return nil
end

function M.channel_of(entry)
  return entry and CLAIM_CHANNEL[entry.claim] or nil
end

function M.entries() return ENTRIES end

function M.validate()
  local faults = {}
  local seen = {}
  for _, e in ipairs(ENTRIES) do
    local tag = tostring(e.tag or "")
    if tag == "" then
      faults[#faults + 1] = "entry with no tag"
    elseif seen[tag] then
      faults[#faults + 1] = "duplicate tag: " .. tag
    end
    seen[tag] = true

    local channel = CLAIM_CHANNEL[e.claim]
    if not channel then
      faults[#faults + 1] = tag .. ": unknown claim " .. tostring(e.claim)
    elseif not (CADENCE_FOR[channel] or {})[e.cadence] then
      faults[#faults + 1] = string.format("%s: claim %s routes to %s, which cannot carry cadence %s",
        tag, tostring(e.claim), channel, tostring(e.cadence))
    end

  end
  for _, e in ipairs(ENTRIES) do
    if not e.prefix then
      for _, other in ipairs(ENTRIES) do
        if other ~= e and not other.prefix and #other.tag > #e.tag
            and other.tag:sub(1, #e.tag) == e.tag then
          faults[#faults + 1] = string.format(
            "%s is a prefix of %s but is not declared prefix = true", e.tag, other.tag)
        end
      end
    end
  end
  return faults
end

return M
