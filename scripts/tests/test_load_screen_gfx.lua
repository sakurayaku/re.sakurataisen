--[[
  Tests for scripts/load_screen_gfx.lua against the retail SAKURA executable.

  The block at 0x5E190 is one PRS stream that decompresses to 42,048 bytes and
  holds three 4bpp VDP1 bitmaps at the offsets FixupSakura copies them to:

      0x0000  288 x 176   25,344 bytes  LOAD_MENU
      0x6300  not exposed 13,440 bytes  preserved verbatim
      0x9780  112 x  50    2,800 bytes  LOAD_MENU_MEMCARD
      0xA270  not exposed      16 bytes  preserved verbatim
      0xA280   56 x  16      448 bytes  LOAD_MENU_COPY_SOURCE

  The 16-colour palette is the first bank at SAKURA 0x5AD98 (the second bank is
  the grayscale label bank, used for the text artifacts).  The BMP palette is
  display-only: the C++ never writes it back for this block, so only pixel
  indices round-trip.

  The episode names are a second PRS block at 0x5C654: 128 16x16 4bpp tiles,
  128 bytes each, drawn from the big-endian glyph-index strings at 0x5A09E.
  Encode re-cuts each label image into 16-pixel cells and rebuilds the sheet.

  These tests deliberately restate the geometry instead of importing it from
  the codec, and parse the emitted BMP headers by hand, so that a wrong layout
  or a broken shared writer cannot pass unnoticed.
]]

local codec = dofile(LUDARED.SCRIPTS .. "/load_screen_gfx.lua")
local bmp = dofile(LUDARED.SCRIPTS .. "/shared/bmp.lua")
local CONST = dofile(LUDARED.SCRIPTS .. "/shared/constants.lua")
local prs = LUDARED.codec("std/sega/compression/prs")

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

local function check_error(name, fn, pattern)
  local ok, err = pcall(fn)
  check(name, not ok and tostring(err):find(pattern) ~= nil,
    ok and "call unexpectedly succeeded" or tostring(err))
end

local file = assert(io.open(LUDARED.PROJECT_ROOT .. "/SAKURA", "rb"),
  "the retail SAKURA executable is required")
local sakura = file:read("*a")
file:close()

local BLOCK = 0x5E190
local PALETTE = 0x5AD98
local SLOT = 2292
local DECOMP_SIZE = 42048

local FONT = 0x5C654
local FONT_SLOT = 6970
local STRINGS = 0x5A09E
local STRING_BUDGET = 0x5A398 - STRINGS
local TILE_BYTES = 128
local RAM_BASE = 0x06004000
local LABELS = 45
local EP_CELLS = 5
local EP_ROWS = 10
local EP_W = EP_CELLS * 16
local EP_H = EP_ROWS * 16
local EP_NAME = "LOAD_SCREEN/EPISODE_NUMBERS.bmp"
local TITLE_CELLS = 13
local TITLE_ROWS = 10
local TITLE_W = TITLE_CELLS * 16
local TITLE_H = TITLE_ROWS * 16
local TITLE_NAME = "LOAD_SCREEN/EPISODE_TITLES.bmp"
local LABEL_ARTIFACTS = 2      -- EMPTY_SAVE and UNUSED_EPISODE_10 stand alone

-- Entries 1, 3 .. 17 and 33 are the episode numbers; 2, 4 .. 20 the titles.
local function is_episode(index)
  return (index <= 17 and index % 2 == 1) or index == 33
end

local function is_title(index)
  return index >= 2 and index <= 20 and index % 2 == 0
end

-- The rest are stacked sheets, one 16-pixel row per entry, in this order.
local GROUPS = {
  { name = "LOAD_SCREEN/COMMANDS_CONTEXT.bmp", cells = 9,  indices = { 21, 22, 23, 24, 25 } },
  { name = "LOAD_SCREEN/COMMANDS_CONFIRM.bmp", cells = 8,  indices = { 27, 40, 41, 42 } },
  { name = "LOAD_SCREEN/COMMANDS_RESULT.bmp",  cells = 11, indices = { 43, 44, 45 } },
  { name = "LOAD_SCREEN/UNUSED_ALONE_GLYPH.bmp", cells = 1, indices = { 34 } },
  { name = "LOAD_SCREEN/ERRORS.bmp",           cells = 17, indices = { 30, 35, 31, 32 } },
  { name = "LOAD_SCREEN/UNUSED.bmp",           cells = 14, indices = { 36, 37, 38, 39 } },
}
local SHEET_ARTIFACTS = #GROUPS

-- Two labels keep a file of their own and may be widened.
local SINGLES = {
  { name = "LOAD_SCREEN/EMPTY_SAVE.bmp",         index = 26 },
  { name = "LOAD_SCREEN/UNUSED_EPISODE_10.bmp", index = 19 },
}
local SINGLE_OF = {}
for _, single in ipairs(SINGLES) do SINGLE_OF[single.index] = single end

-- All four buttons are drawn from sprite descriptors, not their duplicate strings.
local CHOICES = {
  { name = "LOAD_SCREEN/COMMANDS_CHOICE_YES.bmp",    cells = 2, parent = 0x59DC0, slots = { 11, 10 } },
  { name = "LOAD_SCREEN/COMMANDS_CHOICE_NO.bmp",     cells = 3, parent = 0x59DD0, slots = { 10, 10, 19 } },
  { name = "LOAD_SCREEN/COMMANDS_CHOICE_COPY.bmp",   cells = 3, parent = 0x59D10, slots = { 28, 29, 0 } },
  { name = "LOAD_SCREEN/COMMANDS_CHOICE_DELETE.bmp", cells = 2, parent = 0x59D20, slots = { 49, 50 } },
}
local CHOICE_ARTIFACTS = #CHOICES

-- True when an entry is drawn from a stacked sheet instead of its own BMP.
local function in_sheet(index)
  if is_episode(index) or is_title(index) or index == 28 or index == 29 then return true end
  for _, group in ipairs(GROUPS) do
    for _, member in ipairs(group.indices) do
      if member == index then return true end
    end
  end
  return false
end

-- Expected layout: destination offset, size of the 4bpp bitmap, artifact name.
local LAYOUT = {
  { off = 0x0000, width = 288, height = 176, name = "LOAD_MENU.bmp" },
  { off = 0x9780, width = 112, height = 50,  name = "LOAD_MENU_MEMCARD.bmp" },
  { off = 0xA280, width = 56,  height = 16,  name = "LOAD_MENU_COPY_SOURCE.bmp" },
}
for _, region in ipairs(LAYOUT) do
  region.size = region.width * region.height // 2
end

-- Bytes the codec must carry through untouched, as inclusive 1-based ranges.
local PRESERVED = {
  { from = 0x6300 + 1, to = 0x9780, label = "the 192x140 image" },
  { from = 0xA270 + 1, to = 0xA280, label = "the 16-byte gap" },
}

-- Hand-rolled header reader: a broken shared writer must not hide itself.
local function bmp_header(data)
  assert(data:sub(1, 2) == "BM", "not a BMP")
  local file_size = string.unpack("<I4", data, 3)
  local pixel_offset = string.unpack("<I4", data, 11)
  local info_size, width, height, planes, bits =
    string.unpack("<I4i4i4I2I2", data, 15)
  return {
    file_size = file_size,
    pixel_offset = pixel_offset,
    info_size = info_size,
    width = width,
    height = height,
    planes = planes,
    bits = bits,
  }
