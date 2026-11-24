--[[
  Tests for scripts/status_screen_gfx.lua against the retail ICATALL.DAT.

  ICATALL.DAT @ 0x8800 holds a 21,967-byte PRS slot for a 55,296-byte 144x384
  8bpp background.  @ 0x13800 it holds a 2,522-byte slot for 6,144 bytes = 48
  16x16 4bpp font tiles.  The sheet has no artifact of its own any more: it is
  rebuilt from the three label canvases.

  The background palette is the file's own at 0x14800; the label canvases use
  adv_dialogue_jp_for_bmp, the shared adv_dialogue_jp + red display palette.

  The label rows are checked against the retail glyph strings in the SAKURA
  executable, which this test reads itself, so RETAIL is checked against the
  disc rather than trusted.
]]

local codec = dofile(LUDARED.SCRIPTS .. "/status_screen_gfx.lua")
local bmp = dofile(LUDARED.SCRIPTS .. "/shared/bmp.lua")
local palettes = dofile(LUDARED.SCRIPTS .. "/shared/palettes.lua")
local assets = dofile(LUDARED.SCRIPTS .. "/tests/shared/real_assets.lua")
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

local icatall = assets.read("SakTaiCD1_Track1.bin/SAKURA1/ICATALL.DAT")

local BG_OFFSET, BG_SLOT = 0x8800, 21967
local FONT_OFFSET, FONT_SLOT = 0x13800, 2522
local BG_PALETTE, FONT_PALETTE = 0x14800, 0x13000

local background = prs:decode(icatall:sub(BG_OFFSET + 1, BG_OFFSET + BG_SLOT))[1].data
local font = prs:decode(icatall:sub(FONT_OFFSET + 1, FONT_OFFSET + FONT_SLOT))[1].data

------------------------------------------------------------------ helpers --
-- The canvases, restated from the fifteen retail labels.
local GROUPS = {
  { name = "NAMES.bmp",  slots = { 1, 2, 3, 4, 5, 6 } },
  { name = "MOODS.bmp",  slots = { 7, 8, 9, 10, 11, 12 } },
  { name = "STATS.bmp", slots = { 13, 14, 15 } },
}

-- Independent label composition, cutting and packing.
local function compose(sheet, indices)
  local rows = {}
  for row = 0, 15 do
    local parts = {}
    for cell, glyph in ipairs(indices) do
      local at = (glyph - 1) * 128 + row * 8
      parts[cell] = sheet:sub(at + 1, at + 8)
    end
    rows[row + 1] = table.concat(parts)
  end
  return table.concat(rows)
end

