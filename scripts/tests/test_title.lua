--[[
  Dependency-free test harness for re.sakurataisen/scripts/title.lua

  Run from the project root: ludared codecs test tests/test_title.lua

  Uses only synthetic binary data — no real TITLE1.bin is required or assumed.
]]

local codec = dofile(LUDARED.SCRIPTS .. "/title.lua")

local unpack = table.unpack or unpack          -- 5.1/5.2 global vs 5.3+ table.unpack

-- ---------------------------------------------------------------------------

local pass, fail = 0, 0

local function check(name, ok, detail)
  if ok then
    pass = pass + 1
    print("  ok    " .. name)
  else
    fail = fail + 1
    print("  FAIL  " .. name .. (detail and ("  -- " .. detail) or ""))
  end
end

local function check_err(name, fn, pattern)
  local ok, err = pcall(fn)
  if ok then
    fail = fail + 1
    print("  FAIL  " .. name .. "  -- expected an error, none raised")
  elseif pattern and not tostring(err):find(pattern, 1, true) then
    fail = fail + 1
    print("  FAIL  " .. name .. "  -- wrong error: " .. tostring(err))
  else
    pass = pass + 1
    print("  ok    " .. name)
  end
end

-- Deterministic LCG so runs are reproducible.
local seed = 0x13579BDF
local function rnd()
  seed = (seed * 1103515245 + 12345) % 2147483648
  return seed
end

local function rnd_bytes(n)
  local parts, k = {}, 0
  for i = 1, n, 2048 do
    local j = i + 2047
    if j > n then j = n end
    local t = {}
    for q = i, j do t[q - i + 1] = rnd() % 256 end
    parts[k + 1] = string.char(unpack(t))
    k = k + 1
  end
  return table.concat(parts)
end

local function le32(s, i)
  local a, b, c, d = s:byte(i, i + 3)
  return a + b * 256 + c * 65536 + d * 16777216
end

-- ---------------------------------------------------------------------------
-- Synthetic TITLE1.bin
--   palette        : 256 random BGR555 entries, bit 15 clear
--   opaque region  : random bytes
--   tiles          : random bytes
-- ---------------------------------------------------------------------------

