--[[
  Sakura Taisen (Saturn) — TITLE{x}.bin  <->  indexed BMP  <->  TITLE{x}.bin

  Standalone Lua codec for Ludared.  No external dependencies.

  File layout (verified against the C++ tool; see TITLE_CODEC_NOTES.md):

      0x0000 .. 0x01FF   512 bytes   256 x u16 big-endian BGR555 palette
      0x0200 .. 0x13BF  4544 bytes  opaque, preserved verbatim
      0x13C0 .. EOF     71680 bytes 1120 tiles of 8x8 8bpp, raster order
                                  (tile 0 = top-left; byte row 0 = TOP of the
                                  tile band; row-major within a tile)
                                  Total 76736 bytes.

  The 0x0200 region is never interpreted.  It is copied from `original` on
  encode, which is what makes `encode(original, decode(original)) == original`
  hold byte for byte.

  Pixel geometry and palette channel order were confirmed empirically against
  the shipped Data/Screens/TITLE*.bmp and Data/LoadBgrPalette.bin.

  Target runtime: Lua 5.4+ (uses //, <<, >>, |, &, ~, string.pack/unpack).
]]

-- ---------------------------------------------------------------------------
-- Format constants (defined ONCE)
-- ---------------------------------------------------------------------------

local TILE_DIM      = 8
local WIDTH         = 320
local HEIGHT        = 224
local TILES_X       = 40                        -- WIDTH  / TILE_DIM
local TILES_Y       = 28                        -- HEIGHT / TILE_DIM
local TILE_BYTES    = TILE_DIM * TILE_DIM       -- 64
local PIXEL_BYTES   = WIDTH * HEIGHT            -- 71680
local NUM_COLORS    = 256

local PALETTE_BYTES = NUM_COLORS * 2            -- 512
local REGION_OFF    = 0x0200                    -- opaque region starts here
local TILES_OFF     = 0x13C0                    -- tile data starts here
local FILE_BYTES    = TILES_OFF + PIXEL_BYTES   -- 76736

local DEFAULT_NAME  = "TITLE.bmp"

-- BMP header constants
local BMP_FILE_HEADER  = 14
local BMP_INFO_HEADER  = 40
local BMP_PAL_BYTES    = 256 * 4                -- 1024
local BMP_PIXEL_OFF    = BMP_FILE_HEADER + BMP_INFO_HEADER + BMP_PAL_BYTES  -- 1078
local BMP_TOTAL        = BMP_PIXEL_OFF + PIXEL_BYTES                          -- 72758

-- ---------------------------------------------------------------------------
-- Tiling
--
-- Tile order: raster over 40x28 grid, tile 0 = top-left.
-- Within a tile: byte row 0 = TOP row, bytes row-major.
-- Verified against shipped BMPs: top-first gives better vertical continuity.
-- ---------------------------------------------------------------------------

-- Tiled blob (1120 * 64 bytes) -> WIDTH*HEIGHT linear image, row 0 = top.
local function detile(tiled)
  local out = {}
  local src = 1
  for i = 0, TILES_X * TILES_Y - 1 do
    local tr = i // TILES_X
    local tc = i % TILES_X
    local dst = tr * TILE_DIM * WIDTH + tc * TILE_DIM
    for ty = 0, TILE_DIM - 1 do
      local soff = src + ty * TILE_DIM
      local doff = dst + ty * WIDTH
      for tx = 0, TILE_DIM - 1 do
        out[doff + tx + 1] = tiled:byte(soff + tx)
      end
    end
    src = src + TILE_BYTES
  end
  return string.char(table.unpack(out))
end

-- Linear image (row 0 = top) -> tiled blob (exact inverse of detile)
local function retile(img)
  local out = {}
  for i = 0, TILES_X * TILES_Y - 1 do
    local tr = i // TILES_X
    local tc = i % TILES_X
    local src = tr * TILE_DIM * WIDTH + tc * TILE_DIM + 1
    local base = i * TILE_BYTES
    for ty = 0, TILE_DIM - 1 do
      local soff = src + ty * WIDTH
      local doff = ty * TILE_DIM
      for tx = 0, TILE_DIM - 1 do
        out[base + doff + tx + 1] = img:byte(soff + tx)
      end
    end
  end
  return string.char(table.unpack(out))
end

-- ---------------------------------------------------------------------------
-- BMP construction / parsing
-- ---------------------------------------------------------------------------

local function build_bmp(img, pal_bgra)
  return string.pack("<c2I4I2I2I4I4i4i4I2I2I4I4I4I4I4I4",
    "BM", BMP_TOTAL, 0, 0, BMP_PIXEL_OFF,
    BMP_INFO_HEADER, WIDTH, -HEIGHT, 1, 8, 0, 0, 0, 0, NUM_COLORS, 0
  ) .. pal_bgra .. img
end

-- Returns pixels (row 0 = top), palette byte array (1024 entries BGR0).
local function parse_bmp(bmp, stage)
  if #bmp < 54 then error(stage .. ": BMP too short (" .. #bmp .. " bytes)", 0) end
  if bmp:sub(1, 2) ~= "BM" then error(stage .. ": not a BMP file", 0) end

  local off, infoLen, width, height, planes, bpp, comp =
    string.unpack("<I4I4i4i4I2I2I4", bmp, 11)

  if width ~= WIDTH then error(stage .. ": width " .. width .. " != " .. WIDTH, 0) end
  if height ~= HEIGHT and height ~= -HEIGHT then error(stage .. ": height " .. height, 0) end
  if planes ~= 1 then error(stage .. ": biPlanes != 1", 0) end
  if bpp ~= 8 then error(stage .. ": not 8bpp", 0) end
  if comp ~= 0 then error(stage .. ": compressed BMP", 0) end

  if infoLen < 40 then error(stage .. ": DIB header too small " .. infoLen, 0) end
  if off < 14 + infoLen then error(stage .. ": bfOffBits overlaps header", 0) end
  if #bmp < off + PIXEL_BYTES then error(stage .. ": truncated pixels", 0) end

  local avail = off - (14 + infoLen)

  local pal = {}
  for i = 0, 1023 do
    pal[i + 1] = i < avail and bmp:byte(14 + infoLen + 1 + i) or 0
  end

  local px = bmp:sub(off + 1, off + PIXEL_BYTES)
  if height > 0 then
    -- bottom-up -> top-down
    local t = {}
    for y = HEIGHT - 1, 0, -1 do
      local base = y * WIDTH
      for x = 0, WIDTH - 1 do
        t[#t + 1] = px:byte(base + x + 1)
      end
    end
    px = string.char(table.unpack(t))
  end
  return px, pal
end

-- ---------------------------------------------------------------------------
-- Palette (re)serialisation
-- ---------------------------------------------------------------------------

-- Saturn 512-byte palette -> 1024-byte BMP palette (BGR0)
local function sat_palette_to_bmp(data)
  local t = {}
  for i = 0, NUM_COLORS - 1 do
    local c = string.unpack(">I2", data, 1 + i * 2)
    c = c & 0x7FFF  -- mask bit 15 (not a color bit)
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

-- 1024-byte BMP palette -> Saturn 512-byte palette.
-- Bit 15 of each entry is not a colour component and cannot survive in an 8-bit
-- BMP, so it is inherited from `original`.  That keeps the round-trip exact for
-- any input.  (The observed Data/TitlePalette.bin has bit 15 clear in all 256
-- entries, so this is defensive rather than load-bearing.)
local function bmp_palette_to_sat(pal, original)
  local parts = {}
  for i = 0, NUM_COLORS - 1 do
    local o = i * 4
    local b5 = (pal[o + 1] * 31 + 127) // 255
    local g5 = (pal[o + 2] * 31 + 127) // 255
    local r5 = (pal[o + 3] * 31 + 127) // 255
    local v = (b5 << 10) | (g5 << 5) | r5
    local orig = string.unpack(">I2", original, 1 + i * 2)
    if orig >= 32768 then v = v | 0x8000 end
    parts[i + 1] = string.pack(">I2", v)
  end
  return table.concat(parts)
end

-- ---------------------------------------------------------------------------
-- Artifact naming
-- ---------------------------------------------------------------------------

local function artifact_name(args)
  if type(args) == "string" and #args > 0 then return args end
  return DEFAULT_NAME
end

-- ---------------------------------------------------------------------------
-- Codec
-- ---------------------------------------------------------------------------

local codec = {}

codec.name        = "Sakura Taisen Title Screen"
codec.description = "Sakura Taisen (Saturn) TITLE{x}.bin: 256-entry BGR555 palette, " ..
                    "an opaque 4544-byte region, and 1120 8x8 8bpp tiles " ..
                    "covering 320x224. Decodes to an editable indexed BMP."
codec.version     = 1
codec.kind        = "patch"

function codec.can_handle(data)
  if type(data) ~= "string" then return "no" end
  if #data ~= FILE_BYTES then return "no" end
  return "possible"
end

function codec.decode_name(args)
  return artifact_name(args)
end

function codec.decode(data, args)
  if type(data) ~= "string" then error("decode: expected binary string", 0) end
  if #data ~= FILE_BYTES then error("decode: file is " .. #data .. " bytes, expected " .. FILE_BYTES, 0) end

  local pal  = sat_palette_to_bmp(data)
  local img  = detile(data:sub(TILES_OFF + 1))
  local bmp  = build_bmp(img, pal)

  return { { name = artifact_name(args), data = bmp } }
end

function codec.encode(original, artifacts, args)
  if type(original) ~= "string" then error("encode: expected binary string for `original`", 0) end
  if #original ~= FILE_BYTES then error("encode: `original` is " .. #original .. " bytes, expected " .. FILE_BYTES, 0) end
  if type(artifacts) ~= "table" or #artifacts == 0 then error("encode: no artifacts supplied", 0) end

  local want = artifact_name(args)
  local bmp = nil

  for i = 1, #artifacts do
    local a = artifacts[i]
    if a.name == want then bmp = a.data; break end
  end
  if not bmp then
    for i = 1, #artifacts do
      local a = artifacts[i]
      if type(a.name) == "string" and a.name:lower():match("%.bmp$") then
        bmp = a.data; break
      end
    end
  end
  if not bmp and #artifacts == 1 then bmp = artifacts[1].data end
  if not bmp then error("encode: no BMP artifact found (wanted '" .. want .. "')", 0) end
  if type(bmp) ~= "string" then error("encode: BMP artifact data is " .. type(bmp), 0) end

  -- Use shared parse_bmp helper
  local px, pal = parse_bmp(bmp, "encode")

  -- Use shared palette conversion helper
  local satPal = bmp_palette_to_sat(pal, original)

  -- Use shared retile helper
  local tiled = retile(px)

  if #tiled ~= PIXEL_BYTES then error("encode: retiled " .. #tiled .. " bytes, expected " .. PIXEL_BYTES, 0) end

  return satPal .. original:sub(REGION_OFF + 1, TILES_OFF) .. tiled
end

return codec