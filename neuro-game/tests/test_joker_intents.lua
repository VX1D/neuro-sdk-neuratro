_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local H = require("handlers.plan_handlers").handle_record_joker_roles
local check, done = require("tests.helpers").harness("joker-intents")

local function jk(key, sid, extra)
  local c = { config = { center = { key = key } }, ability = { set = "Joker" }, sort_id = sid }
  if extra then for k, v in pairs(extra) do c.ability[k] = v end end
  return c
end
local function base(jokers)
  _G.G = { NEURO = {}, jokers = { cards = jokers } }
end
local function run(exec) if type(exec) == "function" then return exec() end return nil end

base({ jk("j_a", 101), jk("j_b", 102) })
local exec, err = H({ intents = { { index = 1, tag = "CORE" }, { index = 2, tag = "CHANGE" } } })
check("valid returns exec", type(exec) == "function", tostring(err))
run(exec)
check("CORE stored as the tag", G.NEURO.joker_intents[101].tag == "CORE")
check("CHANGE stored as the tag", G.NEURO.joker_intents[102].tag == "CHANGE")

do
  local c1 = jk("j_a", 301); c1.ability.name = "Green Joker"
  local c2 = jk("j_b", 302); c2.ability.name = "Ice Cream"
  base({ c1, c2 })
  local ex = H({ intents = { { index = 1, tag = "SCALING" }, { index = 2, tag = "HOLD" } } })
  local msg = run(ex) or ""
  check("receipt names the tagged joker", msg:find("Green Joker", 1, true) ~= nil, msg)
  check("receipt names every tagged joker", msg:find("Ice Cream", 1, true) ~= nil, msg)
  check("receipt still carries index and tag", msg:find("1=SCALING", 1, true) ~= nil, msg)
