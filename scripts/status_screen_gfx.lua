--[[
  Sakura Taisen (Saturn) — status screen graphics

  PATCH codec for SAKURA1/ICATALL.DAT.

  SakuraTaisen.cpp: ExtractStatusScreen 1664, PatchStatusScreen 10654.

  Two independent PRS blocks:

      0x008800  21,967-byte slot -> 55,296 bytes
                144 x 384, 8bpp linear background

      0x013800   2,522-byte slot -> 6,144 bytes
                48 x 128-byte 16x16 4bpp font tiles

  ## Palettes

  The background palette ships inside ICATALL.DAT, uncompressed at 0x014800
  (512 bytes, 256 colours), and the game uploads it at run time -- which is why
  the reference keeps a copy as StatusScreenPalette.bin and never writes it
  back.  decode reads it from the file, so STATUS_BG.bmp is coloured the way the
  game draws it.  It is display-only: encode never writes a palette, and only
  pixel indices round-trip.  `args` can still override it (bg_palette, or
  bg_palette_path).

  The label canvases use adv_dialogue_jp_for_bmp (adv_dialogue_jp with index 15
  red), the same display palette the other 16-colour BMP codecs use.  The
  status screen's own 16-colour ramp at 0x013000 is a white-to-shadow gradient
  the retail Japanese glyphs are shaded against; over translated art it reads as
  pale on pale, and an artist cannot see what they are drawing.  The sprites
  still *display* through the in-file ramp; only the editor palette changes.

  Index 15 is the red marker: the retail art uses indices 0..14, so red marks
  ink that should not be there.

  ## Labels

  The screen's fifteen labels are not part of the font sheet's meaning: the
  strings in the SAKURA executable are lists of glyph indices, so the retail
  sheet holds the Japanese characters those strings name.  A translation cannot
  use those glyphs, so this codec exposes what the reference's translated build
  actually ships -- whole sentences, one label per row, plus the digits:

      STATUS_NAMES.bmp    labels 1..6     Sakura, Sumire, Kohran, Kanna, Maria, Iris
      STATUS_MOODS.bmp    labels 7..12    High, Spirits, Normal, Mood, Terrible, Mood
      STATUS_STATS.bmp    labels 13..15   Attack, Defense, Movement   (two cells each)
      STATUS_DIGITS.bmp   0..9            one digit per row

  Every row is 16 pixels high and one 16x16 cell per glyph, drawn left to right;
  a group is as wide as its widest row and the shorter rows are padded with
  index 0.  The encoder cuts each row into cells, de-duplicates them and
  rebuilds the sheet, exactly as the load-screen codec does for its labels.

  The stats rows are exactly two cells: scripts/SAKURA/status_screen_metadata.lua
  patches the stats formatter to read both glyph bytes with one `mov.w`, so a
  one-cell row would read its terminator as the second glyph and a third cell
  would be cropped.

  ## The sheet is derived

  There is no sheet artifact.  The sheet is entirely a function of the four
  canvases, so it is rebuilt from them; the retail tiles they do not reference
  are dropped with the Japanese text they belonged to.  After the labels the
  atlas appends the cells the stats formatter needs: retail tile 37 (its padding
  glyph), tile 38 (the separator), the ten digits, and an empty cell the
  formatter's fixed line fill points at.  A build with no canvas edits writes
  nothing at all.

  The atlas is shared with scripts/SAKURA/status_screen_metadata.lua, which
  rewrites the index lists; both use scripts/shared/status_labels.lua, so the
  same canvases always produce the same sheet and the same strings.  The two
  codecs belong to different files and both have to run: the sheet without the
  strings would renumber every glyph the strings point at.

  ## Budgets

  The sheet must compress into the 2,522-byte slot and the background into
  21,967 bytes; both are checked and reported with their sizes, because an
  atlas a few dozen bytes too large makes the edit impossible even though the
  pixels are valid.  The retail sheet is 48 tiles (6,144 bytes) and that is the
  only size the game is known to load; scripts/shared/status_labels.lua allows
  growth to 96 tiles as a margin, which a build has to be checked in an emulator.

  The labels also share the 140-byte index area in SAKURA, which now has to hold
  the two-glyph stats strings, the padding and separator slots and the ten-digit
  table; status_screen_metadata.lua writes one byte per glyph into it and
  enforces the budget, reporting what is over.

  Patching recompresses only the blocks that changed.  The gap between the two
  slots, the palettes, the text data, and every other byte of ICATALL.DAT are
  preserved.

  ICATALL.DAT is byte-identical on both discs, so the shared constants pin the
  one retail file by SHA-256 (AGENTS.md: retail codecs detect through
  scripts/shared/can_handle.lua, never by structure alone).  A rebuilt file is
  therefore rejected by can_handle but still decodes.
]]

