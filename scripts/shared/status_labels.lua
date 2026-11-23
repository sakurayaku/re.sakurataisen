--[[
  The status screen's labels: geometry, grouping, composition and atlas packing.

  Shared by scripts/status_screen_gfx.lua, which owns the font sheet in
  SAKURA1/ICATALL.DAT, and scripts/SAKURA/status_screen_metadata.lua, which owns
  the glyph-index strings in the SAKURA executable.  A rebuilt sheet only makes
  sense with the strings that index it, so both derive the atlas here, once:
  the same canvases always give the same tiles and the same index lists.

  ## A label

  One 16-pixel-high strip, <cells> x 16 pixels, 4bpp, one 16x16 cell per glyph,
  drawn left to right.  The engine walks a string's index list in order, so the
  cell count of the image is the glyph count of the string.

  ## The retail labels

  RETAIL holds the fifteen index lists of the retail SAKURA.  They are the
  reference's own PatchStatusScreen lists (SakuraTaisen.cpp:10654) checked
  against the disc: slots 1..12 are the two pointer-table names and labels,
  13..15 the three stats.  Slots 16..18 are addressed by the pointer tables by
  nothing, but they are not dead: 16 is the padding glyph the stats formatter
  writes between the label and the number, 17 a separator glyph, and 18 the ten
  digit glyphs it indexes with 0..9.  All three are kept.

  ## The stats are two cells

  The code that draws Attack/Defense/Movement reads a whole word of the stats
  string into the first two slots of its line buffer, so a stats label is
  exactly two cells, and its string must start on a 2-byte boundary (`mov.w`).
  In the retail two-byte format that word is two u16 glyph indices; in the byte
  format this project writes it is two glyph bytes, fetched with the retail
  instruction shape.

  ## The atlas

  Cells are de-duplicated exactly and stored in first-use order: label 1's
  cells, then label 2's unused cells, and so on, then the tail.  Nothing else
  about the sheet is stable, so a label edit renumbers every tile and both files
  have to be rebuilt together.

  The tail is appended after the labels and is never de-duplicated against them,
  so its numbers only depend on how many distinct cells the labels use:

      +1        tile 37's cell, the padding glyph the formatter writes
      +2        tile 38's cell, the separator glyph
      +3 .. +12 tiles 39..48's cells, the ten digits 0..9
      +13       an empty cell the formatter's line fill points at

  ## The groups

  A build edits four canvases, not fifteen files.  Each holds one label per row,
  every row 16 pixels high:

      NAMES.bmp   labels 1..6     Sakura, Sumire, Kohran, Kanna, Maria, Iris
      MOODS.bmp   labels 7..12    High, Spirits, Normal, Mood, Terrible, Mood
      STATS.bmp   labels 13..15   Attack, Defense, Movement   (two cells each)
      DIGITS.bmp  the ten digits, 0..9, one per row

  A codec prefixes each of those with its status prefix, so the artifacts are
  STATUS_NAMES.bmp, STATUS_MOODS.bmp, STATUS_STATS.bmp and STATUS_DIGITS.bmp,
  beside STATUS_BG.bmp for the background.

  A group is as wide as its widest row; the shorter rows are filled with index
  0 on the right, which is how a row's sentence ends.  Trailing blank cells are
  padding and are not part of the label, so a row always costs its last inked
  cell and nothing more -- draw through index 0 and the tail disappears.

  ## Canvases are 4 bpp

  A canvas is 4 bpp, sixteen colours, like the sheet cell it becomes.  read_canvas
  takes the size from the BMP's own header (a translation may widen a group) and
  accepts either vertical orientation, but it will not read a deeper BMP: an
  editor that widens or reorders the palette renumbers the pixels with it, so
  the file is refused with the depth in the message rather than half-read.

  ## The sheet's size

  Retail's sheet is 48 tiles, 6,144 bytes, and its whole 2,522-byte PRS slot.
  Nothing in the glyph renderer bounds a glyph id, and the next font base in the
  executable (0x25C09000) is 24 KB above this one, but whether the loader keeps
  feeding the decompressor past 6,144 bytes is not proven.  MAX_TILES is
  therefore a safety margin rather than a measured hardware limit: a build that
  grows the sheet is expected to be checked on hardware or an emulator.
]]

local bmp = dofile(LUDARED.SCRIPTS .. "/shared/bmp.lua")

local M = {}

M.TILE       = 16
M.TILE_BYTES = M.TILE * M.TILE // 2      -- 128, 4bpp
M.RETAIL_TILES = 48                      -- the retail sheet, 6,144 bytes
M.MAX_TILES  = 96                        -- 12,288 bytes; 0x25C09000 leaves 24 KB
M.MAX_CELLS  = 18                        -- 288 px, the screen width
M.SLOTS      = 15                        -- labels 1..15; 16..18 are the tails

