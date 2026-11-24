--[[
  Tests for scripts/intro_credits_gfx.lua against the retail LOGO.SH2.

  LOGO.SH2 holds four PRS blocks: the credits tiles, the credits tile map, the
  logo tiles and the logo tile map.  The codec exposes only the two 320x224
  screens; a tile map is rebuilt by deduplicating the screen's 8x8 cells in
  screen order, which is exactly what the retail maps are.

  The retail credits tile block compresses to 6,885 bytes of its 6,889-byte
  slot, so the tests below free room before adding new cells: that is the real
  editing constraint, not a rule of the codec.
]]

local codec = dofile(LUDARED.SCRIPTS .. "/intro_credits_gfx.lua")
local bmp = dofile(LUDARED.SCRIPTS .. "/shared/bmp.lua")
local palettes = dofile(LUDARED.SCRIPTS .. "/shared/palettes.lua")
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

local file = assert(io.open(LUDARED.PROJECT_ROOT .. "/LOGO.SH2", "rb"),
  "the retail LOGO.SH2 is required")
local logo = file:read("*a")
file:close()

local OFFSETS = {
  credits_tiles = { off = 0x32EDC, slot = 6889 },
  credits_map   = { off = 0x349C8, slot = 916 },
  logo_tiles    = { off = 0x35924, slot = 777 },
  logo_map      = { off = 0x35C30, slot = 208 },
}

local function block(data, name)
  local spec = OFFSETS[name]
  return prs:decode(data:sub(spec.off + 1, spec.off + spec.slot))[1].data
end

local credits_tiles = block(logo, "credits_tiles")
local credits_map   = block(logo, "credits_map")
local logo_tiles    = block(logo, "logo_tiles")
local logo_map      = block(logo, "logo_map")

local WIDTH, HEIGHT = 320, 224
local ROW_BYTES = 160
local CELLS = 40 * 28

local function word(map, cell)
  return string.unpack(">I4", map, cell * 4 + 1)
end

local function mapped_cell(tiles, map, cell)
  local index = word(map, cell) & 0x7FFFFFFF
  return tiles:sub(index * 32 + 1, index * 32 + 32)
end

