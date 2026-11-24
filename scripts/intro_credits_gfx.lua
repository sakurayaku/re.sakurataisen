--[[
  Sakura Taisen (Saturn) — intro credits and logo screens

  PATCH codec for SAKURA1/LOGO.SH2.

  SakuraTaisen.cpp: PatchTiledData (11606), PatchIntroCredits (11676).

  Four PRS blocks, each in a fixed slot:

      0x032EDC  slot 6,889   credits tiles, flat 8x8 4bpp list (311 retail)
      0x0349C8  slot   916   credits tile map, 1,120 big-endian u32
      0x035924  slot   777   logo tiles,    flat 8x8 4bpp list (55 retail)
      0x035C30  slot   208   logo tile map, 1,120 big-endian u32

  ## Two artifacts, both screens

  decode() hands back only the two 320x224 screens the game draws
  (CREDITS.bmp and LOGO.bmp), each with a 16-colour neutral ramp:
  the real palette lives outside these blocks, so only pixel indices round-trip.
  The game reads these tiles through the 16-entry CRAM ramp at LOGO.SH2+0x3216E,
  black 0x0000 to white 0x7FFF, whose entry 0 is transparent (the backdrop shows
  through).  Index 15 is therefore pure white: art painted at 15 alone vanishes
  over a bright backdrop, which is why the retail glyphs carry a full 0..15
  ramp.  Keep a dark outline (index 1) around light ink.

  The tile maps are NOT artifacts.  They are placement, and placement can be
  rebuilt: the retail maps are exactly "deduplicate the screen's 8x8 cells in
  screen order", so a map regenerated from the picture reproduces the retail
  file byte for byte.  Layout of the stored map if you ever need to read it:
  40 x 28 cells of 8x8 pixels covering the 320x224 screen, row-major from the
  top row, one big-endian u32 per cell whose low 31 bits are the tile index.
  Bit 31 is a flag, not an index: the retail logo map sets it on exactly one
  cell (row 15, column 14, word 0x80000004).  Its meaning is undocumented, so
  encode() carries it over to the same cell and leaves it alone.

  ## Editing

  Paint the screen.  Anything is writable, including the empty area: encode()
  cuts the picture into 8x8 cells in screen order, gives each distinct cell the
  next tile index on first appearance, and builds the map from that.  Blank
  cells therefore all share one blank tile, repeated shapes share a tile, and a
  new unique cell simply becomes a new tile.  Nothing has to be kept in sync by
  hand, and a screen that was not edited re-encodes to the original bytes.

  The tile list may grow past the retail 311 / 55 tiles (up to 1,120 cells).
  What is fixed is each block's compressed slot, above: the stream is
  compressed with the project PRS encoder, must fit the slot (an oversized
  block is refused), and is zero padded to it, as the C++ does.  Unchanged
  blocks are copied verbatim, so the gaps between the four blocks and the rest
  of LOGO.SH2 are preserved, and a block is only rewritten when its content
  changes - a retouched glyph keeps the tile map untouched.

  Headroom at retail, with this encoder: credits tiles 6,885 of 6,889 bytes,
  credits map 884 of 916, logo tiles 768 of 777.  The logo map is 210 bytes for
  its retail content, two over its 208-byte slot, so it can only be written
  when the map itself changes; the block is skipped otherwise.

  Growing the decompressed tile list beyond retail has not been checked in game;
  the original tool only ever bounded the compressed size.
]]

local bmp = dofile(LUDARED.SCRIPTS .. "/shared/bmp.lua")
local palettes = dofile(LUDARED.SCRIPTS .. "/shared/palettes.lua")
local prs = LUDARED.codec("std/sega/compression/prs")

local can_handle = dofile(LUDARED.SCRIPTS .. "/shared/can_handle.lua")

local codec = {}

codec.name        = "Sakura Taisen Intro Credits & Logo"
codec.description = "Patches the intro-credit and logo screens in SAKURA1/LOGO.SH2"
codec.version     = 5
codec.kind        = "patch"

