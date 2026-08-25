require("tests.raster_capture")
local check, done = require("tests.helpers").harness("hand type order")

local DynamicJokers = require("facts.dynamic_jokers")
local CardSemantics = require("facts.card_semantics")

local HANDS = {
  ["Flush Five"]     = { visible = false, order = 1,  played = 9 },
  ["Flush House"]    = { visible = false, order = 2,  played = 9 },
  ["Five of a Kind"] = { visible = false, order = 3,  played = 9 },
  ["Straight Flush"] = { visible = true,  order = 4,  played = 2 },
  ["Four of a Kind"] = { visible = true,  order = 5,  played = 1 },
  ["Full House"]     = { visible = true,  order = 6,  played = 0 },
  ["Flush"]          = { visible = true,  order = 7,  played = 3 },
  ["Straight"]       = { visible = true,  order = 8,  played = 0 },
  ["Three of a Kind"]= { visible = true,  order = 9,  played = 1 },
  ["Two Pair"]       = { visible = true,  order = 10, played = 4 },
  ["Pair"]           = { visible = true,  order = 11, played = 7 },
  ["High Card"]      = { visible = true,  order = 12, played = 2 },
}
local EXPECTED = { "Straight Flush", "Four of a Kind", "Full House", "Flush", "Straight",
  "Three of a Kind", "Two Pair", "Pair", "High Card" }

G.GAME = G.GAME or {}
G.GAME.hands = HANDS

local r = DynamicJokers.per_hand_type("j_supernova")
check("per_hand_type publishes an explicit order", type(r) == "table" and type(r.order) == "table")
check("the order is the engine's hand order, strongest first",
  table.concat(r.order or {}, "|") == table.concat(EXPECTED, "|"),
  table.concat(r.order or {}, "|"))
check("the secret hands stay out of the order",
  not table.concat(r.order or {}, "|"):find("Flush Five", 1, true))
check("every ordered name still resolves to its rate",
  (function()
    for _, name in ipairs(r.order or {}) do
      if r.per_type[name] ~= (HANDS[name].played + 1) then return false end
    end
    return true
  end)())

local card = { config = { center = { key = "j_supernova", set = "Joker", config = {} } },
  ability = { set = "Joker", name = "Supernova", extra = {} } }
local summary = CardSemantics.summary(card)
local seen = {}
for _, e in ipairs((summary and summary.effects) or {}) do
  local g = e.gate
  if type(g) == "table" and g.kind == "hand_type" then seen[#seen + 1] = g.value end
end
check("the emitted effect rows follow the engine order",
  #seen == 0 or table.concat(seen, "|") == table.concat(EXPECTED, "|"),
  table.concat(seen, "|"))

do
  local probe = [[package.path="./?.lua;;"..package.path
_G.NEURO_TEST = true
_G.G = { GAME = { hands = {
  ["Straight Flush"]={visible=true,order=4,played=2}, ["Four of a Kind"]={visible=true,order=5,played=1},
  ["Full House"]={visible=true,order=6,played=0}, ["Flush"]={visible=true,order=7,played=3},
  ["Straight"]={visible=true,order=8,played=0}, ["Three of a Kind"]={visible=true,order=9,played=1},
  ["Two Pair"]={visible=true,order=10,played=4}, ["Pair"]={visible=true,order=11,played=7},
  ["High Card"]={visible=true,order=12,played=2} } } }
io.write(table.concat(require("facts.dynamic_jokers").per_hand_type("j_supernova").order, "|"))]]
  local TmpWork = require("tests.tmp_workdir")
  local probe_dir = TmpWork.open("hand_order_probe")
  local probe_path = probe_dir .. "/probe.lua"
  local f = io.open(probe_path, "w")
  if f then
    f:write(probe); f:close()
    local outputs, runs = {}, 6
    for _ = 1, runs do
      local h = io.popen("luajit '" .. probe_path .. "' 2>/dev/null")
      if h then
        local out = h:read("*a") or ""
        h:close()
        if out ~= "" then outputs[out] = (outputs[out] or 0) + 1 end
      end
    end
    local distinct, sample = 0, nil
    for k in pairs(outputs) do distinct = distinct + 1; sample = sample or k end
    TmpWork.close()
    if distinct == 0 then
      require("tests.skip_ledger").note("hand-type-order/cross-process", 2,
        "luajit not reachable from io.popen, the cross-process order check did not run")
    else
      check("the order is identical in " .. runs .. " independent processes", distinct == 1,
        distinct .. " distinct orders")
      check("and it is the engine order", sample == table.concat(EXPECTED, "|"), sample)
    end
  else
    TmpWork.close()
    require("tests.skip_ledger").note("hand-type-order/cross-process", 2,
      "the probe file could not be written to " .. probe_dir)
  end
end

done()