local bmp = dofile(LUDARED.SCRIPTS .. "/shared/bmp.lua")
local can_handle = dofile(LUDARED.SCRIPTS .. "/shared/can_handle.lua")
local labels = dofile(LUDARED.SCRIPTS .. "/shared/status_labels.lua")
local palettes = dofile(LUDARED.SCRIPTS .. "/shared/palettes.lua")
local prs = LUDARED.codec("std/sega/compression/prs")

local codec = {}

codec.name        = "Sakura Taisen Status Screen Graphics"
codec.description = "Patches the 144x384 background and rebuilds the label sheet in SAKURA1/ICATALL.DAT"
codec.version     = 11
codec.kind        = "patch"

local BG_OFFSET    = 0x008800
local BG_SLOT      = 21967
local BG_SIZE      = 55296
local BG_WIDTH     = 144
local BG_HEIGHT    = 384

local FONT_OFFSET  = 0x013800
local FONT_SLOT    = 2522
local TILE_SIZE    = 128

local BG_PALETTE   = 0x014800
local BG_PALETTE_BYTES = 512

-- The retail sheet is 48 128-byte tiles; a build may grow it within the
-- shared margin (see status_labels.lua).
local RETAIL_TILES = labels.RETAIL_TILES

local function read_file(path)
  local file = io.open(path, "rb")
  if not file then error("status_screen: cannot read " .. path, 0) end
  local data = file:read("*a")
  file:close()
  return data
end

local function prefix(args)
  local value
  if type(args) == "table" then value = args.prefix else value = args end
  if not value or value == "" then value = "STATUS" end
  return (value:gsub("/+$", ""))
end

local function palette_arg(args, key, path_key, bytes, colors)
  if type(args) ~= "table" then return nil end
  local raw = args[key]
  if not raw and type(args[path_key]) == "string" then
    raw = read_file(args[path_key])
  end
  if not raw then return nil end
  if type(raw) ~= "string" or #raw < bytes then
    error(string.format("status_screen: %s needs at least %d bytes", key, bytes), 0)
  end
  return bmp.from_bgr555(raw:sub(1, bytes), colors)
end

-- The background palette the game uploads with this screen, read from
-- ICATALL.DAT; the labels' editor palette is the shared one.
local function palettes_for(data, args)
  return palette_arg(args, "bg_palette", "bg_palette_path", BG_PALETTE_BYTES, 256)
      or bmp.from_bgr555(data:sub(BG_PALETTE + 1, BG_PALETTE + BG_PALETTE_BYTES), 256),
    bmp.from_bgr555(palettes.raw("adv_dialogue_jp_for_bmp"), 16)
end

