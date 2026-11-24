--[[
  Tests the hardcoded image layouts against the retail TMAPSP and FUKAGAWA
  archives, including pixel round trips and preservation of TMAPSP's gaps.
]]

local codec = dofile(LUDARED.SCRIPTS .. "/theater_map_gfx.lua")
local empty_room = dofile(LUDARED.SCRIPTS .. "/map/empty_room.lua")
local bmp = dofile(LUDARED.SCRIPTS .. "/shared/bmp.lua")
local constants = dofile(LUDARED.SCRIPTS .. "/shared/constants.lua")
local assets = dofile(LUDARED.SCRIPTS .. "/tests/shared/real_assets.lua")

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

local tmap = assets.read("SakTaiCD1_Track1.bin/SAKURA1/TMAPSP.BIN")
local fukagawa = assets.read("SakTaiCD1_Track1.bin/SAKURA1/FUKAGAWA.BIN")

local function layout_entries(layout)
  local out = {}
  for i, record in ipairs(layout) do
    local width_tiles, height = record[2], record[3]
    out[#out + 1] = {
      index = i - 1,
      start = record[1] * 8,
      size = width_tiles * height * 4,
      width = width_tiles * 8,
      height = height,
    }
  end
  return out
end

local tmap_lut = layout_entries(codec.image_layouts.TMAPSP)
local fukagawa_lut = layout_entries(codec.image_layouts.FUKAGAWA)

local function compare_all(artifacts, lut, data)
  local by_name = {}
  for _, artifact in ipairs(artifacts) do by_name[artifact.name] = artifact end
  local bad = 0
  for _, entry in ipairs(lut) do
    local artifact = by_name[string.format("%02d.bmp", entry.index)]
    if not artifact then
      bad = bad + 1
    else
      local ok, pixels = pcall(bmp.parse, artifact.data, entry.width, entry.height, 4)
      if not ok or pixels ~= data:sub(entry.start + 1, entry.start + entry.size) then
        bad = bad + 1
      end
    end
  end
  return bad
end

print("test_theater_map.lua")