-- Stats strings are read with one word: exactly two glyphs.
M.STATS = { 13, 14, 15 }

-- The tail cells, by their retail glyph ids.
M.PAD_GLYPH   = 37
M.GAP_GLYPH   = 38
M.DIGIT_GLYPHS = { 39, 40, 41, 42, 43, 44, 45, 46, 47, 48 }

-- The retail index lists, slot 1 first.
M.RETAIL = {
  { 5, 6, 7 },            -- 1  Sakura
  { 8, 9, 10 },           -- 2  Sumire
  { 11, 12 },             -- 3  Kohran
  { 13, 14, 15 },         -- 4  Kanna
  { 16, 1, 2 },           -- 5  Maria
  { 2, 17, 1, 18 },       -- 6  Iris
  { 3, 19 },              -- 7  High
  { 20, 21, 22, 23 },     -- 8  Spirits
  { 24, 25, 26, 27 },     -- 9  Normal
  { 3, 28 },              -- 10 Mood
  { 29, 30, 31, 32 },     -- 11 Terrible
  { 4, 4, 33 },           -- 12 Mood
  { 34 },                 -- 13 Attack
  { 35 },                 -- 14 Defense
  { 36 },                 -- 15 Movement
}

-- The canvases, in the order a build edits them.
M.GROUPS = {
  { name = "NAMES.bmp",  slots = { 1, 2, 3, 4, 5, 6 } },
  { name = "MOODS.bmp",  slots = { 7, 8, 9, 10, 11, 12 } },
  { name = "STATS.bmp",  slots = { 13, 14, 15 } },
}

M.DIGITS = { name = "DIGITS.bmp", slots = M.DIGIT_GLYPHS }

-- One empty cell, appended after the digits.  The stats formatter starts its
-- line by filling four slots with a fixed glyph (retail 20, which happens to be
-- a blank cell of the retail sheet); an atlas rebuilt from a translation has no
-- guaranteed blank at any particular index, so it carries one of its own and
-- status_screen_metadata.lua points the formatter's immediate at it.
M.BLANK = string.rep("\0", M.TILE_BYTES)

function M.name(index)
  return string.format("LABEL_%02d.bmp", index)
end

-- A canvas as top-down 4bpp pixels, whatever depth the editor saved.
function M.read_canvas(data, name)
  name = name or "a canvas"
  if type(data) ~= "string" or #data < 54 or data:sub(1, 2) ~= "BM" then
    error(string.format("status labels: %s is not a BMP", name), 0)
  end

  local width, height = string.unpack("<i4i4", data, 19)
  local bits = string.unpack("<H", data, 29)
  width, height = math.abs(width), math.abs(height)

  if bits ~= 4 then
    error(string.format(
      "status labels: %s is %d bpp, not 4; a canvas is 4 bpp with the sixteen text "
      .. "colours (an editor that widened the palette renumbered the pixels -- save "
      .. "it back as 4 bpp)", name, bits), 0)
  end

  return bmp.parse(data, width, height, 4), width, height
end

function M.is_stats(index)
  for _, slot in ipairs(M.STATS) do
    if slot == index then return true end
  end
  return false
end

-- One 128-byte cell of the sheet, 1-based.
function M.cell(sheet, glyph)
  if glyph < 1 or glyph * M.TILE_BYTES > #sheet then
    error(string.format("status labels: the sheet has no tile %d", glyph), 0)
  end
  local at = (glyph - 1) * M.TILE_BYTES
  return sheet:sub(at + 1, at + M.TILE_BYTES)
end

