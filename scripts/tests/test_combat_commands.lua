--[[
  Tests for scripts/combat_commands_gfx.lua and
  scripts/combat_commands_metadata.lua against the retail WKL01.BIN and
  SLG.BIN.

  WKL01 has 206 images: 162 uncompressed command images in 16 blocks inside a
  0x117A0-byte region at 0x336F8, and 44 special-move images in 11 PRS streams
  inside a 0x1BA4-byte section at 0x4C828.  Every number below is read from the
  file or from the codec's exported retail layout.
]]

local gfx  = dofile(LUDARED.SCRIPTS .. "/combat_commands_gfx.lua")
local meta = dofile(LUDARED.SCRIPTS .. "/combat_commands_metadata.lua")
local bmp  = dofile(LUDARED.SCRIPTS .. "/shared/bmp.lua")
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

local function u16(data, offset) return string.unpack(">I2", data, offset + 1) end
local function u32(data, offset) return string.unpack(">I4", data, offset + 1) end

local function dimensions(picture)
  local width, height = string.unpack("<i4i4", picture, 19)
  return width, math.abs(height)
end

local wkl = assets.read("SakTaiCD1_Track1.bin/SAKURA2/WKL01.BIN")
local slg = assets.read("SakTaiCD1_Track1.bin/SAKURA2/SLG.BIN")

-- The codec reads sheets (and the metadata plugin its canvases) from the
-- workspace, so the whole test runs against a scratch one: the real workspace
-- carries the authored COMBAT/CMD_MAIN.bmp and would size the region by it.
local TMP     = "/tmp/ludared_combat_commands_test"
local SAKURA2 = TMP .. "/SakTaiCD1_Track1.bin/SAKURA2"
os.execute("rm -rf '" .. TMP .. "'")
os.execute("mkdir -p '" .. SAKURA2 .. "'")

local old_workspace = LUDARED.WORKSPACE
LUDARED.WORKSPACE = TMP

print("test_combat_commands.lua")

local base        = u32(wkl, 0xE8)
local region_size = u32(wkl, 0xEC)
local moves_base  = u32(wkl, 0x100)
local moves_size  = (function()
  for i = 0, 97 do
    if u32(wkl, i * 8) == moves_base and u32(wkl, i * 8 + 4) ~= 0 then
      return u32(wkl, i * 8 + 4)
    end
  end
end)()

check("retail command region", base == 0x336F8 and region_size == 0x117A0,
  string.format("0x%X / 0x%X", base, region_size))
check("retail moves section", moves_base == 0x4C828 and moves_size == 0x1BA4,
  string.format("0x%X / 0x%X", moves_base, moves_size))
check("codec agrees on the retail region", gfx.retail_region == region_size)

check("can_handle real WKL01", gfx.can_handle(wkl) == "likely")
check("can_handle rejects the SLG executable", gfx.can_handle(slg) == "no")
check("SLG anchors are not WKL", meta.can_handle(wkl) == "no")

