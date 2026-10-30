local M = {}

local Actions = require("core.actions")
local ActionRegistry = require("core.action_registry")
local Utils = require("util.utils")
local CardUtil = require("facts.card_util")

function M.index_range(count)
  count = tonumber(count) or 0
  return count > 0 and ("1-" .. count) or "none"
end

function M.collect_actions(names)
  local list, set, accepted, seen = {}, {}, {}, {}
  for _, name in ipairs(names or {}) do
    if not seen[name] and Actions.is_action_valid(name) then
      seen[name] = true
      list[#list + 1] = name
      set[name] = true
      if not require("core.validate").settling(name) then accepted[name] = true end
    end
  end
  return list, set, accepted
end

local function repeat_pressured()
  local ok_p, name, count = pcall(require("core.validate").repeat_pressure)
  if not ok_p or not name then return nil end
  return name, count
end

function M.pending_gate_note(names)
  local Gate = require("core.gate")
  if Gate.proposal() then return "" end
  local pressured = repeat_pressured()
  local gated = {}
  for _, name in ipairs(names or {}) do
    if name ~= pressured then
      local ok_q, blocked = pcall(Gate.would_review, name)
      if ok_q and blocked then gated[#gated + 1] = name end
    end
  end
  if #gated == 0 then return "" end
  local moves = {}
  for i, name in ipairs(gated) do
    moves[i] = require("core.action_registry").phrase(name):gsub("^%u", string.lower)
  end
  return string.format(
    "The first time you %s, it returns a review: nothing is executed and the decision comes back for a second look. After it, the next such move is final, with the same or different parameters. ",
    table.concat(moves, " or "))
end

function M.repeat_pressure_note(offered)
  local name, count = repeat_pressured()
  if not name then return "" end
  local on_offer = false
  for _, n in ipairs(offered or {}) do if n == name then on_offer = true break end end
  local times = require("facts.text").plural(count, "time")
  if not on_offer then
    return string.format("Your last action was sent with the same parameters %s in a row; another identical send "
      .. "is refused and changes nothing. ", times)
  end
  local rule = require("core.validate").repeat_rule(name)
  return string.format(
    "You have made the same move (%s) with the same parameters %s in a row; another identical send is refused and changes nothing%s. ",
    (require("core.action_registry").phrase(name):gsub("^%u", string.lower)), times, rule and (" -- " .. rule) or "")
end

function M.menu_action_tree_query(offered)
  offered = offered or {}
  local parts = { "open run setup, where the run is started" }
  if offered.select_deck then parts[#parts + 1] = "select a deck to switch the deck" end
  if offered.select_stake then parts[#parts + 1] = "select a stake to switch the stake" end
  if Actions.is_action_valid("copy_seed") then
    parts[#parts + 1] = "copy the current seed"
  end
  if offered.select_challenge then
    parts[#parts + 1] = "select a challenge, then start the challenge run (only when challenges are listed)"
  end
  return "From the main menu: " .. table.concat(parts, "; ") .. "."
end

function M.hiyori_persona_gate()
  if G and G.NEURO and G.NEURO.persona == "hiyori" then
    return {
      query = "Identity not selected. Choose a persona: persona 'neuro' for Neuro-sama or 'evil' for Evil Neuro.",
      actions = { "choose_persona" }
    }
  end
  return nil
end

function M.public_cards(area)
  local out = {}
  for index, card in ipairs((area and area.cards) or {}) do
    if not CardUtil.is_hidden(card) then out[#out + 1] = { index = index, card = card } end
  end
  return out
end

function M.any_public(area, pred)
  for _, entry in ipairs(M.public_cards(area)) do
    if pred(entry.card) then return true end
  end
  return false
end

function M.joker_full_warn(js, negative_ok)
  local tail = negative_ok and "Negative edition jokers bypass this limit. "
    or "Non-Negative jokers require an open joker slot. Selling frees one immediately, but is permanent. "
  return string.format("Joker slots FULL (%d/%d). ", js.count, js.limit) .. tail
end
function M.force_priority()
  return "low"
end

local function hand_count_phrase(lo, hi, noun)
  if lo == hi then
    return (lo == 1) and ("1 " .. noun) or ("exactly " .. lo .. " " .. noun .. "s")
  end
  return lo .. "-" .. hi .. " " .. noun .. "s"
end

function M.target_fields(name, lo, hi)
  local contract = require("core.action_registry").display(name)
  local props = (contract and contract.schema and contract.schema.properties) or {}
  if props.left_index and props.right_index then
    return "left_index (the hand card it applies to) and right_index (the card it takes from), two different hand positions"
  end
  local spec = props.hand_indices
  if type(spec) ~= "table" then return nil end
  local count = lo and hi and hand_count_phrase(lo, hi, "hand position")
    or "as many hand positions as that card targets"
  return "hand_indices (" .. count .. ")"
end

function M.payload_target_range(payload)
  if type(payload) ~= "table" then return nil end
  local area = require("facts.card_area_util").get_area(payload.area)
  local card = area and area.cards and area.cards[tonumber(payload.index)]
  if not card or CardUtil.is_hidden(card) then return nil end
  local lo, hi = CardUtil.consumable_target_range(card)
  if not (hi and hi > 0) then return nil end
  lo = lo or 1
  local held = (G and G.hand and G.hand.cards) and #G.hand.cards or 0
  if held >= lo and held < hi then hi = held end
  return lo, hi
end

function M.render_candidate(name, payload)
  local rendered = require("core.action_registry").render(name, payload)
  if not rendered or payload.hand_indices ~= nil then return rendered end
  local lo, hi = M.payload_target_range(payload)
  local fields = lo and M.target_fields(name, lo, hi)
  return fields and (rendered .. ", " .. fields) or rendered
end

function M.consumable_tools(bits, can, prepare)
  if can.use_consumable then bits.use_consumable = M.candidate_list("use_consumable", prepare) end
  if can.use_directional_consumable then
    bits.use_directional_consumable = ActionRegistry.prompt("use_directional_consumable")
  end
end

function M.candidate_list(name, prepare)
  local out = {}
  for _, payload in ipairs(require("core.action_registry").candidates(name)) do
    out[#out + 1] = M.render_candidate(name, prepare and prepare(name, payload) or payload)
  end
  return table.concat(out, " or ")
end

function M.push_move(bits, text)
  if text ~= "" then bits[#bits + 1] = text end
end

function M.is_win_overlay()
  local om = G and G.OVERLAY_MENU
  return require("facts.game_facts").run_progress().won and type(om) == "table" and type(om.get_UIE_by_ID) == "function"
    and om:get_UIE_by_ID("you_win_UI") ~= nil
end

local GUARDED_CONFIRMATIONS = {
  { action = "sell_card", live = function() return require("handlers.shop_handlers").pending_sell_card_name() end,
    sentence = "FINAL SELL CHOICE -- the sell review began with %s; the next legal sale now commits immediately, including a different joker. " },
  { action = "buy_from_shop", live = function() return require("core.gate").reviewed_target("buy_voucher") end,
    sentence = "FINAL VOUCHER CHOICE -- the voucher review began with %s; the next legal voucher buy now commits immediately, including a different voucher. " },
}

function M.pending_confirmation_note(offered)
  local parts = {}
  for _, entry in ipairs(GUARDED_CONFIRMATIONS) do
    if offered[entry.action] then
      local ok, name = pcall(entry.live)
      if ok and type(name) == "string" and name ~= "" then
        parts[#parts + 1] = string.format(entry.sentence, name)
      end
    end
  end
  return table.concat(parts)
end

local function leave_marker() return "Leave review done: leaving the shop again now leaves it." end

M.REVIEW_MARKERS = {
  interest_engine_off = leave_marker,
  order_think = leave_marker,
  sell_joker = function(target)
    return "Sell review open (began with " .. tostring(target or "a card")
      .. "): the next legal sale is final, even for a different card."
  end,
  buy_voucher = function(target)
    return "Voucher review open (began with " .. tostring(target or "a voucher")
      .. "): the next legal voucher buy is final, even for a different voucher."
  end,
}

function M.review_markers(offered)
  local Gate = require("core.gate")
  local set = {}
  for _, name in ipairs(offered or {}) do set[name] = true end
  local lines, said = {}, {}
  for _, def in ipairs(Gate.DEFINITIONS) do
    local names = {}
    for _, name in ipairs(offered or {}) do
      if def.actions[name] then names[#names + 1] = name end
    end
    local render = M.REVIEW_MARKERS[def.id]
    local ok, open = pcall(Gate.reviewed, def.id)
    if render and #names > 0 and ok and open then
      local line = render(Gate.reviewed_target(def.id), names)
      if not said[line] then said[line], lines[#lines + 1] = true, line end
    end
  end
  if set.play_hand and not Gate.proposal() then
    local ok, final = pcall(Gate.final_play_required)
    if ok and final then
      lines[#lines + 1] = "Play review spent: the next play commits immediately, without another review."
    end
  end
  return table.concat(lines, "\n")
end

-- Fail open so a hint for the shop’s only exit is not silently withdrawn.
function M.untagged_joker_count(where)
  local ok, untagged = pcall(function()
    return require("facts.card_util").untagged_joker_count()
  end)
  if ok then return tonumber(untagged) or 0 end
  require("util.metrics").incr("force_tag_count_error")
  print("[neuro-game] Could not count untagged jokers " .. where .. ": " .. tostring(untagged))
  return nil
end

function M.joker_order_move()
  local ok, gap = pcall(require("util.scoring").joker_order_gap)
  if not (ok and gap) then return nil end
  local group = gap.groups[1]
  local first = group.behind[1]
  local name = require("context.ctx_helpers").normalize_text
  return require("core.action_registry").render("set_joker_order",
      { from_index = first.index, to_index = group.pivot.index })
    .. " moves " .. name(Utils.safe_name_or(first.card)) .. " to slot " .. group.pivot.index
    .. " and collects the joker-order gain stated with your jokers"
end

function M.plan_placeholders(state_name, action_name, fields)
  local required = require("core.gate").action_requirements(state_name, action_name).plan
  if not next(required) then return nil end
  local plan = {}
  for _, field in ipairs(fields) do
    if required[field] then plan[field .. "_plan"] = "..." end
  end
  return plan
end

function M.paragraph(text)
  if type(text) ~= "string" or not text:find("%S") then return "" end
  return "\n\n" .. text .. "\n\n"
end

M.TOOLS_LEAD = "Tools offered too (the decision stays open)"

function M.tools_section(names, bits)
  if type(names) ~= "table" or #names == 0 then return "" end
  local lines = {}
  local settling = require("core.validate").settling
  for _, name in ipairs(names) do
    local text = type(bits) == "table" and bits[name] or nil
    if type(text) ~= "string" or text == "" then text = ActionRegistry.prompt(name) end
    local wait = settling(name) and " -- still settling on screen, so wait a moment first" or ""
    lines[#lines + 1] = (text:gsub(" or (%u)", "\nor %1")) .. wait
  end
  return M.TOOLS_LEAD .. ":\n" .. table.concat(lines, ";\n") .. "."
end

function M.with_tools(query, tools_text)
  if type(tools_text) ~= "string" or tools_text == "" then return query end
  local at = query:find("\n\nYour move:", 1, true)
  if at then return query:sub(1, at - 1) .. "\n\n" .. tools_text .. query:sub(at) end
  return query .. "\n\n" .. tools_text
end

function M.finish(query, fields, keep_lead)
  query = query:gsub("  +", " ")
  fields.query = keep_lead and query or (query:gsub("^%s+", ""))
  return fields
end

function M.your_move(bits)
  if #bits == 0 then return "" end
  local lines = {}
  for i, bit in ipairs(bits) do lines[i] = (bit:gsub(" or (%u)", "\nor %1")) end
  return "\n\nYour move:\n" .. table.concat(lines, ";\n") .. "."
end

return M
