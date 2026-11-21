--[[
  Tests for scripts/intermission_screen_gfx.lua against the retail ICATALL.DAT.

  ICATALL.DAT @ 0x2800 holds a 966-byte PRS slot for fifteen 16x16 4bpp cells
  (1,920 bytes).  The screen places them through SAKURA's index tables, so the
  decoded artifact is the screen layout: 96x48, three lines of six slots.
  PatchMainMenu writes the same block from "IntermediateScreen.bmp" and refuses
  a stream over 966 bytes; this suite pins the geometry, the slot -> cell
  mapping, the budget and the round trip.
]]

local codec = dofile(LUDARED.SCRIPTS .. "/intermission_screen_gfx.lua")
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

local BLOCK_OFFSET, BLOCK_SLOT = 0x2800, 966
local STRIP_W, STRIP_H = 96, 48
local STRIP_ROW = STRIP_W // 2                 -- 48 bytes per strip row
local IMAGE_BYTES = 15 * 128

local raw = prs:decode(icatall:sub(BLOCK_OFFSET + 1, BLOCK_OFFSET + BLOCK_SLOT))[1].data

-- The codec's palette: the game's phrase ramp (adv_dialogue_jp, as shipped in
-- the library's IntermediateScreen.bmp) with entry 15 forced red.
local ramp = palettes.raw("adv_dialogue_jp")
local expected_palette = bmp.from_bgr555(
  ramp:sub(1, #ramp - 2) .. string.char(0x00, 0x1F), 16)
local ink = expected_palette:sub(61, 64)

-- The retail slot tables, written out by hand from SAKURA 0x5F5C8 (1-based
-- glyph indices, 0 = the blank below the atlas).
local TABLES = {
  { 2, 1, 3, 4, 5, 0 },        -- セーブする
  { 6, 7, 8, 9, 10, 0 },       -- 隊員の状況
  { 11, 1, 12, 13, 14, 15 },   -- ゲームを再開
}

-- Independent expansion: slot table -> 96x48 strip.
local function expected_strip(cells)
  local rows = {}
  for y = 0, STRIP_H - 1 do
    local band = y // 16
    local inner = y % 16
    local row = {}
    for slot = 1, 6 do
      local index = TABLES[band + 1][slot]
      if index == 0 then
        row[#row + 1] = string.rep("\0", 8)
      else
        local start = (index - 1) * 128 + inner * 8
        row[#row + 1] = cells:sub(start + 1, start + 8)
      end
    end
    rows[#rows + 1] = table.concat(row)
  end
  return table.concat(rows)
end

local function strip_tile(strip, band, slot)
  local rows = {}
  for inner = 0, 15 do
    local start = (band * 16 + inner) * STRIP_ROW + (slot - 1) * 8
    rows[#rows + 1] = strip:sub(start + 1, start + 8)
  end
  return table.concat(rows)
end

print("test_intermission_screen_gfx.lua")

check("ICATALL size", #icatall == 114688, tostring(#icatall))
check("intermission block decompresses to 1,920 bytes", #raw == IMAGE_BYTES, tostring(#raw))
check("can_handle retail ICATALL", codec.can_handle(icatall) == "certain")
check("can_handle rejects other data", codec.can_handle("not a file") == "no")
check("decode_name", codec.decode_name(nil) == "INTERMISSION")

local arts = codec.decode(icatall)
check("one artifact", #arts == 1, tostring(#arts))
check("artifact name", arts[1].name == "INTERMISSION_LABELS.bmp", arts[1].name)

local pixels, palette = bmp.parse(arts[1].data, STRIP_W, STRIP_H, 4)
check("strip is 96x48 4bpp", #pixels == STRIP_W * STRIP_H // 2, tostring(#pixels))
check("strip matches the slot tables", pixels == expected_strip(raw))
check("strip uses the game phrase palette", palette == expected_palette)
check("palette ramp runs white to light grey",
  palette:sub(1, 4) == string.char(255, 255, 255, 0)
  and palette:sub(57, 60) == string.char(230, 230, 230, 0),
  string.format("%02X %02X %02X / %02X %02X %02X", palette:byte(1), palette:byte(2),
    palette:byte(3), palette:byte(57), palette:byte(58), palette:byte(59)))
check("palette index 15 is pure red", ink == string.char(0, 0, 255, 0),
  string.format("BGRA %02X %02X %02X %02X", ink:byte(1), ink:byte(2), ink:byte(3), ink:byte(4)))

local used = {}
for i = 1, #raw do
  local b = raw:byte(i)
  used[b >> 4] = true
  used[b & 0x0F] = true
end
local indices = {}
for index = 0, 15 do if used[index] then indices[#indices + 1] = index end end
print("        (colour indices used by the labels: " .. table.concat(indices, ", ") .. ")")

-- Row 1 on screen is セ ー ブ す る: cell 1, then the shared cell 0.
check("row 1 slot 1 is cell 1", strip_tile(pixels, 0, 1) == raw:sub(129, 256))
check("row 1 slot 2 is the shared ー (cell 0)", strip_tile(pixels, 0, 2) == raw:sub(1, 128))
check("row 1 ends in the zero terminator", strip_tile(pixels, 0, 6) == string.rep("\0", 128))
check("row 3 slot 5 is 再 (cell 13)", strip_tile(pixels, 2, 5) == raw:sub(13 * 128 + 1, 14 * 128))
check("row 3 reuses cell 0 for ー",
  strip_tile(pixels, 2, 2) == strip_tile(pixels, 0, 2))

check("unmodified encode is byte-identical", codec.encode(icatall, arts) == icatall)

-- Headroom for a translation.  The shipping stream is exactly 966 bytes.
local reshipped = prs:encode("", { { name = "DECOMPRESSED", data = raw } })
check("the shipping cells recompress within the slot", #reshipped <= BLOCK_SLOT,
  string.format("%d of %d bytes", #reshipped, BLOCK_SLOT))
print(string.format("        (unchanged rebuild: %d of %d bytes, %d spare)",
  #reshipped, BLOCK_SLOT, BLOCK_SLOT - #reshipped))

-- Three complete row textures share the existing 2,048-byte transfer.
local function painting(widths, random)
  local rows, expected = {}, {}
  local state = 0x1234567
  for band = 1, 3 do
    expected[band] = {}
    for y = 0, 15 do
      local line = {}
      for x = 1, widths[band] // 2 do
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF
        line[x] = string.char(random and ((state >> 16) & 0xFF) or (band * 17 + y))
      end
      local texture_row = table.concat(line)
      expected[band][y + 1] = texture_row
      rows[#rows + 1] = texture_row .. string.rep("\0", 48 - #texture_row)
    end
    expected[band] = table.concat(expected[band])
  end
  return bmp.build(table.concat(rows), 96, 48, 4, palette), table.concat(expected)
end

local sheet, expected = painting({96, 48, 72})
local modified = codec.encode(icatall, { { name = arts[1].name, data = sheet } })
local rebuilt = prs:decode(modified:sub(BLOCK_OFFSET + 1, BLOCK_OFFSET + BLOCK_SLOT))[1].data
check("96 + 48 + 72 uses 1,728 bytes plus transparent padding",
  rebuilt == expected .. string.rep("\0", 320))
check("edit keeps file size", #modified == #icatall)
check("only the original 966-byte slot changes",
  modified:sub(1, BLOCK_OFFSET) == icatall:sub(1, BLOCK_OFFSET)
  and modified:sub(BLOCK_OFFSET + BLOCK_SLOT + 1) == icatall:sub(BLOCK_OFFSET + BLOCK_SLOT + 1))
check("modified ICATALL is rejected by detection", codec.can_handle(modified) == "no")
check("missing artifact preserves parent", codec.encode(icatall, {}) == icatall)

local full_sheet, full_expected = painting({96, 96, 64})
local full = codec.encode(icatall, { { name = arts[1].name, data = full_sheet } })
check("the full 2,048-byte transfer is usable",
  prs:decode(full:sub(BLOCK_OFFSET + 1, BLOCK_OFFSET + BLOCK_SLOT))[1].data == full_expected)

check_error("decoded budget overflow is rejected", function()
  codec.encode(icatall, { { name = arts[1].name, data = painting({96, 96, 72}) } })
end, "2112 decoded bytes, only 2048 fit")
check_error("compressed budget overflow is rejected", function()
  codec.encode(icatall, { { name = arts[1].name, data = painting({96, 48, 72}, true) } })
end, "only 966 fit.-over budget")
check_error("wrong BMP dimensions are rejected", function()
  codec.encode(icatall, {
    { name = arts[1].name, data = bmp.build(string.rep("\0", 112 * 48 // 2), 112, 48, 4, palette) },
  })
end, "expected 96x48")

print(string.format("%d passed, %d failed", pass, fail))
assert(fail == 0, "intermission_screen_gfx tests failed")
