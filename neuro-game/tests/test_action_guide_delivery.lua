local H = require("tests.hand_pipeline_harness")
local TD = require("tests.test_deadlock")
local Actions = require("core.actions")
local Guide = require("facts.token_legends").ACTION_SEMANTICS_V1
local Delivery = require("core.context_delivery")
local Lifecycle = require("core.neuro_lifecycle")
local check, done = require("tests.helpers").harness("action-guide-delivery")

local MOVED = { "buy_from_shop", "discard_hand", "record_joker_roles", "record_plan", "select_blind",
  "choose_pack_card", "choose_directional_pack_card", "sell_card", "play_hand", "use_consumable", "leave_shop" }

local GUIDE_RULES = {
  "A play either commits at once or opens one review that costs no hand",
  "A shop voucher is reviewed first",
  "a targeted consumable is bought with use=false",
  "the first joker sale opens a review without selling",
  "A pack pick directly uses the picked card when the card is a consumable",
  "Leaving the shop may first return a review when it would forfeit interest or your joker lineup changed",
  "Every joker needs a role tag before you leave",
}
for _, rule in ipairs(GUIDE_RULES) do
  check("the guide carries: " .. rule, Guide.text:find(rule, 1, true) ~= nil)
end

local defs = {}
for _, def in ipairs(Actions.get_static_actions()) do defs[def.name] = def.description end
for _, name in ipairs(MOVED) do
  local description = tostring(defs[name])
  local sentences = 0
  for _ in description:gmatch("[%.%!%?]%s") do sentences = sentences + 1 end
  if description:match("[%.%!%?]$") then sentences = sentences + 1 end
  check(name .. ": description keeps to a sentence or two", sentences <= 2 and #description <= 260,
    sentences .. " sentences, " .. #description .. " bytes")
end

local function first_index(pred, from)
  local frames = H.frames()
  for i = from or 1, #frames do
    if pred(frames[i]) then return i end
  end
  return nil
end
local function is_guide(f) return f.command == "context" and f.data.message == Guide.text end
local function forces_action(name)
  return function(f)
    if f.command ~= "actions/force" then return false end
    for _, n in ipairs(f.data.action_names or {}) do if n == name then return true end end
    return false
  end
end


local function shop_board()
  for _, sc in ipairs(TD.SCENARIOS) do
    if sc.state == "SHOP" and sc.desc:find("Normal: affordable joker", 1, true) then TD.apply_mock(sc.mock()) end
  end
  G.STATE = H.STATES.SHOP
end

do
  H.board()
  Delivery.reset_transport()
  H.tick(8)
  local guide, force = first_index(is_guide), first_index(forces_action("discard_hand"))
  check("SELECTING_HAND: the guide is written before the first force offering discard_hand",
    guide and force and guide < force, tostring(guide) .. " < " .. tostring(force))
  local any_force = first_index(function(f) return f.command == "actions/force" end)
  check("SELECTING_HAND: the guide is written before the first force of the session",
    guide and any_force and guide < any_force, tostring(guide) .. " < " .. tostring(any_force))

  local mark = #H.frames()
  Lifecycle.reconnect_context_delivery()
  shop_board()
  H.tick(8)
  local shop_force = first_index(forces_action("leave_shop"), mark + 1)
  check("after a reconnect the shop force is offered", shop_force ~= nil, tostring(shop_force))
  check("after a reconnect the guide is still known and not re-sent", Delivery.essential_ready()
    and first_index(is_guide, mark + 1) == nil, tostring(first_index(is_guide, mark + 1)))

  mark = #H.frames()
  Lifecycle.reset_context_delivery()
  for i = 1, 6 do G.hand.cards[i] = require("tests.helpers").play_card(i) end
  G.STATE = H.STATES.SELECTING_HAND
  H.tick(8)
  guide, force = first_index(is_guide, mark + 1), first_index(forces_action("discard_hand"), mark + 1)
  check("after a fresh startup the guide is written again before discard_hand is forced",
    guide and force and guide < force, tostring(guide) .. " < " .. tostring(force))
end

do
  H.board()
  Delivery.reset_transport()
  shop_board()
  H.tick(8)
  local guide = first_index(is_guide)
  local leave_force = first_index(forces_action("leave_shop"))
  check("SHOP: the guide with the leaving rules is written before the first force offering leave_shop",
    guide and leave_force and guide < leave_force, tostring(guide) .. " < " .. tostring(leave_force))
  local any_force = first_index(function(f) return f.command == "actions/force" end)
  check("SHOP: the guide is written before the first force of the session",
    guide and any_force and guide < any_force, tostring(guide) .. " < " .. tostring(any_force))
end

H.finish(check, done)
