
_G.NEURO_TEST = true

local failures = 0
local function check(label, ok, detail)
  if ok then
    print("  PASS " .. label)
  else
    failures = failures + 1
    print("  FAIL " .. label .. (detail ~= nil and (" -- " .. tostring(detail)) or ""))
  end
end

local TextColors = require("hud.text_colors")
local State = require("hud.state")

TextColors.invalidate()
check("classify keeps the existing colour rules",
  TextColors.classify("MULT") == "D_RED"
    and TextColors.classify("CHIPS") == "D_CYAN"
    and TextColors.classify("$4") == "D_MONEY"
    and TextColors.classify("X2") == "D_MAROON"
    and TextColors.classify("+3") == "D_GREEN"
    and TextColors.classify("plain") == "D_WHITE")

TextColors.invalidate()
TextColors.classify("same word")
TextColors.classify("same word")
check("classify memoizes repeated words", TextColors._test.cache_size() == 1,
  TextColors._test.cache_size())
for i = 1, TextColors._test.cache_max + 40 do
  TextColors.classify("plain_" .. tostring(i))
end
check("classify memo stays bounded",
  TextColors._test.cache_size() == TextColors._test.cache_max,
  TextColors._test.cache_size())
State.invalidate_caches()
check("HUD invalidation clears the classify memo", TextColors._test.cache_size() == 0,
  TextColors._test.cache_size())

local Economy = require("facts.economy_facts")
local dollar_reads = 0
_G.G = {
  GAME = setmetatable({ bankrupt_at = 0 }, {
    __index = function(_, key)
      if key == "dollars" then
        dollar_reads = dollar_reads + 1
        return 10
      end
    end,
  }),
  NEURO = { reserved_dollars = 0 },
}
local voucher = { cost = 6, config = { center = { set = "Voucher" } } }
for _ = 1, 4 do
  local status = Economy.item_afford_status(voucher, "shop_vouchers", 5)
  check("hoisted spendable value controls affordability", status.afford == false and status.ok == false)
end
check("explicit spendable avoids recomputing global spendable", dollar_reads == 0, dollar_reads)
local fallback = Economy.item_afford_status(voucher, "shop_vouchers")
check("omitted spendable preserves the legacy calculation", fallback.afford and fallback.ok, fallback.afford)
check("legacy calculation reads the live balance", dollar_reads > 0, dollar_reads)

print(string.format("HUD_ECONOMY_CACHE_FAILS=%d (0 = clean)", failures))
os.exit(failures == 0 and 0 or 1)
