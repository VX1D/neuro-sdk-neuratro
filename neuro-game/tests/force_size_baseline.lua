local rows = {
  ["SELECTING_HAND/Normal: 5 cards, 4 hands, 3 discards"] = { 5034, 5082 },
  ["SELECTING_HAND/Amber Acorn: the boss that names reordering"] = { 5761, 5833 },
  ["SHOP/Normal: affordable joker, affordable booster, $10"] = { 5195, 5291 },
  ["BLIND_SELECT/Small blind selectable"] = { 3861, 3981 },
  ["BLIND_SELECT/Boss blind only (no skip, no reroll voucher)"] = { 4338, 4458 },
  ["ROUND_EVAL/Normal: cash_out available"] = { 881, 889 },
  ["TAROT_PACK/Has pack cards"] = { 3521, 3657 },
  ["BUFFOON_PACK/BUFFOON_PACK variant with pack cards"] = { 3242, 3378 },
  ["STANDARD_PACK/STANDARD_PACK with cards"] = { 3398, 3534 },
  ["PLANET_PACK/PLANET_PACK with cards"] = { 3663, 3816 },
  ["SPECTRAL_PACK/SPECTRAL_PACK with cards"] = { 3517, 3670 },
  ["SMODS_BOOSTER_OPENED/SMODS_BOOSTER_OPENED with cards"] = { 3227, 3380 },
  ["SHOP/$0 nothing affordable, has jokers to sell"] = { 4687, 4759 },
  ["SELECTING_HAND/Amber Acorn with the row flipped: face-down jokers and a face-down card in hand"] =
    { 4484, 4565 },
  ["SHOP/Marked roster: a debuffed joker, an eternal joker, and the model's own plan on every row"] =
    { 5463, 5562 },
  ["MENU/Normal: has G.GAME"] = { 364, 400 },
  ["SPLASH/Normal: minimal state"] = { 235, 253 },
  ["RUN_SETUP/Run setup overlay active"] = { 661, 715 },
  ["GAME_OVER/No overlay (setup_run must work)"] = { 235, 253 },
}

local M = { PAYLOAD = {}, WIRE = {} }
for key, sizes in pairs(rows) do
  M.PAYLOAD[key] = sizes[1]
  M.WIRE[key] = sizes[2]
end
return M
