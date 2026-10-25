local M = {}

local CLASS_PROSE = {
  item = "item tag: hands you cards you would otherwise pay shop price for",
  economy = "economy tag: pays money, which compounds through interest",
  edition = "edition tag: the next plain joker in the shop gets this edition and is free, and editions are hard to add later",
  level = "level tag: permanently raises a hand type's level for the rest of the run",
  offer = "shop tag: adds an extra Voucher to the next shop, which you still pay for and then keep for the run",
  copy = "copy tag: its value is a copy of the next tag you take",
  utility = "utility tag: bends a rule for one shop or blind, with nothing to keep afterwards",
}

local ECONOMY_NO_INTEREST = "economy tag: pays money once; interest is off this run, so it does not compound"

local CLASS_OF = {}
for class, keys in pairs({
  item = { "uncommon", "rare", "charm", "meteor", "buffoon", "standard", "ethereal", "top_up", "coupon" },
  economy = { "investment", "handy", "garbage", "skip", "economy" },
  edition = { "negative", "foil", "holo", "polychrome" },
  level = { "orbital" }, offer = { "voucher" }, copy = { "double" }, utility = { "juggle", "boss", "d_six" },
}) do
  for _, k in ipairs(keys) do CLASS_OF["tag_" .. k] = class end
end

local function class_of(tag_key)
  return CLASS_OF[tostring(tag_key or "")]
end

function M.class_prose(tag_key)
  local class = class_of(tag_key)
  if class == "economy" and require("facts.economy_facts").no_interest() then return ECONOMY_NO_INTEREST end
  return class and CLASS_PROSE[class] or ""
end

local SHOP_CONTEXTS = { store_joker_create = true, store_joker_modify = true, voucher_add = true,
  shop_start = true, shop_final_pass = true }

function M.payout_moment(tag_key)
  local def = G and G.P_TAGS and G.P_TAGS[tostring(tag_key or "")]
  local kind = type(def) == "table" and type(def.config) == "table" and def.config.type or nil
  if SHOP_CONTEXTS[kind] then return "shop" end
  if kind == "eval" then return "boss" end
  return nil
end

function M.blind_tag(btype, tag_key)
  if type(btype) ~= "string" or type(tag_key) ~= "string" then return nil end
  local opt = G and G.blind_select_opts and G.blind_select_opts[string.lower(btype)]
  local ok, live = pcall(function()
    local e = opt and opt:get_UIE_by_ID("tag_container")
    return e and e.config and e.config.ref_table
  end)
  if ok and type(live) == "table" and live.key == tag_key then return live end
  local def = G and G.P_TAGS and G.P_TAGS[tag_key]
  local rr = G and G.GAME and G.GAME.round_resets
  local chosen = rr and G.GAME.orbital_choices and G.GAME.orbital_choices[rr.ante]
  return { key = tag_key, name = def and def.name, config = def and def.config,
    ability = { blind_type = btype, orbital_hand = type(chosen) == "table" and chosen[btype] or nil } }
end

return M
