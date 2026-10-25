local M = {}

local function id(v) return v end

function M.complete(ctx)
  local me, mo = ctx.metrics, ctx.motion
  local Tuning = require("core.config")
  me.cn, me.rn = me.cn or id, me.rn or id
  me.anchor = me.anchor or Tuning.get("NEURO_OVERLAY_ANCHOR")
  me.offset_y = me.offset_y or Tuning.get("NEURO_OVERLAY_OFFSET_Y")
  me.shop_anchor = me.shop_anchor or Tuning.get("NEURO_SHOP_ANCHOR")
  me.shop_offset_x = me.shop_offset_x or Tuning.get("NEURO_SHOP_OFFSET_X")
  me.shop_offset_y = me.shop_offset_y or Tuning.get("NEURO_SHOP_OFFSET_Y")
  me.n_cols = me.n_cols or 1
  me.n_cols_used = me.n_cols_used or me.n_cols
  me.p_w = me.p_w or me.rn(320)
  me.pw_total = me.pw_total or me.p_w * me.n_cols
  me.total_h = me.total_h or me.sh
  me.panel_h_target = me.panel_h_target or me.total_h
  local layout = require("render.hud_overlay").panel_layout
  local x, y, side, _, slide = layout(me.anchor, Tuning.get("NEURO_OVERLAY_OFFSET_X"), me.offset_y, me.sw, me.sh,
    me.pw_total, me.panel_h_target, 0)
  if me.p_x == nil then me.p_x, me.p_y = x, y end
  me.main_side = me.main_side or side
  me.main_slide_dir = me.main_slide_dir or slide
  me.p_y_target_stable = me.p_y_target_stable or y
  if ctx.center_cx == nil then
    require("render.hud_shared").corridor(ctx, me.sw, me.main_side, x, me.pw_total, mo.now, mo.dt, me.cn)
  end
  ctx.center_top_y = ctx.center_top_y or 8
  local da = ctx.data
  da.showcase_alpha = da.showcase_alpha or 0
  da.footer_fade = da.footer_fade or 1
  return ctx
end

return M
