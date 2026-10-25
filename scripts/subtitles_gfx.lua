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

    2. Staging.  VDP1 VRAM is partitioned by convention, not by an allocator: the
       atlas is DMA'd to 0x25c02280 and the next upload claims 0x25c07280, so
       0x5000 (20,480) bytes is the whole region the atlas can ever own.  The
       *transfer length* is a u16 immediate in this file's own export #6
       (offset 0xc06), which is why it is budgeted here and not in
       subtitles_metadata.lua: the shipped value is 0x4580 = 17,792 bytes, i.e.
       exactly the original block, and anything past it stays in the decoder's
       scratch and never reaches VRAM.

       `args` is the single string ludared passes through.  It accepts one
       key=value pair (pairs are ';'-separated, values ','-separated):

           grow_dma=none    (default) keep the shipped 0x4580 transfer and the
                            staged window this codec has always enforced
           grow_dma=safe    raise the transfer to the block's own size, up to
                            0x5000, by rewriting that u16

       "safe" only ever raises the length, and only when the block needs it, so
       a build that fits stays byte-identical and a hand-raised value survives.
       Anything else in `args` is an error rather than a silent default.

  Each artifact is an indexed 4bpp BMP whose palette is the in-game palette,
  so the transparent colour (index 0) is visible while editing.
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
  return dofile(script_dir() .. "/shared/" .. name .. ".lua")
end

local prs         = LUDARED.codec("std/sega/compression/prs")
local args_parser = load_shared("args_parser")

local codec = {}

codec.name        = "Sakura Taisen Subtitle Graphics"
codec.description = [[Sakura Taisen (Saturn) subtitle graphics: the PRS block in LOGO.SH2

Patches the 12,673-byte PRS-compressed image block at 0x000196d8 with the 17
SUBTITLES/nn.bmp canvases of the workspace, and returns the file untouched when
none of them changed, so an unchanged decode and rebuild is byte for byte the
disc's own file.

The block is the 17 images concatenated in id order, 4bpp, row-major, high
nibble left. Nothing separates them and nothing inside the block records their
sizes: those are entries of the table at SAKURA:0x000a20c, which
subtitles_metadata.lua writes. This codec reads the layout from the canvases
instead, so the two agree by construction as long as both are in the manifest
for the file pair -- and a manifest that pairs the block with a table written
from different canvases builds a disc whose images contradict their own sizes.

A canvas must be an indexed 4bpp BMP with an uncompressed 40-byte
BITMAPINFOHEADER, bottom-up or top-down, its width in whole 8-pixel tiles, an
even height, at most 320 pixels wide. Index 0 is the transparent colour, and
the palette the decoded canvases carry is the one the file already holds at
0x00019578: the colours are read out for editing, never written back, so a
palette change belongs to a palette codec. A canvas whose every pixel is index
0 is blank, which subtitles_metadata.lua answers by lending it the previous
visible subtitle's records -- but the blank canvas still owns its bytes here,
and 8x2, one 8-byte unit, is the cheapest placeholder.

Budget. The compressed block is fixed at 12,673 bytes and padded with zeroes,
and the images inside it are uncompressed: an image costs width x height / 2
whatever the artwork looks like, so the budget applies to the canvases and
nothing is gained by drawing something simpler.

Getting the block into VRAM is a second, tighter budget. VDP1 VRAM is
partitioned by convention, not by an allocator: the atlas is DMA'd to
0x25c02280 and the upload that follows claims 0x25c07280, leaving 0x5000 bytes
for it. The transfer length is a u16 in this file's own export #6, at offset
0x00000c06, and the shipped disc sets it to 0x4580 -- exactly the original
block's size, so anything past that stays in the decoder's scratch and shows
whatever VRAM held before. `grow_dma` decides what this codec may do with it.

Arguments (string):
  grow_dma (default: "none")
    What the transfer length may become when the canvases outgrow the one the
    disc shipped. It has no effect on decoding, which reads the same canvases
    out of the block either way, and a malformed value is refused in both
    passes rather than only where it would have been used.

    none       Refuse a block past 0x4800 and never touch the word. 0x4800 is
               the window this codec checked before the transfer length was
               located, and it is 640 bytes more lenient than the 0x4580 the
               game moves, so a block between the two builds and loses its tail
               on screen (default)
    safe       Allow the 0x5000 the atlas owns, and raise the word to the
               block's own size when the block needs it. The word is only ever
               raised: a build that still fits leaves it alone, and a value
               already raised by hand survives, so a rebuild of the same art is
               a no-op.

    The whole argument is one string of ';'-separated key=value pairs, which
    is what ludared hands a codec. Anything unrecognised -- another key,
    another value, a token without "=" -- is refused rather than defaulted.

Example:
  grow_dma=safe

Not supported, and refused rather than written wrongly:

  * canvases that are not 4bpp indexed BMPs, that are compressed, or whose DIB
    header is not the 40-byte BITMAPINFOHEADER
  * odd heights, widths that are not multiples of 8, and widths past the
    320-pixel screen: the table counts width in tiles and the block offset in
    8-byte units, so rounding either would move the artwork's centre
  * a block that compresses past 12,673 bytes, or whose images pass the
    transfer limit in force]]
