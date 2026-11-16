--[[
  Tests for scripts/intro_logo_gfx.lua against the retail LOGO.SH2.

  The codec owns two things in the file: the PRS block at 0x25410 (83,584
  decompressed bytes, 13 linear 8bpp rectangles packed back to back) and the
  256-colour palette at 0x29124.  The block's slot is 15,123 bytes and the
  retail stream fills it, so the round trip proves the project encoder fits and
  an edit only spends the headroom it really has.

  The artwork covers nine rectangles: 大 and 戦 are three non-adjacent copies
  each, stacked into one BMP per glyph, so every copy gets its own write test.
]]

local codec = dofile(LUDARED.SCRIPTS .. "/intro_logo_gfx.lua")
local bmp = dofile(LUDARED.SCRIPTS .. "/shared/bmp.lua")
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

local file = assert(io.open(LUDARED.PROJECT_ROOT .. "/LOGO.SH2", "rb"),
  "the retail LOGO.SH2 is required")
local logo = file:read("*a")
file:close()

local BLOCK_OFFSET, BLOCK_SLOT, BLOCK_BYTES = 0x25410, 15123, 83584
local PALETTE_OFFSET, PALETTE_BYTES = 0x28F24, 512
local PALETTE_SPAN = 5 * PALETTE_BYTES
local PAINT_SLOT_AT = 0x29124

local IMAGES = {
  { name = "BACKDROP.bmp", width = 112, height = 136,
    parts = { { 0x000000, 136 } } },
  { name = "EMBLEM.bmp", width = 96, height = 96,
    parts = { { 0x003B80, 96 } } },
  { name = "SAKURA.bmp", width = 56, height = 456,
    parts = { { 0x005F80, 152 }, { 0x0080C0, 152 }, { 0x00A200, 152 } } },
  { name = "TAI.bmp", width = 64, height = 216,
    parts = { { 0x00C340, 72 }, { 0x00D540, 72 }, { 0x00E740, 72 } } },
  { name = "SEN.bmp", width = 64, height = 240,
    parts = { { 0x00F940, 80 }, { 0x010D40, 80 }, { 0x012140, 80 } } },
  { name = "MARK.bmp", width = 24, height = 24,
    parts = { { 0x013540, 24 } } },
  { name = "CAPTION.bmp", width = 160, height = 24,
    parts = { { 0x013780, 24 } } },
}

local function decompressed(data)
  return prs:decode(data:sub(BLOCK_OFFSET + 1, BLOCK_OFFSET + BLOCK_SLOT))[1].data
end

