local rows = {
  ["SELECTING_HAND/Normal: 5 cards, 4 hands, 3 discards"] = { 4393, 4393 },
  ["SELECTING_HAND/Amber Acorn: the boss that names reordering"] = { 4998, 4998 },
  ["SHOP/Normal: affordable joker, affordable booster, $10"] = { 6558, 6558 },
  ["BLIND_SELECT/Small blind selectable"] = { 4259, 4259 },
  ["BLIND_SELECT/Boss blind only (no skip, no reroll voucher)"] = { 4743, 4743 },
  ["ROUND_EVAL/Normal: cash_out available"] = { 875, 875 },
  ["SMODS_BOOSTER_OPENED/Has pack cards"] = { 3482, 3482 },
  ["SMODS_BOOSTER_OPENED/Buffoon pack with a joker"] = { 3243, 3243 },
  ["SMODS_BOOSTER_OPENED/Standard pack with playing cards"] = { 3482, 3482 },
  ["SMODS_BOOSTER_OPENED/Celestial pack with planets"] = { 3828, 3828 },
  ["SMODS_BOOSTER_OPENED/Spectral pack with a card"] = { 3783, 3783 },
  ["SMODS_BOOSTER_OPENED/SMODS_BOOSTER_OPENED with cards"] = { 3482, 3482 },
  ["SHOP/$0 nothing affordable, has jokers to sell"] = { 6000, 6000 },
  ["SELECTING_HAND/Amber Acorn with the row flipped: face-down jokers and a face-down card in hand"] =
    { 4262, 4262 },
  ["SHOP/Marked roster: a debuffed joker, an eternal joker, and the model's own plan on every row"] =
    { 6737, 6737 },
  ["MENU/Normal: has G.GAME"] = { 433, 433 },
  ["RUN_SETUP/Run setup overlay active"] = { 974, 974 },
  ["GAME_OVER/No overlay (open_run_setup must work)"] = { 326, 326 },
}

local M = { PAYLOAD = {}, WIRE = {} }
for key, sizes in pairs(rows) do
  M.PAYLOAD[key] = sizes[1]
  M.WIRE[key] = sizes[2]
end
return M
