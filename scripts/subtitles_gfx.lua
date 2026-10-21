--[[
  Sakura Taisen (Saturn) — Subtitle Graphics Patch Plugin

  PATCH plugin for the subtitle image block in SAKURA1/LOGO.SH2.

  Layout (verified against SakuraTaisen.cpp: ExtractSubtitles / PatchSubtitles
  and the original ISO):

      0x00019578   32 bytes   16 x 15-bit BGR555 palette
      0x000196d8   12673 bytes PRS-compressed image block (bit-packed Sega PRS)

  The decompressed block is a plain concatenation of the 17 subtitle images:
  4bpp, row-major, high nibble is the left pixel. Image sizes come from the
  8-byte entries of the table at SAKURA:0x000a20c (offset in 8-byte units,
  width in 8-pixel tiles, height in pixels), which is handled by
  subtitles_metadata.lua.

  The sizes are *data*, not constants: PatchSubtitles in SakuraTaisen.cpp
  rewrites every entry from the BMP it converts, so a subtitle may be resized.
  The size must fit what the table can express: width in whole 8-pixel tiles and
  an even height (the block offset is counted in 8-byte units).
  encode() therefore reads the block layout from the BMPs it is given, and
  subtitles_metadata.lua writes the matching table.  decode() uses the original
  disc's layout, since the table lives in SAKURA and is not visible from
  LOGO.SH2.

  Two limits come from the game, not from the file format.  Both were measured
  in-game against the renders in the workspace, and both are checked here
  because a build that breaks them still boots and still compresses -- it just
  draws the wrong thing:

    1. Position.  The renderer takes each sprite's top-left from a placement
       record, not from the image table: SAKURA:0x000a294 holds 17 records of
       {u16 index, u16 0, s16 x, s16 y}, and SAKURA:0x000a31c is 17 entries of
       {u32 0x01000000, u32 -> record}.  On the original disc every record is
       x = 160 - width/2, y = 176, so each sprite is centred by construction;
       the SH-2 loader at file offset 0xe6e4 (mapped at 0x06004000) hands both
       tables to the renderer.

       subtitles_metadata.lua rewrites x to (320 - width)/2 whenever it resizes
       an image, so the canvas as a whole is centred on screen.  The artwork is
       drawn centred inside its own canvas, so encode() writes the pixels
       exactly as they are: it does not measure or move anything.  A canvas
       wider than the original slot is therefore fine, and the only width limit
       is the 320-pixel screen.

    2. Staging.  The engine only reaches the first 0x4800 (18,432) bytes of the
       decompressed block -- the original block is 17,792 bytes and fits.  Every
       image that starts past that point shows stale VRAM instead of its own
       pixels, which is what produced the garbage subtitles.  The budget is on
       the *decompressed* size, so compressing better does not buy any room.

  Each artifact is an indexed 4bpp BMP whose palette is the in-game palette,
  so the transparent colour (index 0) is visible while editing.
]]

local prs
if LUDARED and LUDARED.SCRIPTS then
  prs = dofile(LUDARED.SCRIPTS .. "/shared/prs.lua")
else
  prs = dofile((function()
    local paths = {
      "scripts/shared/prs.lua",
      "../shared/prs.lua",
      "./shared/prs.lua"
    }
    for _, p in ipairs(paths) do
      local f = io.open(p, "r")
      if f then
        f:close()
        return p
      end
    end
    return "scripts/shared/prs.lua"
  end)())
end

local codec = {}

codec.name        = "Sakura Taisen Subtitle Graphics"
codec.description = "PATCH plugin for the PRS-compressed subtitle images in LOGO.SH2"
codec.version     = 6
codec.kind        = "patch"

local LOGO_SUBTITLE_PRS_OFFSET = 0x000196d8
local LOGO_PALETTE_OFFSET      = 0x00019578
local PALETTE_SIZE             = 32
local ORIGINAL_COMPRESSED_SIZE = 12673
local NUM_SUBTITLES            = 17

