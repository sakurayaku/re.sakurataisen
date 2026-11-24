--[[
  Sakura Taisen (Saturn) — theater-map EmptyRoom graphic

  PATCH codec for the single 4bpp bitmap the US patcher writes inline
  into the SAKURA executable instead of the TMAPSP/FUKAGAWA archives.

  SakuraTaisen.cpp PatchTheaterView special-cases a source BMP named
  "EmptyRoom": its pixels are written raw at SAKURA file offset 0x58D10 on
  disc 1 (0x58E48 on disc 2), and the archive rebuild skips it. PatchTMapSP
  passes the TMapSP patch directory (and the Fukagawa one through the same
  function), so the slot has exactly one writer.

  The slot is a fixed 672-byte budget (stock art is 56x24 4bpp = 672 bytes).
  Unlike the US tool, which requires exactly 56x24, this codec accepts any
  4bpp dimensions with a width divisible by 8 whose packed pixels fit the
  budget and zero-pads the remainder, so the neighbors starting at slot end
  are never touched. Dimensions live in extra TMAPSP LUT entry 93, after the
  93 archived images. Its address (0x19EC) plus renderer base (0x7A68) maps to
  the EmptyRoom VRAM destination; width is stored in 8-pixel tiles, height in
  pixels.

  This codec owns that 672-byte slot. The BMP palette is display-only, taken
  from the shared theater-map palette so the artifact matches the TMAPSP
  BMPs; pixel indices and dimensions round-trip.
]]

local function script_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then
    return src:sub(2):match("^(.*)[/\\][^/\\]*$") or "."
  end
  return "."
end

local function load_shared(name)
  if LUDARED and LUDARED.SCRIPTS then
    return dofile(LUDARED.SCRIPTS .. "/shared/" .. name .. ".lua")
  end
  return dofile(script_dir() .. "/../shared/" .. name .. ".lua")
end

local bmp = load_shared("bmp")
local can_handle = load_shared("can_handle")
local constants = load_shared("constants")

local codec = {}

codec.name        = "Sakura Taisen Theater-Map EmptyRoom Graphic"
codec.description = "Patches EmptyRoom pixels and dimensions in SAKURA (672-byte slot)"
codec.version     = 3
codec.kind        = "patch"

codec.WIDTH  = 56
codec.HEIGHT = 24
codec.BPP    = 4
codec.SIZE   = codec.WIDTH * codec.HEIGHT // 2 -- 672 bytes of packed 4bpp pixels

codec.FILE = "EmptyRoom.bmp"
codec.LUT_INDEX = 93

-- SakuraTaisen.cpp:8094: disc-2 build shifts this slot by +0x138.
codec.OFFSETS = {
  [1] = 0x00058D10,
  [2] = 0x00058E48,
}

-- SakuraTaisen.cpp LUT starts; EmptyRoom is extra entry 93.
codec.LUT_OFFSETS = {
  [1] = 0x0001EBF4,
  [2] = 0x0001EC0C,
}

local DISPLAY_PALETTE = constants.map_palette
codec.DISPLAY_PALETTE = DISPLAY_PALETTE

local function disc_for_size(data, stage)
  if #data == constants.CD1_SAKURA_BYTES then return 1 end
  if #data == constants.CD2_SAKURA_BYTES then return 2 end
  error(string.format("empty_room: %s: unsupported SAKURA size %d",
    stage, #data), 0)
end

local function slot_for(data, stage)
  local disc = disc_for_size(data, stage)
  local offset = codec.OFFSETS[disc]
  if offset + codec.SIZE > #data then
    error(string.format("empty_room: %s: SAKURA is too short for the slot", stage), 0)
  end
  local lut_offset = codec.LUT_OFFSETS[disc] + codec.LUT_INDEX * 8
  if lut_offset + 6 > #data then
    error(string.format("empty_room: %s: SAKURA is too short for the EmptyRoom dimensions", stage), 0)
  end
  return offset, disc
end

local function dimensions_for(data, disc, stage)
  local entry = codec.LUT_OFFSETS[disc] + codec.LUT_INDEX * 8
  local width_tiles = data:byte(entry + 5)
  local height = data:byte(entry + 6)
  local width = width_tiles * 8
  local size = width * height // 2
  if width_tiles == 0 or height == 0 or size > codec.SIZE then
    error(string.format("empty_room: %s: invalid LUT dimensions %dx%d", stage,
      width, height), 0)
  end
  return width, height, size
end

local function prefix(args)
  if type(args) == "table" and type(args.prefix) == "string" and args.prefix ~= "" then
    return (args.prefix:gsub("/+$", ""))
  end
  if type(args) == "string" and args ~= "" then
    return (args:gsub("/+$", ""))
  end
  return "EMPTY_ROOM"
end

local function artifact_name(args)
  return prefix(args) .. "/" .. codec.FILE
end

function codec.can_handle(data)
  return can_handle.can_handle_sakura1(data)
end

function codec.decode_name(args)
  return prefix(args)
end

function codec.decode(data, args)
  if type(data) ~= "string" then
    error("empty_room: decode: expected binary string", 0)
  end
  local offset, disc = slot_for(data, "decode")
  local width, height, size = dimensions_for(data, disc, "decode")
  local pixels = data:sub(offset + 1, offset + size)
  return {
    {
      name = artifact_name(args),
      data = bmp.build(pixels, width, height, codec.BPP, DISPLAY_PALETTE),
    },
  }
end

function codec.encode(original, artifacts, args)
  if type(original) ~= "string" then
    error("empty_room: encode: expected binary string for `original`", 0)
  end
  local offset, disc = slot_for(original, "encode")

  local by_name = {}
  for _, artifact in ipairs(artifacts or {}) do
    if type(artifact) == "table" and type(artifact.name) == "string" then
      by_name[artifact.name] = artifact.data
    end
  end

  local bmp_data = by_name[artifact_name(args)] or by_name[codec.FILE]
  if not bmp_data then return original end

  -- LUT width is stored in 8-pixel tiles, so resized art must stay tile-aligned.
  if type(bmp_data) ~= "string" or #bmp_data < 54 or bmp_data:sub(1, 2) ~= "BM" then
    error("empty_room: encode: not a BMP file", 0)
  end
  local width, height = string.unpack("<i4i4", bmp_data, 19)
  height = math.abs(height)
  if width <= 0 or height <= 0 then
    error(string.format("empty_room: encode: invalid dimensions %dx%d",
      width, height), 0)
  end
  if width % 8 ~= 0 or width // 8 > 0xff or height > 0xff then
    error(string.format("empty_room: encode: dimensions %dx%d cannot be stored in the LUT",
      width, height), 0)
  end
  local pixel_size = width * height // 2
  if pixel_size > codec.SIZE then
    error(string.format("empty_room: %dx%d needs %d pixel bytes, slot holds %d",
      width, height, pixel_size, codec.SIZE), 0)
  end

  local pixels = bmp.parse(bmp_data, width, height, codec.BPP)
  if #pixels < codec.SIZE then
    pixels = pixels .. string.rep("\0", codec.SIZE - #pixels)
  end

  local entry = codec.LUT_OFFSETS[disc] + codec.LUT_INDEX * 8
  local width_tiles = width // 8
  local old = original:sub(offset + 1, offset + codec.SIZE)
  if pixels == old and width_tiles == original:byte(entry + 5)
      and height == original:byte(entry + 6) then
    return original
  end

  local patched = original:sub(1, offset) .. pixels .. original:sub(offset + codec.SIZE + 1)
  return patched:sub(1, entry + 4) .. string.char(width_tiles, height)
    .. patched:sub(entry + 7)
end

return codec