-- Independent first-appearance dedupe, to check the retail maps really are one.
local function dedupe(tiles, map)
  local seen, order, words = {}, {}, {}
  for cell = 0, CELLS - 1 do
    local data = mapped_cell(tiles, map, cell)
    local index = seen[data]
    if not index then
      index = #order
      order[#order + 1] = data
      seen[data] = index
    end
    words[#words + 1] = string.pack(">I4", index)
  end
  return table.concat(order), table.concat(words)
end

-- Independent screen reconstruction: for every screen row, concatenate the
-- 8 row-bytes each 8x8 cell shows.
local function screen(tiles, map)
  local tile_count = #tiles // 32
  local rows = {}
  for y = 0, HEIGHT - 1 do
    local parts = {}
    for column = 0, 39 do
      local cell = (y // 8) * 40 + column
      local index = word(map, cell) & 0x7FFFFFFF
      assert(index < tile_count, "map index out of range")
      local start = index * 32 + (y % 8) * 4
      parts[#parts + 1] = tiles:sub(start + 1, start + 4)
    end
    rows[#rows + 1] = table.concat(parts)
  end
  return table.concat(rows)
end

local function read_cell(pixels, cell)
  local left = (cell % 40) * 4 + 1
  local top = (cell // 40) * 8
  local parts = {}
  for inner = 0, 7 do
    local start = (top + inner) * ROW_BYTES + left
    parts[#parts + 1] = pixels:sub(start, start + 3)
  end
  return table.concat(parts)
end

local function write_cell(pixels, cell, data)
  local left = (cell % 40) * 4
  local top = (cell // 40) * 8
  for inner = 0, 7 do
    local start = (top + inner) * ROW_BYTES + left + 1
    pixels = pixels:sub(1, start - 1) .. data:sub(inner * 4 + 1, inner * 4 + 4)
      .. pixels:sub(start + 4)
  end
  return pixels
end

-- Set one nibble of the screen: x, y in pixels, v the palette index.
local function edit_pixel(pixels, x, y, value)
  local offset = y * ROW_BYTES + x // 2
  local byte = pixels:byte(offset + 1)
  local new_byte
  if (x % 2) == 0 then
    new_byte = (value << 4) | (byte & 0x0F)
  else
    new_byte = (byte & 0xF0) | value
  end
  return pixels:sub(1, offset) .. string.char(new_byte) .. pixels:sub(offset + 2)
end

-- Erase the first ink pixel of a cell; returns pixels plus its coordinates.
local function erase_ink(pixels, cell)
  local left = (cell % 40) * 4
  local top = (cell // 40) * 8
  for inner = 0, 7 do
    for byte = 0, 3 do
      local value = pixels:byte((top + inner) * ROW_BYTES + left + byte + 1)
      if value >> 4 ~= 0 then
        return edit_pixel(pixels, (left + byte) * 2, top + inner, 0), true
      elseif value & 0x0F ~= 0 then
        return edit_pixel(pixels, (left + byte) * 2 + 1, top + inner, 0), true
      end
    end
  end
  return pixels, false
end

local function encode_screen(name, pixels, palette)
  return codec.encode(logo, {
    { name = "INTRO/" .. name, data = bmp.build(pixels, WIDTH, HEIGHT, 4, palette) },
  }, { prefix = "INTRO" })
end

local function decode_credits(data)
  return bmp.parse(codec.decode(data, { prefix = "I" })[1].data, WIDTH, HEIGHT, 4)
end

print("test_intro_credits.lua")

check("LOGO.SH2 size", #logo == 243200, tostring(#logo))
check("credits tiles are 311", #credits_tiles == 9952, tostring(#credits_tiles))
check("credits map is 1,120 words", #credits_map == 4480, tostring(#credits_map))
check("logo tiles are 55", #logo_tiles == 1760, tostring(#logo_tiles))
check("logo map is 1,120 words", #logo_map == 4480, tostring(#logo_map))

-- The retail maps are exactly a first-appearance dedupe of the screen; that is
-- what lets the codec rebuild them instead of storing them.
local dt, dm = dedupe(credits_tiles, credits_map)
check("credits tiles are first-appearance order", dt == credits_tiles)
check("credits map is first-appearance order", dm == credits_map)
local lt, lm = dedupe(logo_tiles, logo_map)
check("logo tiles are first-appearance order", lt == logo_tiles)
check("logo map matches apart from the flag", (function()
  for cell = 0, CELLS - 1 do
    local expected = word(lm, cell)
    if cell == 15 * 40 + 14 then expected = expected | 0x80000000 end
    if word(logo_map, cell) ~= expected then return false end
  end
  return true
end)())
check("logo map keeps its flagged word", word(logo_map, 15 * 40 + 14) == 0x80000004)

check("can_handle real LOGO.SH2", codec.can_handle(logo) == "certain")
check("decode_name default", codec.decode_name(nil) == "INTRO_CREDITS")

local arts = codec.decode(logo, { prefix = "INTRO" })
check("two artifacts, no tile maps", #arts == 2, tostring(#arts))
check("artifact names",
  arts[1].name == "INTRO/CREDITS.bmp"
  and arts[2].name == "INTRO/LOGO.bmp")

local credits_pixels, credits_palette = bmp.parse(arts[1].data, WIDTH, HEIGHT, 4)
check("credits artifact is a 320x224 screen", #credits_pixels == 35840)
check("credits screen matches the tiles",
  credits_pixels == screen(credits_tiles, credits_map))
check("credits screen uses the shared ADV BMP palette", credits_palette == codec.DISPLAY_PALETTE)
check("display palette is adv_dialogue_jp_for_bmp",
  codec.DISPLAY_PALETTE == bmp.from_bgr555(palettes.raw("adv_dialogue_jp_for_bmp"), 16))

local logo_pixels, logo_palette = bmp.parse(arts[2].data, WIDTH, HEIGHT, 4)
check("logo artifact is a 320x224 screen", #logo_pixels == 35840)
check("logo screen matches the tiles", logo_pixels == screen(logo_tiles, logo_map))
check("logo screen uses the extractor palette", logo_palette == codec.DISPLAY_PALETTE)

check("unmodified encode is byte-identical",
  codec.encode(logo, arts, { prefix = "INTRO" }) == logo)

local function cell_has_ink(px, column, row)
  local left = column * 4 + 1
  for inner = 0, 7 do
    local line = px:sub((row * 8 + inner) * ROW_BYTES + left,
      (row * 8 + inner) * ROW_BYTES + left + 3)
    if line ~= "\0\0\0\0" then return true end
  end
  return false
end
check("credits screen has its first text row", cell_has_ink(credits_pixels, 1, 1))
check("credits screen is blank at the top", not cell_has_ink(credits_pixels, 1, 0))

-- Erasing one pixel of a glyph: the only change on the whole file is that tile.
local erased, found = erase_ink(credits_pixels, 41)
check("cell (row 1, column 1) has ink to erase", found)
local erased_file = encode_screen("CREDITS.bmp", erased, credits_palette)
check("pixel edit survives", decode_credits(erased_file) == erased)
check("pixel edit changes only the credits tile block",
  erased_file:sub(1, OFFSETS.credits_tiles.off) == logo:sub(1, OFFSETS.credits_tiles.off)
  and erased_file:sub(OFFSETS.credits_map.off) == logo:sub(OFFSETS.credits_map.off))
check("credits map rebuilt identically", block(erased_file, "credits_map") == credits_map)
check("logo blocks untouched by a credits edit",
  block(erased_file, "logo_tiles") == logo_tiles
  and block(erased_file, "logo_map") == logo_map)

-- Erasing a whole cell drops its tile: the map is rebuilt and the blank cells
-- keep sharing the one blank tile.
local blanked = write_cell(credits_pixels, 41, string.rep("\0", 32))
local blanked_file = encode_screen("CREDITS.bmp", blanked, credits_palette)
local blanked_map = block(blanked_file, "credits_map")
check("erasing a cell drops its tile", #block(blanked_file, "credits_tiles") == 310 * 32,
  tostring(#block(blanked_file, "credits_tiles")))
check("erased cell decodes blank", read_cell(decode_credits(blanked_file), 41)
  == string.rep("\0", 32))
check("erased cell joins the blank tile",
  word(blanked_map, 41) == word(blanked_map, 0))
check("erasing a cell round-trips", decode_credits(blanked_file) == blanked)

-- Free one tile, then add new art in the empty area: the free cell becomes its
-- own tile in the rebuilt map.
local roomy = write_cell(blanked, 0, string.rep("\x11", 32))
local roomy_file = encode_screen("CREDITS.bmp", roomy, credits_palette)
local roomy_map = block(roomy_file, "credits_map")
local roomy_pixels = decode_credits(roomy_file)
check("new art in the empty area is kept", read_cell(roomy_pixels, 0) == string.rep("\x11", 32))
check("new art gets its own tile",
  word(roomy_map, 0) ~= word(roomy_map, 1)
  and #block(roomy_file, "credits_tiles") == 311 * 32,
  tostring(#block(roomy_file, "credits_tiles")))
check("the rest of the screen is unchanged after adding art",
  write_cell(roomy_pixels, 0, read_cell(blanked, 0)) == blanked)

-- Two identical new cells collapse onto one tile.
local pair = write_cell(roomy, 1, string.rep("\x11", 32))
local pair_file = encode_screen("CREDITS.bmp", pair, credits_palette)
check("identical cells share one tile",
  word(block(pair_file, "credits_map"), 0) == word(block(pair_file, "credits_map"), 1))
check("identical cells round-trip", decode_credits(pair_file) == pair)

-- The undocumented bit-31 flag on the logo map survives an edit here.
check("logo flag survives a credits edit",
  word(block(roomy_file, "logo_map"), 15 * 40 + 14) == 0x80000004)

-- Repainting one cell of the logo artwork keeps its map (flags included) and
-- leaves the credits blocks alone.
local repainted = edit_pixel(logo_pixels, 96, 104, 3)
local repainted_file = encode_screen("LOGO.bmp", repainted, logo_palette)
check("logo repaint survives",
  bmp.parse(codec.decode(repainted_file, { prefix = "I" })[2].data, WIDTH, HEIGHT, 4)
  == repainted)
check("logo repaint keeps its map", block(repainted_file, "logo_map") == logo_map)
check("logo repaint keeps the flag",
  word(block(repainted_file, "logo_map"), 15 * 40 + 14) == 0x80000004)
check("logo repaint keeps the credits blocks",
  block(repainted_file, "credits_tiles") == credits_tiles
  and block(repainted_file, "credits_map") == credits_map)

-- The logo draws tile 4 in two cells because those cells are identical; keep
-- them identical and they stay one tile.
local both = edit_pixel(edit_pixel(logo_pixels, 136, 103, 3), 112, 127, 3)
local both_file = encode_screen("LOGO.bmp", both, logo_palette)
check("the two shared logo cells stay one tile",
  #block(both_file, "logo_tiles") == 55 * 32
  and (word(block(both_file, "logo_map"), 12 * 40 + 17) & 0x7FFFFFFF)
    == (word(block(both_file, "logo_map"), 15 * 40 + 14) & 0x7FFFFFFF))

-- Geometry is fixed at the 320x224 screen.
local wrong_geometry = bmp.build(string.rep("\0", 320 * 208 // 2), 320, 208, 4, credits_palette)
check_error("screen dimensions are fixed", function()
  codec.encode(logo, {
    { name = "INTRO/CREDITS.bmp", data = wrong_geometry },
  }, { prefix = "INTRO" })
end, "expected 320x224")

-- Incompressible art cannot fit the 6,889-byte credits slot.
local seed = 0x12345678
local function random_byte()
  seed = seed ~ ((seed << 13) & 0xFFFFFFFF)
  seed = seed ~ (seed >> 17)
  seed = seed ~ ((seed << 5) & 0xFFFFFFFF)
  seed = seed & 0xFFFFFFFF
  return string.char(seed & 0xFF)
end

local noisy = credits_pixels
for cell = 0, CELLS - 1 do
  if word(credits_map, cell) ~= 0 then
    local bytes = {}
    for i = 1, 32 do bytes[i] = random_byte() end
    noisy = write_cell(noisy, cell, table.concat(bytes))
  end
end
check_error("credits tile block budget is enforced", function()
  encode_screen("CREDITS.bmp", noisy, credits_palette)
end, "exceeds slot 6889")

check("truncated input is rejected",
  codec.can_handle(logo:sub(1, OFFSETS.credits_tiles.off + 100)) == "no")
check_error("truncated input cannot decode", function()
  codec.decode(logo:sub(1, OFFSETS.credits_tiles.off + 100), { prefix = "X" })
end, "intro_credits")

print(string.format("%d passed, %d failed", pass, fail))
assert(fail == 0)