local function read_image(buffer, image)
  local out = {}
  for _, part in ipairs(image.parts) do
    out[#out + 1] = buffer:sub(part[1] + 1, part[1] + part[2] * image.width)
  end
  return table.concat(out)
end

local buffer = decompressed(logo)

local function artifact(list, name)
  for _, entry in ipairs(list) do
    if entry.name == name then return entry.data end
  end
end

local function poke(pixels, index)
  return pixels:sub(1, index - 1) .. string.char((pixels:byte(index) + 7) % 256)
    .. pixels:sub(index + 1)
end

local function ink_rows(offset, width, height)
  local first, last
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      if buffer:byte(offset + y * width + x + 1) ~= 0 then
        first = first or y
        last = y
        break
      end
    end
  end
  return first, last
end

print("block map")
check("the block decompresses to 83,584 bytes", #buffer == BLOCK_BYTES, tostring(#buffer))
do
  -- The thirteen rectangles tile the block exactly; a wrong size would show up
  -- as a gap once the last one is accounted for.
  local covered = 0
  for _, rect in ipairs({
    { 112, 136 }, { 96, 96 }, { 56, 152 }, { 56, 152 }, { 56, 152 },
    { 64, 72 }, { 64, 72 }, { 64, 72 }, { 64, 80 }, { 64, 80 }, { 64, 80 },
    { 24, 24 }, { 160, 24 },
  }) do
    covered = covered + rect[1] * rect[2]
  end
  check("the sprite rectangles add up to the block", covered == BLOCK_BYTES,
    string.format("%d vs %d", covered, BLOCK_BYTES))
end

print("ink bounds (the slack a rebalance could reclaim)")
do
  local first, last = ink_rows(0x012140, 64, 80)
  check("戦 ink spans rows 6..78 of its 80", first == 6 and last == 78,
    string.format("%s..%s", tostring(first), tostring(last)))
  first, last = ink_rows(0x00E740, 64, 72)
  check("大 ink reaches the last row of its 72", first == 0 and last == 71,
    string.format("%s..%s", tostring(first), tostring(last)))
  first, last = ink_rows(0x00A200, 56, 152)
  check("サクラ ink starts at row 2 of its 152", first == 2 and last == 151,
    string.format("%s..%s", tostring(first), tostring(last)))
  first, last = ink_rows(0x013540, 24, 24)
  check("the mark ink stops at row 17 of its 24", first == 0 and last == 17,
    string.format("%s..%s", tostring(first), tostring(last)))
  first, last = ink_rows(0x003B80, 96, 96)
  check("the emblem is inset 5 rows in its 96", first == 5 and last == 90,
    string.format("%s..%s", tostring(first), tostring(last)))
end

print("the fan layer")
local SWIRL_OFFSET, SWIRL_SLOT, SWIRL_BYTES = 0x24B8C, 1644, 5888
local SWIRL_MAP, SWIRL_COLUMNS, SWIRL_ROWS = 0x251F8, 19, 7
local function sheet(data)
  return prs:decode(data:sub(SWIRL_OFFSET + 1, SWIRL_OFFSET + SWIRL_SLOT))[1].data
end
-- The map at 0x251F8 names a tile per cell, as tile index * 2, big endian.
local function map_cell(data, cell)
  local at = SWIRL_MAP + cell * 4
  local value = data:byte(at + 1) * 0x1000000 + data:byte(at + 2) * 0x10000
    + data:byte(at + 3) * 0x100 + data:byte(at + 4)
  return value // 2
end
do
  local fan = sheet(logo)
  check("the fan decompresses to 5,888 bytes (92 8x8 tiles)", #fan == SWIRL_BYTES,
    tostring(#fan))
  check("the fan slot ends where the tile map starts",
    SWIRL_OFFSET + SWIRL_SLOT == 0x251F8)
  local repacked = prs:encode("", { { name = "S", data = fan } })
  check("the fan repacks inside its slot", #repacked <= SWIRL_SLOT,
    string.format("%d of %d", #repacked, SWIRL_SLOT))
  local map = logo:sub(0x251F8 + 1, 0x25410)
  check("the tile map is 134 entries", #map == 134 * 4, tostring(#map))
  local used, distinct = {}, 0
  for cell = 0, SWIRL_COLUMNS * SWIRL_ROWS - 1 do
    local tile = map_cell(logo, cell)
    if not used[tile] then used[tile] = true; distinct = distinct + 1 end
  end
  -- 91 of the 92: the sheet's last tile is never placed by the first 133 cells.
  check("its 133 cells name 91 of the 92 tiles the sheet holds", distinct == 91,
    tostring(distinct))
  -- 19 x 7 cells of 8x8 is the word's 152x56, the size of VDP2/IntoroLogo.tsx.
  check("19 x 7 cells is a 152x56 picture",
    SWIRL_COLUMNS * 8 == 152 and SWIRL_ROWS * 8 == 56)
end

print("decode")
local artifacts = codec.decode(logo, "INTRO_LOGO")
check("nine artifacts: the word, seven pieces and the layout", #artifacts == 9,
  tostring(#artifacts))
do
  local fan = artifact(artifacts, "INTRO_LOGO/SWIRL.bmp")
  local ok = fan ~= nil
  local pixels
  if fan then pixels = bmp.parse(fan, 152, 56, 8); ok = #pixels == 152 * 56 end
  check("the word is emitted untiled, as a 152x56 picture", ok)
  -- Cell 0 of the map is the top-left tile, and its 64 bytes run column-major.
  local raw = sheet(logo)
  local first = map_cell(logo, 0) * 64
  local same = true
  for row = 0, 7 do
    for column = 0, 7 do
      if pixels:byte(row * 152 + column + 1) ~= raw:byte(first + column * 8 + row + 1) then
        same = false
      end
    end
  end
  check("cell 0 lands in the corner, its bytes read column-major", same)
  -- Column-major cells: cell 1 is the second tile down the first column.
  local second = map_cell(logo, 1) * 64
  local vertical = true
  for row = 0, 7 do
    for column = 0, 7 do
      if pixels:byte((row + 8) * 152 + column + 1)
        ~= raw:byte(second + column * 8 + row + 1) then
        vertical = false
      end
    end
  end
  check("cell 1 sits below cell 0, not beside it", vertical)
end

print("the fan in the turned arrangement")
do
  -- The swapped conversion words at 0x387A/0x387E are what take the layer's
  -- rotation away, and the same picture then has to be stored plainly: cell 0
  -- is the top-left tile, its 64 bytes are eight rows of eight pixels, and the
  -- map names tiles from 1.  Keeping the retail arrangement under those words
  -- is what made the fan arrive on screen as shreds.
  local turned = logo:sub(1, 0x387A) .. "\xE7\x07" .. logo:sub(0x387D, 0x387E)
    .. "\xE6\x13" .. logo:sub(0x3881)
  check("the swapped pair fits the two words", #turned == #logo)
  local list = codec.decode(turned, "INTRO_LOGO")
  local fan = artifact(list, "INTRO_LOGO/SWIRL.bmp")
  local pixels = fan and bmp.parse(fan, 152, 56, 8)
  check("the turned word is still a 152x56 picture", pixels ~= nil)
  local raw = sheet(turned)
  local first = map_cell(turned, 0) * 64
  local same = true
  for row = 0, 7 do
    for column = 0, 7 do
      if pixels:byte(row * 152 + column + 1) ~= raw:byte(first + row * 8 + column + 1) then
        same = false
      end
    end
  end
  check("cell 0 is the top-left tile, its bytes read row by row", same)
  local beside = true
  local second = map_cell(turned, 1) * 64
  for row = 0, 7 do
    for column = 0, 7 do
      if pixels:byte(row * 152 + column + 9)
        ~= raw:byte(second + row * 8 + column + 1) then
        beside = false
      end
    end
  end
  check("cell 1 sits beside cell 0, not below it", beside)
  local lowest = 99
  for cell = 0, SWIRL_COLUMNS * SWIRL_ROWS - 1 do
    lowest = math.min(lowest, map_cell(turned, cell))
  end
  check("the map names tiles from 1, never the empty tile 0", lowest == 1,
    tostring(lowest))
  local retail_fan = artifact(codec.decode(logo, "INTRO_LOGO"), "INTRO_LOGO/SWIRL.bmp")
  check("the retail words read the same bytes as the turned word",
    retail_fan ~= fan)
end

print("the sprite layout")
do
  local layout = artifact(artifacts, "INTRO_LOGO/LAYOUT.csv")
  local rows = {}
  for line in layout:gmatch("[^\r\n]+") do rows[#rows + 1] = line end
  check("LAYOUT.csv is a header and twelve sprites", #rows == 13, tostring(#rows))
  check("its header names the six fields", rows[1] == "index,x,y,w,h,file", rows[1])
  -- row 2 is sprite 0, so sprite n is row n + 2.
  check("it carries the サクラ records at -24,-104",
    rows[5] == "3,-24,-104,56,152,SAKURA.bmp", rows[5])
  -- Each line names the artwork its record places; a glyph owns one record per
  -- copy it has in the block.
  local owners = {}
  for index = 0, 11 do
    owners[index] = rows[index + 2]:match(",([^,]*)$")
  end
  local wanted = {
    [0] = "EMBLEM.bmp",
    [1] = "SAKURA.bmp", [2] = "SAKURA.bmp", [3] = "SAKURA.bmp",
    [4] = "TAI.bmp", [5] = "TAI.bmp", [6] = "TAI.bmp",
    [7] = "SEN.bmp", [8] = "SEN.bmp", [9] = "SEN.bmp",
    [10] = "MARK.bmp", [11] = "CAPTION.bmp",
  }
  local misnamed = 0
  for index = 0, 11 do
    if owners[index] ~= wanted[index] then misnamed = misnamed + 1 end
  end
  check("every line names the file it draws", misnamed == 0, tostring(misnamed))
  -- The background is not a sprite, so none of the twelve places it.
  local placed = {}
  for index = 0, 11 do placed[owners[index]] = true end
  check("BACKDROP.bmp is not placed by any sprite record",
    not placed["BACKDROP.bmp"] and not placed[""])
  check("it carries the TM at -49,14",
    rows[12] == "10,-49,14,24,24,MARK.bmp", rows[12])

  -- Moving the TM writes its four placement fields and nothing else.  The line
  -- keeps its file name, and the name is ignored either way.
  local moved = layout:gsub("10,%-49,14,24,24", "10,10,-12,24,24")
  check("the moved line keeps its file name",
    moved:find("10,10,%-12,24,24,MARK%.bmp", 1) ~= nil)
  local out = codec.encode(logo, {
    { name = "INTRO_LOGO/LAYOUT.csv", data = moved },
  }, "INTRO_LOGO")
  local at = 0x6260 + 10 * 14
  check("LAYOUT.csv moves the TM record",
    out:sub(at + 1, at + 8) == string.char(0, 10, 0xFF, 0xF4, 0, 24, 0, 24))
  check("the art pointer and flags of that sprite stay retail",
    out:sub(at + 9, at + 14) == logo:sub(at + 9, at + 14))
  check("nothing else in the file moves",
    out:sub(1, at) == logo:sub(1, at) and out:sub(at + 9) == logo:sub(at + 9))

  -- The US release's own positions, as read from its sprite table at 0x70A0:
  -- サクラ turned, 大 repointed at the 戦 art, TM shifted right.
  local us = layout
    :gsub("1,%-24,%-104,56,152", "1,-128,-48,152,56")
    :gsub("2,%-24,%-104,56,152", "2,-128,-48,152,56")
    :gsub("3,%-24,%-104,56,152", "3,-128,-48,152,56")
    :gsub("6,%-96,%-40,64,72", "6,-16,-32,64,80")
    :gsub("9,%-96,8,64,80", "9,-16,-32,64,80")
  local patched = codec.encode(logo, {
    { name = "INTRO_LOGO/LAYOUT.csv", data = us },
  }, "INTRO_LOGO")
  local turned, tai, sen = 0x6260 + 3 * 14, 0x6260 + 6 * 14, 0x6260 + 9 * 14
  check("the US サクラ record is written",
    patched:sub(turned + 1, turned + 8)
    == string.char(0xFF, 0x80, 0xFF, 0xD0, 0, 0x98, 0, 0x38))
  check("the US 大 record is written",
    patched:sub(tai + 1, tai + 8)
    == string.char(0xFF, 0xF0, 0xFF, 0xE0, 0, 0x40, 0, 0x50))
  check("the US 戦 record is written",
    patched:sub(sen + 1, sen + 8)
    == string.char(0xFF, 0xF0, 0xFF, 0xE0, 0, 0x40, 0, 0x50))
end

for _, image in ipairs(IMAGES) do
  local picture = artifact(artifacts, "INTRO_LOGO/" .. image.name)
  check(image.name .. " is emitted", picture ~= nil)
  if picture then
    local pixels, palette = bmp.parse(picture, image.width, image.height, 8)
    check(image.name .. " pixels are the retail ones", pixels == read_image(buffer, image))
    check(image.name .. " is painted with PALETTE1",
      palette == bmp.from_bgr555(logo:sub(PAINT_SLOT_AT + 1,
        PAINT_SLOT_AT + PALETTE_BYTES), 256))
  end
end
check("the default prefix is INTRO_LOGO",
  codec.decode(logo)[1].name == "INTRO_LOGO/SWIRL.bmp", codec.decode(logo)[1].name)
check("a custom prefix is used",
  artifact(codec.decode(logo, "X/Y/"), "X/Y/SEN.bmp") ~= nil)

print("can_handle")
check("the shipped file is certain", codec.can_handle(logo) == "certain",
  codec.can_handle(logo))
check("a short file is a no", codec.can_handle(logo:sub(1, 100)) == "no")
check("a non-string is a no", codec.can_handle(nil) == "no")

-- A rebuilt or disc-2 module keeps the same block and palette; only code below
-- 0x6020 moved, so a changed file is still recognised -- as "likely".
local nudge = logo:sub(1, 0x200) .. string.char((logo:byte(0x201) + 1) % 256)
  .. logo:sub(0x202)
check("a file that is not the shipped build is likely",
  codec.can_handle(nudge) == "likely", codec.can_handle(nudge))
check("a file with a broken fan slot is a no",
  codec.can_handle(logo:sub(1, 0x24B8C) .. string.rep("\xFF", 16)
    .. logo:sub(0x24B8C + 17)) == "no")

print("round trip")
check("an untouched decode re-encodes to the original",
  codec.encode(logo, artifacts, "INTRO_LOGO") == logo)

print("every rectangle writes to its own offset")
for _, image in ipairs(IMAGES) do
  local picture = artifact(artifacts, "INTRO_LOGO/" .. image.name)
  local pixels, palette = bmp.parse(picture, image.width, image.height, 8)
  local row = 0
  for index, part in ipairs(image.parts) do
    local local_row = math.min(5, part[2] - 1)
    local column = 5
    local pixel = (row + local_row) * image.width + column + 1
    local edited = poke(pixels, pixel)
    local out = decompressed(codec.encode(logo, {
      { name = "INTRO_LOGO/" .. image.name,
        data = bmp.build(edited, image.width, image.height, 8, palette) },
    }, "INTRO_LOGO"))

    local landed = part[1] + local_row * image.width + column + 1
    check(string.format("%s copy %d -> 0x%05X", image.name, index, landed - 1),
      out:byte(landed) == edited:byte(pixel),
      string.format("%d vs %d", out:byte(landed), edited:byte(pixel)))
    check(string.format("%s copy %d changed nothing else", image.name, index),
      out:sub(1, landed - 1) .. out:sub(landed + 1)
      == buffer:sub(1, landed - 1) .. buffer:sub(landed + 1))
    row = row + part[2]
  end
end

print("the block still fits")
do
  local picture = artifact(artifacts, "INTRO_LOGO/SAKURA.bmp")
  local pixels, palette = bmp.parse(picture, 56, 456, 8)
  local rebuilt = codec.encode(logo, {
    { name = "INTRO_LOGO/SAKURA.bmp",
      data = bmp.build(poke(pixels, 500), 56, 456, 8, palette) },
  }, "INTRO_LOGO")
  local compressed = prs:encode("", { { name = "INTRO_LOGO",
    data = decompressed(rebuilt) } })
  check("an edited block fits the 15,123-byte slot", #compressed <= BLOCK_SLOT,
    string.format("%d of %d", #compressed, BLOCK_SLOT))
  check("the palette is untouched by a pixel edit",
    rebuilt:sub(PALETTE_OFFSET + 1, PALETTE_OFFSET + PALETTE_BYTES)
    == logo:sub(PALETTE_OFFSET + 1, PALETTE_OFFSET + PALETTE_BYTES))
  check("everything before the block is unchanged",
    rebuilt:sub(1, BLOCK_OFFSET) == logo:sub(1, BLOCK_OFFSET))
  check("everything after the slot is unchanged",
    rebuilt:sub(BLOCK_OFFSET + BLOCK_SLOT + 1) == logo:sub(BLOCK_OFFSET + BLOCK_SLOT + 1))
  check("the file keeps its size", #rebuilt == #logo)
end

print("the turned サクラ (the US layout)")
-- PatchIntroLogo writes the glyph with rows of 152 and patches one sprite record;
-- supplying a 152x56 BMP has to do exactly that, and the vertical BMP undo it.
local function transpose(pixels, width, height)
  local rows = {}
  for y = 1, height do
    rows[y] = pixels:sub((y - 1) * width + 1, y * width)
  end
  local out = {}
  for x = 1, width do
    local column = {}
    for y = 1, height do column[y] = rows[y]:sub(x, x) end
    out[x] = table.concat(column)
  end
  return table.concat(out)
end

do
  local vertical, palette = bmp.parse(artifact(artifacts, "INTRO_LOGO/SAKURA.bmp"),
    56, 456, 8)
  -- The three states turn on their own: transposing the stacked 56x456 picture
  -- as one image would give 456x56, which is not the turned geometry.
  local function turn(pixels)
    local frames = {}
    for frame = 0, 2 do
      frames[frame + 1] = transpose(pixels:sub(frame * 8512 + 1, (frame + 1) * 8512),
        56, 152)
    end
    return table.concat(frames)
  end
  local turned_pixels = turn(vertical)
  check("the three turned states are 152x168", #turned_pixels == 152 * 168,
    tostring(#turned_pixels))

  local out = codec.encode(logo, {
    { name = "INTRO_LOGO/SAKURA.bmp",
      data = bmp.build(turned_pixels, 152, 168, 8, palette) },
  }, "INTRO_LOGO")

  -- Records 1, 2 and 3 all take the US rectangle: the two flat states sit under
  -- the colour copy, so the word never drops out between them.
  local rect = "\xFF\x80\xFF\xD0\x00\x98\x00\x38"
  local turned_records = out:sub(0x626E + 1, 0x626E + 8) == rect
    and out:sub(0x627C + 1, 0x627C + 8) == rect
    and out:sub(0x628A + 1, 0x628A + 8) == rect
  check("a 152x168 SAKURA patches all three records", turned_records,
    (out:sub(0x626E + 1, 0x628A + 8):gsub(".", function(c)
      return string.format("%02X", c:byte()) end)))
  local block = decompressed(out)
  check("the three states are stored at 0x5F80, 0x80C0 and 0xA200, rows of 152",
    block:sub(0x5F80 + 1, 0x5F80 + 8512) == turned_pixels:sub(1, 8512)
    and block:sub(0x80C0 + 1, 0x80C0 + 8512) == turned_pixels:sub(8513, 8512 * 2)
    and block:sub(0xA200 + 1, 0xA200 + 8512) == turned_pixels:sub(8512 * 2 + 1))

  -- The horizontal word also brings the US entrance with it: the module is told
  -- the map's two dimensions the other way round and gets the third argument of
  -- that same call, and then the fan travels in across the middle of the screen.
  check("a 152x56 SAKURA swaps the fan's motion arguments",
    out:sub(0x387A + 1, 0x387A + 2) == "\xE7\x07"
    and out:sub(0x387E + 1, 0x387E + 2) == "\xE6\x13",
    (out:sub(0x387A + 1, 0x387A + 1):gsub(".", function(c)
      return string.format("%02X", c:byte()) end))
    .. " " .. (out:sub(0x387E + 1, 0x387E + 1):gsub(".", function(c)
      return string.format("%02X", c:byte()) end)))
  check("and the third argument of the same call",
    out:sub(0x392A + 1, 0x392A + 2) == "\x48\x10",
    (out:sub(0x392A + 1, 0x392A + 2):gsub(".", function(c)
      return string.format("%02X", c:byte()) end)))
  check("the three motion words are the only code it touches",
    out:sub(1, 0x387A) == logo:sub(1, 0x387A)
    and out:sub(0x387A + 3, 0x387E) == logo:sub(0x387A + 3, 0x387E)
    and out:sub(0x387E + 3, 0x392A) == logo:sub(0x387E + 3, 0x392A)
    and out:sub(0x392A + 3, 0x6260) == logo:sub(0x392A + 3, 0x6260)
    and out:sub(0x6293, BLOCK_OFFSET) == logo:sub(0x6293, BLOCK_OFFSET))
  check("only the block, the three records and the motion words moved",
    out:sub(0x628A + 9, BLOCK_OFFSET) == logo:sub(0x628A + 9, BLOCK_OFFSET)
    and out:sub(BLOCK_OFFSET + BLOCK_SLOT + 1) == logo:sub(BLOCK_OFFSET + BLOCK_SLOT + 1))

  local turned_decoded = codec.decode(out, "INTRO_LOGO")
  local picture = artifact(turned_decoded, "INTRO_LOGO/SAKURA.bmp")
  local ok = pcall(bmp.parse, picture, 152, 168, 8)
  check("decode hands back 152x168 once the record is turned", ok)
  check("re-encoding the turned build unchanged is byte-identical",
    codec.encode(out, turned_decoded, "INTRO_LOGO") == out)

  local back = codec.encode(out, {
    { name = "INTRO_LOGO/SAKURA.bmp", data = bmp.build(vertical, 56, 456, 8, palette) },
  }, "INTRO_LOGO")
  check("the vertical artwork restores the retail records",
    back:sub(0x626E + 1, 0x628A + 8) == logo:sub(0x626E + 1, 0x628A + 8))
  check("and retail's motion arguments",
    back:sub(0x387A + 1, 0x387A + 2) == "\xE7\x13"
    and back:sub(0x387E + 1, 0x387E + 2) == "\xE6\x07"
    and back:sub(0x392A + 1, 0x392A + 2) == "\x41\x44")
  -- The stream itself is re-encoded (and comes out shorter than retail, so the
  -- slot is zero padded): everything around it has to be the retail file again.
  check("and everything around the stream comes back",
    #back == #logo and back:sub(1, BLOCK_OFFSET) == logo:sub(1, BLOCK_OFFSET)
    and back:sub(BLOCK_OFFSET + BLOCK_SLOT + 1) == logo:sub(BLOCK_OFFSET + BLOCK_SLOT + 1))
  check("the restored block decompresses to the retail buffer",
    decompressed(back) == buffer)
end

print("editing the fan")
do
  local picture = artifact(artifacts, "INTRO_LOGO/SWIRL.bmp")
  local pixels, palette = bmp.parse(picture, 152, 56, 8)
  -- Cells that share a tile cannot be repainted apart, so edit one whose tile the
  -- map uses once: that cell keeps its retail slot and the map stays put.
  local usage, alone = {}, nil
  for cell = 0, SWIRL_COLUMNS * SWIRL_ROWS - 1 do
    local tile = map_cell(logo, cell)
    usage[tile] = (usage[tile] or 0) + 1
    if not alone then alone = cell end
  end
  for cell = 0, SWIRL_COLUMNS * SWIRL_ROWS - 1 do
    if usage[map_cell(logo, cell)] == 1 then alone = cell break end
  end
  -- Column 4, row 1 of that cell is tile byte 4 * 8 + 1 = 33.
  local at = ((alone % SWIRL_ROWS) * 8 + 1) * 152 + (alone // SWIRL_ROWS) * 8 + 4 + 1
  local byte = map_cell(logo, alone) * 64 + 33 + 1
  local out = codec.encode(logo, {
    { name = "INTRO_LOGO/SWIRL.bmp", data = bmp.build(poke(pixels, at), 152, 56, 8,
      palette) },
  }, "INTRO_LOGO")
  check("a word pixel lands in the right tile byte at 0x24B8C",
    sheet(out):byte(byte) == (pixels:byte(at) + 7) % 256,
    string.format("%d vs %d", sheet(out):byte(byte), (pixels:byte(at) + 7) % 256))
  check("a cell with a tile of its own leaves the map alone",
    out:sub(SWIRL_MAP + 1, 0x25410) == logo:sub(SWIRL_MAP + 1, 0x25410))
  check("the fan edit leaves the glyph block alone",
    out:sub(BLOCK_OFFSET + 1, BLOCK_OFFSET + BLOCK_SLOT)
    == logo:sub(BLOCK_OFFSET + 1, BLOCK_OFFSET + BLOCK_SLOT))
  check("the whole file round-trips with an untouched fan",
    codec.encode(logo, codec.decode(logo, "INTRO_LOGO"), "INTRO_LOGO") == logo)
end

print("the palette is read-only")
do
  local slot = PALETTE_OFFSET + PALETTE_BYTES          -- 0x29124
  check("the slot after the first one is 0x29124", PAINT_SLOT_AT == slot)

  local picture = artifact(artifacts, "INTRO_LOGO/EMBLEM.bmp")
  local pixels, palette = bmp.parse(picture, 96, 96, 8)
  -- A whole 5-bit step on entry 0's blue channel, as an editor would do.
  local recoloured = palette:sub(1, 1) .. string.char((palette:byte(2) + 8) % 256)
    .. palette:sub(3)
  check("a recoloured BMP palette is refused", not pcall(function()
    codec.encode(logo, {
      { name = "INTRO_LOGO/EMBLEM.bmp",
        data = bmp.build(pixels, 96, 96, 8, recoloured) },
    }, "INTRO_LOGO")
  end))

  -- Re-saving the same colours (or touching the ignored alpha byte) is accepted
  -- and changes nothing at all.
  local alpha = palette:sub(1, 3) .. string.char(77) .. palette:sub(5)
  local out = codec.encode(logo, { { name = "INTRO_LOGO/EMBLEM.bmp",
    data = bmp.build(pixels, 96, 96, 8, alpha) } }, "INTRO_LOGO")
  check("an alpha-only change is accepted and writes nothing", out == logo)
  check("none of the five palettes is written",
    out:sub(PALETTE_OFFSET + 1, PALETTE_OFFSET + PALETTE_SPAN)
    == logo:sub(PALETTE_OFFSET + 1, PALETTE_OFFSET + PALETTE_SPAN))
end

print("guards")
do
  local picture = artifact(artifacts, "INTRO_LOGO/EMBLEM.bmp")
  local pixels, palette = bmp.parse(picture, 96, 96, 8)
  -- One palette for the screen: two BMPs that disagree cannot both be honoured.
  local mark_pixels, mark_palette = bmp.parse(
    artifact(artifacts, "INTRO_LOGO/MARK.bmp"), 24, 24, 8)
  check("two BMPs with different palettes are refused", not pcall(function()
    codec.encode(logo, {
      { name = "INTRO_LOGO/EMBLEM.bmp", data = bmp.build(pixels, 96, 96, 8,
        palette:sub(1, 2) .. string.char(120) .. palette:sub(4)) },
      { name = "INTRO_LOGO/MARK.bmp", data = bmp.build(mark_pixels, 24, 24, 8,
        mark_palette:sub(1, 2) .. string.char(9) .. mark_palette:sub(4)) },
    }, "INTRO_LOGO")
  end))
  check("a wrong-sized artwork is refused", not pcall(function()
    codec.encode(logo, { { name = "INTRO_LOGO/EMBLEM.bmp",
      data = bmp.build(pixels:sub(1, 96 * 80), 96, 80, 8, palette) } }, "INTRO_LOGO")
  end))
  check("a wrong-sized SEN is refused", not pcall(function()
    codec.encode(logo, { { name = "INTRO_LOGO/SEN.bmp",
      data = bmp.build(pixels:sub(1, 64 * 160), 64, 160, 8, palette) } }, "INTRO_LOGO")
  end))
end

print(string.format("\n%d passed, %d failed", pass, fail))
assert(fail == 0, "intro logo codec tests failed")
