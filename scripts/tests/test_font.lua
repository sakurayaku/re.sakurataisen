--[[
  Dependency-free test harness for re.sakurataisen/scripts/font.lua

  Run from the project root: ludared codecs test tests/test_font.lua

  Uses only synthetic binary data — no real KNJ/BIN is required or assumed.
]]

local codec = dofile(LUDARED.SCRIPTS .. "/font.lua")

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

local function le16(s, i)
  local a, b = s:byte(i, i + 1)
  return a + b * 256
end

-- ---------------------------------------------------------------------------
-- Synthetic KNJ font file
--   No embedded palette (palette is external)
--   Tiles: random bytes (multiple of 128)
-- ---------------------------------------------------------------------------

local TILE_SIZE = 128
-- Use 629 tiles like the real 0100KNJ.BIN to get 40 pages
local NUM_TILES = 629
local TILE_DATA_SIZE = NUM_TILES * TILE_SIZE

local function make_knj()
  return rnd_bytes(TILE_DATA_SIZE)
end

-- Helper to extract BMP header fields
local function get_bmp_header(bmp)
  return {
    signature = bmp:sub(1, 2),
    file_size = le32(bmp, 3),
    off_bits = le32(bmp, 11),
    info_size = le32(bmp, 15),
    width = le32(bmp, 19),
    height = le32(bmp, 23),
    planes = le16(bmp, 27),
    bit_count = le16(bmp, 29),
    compression = le32(bmp, 31),
    image_size = le32(bmp, 35),
  }
end

-- ---------------------------------------------------------------------------

print("font.lua test harness")
print("")

print("can_handle")
local bin = make_knj()
check("exact-size input (multiple of 128) -> likely",
      codec.can_handle(bin) == "likely", codec.can_handle(bin))
check("short input -> no", codec.can_handle(bin:sub(1, 100)) == "no")
check("long input -> no", codec.can_handle(bin .. "x") == "no")
check("non-string -> no", codec.can_handle(nil) == "no")
check("size not multiple of 128 -> no", codec.can_handle("x") == "no")
check("size 160 (128+32) -> no", codec.can_handle(string.rep("x", 160)) == "no")

print("")
print("decode structure")
local arts = codec.decode(bin)
-- 629 tiles / 16 = 39.3 pages = 40 pages + 1 metadata = 41 artifacts
check("41 artifacts returned (40 pages + metadata)", #arts == 41)
check("last artifact is metadata", arts[41].name == "font.meta.json")
local bmp = arts[1].data
local hdr = get_bmp_header(bmp)
check("BMP signature", hdr.signature == "BM")
check("biWidth == 256", hdr.width == 256)
check("biHeight == -16 (top-down)", hdr.height == 4294967280)  -- -16 as u32
check("biBitCount == 4", hdr.bit_count == 4)
check("biCompression == 0", hdr.compression == 0)
check("biPlanes == 1", hdr.planes == 1)

print("")
print("round-trip")
local re = codec.encode(bin, arts)
check("encode(original, decode(original)) == original", re == bin,
      re == bin and "" or ("lengths " .. #re .. " vs " .. #bin))

print("")
print("artifact selection and args")
-- Font codec generates page names automatically, args only affects decode_name default
check("decode_name honours args", codec.decode_name("x.bmp") == "x.bmp")
check("decode_name defaults", codec.decode_name(nil) == "FONT_00.bmp")
check("rename survives round-trip (via decode_name)",
      codec.encode(bin, codec.decode(bin, "custom.bmp")) == bin)

print("")
print("editing actually takes effect")
-- Recolour first tile to palette index 7 by rewriting the first 128 bytes
local edited = string.rep(string.char(7), TILE_SIZE) .. bin:sub(TILE_SIZE + 1)
local edited_arts = codec.decode(edited)
local rebuilt = codec.encode(edited, edited_arts)
check("edited pixels survive", rebuilt == edited)
check("edited file keeps original size", #rebuilt == #bin)

print("")
print("palette visibility")
local bmp_arts_pv = codec.decode(bin)
local bmp_check = bmp_arts_pv[1].data
local infoLen_pv = le32(bmp_check, 15)
local off_bits_pv = le32(bmp_check, 11)
local pal_off_pv = 14 + infoLen_pv + 1
local has_nonblack_pv = false
for i = 0, 15 do
  local o = pal_off_pv + i * 4
  if o + 2 < off_bits_pv then
    local b = bmp_check:byte(o)
    local g = bmp_check:byte(o + 1)
    local r = bmp_check:byte(o + 2)
    if b ~= 0 or g ~= 0 or r ~= 0 then
      has_nonblack_pv = true
      break
    end
  end
end
check("generated BMP has visible (non-black) palette", has_nonblack_pv)

print("")
print("rejection of malformed input")
check_err("decode: wrong size", function() codec.decode(bin:sub(1, 100)) end,
          "file size not multiple of 128")
check_err("decode: nil", function() codec.decode(nil) end, "expected binary string")
check_err("encode: wrong original size", function() codec.encode("short", arts) end,
          "size not multiple of 128")
check_err("encode: no artifacts", function() codec.encode(bin, {}) end, "no artifacts")

-- These tests require a metadata artifact first, so they error on "no metadata artifact found"
check_err("encode: not a BMP", function()
  codec.encode(bin, { { name = "a.bmp", data = string.char(0, 0) .. bmp:sub(3) } })
end, "no metadata artifact found")
check_err("encode: wrong width", function()
  local b = bmp:sub(1, 18) .. string.char(80, 0, 0, 0) .. bmp:sub(23)
  codec.encode(bin, { { name = "a.bmp", data = b } })
end, "no metadata artifact found")
check_err("encode: wrong height", function()
  local b = bmp:sub(1, 22) .. string.char(64, 0, 0, 0) .. bmp:sub(27)
  codec.encode(bin, { { name = "a.bmp", data = b } })
end, "no metadata artifact found")
check_err("encode: not 4bpp", function()
  local b = bmp:sub(1, 28) .. string.char(8, 0) .. bmp:sub(31)
  codec.encode(bin, { { name = "a.bmp", data = b } })
end, "no metadata artifact found")
check_err("encode: compressed", function()
  local b = bmp:sub(1, 30) .. string.char(1, 0, 0, 0) .. bmp:sub(35)
  codec.encode(bin, { { name = "a.bmp", data = b } })
end, "no metadata artifact found")
check_err("encode: truncated pixels", function()
  codec.encode(bin, { { name = "a.bmp", data = bmp:sub(1, hdr.off_bits + 100) } })
end, "no metadata artifact found")
check_err("encode: ambiguous artifact set", function()
  codec.encode(bin, { { name = "notes.md", data = "x" }, { name = "other.txt", data = "y" } })
end, "no metadata artifact found")
check_err("encode: sole artifact must still be a valid BMP", function()
  codec.encode(bin, { { name = "notes.md", data = "not a bmp" } })
end, "no metadata artifact found")

print("")
print(string.format("%d passed, %d failed", pass, fail))
assert(fail == 0, string.format("%d tests failed", fail))