local TILE         = 8
local TILE_ROW     = TILE // 2             -- 4 bytes per tile row at 4bpp
local TILE_BYTES   = TILE * TILE_ROW       -- 32 bytes per tile
local COLS         = 40                    -- 320 / 8
local ROWS         = 28                    -- 224 / 8
local WIDTH        = COLS * TILE           -- 320
local HEIGHT       = ROWS * TILE           -- 224
local ROW_BYTES    = WIDTH // 2            -- 160 bytes per screen row
local SCREEN_BYTES = ROW_BYTES * HEIGHT    -- 35,840
local CELLS        = COLS * ROWS           -- 1,120 map entries
local LUT_BYTES    = CELLS * 4             -- 4,480
local INDEX_MASK   = 0x7FFFFFFF            -- bit 31 is a flag, not an index
local FLAG_BIT     = 0x80000000

local BLOCKS = {
  { key = "credits_tiles", offset = 0x032EDC, slot = 6889 },
  { key = "credits_map",   offset = 0x0349C8, slot = 916 },
  { key = "logo_tiles",    offset = 0x035924, slot = 777 },
  { key = "logo_map",      offset = 0x035C30, slot = 208 },
}

local SCREENS = {
  { tiles = "credits_tiles", map = "credits_map", name = "CREDITS.bmp" },
  { tiles = "logo_tiles",    map = "logo_map",    name = "LOGO.bmp" },
}

-- The same display palette the other 16-colour BMP codecs use: the ADV ramp
-- with index 15 forced red.  Encode reads pixel indices only.
local DISPLAY_PALETTE = bmp.from_bgr555(palettes.raw("adv_dialogue_jp_for_bmp"), 16)

codec.DISPLAY_PALETTE = DISPLAY_PALETTE

local function prefix(args)
  local value
  if type(args) == "table" then value = args.prefix else value = args end
  if not value or value == "" then value = "INTRO_CREDITS" end
  return (value:gsub("/+$", ""))
end