check("TMAPSP size", #tmap == 53088, tostring(#tmap))
check("FUKAGAWA size", #fukagawa == 27968, tostring(#fukagawa))
check("can_handle TMAPSP", codec.can_handle(tmap) == "certain")
check("can_handle FUKAGAWA", codec.can_handle(fukagawa) == "certain")
check("decode_name is archive-neutral", codec.decode_name() == "THEATER_MAP")

check("TMAPSP layout has 93 entries", #tmap_lut == 93)
check("TMAPSP entry 0 is 24x16", tmap_lut[1].width == 24 and tmap_lut[1].height == 16)
check("TMAPSP entry 92 is 56x24", tmap_lut[93].width == 56 and tmap_lut[93].height == 24)
check("TMAPSP last image ends at EOF",
  tmap_lut[93].start + tmap_lut[93].size == #tmap)
check("FUKAGAWA layout has 67 entries", #fukagawa_lut == 67)
check("FUKAGAWA last image ends at EOF",
  fukagawa_lut[67].start + fukagawa_lut[67].size == #fukagawa)

local tmap_arts = codec.decode(tmap)
check("TMAPSP decodes 93 artifacts", #tmap_arts == 93, tostring(#tmap_arts))
check("TMAPSP every image matches raw pixels",
  compare_all(tmap_arts, tmap_lut, tmap) == 0)

local first_pixels, first_palette = bmp.parse(tmap_arts[1].data, 24, 16, 4)
check("TMAPSP entry 0 pixels", first_pixels == tmap:sub(1, 192))
check("game display palette", first_palette == constants.map_palette
  and codec.DISPLAY_PALETTE == constants.map_palette
  and empty_room.DISPLAY_PALETTE == constants.map_palette)

local fukagawa_arts = codec.decode(fukagawa)
check("FUKAGAWA decodes 67 artifacts", #fukagawa_arts == 67, tostring(#fukagawa_arts))
check("FUKAGAWA every image matches raw pixels",
  compare_all(fukagawa_arts, fukagawa_lut, fukagawa) == 0)
check("TMAPSP unmodified encode", codec.encode(tmap, tmap_arts) == tmap)
check("FUKAGAWA unmodified encode",
  codec.encode(fukagawa, fukagawa_arts) == fukagawa)

-- Edit TMAPSP entry 0.  Its data is the first 192 bytes.
local new_pixels = string.char(1) .. first_pixels:sub(2)
local modified = codec.encode(tmap, {
  { name = "00.bmp",
    data = bmp.build(new_pixels, 24, 16, 4, first_palette) },
})

check("TMAPSP edit keeps size", #modified == #tmap)
check("TMAPSP edit preserves all later data", modified:sub(193) == tmap:sub(193))
check("TMAPSP edit survives", modified:byte(1) == 1)
check("TMAPSP other pixels unchanged", modified:sub(2, 192) == first_pixels:sub(2))
local entry1 = tmap_lut[2]
check("TMAPSP entry 1 unchanged",
  modified:sub(entry1.start + 1, entry1.start + entry1.size)
    == tmap:sub(entry1.start + 1, entry1.start + entry1.size))

-- TMAPSP has padding gaps.  Edit the image before the first gap (entry 47) and
-- verify the gap bytes are not touched.
local gap_before = tmap_lut[48]
local gap_after = tmap_lut[49]
local gap_start = gap_before.start + gap_before.size
local gap_size = gap_after.start - gap_start
local gap_pixels = bmp.parse(tmap_arts[48].data, gap_before.width, gap_before.height, 4)
local gap_modified = codec.encode(tmap, {
  { name = "47.bmp",
    data = bmp.build(string.char(1) .. gap_pixels:sub(2),
      gap_before.width, gap_before.height, 4, codec.DISPLAY_PALETTE) },
})
check("TMAPSP has a real gap before entry 48", gap_size == 864, tostring(gap_size))
check("TMAPSP gap bytes preserved",
  gap_modified:sub(gap_start + 1, gap_after.start) == tmap:sub(gap_start + 1, gap_after.start))

-- FUKAGAWA encode also operates through its own 67-entry LUT.
local fukagawa_pixels, fukagawa_palette = bmp.parse(fukagawa_arts[1].data, 24, 16, 4)
local fukagawa_modified = codec.encode(fukagawa, {
  { name = "00.bmp",
    data = bmp.build(string.char(2) .. fukagawa_pixels:sub(2),
      24, 16, 4, fukagawa_palette) },
})
check("FUKAGAWA edit keeps size", #fukagawa_modified == #fukagawa)
check("FUKAGAWA edit survives", fukagawa_modified:byte(1) == 2)

-- Resizing rebuilds the archive compactly; unchanged images are sourced from
-- the original buffer and follow the resized image at its new offset.
local resized_pixels = string.rep("\x34", 40 * 24 // 2)
local resized_tmap = codec.encode(tmap, {
  { name = "00.bmp", data = bmp.build(resized_pixels, 40, 24, 4, first_palette) },
})
local compact_tmap_size = 0
for _, entry in ipairs(tmap_lut) do compact_tmap_size = compact_tmap_size + entry.size end
check("TMAPSP resize repacks within budget",
  #resized_tmap == compact_tmap_size - tmap_lut[1].size + #resized_pixels)
check("TMAPSP resized pixels survive", resized_tmap:sub(1, #resized_pixels) == resized_pixels)
check("TMAPSP next image follows the resize",
  resized_tmap:sub(#resized_pixels + 1, #resized_pixels + entry1.size)
    == tmap:sub(entry1.start + 1, entry1.start + entry1.size))

local resize_entry60 = tmap_lut[61]
local resized_60_pixels = string.rep("\x78", 48 * 24 // 2)
local resized_after_prefix = codec.encode(tmap, {
  { name = "60.bmp",
    data = bmp.build(resized_60_pixels, 48, 24, 4, codec.DISPLAY_PALETTE) },
})
check("TMAPSP resize preserves the earlier archive prefix",
  resized_after_prefix:sub(1, resize_entry60.start)
    == tmap:sub(1, resize_entry60.start))
check("TMAPSP resized image stays at its original start",
  resized_after_prefix:sub(resize_entry60.start + 1,
    resize_entry60.start + #resized_60_pixels) == resized_60_pixels)

local fukagawa_resize_entry = fukagawa_lut[51]
local resized_fukagawa_pixels = string.rep("\x56", 40 * 24 // 2)
local resized_fukagawa = codec.encode(fukagawa, {
  { name = "50.bmp",
    data = bmp.build(resized_fukagawa_pixels, 40, 24, 4, codec.DISPLAY_PALETTE) },
})
check("FUKAGAWA resize repacks within budget",
  #resized_fukagawa == #fukagawa - fukagawa_resize_entry.size + #resized_fukagawa_pixels)
local fukagawa_last = fukagawa_lut[67]
local fukagawa_last_offset = fukagawa_last.start - fukagawa_resize_entry.size
  + #resized_fukagawa_pixels
check("FUKAGAWA later image follows the resize",
  resized_fukagawa:sub(fukagawa_last_offset + 1,
      fukagawa_last_offset + fukagawa_last.size)
    == fukagawa:sub(fukagawa_last.start + 1,
      fukagawa_last.start + fukagawa_last.size))

local invalid_width = bmp.build(string.rep("\0", 40 * 24 // 2), 40, 24, 4, first_palette)
invalid_width = invalid_width:sub(1, 18) .. string.pack("<i4", 39) .. invalid_width:sub(23)
check_error("non-tile-aligned width is rejected", function()
  codec.encode(tmap, { { name = "00.bmp", data = invalid_width } })
end, "unsupported dimensions")

check("truncated input is rejected", codec.can_handle(tmap:sub(1, 0x1000)) == "no")
check_error("truncated input cannot decode", function()
  codec.decode(tmap:sub(1, 0x1000))
end, "theater_map")

check_error("unsupported archive size cannot encode", function()
  codec.encode(tmap:sub(1, 0x1000), {})
end, "unsupported archive size")

print(string.format("%d passed, %d failed", pass, fail))
assert(fail == 0)
