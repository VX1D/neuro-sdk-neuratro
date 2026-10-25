local check, done = require("tests.helpers").harness("outbox_rotation_fence")

_G.G = nil
local Bridge = require("core.bridge")
local TmpWork = require("tests.tmp_workdir")

local bit = require("bit")
local U64 = require("ffi").typeof("uint64_t")
local PRIME = U64(0x100000000) * 0x100 + 0x1b3
local OFFSET = U64(0xcbf29ce4) * 0x100000000 + 0x84222325
local CHUNK = 64 * 1024

local function mix(h, w) return bit.bxor(h, w) * PRIME end

local function word_at(bytes, i)
  local w = U64(0)
  for k = 7, 0, -1 do w = w * 256 + (bytes:byte(i + k) or 0) end
  return w
end

local function update_words(h, bytes)
  h = mix(h, U64(#bytes))
  for i = 1, #bytes, 8 do h = mix(h, word_at(bytes, i)) end
  return h
end

local function u64_le(w)
  local out = {}
  for i = 1, 8 do out[i] = string.char(tonumber(w % 256)); w = w / 256 end
  return table.concat(out)
end

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function write(path, s)
  local f = assert(io.open(path, "wb"))
  f:write(s)
  f:close()
end

local function size(path)
  local s = read(path)
  return s and #s or nil
end

local function samples(len)
  return len <= 2 * CHUNK and { { 0, len } } or { { 0, CHUNK }, { len - CHUNK, CHUNK } }
end

local function fingerprint(bytes, pos, len)
  local h = mix(mix(OFFSET, U64(pos)), U64(len))
  for _, s in ipairs(samples(len)) do
    h = update_words(mix(h, U64(s[1])), bytes:sub(s[1] + 1, s[1] + s[2]))
  end
  return h
end

local MAGIC = word_at("NBCURSOR", 1)

local function record(pos, len, fp)
  local words = { MAGIC, U64(pos), U64(len), U64(1), U64(2), fp }
  local sum = OFFSET
  for _, w in ipairs(words) do sum = mix(sum, w) end
  words[7] = sum
  local out = {}
  for i, w in ipairs(words) do out[i] = u64_le(w) end
  return table.concat(out)
end

local function cursor_for(path, pos, len)
  return record(pos, len, fingerprint(read(path), pos, len))
end

local function fixture(n)
  local out = {}
  for i = 0, n - 1 do out[#out + 1] = string.char((i * 131 + 17) % 256) end
  return table.concat(out)
end
local FIXTURES = {
  { len = 4096, pos = 1000, hex = "175bc90c14ff821d" },
  { len = 200000, pos = 150000, hex = "71a204fd616e5a6d" },
}

local function from_hex(hex)
  return (hex:gsub("%s", ""):gsub("..", function(b) return string.char(tonumber(b, 16)) end))
end

do
  for _, fx in ipairs(FIXTURES) do
    local bytes = fixture(fx.len)
    local h = fingerprint(bytes, fx.pos, fx.len)
    check("the test's fingerprint of the " .. fx.len .. "-byte fixture is the relay's constant",
      bit.tohex(h, 16) == fx.hex, bit.tohex(h, 16))
  end
end

local RELAY_FIXTURE = from_hex(assert(read("../neuro-bridge-rs/src/cursor_fixture.hex"), "relay cursor fixture"))

do
  local bytes = fixture(200000)
  check("the test's encoder reproduces the relay's cursor bytes",
    record(120000, 200000, fingerprint(bytes, 120000, 200000)) == RELAY_FIXTURE)
end

local function rotation_kept(dir, rotated_bytes, cursor)
  local out = dir .. "/neuro_outbox.jsonl"
  write(out, string.rep("y", 99) .. "\n")
  write(out .. ".1", rotated_bytes)
  write(out .. ".cursor", cursor)
  local b = Bridge:new({ enabled = true, fs_dir = dir })
  b.MAX_OUTBOX_FILE_BYTES = 150
  b:_append(string.rep("z", 99) .. "\n")
  return read(out .. ".1") == rotated_bytes
end

do
  local dir = TmpWork.open("outbox_rotation_fixture")
  for _, fx in ipairs(FIXTURES) do
    local bytes = fixture(fx.len)
    local want = U64(0)
    for i = 1, 16, 2 do want = want * 256 + tonumber(fx.hex:sub(i, i + 1), 16) end
    for _, case in ipairs({ { fp = want, defers = true }, { fp = want + 1, defers = false } }) do
      local kept = rotation_kept(dir, bytes, record(fx.pos, fx.len, case.fp))
      check(string.format("mod fence on the %d-byte fixture, %s fingerprint: %s", fx.len,
        case.defers and "matching" or "wrong", case.defers and "defers" or "rotates"),
        kept == case.defers, tostring(kept))
    end
  end

  local bytes = fixture(200000)
  local function tear(s) return s:sub(1, 40) .. string.char((s:byte(41) + 1) % 256) .. s:sub(42) end
  for _, case in ipairs({
    { name = "the relay's file: its cursor is inside .1", cursor = RELAY_FIXTURE, defers = true },
    { name = "a drained cursor at the end of .1", cursor = record(200000, 200000, fingerprint(bytes, 200000, 200000)), defers = false },
    { name = "a torn cursor: no cursor", cursor = tear(RELAY_FIXTURE), defers = false },
    { name = "a truncated file: no cursor", cursor = RELAY_FIXTURE:sub(1, 55), defers = false },
  }) do
    local kept = rotation_kept(dir, bytes, case.cursor)
    check(case.name .. (case.defers and " (defers)" or " (rotates)"), kept == case.defers, tostring(kept))
  end
end

do
  local dir = TmpWork.open("outbox_rotation")
  local out = dir .. "/neuro_outbox.jsonl"
  write(out, "")
  local b = Bridge:new({ enabled = true, fs_dir = dir })
  local CAP = 300 * 1024
  b.MAX_OUTBOX_FILE_BYTES = CAP
  local line = string.rep("x", 1000) .. "\n"
  local seq = 0
  local function fill()
    for _ = 1, 400 do
      seq = seq + 1
      b:_append(string.format("%08d", seq) .. line:sub(9))
    end
  end

  fill()
  check("first rotation happens without a cursor", size(out .. ".1") ~= nil)
  local rotated_size = size(out .. ".1")

  write(out .. ".cursor", cursor_for(out .. ".1", 1000, rotated_size))
  local rotated = read(out .. ".1")
  fill(); fill()
  check("rotation deferred while the relay's cursor is inside unread .1", read(out .. ".1") == rotated)
  check("frames keep appending to the live outbox past the limit", size(out) > CAP, size(out))

  write(out .. ".cursor", cursor_for(out .. ".1", 500, 200 * 1024))
  b:_append(line)
  check("a late checkpoint that covers only part of .1 still defers", read(out .. ".1") == rotated)

  write(out .. ".cursor", cursor_for(out .. ".1", rotated_size, rotated_size))
  local live = size(out)
  b:_append(line)
  check("rotation resumes once .1 is fully drained",
    size(out .. ".1") == live and size(out) == #line, tostring(size(out .. ".1")) .. "/" .. size(out))

  fill()
  write(out .. ".cursor", cursor_for(out, 10, size(out)))
  b:_append("MARK\n")
  fill()
  check("a cursor on the live outbox does not block rotation",
    (read(out .. ".1") or ""):find("MARK", 1, true) ~= nil)

  write(out .. ".cursor", "junk")
  local before = size(out)
  fill()
  check("an unreadable cursor keeps plain rotation", size(out) < before + 400 * #line, size(out))
end

TmpWork.close()
done()