local function find_blocks(data)
  if type(data) ~= "string" then
    error("status_screen: input is not a byte string", 0)
  end
  if #data < FONT_OFFSET + FONT_SLOT then
    error(string.format(
      "status_screen: input is %d bytes; the font slot at 0x%06X ends at 0x%06X",
      #data, FONT_OFFSET, FONT_OFFSET + FONT_SLOT), 0)
  end

  local function decompress(offset, slot, size, what)
    local ok, artifact = pcall(function()
      return prs:decode(data:sub(offset + 1, offset + slot))[1]
    end)
    if not ok or not artifact then
      error(string.format("status_screen: the %s at 0x%06X is not a PRS stream",
        what, offset), 0)
    end
    if size and #artifact.data ~= size then
      error(string.format("status_screen: the %s decompresses to %d bytes, expected %d",
        what, #artifact.data, size), 0)
    end
    return artifact.data
  end

  local background = decompress(BG_OFFSET, BG_SLOT, BG_SIZE, "background")
  local font = decompress(FONT_OFFSET, FONT_SLOT, nil, "font sheet")
  if #font % TILE_SIZE ~= 0 then
    error(string.format(
      "status_screen: the font sheet decompresses to %d bytes, not whole %d-byte tiles",
      #font, TILE_SIZE), 0)
  end
  if #font > labels.MAX_TILES * TILE_SIZE then
    error(string.format("status_screen: the font sheet is %d tiles, over the %d-tile limit",
      #font // TILE_SIZE, labels.MAX_TILES), 0)
  end

  return background, font
end

-- A group canvas as 4bpp top-down pixels; its header gives the size (a
-- translation may widen it) and the depth an editor saved it at.
local function group_image(image, name)
  return labels.read_canvas(image, name)
end

-- The fifteen retail labels, composed from the sheet in the file.
local function retail_labels(font)
  local strips = {}
  for i = 1, labels.SLOTS do
    local indices = labels.RETAIL[i]
    strips[i] = {
      pixels = labels.compose(font, indices),
      width = #indices * labels.TILE,
    }
  end
  return strips
end

function codec.can_handle(data)
  return can_handle.can_handle_icatall(data)
end

function codec.decode_name(args)
  return (prefix(args))
end

function codec.decode(data, args)
  local background, font = find_blocks(data)
  local background_palette, label_palette = palettes_for(data, args)
  local dir = prefix(args)
  local strips = retail_labels(font)

  local artifacts = {
    {
      name = dir .. "_BG.bmp",
      data = bmp.build(background, BG_WIDTH, BG_HEIGHT, 8, background_palette),
    },
  }

  for _, group in ipairs(labels.GROUPS) do
    local rows = {}
    for k, slot in ipairs(group.slots) do rows[k] = strips[slot] end
    local pixels, width, height = labels.compose_group(rows)
    artifacts[#artifacts + 1] = {
      name = dir .. "_" .. group.name,
      data = bmp.build(pixels, width, height, 4, label_palette),
    }
  end

  -- The ten digit tiles, one per row, from the sheet the formatter indexes.
  local digit_strips = {}
  for i, glyph in ipairs(labels.DIGIT_GLYPHS) do
    digit_strips[i] = { pixels = labels.compose(font, { glyph }), width = labels.TILE }
  end
  local digit_pixels, digit_width, digit_height = labels.compose_group(digit_strips)
  artifacts[#artifacts + 1] = {
    name = dir .. "_" .. labels.DIGITS.name,
    data = bmp.build(digit_pixels, digit_width, digit_height, 4, label_palette),
  }

  return artifacts
end

function codec.encode(original, artifacts, args)
  local background, sheet = find_blocks(original)
  local dir = prefix(args)
  local by_name = {}
  for _, artifact in ipairs(artifacts or {}) do
    by_name[artifact.name] = artifact.data
  end

  local background_changed = false
  local background_bmp = by_name[dir .. "_BG.bmp"]
  if background_bmp then
    local pixels = bmp.parse(background_bmp, BG_WIDTH, BG_HEIGHT, 8)
    if pixels ~= background then
      background = pixels
      background_changed = true
    end
  end

  -- Every label comes from its group canvas; a group that is not supplied keeps
  -- its retail glyphs.  A canvas that differs from the retail composition
  -- rebuilds the whole sheet, and so does a digit canvas.
  local retail = retail_labels(sheet)
  local strips, labels_changed = {}, false

  for _, group in ipairs(labels.GROUPS) do
    local rows = {}
    local image = by_name[dir .. "_" .. group.name]
    if image then
      local pixels, width, height = group_image(image, group.name)
      rows = labels.split_group(group, pixels, width, height)
    end

    for k, slot in ipairs(group.slots) do
      local row = rows[k] or retail[slot]
      strips[slot] = row
      if row.pixels ~= retail[slot].pixels then labels_changed = true end
    end
  end

  -- The tail: retail tile 37's cell (the formatter's padding glyph), tile 38's,
  -- then the ten digits from DIGITS.bmp (or the sheet's retail tiles when the
  -- canvas is not supplied).
  local tail = {
    labels.cell(sheet, labels.PAD_GLYPH),
    labels.cell(sheet, labels.GAP_GLYPH),
  }
  local digits_changed = false
  do
    local image = by_name[dir .. "_" .. labels.DIGITS.name]
    local cells = {}
    if image then
      local pixels, width, height = labels.read_canvas(image, labels.DIGITS.name)
      local rows = labels.split_group(labels.DIGITS, pixels, width, height)
      for i, row in ipairs(rows) do
        local cut = labels.cells(row.pixels, row.width, labels.TILE)
        if #cut ~= 1 then
          error(string.format(
            "status_screen: %s row %d is %d cells wide; each row is one digit, "
            .. "one 16-pixel cell", labels.DIGITS.name, i, #cut), 0)
        end
        cells[i] = cut[1]
      end
    else
      for i, glyph in ipairs(labels.DIGIT_GLYPHS) do
        cells[i] = labels.cell(sheet, glyph)
      end
    end
    for i, cell in ipairs(cells) do
      tail[#tail + 1] = cell
      if cell ~= labels.cell(sheet, labels.DIGIT_GLYPHS[i]) then digits_changed = true end
    end
  end
  -- The stats formatter fills its line with a fixed glyph before drawing, so
  -- the atlas ends with a cell that is genuinely empty.  Its index depends only
  -- on the label count, and the strings codec points the formatter at it.
  tail[#tail + 1] = labels.BLANK

  local sheet_changed = false
  if labels_changed or digits_changed then
    local lists = {}
    for i = 1, labels.SLOTS do
      local strip = strips[i]
      local cells = labels.cells(strip.pixels, strip.width, labels.TILE)
      if labels.is_stats(i) and #cells ~= 2 then
        error(string.format(
          "status_screen: label %d is %d cells wide, but the stats formatter reads "
          .. "two glyph words with one longword; draw it as exactly two cells",
          i, #cells), 0)
      end
      lists[i] = cells
    end

    local built = labels.atlas(lists, tail)
    sheet_changed = built ~= sheet
    sheet = built
  end

  local out = original

  if sheet_changed then
    local compressed = prs:encode("", { { name = "STATUS_FONT", data = sheet } })
    if #compressed > FONT_SLOT then
      error(string.format(
        "status_screen: the %d-cell sheet compresses to %d bytes, over the %d-byte slot",
        #sheet // TILE_SIZE, #compressed, FONT_SLOT), 0)
    end
    compressed = compressed .. string.rep("\0", FONT_SLOT - #compressed)
    out = out:sub(1, FONT_OFFSET) .. compressed .. out:sub(FONT_OFFSET + FONT_SLOT + 1)
  end

  if background_changed then
    local compressed = prs:encode("", { { name = "STATUS_BG", data = background } })
    if #compressed > BG_SLOT then
      error(string.format("status_screen: compressed background %d exceeds slot %d",
        #compressed, BG_SLOT), 0)
    end
    compressed = compressed .. string.rep("\0", BG_SLOT - #compressed)
    out = out:sub(1, BG_OFFSET) .. compressed .. out:sub(BG_OFFSET + BG_SLOT + 1)
  end

  return out
end

return codec