local function cut(pixels, width)
  local cells, stride = {}, width // 2
  for cell = 0, width // 16 - 1 do
    local parts = {}
    for row = 0, 15 do
      local at = row * stride + cell * 8
      parts[row + 1] = pixels:sub(at + 1, at + 8)
    end
    cells[#cells + 1] = table.concat(parts)
  end
  return cells
end

local function atlas(lists, tail)
  local order, index, out = {}, {}, {}
  for i, tiles in ipairs(lists) do
    out[i] = {}
    for k, tile in ipairs(tiles) do
      local at = index[tile]
      if not at then
        order[#order + 1] = tile
        at = #order
        index[tile] = at
      end
      out[i][k] = at
    end
  end
  local extra
  if tail then
    extra = {}
    for i, tile in ipairs(tail) do
      order[#order + 1] = tile
      extra[i] = #order
    end
  end
  return table.concat(order), out, extra
end

local function group_pixels(strips)
  local width = 0
  for _, strip in ipairs(strips) do width = math.max(width, strip.width) end
  local rows = {}
  for _, strip in ipairs(strips) do
    for row = 0, 15 do
      local line = strip.pixels:sub(row * (strip.width // 2) + 1,
        (row + 1) * (strip.width // 2))
      rows[#rows + 1] = line .. string.rep("\0", (width - strip.width) // 2)
    end
  end
  return table.concat(rows), width, 16 * #strips
end

-- A strip of flat cells, for synthetic labels.
local function strip(bytes)
  local rows = {}
  for _ = 0, 15 do
    local parts = {}
    for k, value in ipairs(bytes) do parts[k] = string.char(value):rep(8) end
    rows[#rows + 1] = table.concat(parts)
  end
  return table.concat(rows), #bytes * 16
end

local function dims(data)
  local width, height = string.unpack("<i4i4", data, 19)
  return math.abs(width), math.abs(height)
end

-- The tail the atlas appends after the labels: tile 37 (the formatter's
-- padding glyph), tile 38, then the ten digits.
local function sheet_cell(glyph)
  local at = (glyph - 1) * 128
  return font:sub(at + 1, at + 128)
end

local TAIL = { sheet_cell(37), sheet_cell(38) }
for _, glyph in ipairs({ 39, 40, 41, 42, 43, 44, 45, 46, 47, 48 }) do
  TAIL[#TAIL + 1] = sheet_cell(glyph)
end
-- The atlas ends with an empty cell: the stats formatter's line fill points at
-- it, because a rebuilt sheet has text at retail's blank glyph 20.
TAIL[#TAIL + 1] = string.rep("\0", 128)

-- Stats rows are two cells now, and the retail sheet has one-cell strings, so
-- every rebuild needs a stats canvas of its own.
local STAT_CELLS = { { 0x21, 0x22 }, { 0x23, 0x24 }, { 0x25, 0x26 } }
local function stats_art()
  local rows = {}
  for i = 1, 3 do
    local pixels, width = strip(STAT_CELLS[i])
    rows[i] = { pixels = pixels, width = width }
  end
  local value, width, height = group_pixels(rows)
  return { name = "STATUS_STATS.bmp",
    data = bmp.build(value, width, height, 4, p_label) }
end

------------------------------------------------------------------ the data --
-- The retail glyph strings, read from the executable independently.
local sakura_file = assert(io.open(LUDARED.PROJECT_ROOT .. "/SAKURA", "rb"),
  "the retail SAKURA executable is required")
local sakura = sakura_file:read("*a")
sakura_file:close()

local retail_lists = (function()
  local out, pos = {}, 0x5F428
  while pos < 0x5F4B4 do
    if string.unpack(">I2", sakura, pos + 1) == 0 then break end
    local indices = {}
    while true do
      local value = string.unpack(">I2", sakura, pos + 1)
      pos = pos + 2
      if value == 0 then break end
      indices[#indices + 1] = value
    end
    out[#out + 1] = indices
  end
  return out
end)()

local retail_strips = {}
for i = 1, 15 do
  retail_strips[i] = {
    pixels = compose(font, retail_lists[i]),
    width = #retail_lists[i] * 16,
  }
end

print("test_status_screen_gfx.lua")

check("ICATALL size", #icatall == 114688, tostring(#icatall))
check("background decompresses to 55,296", #background == 55296, tostring(#background))
check("font decompresses to 6,144", #font == 6144, tostring(#font))
check("the retail strings number 18", #retail_lists == 18, tostring(#retail_lists))
check("can_handle real ICATALL", codec.can_handle(icatall) == "certain",
  codec.can_handle(icatall))
check("can_handle rejects non-strings", codec.can_handle(nil) == "no")
check("can_handle rejects random data",
  codec.can_handle(string.rep("\xA5", 114688)) == "no")

-- Detection is the shared SHA-256 pin, so a rebuilt file is "no" but still
-- decodes.  Editing one byte of the gap between the two slots proves both, and
-- that encode carries every byte it does not own through untouched.
do
  local GAP = BG_OFFSET + BG_SLOT
  local edited = icatall:sub(1, GAP)
    .. string.char((icatall:byte(GAP + 1) + 1) % 256)
    .. icatall:sub(GAP + 2)
  check("a rebuilt ICATALL is rejected by can_handle",
    codec.can_handle(edited) == "no", codec.can_handle(edited))
  local rebuilt_arts = codec.decode(edited, { prefix = "STATUS" })
  check("a rebuilt ICATALL still decodes", #rebuilt_arts == 5, tostring(#rebuilt_arts))
  check("a rebuilt ICATALL round-trips",
    codec.encode(edited, rebuilt_arts, { prefix = "STATUS" }) == edited)
end
check("decode_name default", codec.decode_name(nil) == "STATUS")

local arts = codec.decode(icatall, { prefix = "STATUS" })
check("five artifacts", #arts == 5, tostring(#arts))
check("artifact names",
  arts[1].name == "STATUS_BG.bmp"
  and arts[2].name == "STATUS_NAMES.bmp"
  and arts[3].name == "STATUS_MOODS.bmp"
  and arts[4].name == "STATUS_STATS.bmp"
  and arts[5].name == "STATUS_DIGITS.bmp")

--------------------------------------------------------------- the palettes --
local p_bg = bmp.from_bgr555(icatall:sub(BG_PALETTE + 1, BG_PALETTE + 512), 256)
-- The shared label palette: adv_dialogue_jp with its last entry repainted red.
local p_label = bmp.from_bgr555(palettes.raw("adv_dialogue_jp_for_bmp"), 16)
local p_adv = bmp.from_bgr555(palettes.raw("adv_dialogue_jp"), 16)

local bg_pixels, bg_palette = bmp.parse(arts[1].data, 144, 384, 8)
check("background is 144x384 8bpp", #bg_pixels == 55296)
check("background pixels match the stream", bg_pixels == background)
check("background uses the palette at 0x14800", bg_palette == p_bg)
check("the background palette is not a neutral ramp", bg_palette ~= bmp.ramp(8))
check("the background palette is not blank", bg_palette:sub(1, 3) ~= "\0\0\0")

----------------------------------------------------------------- the labels --
do
  local ok = true
  local ok_width, ok_palette = true, true
  for _, group in ipairs(GROUPS) do
    local artifact
    for _, candidate in ipairs(arts) do
      if candidate.name == "STATUS_" .. group.name then artifact = candidate end
    end
    local width, height = dims(artifact.data)
    local pixels, palette = bmp.parse(artifact.data, width, height, 4)
    local strips = {}
    for k, slot in ipairs(group.slots) do strips[k] = retail_strips[slot] end
    local expected, expected_width, expected_height = group_pixels(strips)
    if pixels ~= expected or width ~= expected_width or height ~= expected_height then
      ok = false
      print("       " .. group.name .. ": " .. width .. "x" .. height
        .. " vs " .. expected_width .. "x" .. expected_height)
    end
    if height ~= 16 * #group.slots then ok_width = false end
    if palette ~= p_label then ok_palette = false end
  end
  check("every group canvas shows its retail sentences", ok)
  check("every group has one 16-pixel row per label", ok_width)
  check("every group uses the ADV text palette", ok_palette)
end
check("the text palette is not the in-file font ramp",
  p_label ~= bmp.from_bgr555(icatall:sub(FONT_PALETTE + 1, FONT_PALETTE + 32), 16))
check("the text palette's last colour is bright red",
  p_label:sub(61, 64) == "\0\0\xFF\0",
  (p_label:sub(61, 64):gsub(".", function(c) return string.format("%02X ", c:byte()) end)))
check("only the last colour differs from the ADV palette",
  p_label:sub(1, 60) == p_adv:sub(1, 60) and p_label ~= p_adv)
check("adv_dialogue_jp_for_bmp is adv_dialogue_jp plus red",
  p_label == p_adv:sub(1, 60) .. string.char(0, 0, 255, 0))

check("unmodified encode is byte-identical",
  codec.encode(icatall, arts, { prefix = "STATUS" }) == icatall)

-- Background edit: only the 21,967-byte background slot may change.
local new_bg = string.char(1) .. bg_pixels:sub(2)
local modified_bg = codec.encode(icatall, {
  { name = "STATUS_BG.bmp",
    data = bmp.build(new_bg, 144, 384, 8, bg_palette) },
}, { prefix = "STATUS" })

check("background edit keeps size", #modified_bg == #icatall)
check("only the background slot changed",
  modified_bg:sub(1, BG_OFFSET) == icatall:sub(1, BG_OFFSET)
  and modified_bg:sub(BG_OFFSET + BG_SLOT + 1) == icatall:sub(BG_OFFSET + BG_SLOT + 1))
check("gap between the slots preserved",
  modified_bg:sub(BG_OFFSET + BG_SLOT + 1, FONT_OFFSET)
  == icatall:sub(BG_OFFSET + BG_SLOT + 1, FONT_OFFSET))

local bg_arts = codec.decode(modified_bg, { prefix = "STATUS" })
local edited_bg = bmp.parse(bg_arts[1].data, 144, 384, 8)
check("background edit survives", edited_bg:byte(1) == 1)
check("other background pixels unchanged", edited_bg:sub(2) == bg_pixels:sub(2))
check("a background edit leaves the groups alone", (function()
  for i = 2, 5 do
    if bg_arts[i].data ~= arts[i].data then return false end
  end
  return true
end)())

--------------------------------------------------------------- label edits --
-- Two-cell stats row: the rebuilt sheet is the atlas of the fifteen rows plus
-- the padding, separator and digit tail.
do
  local strips, widths = {}, {}
  for i = 1, 15 do
    strips[i], widths[i] = retail_strips[i].pixels, retail_strips[i].width
  end
  local pixels, width = strip(STAT_CELLS[1])
  for k = 1, 3 do strips[12 + k], widths[12 + k] = strip(STAT_CELLS[k]) end

  local lists = {}
  for i = 1, 15 do lists[i] = cut(strips[i], widths[i]) end
  local sheet, indices, tail_index = atlas(lists, TAIL)

  local stat_rows = {}
  for k = 1, 3 do stat_rows[k] = { pixels = strips[12 + k], width = widths[12 + k] } end
  local stat_pixels, stat_width, stat_height = group_pixels(stat_rows)

  local out = codec.encode(icatall, {
    { name = "STATUS_STATS.bmp",
      data = bmp.build(stat_pixels, stat_width, stat_height, 4, p_label) },
  }, { prefix = "STATUS" })

  check("a label edit keeps the file size", #out == #icatall, tostring(#out))
  check("a label edit touches only the font slot",
    out:sub(1, FONT_OFFSET) == icatall:sub(1, FONT_OFFSET)
    and out:sub(FONT_OFFSET + FONT_SLOT + 1) == icatall:sub(FONT_OFFSET + FONT_SLOT + 1))

  local rebuilt = prs:decode(out:sub(FONT_OFFSET + 1, FONT_OFFSET + FONT_SLOT))[1].data
  check("a label edit rebuilds the sheet as the atlas", rebuilt == sheet,
    string.format("%d vs %d bytes", #rebuilt, #sheet))
  check("the stats cells are the sheet's first new tiles",
    rebuilt:sub((indices[13][1] - 1) * 128 + 1, indices[13][1] * 128) == cut(pixels, width)[1]
    and rebuilt:sub((indices[13][2] - 1) * 128 + 1, indices[13][2] * 128) == cut(pixels, width)[2])
  check("the digit tail follows the labels",
    rebuilt:sub(#rebuilt - 128 * #TAIL + 1) == table.concat(TAIL)
    and tail_index[3] == #rebuilt // 128 - #TAIL + 3)
end

-- A wider row is a longer sentence: two cells, first in the atlas because label
-- 1 is first.
do
  local pixels, width = strip({ 0x11, 0x22 })
  local names = {}
  for k = 1, 6 do names[k] = retail_strips[k] end
  names[1] = { pixels = pixels, width = width }
  local group_pixels_value, group_width, group_height = group_pixels(names)

  local out = codec.encode(icatall, {
    { name = "STATUS_NAMES.bmp",
      data = bmp.build(group_pixels_value, group_width, group_height, 4, p_label) },
    stats_art(),
  }, { prefix = "STATUS" })

  local rebuilt = prs:decode(out:sub(FONT_OFFSET + 1, FONT_OFFSET + FONT_SLOT))[1].data
  local cells = cut(pixels, width)
  check("a two-cell label keeps the file size", #out == #icatall)
  check("a two-cell label leads the sheet",
    rebuilt:sub(1, 128) == cells[1] and rebuilt:sub(129, 256) == cells[2])
end

-- Trailing blank cells are padding, so a row's width is its last inked cell.
do
  local pixels, width = strip({ 0x11, 0x22 })
  local padded = {}
  for row = 0, 15 do
    local start = row * (width // 2)
    padded[#padded + 1] = pixels:sub(start + 1, start + 16) .. string.rep("\0", 16)
  end
  local names = {}
  for k = 1, 6 do names[k] = retail_strips[k] end
  names[1] = { pixels = table.concat(padded), width = 64 }
  local group_value, group_width, group_height = group_pixels(names)

  local out = codec.encode(icatall, {
    { name = "STATUS_NAMES.bmp",
      data = bmp.build(group_value, group_width, group_height, 4, p_label) },
    stats_art(),
  }, { prefix = "STATUS" })

  local rebuilt = prs:decode(out:sub(FONT_OFFSET + 1, FONT_OFFSET + FONT_SLOT))[1].data
  check("a padded row keeps the file size", #out == #icatall)
  check("the padded row's two cells lead the sheet",
    rebuilt:sub(1, 128) == cut(pixels, width)[1]
    and rebuilt:sub(129, 256) == cut(pixels, width)[2])
end

-- The formatter reads both stats glyphs with one longword, so a one-cell stats
-- row would leave its number unseen and a three-cell row would be cropped.
do
  check_error("a one-cell stats row is refused", function()
    local narrow = { pixels = strip({ 0x11 }), width = 16 }
    local rows = { narrow, narrow, narrow }
    local value, group_width, group_height = group_pixels(rows)
    codec.encode(icatall, {
      { name = "STATUS_STATS.bmp",
        data = bmp.build(value, group_width, group_height, 4, p_label) },
    }, { prefix = "STATUS" })
  end, "exactly two cells")

  local pixels, width = strip({ 0x11, 0x22, 0x33 })
  local stats = { retail_strips[13], { pixels = pixels, width = width }, retail_strips[15] }
  local group_value, group_width, group_height = group_pixels(stats)
  check_error("a three-cell stats row is refused", function()
    codec.encode(icatall, {
      { name = "STATUS_STATS.bmp",
        data = bmp.build(group_value, group_width, group_height, 4, p_label) },
    }, { prefix = "STATUS" })
  end, "exactly two cells")
end

-- A canvas is 4 bpp.  A deeper BMP has had its palette renumbered with its
-- pixels, so it is refused rather than guessed at.
do
  local names = {}
  for k = 1, 6 do names[k] = retail_strips[k] end
  local group_value, group_width, group_height = group_pixels(names)

  local widened = {}
  for row = 0, group_height - 1 do
    for i = row * (group_width // 2) + 1, (row + 1) * (group_width // 2) do
      local byte = group_value:byte(i)
      widened[#widened + 1] = string.char(byte >> 4, byte & 15)
    end
  end
  local eight = bmp.build(table.concat(widened), group_width, group_height, 8,
    string.rep("\0", 1024))

  check_error("an 8 bpp canvas is refused with its depth", function()
    codec.encode(icatall, {
      { name = "STATUS_NAMES.bmp", data = eight },
    }, { prefix = "STATUS" })
  end, "is 8 bpp, not 4")
end

-- Group geometry: 16 pixels per label, whole 16-pixel cells, no blank row.
do
  check_error("a canvas with the wrong row count is refused", function()
    codec.encode(icatall, {
      { name = "STATUS_STATS.bmp",
        data = bmp.build(string.rep("\0", 16 * 64 // 2), 16, 64, 4, p_label) },
    }, { prefix = "STATUS" })
  end, "holds 3 labels")

  check_error("a canvas that is not whole cells is refused", function()
    codec.encode(icatall, {
      { name = "STATUS_STATS.bmp",
        data = bmp.build(string.rep("\0", 24 * 48 // 2), 24, 48, 4, p_label) },
    }, { prefix = "STATUS" })
  end, "whole 16%-pixel cells")

  check_error("a blank row is refused", function()
    codec.encode(icatall, {
      { name = "STATUS_STATS.bmp",
        data = bmp.build(string.rep("\0", 16 * 48 // 2), 16, 48, 4, p_label) },
    }, { prefix = "STATUS" })
  end, "row 1 is blank")
end

-- A group wider than the screen.
do
  local names = {}
  for k = 1, 6 do names[k] = retail_strips[k] end
  local wide, wide_width = strip({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12,
                                   13, 14, 15, 16, 17, 18, 19 })
  names[1] = { pixels = wide, width = wide_width }
  local value, width, height = group_pixels(names)
  check_error("a group wider than the screen is refused", function()
    codec.encode(icatall, {
      { name = "STATUS_NAMES.bmp",
        data = bmp.build(value, width, height, 4, p_label) },
    }, { prefix = "STATUS" })
  end, "over the 18%-cell screen")
end

-- The sheet may grow past retail's 48 tiles to 96, and no further: six rows of
-- sixteen new cells need more than that once the other labels and the tail are
-- counted.
do
  local names = {}
  for k = 1, 6 do names[k] = retail_strips[k] end
  for _, slot in ipairs({ 1, 2, 3, 4, 5, 6 }) do
    local wide = {}
    for cell = 1, 16 do wide[cell] = (slot - 1) * 16 + cell end
    local pixels, width = strip(wide)
    names[slot] = { pixels = pixels, width = width }
  end
  local value, width, height = group_pixels(names)
  check_error("more than 96 cells is refused", function()
    codec.encode(icatall, {
      { name = "STATUS_NAMES.bmp",
        data = bmp.build(value, width, height, 4, p_label) },
      stats_art(),
    }, { prefix = "STATUS" })
  end, "over the 96%-tile sheet")
end

--------------------------------------------------------------- dimensions --
local wrong_bg = bmp.build(string.rep("\0", 144 * 383), 144, 383, 8, bg_palette)
check_error("background dimension change is rejected", function()
  codec.encode(icatall, {
    { name = "STATUS_BG.bmp", data = wrong_bg },
  }, { prefix = "STATUS" })
end, "expected 144x384")

-- Both blocks are compression budgets.
local seed = 0x12345678
local function random_bytes(count)
  local out = {}
  for i = 1, count do
    seed = seed ~ ((seed << 13) & 0xFFFFFFFF)
    seed = seed ~ (seed >> 17)
    seed = seed ~ ((seed << 5) & 0xFFFFFFFF)
    seed = seed & 0xFFFFFFFF
    out[i] = string.char(seed & 0xFF)
  end
  return table.concat(out)
end

local random_bg = bmp.build(random_bytes(144 * 384), 144, 384, 8, bg_palette)
check_error("background slot budget is enforced", function()
  codec.encode(icatall, {
    { name = "STATUS_BG.bmp", data = random_bg },
  }, { prefix = "STATUS" })
end, "exceeds slot 21967")

-- Incompressible cells stay inside the 96-tile sheet and blow its slot.
do
  local function random_row(cells)
    local parts, rows = {}, {}
    for cell = 1, cells do parts[cell] = random_bytes(128) end
    for row = 0, 15 do
      local pieces = {}
      for cell = 1, cells do
        pieces[cell] = parts[cell]:sub(row * 8 + 1, (row + 1) * 8)
      end
      rows[#rows + 1] = table.concat(pieces)
    end
    return { pixels = table.concat(rows), width = cells * 16 }
  end

  local artifacts = {}
  for _, spec in ipairs({ { "NAMES", 6, 3 }, { "MOOD", 6, 3 }, { "STATS", 3, 2 } }) do
    local rows = {}
    for k = 1, spec[2] do rows[k] = random_row(spec[3]) end
    local value, width, height = group_pixels(rows)
    artifacts[#artifacts + 1] = {
      name = "STATUS_" .. spec[1] .. ".bmp",
      data = bmp.build(value, width, height, 4, p_label),
    }
  end

  check_error("sheet slot budget is enforced", function()
    codec.encode(icatall, artifacts, { prefix = "STATUS" })
  end, "over the 2522%-byte slot")
end

-- The background palette can still be overridden for inspection.
local custom_bg_palette = string.rep(string.pack(">I2", 0x001F), 256)
local custom_arts = codec.decode(icatall, {
  prefix = "CUSTOM", bg_palette = custom_bg_palette,
})
local _, custom_palette = bmp.parse(custom_arts[1].data, 144, 384, 8)
check("optional background palette is honoured",
  custom_palette == bmp.from_bgr555(custom_bg_palette, 256))

check("truncated input is rejected", codec.can_handle(icatall:sub(1, 0x8800 + 100)) == "no")
check("a non-PRS background slot is reported", (function()
  local broken = icatall:sub(1, BG_OFFSET)
    .. string.rep("\xFF", BG_SLOT) .. icatall:sub(BG_OFFSET + BG_SLOT + 1)
  local ok, err = pcall(codec.decode, broken, { prefix = "X" })
  return not ok and tostring(err):find("background at 0x008800 is not a PRS stream") ~= nil
end)())
check_error("truncated input cannot decode", function()
  codec.decode(icatall:sub(1, 0x8800 + 100), { prefix = "X" })
end, "status_screen")

print(string.format("%d passed, %d failed", pass, fail))
assert(fail == 0)
