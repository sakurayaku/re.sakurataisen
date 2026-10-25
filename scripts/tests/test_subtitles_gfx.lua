--[[
  Test harness for subtitles_gfx.lua

  Run from the project root: ludared codecs test tests/test_subtitles_gfx.lua
]]

local prs = LUDARED.codec("std/sega/compression/prs")
local codec = dofile(LUDARED.SCRIPTS .. "/subtitles_gfx.lua")

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

local PRS_OFFSET  = 0x000196d8
local PAL_OFFSET  = 0x00019578
local DMA_OFFSET  = 0x00000c06
local SHIPPED_DMA = 0x4580
local BLOCK_SIZE  = 12673
local FILE_SIZE   = 243200

local DIMS = {
  {160, 16}, {112, 16}, {128, 16}, {144, 16}, {112, 16}, {112, 16},
  {128, 16}, {144, 16}, {176, 16}, {96, 16},  {144, 16}, {160, 16},
  {112, 16}, {144, 16}, {112, 16}, {128, 16}, {112, 16},
}

-- A recognisable pattern: gradient blocks with a "text" stripe, drawn
-- symmetrically (from x=5 to w-6) the way subtitle art is: encode() must leave
-- the block untouched.
local function make_image_block()
  local parts = {}
  for i = 1, #DIMS do
    local w, h = DIMS[i][1], DIMS[i][2]
    local row = {}
    for x = 0, w // 2 - 1 do
      local function nibble(v)
        return (v >= 5 and v <= w - 6) and ((v * 7 + i) % 15 + 1) or 0
      end
      row[#row + 1] = string.char((nibble(x * 2) << 4) | nibble(x * 2 + 1))
    end
    local row_bytes = table.concat(row)
    local image = {}
    for y = 0, h - 1 do
      if y >= 6 and y <= 9 then
        image[#image + 1] = row_bytes
      else
        image[#image + 1] = string.rep("\x00", w // 2)
      end
    end
    parts[i] = table.concat(image)
  end
  return table.concat(parts)
end

local function make_palette()
  local entries = {}
  for i = 0, 15 do
    local value = (i * 0x631) & 0x7FFF
    entries[i + 1] = string.pack(">I2", value)
  end
  return table.concat(entries)
end

local function make_logo(block)
  local compressed = prs:encode("", { { name = "DECOMPRESSED", data = block } })
  assert(#compressed <= BLOCK_SIZE, "test fixture no longer fits the block")
  compressed = compressed .. string.rep("\x00", BLOCK_SIZE - #compressed)

  local data = string.rep("\x00", FILE_SIZE)
  data = data:sub(1, PAL_OFFSET) .. make_palette() .. data:sub(PAL_OFFSET + 33)
  data = data:sub(1, PRS_OFFSET) .. compressed .. data:sub(PRS_OFFSET + BLOCK_SIZE + 1)
  -- The shipped transfer length, sitting in export #6's literal pool.
  data = data:sub(1, DMA_OFFSET) .. string.pack(">I2", SHIPPED_DMA)
    .. data:sub(DMA_OFFSET + 3)
  return data
end

local function bmp_fields(bmp)
  local off, info_len, width, height, planes, bpp, comp =
    string.unpack("<I4I4i4i4I2I2I4", bmp, 11)
  return {
    off = off, info_len = info_len, width = width, height = height,
    planes = planes, bpp = bpp, comp = comp,
    bits = bmp:sub(off + 1),
    pal = bmp:sub(15 + info_len, off),
  }
end

local function bmp_pixels(bmp, width, height)
  local f = bmp_fields(bmp)
  local stride = ((width * 4 + 31) // 32) * 4
  local rows = {}
  for y = 0, height - 1 do
    rows[y + 1] = bmp:sub(f.off + y * stride + 1, f.off + y * stride + width // 2)
  end
  if f.height > 0 then
    local flipped = {}
    for y = 1, height do
      flipped[y] = rows[height - y + 1]
    end
    rows = flipped
  end
  return table.concat(rows)
end

-- Turn a top-down BMP into a bottom-up one (as many editors write).
local function make_bottom_up(bmp, width, height)
  local f = bmp_fields(bmp)
  local stride = ((width * 4 + 31) // 32) * 4
  local rows = {}
  for y = 0, height - 1 do
    rows[y + 1] = bmp:sub(f.off + y * stride + 1, f.off + y * stride + stride)
  end
  local flipped = {}
  for y = 1, height do
    flipped[y] = rows[height - y + 1]
  end

  local header = bmp:sub(1, 22) .. string.pack("<i4", height) .. bmp:sub(27, f.off)
  return header .. table.concat(flipped)
end

print("subtitles_gfx.lua test harness")
print("")

local block = make_image_block()
local logo = make_logo(block)
local palette = make_palette()

check("can_handle returns possible", codec.can_handle(logo) == "possible")
check("can_handle rejects short input", codec.can_handle("BM") == "no")

local artifacts = codec.decode(logo)
check("decode returns 17 artifacts", #artifacts == 17)

-- decode must reproduce the stored pixels exactly
local offset = 0
local pixels_ok, names_ok, palette_ok = true, true, true
for i = 1, #DIMS do
  local w, h = DIMS[i][1], DIMS[i][2]
  local size = (w * h) // 2
  local expected = block:sub(offset + 1, offset + size)
  offset = offset + size

  local artifact = artifacts[i]
  local name = string.format("SUBTITLES/%02d.bmp", i - 1)
  if artifact.name ~= name then
    names_ok = false
  end

  local f = bmp_fields(artifact.data)
  if f.width ~= w or f.height ~= -h or f.bpp ~= 4 or f.comp ~= 0 then
    pixels_ok = false
  elseif bmp_pixels(artifact.data, w, h) ~= expected then
    pixels_ok = false
  end
end
check("artifact names are SUBTITLES/00..16", names_ok)
check("decoded BMPs are top-down 4bpp with the block's pixels", pixels_ok)

-- palette must be the Saturn palette, converted to BGRA
local pal = bmp_fields(artifacts[1].data).pal
local pal_ok = true
for i = 0, 15 do
  local c = string.unpack(">I2", palette, 1 + i * 2) & 0x7FFF
  local b = ((c >> 10) * 255 + 15) // 31
  local g = (((c >> 5) & 0x1F) * 255 + 15) // 31
  local r = ((c & 0x1F) * 255 + 15) // 31
  if pal:byte(i * 4 + 1) ~= b or pal:byte(i * 4 + 2) ~= g or pal:byte(i * 4 + 3) ~= r then
    pal_ok = false
  end
end
check("decoded BMP palette matches the LOGO.SH2 palette", pal_ok)

-- unchanged artifacts must round-trip byte for byte
check("encode(decode(original)) == original", codec.encode(logo, artifacts) == logo)

-- a single changed pixel must be written back and nothing else disturbed
local edited = {}
for i = 1, #artifacts do
  edited[i] = { name = artifacts[i].name, data = artifacts[i].data }
end
local w, h = DIMS[1][1], DIMS[1][2]
local first = bmp_fields(edited[1].data)
local stride = ((w * 4 + 31) // 32) * 4
-- Row 6 is inside the stripe, so the edit stays clear of the image's edges.
local patched_bmp = edited[1].data:sub(1, first.off + 6 * stride + 3)
  .. "\xF7"
  .. edited[1].data:sub(first.off + 6 * stride + 5)
edited[1].data = patched_bmp

local patched = codec.encode(logo, edited)
check("encode keeps the file size", #patched == #logo)
check("encode leaves the palette untouched",
  patched:sub(PAL_OFFSET + 1, PAL_OFFSET + 32) == palette)

local new_block = prs:decode(patched:sub(PRS_OFFSET + 1, PRS_OFFSET + BLOCK_SIZE))[1].data
-- replace the 4th byte of row 6
local expected_block = block:sub(1, 6 * (w // 2) + 3) .. "\xF7" .. block:sub(6 * (w // 2) + 5)
check("encode writes the edited pixels", new_block == expected_block,
  string.format("block %d bytes", #new_block))
check("encode keeps everything after the block", 
  patched:sub(PRS_OFFSET + BLOCK_SIZE + 1) == logo:sub(PRS_OFFSET + BLOCK_SIZE + 1))

-- bottom-up BMPs (positive height) must decode to the same pixels
local bottom_up = {}
for i = 1, #artifacts do
  bottom_up[i] = {
    name = artifacts[i].name,
    data = make_bottom_up(artifacts[i].data, DIMS[i][1], DIMS[i][2]),
  }
end
check("bottom-up BMPs encode identically", codec.encode(logo, bottom_up) == logo)

-- malformed input must fail loudly instead of writing zeros
check_err("missing artifact is an error", function()
  local short = { edited[1] }
  codec.encode(logo, short)
end, "missing")

-- A subtitle may be resized.  The block layout follows the BMPs, not a
-- constant: PatchSubtitles rewrites SAKURA:0xa20c from the image it converts.
local function make_bmp(width, height, pixels, pal)
  local stride = ((width * 4 + 31) // 32) * 4
  local size = stride * height
  local off = 54 + 64
  local hdr = string.pack("<c2I4I2I2I4I4i4i4I2I2I4I4I4I4I4I4",
    "BM", off + size, 0, 0, off, 40, width, -height, 1, 4, 0, size, 0, 0, 16, 0)
  return hdr .. pal .. pixels
end

local resized = {}
for i = 1, #artifacts do
  resized[i] = { name = artifacts[i].name, data = artifacts[i].data }
end
-- The fixture is the original 17,792-byte layout, which leaves only 640 bytes
-- free inside the engine's 18,432-byte staging window.  Blank the last slot to
-- make room for the growth this case asserts.
local STUB = make_bmp(8, 2, string.rep("\x00", 8), bmp_fields(artifacts[1].data).pal)
resized[17].data = STUB

-- Slot 1 is 112 px wide, and the engine anchors it at screen x = 160 - 112/2
-- = 104, so 112 px is the widest art that can be centred there.  Two lines fit
-- in the same width by doubling the height.
local BIG_W, BIG_H = 112, 32
local big_rows = {}
for y = 0, BIG_H - 1 do
  big_rows[y + 1] = string.rep(string.char(0x50 + (y % 8)), BIG_W // 2)
end
local big_pixels = table.concat(big_rows)
resized[2].data = make_bmp(BIG_W, BIG_H, big_pixels, bmp_fields(artifacts[1].data).pal)

local resized_out = codec.encode(logo, resized)
local resized_block = prs:decode(
  resized_out:sub(PRS_OFFSET + 1, PRS_OFFSET + BLOCK_SIZE))[1].data
local head = block:sub(1, 160 * 16 // 2)
local tail = block:sub(160 * 16 // 2 + 112 * 16 // 2 + 1, #block - 112 * 16 // 2)
  .. string.rep("\x00", 8)
check("a resized BMP grows the block to the new size",
  #resized_block == #head + #big_pixels + #tail,
  string.format("block %d bytes", #resized_block))
check("images before the resized one are unchanged",
  resized_block:sub(1, #head) == head)
check("the resized image is written whole",
  resized_block:sub(#head + 1, #head + #big_pixels) == big_pixels)
check("images after the resized one shift, pixels intact",
  resized_block:sub(#head + #big_pixels + 1) == tail)
check("a resize still leaves everything after the block alone",
  resized_out:sub(PRS_OFFSET + BLOCK_SIZE + 1) == logo:sub(PRS_OFFSET + BLOCK_SIZE + 1))

-- Engine model -------------------------------------------------------------
-- A sprite's screen position comes from SAKURA:0xa294, which the metadata codec
-- rewrites to (320 - width)/2, so the codec here must not move pixels at all:
-- the artwork is drawn centred inside its own canvas.  These cases pin that,
-- and the 0x4800-byte staging window the engine exposes.

local function paint_span(width, height, from_x, to_x)
  local rows = {}
  for y = 0, height - 1 do
    local nibbles = {}
    for x = 0, width - 1 do
      nibbles[x + 1] = (x >= from_x and x <= to_x) and 5 or 0
    end
    local bytes = {}
    for i = 0, width // 2 - 1 do
      bytes[i + 1] = string.char((nibbles[i * 2 + 1] << 4) | nibbles[i * 2 + 2])
    end
    rows[y + 1] = table.concat(bytes)
  end
  return table.concat(rows)
end

local function span_of(data, w, h)
  local row_bytes = w // 2
  local minx, maxx = w, -1
  for y = 0, h - 1 do
    local row = data:sub(y * row_bytes + 1, (y + 1) * row_bytes)
    for i = 0, row_bytes - 1 do
      local b = row:byte(i + 1)
      local hi, lo = b >> 4, b & 0x0F
      if hi ~= 0 then
        minx = math.min(minx, i * 2)
        maxx = math.max(maxx, i * 2)
      end
      if lo ~= 0 then
        minx = math.min(minx, i * 2 + 1)
        maxx = math.max(maxx, i * 2 + 1)
      end
    end
  end
  return minx, maxx
end

-- The fixture is the original 17,792-byte layout, which leaves only 640 bytes
-- free in the staging window; blank slot 16 first so the cases below fit.
local function with_stub(arts)
  local out = {}
  for i = 1, #arts do
    out[i] = { name = arts[i].name, data = arts[i].data }
  end
  out[17].data = make_bmp(8, 2, string.rep("\x00", 8), bmp_fields(arts[1].data).pal)
  return out
end

local anchored = with_stub(artifacts)
anchored[2].data = make_bmp(120, 32, paint_span(120, 32, 0, 99),
  bmp_fields(artifacts[1].data).pal)
local anchored_out = codec.encode(logo, anchored)
local anchored_block = prs:decode(
  anchored_out:sub(PRS_OFFSET + 1, PRS_OFFSET + BLOCK_SIZE))[1].data
local s0, s1 = span_of(anchored_block:sub(1280 + 1, 1280 + 120 * 32 // 2), 120, 32)
-- Art left-flush at canvas x = 0..99 stays exactly there: the canvas is what
-- gets centred on screen, so the codec must pass the pixels through untouched.
check("pixels are written exactly as supplied", s0 == 0 and s1 == 99,
  string.format("ink at %d..%d", s0, s1))

-- Width is no longer bounded by the original slot: subtitles_metadata.lua
-- moves the sprite's x to (320 - width)/2, so a canvas wider than the slot is
-- legal on its own.  144 px keeps this case inside the staging window.
local wide = with_stub(artifacts)
wide[2].data = make_bmp(144, 32, paint_span(144, 32, 0, 111),
  bmp_fields(artifacts[1].data).pal)
local wide_out = codec.encode(logo, wide)
local wide_block = prs:decode(
  wide_out:sub(PRS_OFFSET + 1, PRS_OFFSET + BLOCK_SIZE))[1].data
local w0, w1 = span_of(wide_block:sub(1280 + 1, 1280 + 144 * 32 // 2), 144, 32)
check("a canvas wider than the slot is written unchanged", w0 == 0 and w1 == 111,
  string.format("ink at %d..%d", w0, w1))

check_err("a canvas wider than the screen is an error", function()
  local huge = with_stub(artifacts)
  huge[2].data = make_bmp(328, 32, paint_span(328, 32, 0, 111),
    bmp_fields(artifacts[1].data).pal)
  codec.encode(logo, huge)
end, "more than the 320-pixel screen")

check_err("a block past the staging window is an error", function()
  local tall = {}
  for i = 1, #artifacts do
    local slot_w = DIMS[i][1]
    tall[i] = {
      name = artifacts[i].name,
      data = make_bmp(slot_w, 32, paint_span(slot_w, 32, 0, slot_w - 1),
        bmp_fields(artifacts[1].data).pal),
    }
  end
  codec.encode(logo, tall)
end, "only stages")

check_err("a width that is not a multiple of 8 is an error", function()
  local f = bmp_fields(resized[2].data)
  local header = resized[2].data:sub(1, 18) .. string.pack("<i4", 252) ..
    resized[2].data:sub(23, f.off)
  local odd = { name = resized[2].name, data = header .. resized[2].data:sub(f.off + 1) }
  local arts = { resized[1], odd }
  for i = 3, #resized do arts[i] = resized[i] end
  codec.encode(logo, arts)
end, "not a multiple of 8")

check_err("a height past the table's byte is an error", function()
  local f = bmp_fields(resized[2].data)
  local header = resized[2].data:sub(1, 22) .. string.pack("<i4", -256) ..
    resized[2].data:sub(27, f.off)
  local tall = { name = resized[2].name, data = header .. resized[2].data:sub(f.off + 1) }
  local arts = { resized[1], tall }
  for i = 3, #resized do arts[i] = resized[i] end
  codec.encode(logo, arts)
end, "255-pixel limit")

check_err("oversized block is an error", function()
  -- Random pixels barely compress, so this must exceed the fixed block size.
  local state = 12345
  local noisy = {}
  for i = 1, #artifacts do
    local dims_w, dims_h = DIMS[i][1], DIMS[i][2]
    local stride2 = ((dims_w * 4 + 31) // 32) * 4
    local rows = {}
    for y = 0, dims_h - 1 do
      local row = {}
      for x = 0, dims_w // 2 - 1 do
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF
        row[x + 1] = string.char((state >> 16) & 0xFF)
      end
      row = table.concat(row)
      rows[y + 1] = row .. string.rep("\x00", stride2 - #row)
    end
    noisy[i] = {
      name = artifacts[i].name,
      data = artifacts[i].data:sub(1, bmp_fields(artifacts[i].data).off) .. table.concat(rows),
    }
  end
  codec.encode(logo, noisy)
end, "over the")

-- ---------------------------------------------------------------------------
-- grow_dma: the transfer length is a u16 in this file's own export #6

print("")
print("encode: grow_dma")

local function dma_word(data)
  return string.unpack(">I2", data, DMA_OFFSET + 1)
end

local function copy_artifacts(arts)
  local out = {}
  for i = 1, #arts do out[i] = { name = arts[i].name, data = arts[i].data } end
  return out
end

-- The fixture block is the disc's 17,792 bytes, so a build that fits stays
-- byte-identical whatever the mode says.
check("grow_dma=safe on an unchanged block is a no-op",
  codec.encode(logo, artifacts, "grow_dma=safe") == logo)
check("an empty argument means grow_dma=none",
  codec.encode(logo, artifacts, "") == logo)

-- Two lines in slot 1: 192x32 instead of 112x16, i.e. +2,176 bytes, which lands
-- between the shipped 0x4580 and the 0x5000 the atlas may own.
local grown = copy_artifacts(artifacts)
grown[2].data = make_bmp(192, 32, paint_span(192, 32, 0, 191),
  bmp_fields(artifacts[1].data).pal)
local grown_bytes = 17792 - 112 * 16 // 2 + 192 * 32 // 2
check("the grown artwork is past the default window",
  grown_bytes > 0x4800 and grown_bytes <= 0x5000, tostring(grown_bytes))

check_err("grow_dma=none refuses artwork past its window", function()
  codec.encode(logo, grown)
end, "only stages")
check_err("grow_dma=none is the same when spelled out", function()
  codec.encode(logo, grown, "grow_dma=none")
end, "only stages")

local safe_out = codec.encode(logo, grown, "grow_dma=safe")
check("grow_dma=safe builds that artwork", #safe_out == #logo)
check("it raises the transfer to the block's own size",
  dma_word(safe_out) == grown_bytes, string.format("0x%04x", dma_word(safe_out)))
check("only the two transfer bytes change outside the image block",
  safe_out:sub(1, DMA_OFFSET) == logo:sub(1, DMA_OFFSET)
    and safe_out:sub(DMA_OFFSET + 3, PRS_OFFSET) == logo:sub(DMA_OFFSET + 3, PRS_OFFSET)
    and safe_out:sub(PRS_OFFSET + BLOCK_SIZE + 1) == logo:sub(PRS_OFFSET + BLOCK_SIZE + 1))
check("the raised pixels are what was asked for",
  prs:decode(safe_out:sub(PRS_OFFSET + 1, PRS_OFFSET + BLOCK_SIZE))[1].data
    :sub(1280 + 1, 1280 + 192 * 32 // 2) == paint_span(192, 32, 0, 191))
check("re-encoding a raised build is a no-op",
  codec.encode(safe_out, grown, "grow_dma=safe") == safe_out)

-- Shrinking must leave the shipped length alone: never lower, so a build that
-- fits copies exactly what the disc copied.
local short = with_stub(artifacts)
local short_out = codec.encode(logo, short, "grow_dma=safe")
check("a smaller block never lowers the transfer",
  dma_word(short_out) == SHIPPED_DMA, string.format("0x%04x", dma_word(short_out)))

-- The region ends at the next overlay; "safe" means exactly that much.
check_err("grow_dma=safe stops at the next overlay", function()
  local too_big = copy_artifacts(artifacts)
  too_big[2].data = make_bmp(232, 32, paint_span(232, 32, 0, 231),
    bmp_fields(artifacts[1].data).pal)
  codec.encode(logo, too_big, "grow_dma=safe")
end, "0x25c07280")

check_err("an unknown mode is an error", function()
  codec.encode(logo, grown, "grow_dma=maybe")
end, "must be")
check_err("a bare token is an error", function()
  codec.encode(logo, grown, "grow_dma")
end, "key=value")
check_err("an unknown key is an error", function()
  codec.encode(logo, grown, "dma=0x5000")
end, "unknown argument")

-- ludared hands the same string to both passes, so a value a rebuild would
-- refuse must not decode silently.
check_err("decoding with a bad argument is refused too", function()
  codec.decode(logo, "grow_dma=maybe")
end, "must be")

local function decode_bytes(args)
  local parts = {}
  for i, artifact in ipairs(codec.decode(logo, args)) do
    parts[i] = artifact.name .. "\0" .. artifact.data
  end
  return table.concat(parts)
end

check("decoding accepts a good argument and yields the same canvases",
  decode_bytes("grow_dma=safe") == decode_bytes(nil))


print("")
print(string.format("%d passed, %d failed", pass, fail))
assert(fail == 0, string.format("%d tests failed", fail))
