local TextColors = require("hud.text_colors")

local function new_state()
  return {
    state_changed_at = 0,
    rp_compact = false,
    lp_compact = false,
    rp_cols_latch = nil,
    lp_cols_latch = nil,
    seed_quip = nil,
    seed_quip_src = nil,
    panel_font = nil,
    panel_font_small = nil,
    wrap_cache = {},
    wrap_cache_keys = {},
    desc_text = {},
    desc_text_keys = {},
    _text_blocks = {},
    _text_blocks_n = 0,
    ov = {
      trunc = {}, trunc_keys = {},
      panel = {}, shop = {}, pack = {}, built_at = 0, built_sn = nil, built_epoch = nil,
      sl_text = nil, sl_at = 0,
      round_eval_at = 0, re_seen = false,
      footer_prev_emote = nil, footer_prev_quip = nil,
      footer_last_emote = nil, footer_last_quip = nil,
      stage_cx = nil, stage_max_w = nil,
    },
    neuro_logo = nil,
    neuro_logo_attempts = 0,
    quad_cache = {},
    quad_cache_n = 0,
    panel_emote_cache = {},
    panel_emote_attempts = {},
    neuro_card_draw_hooked = false,
    card_glow_lv = setmetatable({}, { __mode = "k" }),
    card_glow_t  = setmetatable({}, { __mode = "k" }),
    panel_y_current = 6,
    panel_y_last_time = 0,
    panel_x_current = nil,
    shop_x_current = nil,
    shop_x_from = nil,
    shop_x_target = nil,
    shop_x_at = 0,
    shop_y_current = nil,
    shop_y_from = nil,
    shop_y_target = nil,
    shop_y_at = 0,
    center_cx_current = nil,
    center_w_current = nil,
    pack_w_hi = nil,
    right_panel_slide_frac = 0,
    rp_slide_current = 0,
    rp_slide_from = 0,
    rp_slide_target = 0,
    rp_slide_at = 0,
    rp_slide_run = 0,
    left_panel_slide_frac = 0,
    lp_slide_current = 0,
    lp_slide_from = 0,
    lp_slide_target = 0,
    lp_slide_at = 0,
    lp_slide_run = 0,
    shop_appear_t = 0,
    shop_last_visible = false,
    shop_reroll_seen = nil,
    shop_reroll_t = nil,
    shop_leave_t = nil, shop_leave_snap = nil, shop_leave_game = nil,
    shop_ignite_t = nil,
    panel_h_current = 0,
    known_joker_refs = nil,
    known_cons_refs = nil,
    joker_showcase = nil,
    joker_showcase_q = {},
    pack_gained_q = {},
    desc_slot = 0,
    desc_epoch = false,
    desc_cache = {},
    desc_cache_n = -1,
    cons_slot = 0,
    cons_epoch = false,
    cons_cache = {},
    cons_cache_n = -1,
    buy_showcase = nil,
    pack_disp = {},
    pack_appear_t = 0,
    pack_last_sn = nil,
    pack_card_indices = {},
    pack_initial_count = 0,
    pack_hl = false, pack_hl_t = 0,
    pack_claim_at = nil,
    pack_winners = {}, pack_collapse_t = nil, pack_collapse_snap = nil,
    pack_collapse_req = nil, pack_collapse_done = nil, pack_losers = nil,
    pack_leave_t = nil, pack_leave_snap = nil, pack_leave_n = 0,
    pack_relight_t = nil,
    known_voucher_keys = nil,
    voucher_order = {},
    voucher_anim = {},
    voucher_wrap = {},
    voucher_fx = {},
    voucher_seg = {},
    voucher_seg_fit = {},
    voucher_tier2 = {},
    voucher_drawer_gate = {},
    desc_slot_ref = nil, cons_slot_ref = nil,
    voucher_rot_anchor = nil,
    voucher_count_pulse_at = 0,
    voucher_rot_idx = 1,
    voucher_rot_prev = 1,
    voucher_rot_epoch = false,
    voucher_rot_hold_until = 0,
    voucher_rot_slide_at = 0,
    voucher_game_ref = nil,
    drawer_slide_current = 0,
    drawer_slide_from = 0,
    drawer_slide_target = 0,
    drawer_slide_at = 0,
    drawer_slide_run = 0,
    drawer_h_current = 0,
    drawer_reserve = 0,
    drawer_reserve_target = 0,
  }
end

local S = new_state()
S.new_state = new_state

function S.invalidate_caches()
  TextColors.invalidate()
  S.panel_font, S.panel_font_small = nil, nil
  S.wrap_cache, S.wrap_cache_keys = {}, {}
  S.desc_text, S.desc_text_keys = {}, {}
  S._text_blocks, S._text_blocks_n = {}, 0
  S.quad_cache, S.quad_cache_n = {}, 0
  S.desc_cache, S.desc_cache_n = {}, -1
  S.cons_cache, S.cons_cache_n = {}, -1
  S.panel_emote_cache, S.panel_emote_attempts = {}, {}
  S.neuro_logo, S.neuro_logo_attempts = nil, 0
  S.voucher_wrap, S.voucher_fx = {}, {}
  S.voucher_seg, S.voucher_seg_fit = {}, {}
  S.ov.trunc, S.ov.trunc_keys = {}, {}
  S.ov.panel, S.ov.shop, S.ov.pack = {}, {}, {}
  S.shop_leave_t, S.shop_leave_snap, S.shop_leave_game = nil, nil, nil
  S.ov.built_at, S.ov.built_sn, S.ov.built_epoch = 0, nil, nil
end

return S