-- Width/height of each image in the *original* game, from the SAKURA:0x000a20c
-- table (width field * 8, height field).  Only decode() needs this: encode()
-- takes the layout from the BMPs.
local SUBTITLE_DIMS = {
  {w = 160, h = 16},
  {w = 112, h = 16},
  {w = 128, h = 16},
  {w = 144, h = 16},
  {w = 112, h = 16},
  {w = 112, h = 16},
  {w = 128, h = 16},
  {w = 144, h = 16},
  {w = 176, h = 16},
  {w = 96,  h = 16},
  {w = 144, h = 16},
  {w = 160, h = 16},
  {w = 112, h = 16},
  {w = 144, h = 16},
  {w = 112, h = 16},
  {w = 128, h = 16},      {w = 112, h = 16},
}

-- The table stores width/8 and height in single bytes, and the block offset in
-- 8-byte units in a u16.
local MAX_WIDTH_TILES = 0xFF
local MAX_HEIGHT_PX   = 0xFF
local MAX_BLOCK_BYTES = 0xFFFF * 8

-- Game limits, not file-format limits.  See the header comment.
local SCREEN_WIDTH       = 320
local ENGINE_STAGE_BYTES = 0x4800


local BMP_FILE_HEADER  = 14
local BMP_INFO_HEADER  = 40
local BMP_PAL_BYTES    = 16 * 4
local BMP_PIXEL_OFF    = BMP_FILE_HEADER + BMP_INFO_HEADER + BMP_PAL_BYTES

local function read_u16_be(data, offset)
  if offset + 1 > #data then
    return 0
  end
  return (string.byte(data, offset) << 8) | string.byte(data, offset + 1)
end

-- Saturn 32-byte palette -> 64-byte BMP palette (BGR0)
local function sat_palette_to_bmp(data)
  local t = {}
  for i = 0, 15 do
    local c = read_u16_be(data, 1 + i * 2) & 0x7FFF
    local b5 = c >> 10
    local g5 = (c >> 5) & 0x1F
    local r5 = c & 0x1F
    local o = i * 4
    t[o + 1] = (b5 * 255 + 15) // 31
    t[o + 2] = (g5 * 255 + 15) // 31
    t[o + 3] = (r5 * 255 + 15) // 31
    t[o + 4] = 0
  end
  return string.char(table.unpack(t))
end

