_G.NEURO_TEST = true

local check, done = require("tests.helpers").harness("gameplay-journal")
local Journal = require("core.gameplay_journal")

local function reset(generation, epoch)
  _G.G = {
    NEURO = {
      run_generation = generation or 1,
      shop_visit_epoch = epoch or 1,
      shop_pack_interrupt = false,
    },
  }
end

local function seal(body, id)
  local event, err = Journal.seal(body, id)
  check("seal " .. tostring(id), type(event) == "table", err)
  return event
end

reset()
check("rendering an absent journal is observational",
  Journal.render("SHOP", 0, { dollars = 10 }) == nil and G.NEURO.gameplay_journal == nil)

local bad, bad_err = Journal.seal({ kind = "shop_buy", area = "shop_jokers",
  purchase_kind = "joker", paid = -1, public_subject = "Joker" }, "bad")
check("closed union rejects invalid money", bad == nil and bad_err == "invalid paid value", bad_err)
local fractional_buy, fractional_buy_err = Journal.seal({ kind = "shop_buy", area = "shop_jokers",
  purchase_kind = "joker", paid = 2.5, public_subject = "Joker" }, "fractional-buy")
check("journal rejects rather than rounds a fractional purchase value",
  fractional_buy == nil and fractional_buy_err == "invalid paid value", fractional_buy_err)
local fractional_sell, fractional_sell_err = Journal.seal({ kind = "shop_sell", area = "jokers",
  received = 1.5, public_subject = "Joker" }, "fractional-sell")
check("journal rejects rather than rounds a fractional sale value",
  fractional_sell == nil and fractional_sell_err == "invalid received value", fractional_sell_err)
local extra = seal({ kind = "shop_reroll", paid = 5, used_free_reroll = false,
  arbitrary = "discard me" }, "r1")
check("closed union drops arbitrary fields", extra.arbitrary == nil)

local ok, published = Journal.publish(extra)
check("paid reroll publishes", ok and published.sequence == 1 and published.paid == 5)
local dup, dup_reason = Journal.publish(extra)
check("action id is exactly-once", not dup and dup_reason == "duplicate", dup_reason)

local free = seal({ kind = "shop_reroll", paid = 0, used_free_reroll = true }, "r2")
check("free reroll publishes", Journal.publish(free) == true)
local buy = seal({ kind = "shop_buy", public_subject = "  Crystal\n Ball  ", area = "shop_vouchers",
  purchase_kind = "voucher", paid = 10 }, "b1")
check("buy publishes", Journal.publish(buy) == true)
local sell = seal({ kind = "shop_sell", public_subject = "Egg", area = "jokers", received = 2 }, "s1")
check("sell publishes", Journal.publish(sell) == true)

local text, through = Journal.render("SHOP", 0,
  { dollars = 7, joker_slots = { count = 3, limit = 5 } })
check("shop history is chronological and source-valued",
  text:find("rerolled for $5; rerolled for $0 (free reroll); bought Crystal Ball for $10; sold Egg for $2", 1, true) ~= nil,
  text)
check("shop history carries captured current facts",
  text:find("current money $7; Joker slots 3/5", 1, true) ~= nil, text)
check("shop projection does not duplicate current events",
  not text:find("Applied since the last delivered decision", 1, true), text)
check("cursor covers the rendered high-water mark", through == 4, through)

local outside = Journal.render("SELECTING_HAND", 2, {}) or ""
check("outside shop only undelivered events render",
  outside:find("bought Crystal Ball", 1, true) ~= nil
    and outside:find("sold Egg", 1, true) ~= nil
    and not outside:find("rerolled for $5", 1, true), outside)
G.NEURO.shop_pack_interrupt = true
local interlude = Journal.render("STANDARD_PACK", 4, {}) or ""
check("shop pack interlude retains visit history", interlude:find("This shop visit", 1, true) ~= nil, interlude)

local stale = seal({ kind = "shop_reroll", paid = 6, used_free_reroll = false }, "old")
G.NEURO.run_generation = 2
local stale_ok, stale_reason = Journal.publish(stale)
check("old generation cannot publish", not stale_ok and stale_reason == "stale generation", stale_reason)

reset(3, 9)
local stale_without_store = assert(Journal.seal(
  { kind = "shop_reroll", paid = 1, used_free_reroll = false }, "stale-without-store"))
G.NEURO.run_generation = 4
local stale_empty_ok, stale_empty_reason = Journal.publish(stale_without_store)
check("stale publish is observational before store allocation",
  not stale_empty_ok and stale_empty_reason == "stale generation" and G.NEURO.gameplay_journal == nil,
  stale_empty_reason)

reset(3, 9)
local hidden = Journal.public_card_label({ facing = "back", ability = { name = "Secret" } }, "shop_jokers", 2)
check("hidden identity is never journalled", hidden == "face-down item #2 in shop_jokers", hidden)
local PublicCard = require("facts.public_card_identity")
local vanilla = { config = { center = { key = "j_egg" } }, ability = { name = "Egg" } }
check("vanilla centre key is the canonical multiset identity",
  PublicCard.multiset_key(vanilla, "jokers", 1) == "center:j_egg")
local utf8 = string.rep("a", 159) .. "ątail"
local clipped = Journal._test.public_label(utf8)
check("label cap ends on a UTF-8 boundary", #clipped == 159 and clipped == string.rep("a", 159), #clipped)

for i = 1, 18 do
  local event = seal({ kind = "shop_reroll", paid = i, used_free_reroll = false }, "many" .. i)
  Journal.publish(event)
end
local bounded, bounded_through = Journal.render("SHOP", 0, {})
check("renderer is bounded with exact omission count",
  bounded:find("2 earlier transaction(s) omitted", 1, true) ~= nil
    and bounded_through == 18, bounded)

G.NEURO.shop_visit_epoch = 10
local newest = seal({ kind = "shop_reroll", paid = 19, used_free_reroll = false }, "new-visit")
Journal.publish(newest)
Journal.prune_delivered({ journal = { through_sequence = 19, shop_visit_epoch = 10 } })
check("delivered older bodies are pruned", #G.NEURO.gameplay_journal.ordered == 1,
  #G.NEURO.gameplay_journal.ordered)
local replay, replay_reason = Journal.publish(newest)
check("pruning retains id tombstones", not replay and replay_reason == "duplicate", replay_reason)

done()