end
do
  local c1 = jk("j_a", 401); c1.ability.name = "A"
  local c2 = jk("j_b", 402); c2.ability.name = "B"
  base({ c1, c2 })
  local payload = { intents = {
    { index = 1, tag = "CORE", note = "anchor" },
    { index = 2, tag = "HOLD" },
  } }
  local prepared = H(payload)
  check("tag receipt identity is not recorded during preparation",
    G.NEURO.joker_intents_ack_identity == nil)
  local first = run(prepared) or ""
  check("first semantic tag state gets the full receipt",
    first:find("Tagged:", 1, true) == 1, first)
  local repeated = run(H(payload)) or ""
  check("identical tag state resend gets the short receipt",
    repeated == "Tagged.", repeated)

  local changed_tag = run(H({ intents = {
    { index = 1, tag = "SCALING", note = "anchor" },
    { index = 2, tag = "HOLD" },
  } })) or ""
  check("a tag change restores the full receipt",
    changed_tag:find("Tagged:", 1, true) == 1, changed_tag)

  local changed_note = run(H({ intents = {
    { index = 1, tag = "SCALING", note = "new note" },
    { index = 2, tag = "HOLD" },
  } })) or ""
  check("a note change restores the full receipt",
    changed_note:find("Tagged:", 1, true) == 1, changed_note)

  G.jokers.cards[#G.jokers.cards + 1] = jk("j_c", 403)
  local changed_roster = run(H({ intents = {
    { index = 1, tag = "SCALING", note = "new note" },
  } })) or ""
  check("a roster change restores the full receipt",
    changed_roster:find("Tagged:", 1, true) == 1, changed_roster)
end

base({ jk("j_a", 101), jk("j_b", 102) })
local exec2 = H({ intents = { { index = 1, tag = "CORE" }, { index = 2, tag = "HOLD" } } })
run(exec2)

G.jokers.cards = { G.jokers.cards[2], G.jokers.cards[1] }
check("tag follows the card across reorder",
  G.NEURO.joker_intents[101].tag == "CORE" and G.NEURO.joker_intents[102].tag == "HOLD")

base({ jk("j_a", 101) })
run(H({ intents = { { index = 1, tag = "CHANGE" } } }))
check("CHANGE stored", G.NEURO.joker_intents[101].tag == "CHANGE")
run(H({ intents = { { index = 1, tag = "HOLD" } } }))
check("retagging replaces the previous tag", G.NEURO.joker_intents[101].tag == "HOLD")

base({ jk("j_a", 101) })
run(H({ intents = { { index = 1, tag = "CORE", note = "core xmult piece" } } }))
check("note stored alongside the tag", G.NEURO.joker_intents[101].note == "core xmult piece"
  and G.NEURO.joker_intents[101].tag == "CORE")
run(H({ intents = { { index = 1, tag = "HOLD" } } }))
check("retagging without a new note preserves the existing one",
  G.NEURO.joker_intents[101].note == "core xmult piece" and G.NEURO.joker_intents[101].tag == "HOLD")
run(H({ intents = { { index = 1, tag = "HOLD", note = "actually just a filler" } } }))
check("a new note overwrites the old one", G.NEURO.joker_intents[101].note == "actually just a filler")

run(H({ intents = { { index = 1, tag = "HOLD", note = "" } } }))
check("note=\"\" clears the note but keeps the tag",
  G.NEURO.joker_intents[101] ~= nil and G.NEURO.joker_intents[101].note == nil
  and G.NEURO.joker_intents[101].tag == "HOLD")

base({ jk("j_a", 101) })
run(H({ intents = { { index = 1, tag = "SCALING", note = "temp note" } } }))
check("note stored", G.NEURO.joker_intents[101].note == "temp note")
run(H({ intents = { { index = 1, tag = "SCALING", note = "   " } } }))
check("whitespace-only note also clears (trims to empty), tag survives",
  G.NEURO.joker_intents[101] ~= nil and G.NEURO.joker_intents[101].note == nil
  and G.NEURO.joker_intents[101].tag == "SCALING")

do
  local function utf8_length(text)
    local n = 0
    for i = 1, #text do
      local byte = text:byte(i)
      if byte < 0x80 or byte >= 0xC0 then n = n + 1 end
    end
    return n
  end

  base({ jk("j_a", 101), jk("j_b", 102) })
  local long = string.rep("x", 800)
  local exec_long, long_err = H({ intents = {
    { index = 1, tag = "HOLD", note = long },
    { index = 2, tag = "CORE" },
  } })
  check("an 800-character note is accepted", type(exec_long) == "function", tostring(long_err))
  local long_receipt = run(exec_long) or ""
  check("the stored note is the note as written, at full length",
    G.NEURO.joker_intents[101] and G.NEURO.joker_intents[101].note == long,
    G.NEURO.joker_intents[101] and utf8_length(G.NEURO.joker_intents[101].note))
  check("the long note's own tag still lands", G.NEURO.joker_intents[101].tag == "HOLD")
  check("the other joker in the same call is tagged too, instead of being thrown away",
    G.NEURO.joker_intents[102] and G.NEURO.joker_intents[102].tag == "CORE")
  check("the receipt echoes the note with no shortening clause",
    long_receipt:find("shortened", 1, true) == nil and long_receipt:find(long, 1, true) ~= nil,
    #long_receipt)

  base({ jk("j_a", 101) })
  local multibyte = string.rep("x", 120) .. "\196\133\196\153" -- U+0105, U+0119: two bytes each
  run(H({ intents = { { index = 1, tag = "SCALING", note = multibyte } } }))
  local stored = G.NEURO.joker_intents[101].note
  check("a multi-byte note is stored with every byte intact", stored == multibyte, stored)
  check("its character count is unchanged by storage", utf8_length(stored) == 122, utf8_length(stored))

  require("core.actions") -- populates the action registry read below
  local note_schema = require("core.action_registry")
    .get("record_joker_roles").schema.properties.intents.items.properties.note
  check("the note schema advertises no maxLength", note_schema.maxLength == nil, note_schema.maxLength)
  check("a 5000-character note passes schema validation",
    require("util.schema_validate").validate_value(note_schema, string.rep("z", 5000), "note") == true)
end

base({ jk("a", 1), jk("b", 2), jk("c", 3), jk("d", 4) })
for _, tag in ipairs({ "CORE", "SCALING", "HOLD", "CHANGE" }) do
  local ok_exec, ok_err = H({ intents = { { index = 1, tag = tag } } })
  check("tag '" .. tag .. "' is accepted", type(ok_exec) == "function", tostring(ok_err))
end
for _, dead_tag in ipairs({ "CUT", "KEEP", "FLEX", "MAYBE" }) do
  local _, dead_err = H({ intents = { { index = 1, tag = dead_tag } } })
  check("tag '" .. dead_tag .. "' is not valid",
    dead_err ~= nil and tostring(dead_err):find("Invalid tag", 1, true) ~= nil, dead_err)
end

base({ jk("j_a", 101), jk("j_b", 102) })
local exec_partial, err_partial = H({ intents = { { index = 1, tag = "CORE" } } })
check("partial tagging is allowed (the gate handles completeness)", type(exec_partial) == "function", tostring(err_partial))
run(exec_partial)
check("only the submitted joker got tagged",
  G.NEURO.joker_intents[101] ~= nil and G.NEURO.joker_intents[102] == nil)

base({ jk("j_a", 101) })
check("bad tag rejected", select(2, H({ intents = { { index = 1, tag = "MAYBE" } } })) ~= nil)
check("out-of-range index rejected", select(2, H({ intents = { { index = 9, tag = "CORE" } } })) ~= nil)
check("duplicate index rejected", select(2, H({ intents = { { index = 1, tag = "CORE" }, { index = 1, tag = "HOLD" } } })) ~= nil)
check("empty intents rejected", select(2, H({ intents = {} })) ~= nil)
base({})
check("no jokers rejected", select(2, H({ intents = { { index = 1, tag = "CORE" } } })) ~= nil)

base({ jk("j_e", 201, { eternal = true }) })
local exe = H({ intents = { { index = 1, tag = "CORE" } } })
check("Eternal joker tag accepted (not blocked at tag time)", type(exe) == "function")
run(exe)
check("Eternal joker tag stored", G.NEURO.joker_intents[201].tag == "CORE")

do
  local c = jk("j_a", 101); c.sell_cost = 3
  c.generate_UIBox_ability_table = function() return { name = "A", main = { { config = { text = "+4 Mult" } } }, info = {} } end
  _G.G = { NEURO = { joker_intents = { [101] = { tag = "CORE" } } },
    STATE = 1, STATES = { SHOP = 1 },
    jokers = { cards = { c }, config = { card_limit = 5 } } }
  local out = require("context.ctx_jokers").jokers_section() or ""
  local row1 = out:match("\n(1%. [^\n]+)")
  check("tag renders as 'your plan: CORE' on the row",
    row1 and row1:find("your plan: CORE", 1, true) ~= nil, row1)
  check("row stays a single well-formed line with the sell value",
    row1 and row1:find("(sell $3)", 1, true) ~= nil, row1)
  check("the tag is not injected into the flags column",
    row1 and row1:find("[CORE]", 1, true) == nil and row1:find("[core]", 1, true) == nil, row1)

  G.STATE = 2; G.STATES.BLIND_SELECT = 2
  local out2 = require("context.ctx_jokers").jokers_section() or ""
  local row2 = out2:match("\n(1%. [^\n]+)")
  check("tag renders outside SHOP too", row2 and row2:find("your plan: CORE", 1, true) ~= nil, row2)
end

do
  local c = jk("j_a", 101); c.sell_cost = 3
  c.generate_UIBox_ability_table = function() return { name = "A", main = { { config = { text = "+4 Mult" } } }, info = {} } end
  _G.G = { NEURO = { joker_intents = { [101] = { tag = "SCALING", note = "scaling piece, keep through ante 6" } } },
    STATE = 1, STATES = { SHOP = 1 },
    jokers = { cards = { c }, config = { card_limit = 5 } } }
  local out = require("context.ctx_jokers").jokers_section() or ""
  local row1 = out:match("\n(1%. [^\n]+)")
  check("note renders on the row in SHOP",
    row1 and row1:find("scaling piece, keep through ante 6", 1, true) ~= nil, row1)
  check("note is rendered after the tag",
    row1 and row1:find("your plan: SCALING", 1, true) < row1:find("your note:", 1, true), row1)

  G.NEURO.shop_visit_epoch = 99
  local out2 = require("context.ctx_jokers").jokers_section() or ""
  local row2 = out2:match("\n(1%. [^\n]+)")
  check("note is not shop-visit-scoped", row2 and row2:find("scaling piece", 1, true) ~= nil, row2)

  G.STATE = 2; G.STATES.BLIND_SELECT = 2
  local out3 = require("context.ctx_jokers").jokers_section() or ""
  local row3 = out3:match("\n(1%. [^\n]+)")
  check("note does not render outside SHOP", row3 and row3:find("scaling piece", 1, true) == nil, row3)
  check("tag still renders outside SHOP alongside a hidden note",
    row3 and row3:find("your plan: SCALING", 1, true) ~= nil, row3)
end

do
  local function jkc(sid, note_len)
    local c = jk("j" .. sid, sid); c.sell_cost = 3
    c.generate_UIBox_ability_table = function() return { name = "J" .. sid, main = { { config = { text = "+4 Mult" } } }, info = {} } end
    return c, string.rep(tostring(sid), note_len)
  end
  local c1, n1 = jkc(1, 60)
  local c2, n2 = jkc(2, 60)
  local c3, n3 = jkc(3, 400)
  _G.G = {
    NEURO = { joker_intents = {
      [1] = { tag = "CORE", note = n1 }, [2] = { tag = "HOLD", note = n2 }, [3] = { tag = "CHANGE", note = n3 },
    } },
    STATE = 1, STATES = { SHOP = 1 },
    jokers = { cards = { c1, c2, c3 }, config = { card_limit = 5 } },
  }
  local out = require("context.ctx_jokers").jokers_section() or ""
  check("first joker's note renders", out:find(n1, 1, true) ~= nil, out)
  check("second joker's note renders", out:find(n2, 1, true) ~= nil, out)
  check("the last note renders in full even though the three together run to 520 chars",
    out:find(n3, 1, true) ~= nil, #out)
  check("every note is rendered verbatim, not shortened", G.NEURO.joker_intents[3].note == n3)
  check("the tag of the longest-note joker still renders",
    out:find("your plan: CHANGE", 1, true) ~= nil, out)
end

done()
