--[[
  Test harness for subtitles_metadata.lua

  Run: lua test_subtitles_metadata.lua

  The plugin's job is to write each subtitle's size, block offset and screen
  position from the BMPs in the workspace, so the tests build a throwaway
  workspace and drive it through tables shaped like the original SAKURA ones.
]]

local function script_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then
    return src:sub(2):match("^(.*)[/\\][^/\\]*$") or "."
  end
  return "."
end

local codec = dofile(script_dir() .. "/../subtitles_metadata.lua")

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
local SUBTITLE_DIR = TMP .. "/workspace/SakTaiCD1_Track1.bin/data.bin/SAKURA1/LOGO.SH2"

local function write_bmp(path, width, height)
  local fh = assert(io.open(path, "wb"))
  local stride = ((width * 4 + 31) // 32) * 4
  local header = string.pack("<c2I4I2I2I4I4i4i4I2I2I4I4I4I4I4I4",
    "BM", 54 + stride * height, 0, 0, 54, 40, width, -height,
    1, 4, 0, stride * height, 0, 0, 16, 0)
  fh:write(header)
  fh:close()
end

local function reset_workspace(dims)
  os.execute("rm -rf '" .. TMP .. "'")
  os.execute("mkdir -p '" .. SUBTITLE_DIR .. "'")
  for i, d in ipairs(dims) do
    write_bmp(string.format("%s/SUBTITLES_%02d.bmp", SUBTITLE_DIR, i - 1), d[1], d[2])
  end
end

PROJECT_ROOT = TMP
LUDARED = nil

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

print("")
print(string.format("%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
