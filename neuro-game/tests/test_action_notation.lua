_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} }, TIMERS = { REAL = 100 } }

local check, done = require("tests.helpers").harness("action-notation")

require("core.actions")
local Registry = require("core.action_registry")

local names = Registry.names()
check("the sweep has actions to scan", #names >= 20, tostring(#names))

for _, name in ipairs(names) do
  local prompt = Registry.prompt(name)
  local body = prompt:match("^" .. name .. "|(%b{})")
  check("" .. name .. ": prompt renders as NAME|{json object}", body ~= nil, tostring(prompt))
  if body then
    local stripped = body:gsub("<[^>]*>", "0")
    check("" .. name .. ": every key is quoted",
      stripped:find("[{,]%s*[%a_]") == nil, prompt)
    check("" .. name .. ": no bare one-token placeholder (i, j, N)",
      body:find(":%s*[ijN][,}%]]") == nil, prompt)
    check("" .. name .. ": no schema-keyword notation leaks in",
      body:find(":integer") == nil and body:find(":array") == nil
      and body:find(">=") == nil and body:find("%?[,}]") == nil, prompt)
  end
end

local play = Registry.prompt("play_hand")
check("play_hand no longer renders a bracketed count next to a value bound",
  play:find("array%[%d+%-%d+%]") == nil, play)
check("play_hand spells the count as a count",
  play:find("pick 1 to ", 1, true) ~= nil, play)
check("play_hand names what the entries are",
  play:find("hand positions", 1, true) ~= nil, play)
check("indices is still rendered as a JSON array",
  play:find('"indices":%[') ~= nil, play)

local order = Registry.prompt("set_joker_order")
check("an integer value bound reads as a value, not a count",
  order:find('"from_index":<int 1+>', 1, true) ~= nil, order)
check("count and value notations cannot be confused",
  play:find("int 1+", 1, true) == nil and order:find("pick ", 1, true) == nil,
  play .. " || " .. order)

check("set_joker_order renders identically on every call",
  Registry.prompt("set_joker_order") == order, order)

local TokenLegends = require("facts.token_legends")
local gloss = TokenLegends.READABLE_COMMON
check("the glossary explains the angle-bracket placeholder",
  gloss:find("angle brackets", 1, true) ~= nil, gloss)
check("the glossary says the count is a count",
  gloss:find("HOW MANY", 1, true) ~= nil, gloss)

local sell = Registry.render("sell_card",
  { area = "jokers", index = 1, plan = { money_plan = "m", build_plan = "b" } })
check("rendered key order is the schema's, required first then alphabetical",
  sell == 'sell_card|{"area":"jokers","index":1,"plan":{"build_plan":"b","money_plan":"m"}}', sell)
local buy = Registry.render("buy_from_shop", { area = "shop_jokers", index = 2, use = false })
check("the same ordering holds for another contract",
  buy == 'buy_from_shop|{"area":"shop_jokers","index":2,"use":false}', buy)
check("re-rendering the same payload is byte-identical",
  Registry.render("sell_card",
    { area = "jokers", index = 1, plan = { money_plan = "m", build_plan = "b" } }) == sell, sell)

done()