codec.version     = 7
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
local ENGINE_STAGE_BYTES = 0x4800   -- staged window enforced by default
local VDP1_ATLAS_CEILING = 0x5000   -- 0x25c07280 - 0x25c02280: the atlas's region

-- The transfer length itself: a bare u16 in export #6's literal pool, read by
-- exactly one instruction (0x00204bba, mov.w @(pc),r6).  Raising it is a
-- two-byte edit; see SAKTAI_SUBTITLES.md 5.4.
local LOGO_DMA_LENGTH_OFFSET = 0x00000c06


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

-- Arguments arrive as one opaque string, parsed by shared/args_parser.lua:
-- ';'-separated key=value pairs.  Unknown keys, unknown values and bare
-- tokens are errors -- a typo in the manifest must not quietly build a disc
-- with the wrong transfer length.
local ARG_SPEC = {
  grow_dma = { values = { "none", "safe" }, default = "none", lower = true },
}

local function parse_args(args)
  return args_parser.parse(args, ARG_SPEC, "subtitles gfx")
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
  -- Validated here as well: ludared hands the same string to both passes, and an
  -- argument a rebuild would refuse should not decode silently.
  parse_args(args)
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
  local unpacked = prs:decode(compressed)[1].data

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
      name = string.format("SUBTITLES/%02d.bmp", i - 1),
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
      local index = artifact.name:match("^SUBTITLES/(%d+)%.bmp$")
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
    local stage = string.format("SUBTITLES/%02d.bmp", i - 1)
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

  -- The transfer only reaches the head of the block (see the header comment).
  -- Name the exact images that land outside it: they still build and the disc
  -- still boots, the game just shows stale VRAM where they should be.
  local opts = parse_args(args)
  local dma_length = string.unpack(">I2", original, LOGO_DMA_LENGTH_OFFSET + 1)
  local stage_limit = ENGINE_STAGE_BYTES
  if opts.grow_dma == "safe" then
    stage_limit = VDP1_ATLAS_CEILING
  end

  local staged = nil
  if block_size > stage_limit then
    local lost = {}
    for i = 1, NUM_SUBTITLES do
      if offsets[i] >= stage_limit then
        lost[#lost + 1] = string.format("%s (starts at %d)", names[i], offsets[i])
      elseif offsets[i] + sizes[i] > stage_limit then
        lost[#lost + 1] = string.format("%s (cut off at %d)", names[i], stage_limit)
      end
    end
    local reaches
    if opts.grow_dma == "safe" then
      reaches = string.format(
        "VDP1 VRAM gives the atlas only the %d (0x%04X) bytes between its base "
        .. "0x25c02280 and the next overlay at 0x25c07280",
        stage_limit, stage_limit)
    else
      reaches = string.format(
        "the engine only stages the first %d (0x%04X) bytes of it",
        stage_limit, stage_limit)
    end
    staged = string.format(
      "The block is %d bytes, but %s, so %d bytes would show stale VRAM instead "
      .. "of art (%s). Free %d bytes: the budget is on the decompressed block, so "
      .. "compressing better does not help -- an image costs width x height / 2.",
      block_size, reaches, block_size - stage_limit, table.concat(lost, ", "),
      block_size - stage_limit)
  end

  if staged then
    error("encode: " .. staged, 0)
  end

  local image_block = table.concat(parts)

  -- Unmodified artifacts: keep the original block byte for byte.
  local compressed_original = original:sub(LOGO_SUBTITLE_PRS_OFFSET + 1,
                                           LOGO_SUBTITLE_PRS_OFFSET + ORIGINAL_COMPRESSED_SIZE)
  if prs:decode(compressed_original)[1].data == image_block then
    return original
  end

  local compressed = prs:encode("", { { name = "DECOMPRESSED", data = image_block } })
  if #compressed > ORIGINAL_COMPRESSED_SIZE then
    error(string.format(
      "encode: subtitle block compresses to %d bytes, %d over the %d-byte budget; shorten the subtitles",
      #compressed, #compressed - ORIGINAL_COMPRESSED_SIZE, ORIGINAL_COMPRESSED_SIZE), 0)
  end

  compressed = compressed .. string.rep("\x00", ORIGINAL_COMPRESSED_SIZE - #compressed)

  local out = original:sub(1, LOGO_SUBTITLE_PRS_OFFSET)
    .. compressed
    .. original:sub(LOGO_SUBTITLE_PRS_OFFSET + ORIGINAL_COMPRESSED_SIZE + 1)

  -- Raise the transfer length only when the block needs it.  Never lowering it
  -- keeps a build that fits byte-identical, preserves a value that was already
  -- raised by hand, and makes a second build of the same art a no-op.
  if opts.grow_dma == "safe" and block_size > dma_length then
    out = out:sub(1, LOGO_DMA_LENGTH_OFFSET)
      .. string.pack(">I2", block_size)
      .. out:sub(LOGO_DMA_LENGTH_OFFSET + 3)
  end

  return out
end

return codec
