--[[
  Sakura Taisen (Saturn) — Font codec for NNNNKNJ.BIN / M##MES.FNT files

  Standalone Lua codec for Ludared.  No external dependencies.

  File format (verified against C++ tool; see SAKTAI_ISO_ARCHITECTURE.md §5):

      Pure tile array, 128 bytes per tile (4bpp, 16x16 pixels)
      No header, no table, no checksums
      File size = num_tiles * 128 bytes

  Palette: external (32 bytes = 16 x 15-bit BGR555)
  - The original game loads palette separately into VRAM
  - For editing, we embed a standard 16-color BGR0 palette in the BMP
  - On encode, we reconstruct the 15-bit Saturn palette

  Glyph page format (new):
  - 16 glyphs per page, 256x16 pixels per BMP page
  - 4bpp indexed BMP
  - 128 bytes per glyph in the original binary

  Target runtime: Lua 5.4+ (uses //, <<, >>, |, &, ~, string.pack/unpack)
]]

-- ---------------------------------------------------------------------------
-- Format constants (defined ONCE)
-- ---------------------------------------------------------------------------

local TILE_DIM_PX   = 16                        -- pixels per tile dimension
local TILES_X       = 16                        -- tiles per row in atlas
local TILE_BYTES    = 128                       -- 16x16 4bpp = 128 bytes per tile (source & BMP)
local NUM_COLORS    = 16                        -- 4bpp = 16 colors
local PALETTE_BYTES = 32                        -- 16 * 2 bytes (BGR555)

local DEFAULT_NAME  = "FONT.bmp"

local FILE_BYTES    = 76736                     -- 629 tiles * 128 bytes (standard title font size)

-- BMP header constants
local BMP_FILE_HEADER  = 14
local BMP_INFO_HEADER  = 40
local BMP_PAL_BYTES    = 16 * 4               -- 64 bytes (16 colors * 4 bytes RGBA)
local BMP_PIXEL_OFF    = 14 + 40 + 64         -- 118
local ROW_BYTES        = 128                  -- 256 pixels at 4bpp = 128 bytes per row

-- Palette conversion: floor(v*255/31 + 0.5)  /  floor(v*31/255 + 0.5)
local function l5to8(v) return (v * 255 + 15) // 31 end
local function l8to5(v) return (v * 31 + 127) // 255 end

-- ---------------------------------------------------------------------------
-- Glyph page tiling
-- ---------------------------------------------------------------------------

local GLYPHS_PER_PAGE = 16
local TILE_DIM_PX   = 16
local TILE_BYTES    = 128
local PAGE_BYTES    = 16 * 128  -- 2048 bytes per page

-- Tiled blob (num_tiles * 128 bytes) -> sequence of glyph page images
-- Each page: 16 glyphs, 256x16 pixels, 4bpp BMP
local function detile_pages(tiled)
  local num_tiles = #tiled // 128
  local num_pages = (num_tiles + 15) // 16
  local pages = {}

  for page_idx = 0, num_pages - 1 do
    local page_tiles = math.min(GLYPHS_PER_PAGE, num_tiles - page_idx * GLYPHS_PER_PAGE)
    local out = {}
    -- Pre-allocate page buffer (16 tiles * 128 bytes = 2048 bytes)
    for i = 1, 2048 do out[i] = 0 end

    for i = 0, page_tiles - 1 do
      local tile_idx = page_idx * GLYPHS_PER_PAGE + i
      local tc = i % GLYPHS_PER_PAGE
      local dst = tc * 8
      for ty = 0, 15 do
        local soff = tile_idx * 128 + 1 + ty * 8
        local doff = ty * 128 + tc * 8
        for tx = 0, 7 do
          out[doff + tx + 1] = tiled:byte(soff + tx)
        end
      end
    end
    pages[page_idx + 1] = string.char(table.unpack(out))
  end
  return pages
end

-- Linear page data (concatenated page data, row 0 = top) -> tiled blob (exact inverse of detile_pages)
-- num_tiles: number of tiles to extract (may be less than full grid)
local function retile(img, num_tiles)
  local out = {}
  for i = 0, num_tiles - 1 do
    local page_idx = i // 16
    local tile_in_page = i % 16
    -- Source in concatenated page data: each page is 2048 bytes
    local src = page_idx * 2048 + tile_in_page * 8
    local base = i * 128
    for ty = 0, 15 do
      local soff = src + ty * 128
      local doff = ty * 8
      for tx = 0, 7 do
        out[base + doff + tx + 1] = img:byte(soff + tx + 1)
      end
    end
  end
  return string.char(table.unpack(out))
end

-- ---------------------------------------------------------------------------
-- BMP construction / parsing
-- ---------------------------------------------------------------------------

local function build_bmp(img, pal_bgra, num_tiles)
  local tiles_high = (num_tiles + 15) // 16
  local total_tiles = tiles_high * 16
  local expected_pixels = total_tiles * 128
  if #img < expected_pixels then
    img = img .. string.rep("\x00", expected_pixels - #img)
  end
  local tiles_high = (num_tiles + 15) // 16
  local hdr = string.pack("<c2I4I2I2I4I4i4i4I2I2I4I4I4I4I4I4",
    "BM", 14 + 40 + 64 + total_tiles * 128, 0, 0, 14 + 40 + 64,
    40, 256, -tiles_high * 16, 1, 4, 0, 0, 0, 0, 16, 0
  )
  return hdr .. pal_bgra .. img:sub(1, expected_pixels)
end

-- Returns pixels (row 0 = top, 4bpp packed, 128 bytes per row), palette byte array (64 entries BGR0 for 16 colors).
local function parse_bmp(bmp, stage)
  if #bmp < 54 then error(stage .. ": BMP too short (" .. #bmp .. " bytes)", 0) end
  if bmp:sub(1, 2) ~= "BM" then error(stage .. ": not a BMP file", 0) end

  local off, infoLen, width, height, planes, bpp, comp =
    string.unpack("<I4I4i4i4I2I2I4", bmp, 11)

  if width ~= 256 then error(stage .. ": width " .. width .. " != 256", 0) end
  if height == 0 then error(stage .. ": height is 0", 0) end
  local h = height
  if h < 0 then h = -h end
  if h % 16 ~= 0 then error(stage .. ": height not multiple of 16", 0) end
  if planes ~= 1 then error(stage .. ": biPlanes != 1", 0) end
  if bpp ~= 4 then error(stage .. ": not 4bpp", 0) end
  if comp ~= 0 then error(stage .. ": compressed BMP", 0) end

  if infoLen < 40 then error(stage .. ": DIB header too small " .. infoLen, 0) end
  if off < 14 + infoLen then error(stage .. ": bfOffBits overlaps header", 0) end
  if #bmp < off + 128 * (h // 16) then error(stage .. ": truncated pixels", 0) end

  local avail = off - (14 + infoLen)

  local pal = {}
  for i = 0, 63 do
    pal[i + 1] = i < avail and bmp:byte(14 + infoLen + 1 + i) or 0
  end

  local px = bmp:sub(off + 1, off + 128 * h)
  if height > 0 then
    -- bottom-up -> top-down (4bpp packed, 128 bytes per row)
    local t = {}
    for y = h - 1, 0, -1 do
      local base = y * 128
      for x = 0, 127 do
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

-- Saturn 32-byte palette -> 64-byte BMP palette (BGR0)
local function sat_palette_to_bmp(data)
  local t = {}
  for i = 0, 15 do
    local c = string.unpack(">I2", data, 1 + i * 2)
    c = c & 0x7FFF
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

-- 64-byte BMP palette -> Saturn 32-byte palette.
-- Bit 15 of each entry is not a colour component and cannot survive in an 8-bit
-- BMP. KNJ files don't embed palettes (the palette is external), so bit 15 is 0.
local function bmp_palette_to_sat(pal)
  local parts = {}
  for i = 0, 15 do
    local o = i * 4
    local b5 = (pal[o + 1] * 31 + 127) // 255
    local g5 = (pal[o + 2] * 31 + 127) // 255
    local r5 = (pal[o + 3] * 31 + 127) // 255
    local v = (b5 << 10) | (g5 << 5) | r5
    parts[i + 1] = string.pack(">I2", v)
  end
  return table.concat(parts)
end

-- ---------------------------------------------------------------------------
-- Artifact naming
-- ---------------------------------------------------------------------------

local function artifact_name(args)
  if type(args) == "string" and #args > 0 then return args end
  return "FONT_00.bmp"
end

local function page_name(index)
  return string.format("FONT_%02X.bmp", index)
end

-- ---------------------------------------------------------------------------
-- Minimal JSON encoder/decoder for metadata
-- ---------------------------------------------------------------------------

local function json_escape(s)
  return s:gsub('[\\"]', '\\%1')
end

local function json_encode_key(val)
  if type(val) == "string" then
    return '"' .. json_escape(val) .. '"'
  elseif type(val) == "number" then
    return tostring(val)
  elseif type(val) == "boolean" then
    return val and "true" or "false"
  else
    error("json_encode_key: unsupported type " .. type(val))
  end
end

local function json_encode(val)
  if type(val) == "string" then
    return '"' .. json_escape(val) .. '"'
  elseif type(val) == "number" then
    return tostring(val)
  elseif type(val) == "boolean" then
    return val and "true" or "false"
  elseif type(val) == "table" then
    local is_array = #val > 0
    local parts = {}
    if is_array then
      for _, v in ipairs(val) do
        parts[#parts + 1] = json_encode(v)
      end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      local parts = {}
      for k, v in pairs(val) do
        parts[#parts + 1] = json_encode_key(k) .. ':' .. json_encode(v)
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  elseif val == nil then
    return "null"
  end
  error("json_encode: unsupported type " .. type(val))
end

local function json_decode(s)
  local i = 1
  local function skip_ws()
    while i <= #s and s:sub(i,i):match("%s") do i = i + 1 end
  end
  local function parse_val()
    skip_ws()
    local c = s:sub(i,i)
    if c == '"' then
      i = i + 1
      local start = i
      while i <= #s and s:sub(i,i) ~= '"' do
        if s:sub(i,i) == '\\' then i = i + 2 else i = i + 1 end
      end
      local str = s:sub(start, i-1)
      i = i + 1
      return str
    elseif c == '{' then
      i = i + 1
      local obj = {}
      while true do
        skip_ws()
        if s:sub(i,i) == '}' then i = i + 1 return obj end
        local key = parse_val()
        skip_ws()
        if s:sub(i,i) ~= ':' then error("expected :") end
        i = i + 1
        obj[key] = parse_val()
        skip_ws()
        if s:sub(i,i) == '}' then i = i + 1 return obj end
        if s:sub(i,i) ~= ',' then error("expected ,") end
        i = i + 1
      end
    elseif c == '[' then
      i = i + 1
      local arr = {}
      while true do
        skip_ws()
        if s:sub(i,i) == ']' then i = i + 1 return arr end
        arr[#arr + 1] = parse_val()
        skip_ws()
        if s:sub(i,i) == ']' then i = i + 1 return arr end
        if s:sub(i,i) ~= ',' then error("expected ,") end
        i = i + 1
      end
    elseif c == 't' then
      if s:sub(i,i+3) == 'true' then i = i + 4 return true end
    elseif c == 'f' then
      if s:sub(i,i+4) == 'false' then i = i + 5 return false end
    elseif c == 'n' then
      if s:sub(i,i+3) == 'null' then i = i + 4 return nil end
    elseif c:match('[%d%-]') then
      local start = i
      while i <= #s and s:sub(i,i):match('[%d%.%-eE]') do i = i + 1 end
      return tonumber(s:sub(start, i-1))
    end
    error("unexpected char at " .. i)
  end
  i = 1
  skip_ws()
  local val = parse_val()
  skip_ws()
  if i <= #s then error("trailing garbage") end
  return val
end

local function encode_metadata(metadata)
  return json_encode(metadata)
end

local function decode_metadata(data)
  return json_decode(data)
end

-- ---------------------------------------------------------------------------
-- Standard Sakura Taisen font palette (BGR555, 32 bytes)
-- From MainMenuFontPalette.bin, OptionsFontPalette.bin, BattleTextPalette.bin
-- Used by the C++ tool for visualization
local function build_standard_font_palette()
  -- 16-color BGR555: 7F FF 08 42 10 84 18 C6 21 08 29 4A 31 8C 39 CE 42 10 4A 52 52 94 5A D6 63 18 6B 5A 73 9C 7F FF
  local parts = {}
  parts[1] = string.pack(">I2", 0x7FFF)
  parts[2] = string.pack(">I2", 0x0842)
  parts[3] = string.pack(">I2", 0x1084)
  parts[4] = string.pack(">I2", 0x18C6)
  parts[5] = string.pack(">I2", 0x2108)
  parts[6] = string.pack(">I2", 0x294A)
  parts[7] = string.pack(">I2", 0x318C)
  parts[8] = string.pack(">I2", 0x39CE)
  parts[9] = string.pack(">I2", 0x4210)
  parts[10] = string.pack(">I2", 0x4A52)
  parts[11] = string.pack(">I2", 0x5294)
  parts[12] = string.pack(">I2", 0x5AD6)
  parts[13] = string.pack(">I2", 0x6318)
  parts[14] = string.pack(">I2", 0x6B5A)
  parts[15] = string.pack(">I2", 0x739C)
  parts[16] = string.pack(">I2", 0x7FFF)
  return table.concat(parts)
end

local DEFAULT_FONT_PALETTE_SAT = build_standard_font_palette()
local DEFAULT_FONT_PALETTE_BMP = sat_palette_to_bmp(DEFAULT_FONT_PALETTE_SAT)

-- ---------------------------------------------------------------------------
-- Codec
-- ---------------------------------------------------------------------------

local codec = {}

codec.name        = "Sakura Taisen Font (Deprecated)"
codec.description = [[
Deprecated. Kept for inspecting Sakura Taisen font files.

Decodes NNNNKNJ.BIN / M##MES.FNT into editable indexed BMP glyph pages.
Not used by the translation pipeline.
]]
codec.version     = 1
codec.kind        = "rebuild"

function codec.can_handle(data)
  if type(data) ~= "string" then return "no" end
  -- KNJ/MES.FNT are pure tile arrays: file size must be multiple of 128 bytes
  if #data % 128 ~= 0 then return "no" end
  if #data < 128 then return "no" end
  if #data > 1024 * 128 then return "no" end
  return "likely"
end

function codec.decode_name(args)
  if type(args) == "string" and #args > 0 then return args end
  return "FONT_00.bmp"
end

function codec.decode(data, args)
  if type(data) ~= "string" then error("decode: expected binary string", 0) end
  if #data % 128 ~= 0 then error("decode: file size not multiple of 128", 0) end
  if #data < 128 then error("decode: file too small", 0) end
  if #data > 1024 * 128 then error("decode: file too large (>1024 tiles)", 0) end

  -- KNJ/MES.FNT have no embedded palette; use standard font palette for BMP visualization
  local bmp_palette = DEFAULT_FONT_PALETTE_BMP

  local tile_data = data
  local pages = detile_pages(tile_data)
  local artifacts = {}

  for i, page_img in ipairs(pages) do
    local tiles_this_page = math.min(16, (#tile_data // 128) - (i-1)*16)
    local bmp = build_bmp(page_img, bmp_palette, tiles_this_page)
    artifacts[#artifacts + 1] = { name = page_name(i-1), data = bmp }
  end

  -- Metadata artifact (includes BMP palette for roundtrip)
  local metadata = {
    glyph_pages = {},
    tile_count = #tile_data // 128,
    palette_hex = bmp_palette:gsub(".", function(c) return string.format("%02X", c:byte()) end)
  }
  for i = 1, #artifacts do
    metadata.glyph_pages[i] = artifacts[i].name
  end

  local meta_data = encode_metadata(metadata)
  artifacts[#artifacts + 1] = { name = "font.meta.json", data = meta_data }

  return artifacts
end

function codec.encode(original, artifacts, args)
  if type(original) ~= "string" then error("encode: expected binary string for `original`", 0) end
  if #original % 128 ~= 0 then error("encode: `original` size not multiple of 128", 0) end
  if type(artifacts) ~= "table" or #artifacts == 0 then error("encode: no artifacts supplied", 0) end

  -- Find metadata artifact
  local meta = nil
  for i = 1, #artifacts do
    local a = artifacts[i]
    if a.name == "font.meta.json" then
      meta = decode_metadata(a.data)
      break
    end
  end

  if not meta then error("encode: no metadata artifact found", 0) end
  if #meta.glyph_pages == 0 then error("encode: no glyph pages specified", 0) end

  local num_tiles = #original // 128

  -- Build image from glyph pages in metadata order
  local img_parts = {}
  for _, page_name in ipairs(meta.glyph_pages) do
    local page_data = nil
    for _, a in ipairs(artifacts) do
      if a.name == page_name then
        page_data = a.data
        break
      end
    end
    if not page_data then error("encode: missing glyph page '" .. page_name .. "'", 0) end
    local px, _ = parse_bmp(page_data, "encode")
    table.insert(img_parts, px)
  end

  -- Concatenate all page pixel data
  local img = table.concat(img_parts)
  local tiles_high = (num_tiles + 15) // 16
  local expected_pixels = tiles_high * 16 * 128
  if #img < expected_pixels then
    img = img .. string.rep("\x00", expected_pixels - #img)
  end

  -- Convert palette from metadata back to Saturn format
  local pal_bin = meta.palette_hex:gsub("(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
  local pal_tbl = {}
  for i = 1, 64 do
    pal_tbl[i] = pal_bin:byte(i)
  end
  local satPal = bmp_palette_to_sat(pal_tbl)

  -- Retile back to linear tiles
  local tiled = retile(img, num_tiles)

  if #tiled ~= num_tiles * 128 then error("encode: retiled " .. #tiled .. " bytes, expected " .. (num_tiles * 128), 0) end

  -- KNJ/MES.FNT have no embedded palette; return pure tile data
  return tiled
end

return codec