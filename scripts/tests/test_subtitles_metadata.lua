--[[
  Test harness for subtitles_metadata.lua

  Run: ludared codecs test tests/test_subtitles_metadata.lua

  The plugin's job is to write each subtitle's size, block offset and screen
  position from the BMPs in the workspace, so the tests build a throwaway
  workspace and drive it through tables shaped like the original SAKURA ones.

  A canvas whose every pixel is the transparent index is a placeholder, and its
  metadata is expected to point at the last canvas that draws -- the aliasing
  rule the encode tests below cover.
]]

local codec = dofile(LUDARED.SCRIPTS .. "/subtitles_metadata.lua")

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

local TABLE_OFFSET = 0x000a20c
local PLACEMENT_OFFSET = 0x000a294
local SCREEN_WIDTH = 320

-- The original disc's sizes, and what the workspace starts out holding.
local DIMS = {
  {160, 16}, {112, 16}, {128, 16}, {144, 16}, {112, 16}, {112, 16},
  {128, 16}, {144, 16}, {176, 16}, {96, 16},  {144, 16}, {160, 16},
  {112, 16}, {144, 16}, {112, 16}, {128, 16}, {112, 16},
}

local function entry(offset, unknown1, w_tiles, h, unknown2)
  return string.pack(">I2", offset)
    .. unknown1 .. string.char(w_tiles, h) .. unknown2
end

