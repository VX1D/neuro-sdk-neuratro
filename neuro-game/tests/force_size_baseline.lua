local rows = {
  ["SELECTING_HAND/Normal: 5 cards, 4 hands, 3 discards"] = { 5072, 5120 },
  ["SELECTING_HAND/Amber Acorn: the boss that names reordering"] = { 5755, 5827 },
  ["SHOP/Normal: affordable joker, affordable booster, $10"] = { 5900, 6044 },
  ["BLIND_SELECT/Small blind selectable"] = { 4075, 4195 },
  ["BLIND_SELECT/Boss blind only (no skip, no reroll voucher)"] = { 4552, 4672 },
  ["ROUND_EVAL/Normal: cash_out available"] = { 881, 889 },
  ["TAROT_PACK/Has pack cards"] = { 3776, 3912 },
  ["BUFFOON_PACK/BUFFOON_PACK variant with pack cards"] = { 3497, 3633 },
  ["STANDARD_PACK/STANDARD_PACK with cards"] = { 3653, 3789 },
  ["PLANET_PACK/PLANET_PACK with cards"] = { 3918, 4071 },
  ["SPECTRAL_PACK/SPECTRAL_PACK with cards"] = { 3772, 3925 },
  ["SMODS_BOOSTER_OPENED/SMODS_BOOSTER_OPENED with cards"] = { 3482, 3635 },
  ["SHOP/$0 nothing affordable, has jokers to sell"] = { 5370, 5496 },
  ["SELECTING_HAND/Amber Acorn with the row flipped: face-down jokers and a face-down card in hand"] =
    { 4527, 4608 },
  ["SHOP/Marked roster: a debuffed joker, an eternal joker, and the model's own plan on every row"] =
    { 6064, 6208 },
  ["MENU/Normal: has G.GAME"] = { 364, 400 },
  ["SPLASH/Normal: minimal state"] = { 235, 253 },
  ["RUN_SETUP/Run setup overlay active"] = { 661, 715 },
  ["GAME_OVER/No overlay (open_run_setup must work)"] = { 235, 253 },
}

local M = { PAYLOAD = {}, WIRE = {} }
for key, sizes in pairs(rows) do
  M.PAYLOAD[key] = sizes[1]
  M.WIRE[key] = sizes[2]
end
return M
