local Model = require("facts.boss.model")
local View = require("facts.boss.view")
local Utils = require("util.utils")

local M = {}

local function subst(tpl, vars)
  return (tostring(tpl):gsub("{([%w_]+)}", function(k)
    local v = vars[k]
    if v == nil then return "{" .. k .. "}" end
    return tostring(v)
  end))
end

local SURFACE_FALLBACK = {
  select = { "select" },
  status = { "status", "select" },
  hand = { "hand", "status", "select" },
  ante = { "ante" },
  rejection = { "rejection" },
}

function M.render(surface, key, opts)
  opts = opts or {}
  local rec = Model.get(key)
  if not rec then return nil end
  local order = SURFACE_FALLBACK[surface]
  if not order then return nil end
  local tpl
  for _, name in ipairs(order) do
    tpl = rec.templates and rec.templates[name]
    if tpl then break end
  end
  if not tpl then
    if surface == "ante" or surface == "rejection" then return nil end
    tpl = "{rule}"
  end
  local ok_v, v = pcall(View.build, opts.blind)
  if not ok_v then v = {} end
  local vars = {}
  if rec.facts then
    local ok_f, facts = pcall(rec.facts, v)
    if ok_f and type(facts) == "table" then vars = facts end
  end
  for k, val in pairs(opts.vars or {}) do vars[k] = val end
  local name = Model.boss_name(key) or rec.name
  vars.boss = name
  vars.rule = subst(rec.rule, vars)
  local body = subst(tpl, vars)
  if surface == "ante" or surface == "rejection" or (opts and opts.no_prefix) then return body end
  return "Boss (" .. tostring(name) .. "): " .. body
end

function M.boss_line(surface, key, blind, opts)
  local blind_def = blind or (key and G and G.P_BLINDS and G.P_BLINDS[key])
  key = key or Model.resolve_key(blind)
  local line = M.render(surface, key, { blind = blind, vars = opts and opts.vars })
  if line then return line end
  local ok_df, DF = pcall(require, "facts.debuff_facts")
  if not (ok_df and DF) then return nil end
  local src = blind_def or blind
  local txt = ""
  if type(src) == "table" then
    local ok_t, native = pcall(DF.blind_effect_text, key, src)
    if ok_t and type(native) == "string" then txt = native end
  end
  if txt == "" and type(blind) == "table" then
    local ok_t, native = pcall(DF.boss_debuff_text, blind)
    if ok_t and type(native) == "string" then txt = native end
  end
  if txt == "" then return nil end
  Utils.neuro_log("boss: no curated record for key " .. tostring(key) .. "; using raw engine text")
  local name = (type(src) == "table" and src.name) or (type(blind) == "table" and blind.name) or key or "?"
  return "Boss (" .. tostring(name) .. "): " .. txt
end

function M.active_boss_key()
  local b = G and G.GAME and G.GAME.blind
  if type(b) ~= "table" or b.disabled then return nil end
  return Model.resolve_key(b)
end

function M.upcoming_boss_key()
  local rr = G and G.GAME and G.GAME.round_resets
  local key = rr and rr.blind_choices and rr.blind_choices.Boss
  return type(key) == "string" and key or nil
end

return M
