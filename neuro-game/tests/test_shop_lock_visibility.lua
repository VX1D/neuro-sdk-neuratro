_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("shop-lock-visibility")

local Tuning = require("core.config")

local PlanGate = require("core.plan_gate")
local CtxShop = require("context.ctx_shop")

local function fresh_G()
  _G.G = {
    STATE = 5, STATES = { SHOP = 5 },
    P_BLINDS = {},
    GAME = {
      dollars = 8, interest_cap = 25,
      round_resets = { ante = 2, blind_choices = {} },
      current_round = { free_rerolls = 0, reroll_cost = 5, discards_left = 0, hands_left = 0 },
      modifiers = {},
    },
    NEURO = { once_serials = {} },
    jokers = { cards = {} }, consumeables = { cards = {} },
    shop_jokers = { cards = {} }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
  }
end

local function add_affordable_joker()
  G.shop_jokers.cards = { {
    cost = 2,
    ability = { set = "Joker", name = "Joker" },
    config = { center = { key = "j_joker", set = "Joker", rarity = 1, name = "Joker" } },
  } }
end

local function unlock_plan()
  G.NEURO.econ_plan_ok = true
  G.NEURO.shop_plan_revision_required = {}
  G.NEURO.plan = { money = "hold for interest", money_scope = PlanGate.current_economy_scope() }
end

local function la() return CtxShop.legality_section("SHOP") or "" end

do
  fresh_G(); add_affordable_joker()
  G.NEURO.econ_plan_ok = false
  G.NEURO.shop_plan_revision_required = {}
  local line = la()
  check("L1a inline requirements name buy and reroll money plans",
    line:find("buying: include plan.money_plan", 1, true) ~= nil
    and line:find("rerolling: include plan.money_plan", 1, true) ~= nil, line)
  check("L1b affordability remains reported", line:find("can buy something: yes", 1, true) ~= nil, line)
end

do
  fresh_G(); add_affordable_joker(); unlock_plan()
  local line = la()
  check("L2a current standalone plan keeps the inline action contract",
    line:find("buying: include plan.money_plan", 1, true) ~= nil, line)
  local last_field_at = line:find("can use a consumable:", 1, true)
  local requires_at = line:find("Action requirements", 1, true)
  check("L2b legality line carries requirements after the five affordability fields",
    last_field_at and requires_at and requires_at > last_field_at, line)
end

do
  local Actions = require("core.actions")
  local real_valid = Actions.is_action_valid
  Actions.is_action_valid = function(n)
    return n == "leave_shop" or n == "buy_from_shop" or n == "reroll_shop" or n == "record_plan"
      or n == "record_joker_roles"
  end
  local FS = require("force.force_shop")

  local function offered(res, name)
    for _, a in ipairs((res or {}).actions or {}) do if a == name then return true end end
    return false
  end
  local ACTION_PHRASE = {
    buy = "buying", reroll = "rerolling", sell = "selling",
    use = "using a consumable", leave = "leaving the shop",
  }
  local function requires_says(line, act)
    return line:find((ACTION_PHRASE[act] or act) .. ": include", 1, true) ~= nil
  end

  local cases = {
    { name = "nothing locked", setup = function() unlock_plan() end },
    { name = "buy locked", setup = function()
        G.NEURO.econ_plan_ok = false; G.NEURO.shop_plan_revision_required = {}
      end },
    { name = "plan revision pending", setup = function()
        unlock_plan(); G.NEURO.shop_plan_revision_required = { money = true, build = true }
      end },
    { name = "buy locked + revision", setup = function()
        G.NEURO.econ_plan_ok = false; G.NEURO.shop_plan_revision_required = { build = true }
      end },
  }
  for _, c in ipairs(cases) do
    fresh_G(); add_affordable_joker(); c.setup()
    local res = FS.build()
    local line = la()
    check("[" .. c.name .. "] buy_from_shop remains offered with requirements",
      offered(res, "buy_from_shop") and requires_says(line, "buy"),
      line .. " || " .. table.concat(res.actions or {}, ","))
    check("[" .. c.name .. "] reroll_shop remains offered with requirements",
      offered(res, "reroll_shop") and requires_says(line, "reroll"),
      line .. " || " .. table.concat(res.actions or {}, ","))
    check("[" .. c.name .. "] leave_shop remains offered",
      offered(res, "leave_shop"), line .. " || " .. table.concat(res.actions or {}, ","))
  end
  Actions.is_action_valid = real_valid
end

do
  local real_requirements = PlanGate.action_requirements

  fresh_G(); add_affordable_joker()
  PlanGate.action_requirements = function(state, action)
    if state == "SHOP" and (action == "buy_from_shop" or action == "reroll_shop") then
      return { plan = { money = true } }
    end
    return { plan = {} }
  end
  local out = la()
  check("L4a names plan field and same-action contract",
    out:find("plan.money_plan", 1, true) and out:find("same action payload", 1, true), out)
  check("L4b keeps buying legal while describing its payload",
    out:find("can buy something: yes", 1, true) ~= nil, out)
  check("L4c leaks no raw tokens", not out:find("REQUIRES:", 1, true) and not out:find("LA|", 1, true), out)

  PlanGate.action_requirements = real_requirements

  fresh_G(); add_affordable_joker()
  local out3 = la()
  check("L4e plain line remains readable without requirements",
    out3:find("Legality: can buy something: yes", 1, true) ~= nil, out3)

  local out4 = CtxShop.legality_section("RUN_SETUP", { start_run = true }) or ""
  check("L4f RUN_SETUP branch untouched", out4:find("can start run: yes", 1, true) ~= nil, out4)
end

done()