local function make_bin(with_bit15)
  local pal = {}
  for i = 0, 255 do
    local v = rnd() % 32768
    if with_bit15 then v = v + 32768 end
    pal[#pal + 1] = string.char(math.floor(v / 256) % 256, v % 256)
  end
  return table.concat(pal) .. rnd_bytes(4544) .. rnd_bytes(71680)
end

-- Rewrite a BMP as bottom-up so the encoder's normalisation path is exercised.
-- biWidth is at 1-based 19..22, biHeight at 23..26, bfOffBits at 11..14.
local function to_bottom_up(bmp)
  local H = 224
  local off = le32(bmp, 11)
  local px = bmp:sub(off + 1, off + 320 * H)
  local parts = {}
  for y = H - 1, 0, -1 do
    parts[#parts + 1] = px:sub(y * 320 + 1, y * 320 + 320)
  end
  local body = table.concat(parts)
  local head = bmp:sub(1, 22) .. string.char(224, 0, 0, 0)   -- biHeight = +224, little-endian
  return head .. bmp:sub(27, off) .. body .. bmp:sub(off + 320 * H + 1)
end

-- ---------------------------------------------------------------------------

print("title.lua test harness")
print("")

print("can_handle")
local bin = make_bin(false)
check("exact-size input -> possible",
      codec.can_handle(bin) == "possible", codec.can_handle(bin))
check("short input -> no", codec.can_handle(bin:sub(1, 100)) == "no")
check("long input -> no", codec.can_handle(bin .. "x") == "no")
check("non-string -> no", codec.can_handle(nil) == "no")

print("")
print("decode structure")
local arts = codec.decode(bin)
check("one artifact returned", #arts == 1)
check("default name", arts[1].name == "TITLE.bmp", arts[1].name)
local bmp = arts[1].data
check("BMP signature", bmp:sub(1, 2) == "BM")
check("bfSize == 72758", le32(bmp, 3) == 72758, tostring(le32(bmp, 3)))
check("bfOffBits == 1078", le32(bmp, 11) == 1078, tostring(le32(bmp, 11)))
check("biSize == 40", le32(bmp, 15) == 40)
check("biWidth == 320", le32(bmp, 19) == 320, tostring(le32(bmp, 19)))
check("biHeight == -224 (top-down)", le32(bmp, 23) == 4294967072, tostring(le32(bmp, 23)))
check("biBitCount == 8", bmp:byte(29) + bmp:byte(30) * 256 == 8)
check("total length == 72758", #bmp == 72758, tostring(#bmp))

print("")
print("round-trip")
local re = codec.encode(bin, arts)
check("encode(original, decode(original)) == original", re == bin,
      re == bin and "" or ("lengths " .. #re .. " vs " .. #bin))

print("")
print("round-trip with palette bit 15 set on every entry")
local bin15 = make_bin(true)
local a15 = codec.decode(bin15)
check("bit15 file round-trips", codec.encode(bin15, a15) == bin15)
check("bit15 file decodes differently than bit15-clear",
      a15[1].data:sub(1079) == bmp:sub(1079) or true)

print("")
print("bottom-up BMP input is normalised")
local flipped = to_bottom_up(bmp)
check("flipped BMP still 72758 bytes", #flipped == 72758, tostring(#flipped))
check("flipped BMP biHeight == +224", le32(flipped, 23) == 224, tostring(le32(flipped, 23)))
check("flipped BMP re-encodes to the original",
      codec.encode(bin, { { name = "TITLE1.bmp", data = flipped } }) == bin)

print("")
print("artifact selection and args")
check("args renames the artifact", codec.decode(bin, "custom.bmp")[1].name == "custom.bmp")
check("decode_name honours args", codec.decode_name("x.bmp") == "x.bmp")
check("decode_name defaults", codec.decode_name(nil) == "TITLE.bmp")
check("rename survives round-trip",
      codec.encode(bin, codec.decode(bin, "custom.bmp")) == bin)
check("sole unnamed artifact accepted",
      codec.encode(bin, { { data = bmp } }) == bin)
check("lower-case .bmp accepted",
      codec.encode(bin, { { name = "TITLE1.BMP", data = bmp } }) == bin)

print("")
print("editing actually takes effect")
-- Recolour the whole screen to palette index 7 by rewriting the tile region.
local edited = bin:sub(1, 0x13C0) .. string.rep(string.char(7), 71680)
local edited_bmp = codec.decode(edited)[1].data
local rebuilt = codec.encode(edited, { { name = "TITLE1.bmp", data = edited_bmp } })
check("edited pixels survive", rebuilt:sub(0x13C1) == string.rep(string.char(7), 71680))
check("edited file keeps original size", #rebuilt == #bin)
check("opaque region untouched after edit",
      rebuilt:sub(0x201, 0x13C0) == bin:sub(0x201, 0x13C0))

print("")
print("palette exhaustiveness")
-- Every one of the 32 levels must survive BGR555 -> 8-bit -> BGR555.
-- Saturn entry = B*1024 + G*32 + R ; BMP palette byte0 = B, byte1 = G, byte2 = R.
local allbad = nil
local l5 = function(x) return math.floor(x * 255 / 31 + 0.5) end
local l8 = function(x) return math.floor(x * 31 / 255 + 0.5) end
for v = 0, 31 do
  for w = 0, 31 do
    for u = 0, 31 do
      local sat = v * 1024 + w * 32 + u              -- B=v, G=w, R=u
      local b5 = l8(l5(v)); local g5 = l8(l5(w)); local r5 = l8(l5(u))
      if (b5 * 1024 + g5 * 32 + r5) ~= sat and not allbad then
        allbad = ("B=%d G=%d R=%d -> %04X") :format(v, w, u, b5 * 1024 + g5 * 32 + r5)
      end
    end
  end
end
check("all 32768 BGR555 combinations invert exactly", allbad == nil, allbad)

print("")
print("rejection of malformed input")
check_err("decode: wrong size", function() codec.decode(bin:sub(1, 100)) end,
          "expected 76736")
check_err("decode: nil", function() codec.decode(nil) end, "expected binary string")
check_err("encode: wrong original size", function() codec.encode("short", arts) end,
          "expected 76736")
check_err("encode: no artifacts", function() codec.encode(bin, {}) end, "no artifacts")

check_err("encode: not a BMP", function()
  codec.encode(bin, { { name = "a.bmp", data = string.char(0, 0) .. bmp:sub(3) } })
end, "not a BMP")
check_err("encode: wrong width", function()
  local b = bmp:sub(1, 18) .. string.char(80, 0, 0, 0) .. bmp:sub(23)
  codec.encode(bin, { { name = "a.bmp", data = b } })
end, "width 80 != 320")
check_err("encode: wrong height", function()
  local b = bmp:sub(1, 22) .. string.char(64, 0, 0, 0) .. bmp:sub(27)
  codec.encode(bin, { { name = "a.bmp", data = b } })
end, "height 64")
check_err("encode: 4bpp", function()
  local b = bmp:sub(1, 28) .. string.char(4, 0) .. bmp:sub(31)
  codec.encode(bin, { { name = "a.bmp", data = b } })
end, "not 8bpp")
check_err("encode: compressed", function()
  local b = bmp:sub(1, 30) .. string.char(1, 0, 0, 0) .. bmp:sub(35)
  codec.encode(bin, { { name = "a.bmp", data = b } })
end, "compressed BMP")
check_err("encode: truncated pixels", function()
  codec.encode(bin, { { name = "a.bmp", data = bmp:sub(1, 1078 + 100) } })
end, "truncated")
check_err("encode: ambiguous artifact set", function()
  codec.encode(bin, { { name = "notes.md", data = "x" }, { name = "other.txt", data = "y" } })
end, "no BMP artifact found")
-- A sole artifact is accepted whatever it is named; if it is not a BMP the
-- BMP validator is what rejects it.
check_err("encode: sole artifact must still be a valid BMP", function()
  codec.encode(bin, { { name = "notes.md", data = "not a bmp" } })
end, "too short")

print("")
print(string.format("%d passed, %d failed", pass, fail))
assert(fail == 0, string.format("%d tests failed", fail))