end

local decompressed = prs:decode(sakura:sub(BLOCK + 1, BLOCK + SLOT))[1].data
local real_palette = bmp.from_bgr555(sakura:sub(PALETTE + 1, PALETTE + 32), 16)
-- The codec swaps the label bank's last colour for bright red.
local retail_label_palette = bmp.from_bgr555(sakura:sub(PALETTE + 33, PALETTE + 64), 16)
local label_palette = retail_label_palette:sub(1, #retail_label_palette - 4)
  .. string.char(0, 0, 255, 0)

print("test_load_screen_gfx.lua")

--------------------------------------------------------------------- layout --
check("SAKURA size", #sakura == 391712, tostring(#sakura))
check("load block decompresses to 42,048 bytes", #decompressed == DECOMP_SIZE,
  tostring(#decompressed))

do
  local exposed, cursor, ordered = 0, 0, true
  for _, region in ipairs(LAYOUT) do
    exposed = exposed + region.size
    if region.off < cursor then ordered = false end
    cursor = math.max(cursor, region.off + region.size)
  end
  check("exposed images cover 28,592 bytes", exposed == 25344 + 2800 + 448,
    tostring(exposed))
  check("exposed images are ordered", ordered)
  check("the last image ends at the block end", cursor == DECOMP_SIZE, tostring(cursor))
  check("LOAD_MENU stops where the 192-pixel image starts",
    LAYOUT[1].off + LAYOUT[1].size == 0x6300)

  local accounted = exposed
  for _, range in ipairs(PRESERVED) do
    accounted = accounted + (range.to - range.from + 1)
  end
  check("images plus preserved ranges tile the block",
    accounted == DECOMP_SIZE, tostring(accounted))
  check("preserved ranges are disjoint from the images",
    PRESERVED[1].to <= LAYOUT[2].off and PRESERVED[2].from > LAYOUT[2].off + LAYOUT[2].size)
end

------------------------------------------------------------------ detection --
-- Both retail executables are pinned by content hash; the codec returns
-- "certain" only for those and falls back to structure for anything rebuilt.
-- The codec pins the executable by the shared hash constant, so the constant
-- must describe the retail file the fixture came from.
local CD1_SHA256 = CONST.CD1_SAKURA_SHA256
check("shared constants match the executable",
  #sakura == CONST.CD1_SAKURA_BYTES, #sakura)
do
  local ok, native = pcall(LUDARED.sha256, sakura)
  check("native sha256 accepts binary input", ok, ok and native or nil)
  check("native sha256 matches the pin", ok and native == CD1_SHA256,
    ok and native or nil)
end
check("sha256 of the disc-1 executable matches the pin",
  LUDARED.sha256(sakura) == CD1_SHA256, LUDARED.sha256(sakura))
check("can_handle real SAKURA", codec.can_handle(sakura) == "certain",
  codec.can_handle(sakura))

-- Modified executables remain decodable, but can_handle only claims retail hashes.
do
  local rebuilt = sakura:sub(1, PALETTE + 40)
    .. string.char((sakura:byte(PALETTE + 41) + 1) % 256)
    .. sakura:sub(PALETTE + 42)
  check("a rebuilt executable is rejected by can_handle",
    LUDARED.sha256(rebuilt) ~= CD1_SHA256 and codec.can_handle(rebuilt) == "no",
    codec.can_handle(rebuilt))
  check("a rebuilt executable still decodes",
    #codec.decode(rebuilt, nil) == 3 + 2 + SHEET_ARTIFACTS + LABEL_ARTIFACTS
      + CHOICE_ARTIFACTS)
end
check("can_handle rejects non-strings", codec.can_handle(nil) == "no")
check("can_handle rejects random data",
  codec.can_handle(string.rep("\xA5", 4096)) == "no")
-- Hash pinning is size-gated so a whole disc image is never fed to the digest.
check("can_handle rejects a disc image without hashing it",
  codec.can_handle(string.rep("\0", 600000)) == "no")
check("truncated input is rejected", codec.can_handle(sakura:sub(1, BLOCK + 100)) == "no")
check_error("truncated input cannot decode", function()
  codec.decode(sakura:sub(1, BLOCK + 100), { prefix = "X" })
end, "load_screen")

check("decode_name default", codec.decode_name(nil) == "LOAD_SCREEN")
check("decode_name from a string", codec.decode_name("CD2") == "CD2")
check("decode_name strips trailing slashes", codec.decode_name("A/B//") == "A/B")
check("decode_name from a table", codec.decode_name({ prefix = "P/Q" }) == "P/Q")
check("decode_name ignores an empty prefix", codec.decode_name("") == "LOAD_SCREEN")

--------------------------------------------------------------------- decode --
local arts = codec.decode(sakura, { prefix = "LOAD_SCREEN" })
check("three images, six label sheets, two labels and four buttons",
  #arts == 3 + 2 + SHEET_ARTIFACTS + LABEL_ARTIFACTS + CHOICE_ARTIFACTS,
  tostring(#arts))
check("artifact names",
  arts[1].name == "LOAD_SCREEN/LOAD_MENU.bmp"
  and arts[2].name == "LOAD_SCREEN/LOAD_MENU_MEMCARD.bmp"
  and arts[3].name == "LOAD_SCREEN/LOAD_MENU_COPY_SOURCE.bmp")
check("label names",
  arts[4].name == EP_NAME and arts[5].name == TITLE_NAME, tostring(arts[4].name))
do
  local ok = true
  for i, group in ipairs(GROUPS) do
    if arts[5 + i].name ~= group.name then ok = false end
  end
  check("the sheet artifacts follow in sheet order", ok, tostring(arts[6].name))
  local at = 3 + 2 + SHEET_ARTIFACTS
  check("the two standalone labels follow the sheets",
    arts[at + 1].name == SINGLES[1].name and arts[at + 2].name == SINGLES[2].name,
    arts[at + 1].name .. ", " .. arts[at + 2].name)
  local ordered = true
  for i, choice in ipairs(CHOICES) do
    if arts[at + 2 + i].name ~= choice.name then ordered = false end
  end
  check("the four buttons come last, one file each", ordered,
    arts[at + 3].name)
end

local function find_in(list, name)
  for _, artifact in ipairs(list) do
    if artifact.name == name then return artifact end
  end
  return nil
end

do
  local missing, numbered = {}, 0
  for index = 1, LABELS do
    local single = SINGLE_OF[index]
    if not in_sheet(index) then
      if not single or not find_in(arts, single.name) then
        missing[#missing + 1] = index
      end
    end
  end
  for _, artifact in ipairs(arts) do
    if artifact.name:find("/TEXT_%d%d%.bmp$") then numbered = numbered + 1 end
  end
  check("every represented entry has an artifact", #missing == 0,
    table.concat(missing, ","))
  check("no numbered TEXT artifact is left", numbered == 0, tostring(numbered))
end

local pixels = {}
for i, region in ipairs(LAYOUT) do
  local header = bmp_header(arts[i].data)
  check(region.name .. ": header geometry",
    header.width == region.width and math.abs(header.height) == region.height
    and header.bits == 4 and header.planes == 1 and header.info_size == 40,
    string.format("%dx%d %dbpp info=%d", header.width, header.height,
      header.bits, header.info_size))
  check(region.name .. ": stored top-down", header.height < 0, tostring(header.height))
  check(region.name .. ": header size matches the file", header.file_size == #arts[i].data,
    string.format("%d vs %d", header.file_size, #arts[i].data))
  check(region.name .. ": 16-colour palette before the pixels",
    header.pixel_offset == 14 + 40 + 64, tostring(header.pixel_offset))

  local data, palette = bmp.parse(arts[i].data, region.width, region.height, 4)
  pixels[i] = data
  check(region.name .. ": pixel byte count", #data == region.size, tostring(#data))
  check(region.name .. ": pixels match the stream",
    data == decompressed:sub(region.off + 1, region.off + region.size))
  check(region.name .. ": uses the load-screen palette", palette == real_palette)
end

local load_pixels = pixels[1]
local cartridge_pixels = pixels[2]
local copy_pixels = pixels[3]

check("palette is the first bank, not the label bank", real_palette ~= label_palette)
check("label BMPs end on bright red", label_palette:sub(-4) == string.char(0, 0, 255, 0),
  (label_palette:sub(-4):gsub(".", function(c) return string.format("%02X ", c:byte()) end)))
check("the retail label bank ended on a grey",
  retail_label_palette:sub(-4) == string.char(255, 255, 255, 0),
  (retail_label_palette:sub(-4):gsub(".", function(c) return string.format("%02X ", c:byte()) end)))
check("the picture palette keeps its retail last colour",
  real_palette:sub(-4) ~= string.char(0, 0, 255, 0))
check("palette has 16 entries", #real_palette == 64, tostring(#real_palette))
do
  local alpha_ok = true
  for i = 4, #real_palette, 4 do
    if real_palette:byte(i) ~= 0 then alpha_ok = false end
  end
  check("palette entries keep a zero alpha byte", alpha_ok)
end

----------------------------------------------------------- unchanged travels --
check("unmodified encode is byte-identical",
  codec.encode(sakura, arts, { prefix = "LOAD_SCREEN" }) == sakura)
check("encode without artifacts is byte-identical",
  codec.encode(sakura, {}, { prefix = "LOAD_SCREEN" }) == sakura)
check("encode with a nil prefix uses LOAD_SCREEN",
  codec.encode(sakura, { { name = "LOAD_SCREEN/LOAD_MENU.bmp", data = arts[1].data } },
    nil) == sakura)
check("encode ignores unknown artifact names", codec.encode(sakura, {
  { name = "LOAD_SCREEN/OTHER.bmp", data = string.rep("\0", 10) },
}, { prefix = "LOAD_SCREEN" }) == sakura)

-- Changing only the BMP palette must not touch the file: the C++ never writes
-- this block's palette back, so the palette is display-only.
do
  local repainted = bmp.build(load_pixels, 288, 176, 4, label_palette)
  check("a palette-only edit is a no-op",
    repainted ~= arts[1].data
    and codec.encode(sakura, { { name = "LOAD_SCREEN/LOAD_MENU.bmp", data = repainted } },
      { prefix = "LOAD_SCREEN" }) == sakura)
end

---------------------------------------------------------------------- edits --
local function encode_one(index, new_pixels)
  local region = LAYOUT[index]
  return codec.encode(sakura, {
    { name = "LOAD_SCREEN/" .. region.name,
      data = bmp.build(new_pixels, region.width, region.height, 4) },
  }, { prefix = "LOAD_SCREEN" }), region
end

for index, region in ipairs(LAYOUT) do
  local old = pixels[index]
  local changed = string.char(old:byte(1) ~ 0x11) .. old:sub(2)
  local out = encode_one(index, changed)
  local name = region.name

  check(name .. ": edit keeps the file size", #out == #sakura)
  check(name .. ": only the slot changed",
    out:sub(1, BLOCK) == sakura:sub(1, BLOCK)
    and out:sub(BLOCK + SLOT + 1) == sakura:sub(BLOCK + SLOT + 1))

  local rebuilt = prs:decode(out:sub(BLOCK + 1, BLOCK + SLOT))[1].data
  check(name .. ": block size unchanged", #rebuilt == DECOMP_SIZE, tostring(#rebuilt))
  check(name .. ": edited pixel landed",
    rebuilt:byte(region.off + 1) == (old:byte(1) ~ 0x11))
  check(name .. ": rest of the image unchanged",
    rebuilt:sub(region.off + 2, region.off + region.size)
    == decompressed:sub(region.off + 2, region.off + region.size))

  for other_index, other in ipairs(LAYOUT) do
    if other_index ~= index then
      check(name .. ": " .. other.name .. " preserved",
        rebuilt:sub(other.off + 1, other.off + other.size)
        == decompressed:sub(other.off + 1, other.off + other.size))
    end
  end
  for _, range in ipairs(PRESERVED) do
    check(name .. ": " .. range.label .. " preserved",
      rebuilt:sub(range.from, range.to) == decompressed:sub(range.from, range.to))
  end

  local redecoded = codec.decode(out, { prefix = "LOAD_SCREEN" })
  check(name .. ": edit survives a re-decode",
    bmp.parse(redecoded[index].data, region.width, region.height, 4) == changed)
  check(name .. ": re-encode is stable",
    codec.encode(out, redecoded, { prefix = "LOAD_SCREEN" }) == out)
end

-- Last pixel of the last region: catches an off-by-one at the block end.
do
  local changed = copy_pixels:sub(1, #copy_pixels - 1) .. string.char(0x3C)
  local out = encode_one(3, changed)
  local rebuilt = prs:decode(out:sub(BLOCK + 1, BLOCK + SLOT))[1].data
  check("LOAD_MENU_COPY_SOURCE last pixel is writable", rebuilt:sub(0xA280 + 1, 0xA440) == changed)
  check("LOAD_MENU_COPY_SOURCE last pixel does not grow the block", #rebuilt == DECOMP_SIZE)
end

-- First pixel of the first region.
do
  local changed = string.char(0x0E) .. load_pixels:sub(2)
  local out = encode_one(1, changed)
  local rebuilt = prs:decode(out:sub(BLOCK + 1, BLOCK + SLOT))[1].data
  check("LOAD_MENU first pixel is writable", rebuilt:byte(1) == 0x0E)
end

-- All three at once.
do
  local out = codec.encode(sakura, {
    { name = "LOAD_SCREEN/LOAD_MENU.bmp",
      data = bmp.build(string.char(0x01) .. load_pixels:sub(2), 288, 176, 4) },
    { name = "LOAD_SCREEN/LOAD_MENU_MEMCARD.bmp",
      data = bmp.build(cartridge_pixels:sub(1, #cartridge_pixels - 1) .. string.char(0x03),
        112, 50, 4) },
    { name = "LOAD_SCREEN/LOAD_MENU_COPY_SOURCE.bmp",
      data = bmp.build(string.char(0x04) .. copy_pixels:sub(2), 56, 16, 4) },
  }, { prefix = "LOAD_SCREEN" })

  local rebuilt = prs:decode(out:sub(BLOCK + 1, BLOCK + SLOT))[1].data
  check("three-way edit: menu", rebuilt:byte(1) == 0x01)
  check("three-way edit: cartridge", rebuilt:byte(0xA270) == 0x03)
  check("three-way edit: copy", rebuilt:byte(0xA281) == 0x04)
  check("three-way edit: 192x140 image preserved",
    rebuilt:sub(0x6301, 0x9780) == decompressed:sub(0x6301, 0x9780))
  check("three-way edit: file size", #out == #sakura)
  check("three-way edit: stable re-encode",
    codec.encode(out, codec.decode(out, { prefix = "LOAD_SCREEN" }),
      { prefix = "LOAD_SCREEN" }) == out)
end

--------- labels --
local sheet = prs:decode(sakura:sub(FONT + 1, FONT + FONT_SLOT))[1].data
check("font sheet is 128 tiles", #sheet == 128 * TILE_BYTES, tostring(#sheet))
check("the font slot ends at the picture block", FONT + FONT_SLOT == BLOCK - 2)

-- Independent reader for the big-endian glyph strings, including the table's
-- own double-zero terminator.
local function read_table()
  local out, pos, current = {}, STRINGS, {}
  while true do
    local value = (sakura:byte(pos + 1) or 0) * 256 + (sakura:byte(pos + 2) or 0)
    if value == 0 then
      out[#out + 1] = current
      current = {}
      local next_value = (sakura:byte(pos + 3) or 0) * 256 + (sakura:byte(pos + 4) or 0)
      pos = pos + 2
      if next_value == 0 then break end
    else
      current[#current + 1] = value
      pos = pos + 2
    end
  end
  return out, pos
end

local retail_strings, retail_end = read_table()

-- The same reader for any block, used on the encoded output.
local function table_of(data, offset)
  local out, pos, current = {}, offset, {}
  while true do
    local value = (data:byte(pos + 1) or 0) * 256 + (data:byte(pos + 2) or 0)
    if value == 0 then
      out[#out + 1] = current
      current = {}
      local next_value = (data:byte(pos + 3) or 0) * 256 + (data:byte(pos + 4) or 0)
      pos = pos + 2
      if next_value == 0 then break end
    else
      current[#current + 1] = value
      pos = pos + 2
    end
  end
  return out, pos
end
check("45 label strings", #retail_strings == LABELS, tostring(#retail_strings))
check("the strings fill their area exactly",
  retail_end - STRINGS + 2 == STRING_BUDGET, tostring(retail_end - STRINGS + 2))

do
  local longest = 0
  for _, indices in ipairs(retail_strings) do
    longest = math.max(longest, #indices)
  end
  check("no page is wider than the 18-cell screen", longest <= 18, tostring(longest))
  check("episode 1 is three glyphs", #retail_strings[1] == 3, tostring(#retail_strings[1]))
end

local function compose(indices)
  local rows = {}
  for row = 0, 15 do
    local cells = {}
    for cell, glyph in ipairs(indices) do
      local base = (glyph - 1) * TILE_BYTES + row * (16 // 2)
      cells[cell] = sheet:sub(base + 1, base + 16 // 2)
    end
    rows[row + 1] = table.concat(cells)
  end
  return table.concat(rows)
end

local function dims_of(artifact)
  local width, height = string.unpack("<i4i4", artifact.data, 19)
  return width, math.abs(height)
end

-- EPISODE_NUMBERS.bmp: 80 x 160, a row per episode number, five cells a row.
-- Retail stores three glyphs, so cells 4 and 5 of every row are blank.
do
  local artifact = find_in(arts, EP_NAME)
  local width, height = dims_of(artifact)
  check("EPISODE_NUMBERS: 80 x 160", width == EP_W and height == EP_H,
    string.format("%dx%d", width, height))
  check("EPISODE_NUMBERS: header size",
    string.unpack("<I4", artifact.data, 3) == #artifact.data)

  local pixels, palette = bmp.parse(artifact.data, width, height, 4)
  local stride = EP_W // 2
  check("EPISODE_NUMBERS: uses the label palette", palette == label_palette)

  for row = 1, EP_ROWS do
    local index = (row == EP_ROWS) and 33 or (row * 2 - 1)
    local glyphs = retail_strings[index]
    local source = compose(glyphs)
    local source_stride = #glyphs * 8
    local ok = true
    for y = 0, 15 do
      local at = (row - 1) * 16 * stride + y * stride
      local got = pixels:sub(at + 1, at + stride)
      local want = source:sub(y * source_stride + 1, (y + 1) * source_stride)
        .. string.rep("\0", stride - source_stride)
      if got ~= want then ok = false end
    end
    check(("EPISODE row %d is table entry %d"):format(row, index), ok)
  end
  -- Episodes 1-9 are 第n話 (three glyphs); row 10 is 最終話 (three glyphs).
  check("EPISODE_NUMBERS: three glyphs on every row",
    #retail_strings[1] == 3 and #retail_strings[33] == 3,
    string.format("%d, %d", #retail_strings[1], #retail_strings[33]))
end

-- EPISODE_TITLES.bmp: 208 x 160, a row per title, thirteen cells a row with
-- the unused cells blank.
do
  local artifact = find_in(arts, TITLE_NAME)
  local width, height = dims_of(artifact)
  check("EPISODE_TITLES: 208 x 160", width == TITLE_W and height == TITLE_H,
    string.format("%dx%d", width, height))
  check("EPISODE_TITLES: header size",
    string.unpack("<I4", artifact.data, 3) == #artifact.data)

  local pixels, palette = bmp.parse(artifact.data, width, height, 4)
  local stride = TITLE_W // 2
  check("EPISODE_TITLES: uses the label palette", palette == label_palette)

  local widest = 0
  for row = 1, TITLE_ROWS do
    local index = row * 2
    local glyphs = retail_strings[index]
    widest = math.max(widest, #glyphs)
    local source = compose(glyphs)
    local source_stride = #glyphs * 8
    local ok = true
    for y = 0, 15 do
      local at = (row - 1) * 16 * stride + y * stride
      local got = pixels:sub(at + 1, at + stride)
      local want = source:sub(y * source_stride + 1, (y + 1) * source_stride)
        .. string.rep("\0", stride - source_stride)
      if got ~= want then ok = false end
    end
    check(("TITLE row %d is table entry %d"):format(row, index), ok)
  end
  check("EPISODE_TITLES: the sheet fits the longest title", widest == TITLE_CELLS,
    tostring(widest))
end

-- Every other sheet: one 16-pixel row per entry, as wide as the longest
-- retail label of the group, the rest of each row blank.
for _, group in ipairs(GROUPS) do
  local artifact = find_in(arts, group.name)
  check(group.name .. ": present", artifact ~= nil)
  local width, height = dims_of(artifact)
  check(group.name .. ": geometry",
    width == group.cells * 16 and height == #group.indices * 16,
    string.format("%dx%d", width, height))
  check(group.name .. ": header size",
    string.unpack("<I4", artifact.data, 3) == #artifact.data)

  local pixels, palette = bmp.parse(artifact.data, width, height, 4)
  local stride = width // 2
  check(group.name .. ": uses the label palette", palette == label_palette)

  for row, index in ipairs(group.indices) do
    local glyphs = retail_strings[index]
    local source = compose(glyphs)
    local source_stride = #glyphs * 8
    check(group.name .. ": the sheet fits entry " .. index,
      #glyphs <= group.cells, string.format("%d over %d", #glyphs, group.cells))
    local ok = true
    for y = 0, 15 do
      local at = (row - 1) * 16 * stride + y * stride
      local got = pixels:sub(at + 1, at + stride)
      local want = source:sub(y * source_stride + 1, (y + 1) * source_stride)
        .. string.rep("\0", stride - source_stride)
      if got ~= want then ok = false end
    end
    check(("%s row %d is entry %d"):format(group.name, row, index), ok)
  end
end

-- The two standalone labels: one cell per glyph, own file, no padding.
for _, single in ipairs(SINGLES) do
  local artifact = find_in(arts, single.name)
  check(single.name .. ": present", artifact ~= nil)
  local width, height = dims_of(artifact)
  local glyphs = retail_strings[single.index]
  check(single.name .. ": 16 pixels high, one cell per glyph",
    height == 16 and width == math.max(#glyphs, 1) * 16,
    string.format("%dx%d for %d glyph", width, height, #glyphs))
  local pixels, palette = bmp.parse(artifact.data, width, height, 4)
  check(single.name .. ": composed from its own glyphs", pixels == compose(glyphs))
  check(single.name .. ": uses the label palette", palette == label_palette)
end

-- The four buttons are composed from the formatting table's glyph sources.
for _, choice in ipairs(CHOICES) do
  local artifact = find_in(arts, choice.name)
  check(choice.name .. ": present", artifact ~= nil)
  local width, height = dims_of(artifact)
  check(choice.name .. ": 16 pixels high, one cell per glyph",
    height == 16 and width == choice.cells * 16,
    string.format("%dx%d", width, height))
  local pixels, palette = bmp.parse(artifact.data, width, height, 4)
  check(choice.name .. ": uses the label palette", palette == label_palette)

  local glyphs = {}
  for k, slot in ipairs(choice.slots) do glyphs[k] = slot + 1 end
  check(choice.name .. ": composed from the cells the engine draws",
    pixels == compose(glyphs))
end

-- The cells the formatting table reads are the retail ones: コピー at 28, 29, 0
-- and 消去 at 49, 50, which is entries 29, 30 and 1 counting from glyph 1.
do
  local copy = find_in(arts, "LOAD_SCREEN/COMMANDS_CHOICE_COPY.bmp")
  local delete = find_in(arts, "LOAD_SCREEN/COMMANDS_CHOICE_DELETE.bmp")
  local copy_cells = {
    sheet:sub(28 * TILE_BYTES + 1, 29 * TILE_BYTES),
    sheet:sub(29 * TILE_BYTES + 1, 30 * TILE_BYTES),
    sheet:sub(1, TILE_BYTES),
  }
  local delete_cells = {
    sheet:sub(49 * TILE_BYTES + 1, 50 * TILE_BYTES),
    sheet:sub(50 * TILE_BYTES + 1, 51 * TILE_BYTES),
  }
  local function frame(cells)
    local rows = {}
    for y = 0, 15 do
      local line = {}
      for k, tile in ipairs(cells) do line[k] = tile:sub(y * 8 + 1, y * 8 + 8) end
      rows[y + 1] = table.concat(line)
    end
    return table.concat(rows)
  end
  check("COPY is read from sheet cells 28, 29 and 0",
    select(1, bmp.parse(copy.data, 48, 16, 4)) == frame(copy_cells))
  check("DELETE is read from sheet cells 49 and 50",
    select(1, bmp.parse(delete.data, 32, 16, 4)) == frame(delete_cells))
end

local function u32(data, offset)
  return ((data:byte(offset + 1) * 256 + data:byte(offset + 2)) * 256
    + data:byte(offset + 3)) * 256 + data:byte(offset + 4)
end

-- The 38 menu pointers sit between the string area and the font slot.
local function string_refs(data)
  local refs = {}
  for pos = 0x5A398, 0x5A4B8 - 4, 4 do
    local value = u32(data, pos)
    local offset = value - RAM_BASE
    if offset >= STRINGS and offset < STRINGS + STRING_BUDGET then
      refs[#refs + 1] = { pos = pos, offset = offset }
    end
  end
  return refs
end

check("38 pointers address the label strings", #string_refs(sakura) == 38,
  tostring(#string_refs(sakura)))

local function has_ref(refs, offset)
  for _, ref in ipairs(refs) do
    if ref.offset == offset then return true end
  end
  return false
end

-- Where string N starts, read straight out of the retail table.
local function string_offset(index)
  local at = STRINGS
  for k = 1, index - 1 do at = at + (#retail_strings[k] + 1) * 2 end
  return at
end

-- Blank two cells of a command row: string 21 is eight glyphs in a row nine
-- cells wide, so it becomes six.  Everything after it moves back four bytes
-- and the pointers baked into the executable have to follow.
do
  local group = GROUPS[1]
  local artifact = find_in(arts, group.name)
  local width, height = dims_of(artifact)
  local pixels = select(1, bmp.parse(artifact.data, width, height, 4))
  local stride = width // 2
  local rows = {}
  for y = 0, height - 1 do
    local line = pixels:sub(y * stride + 1, (y + 1) * stride)
    if y // 16 + 1 == 1 then
      line = line:sub(1, 6 * 8) .. string.rep("\0", 2 * 8) .. line:sub(8 * 8 + 1)
    end
    rows[y + 1] = line
  end

  local out = codec.encode(sakura,
    { { name = group.name, data = bmp.build(table.concat(rows), width, height, 4) } },
    { prefix = "LOAD_SCREEN" })

  local labels = table_of(out, STRINGS)
  check("a shortened row keeps 45 entries", #labels == LABELS, tostring(#labels))
  check("the shortened command is six glyphs", #labels[21] == 6, tostring(#labels[21]))
  check("a shortened row keeps the file size", #out == #sakura, tostring(#out))
  check("a shortened row leaves the picture slot alone",
    out:sub(BLOCK + 1, BLOCK + SLOT) == sakura:sub(BLOCK + 1, BLOCK + SLOT))

  local refs = string_refs(out)
  check("the pointer count is unchanged", #refs == 38, tostring(#refs))
  check("the first string keeps its address", has_ref(refs, STRINGS),
    tostring(string_offset(1)))
  check("the shortened string keeps its own address", has_ref(refs, string_offset(21)),
    tostring(string_offset(21)))
  check("the next string moved back by four bytes",
    has_ref(refs, string_offset(22) - 4), tostring(string_offset(22) - 4))

  -- Every pointer must land on a string start, read straight out of the new
  -- block: a terminator, then the next string's first word.
  local block = math.huge
  for _, ref in ipairs(refs) do block = math.min(block, ref.offset) end
  local starts, pos = {}, block
  while true do
    starts[pos] = true
    while (out:byte(pos + 1) * 256 + out:byte(pos + 2)) ~= 0 do pos = pos + 2 end
    pos = pos + 2
    if (out:byte(pos + 1) * 256 + out:byte(pos + 2)) == 0 then break end
  end
  local aligned = true
  for _, ref in ipairs(refs) do
    if not starts[ref.offset] then aligned = false end
  end
  check("every pointer still lands on a string start", aligned)
  check("a shortened row re-encodes stably",
    codec.encode(out, codec.decode(out, { prefix = "LOAD_SCREEN" }),
      { prefix = "LOAD_SCREEN" }) == out)
end

-- The retail area is full to the byte, so growing it reaches the reclaim path:
-- the strings no pointer addresses give their bytes up, one blank glyph each.
do
  local tile = string.rep("\x0F", TILE_BYTES)
  local wide = bmp.build(string.rep(tile, 18), 288, 16, 4)

  local group = GROUPS[1]
  local artifact = find_in(arts, group.name)
  local width, height = dims_of(artifact)
  local pixels = select(1, bmp.parse(artifact.data, width, height, 4))
  local stride = width // 2
  local rows = {}
  for y = 0, height - 1 do
    local line = pixels:sub(y * stride + 1, (y + 1) * stride)
    if y // 16 + 1 == 1 then
      line = line:sub(1, 8 * 8) .. string.rep("\x0F", 8) .. line:sub(9 * 8 + 1)
    end
    rows[y + 1] = line
  end

  local out = codec.encode(sakura, {
    { name = group.name, data = bmp.build(table.concat(rows), width, height, 4) },
    { name = SINGLES[1].name, data = wide },
    { name = SINGLES[2].name, data = wide },
  }, { prefix = "LOAD_SCREEN" })

  local labels, new_end = table_of(out, STRINGS)
  check("a grown block keeps 45 entries", #labels == LABELS, tostring(#labels))
  check("the grown labels keep their glyphs",
    #labels[21] == 9 and #labels[26] == 18,
    string.format("%d, %d", #labels[21], #labels[26]))
  check("the released bytes keep the block inside the area",
    new_end - STRINGS + 2 <= STRING_BUDGET, tostring(new_end - STRINGS + 2))
  check("a grown block keeps the file size", #out == #sakura, tostring(#out))

  -- Rows 28 and 29 are both dead, so an emptied entry would cut the table in
  -- two: every dead string is one blank glyph instead.
  local blank = string.rep("\0", TILE_BYTES)
  local new_sheet = prs:decode(out:sub(FONT + 1, FONT + FONT_SLOT))[1].data
  local dead = { 19, 28, 29, 34, 36, 37, 38, 39 }
  local released, kept = true, true
  for _, i in ipairs(dead) do
    if #labels[i] ~= 1 then released = false end
    if #labels[i] == 1 and new_sheet:sub((labels[i][1] - 1) * TILE_BYTES + 1,
      labels[i][1] * TILE_BYTES) ~= blank then kept = false end
  end
  check("the dead strings became one blank glyph", released and kept)

  local live_ok = true
  for _, i in ipairs({ 1, 20, 43, 45 }) do
    if #labels[i] ~= #retail_strings[i] then live_ok = false end
  end
  check("the referenced strings keep their glyphs", live_ok)

  check("a grown block re-encodes stably",
    codec.encode(out, codec.decode(out, { prefix = "LOAD_SCREEN" }),
      { prefix = "LOAD_SCREEN" }) == out)
end


-- All four button descriptors must follow the rebuilt atlas, without pinned glyphs.
do
  local function label(cells)
    local rows = {}
    for y = 0, 15 do
      local line = {}
      for k, tile in ipairs(cells) do line[k] = tile:sub(y * 8 + 1, y * 8 + 8) end
      rows[y + 1] = table.concat(line)
    end
    return table.concat(rows)
  end

  local NEW = {}
  for i = 1, 10 do NEW[i] = string.rep(string.char(i), TILE_BYTES) end
  local supplied = {
    { NEW[1], NEW[2] }, { NEW[3], NEW[4], NEW[5] },
    { NEW[6], NEW[7], NEW[8] }, { NEW[9], NEW[10] },
  }
  local edits = {}
  for i, choice in ipairs(CHOICES) do
    edits[i] = { name = choice.name,
      data = bmp.build(label(supplied[i]), #supplied[i] * 16, 16, 4) }
  end
  local out = codec.encode(sakura, edits, { prefix = "LOAD_SCREEN" })
  local new_sheet = prs:decode(out:sub(FONT + 1, FONT + FONT_SLOT))[1].data
  local all_sources_match, all_sources_moved = true, true
  for i, choice in ipairs(CHOICES) do
    local count, pointer = string.unpack(">I2I4", out, choice.parent + 3)
    if count ~= #supplied[i] then all_sources_match = false end
    for k, tile in ipairs(supplied[i]) do
      local offset = pointer - RAM_BASE + (k - 1) * 10 + 8
      local source = string.unpack(">I2", out, offset + 1)
      if new_sheet:sub(source // 16 * TILE_BYTES + 1,
          (source // 16 + 1) * TILE_BYTES) ~= tile then
        all_sources_match = false
      end
      local old_source = string.unpack(">I2", sakura, offset + 1)
      if source == old_source then all_sources_moved = false end
    end
  end
  check("all four button lists point at their rebuilt glyphs", all_sources_match)
  check("button glyphs moved without reserved atlas cells", all_sources_moved)
  check("a button edit leaves the picture slot alone",
    out:sub(BLOCK + 1, BLOCK + SLOT) == sakura:sub(BLOCK + 1, BLOCK + SLOT))
  check("a button edit keeps the file size", #out == #sakura)

  local back = codec.decode(out, { prefix = "LOAD_SCREEN" })
  local decoded = true
  for i, choice in ipairs(CHOICES) do
    if select(1, bmp.parse(find_in(back, choice.name).data,
        #supplied[i] * 16, 16, 4)) ~= label(supplied[i]) then decoded = false end
  end
  check("all four button images decode from the changed descriptors", decoded)
  check("a button edit re-encodes stably",
    codec.encode(out, back, { prefix = "LOAD_SCREEN" }) == out)

  check_error("eleven button cells cannot fit the ten descriptors", function()
    codec.encode(sakura, {
      { name = "LOAD_SCREEN/COMMANDS_CHOICE_COPY.bmp",
        data = bmp.build(string.rep("\x0F", 64 * 8), 64, 16, 4) },
    }, { prefix = "LOAD_SCREEN" })
  end, "over the 10 available")

  local resized = codec.encode(sakura, {
    { name = CHOICES[2].name, data = bmp.build(label({ NEW[3], NEW[4] }), 32, 16, 4) },
    { name = CHOICES[4].name,
      data = bmp.build(label({ NEW[8], NEW[9], NEW[10] }), 48, 16, 4) },
  }, { prefix = "LOAD_SCREEN" })
  local expected = {
    [CHOICES[1]] = { count = 2, pointer = RAM_BASE + 0x59CAC },
    [CHOICES[2]] = { count = 2, pointer = RAM_BASE + 0x59CC0 },
    [CHOICES[3]] = { count = 3, pointer = RAM_BASE + 0x59C70 },
    [CHOICES[4]] = { count = 3, pointer = RAM_BASE + 0x59C8E },
  }
  local refs = { [CHOICES[1]] = 0, [CHOICES[2]] = 0,
    [CHOICES[3]] = 0, [CHOICES[4]] = 0 }
  local records_ok = true
  for pos = 0x59D00, 0x5A000, 0x10 do
    local old_pointer = string.unpack(">I4", sakura, pos + 5)
    for _, choice in ipairs(CHOICES) do
      local first_pointer = string.unpack(">I4", sakura, choice.parent + 5)
      if old_pointer == first_pointer then
        local count, pointer = string.unpack(">I2I4", resized, pos + 3)
        records_ok = records_ok and count == expected[choice].count
          and pointer == expected[choice].pointer
        refs[choice] = refs[choice] + 1
      end
    end
  end
  check("DELETE gains NO's cell in the same ten-record area", records_ok
    and refs[CHOICES[1]] == 3 and refs[CHOICES[2]] == 3
    and refs[CHOICES[3]] == 9 and refs[CHOICES[4]] == 9)
  check("the sprite records after the four buttons stay intact",
    resized:sub(0x59CD4 + 1, 0x59D00) == sakura:sub(0x59CD4 + 1, 0x59D00))
  local resized_art = codec.decode(resized, { prefix = "LOAD_SCREEN" })
  check("NO is 32px and DELETE is 48px after decode",
    bmp_header(find_in(resized_art, CHOICES[2].name).data).width == 32
    and bmp_header(find_in(resized_art, CHOICES[4].name).data).width == 48)
  check("resized buttons re-encode stably",
    codec.encode(resized, resized_art, { prefix = "LOAD_SCREEN" }) == resized)
end

------------------------------------------------------------------- rejection --
do
  local previous = {
    { 288, 224, "expected 288x176" }, -- the old LOAD_MENU, 48 rows too tall
    { 88, 64, "expected 112x50" },    -- the old LOAD_MENU_MEMCARD
    { 64, 14, "expected 56x16" },     -- the old LOAD_MENU_COPY_SOURCE
  }
  for i, case in ipairs(previous) do
    local width, height, message = case[1], case[2], case[3]
    check_error(("old %dx%d geometry is rejected"):format(width, height), function()
      codec.encode(sakura, {
        { name = "LOAD_SCREEN/" .. LAYOUT[i].name,
          data = bmp.build(string.rep("\0", width * height // 2), width, height, 4) },
      }, { prefix = "LOAD_SCREEN" })
    end, message)
  end

  check_error("an 8bpp artifact is rejected", function()
    codec.encode(sakura, {
      { name = "LOAD_SCREEN/LOAD_MENU_COPY_SOURCE.bmp",
        data = bmp.build(string.rep("\0", 56 * 16), 56, 16, 8) },
    }, { prefix = "LOAD_SCREEN" })
  end, "expected 4")

  check_error("a truncated artifact is rejected", function()
    codec.encode(sakura, {
      { name = "LOAD_SCREEN/LOAD_MENU_COPY_SOURCE.bmp", data = "BM" },
    }, { prefix = "LOAD_SCREEN" })
  end, "bmp")

  check_error("a non-BMP artifact is rejected", function()
    codec.encode(sakura, {
      { name = "LOAD_SCREEN/LOAD_MENU.bmp", data = string.rep("\0", 100) },
    }, { prefix = "LOAD_SCREEN" })
  end, "bmp")
end

-- Random pixels cannot fit the 2,292-byte slot.
local seed = 0x12345678
local random = {}
for i = 1, 288 * 176 // 2 do
  seed = seed ~ ((seed << 13) & 0xFFFFFFFF)
  seed = seed ~ (seed >> 17)
  seed = seed ~ ((seed << 5) & 0xFFFFFFFF)
  seed = seed & 0xFFFFFFFF
  random[i] = string.char(seed & 0xFF)
end
local random_bmp = bmp.build(table.concat(random), 288, 176, 4, real_palette)
check_error("compression budget is enforced", function()
  codec.encode(sakura, { { name = "LOAD_SCREEN/LOAD_MENU.bmp", data = random_bmp } },
    { prefix = "LOAD_SCREEN" })
end, "exceeds limit 2292")

-- Label geometry and the two label budgets.
local function label_edit(name, data)
  return codec.encode(sakura, { { name = name, data = data } }, { prefix = "LOAD_SCREEN" })
end

check_error("a 32-pixel-high label is rejected", function()
  label_edit(SINGLES[1].name, bmp.build(string.rep("\0", 48 * 16), 48, 32, 4))
end, "string is 16")

check_error("a label that is not a whole number of cells is rejected", function()
  label_edit(SINGLES[1].name, bmp.build(string.rep("\0", 40 * 8), 40, 16, 4))
end, "glyph pitch")

check_error("a label wider than the screen is rejected", function()
  label_edit(SINGLES[1].name, bmp.build(string.rep("\0", 304 * 8), 304, 16, 4))
end, "1..18")

check_error("a command sheet of the wrong size is rejected", function()
  label_edit("LOAD_SCREEN/COMMANDS_RESULT.bmp",
    bmp.build(string.rep("\0", 80 * 16 // 2), 80, 16, 4))
end, "expected 176 x 48")

check_error("an episode sheet of the wrong size is rejected", function()
  label_edit(EP_NAME, bmp.build(string.rep("\0", 80 * 8), 80, 16, 4))
end, "expected 80 x 160")

check_error("a title sheet of the wrong size is rejected", function()
  label_edit(TITLE_NAME, bmp.build(string.rep("\0", 80 * 160 // 2), 80, 160, 4))
end, "expected 208 x 160")

-- Every sheet drawn to its full width, both standalone labels drawn to the
-- 18-cell screen: far past the 762-byte string area, even after the dead
-- strings give their bytes up.
local function filled_sheet(cells, rows)
  local tile = string.rep("\x0F", TILE_BYTES)
  local out = {}
  for _ = 1, rows do
    for y = 0, 15 do
      out[#out + 1] = string.rep(tile:sub(y * 8 + 1, y * 8 + 8), cells)
    end
  end
  return bmp.build(table.concat(out), cells * 16, rows * 16, 4)
end

local function everything(provider)
  local all = {
    { name = EP_NAME, data = provider(EP_CELLS, EP_ROWS) },
    { name = TITLE_NAME, data = provider(TITLE_CELLS, TITLE_ROWS) },
    { name = SINGLES[1].name, data = provider(18, 1) },
    { name = SINGLES[2].name, data = provider(18, 1) },
  }
  for _, group in ipairs(GROUPS) do
    all[#all + 1] = { name = group.name, data = provider(group.cells, #group.indices) }
  end
  return all
end

check_error("the 762-byte string area is enforced", function()
  codec.encode(sakura, everything(filled_sheet), { prefix = "LOAD_SCREEN" })
end, "before the pointer table")

-- Distinct random cells: every cell of every sheet is its own tile, far over
-- the 192-tile sheet.
local noise_seed = 0x2468ACE0
local function noise_tile()
  local bytes = {}
  for i = 1, TILE_BYTES do
    noise_seed = noise_seed ~ ((noise_seed << 13) & 0xFFFFFFFF)
    noise_seed = noise_seed ~ (noise_seed >> 17)
    noise_seed = noise_seed ~ ((noise_seed << 5) & 0xFFFFFFFF)
    noise_seed = noise_seed & 0xFFFFFFFF
    bytes[i] = string.char(noise_seed & 0xFF)
  end
  return table.concat(bytes)
end

local function noise_sheet(cells, rows)
  local out = {}
  for _ = 1, rows do
    local lines = {}
    for y = 1, 16 do lines[y] = {} end
    for cell = 1, cells do
      local tile = noise_tile()
      for y = 0, 15 do lines[y + 1][cell] = tile:sub(y * 8 + 1, y * 8 + 8) end
    end
    for y = 1, 16 do out[#out + 1] = table.concat(lines[y]) end
  end
  return bmp.build(table.concat(out), cells * 16, rows * 16, 4)
end

check_error("the 192-tile sheet is enforced", function()
  codec.encode(sakura, everything(noise_sheet), { prefix = "LOAD_SCREEN" })
end, "distinct glyphs")

-- 143 distinct incompressible tiles: inside the tile cap, 18,304 bytes,
-- which cannot fit the 6,970-byte slot.
do
  local pool, n = {}, 0
  for i = 1, 143 do pool[i] = noise_tile() end
  local function pooled(cells, rows)
    local out = {}
    for _ = 1, rows do
      local lines = {}
      for y = 1, 16 do lines[y] = {} end
      for cell = 1, cells do
        n = n % 143 + 1
        local tile = pool[n]
        for y = 0, 15 do lines[y + 1][cell] = tile:sub(y * 8 + 1, y * 8 + 8) end
      end
      for y = 1, 16 do out[#out + 1] = table.concat(lines[y]) end
    end
    return bmp.build(table.concat(out), cells * 16, rows * 16, 4)
  end

  check_error("the font slot is enforced", function()
    codec.encode(sakura, everything(pooled), { prefix = "LOAD_SCREEN" })
  end, "compresses to")
end


-- A small edit may only pad up to the slot, never resize the file.
do
  local out = encode_one(1, string.char(0x05) .. load_pixels:sub(2))
  check("an edited stream stays inside the slot",
    #prs:decode(out:sub(BLOCK + 1, BLOCK + SLOT))[1].data == DECOMP_SIZE)
  check("the slot is padded, not resized", #out == #sakura)
  check("the slot keeps its own compressed length",
    out:sub(BLOCK + 1, BLOCK + SLOT) ==
      prs:encode("", { { name = "x",
        data = prs:decode(out:sub(BLOCK + 1, BLOCK + SLOT))[1].data } })
        .. string.rep("\0", SLOT - #prs:encode("", { { name = "x",
          data = prs:decode(out:sub(BLOCK + 1, BLOCK + SLOT))[1].data } })))
end

--------------------------------------------------------------------- disc 2 --
-- Disc 2 is the disc-1 payload at +0x138 for every block past 0x52E00, so the
-- synthetic file carries the palette, both PRS blocks and the string area.
local fake_disc2 = string.rep("\0", 0x60000)
local function place(fake, offset, source, length)
  return fake:sub(1, offset) .. source:sub(1, length)
    .. fake:sub(offset + length + 1)
end
fake_disc2 = place(fake_disc2, 0x5AED0, sakura:sub(PALETTE + 1), 32)
fake_disc2 = place(fake_disc2, 0x5E2C8, sakura:sub(BLOCK + 1), SLOT)
fake_disc2 = place(fake_disc2, 0x5C78C, sakura:sub(FONT + 1), FONT_SLOT)
fake_disc2 = place(fake_disc2, 0x5A1D6, sakura:sub(STRINGS + 1), STRING_BUDGET)
local formatting = sakura:sub(0x59C70 + 1, STRINGS)
for pos = 0x90, 0x390, 0x10 do
  local pointer = string.unpack(">I4", formatting, pos + 5)
  if pointer >= RAM_BASE + 0x59C70 and pointer < RAM_BASE + 0x59CD4 then
    formatting = formatting:sub(1, pos + 4)
      .. string.pack(">I4", pointer + 0x138) .. formatting:sub(pos + 9)
  end
end
fake_disc2 = place(fake_disc2, 0x59DA8, formatting, #formatting)

check("a synthetic disc-2-sized input is rejected",
  codec.can_handle(fake_disc2) == "no")
local disc2_arts = codec.decode(fake_disc2, { prefix = "D2", disc = 2 })
check("disc-2 decodes the same artifacts as disc 1",
  #disc2_arts == 3 + 2 + SHEET_ARTIFACTS + LABEL_ARTIFACTS + CHOICE_ARTIFACTS,
  tostring(#disc2_arts))
check("disc-2 pixels match disc 1",
  bmp.parse(disc2_arts[1].data, 288, 176, 4) == load_pixels)
check("disc-2 unmodified encode",
  codec.encode(fake_disc2, disc2_arts, { prefix = "D2", disc = 2 }) == fake_disc2)
local disc2_resized = codec.encode(fake_disc2, {
  { name = "D2/COMMANDS_CHOICE_NO.bmp",
    data = bmp.build(string.rep("\x01", 32 * 16 // 2), 32, 16, 4) },
  { name = "D2/COMMANDS_CHOICE_DELETE.bmp",
    data = bmp.build(string.rep("\x02", 48 * 16 // 2), 48, 16, 4) },
}, { prefix = "D2", disc = 2 })
local d2_delete_count, d2_delete_ptr = string.unpack(">I2I4", disc2_resized,
  0x59DA8 + 0x0B0 + 3)
local d2_no_count, d2_no_ptr = string.unpack(">I2I4", disc2_resized,
  0x59DA8 + 0x160 + 3)
check("disc-2 repacks the choice descriptors at its shifted offsets",
  d2_delete_count == 3 and d2_delete_ptr == RAM_BASE + 0x59DC6
  and d2_no_count == 2 and d2_no_ptr == RAM_BASE + 0x59DF8)
check("disc-2 resized buttons re-encode stably",
  codec.encode(disc2_resized,
    codec.decode(disc2_resized, { prefix = "D2", disc = 2 }),
    { prefix = "D2", disc = 2 }) == disc2_resized)
check("disc-2 is also addressed by a string argument",
  codec.decode(fake_disc2, "CD2")[1].name == "CD2/LOAD_MENU.bmp")

-- The palette travels with the file, not with the codec.
do
  local recoloured = fake_disc2:sub(1, 0x5AED0)
    .. string.rep("\xFF\x7F", 16)
    .. fake_disc2:sub(0x5AED0 + 32 + 1)
  local _, palette = bmp.parse(
    codec.decode(recoloured, { prefix = "P", disc = 2 })[1].data, 288, 176, 4)
  check("decode uses the palette of the decoded file",
    palette == bmp.from_bgr555(string.rep("\xFF\x7F", 16), 16))
end

-- Prefix forms must agree between decode and encode.
local prefix_forms = {
  { args = nil, dir = "LOAD_SCREEN", label = "default" },
  { args = "SUBDIR/", dir = "SUBDIR", label = "string with slash" },
  { args = { prefix = "SUBDIR" }, dir = "SUBDIR", label = "table" },
}
for _, case in ipairs(prefix_forms) do
  local named = codec.decode(sakura, case.args)
  check("prefix form: " .. case.label, named[1].name == case.dir .. "/LOAD_MENU.bmp",
    named[1].name)
  check("prefix round-trips: " .. case.label,
    codec.encode(sakura, named, case.args) == sakura)
end

print(string.format("%d passed, %d failed", pass, fail))
assert(fail == 0)