local artifacts = gfx.decode(wkl)
check("206 images", #artifacts == 206, tostring(#artifacts))

local by_name = {}
for _, artifact in ipairs(artifacts) do by_name[artifact.name] = artifact.data end

local first = by_name["COMBAT/command_00_00.bmp"]
check("first command exists", first ~= nil)
local first_w, first_h = dimensions(first)
check("first command is 96x32", first_w == 96 and first_h == 32,
  string.format("%dx%d", first_w, first_h))

local move = by_name["NAMES/special_move_00_00.bmp"]
check("first special move exists", move ~= nil)
local move_w, move_h = dimensions(move)
check("first special move is 40x16", move_w == 40 and move_h == 16,
  string.format("%dx%d", move_w, move_h))

-- The palette is the 0SLG.BIN one at 0x11B78, carried as a display ramp.
local _, palette = bmp.parse(first, first_w, first_h, 4)
check("command palette matches 0SLG.BIN",
  palette == bmp.from_bgr555(slg:sub(0x11B78 + 1, 0x11B78 + 32), 16))
check("special-move palette matches it too", select(2, bmp.parse(move, move_w, move_h, 4)) == palette)

check("unmodified encode is byte-identical", gfx.encode(wkl, artifacts) == wkl)

-- An in-place command repaint changes the file only where that image lives.
do
  local pixels = bmp.parse(first, first_w, first_h, 4)
  local painted = string.char(pixels:byte(1) ~ 0x0F) .. pixels:sub(2)
  local edited = gfx.encode(wkl, {
    { name = "COMBAT/command_00_00.bmp", data = bmp.build(painted, first_w, first_h, 4, palette) },
  })

  check("repaint keeps the file size", #edited == #wkl)

  local data_start = base + 0x80 + 8 + 34 * 16 + 8
  check("repaint touches only that image",
    edited:sub(1, data_start) == wkl:sub(1, data_start)
    and edited:sub(data_start + #painted + 1) == wkl:sub(data_start + #painted + 1))

  local again = {}
  for _, artifact in ipairs(gfx.decode(edited)) do again[artifact.name] = artifact.data end
  check("repaint survives", bmp.parse(again["COMBAT/command_00_00.bmp"], first_w, first_h, 4) == painted)
  check("the other group is untouched", again["NAMES/special_move_00_00.bmp"] == move)
end

-- Growing a command image by 32 pixels of width relocates the region.
do
  local pixels = bmp.parse(first, first_w, first_h, 4)
  local wide_w = first_w + 32
  local rows = {}
  for y = 0, first_h - 1 do
    rows[y + 1] = pixels:sub(y * (first_w // 2) + 1, (y + 1) * (first_w // 2))
      .. string.rep("\0", wide_w // 2 - first_w // 2)
  end
  local wide_pixels = table.concat(rows)
  local delta = wide_w * first_h // 2 - first_w * first_h // 2

  local grown = gfx.encode(wkl, {
    { name = "COMBAT/command_00_00.bmp", data = bmp.build(wide_pixels, wide_w, first_h, 4, palette) },
  })

  check("growth adds exactly the new pixels", #grown == #wkl + delta,
    string.format("%d vs %d", #grown, #wkl))
  check("region pointer unchanged", u32(grown, 0xE8) == base)
  check("region size updated", u32(grown, 0xEC) == region_size + delta,
    string.format("0x%X", u32(grown, 0xEC)))
  check("next block shifted", u32(grown, 30 * 8) == u32(wkl, 30 * 8) + delta)
  check("moves section shifted", u32(grown, 0x100) == moves_base + delta)
  check("moves section size unchanged",
    (function()
      for i = 0, 97 do
        if u32(grown, i * 8) == moves_base + delta and u32(grown, i * 8 + 4) ~= 0 then
          return u32(grown, i * 8 + 4)
        end
      end
    end)() == moves_size)
  check("last header entry shifted", u32(grown, 95 * 8) == u32(wkl, 95 * 8) + delta)
  check("grown file length matches the last entry",
    #grown == u32(grown, 95 * 8) + u32(grown, 95 * 8 + 4))
  check("grown file still detects", gfx.can_handle(grown) == "likely")

  local after = {}
  for _, artifact in ipairs(gfx.decode(grown)) do after[artifact.name] = artifact.data end
  check("206 images after relocation", #gfx.decode(grown) == 206)
  check("new dimensions survive", select(1, dimensions(after["COMBAT/command_00_00.bmp"])) == wide_w)
  check("neighbour unchanged", after["COMBAT/command_00_01.bmp"] == by_name["COMBAT/command_00_01.bmp"])
  check("later block unchanged", after["COMBAT/command_15_00.bmp"] == by_name["COMBAT/command_15_00.bmp"])
  check("special moves survive the command shift",
    after["NAMES/special_move_00_00.bmp"] == move
    and after["NAMES/special_move_10_00.bmp"] == by_name["NAMES/special_move_10_00.bmp"])
end

-- Editing a special move recompresses its stream; the section relocates.
do
  local pixels = bmp.parse(move, move_w, move_h, 4)
  local painted = string.char(pixels:byte(1) ~ 0xFF) .. pixels:sub(2)
  local edited = gfx.encode(wkl, {
    { name = "NAMES/special_move_00_00.bmp", data = bmp.build(painted, move_w, move_h, 4, palette) },
  })

  check("command region untouched by a move edit",
    u32(edited, 0xEC) == region_size)
  check("moves section resized", #edited ~= #wkl)

  local section_start = moves_base
  local section_now
  for i = 0, 97 do
    if u32(edited, i * 8) == section_start and u32(edited, i * 8 + 4) ~= 0 then
      section_now = u32(edited, i * 8 + 4)
    end
  end
  check("moves section has a size", section_now ~= nil and section_now ~= moves_size,
    tostring(section_now))
  check("the section is the new file's tail",
    #edited == u32(edited, 95 * 8) + u32(edited, 95 * 8 + 4))

  local after = {}
  for _, artifact in ipairs(gfx.decode(edited)) do after[artifact.name] = artifact.data end
  check("move edit survives", bmp.parse(after["NAMES/special_move_00_00.bmp"], move_w, move_h, 4) == painted)
  check("other moves unchanged", after["NAMES/special_move_00_01.bmp"] == by_name["NAMES/special_move_00_01.bmp"])
  check("every command image unchanged",
    after["COMBAT/command_00_00.bmp"] == first
    and after["COMBAT/command_15_03.bmp"] == by_name["COMBAT/command_15_03.bmp"])
end

-- Resizing a special move is allowed; the region grows with it.
do
  local pixels = bmp.parse(move, move_w, move_h, 4)
  local wide_w = move_w + 8
  local rows = {}
  for y = 0, move_h - 1 do
    rows[y + 1] = pixels:sub(y * (move_w // 2) + 1, (y + 1) * (move_w // 2))
      .. string.rep("\0", wide_w // 2 - move_w // 2)
  end
  local resized = gfx.encode(wkl, {
    { name = "NAMES/special_move_00_00.bmp", data = bmp.build(table.concat(rows), wide_w, move_h, 4, palette) },
  })

  local after = {}
  for _, artifact in ipairs(gfx.decode(resized)) do after[artifact.name] = artifact.data end
  check("resized move decodes at the new size",
    select(1, dimensions(after["NAMES/special_move_00_00.bmp"])) == wide_w)
  check("resizing a move leaves the commands alone",
    after["COMBAT/command_00_00.bmp"] == first and u32(resized, 0xEC) == region_size)
end

check_error("command width must stay 8-pixel aligned", function()
  local pixels = bmp.parse(first, first_w, first_h, 4)
  local odd_w = first_w + 4
  local rows = {}
  for y = 0, first_h - 1 do
    rows[y + 1] = pixels:sub(y * (first_w // 2) + 1, (y + 1) * (first_w // 2))
      .. string.rep("\0", odd_w // 2 - first_w // 2)
  end
  gfx.encode(wkl, {
    { name = "COMBAT/command_00_00.bmp", data = bmp.build(table.concat(rows), odd_w, first_h, 4, palette) },
  })
end, "multiple of 8")

check_error("this codec takes no arguments", function()
  gfx.encode(wkl, artifacts, "WKL")
end, "takes no arguments")

check_error("truncated WKL is rejected", function()
  gfx.decode(wkl:sub(1, 0x1000))
end, "combat_commands_gfx")

-- ---------------------------------------------------------------- sheets

-- CMD_MAIN.bmp: 2 columns (ACTIVE / INACTIVE) by 6 rows of main commands.
local function write_sheet(width, height, wkl_name, fill)
  local dir = SAKURA2 .. "/" .. wkl_name .. "/COMBAT"
  os.execute("mkdir -p '" .. dir .. "'")
  local pixels = string.rep(fill or "\0", width * height // 2)
  local file = assert(io.open(dir .. "/CMD_MAIN.bmp", "wb"))
  file:write(bmp.build(pixels, width, height, 4))
  file:close()
end

-- 10 slots take a cell: 6 ACTIVE labels and 4 INACTIVE ones (情報 and 終 have
-- no inactive art at retail, so their second cells are ignored).
local SHEET_SLOTS = 10
local SHEET_DELTA = SHEET_SLOTS * ((32 * 15) // 2 - 128)   -- 32x15 cells, 1120

write_sheet(32, 96, "WKL01.BIN")
check("a 16x16-cell sheet keeps the retail layout",
  gfx.region_size(SAKURA2 .. "/WKL01.BIN") == 0x117A0,
  tostring(gfx.region_size(SAKURA2 .. "/WKL01.BIN")))
check("a 16x16-cell sheet keeps the retail size", #gfx.encode(wkl, {}) == #wkl)

write_sheet(64, 90, "WKL01.BIN")
check("a 32x15-cell sheet grows the region by 1120",
  gfx.region_size(SAKURA2 .. "/WKL01.BIN") == 0x117A0 + SHEET_DELTA,
  tostring(gfx.region_size(SAKURA2 .. "/WKL01.BIN")))
check("a WKL without a copy still reads its own BMPs",
  gfx.region_size(SAKURA2 .. "/WKL02.BIN") == 0x117A0)

local sheeted = gfx.encode(wkl, {})
check("the sheet is written into the file", #sheeted == #wkl + SHEET_DELTA,
  string.format("%d vs %d", #sheeted, #wkl + SHEET_DELTA))

local after_sheet = {}
for _, artifact in ipairs(gfx.decode(sheeted)) do after_sheet[artifact.name] = artifact.data end
check("a named slot takes the cell size",
  select(1, dimensions(after_sheet["COMBAT/command_00_05.bmp"])) == 32
  and select(2, dimensions(after_sheet["COMBAT/command_00_05.bmp"])) == 15)
check("a dim slot takes it too",
  select(1, dimensions(after_sheet["COMBAT/command_00_31.bmp"])) == 32)
check("an unnamed slot keeps its BMP",
  after_sheet["COMBAT/command_00_07.bmp"] == by_name["COMBAT/command_00_07.bmp"])
check("the sheet beats the individual BMP of a slot", (function()
  local pixels = bmp.parse(by_name["COMBAT/command_00_05.bmp"], 16, 16, 4)
  return gfx.encode(wkl, {
    { name = "COMBAT/command_00_05.bmp", data = bmp.build(pixels, 16, 16, 4, palette) },
  }) == sheeted
end)())

-- The sheet is disc-wide: one WKL's copy sets the anchors for all thirteen.
check("one sheet moves the SLG anchors for every WKL",
  u32(meta.encode(slg, {}), 0x14058) == u32(slg, 0x14058) + SHEET_DELTA)

-- Wider cells cannot keep the retail 16-pixel row; the six x values are data at
-- 0x46C60, { i16 x; i16 y; u16 pad; u16 entries }.
local function layout_x(data, i)
  return string.unpack(">i2", data, 0x46C60 + (i - 1) * 8 + 1)
end
local function layout_row(data)
  local xs = {}
  for i = 1, 6 do xs[i] = layout_x(data, i) end
  return table.concat(xs, ",")
end

check("the retail command row is a 16-pixel pitch",
  layout_row(slg) == "0,16,32,48,64,88", layout_row(slg))

local spaced = meta.encode(slg, {})
check("32-pixel cells respace the command row",
  layout_row(spaced) == "0,32,64,96,128,168", layout_row(spaced))
check("the row keeps its heights and submenu counts", (function()
  for i = 1, 6 do
    local at = 0x46C60 + (i - 1) * 8
    if spaced:sub(at + 3, at + 8) ~= slg:sub(at + 3, at + 8) then return false end
  end
  return true
end)())

-- The entries themselves sit 8 pixels right of the label: {u16 pad; i16 x;
-- i16 y; u16 pad; u16 image}, 10 bytes each.
local LISTS = {
  { offset = 0x46CC2, count = 2, x = 8 },
  { offset = 0x46CFE, count = 3, x = 24 },
  { offset = 0x46D1C, count = 4, x = 40 },
  { offset = 0x46D44, count = 4, x = 56 },
  { offset = 0x46D80, count = 2, x = 72 },
  { offset = 0x46D6C, count = 2, x = 96 },
}
local function entry_row(data)
  local xs = {}
  for i, list in ipairs(LISTS) do
    xs[i] = string.unpack(">i2", data, list.offset + 3)
  end
  return table.concat(xs, ",")
end

check("the retail entries hang off their labels",
  entry_row(slg) == "8,24,40,56,72,96", entry_row(slg))
check("32-pixel cells respace the entries with them",
  entry_row(spaced) == "8,40,72,104,136,176", entry_row(spaced))
check("the entries keep their rows and images", (function()
  for _, list in ipairs(LISTS) do
    for j = 0, list.count - 1 do
      local at = list.offset + j * 10
      if spaced:sub(at + 5, at + 10) ~= slg:sub(at + 5, at + 10) then return false end
    end
  end
  return true
end)())

-- The main-command panel: { u16 image; u16 x; u16 y; u16 pad } at 0x46C90,
-- and one selection box per command at 0x46E3C.
local function panel_row(data)
  local xs = {}
  for i = 1, 6 do
    xs[i] = string.unpack(">i2", data, 0x46C90 + (i - 1) * 8 + 3)
  end
  return table.concat(xs, ",")
end
local function rect_row(data)
  local out = {}
  for i = 1, 6 do
    local at = 0x46E3C + (i - 1) * 16
    local x1 = string.unpack(">i2", data, at + 3)
    local x2 = string.unpack(">i2", data, at + 11)
    out[i] = string.format("%d-%d", x1, x2)
  end
  return table.concat(out, ",")
end

check("the retail panel repeats the label columns",
  panel_row(slg) == "8,24,40,56,72,96", panel_row(slg))
check("32-pixel cells respace the panel",
  panel_row(spaced) == "8,40,72,104,136,176", panel_row(spaced))
check("the retail selection boxes are 16 wide",
  rect_row(slg) == "8-24,24-40,40-56,56-72,72-88,96-112", rect_row(slg))
check("32-pixel cells widen the selection boxes",
  rect_row(spaced) == "8-40,40-72,72-104,104-136,136-168,176-208", rect_row(spaced))
check("the panel keeps its rows and images", (function()
  for i = 1, 6 do
    local at = 0x46C90 + (i - 1) * 8
    if spaced:sub(at + 1, at + 2) ~= slg:sub(at + 1, at + 2) then return false end
    if spaced:sub(at + 5, at + 8) ~= slg:sub(at + 5, at + 8) then return false end
    local rect = 0x46E3C + (i - 1) * 16
    if spaced:sub(rect + 5, rect + 10) ~= slg:sub(rect + 5, rect + 10) then return false end
  end
  return true
end)())
check("the moved executable decodes the same size",
  meta.encode(meta.encode(slg, {}), {}) == meta.encode(slg, {}))

-- Sheets that disagree on cell size would give the disc two layouts.
write_sheet(64, 96, "WKL02.BIN")
check_error("two copies with different cells are refused", function()
  meta.encode(slg, {})
end, "one file for the disc")
os.execute("rm -f '" .. SAKURA2 .. "/WKL02.BIN/COMBAT/CMD_MAIN.bmp'")

-- A sheet that does not divide exactly is refused.
local function write_sheet_bytes(width, height, wkl_name, data)
  local dir = SAKURA2 .. "/" .. wkl_name .. "/COMBAT"
  os.execute("mkdir -p '" .. dir .. "'")
  local file = assert(io.open(dir .. "/CMD_MAIN.bmp", "wb"))
  file:write(data)
  file:close()
end
write_sheet_bytes(64, 89, "WKL01.BIN", bmp.build(string.rep("\0", 64 * 89 // 2), 64, 89, 4))
check_error("a sheet that does not split evenly is refused", function()
  gfx.encode(wkl, {})
end, "equal cells")

os.execute("rm -f '" .. SAKURA2 .. "/WKL01.BIN/COMBAT/CMD_MAIN.bmp'")
check("removing the sheet restores the retail build", gfx.encode(wkl, {}) == wkl)
check("and the retail region", gfx.region_size(SAKURA2 .. "/WKL01.BIN") == 0x117A0)

-- CMD_NAMES.bmp: 2 x 12 cells of 56x15 at 112 x 180, one row per command.  12
-- rows have a label; only six of their inactive cells replace anything
-- (Déplacer, Statut, Carte, Stratégie, Terminer and Protéger have no inactive
-- art at retail).  A 56x15 cell is 420 bytes, so it is padded with four blank
-- bytes to the 424 the next 8-byte VDP1 character starts on; the sprite still
-- draws 56x15 and never reads them.
local NAMES_SLOTS = 18
local NAMES_CELL  = (56 * 15) // 2 + 4                      -- 420 -> 424
local NAMES_DELTA = NAMES_SLOTS * (NAMES_CELL - 192)        -- 4176

local function write_names(width, height)
  local dir = SAKURA2 .. "/WKL01.BIN/COMBAT"
  os.execute("mkdir -p '" .. dir .. "'")
  local file = assert(io.open(dir .. "/CMD_NAMES.bmp", "wb"))
  file:write(bmp.build(string.rep("\0", width * height // 2), width, height, 4))
  file:close()
end

write_names(112, 180)
check("a 56x15 cell is padded to 424 bytes",
  gfx.region_size(SAKURA2 .. "/WKL01.BIN") == 0x117A0 + NAMES_DELTA,
  tostring(gfx.region_size(SAKURA2 .. "/WKL01.BIN")))

local named = gfx.encode(wkl, {})
check("the names sheet is written into the file", #named == #wkl + NAMES_DELTA,
  string.format("%d vs %d", #named, #wkl + NAMES_DELTA))

-- The padding lands in the block's own offset table: image 7 (the first
-- 56x15 cell) is stored as 424 bytes, and every image in the block still starts
-- on an 8-byte character address.
local names_block = base + u32(wkl, base)
local function stored_length(data, j)          -- what image j - 1 is recorded as
  return u32(data, names_block + 8 + 16 * j + 4)
end
check("the block stores the padded cell, and only that one changed",
  stored_length(named, 8) == 424 and stored_length(named, 7) == 128,
  string.format("%d / %d", stored_length(named, 8), stored_length(named, 7)))
check("every image in the block starts on an 8-byte address", (function()
  for j = 0, 33 do
    local at = names_block + 8 + 16 * j
    if (u32(named, at) + u32(named, at + 4)) % 8 ~= 0 then return false end
  end
  return true
end)())
check("re-encoding the padded block changes nothing", gfx.encode(named, {}) == named)

local after_names = {}
for _, artifact in ipairs(gfx.decode(named)) do after_names[artifact.name] = artifact.data end
local function size_of(name)
  local w, h = dimensions(after_names[name])
  return string.format("%dx%d", w, h)
end
check("a listed command takes the cell size", size_of("COMBAT/command_00_10.bmp") == "56x15",
  size_of("COMBAT/command_00_10.bmp"))
check("its inactive twin takes it too", size_of("COMBAT/command_00_11.bmp") == "56x15",
  size_of("COMBAT/command_00_11.bmp"))
check("a command outside the sheet keeps its BMP", size_of("COMBAT/command_00_24.bmp") == "16x16",
  size_of("COMBAT/command_00_24.bmp"))
check("and one whose inactive cell is unused", size_of("COMBAT/command_00_32.bmp") == "56x15",
  size_of("COMBAT/command_00_32.bmp"))

os.execute("rm -f '" .. SAKURA2 .. "/WKL01.BIN/COMBAT/CMD_NAMES.bmp'")
check("removing the names sheet restores the retail build", gfx.encode(wkl, {}) == wkl)

-- ---------------------------------------------------------------- metadata

local function write_command(width, height, wkl_name)
  local dir = SAKURA2 .. "/" .. wkl_name .. "/COMBAT"
  os.execute("mkdir -p '" .. dir .. "'")
  local pixels = string.rep("\0", width * height // 2)
  local file = assert(io.open(dir .. "/command_00_00.bmp", "wb"))
  file:write(bmp.build(pixels, width, height, 4))
  file:close()
end

local function write_all(width, height)
  for _, name in ipairs(gfx.wkl_files) do write_command(width, height, name) end
end

check("metadata recognises the retail executable", meta.can_handle(slg) == "certain")
check("no canvas overrides, no change", meta.encode(slg, {}) == slg)

check("the retail layout reproduces 0x117A0", gfx.region_size("/nonexistent") == 0x117A0)

write_all(96, 32)
check("same-size canvases keep the retail layout", gfx.region_size(SAKURA2 .. "/WKL01.BIN") == 0x117A0)
check("same-size canvases are a no-op", meta.encode(slg, {}) == slg)

local delta = 32 * 32 // 2          -- 96x32 -> 128x32
write_all(128, 32)
check("resized canvases grow the region by 512",
  gfx.region_size(SAKURA2 .. "/WKL01.BIN") == 0x117A0 + delta,
  tostring(gfx.region_size(SAKURA2 .. "/WKL01.BIN")))

local moved = meta.encode(slg, {})
check("metadata grows the VDP1 anchors",
  u32(moved, 0x14058) == u32(slg, 0x14058) + delta
  and u32(moved, 0x10F8C) == u32(slg, 0x10F8C) + delta
  and u32(moved, 0x1070) == u32(slg, 0x1070) + delta)
check("the dialogue-text pair belongs to the font patch, not here",
  u32(moved, 0x21590) == u32(slg, 0x21590)
  and u32(moved, 0x219C4) == u32(slg, 0x219C4))
check("packed face offsets move in eighths",
  u16(moved, 0x142A6) == u16(slg, 0x142A6) + delta // 8,
  string.format("0x%X vs 0x%X", u16(moved, 0x142A6), u16(slg, 0x142A6)))

local function without_sites(data)
  local sites = {}
  for _, site in ipairs(meta._sites) do sites[#sites + 1] = site end
  table.sort(sites, function(a, b) return a.offset < b.offset end)

  local out, position = {}, 1
  for _, site in ipairs(sites) do
    out[#out + 1] = data:sub(position, site.offset)
    position = site.offset + (site.kind == "u16" and 3 or 5)
  end
  out[#out + 1] = data:sub(position)
  return table.concat(out)
end
check("only the anchor bytes change", without_sites(slg) == without_sites(moved))

check("metadata is idempotent", meta.encode(moved, {}) == moved)
check("metadata sees the applied delta", meta._applied_delta(moved) == delta)
check("metadata recognises a moved executable", meta.can_handle(moved) == "possible")

write_all(96, 32)
check("restoring the canvases restores the executable", meta.encode(moved, {}) == slg)
check("and the anchors agree again", meta._applied_delta(slg) == 0)

-- When the WKLs disagree the anchors follow the largest region, so a WKL that
-- kept smaller art still loads where they point.
write_all(128, 32)
os.execute("rm -rf '" .. SAKURA2 .. "/WKL07.BIN/COMBAT'")
local biggest = meta.encode(slg, {})
check("the largest layout wins when the WKLs differ",
  u32(biggest, 0x14058) == u32(slg, 0x14058) + delta,
  string.format("0x%X", u32(biggest, 0x14058)))
check("and the smaller WKL is reported", meta.encode(biggest, {}) == biggest)

os.execute("rm -rf '" .. TMP .. "'")
LUDARED.WORKSPACE = old_workspace

check_error("metadata takes no arguments", function()
  meta.encode(slg, {}, "512")
end, "takes no arguments")

check_error("a damaged anchor is reported", function()
  local bogus = moved:sub(1, 0x14058) .. "\0\0\0\0" .. moved:sub(0x1405D)
  meta.encode(bogus, {})
end, "anchors here")

print(string.format("%d passed, %d failed", pass, fail))
assert(fail == 0)
