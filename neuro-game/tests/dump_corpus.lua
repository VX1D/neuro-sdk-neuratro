local M = {}

function M.seed(default_seed, default_iters)
  local seed = tonumber(arg and arg[1]) or default_seed
  local iters = tonumber(arg and arg[2]) or default_iters
  math.randomseed(seed)
  return seed, iters
end

function M.ri(a, b) return math.random(a, b) end
function M.pick(t) return t[M.ri(1, #t)] end
function M.chance(p) return math.random() < p end

function M.banner(s) print(("="):rep(90)); print(s); print(("="):rep(90)) end

M.WIPE = { "hand", "jokers", "consumeables", "shop_jokers", "shop_vouchers", "shop_booster", "shop",
  "pack_cards", "booster_pack", "blind_select_opts", "blind_select", "OVERLAY_MENU" }

function M.fresh_g(D, A)
  for _, k in ipairs(M.WIPE) do G[k] = nil end
  G.NEURO = { dispatcher = D, actions = A, persona = "neuro", reserved_dollars = 0, _reservation_epoch = 0, shop_reroll_count = 0,
  state_enter_serial = (tonumber(G.NEURO and G.NEURO.state_enter_serial) or 0) + 5 }
end

return M
