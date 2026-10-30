local ContextReadable = {}


local Utils = require("util.utils")
local ContextCompact = require("context.context_compact")
local CtxHelpers = require("context.ctx_helpers")
local StateDoc = require("context.state_doc")

local VALUE_LONG = CtxHelpers.VALUE_LONG

local TAGGED = { FRAME = "^FRAME|", RUN = "^RUN|", STATE = "^.*" }

local function verbalize_sections(list)
  local out = {}
  for _, section in ipairs(list) do
    for line in ((section or "") .. "\n"):gmatch("([^\n]*)\n") do
      if line ~= "" then
        local tag = TAGGED[line:find("^STATE:") and "STATE" or line:match("^([A-Z][A-Z_0-9]*)[:|%[%(]")]
        local s = tag and line:gsub(tag, "") or line
        if s ~= "" then out[#out + 1] = s end
      end
    end
  end
  return table.concat(out, "\n")
end

local function verbalize(board) return verbalize_sections({ board }) end

local function cards_list(ix) return table.concat(ix, ", ") end
local function named_cards(ix)
  local hand = G and G.hand and G.hand.cards or {}
  local out = {}
  for k, i in ipairs(ix) do
    local card = hand[i]
    out[k] = card and (i .. ": " .. require("facts.card_area_util").hand_card_name(card)) or tostring(i)
  end
  return table.concat(out, ", ")
end

local function attach(out, piece)
  if piece == "" then return out end
  if piece:sub(1, 1) == "(" and out:find("[%d%)]$") then return out .. " " .. piece end
  return out .. piece
end

local function attach_all(out, pieces)
  for _, p in ipairs(pieces) do out = attach(out, p) end
  return out
end

local function faced_prose(d)
  if not d.faced then return "" end
  return string.format("; up to %d face card%s, dealt face down, would complete it too, so the real chance is higher",
    d.faced, d.faced == 1 and "" or "s")
end

local DRAW_ASSUMPTION = "you discard as many of the others listed as you may"

local function draw_prose(d, shared)
  if type(d) ~= "table" then return "" end
  local assumption = shared and "" or (" if " .. DRAW_ASSUMPTION)
  if d.lo then
    return string.format(
      "(%d to %d of the %d draw-pile cards complete it, depending on which cards are face down; %d-%d%% chance to hit one%s%s)",
      d.lo, d.n, d.m, d.plo, d.pct, assumption, faced_prose(d))
  end
  return string.format(
    "(%d of the %d draw-pile cards complete it; %d%% chance to hit one%s%s)",
    d.n, d.m, d.pct, assumption, faced_prose(d))
end

-- Debuffed cards add no card value, but the hand’s chips and mult still score.
local function deb_text(deb)
  if deb == "all" then return "all cards debuffed, adding nothing" end
  return deb > 0 and (CtxHelpers.plural(deb, "card") .. " debuffed, adding nothing") or nil
end

local function floor_text(n) return n and ("this boss needs " .. n .. "+ cards played - add spare cards") or nil end

local function paren(t) return t and ("(" .. t .. ")") or "" end

local function zeroed_prose(z) return z and (" -- " .. z) or "" end

local function ready_prose(ready)
  local notes, holders = {}, {}
  for i, r in ipairs(ready) do
    local pre, post = { deb_text(r.deb), floor_text(r.floor) }, {}
    for _, part in ipairs(r.chain) do post[#post + 1] = part end
    notes[i] = { pre = pre, post = post }
    for _, list in ipairs({ pre, post }) do
      for _, t in pairs(list) do
        holders[t] = holders[t] or {}
        table.insert(holders[t], i)
      end
    end
  end
  local function inline(t) return (t and #holders[t] < 2) and paren(t) or "" end
  local items, groups, by_key = {}, {}, {}
  for i, r in ipairs(ready) do
    local n = notes[i]
    local pieces = {
      #r.ix > 0 and (" (cards " .. named_cards(r.ix) .. ")") or "",
      r.level and string.format("(level %g, %g chips x%g mult)", r.level.score_level, r.level.chips, r.level.mult) or "",
      inline(n.pre[1]), inline(n.pre[2]),
      r.cost and (" (" .. Utils.money(-r.cost) .. ")") or "", r.ox and " (OX: zeroes $ if played)" or "",
    }
    for _, t in ipairs(n.post) do pieces[#pieces + 1] = inline(t) end
    items[i] = attach_all(r.name, pieces) .. zeroed_prose(r.zeroed)
    for _, t in ipairs({ n.pre[1] or false, n.pre[2] or false, unpack(n.post) }) do
      if t and #holders[t] >= 2 then
        local key = table.concat(holders[t], ",")
        local g = by_key[key]
        if not g then
          g = { idx = holders[t], notes = {}, seen = {} }
          by_key[key] = g
          groups[#groups + 1] = g
        end
        if not g.seen[t] then g.seen[t] = true; g.notes[#g.notes + 1] = t end
      end
    end
  end
  local out = table.concat(items, "; ") .. "."
  for _, g in ipairs(groups) do
    local names = {}
    for k, i in ipairs(g.idx) do names[k] = ready[i].name end
    local label = #g.idx == #ready and "Each of these" or CtxHelpers.join(names)
    out = out .. " " .. label .. ": " .. table.concat(g.notes, "; ") .. "."
  end
  return out
end

local function close_prose(c, shared)
  if not c.ix then return c.name .. zeroed_prose(c.zeroed) end
  local lead = c.suit and string.format("Flush: %d %s", c.suit_count, c.suit) or c.name
  local out = lead .. " keep cards " .. cards_list(c.ix)
    .. (c.others and (", the others are " .. cards_list(c.others)) or "")
  out = attach_all(out, {
    c.cap and (" (you may discard at most " .. c.cap .. " of them)") or "",
    draw_prose(c.draw, shared), paren(deb_text(c.deb)), paren(floor_text(c.floor)),
    c.open == nil and "" or (c.open and " (completes on either end)" or " (needs one exact rank)"),
  })
  return out .. zeroed_prose(c.zeroed)
end

function ContextReadable.structure_prose(st)
  if not st then return "" end
  if st.hidden then return st.hidden end
  local sh = st.shape
  local out = (st.lead ~= "" and (st.lead:sub(1, -2) .. "\n") or "") .. string.format(
    "- Shape: %d pair or better, %d three-of-a-kind or better, %d four-of-a-kind; highest repeated rank %s; most cards of one suit %d; longest run %d.",
    sh.pairs, sh.trips, sh.quads, sh.top and (VALUE_LONG[sh.top] or sh.top) or "none", sh.max_suit, sh.max_run)
  if st.debuffed > 0 then
    out = out .. string.format(" %d card(s) DEBUFFED (they score 0).", st.debuffed)
  end
  if #st.ready > 0 then
    out = out .. "\n- Ready to play now: " .. ready_prose(st.ready)
    if st.splash then
      out = out .. string.format(" All played cards score (Splash) -- you may still play at most %d.", st.splash)
    end
  end
  if #st.close > 0 then
    local figures = 0
    for _, c in ipairs(st.close) do
      if c.ix and type(c.draw) == "table" then figures = figures + 1 end
    end
    local shared = figures >= 2
    local items = {}
    for i, c in ipairs(st.close) do items[i] = close_prose(c, shared) end
    out = out .. "\n- One card away: " .. table.concat(items, "; ") .. "."
      .. (shared and (" Each chance to hit assumes " .. DRAW_ASSUMPTION .. ".") or "")
  end
  if st.facedown then
    out = out .. " (This boss draws some cards face-down - your hand may change.)"
  end
  return out .. " "
end

function ContextReadable.blocks(state_name, allowed_actions)
  local ok, sections = pcall(ContextCompact.build, state_name, allowed_actions,
    { split = "state", return_list = true, blocks = true })
  if not ok or type(sections) ~= "table" then return nil end
  local out = {}
  for _, section in ipairs(sections) do
    out[#out + 1] = { heading = section.heading, text = verbalize_sections({ section.text }) }
  end
  return #out > 0 and out or nil
end

function ContextReadable.build(state_name, allowed_actions)
  local blocks = ContextReadable.blocks(state_name, allowed_actions)
  return blocks and StateDoc.render(blocks) or nil
end

function ContextReadable.verbalize_stable(board)
  if type(board) ~= "string" or board == "" then return board end
  local ok, prose = pcall(verbalize, board)
  return (ok and prose ~= "" and prose) or board
end

return ContextReadable