local function row_stride(width)
  return ((width * 4 + 31) // 32) * 4
end

local function build_bmp(pixels, width, height, pal_bgra)
  local size = row_stride(width) * height
  if #pixels < size then
    pixels = pixels .. string.rep("\x00", size - #pixels)
  end

  local hdr = string.pack("<c2I4I2I2I4I4i4i4I2I2I4I4I4I4I4I4",
    "BM", BMP_PIXEL_OFF + size, 0, 0, BMP_PIXEL_OFF,
    BMP_INFO_HEADER, width, -height, 1, 4, 0, size, 0, 0, 16, 0
  )

  return hdr .. pal_bgra .. pixels:sub(1, size)
end

-- Returns the packed 4bpp pixels (row 0 = top, high nibble = left pixel) and
-- the image's own size.  The size is not checked against a constant: any size
-- the SAKURA:0xa20c table can describe is legal, so a subtitle may be resized by
-- dropping in a bigger BMP.  Accepts both bottom-up (positive height) and
-- top-down (negative height) BMPs, because image editors write either.
local function parse_bmp(bmp, stage)
  if #bmp < BMP_FILE_HEADER + BMP_INFO_HEADER then
    error(stage .. ": BMP too short (" .. #bmp .. " bytes)", 0)
  end
  if bmp:sub(1, 2) ~= "BM" then
    error(stage .. ": not a BMP file", 0)
  end

  local off, info_len, width, height, planes, bpp, comp =
    string.unpack("<I4I4i4i4I2I2I4", bmp, 11)

  local bottom_up = height > 0

  if planes ~= 1 then
    error(stage .. ": biPlanes != 1", 0)
  end
  if bpp ~= 4 then
    error(stage .. ": not a 4bpp image (biBitCount = " .. bpp .. ")", 0)
  end
  if comp ~= 0 then
    error(stage .. ": compressed BMP (biCompression = " .. comp .. ")", 0)
  end
  if info_len < BMP_INFO_HEADER then
    error(stage .. ": DIB header too small (" .. info_len .. " bytes)", 0)
  end
  if off < BMP_FILE_HEADER + info_len then
    error(stage .. ": bfOffBits overlaps the DIB header", 0)
  end

  if width <= 0 or height == 0 then
    error(string.format("%s: %dx%d is empty", stage, width, height), 0)
  end
  height = math.abs(height)

  -- The table stores width in whole 8-pixel tiles and the block offset in
  -- 8-byte units, so a size that does not fit those units cannot be described
  -- without silently padding — which would shift the artwork's centre.  Reject
  -- it instead and let the artist fix the canvas.
  if width % 8 ~= 0 then
    error(string.format(
      "%s: width %d is not a multiple of 8; SAKURA:0xa20c stores width/8 in one byte",
      stage, width), 0)
  end
  if width // 8 > MAX_WIDTH_TILES then
    error(string.format("%s: width %d exceeds %d (255 tiles of 8px)",
      stage, width, MAX_WIDTH_TILES * 8), 0)
  end
  if height > MAX_HEIGHT_PX then
    error(string.format("%s: height %d exceeds the table's %d-pixel limit",
      stage, height, MAX_HEIGHT_PX), 0)
  end
  if height % 2 ~= 0 then
    error(string.format(
      "%s: height %d is odd; the block offset is counted in 8-byte units, so "
      .. "the height must be even", stage, height), 0)
  end

  local stride = row_stride(width)
  local row_bytes = width // 2
  if #bmp < off + stride * height then
    error(stage .. ": truncated pixel data", 0)
  end

  local rows = {}
  for y = 0, height - 1 do
    local base = off + y * stride
    rows[y + 1] = bmp:sub(base + 1, base + row_bytes)
  end

  if bottom_up then
    -- Bottom-up: the first stored row is the bottom one.
    local flipped = {}
    for y = 1, height do
      flipped[y] = rows[height - y + 1]
    end
    rows = flipped
  end

  return table.concat(rows), width, height
end

local function image_block_size(dims)
  local total = 0
  for i = 1, NUM_SUBTITLES do
    total = total + (dims[i].w * dims[i].h) // 2
  end
  return total
end

function codec.can_handle(data)
  if type(data) ~= "string" then
    return "no"
  end
  if #data < LOGO_SUBTITLE_PRS_OFFSET + ORIGINAL_COMPRESSED_SIZE then
    return "no"
  end
  return "possible"
end

function codec.decode_name(args)
  return "SUBTITLES"
end

function codec.decode(data, args)
  if type(data) ~= "string" then
    error("decode: expected binary string", 0)
  end
  if #data < LOGO_SUBTITLE_PRS_OFFSET + ORIGINAL_COMPRESSED_SIZE then
    error("decode: LOGO.SH2 is too small for the subtitle block", 0)
  end

  local pal_bgra = sat_palette_to_bmp(
    data:sub(LOGO_PALETTE_OFFSET + 1, LOGO_PALETTE_OFFSET + PALETTE_SIZE))

  local compressed = data:sub(LOGO_SUBTITLE_PRS_OFFSET + 1,
                             LOGO_SUBTITLE_PRS_OFFSET + ORIGINAL_COMPRESSED_SIZE)
  local unpacked = prs.decompress(compressed)

  local expected = image_block_size(SUBTITLE_DIMS)
  if #unpacked < expected then
    error(string.format(
      "decode: subtitle block decompressed to %d bytes, expected %d",
      #unpacked, expected), 0)
  end

  local artifacts = {}
  local offset = 0
  for i = 1, NUM_SUBTITLES do
    local dims = SUBTITLE_DIMS[i]
    local size = (dims.w * dims.h) // 2
    local pixels = unpacked:sub(offset + 1, offset + size)
    offset = offset + size

    artifacts[i] = {
      name = string.format("SUBTITLES_%02d.bmp", i - 1),
      data = build_bmp(pixels, dims.w, dims.h, pal_bgra),
    }
  end

  return artifacts
end

function codec.encode(original, artifacts, args)
  if type(original) ~= "string" then
    error("encode: expected binary string for `original`", 0)
  end
  if #original < LOGO_SUBTITLE_PRS_OFFSET + ORIGINAL_COMPRESSED_SIZE then
    error("encode: LOGO.SH2 is too small for the subtitle block", 0)
  end
  if type(artifacts) ~= "table" then
    error("encode: expected the subtitle BMP artifacts", 0)
  end

  local by_index = {}
  for _, artifact in ipairs(artifacts) do
    if type(artifact) == "table" and type(artifact.name) == "string" then
      local index = artifact.name:match("^SUBTITLES_(%d+)%.bmp$")
      if index then
        by_index[tonumber(index) + 1] = artifact.data
      end
    end
  end

  local parts = {}
  local names = {}
  local offsets = {}
  local sizes = {}
  local block_size = 0
  for i = 1, NUM_SUBTITLES do
    local bmp = by_index[i]
    local stage = string.format("SUBTITLES_%02d.bmp", i - 1)
    if type(bmp) ~= "string" then
      error(stage .. ": missing", 0)
    end

    local pixels, w, h = parse_bmp(bmp, stage)
    if w > SCREEN_WIDTH then
      error(string.format(
        "%s: %d px wide, more than the %d-pixel screen; subtitles_metadata.lua "
        .. "cannot centre it", stage, w, SCREEN_WIDTH), 0)
    end
    parts[i] = pixels
    names[i] = stage
    offsets[i] = block_size
    sizes[i] = (w * h) // 2
    block_size = block_size + sizes[i]
  end

  if block_size > MAX_BLOCK_BYTES then
    error(string.format(
      "encode: the subtitle images total %d bytes, over the %d-byte block the "
      .. "SAKURA:0xa20c offsets can address",
      block_size, MAX_BLOCK_BYTES), 0)
  end

  -- The engine only stages the head of the block (see the header comment).
  -- Name the exact images that land outside it: they still build and the disc
  -- still boots, the game just shows stale VRAM where they should be.
  local staged = nil
  if block_size > ENGINE_STAGE_BYTES then
    local lost = {}
    for i = 1, NUM_SUBTITLES do
      if offsets[i] >= ENGINE_STAGE_BYTES then
        lost[#lost + 1] = string.format("%s (starts at %d)", names[i], offsets[i])
      elseif offsets[i] + sizes[i] > ENGINE_STAGE_BYTES then
        lost[#lost + 1] = string.format("%s (cut off at %d)", names[i], ENGINE_STAGE_BYTES)
      end
    end
    staged = string.format(
      "The block is %d bytes, but the engine only stages the first %d (0x%04X) "
      .. "bytes of it, so %d bytes would show stale VRAM instead of art (%s). "
      .. "Free %d bytes: the budget is on the decompressed block, so compressing "
      .. "better does not help -- an image costs width x height / 2.",
      block_size, ENGINE_STAGE_BYTES, ENGINE_STAGE_BYTES,
      block_size - ENGINE_STAGE_BYTES, table.concat(lost, ", "),
      block_size - ENGINE_STAGE_BYTES)
  end

  if staged then
    error("encode: " .. staged, 0)
  end

  local image_block = table.concat(parts)

  -- Unmodified artifacts: keep the original block byte for byte.
  local compressed_original = original:sub(LOGO_SUBTITLE_PRS_OFFSET + 1,
                                           LOGO_SUBTITLE_PRS_OFFSET + ORIGINAL_COMPRESSED_SIZE)
  if prs.decompress(compressed_original) == image_block then
    return original
  end

  local compressed = prs.compress(image_block)
  if #compressed > ORIGINAL_COMPRESSED_SIZE then
    error(string.format(
      "encode: subtitle block compresses to %d bytes, %d over the %d-byte budget; shorten the subtitles",
      #compressed, #compressed - ORIGINAL_COMPRESSED_SIZE, ORIGINAL_COMPRESSED_SIZE), 0)
  end

  compressed = compressed .. string.rep("\x00", ORIGINAL_COMPRESSED_SIZE - #compressed)

  return original:sub(1, LOGO_SUBTITLE_PRS_OFFSET)
    .. compressed
    .. original:sub(LOGO_SUBTITLE_PRS_OFFSET + ORIGINAL_COMPRESSED_SIZE + 1)
end

return codec
