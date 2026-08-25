local M = {}

local CLASS_PROSE = {
  item = "item tag: hands you a card you would otherwise pay shop price for",
  economy = "economy tag: moves money, which compounds through interest",
  edition = "edition tag: upgrades a joker permanently, and editions are hard to add later",
  utility = "utility tag: bends a rule for one shop or blind, with nothing to keep afterwards",
}

local CLASS_OF = {
  tag_uncommon = "item",
  tag_rare = "item",
  tag_charm = "item",
  tag_meteor = "item",
  tag_buffoon = "item",
  tag_standard = "item",
  tag_ethereal = "item",
  tag_investment = "economy",
  tag_handy = "economy",
  tag_garbage = "economy",
  tag_top_up = "economy",
  tag_skip = "economy",
  tag_economy = "economy",
  tag_coupon = "economy",
  tag_d_six = "economy",
  tag_negative = "edition",
  tag_foil = "edition",
  tag_holo = "edition",
  tag_polychrome = "edition",
  tag_juggle = "utility",
  tag_boss = "utility",
  tag_orbital = "utility",
  tag_voucher = "utility",
  tag_double = "utility",
}

function M.class_of(tag_key)
  return CLASS_OF[tostring(tag_key or "")]
end

function M.class_prose(tag_key)
  local class = M.class_of(tag_key)
  return class and CLASS_PROSE[class] or ""
end

M.CLASS_PROSE = CLASS_PROSE
M.CLASS_OF = CLASS_OF

return M