local function build_sakura(dims)
  local entries = {}
  local cursor = 0
  for i, d in ipairs(dims) do
    entries[i] = entry(cursor, "\xAA\xBB", d[1] // 8, d[2], "\xCC\xDD")
    cursor = cursor + (d[1] * d[2] // 2) // 8
  end

  -- Placement records as the disc ships them: index, 0, x = 160 - width/2, 176.
  local places = {}
  for i, d in ipairs(dims) do
    places[i] = string.pack(">I2I2I2I2", i - 1, 0, (SCREEN_WIDTH - d[1]) // 2, 176)
  end

  return string.rep("\0", TABLE_OFFSET)
    .. table.concat(entries)
    .. string.rep("\0", PLACEMENT_OFFSET - (TABLE_OFFSET + #table.concat(entries)))
    .. table.concat(places)
    .. string.rep("\0", 64)
end

local function read_entry(data, i)
  local pos = TABLE_OFFSET + (i - 1) * 8
  local b = data:sub(pos + 1, pos + 8)
  return {
    offset = b:byte(1) * 256 + b:byte(2),
    unknown1 = b:sub(3, 4),
    w_tiles = b:byte(5),
    h = b:byte(6),
    unknown2 = b:sub(7, 8),
  }
end

local function read_place(data, i)
  local pos = PLACEMENT_OFFSET + (i - 1) * 8
  local b = data:sub(pos + 1, pos + 8)
  return {
    index = b:byte(1) * 256 + b:byte(2),
    pad   = b:byte(3) * 256 + b:byte(4),
    x     = b:byte(5) * 256 + b:byte(6),
    y     = b:byte(7) * 256 + b:byte(8),
  }
end

-- ---------------------------------------------------------------------------
-- Throwaway workspace

local TMP = "/tmp/ludared_metadata_test"
local SUBTITLE_DIR = TMP .. "/workspace/SakTaiCD1_Track1.bin/SAKURA1/LOGO.SH2"

-- A 4bpp indexed BMP in the game's palette.  `fill` is the palette index
-- painted everywhere (or a function(x, y) returning one): 0 is the transparent
-- index, anything else draws.  Index 0 is deliberately painted a colour no
-- editor would use for "empty", because transparency is a property of the index
-- and not of the RGB value -- the game's own entry 0 is bright yellow.
-- `header_only` stops after the palette, which is how a truncated file reaches
-- the codec.
local function write_bmp(path, width, height, opts)
  opts = opts or {}
  local stride = ((width * 4 + 31) // 32) * 4
  local row_bytes = width // 2

  local pal = {}
  for i = 0, 15 do
    local bgr = (i == 0) and (opts.transparent_bgr or 0x00FFFF)
                      or (opts.visible_bgr or 0x000000)
    pal[i + 1] = string.char(bgr % 256, (bgr // 256) % 256, (bgr // 65536) % 256, 0)
  end

  local fill = opts.fill
  if fill == nil then fill = 1 end

  local rows = {}
  for y = 0, height - 1 do
    local cells = {}
    for x = 0, row_bytes - 1 do
      local left  = (type(fill) == "function") and fill(x * 2, y) or fill
      local right = (type(fill) == "function") and fill(x * 2 + 1, y) or fill
      cells[x + 1] = string.char((left << 4) | right)
    end
    rows[y + 1] = table.concat(cells) .. string.rep("\0", stride - row_bytes)
  end

  local off = 14 + 40 + 16 * 4
  local header = string.pack("<c2I4I2I2I4I4i4i4I2I2I4I4I4I4I4I4",
    "BM", off + stride * height, 0, 0, off, 40, width, -height,
    1, 4, 0, stride * height, 0, 0, 16, 0)

  local fh = assert(io.open(path, "wb"))
  fh:write(header, table.concat(pal),
    opts.header_only and "" or table.concat(rows))
  fh:close()
end

local function reset_workspace(dims, overrides)
  os.execute("rm -rf '" .. TMP .. "'")
  os.execute("mkdir -p '" .. SUBTITLE_DIR .. "/SUBTITLES'")
  for i, d in ipairs(dims) do
    write_bmp(string.format("%s/SUBTITLES/%02d.bmp", SUBTITLE_DIR, i - 1),
      d[1], d[2], overrides and overrides[i])
  end
end

LUDARED.WORKSPACE = TMP .. "/workspace"

print("subtitles_metadata.lua test harness")
print("")

-- ---------------------------------------------------------------------------

print("decode")
local sakura = build_sakura(DIMS)
local arts = codec.decode(sakura)
check("decode returns a table", type(arts) == "table")
check("decode on SAKURA is a nop (empty)", #arts == 0)

print("")
print("encode: sizes and offsets come from the BMPs")

reset_workspace(DIMS)
check("workspace matching the disc leaves the table untouched",
  codec.encode(sakura, arts) == sakura)

-- Resize subtitle 1 from 112x16 (896 bytes) to 256x32 (4096 bytes).
local resized = {}
for i, d in ipairs(DIMS) do resized[i] = { d[1], d[2] } end
resized[2] = { 256, 32 }
reset_workspace(resized)

local out = codec.encode(sakura, arts)
local first = read_entry(out, 2)
check("resized entry records its own width in tiles", first.w_tiles == 32,
  tostring(first.w_tiles))
check("resized entry records its own height", first.h == 32, tostring(first.h))
check("first entry still starts at offset 0", read_entry(out, 1).offset == 0)
check("following entry shifts by the size difference",
  read_entry(out, 3).offset == 0xA0 + (4096 // 8), tostring(read_entry(out, 3).offset))
check("last entry reflects the larger block",
  read_entry(out, 17).offset == 0x840 + (4096 - 896) // 8,
  tostring(read_entry(out, 17).offset))
check("reserved fields are preserved",
  first.unknown1 == "\xAA\xBB" and first.unknown2 == "\xCC\xDD")
check("only the two tables change",
  out:sub(TABLE_OFFSET + 17 * 8 + 1, PLACEMENT_OFFSET) ==
    sakura:sub(TABLE_OFFSET + 17 * 8 + 1, PLACEMENT_OFFSET)
  and out:sub(PLACEMENT_OFFSET + 17 * 8 + 1) == sakura:sub(PLACEMENT_OFFSET + 17 * 8 + 1)
  and #out == #sakura)

print("")
print("encode: screen placement comes from the BMPs")

local place = read_place(out, 2)
check("resized subtitle is centred on screen",
  place.x == (SCREEN_WIDTH - 256) // 2, tostring(place.x))
check("placement keeps the record index, reserved word and y",
  place.index == 1 and place.pad == 0 and place.y == 176,
  string.format("index %d pad %d y %d", place.index, place.pad, place.y))
check("an untouched slot keeps its original x", read_place(out, 1).x == 80,
  tostring(read_place(out, 1).x))

print("")
print("encode: rejections and fallbacks")

local function with_sizes(index, w, h)
  local dims = {}
  for i, d in ipairs(DIMS) do dims[i] = { d[1], d[2] } end
  dims[index] = { w, h }
  reset_workspace(dims)
  return sakura
end

check_err("width that is not a multiple of 8 is rejected", function()
  codec.encode(with_sizes(2, 252, 16), arts)
end, "multiple of 8")

check_err("height past a byte is rejected", function()
  codec.encode(with_sizes(2, 112, 256), arts)
end, "255-pixel limit")

check_err("odd height cannot be described in 8-byte offsets", function()
  codec.encode(with_sizes(2, 112, 15), arts)
end, "height must be even")

os.execute("rm -rf '" .. TMP .. "'")
check("no BMPs in the workspace leaves the table untouched",
  codec.encode(sakura, arts) == sakura)

check_err("a canvas wider than the screen is rejected", function()
  codec.encode(with_sizes(2, 328, 16), arts)
end, "pixel screen")

check_err("a short SAKURA file is rejected", function()
  codec.encode(string.rep("\0", 16), arts)
end, "too small")

-- ---------------------------------------------------------------------------
-- Blank canvases alias the last subtitle that draws

local BLANK = { fill = 0 }

local function dims_of(overrides)
  local dims = {}
  for i, d in ipairs(DIMS) do dims[i] = { d[1], d[2] } end
  for i, d in pairs(overrides or {}) do dims[i] = { d[1], d[2] } end
  return dims
end

-- Every canvas painted index 2, so one test can blank exactly one slot without
-- the rest of the workspace going blank as well.  Keeping index 1 out of the
-- background matters: the "index 0 is transparent" rule must not be able to
-- pass by treating every low index as empty.
local function visible_workspace(dims, overrides)
  local all = {}
  for i = 1, #dims do all[i] = { fill = 2 } end
  for i, o in pairs(overrides or {}) do all[i] = o end
  reset_workspace(dims, all)
end

local TWO_LINE_UNITS = (208 * 32 // 2) // 8     -- a 208x32 canvas: 416 units
local STUB_UNITS     = (8 * 2 // 2) // 8        -- an 8x2 placeholder: 1 unit

print("")
print("encode: a blank canvas shows the previous subtitle")

-- Subtitle 9 is a two-line 208x32 image and subtitle 10 is the empty 8x2
-- placeholder that stands in for the second id, the way a translator collapses
-- two ids onto one canvas.
local pair = dims_of({ [10] = {208, 32}, [11] = {8, 2} })
visible_workspace(pair, { [11] = BLANK })
local alias = codec.encode(sakura, arts)

local nine, ten = read_entry(alias, 10), read_entry(alias, 11)
check("the blank entry borrows the previous texture offset",
  ten.offset == nine.offset,
  string.format("0x%04x vs 0x%04x", ten.offset, nine.offset))
check("the blank entry borrows the previous width and height",
  ten.w_tiles == nine.w_tiles and ten.h == nine.h,
  string.format("%dx%d vs %dx%d", ten.w_tiles * 8, ten.h, nine.w_tiles * 8, nine.h))
check("the blank entry keeps its own reserved words",
  ten.unknown1 == "\xAA\xBB" and ten.unknown2 == "\xCC\xDD")

local place9, place10 = read_place(alias, 10), read_place(alias, 11)
check("the blank placement borrows the previous x and y",
  place10.x == place9.x and place10.y == place9.y,
  string.format("(%d,%d) vs (%d,%d)", place10.x, place10.y, place9.x, place9.y))
check("the borrowed position is where the wide canvas sits",
  place10.x == (SCREEN_WIDTH - 208) // 2 and place10.y == 176,
  string.format("(%d,%d)", place10.x, place10.y))
check("the blank placement keeps its own index", place10.index == 10,
  tostring(place10.index))
check("the descriptor table and the rest of the file are untouched",
  alias:sub(TABLE_OFFSET + 17 * 8 + 1, PLACEMENT_OFFSET) ==
      sakura:sub(TABLE_OFFSET + 17 * 8 + 1, PLACEMENT_OFFSET)
    and alias:sub(PLACEMENT_OFFSET + 17 * 8 + 1) ==
      sakura:sub(PLACEMENT_OFFSET + 17 * 8 + 1)
    and #alias == #sakura)
check("the blank canvas still reserves its own bytes in the block",
  read_entry(alias, 12).offset == nine.offset + TWO_LINE_UNITS + STUB_UNITS,
  string.format("0x%04x, expected 0x%04x", read_entry(alias, 12).offset,
    nine.offset + TWO_LINE_UNITS + STUB_UNITS))
check("re-encoding an aliased table changes nothing",
  codec.encode(alias, arts) == alias)

-- The same sizes, but the second canvas draws: it must keep its own metadata.
visible_workspace(pair)
local drawn = codec.encode(sakura, arts)
check("a canvas with visible pixels keeps its own size and position",
  read_entry(drawn, 11).w_tiles == 1 and read_entry(drawn, 11).h == 2
    and read_place(drawn, 11).x == (SCREEN_WIDTH - 8) // 2,
  string.format("%dx%d at x=%d", read_entry(drawn, 11).w_tiles * 8,
    read_entry(drawn, 11).h, read_place(drawn, 11).x))
check("aliasing moves no later image",
  read_entry(drawn, 12).offset == read_entry(alias, 12).offset
    and read_entry(drawn, 17).offset == read_entry(alias, 17).offset)

print("")
print("encode: consecutive blank canvases chain to the last visible subtitle")

local chain = dims_of({
  [10] = {208, 32}, [11] = {8, 2}, [12] = {8, 2}, [13] = {8, 2},
})
visible_workspace(chain, { [11] = BLANK, [12] = BLANK, [13] = BLANK })
local chained = codec.encode(sakura, arts)

local target = read_entry(chained, 10)
for _, i in ipairs({ 11, 12, 13 }) do
  local e, p = read_entry(chained, i), read_place(chained, i)
  check(string.format("subtitle %d borrows subtitle 9's texture", i - 1),
    e.offset == target.offset and e.w_tiles == target.w_tiles and e.h == target.h,
    string.format("0x%04x %dx%d", e.offset, e.w_tiles * 8, e.h))
  check(string.format("subtitle %d keeps its own index and borrows 9's position", i - 1),
    p.index == i - 1 and p.x == place9.x and p.y == place9.y,
    string.format("index %d at (%d,%d)", p.index, p.x, p.y))
end
check("each blank canvas advances the block by its own 8x2",
  read_entry(chained, 14).offset == target.offset + TWO_LINE_UNITS + 3 * STUB_UNITS,
  string.format("0x%04x, expected 0x%04x", read_entry(chained, 14).offset,
    target.offset + TWO_LINE_UNITS + 3 * STUB_UNITS))
check("subtitles 11 and 12 keep their own records in the descriptor table",
  chained:sub(PLACEMENT_OFFSET + 17 * 8 + 1) == sakura:sub(PLACEMENT_OFFSET + 17 * 8 + 1))

print("")
print("encode: a blank first canvas cannot borrow")

local head = dims_of({ [1] = {8, 2}, [2] = {8, 2} })
visible_workspace(head, { [1] = BLANK, [2] = BLANK })
local lonely = codec.encode(sakura, arts)
local first = read_entry(lonely, 1)
check("the first entry keeps its own offset, size and position",
  first.offset == 0 and first.w_tiles == 1 and first.h == 2
    and read_place(lonely, 1).x == (SCREEN_WIDTH - 8) // 2,
  string.format("0x%04x %dx%d at x=%d", first.offset, first.w_tiles * 8, first.h,
    read_place(lonely, 1).x))
check("the blank canvas after it has nothing to borrow either",
  read_entry(lonely, 2).offset == STUB_UNITS
    and read_entry(lonely, 2).w_tiles == 1 and read_entry(lonely, 2).h == 2,
  string.format("0x%04x %dx%d", read_entry(lonely, 2).offset,
    read_entry(lonely, 2).w_tiles * 8, read_entry(lonely, 2).h))

print("")
print("encode: blankness is decided on palette indices, not colours")

-- Index 0 painted bright yellow, as the game's own palette does: a colour-based
-- test would call this canvas visible.
visible_workspace(pair, { [11] = { fill = 0, transparent_bgr = 0x00FFFF } })
local yellow = codec.encode(sakura, arts)
check("a canvas of index 0 is blank whatever colour index 0 has",
  read_entry(yellow, 11).offset == read_entry(yellow, 10).offset,
  string.format("0x%04x", read_entry(yellow, 11).offset))

-- Index 1 painted black is still a pixel.
visible_workspace(pair, { [11] = { fill = 1, visible_bgr = 0x000000 } })
local black = codec.encode(sakura, arts)
check("a canvas of visible index 1 is not blank even when it is black",
  read_entry(black, 11).w_tiles == 1 and read_entry(black, 11).h == 2)

-- One visible pixel anywhere in the canvas is enough.
visible_workspace(pair, {
  [11] = { fill = function(x, y) return (x == 5 and y == 1) and 1 or 0 end },
})
local dot = codec.encode(sakura, arts)
check("a single visible pixel stops the alias",
  read_entry(dot, 11).w_tiles == 1 and read_entry(dot, 11).h == 2)

-- Pixels that cannot be read are not blank: subtitles_gfx.lua owns format errors.
visible_workspace(pair, { [11] = { header_only = true } })
local unreadable = codec.encode(sakura, arts)
check("a BMP whose pixels cannot be read keeps its own metadata",
  read_entry(unreadable, 11).w_tiles == 1 and read_entry(unreadable, 11).h == 2)

os.execute("rm -rf '" .. TMP .. "'")

print("")
print(string.format("%d passed, %d failed", pass, fail))
assert(fail == 0, string.format("%d tests failed", fail))