-- One label as packed 4bpp pixels, 16 pixels high and #indices cells wide.
function M.compose(sheet, indices)
  local cells = math.max(#indices, 1)
  local row_bytes = M.TILE // 2
  local rows = {}
  for row = 0, M.TILE - 1 do
    local parts = {}
    for cell = 1, cells do
      local glyph = indices[cell]
      local out = string.rep("\0", row_bytes)
      if glyph then
        local at = (glyph - 1) * M.TILE_BYTES + row * row_bytes
        out = sheet:sub(at + 1, at + row_bytes)
      end
      parts[cell] = out
    end
    rows[row + 1] = table.concat(parts)
  end
  return table.concat(rows)
end

-- Cut a label strip into its 16x16 cells, left to right.
function M.cells(pixels, width, height)
  if height ~= M.TILE then
    error(string.format("status labels: a label is %d pixels high, not %d",
      height, M.TILE), 0)
  end
  if width <= 0 or width % M.TILE ~= 0 then
    error(string.format(
      "status labels: a label is %d pixels wide; widths are whole %d-pixel cells",
      width, M.TILE), 0)
  end

  local count = width // M.TILE
  if count > M.MAX_CELLS then
    error(string.format("status labels: a %d-cell label is wider than the %d-cell screen",
      count, M.MAX_CELLS), 0)
  end

  local stride, row_bytes = width // 2, M.TILE // 2
  local out = {}
  for cell = 0, count - 1 do
    local parts = {}
    for row = 0, M.TILE - 1 do
      local at = row * stride + cell * row_bytes
      parts[row + 1] = pixels:sub(at + 1, at + row_bytes)
    end
    out[cell + 1] = table.concat(parts)
  end
  return out
end

-- Stack the strips of one group into its canvas: one label per row, every row
-- as wide as the widest one, index 0 to the right.
function M.compose_group(strips)
  local width = 0
  for _, strip in ipairs(strips) do
    if strip.width > width then width = strip.width end
  end
  if width <= 0 then
    error("status labels: a group of empty labels", 0)
  end

  local stride = width // 2
  local rows = {}
  for _, strip in ipairs(strips) do
    local row_bytes = strip.width // 2
    for row = 0, M.TILE - 1 do
      local line = strip.pixels:sub(row * row_bytes + 1, (row + 1) * row_bytes)
      rows[#rows + 1] = line .. string.rep("\0", stride - row_bytes)
    end
  end
  return table.concat(rows), width, M.TILE * #strips
end

-- Back from a group canvas to its labels.  A row ends at its last inked cell;
-- the rest is padding.
function M.split_group(group, pixels, width, height)
  local count = #group.slots

  if height ~= M.TILE * count then
    error(string.format("status labels: %s has %d rows of %d pixels, but it holds %d labels",
      group.name, math.floor(height / M.TILE), M.TILE, count), 0)
  end
  if width <= 0 or width % M.TILE ~= 0 then
    error(string.format("status labels: %s is %d pixels wide; widths are whole %d-pixel cells",
      group.name, width, M.TILE), 0)
  end
  if width > M.MAX_CELLS * M.TILE then
    error(string.format("status labels: %s is %d cells wide, over the %d-cell screen",
      group.name, width // M.TILE, M.MAX_CELLS), 0)
  end

  local stride, cells = width // 2, width // M.TILE
  local out = {}

  for index = 1, count do
    local used = 0
    for row = 0, M.TILE - 1 do
      local start = ((index - 1) * M.TILE + row) * stride
      local line = pixels:sub(start + 1, start + stride)
      for cell = cells, 1, -1 do
        if line:sub((cell - 1) * 8 + 1, cell * 8):find("[^%z]") then
          if cell > used then used = cell end
          break
        end
      end
    end

    if used == 0 then
      error(string.format("status labels: %s row %d is blank", group.name, index), 0)
    end

    local rows = {}
    for row = 0, M.TILE - 1 do
      local start = ((index - 1) * M.TILE + row) * stride
      rows[#rows + 1] = pixels:sub(start + 1, start + used * 8)
    end
    out[index] = { pixels = table.concat(rows), width = used * M.TILE }
  end

  return out
end

-- De-duplicate the cells of every label, in first-use order, into one sheet.
-- The optional tail (pad, separator, digits) is appended as given: it is never
-- merged with a label cell, so its numbers depend only on the label count.
-- Returns the flat sheet bytes, one index list per label, and the tail's.
function M.atlas(lists, tail)
  local index, order, indices = {}, {}, {}

  local function add(tile)
    if #tile ~= M.TILE_BYTES then
      error(string.format("status labels: a cell is %d bytes, expected %d",
        #tile, M.TILE_BYTES), 0)
    end
    local at = index[tile]
    if not at then
      order[#order + 1] = tile
      at = #order
      index[tile] = at
    end
    return at
  end

  for i, tiles in ipairs(lists) do
    local list = {}
    for k, tile in ipairs(tiles) do list[k] = add(tile) end
    indices[i] = list
  end

  local extra
  if tail then
    extra = {}
    for i, tile in ipairs(tail) do
      if #tile ~= M.TILE_BYTES then
        error(string.format("status labels: a tail cell is %d bytes, expected %d",
          #tile, M.TILE_BYTES), 0)
      end
      order[#order + 1] = tile
      extra[i] = #order
    end
  end

  if #order == 0 then
    error("status labels: the labels are empty", 0)
  end
  if #order > M.MAX_TILES then
    error(string.format(
      "status labels: the labels and the digit tail use %d distinct cells, over the %d-tile sheet",
      #order, M.MAX_TILES), 0)
  end
  return table.concat(order), indices, extra
end

return M