local function find_blocks(data)
  if type(data) ~= "string" then
    error("intro_credits: expected a binary string", 0)
  end
  local last = BLOCKS[#BLOCKS]
  if #data < last.offset + last.slot then
    error("intro_credits: input LOGO.SH2 is too short", 0)
  end

  local out = {}
  for _, block in ipairs(BLOCKS) do
    local decompressed =
      prs:decode(data:sub(block.offset + 1, block.offset + block.slot))[1].data
    out[block.key] = decompressed
  end
  return out
end

local function check_blocks(blocks)
  for _, screen in ipairs(SCREENS) do
    local tiles = blocks[screen.tiles]
    if #tiles == 0 or #tiles % TILE_BYTES ~= 0 then
      error(string.format("intro_credits: %s is not a whole number of 8x8 tiles",
        screen.tiles), 0)
    end
    local map = blocks[screen.map]
    if #map ~= LUT_BYTES then
      error(string.format("intro_credits: %s decompresses to %d bytes, expected %d",
        screen.map, #map, LUT_BYTES), 0)
    end
  end
end

local function cell_word(map, cell)
  return string.unpack(">I4", map, cell * 4 + 1)
end

local function check_index(index, tile_count, cell)
  if index >= tile_count then
    error(string.format(
      "intro_credits: tile map cell (%d, %d) references tile %d, but the tile block has %d",
      cell % COLS, cell // COLS, index, tile_count), 0)
  end
end

-- The whole 320x224 screen: every cell shows the tile its map word names.
local function compose(tiles, map)
  local tile_count = #tiles // TILE_BYTES
  local rows = {}
  for y = 1, HEIGHT do rows[y] = string.rep("\0", ROW_BYTES) end

  for cell = 0, CELLS - 1 do
    local index = cell_word(map, cell) & INDEX_MASK
    check_index(index, tile_count, cell)

    local left = (cell % COLS) * TILE_ROW
    local top = (cell // COLS) * TILE
    local base = index * TILE_BYTES
    for inner = 0, TILE - 1 do
      local row = top + inner + 1
      local source = base + inner * TILE_ROW + 1
      rows[row] = rows[row]:sub(1, left)
        .. tiles:sub(source, source + TILE_ROW - 1)
        .. rows[row]:sub(left + TILE_ROW + 1)
    end
  end

  return table.concat(rows)
end

-- The 32 tile bytes one screen cell shows.
local function cell_tile(pixels, cell)
  local left = (cell % COLS) * TILE_ROW + 1
  local top = (cell // COLS) * TILE
  local parts = {}
  for inner = 0, TILE - 1 do
    local start = (top + inner) * ROW_BYTES + left
    parts[#parts + 1] = pixels:sub(start, start + TILE_ROW - 1)
  end
  return table.concat(parts)
end

-- Cut the screen into 8x8 cells and deduplicate them in screen order, the order
-- the retail blocks use.  `flag_map` keeps bit 31 on the cells that had it, so
-- the undocumented flag survives an edit.
local function pack_screen(pixels, flag_map)
  if type(pixels) ~= "string" or #pixels ~= SCREEN_BYTES then
    error("intro_credits: screen has an unexpected size", 0)
  end

  local flagged = {}
  for cell = 0, CELLS - 1 do
    if cell_word(flag_map, cell) & FLAG_BIT ~= 0 then flagged[cell] = true end
  end

  local index_of = {}
  local tiles = {}
  local words = {}
  for cell = 0, CELLS - 1 do
    local data = cell_tile(pixels, cell)
    local index = index_of[data]
    if not index then
      index = #tiles
      tiles[#tiles + 1] = data
      index_of[data] = index
    end
    words[#words + 1] = string.pack(">I4", index | (flagged[cell] and FLAG_BIT or 0))
  end

  return table.concat(tiles), table.concat(words)
end

function codec.can_handle(data)
  return can_handle.can_handle_logo_sh2(data)
end

function codec.decode_name(args)
  return (prefix(args))
end

function codec.decode(data, args)
  local blocks = find_blocks(data)
  check_blocks(blocks)
  local dir = prefix(args)

  local artifacts = {}
  for _, screen in ipairs(SCREENS) do
    local pixels = compose(blocks[screen.tiles], blocks[screen.map])
    artifacts[#artifacts + 1] = {
      name = dir .. "/" .. screen.name,
      data = bmp.build(pixels, WIDTH, HEIGHT, 4, DISPLAY_PALETTE),
    }
  end

  return artifacts
end

function codec.encode(original, artifacts, args)
  local blocks = find_blocks(original)
  check_blocks(blocks)
  local dir = prefix(args)

  local by_name = {}
  for _, artifact in ipairs(artifacts or {}) do
    by_name[artifact.name] = artifact.data
  end

  -- Pack every screen that was supplied; a screen left out of the artifact
  -- list, or supplied unchanged, leaves its blocks untouched.
  local replacements = {}
  for _, screen in ipairs(SCREENS) do
    local picture = by_name[dir .. "/" .. screen.name]
    if picture then
      local pixels = bmp.parse(picture, WIDTH, HEIGHT, 4)
      local tiles, map = pack_screen(pixels, blocks[screen.map])
      if tiles ~= blocks[screen.tiles] then
        replacements[screen.tiles] = tiles
        replacements[screen.map] = map
      end
    end
  end

  local out = original
  for _, block in ipairs(BLOCKS) do
    local replacement = replacements[block.key]
    if replacement and replacement ~= blocks[block.key] then
      local compressed = prs:encode("", { { name = block.key, data = replacement } })
      if #compressed > block.slot then
        error(string.format("intro_credits: compressed %s is %d bytes, exceeds slot %d",
          block.key, #compressed, block.slot), 0)
      end
      compressed = compressed .. string.rep("\0", block.slot - #compressed)
      out = out:sub(1, block.offset) .. compressed
        .. out:sub(block.offset + block.slot + 1)
    end
  end

  return out
end

return codec
