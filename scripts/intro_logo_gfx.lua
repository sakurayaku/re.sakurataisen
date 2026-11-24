--[[
  Sakura Taisen (Saturn) — boot logo screen ("sakura / taisen")

  PATCH codec for SAKURA1/LOGO.SH2, adapting

      SakuraTaisen.cpp: bool PatchIntroLogo(const string&, const string&)  (11706)

  The C++ does not compress anything: it copies a pre-built PRS stream from
  `PrecompressedIntroLogo.bin` into the file and refuses it above 15,123 bytes.
  This codec replaces that blob with the pixels themselves: decode() decompresses
  the retail block and hands back every part of the logo as a BMP, encode()
  paints the edits back and recompresses into the same slot.

  ## The block

      0x00025410   PRS, 15,123 bytes  ->  83,584 decompressed bytes

  The retail stream is exactly 15,123 bytes long: the five palettes below start
  at 0x28F24, the first byte after it.  The slot is full, so an edited buffer has
  to compress no worse than the original encoder.  The project's PRS encoder
  reproduces the retail buffer in 14,543 bytes, which leaves about 580 bytes of
  headroom; an oversized result is refused rather than truncated.  A shorter
  stream is zero padded to the slot, so the palette never moves.

  ## What is in it: 13 rectangles, packed back to back

  Every rectangle is linear 8bpp with its own width as the row stride -- no
  tiling, no padding.  They tile the block exactly, so the map below has no gaps:

      0x00000  112x136   15,232   card backdrop: frame, blossoms, "TEIGEKI", TM
      0x03B80   96x96     9,216   emblem: red disc, 帝撃
      0x05F80   56x152    8,512   サクラ, first copy   (silhouette)
      0x080C0   56x152    8,512   サクラ, second copy  (silhouette)
      0x0A200   56x152    8,512   サクラ, full colour   <- the C++ replaces this
      0x0C340   64x72     4,608   大, first copy      (silhouette)
      0x0D540   64x72     4,608   大, second copy     (silhouette)
      0x0E740   64x72     4,608   大, full colour     <- the C++ replaces this
      0x0F940   64x80     5,120   戦, first copy      (silhouette)
      0x10D40   64x80     5,120   戦, second copy     (silhouette)
      0x12140   64x80     5,120   戦, full colour
      0x13540   24x24       576   small mark (the "TM")
      0x13780  160x24     3,840   caption strip

  The three copies of a glyph are not identical: the first two use only three
  indices (a silhouette) and the third carries the real artwork (33 indices for
  サクラ, 62 for 大, 56 for 戦).  So the screen builds each glyph as a flat colour
  shape and then fills it in with the coloured art.  The C++ only rewrites the
  full-colour copy, which is why the JP silhouettes still flash before its
  artwork appears -- so 大 and 戦 are exposed here as all three copies stacked,
  which is also how the US team's own file is laid out (see below).

  ## How the sprites are drawn

  File offset 0x6260 holds the sprite table, 12 records of 14 bytes, three per
  glyph, big-endian i16:

      +0  x, y      placement (the left column starts at -24)
      +4  w, h      source rectangle, and the row stride of the art above
      +8  u16       art offset divided by 8 -- 5184 * 8 = 0xA200, 7400 * 8 =
                    0xE740, 9256 * 8 = 0x12140, and so on for all twelve
      +10 u16       0, or 16 on the last record
      +12 u16       0x20, or 0 on the last record

  So the engine takes placement *and size* from this table, not from the art:
  that is how the US release turns the vertical サクラ into a horizontal one.
  PatchIntroLogo rewrites three of them -- 0x628A (サクラ to 152x56 at -128,-48),
  0x62B4 (大 to y=-256, off screen) and 0x62DE (戦 to -16,-32) -- which is
  placement, not pixels, and this codec leaves it alone so a build keeps the
  shipped layout.

  The last record claims 168x24 while its rectangle is 160x24 (0x13780 to the end
  of the block), so for the caption the record's width is a cell-rounded bounding
  box rather than the stride.  Nothing else disagrees.

  That last rectangle is not lettering: it is a two-band diagonal hatch -- each
  row repeats the one above shifted by eight pixels, one direction in the top
  band and the other in the bottom one -- i.e. the hatched banner that runs under
  the logo.  It looks like noise in a BMP viewer because it is a hatch, and
  0x29124 is still its palette: of the five slots it gives the used indices the
  smoothest luminance ramp (5 direction changes against 9..19 for the others).

  Nothing here is DMA'd from the file directly to VRAM.  File 0x6000 holds a list
  of (destination, source) u32 pairs, one of which is (0x060E1800, 0x00229410) --
  this block into work RAM -- which matches the shuttling LOGO export #6 does for
  the subtitle atlas: PRS into a work-RAM buffer first, then a second transfer
  out of it (see research/SAKTAI_SUBTITLES.md section 5).

  ## The fan behind the logo: a second, compressed layer

  The glyph block is only the VDP1 sprite layer.  The logo's brush-script word is
  a VDP2 layer, stored above it in two pieces:

      0x00024B8C   PRS, 1,644-byte slot  ->  5,888 bytes = 92 8x8 8bpp tiles
      0x000251F8   536-byte tile map    ->  134 x u32, first 133 used,
                                            value = tile index * 2 (max 91)

  The slot is exactly full (0x24B8C + 1,644 = 0x251F8, where the map starts) and
  the project encoder repacks the retail sheet in 1,568 bytes, leaving 76 bytes.
  The sheet uses only 15 indices.

  The 92 tiles are a bank, not a picture: the map picks 133 of them into a 19 x 7
  grid -- 152x56, exactly the size of the US team's `VDP2/IntoroLogo.tsx` and the
  grid of `VDP2/IntoroLogo.tmx` (19 by 7 tiles, numbered 1..133).  Tile 0 is left
  empty; the map names tiles from 1.

  How that grid is laid out depends on the module's own two conversion words (see
  "How the fan comes in" below), because they are what rotates the layer:

    * retail's (19, 7) turns the layer, and the artwork is stored transposed to
      compensate: cell i is column i // 7, row i % 7, and each tile's 64 bytes
      are column-major too -- byte k is the pixel at column k // 8, row k % 8.
      Read that way the retail sheet and map are the word サクラ.
    * the US build's (7, 19) takes the rotation away, so the same artwork has to
      be stored plainly: cell i is row i // 19, column i % 19, and a tile is
      eight rows of eight pixels.  Read this way the US sheet and map are its
      "Sakura", and the retail pair is noise.

  encode() picks the arrangement from the SAKURA.bmp it is given (horizontal word
  => the swapped pair => plain tiles), falling back to the module's own words when
  no SAKURA.bmp is supplied, and decode() follows the same rule.  Writing the
  transposed arrangement into a module that asks for the swapped pair is what
  made the fan arrive as shreds.

  PatchIntroLogo patches these same two places, inside the `if( 0 )` branch:
  `VDP2/SakuraLogo_Small.bmp` (140x40) goes to 0x24B8C under a 1,644-byte limit
  -- "Compressed swirl sakura image is too big" -- and `VDP2/IntroLogo.csv`
  becomes the tile map at 0x251F8.  The US disc keeps the same layout as retail:
  243,200 bytes, a 92-tile sheet in the 1,644-byte slot at 0x24B8C and a 133-cell
  map at 0x251F8.  Only the art changed.  Decoding that module and encoding it
  again reproduces every one of its 243,200 bytes.

  SWIRL.bmp is that grid untiled: 152x56.  encode() cuts it back into tiles,
  keeping every cell in the retail tile slot the map gave it, so an untouched
  picture reproduces the shipped sheet and map byte for byte; only an edit that
  makes two cells sharing a tile differ renumbers the sheet, and then the map at
  0x251F8 is rewritten with it.

  ## The artworks

      INTRO_LOGO/SWIRL.bmp    152x56    the word: 19 x 7 cells from a 92-tile bank
      INTRO_LOGO/BACKDROP.bmp  112x136   card, frame, blossoms, caption, TM
      INTRO_LOGO/EMBLEM.bmp     96x96    the 帝撃 disc
      INTRO_LOGO/SAKURA.bmp    56x456    サクラ: white state, then the same in
                                        241, then the colour copy
      INTRO_LOGO/TAI.bmp        64x216   大: silhouette, silhouette, colour
      INTRO_LOGO/SEN.bmp        64x240   戦: silhouette, silhouette, colour
      INTRO_LOGO/MARK.bmp       24x24    the "TM"
      INTRO_LOGO/CAPTION.bmp   160x24    the caption strip
      INTRO_LOGO/LAYOUT.csv     12 rows   index,x,y,w,h,file for the sprite records

  The twelve sprite records place all of that on screen, and they are the whole
  difference between the JP and US logo: the US build turns all three サクラ
  records to -128,-48 152x56, puts all six 大/戦 records at -16,-32 64x80 (the
  colour 戦 art is what draws "Wars"), and shifts the TM from -49,14 to 10,-12.
  All three サクラ records matter: the glyph is on screen three times over, the
  two flat states underneath and the colour one on top, and a build that parks
  the flat two off screen shows the word arrive, vanish, and come back in
  colour.  encode() therefore writes the same rectangle to all three.
  PatchIntroLogo does the same job by writing three records at fixed offsets
  (0x628A, 0x62B4, 0x62DE).

  The table's address is not the same in every revision: the retail disc's
  LOGO.SH2 keeps it at 0x70A0, while the copy in the project root keeps it at
  0x6260, 0xE40 earlier because that revision's code is shorter.  The codec
  probes both and uses whichever holds twelve records that could be sprites --
  writing the 0x6260 addresses into a disc file edits shift-JIS text, which is
  what made TAI and the TM appear stuck in the JP positions.

  LAYOUT.csv carries all twelve so any sprite can be moved by hand; a line
  `index,x,y,w,h,file` rewrites that record's eight placement bytes and leaves
  the art pointer and the flags alone.  A sprite whose art is not in the right
  orientation (the サクラ silhouettes are stored vertical) can be parked off
  screen with y=255.  The last field names the BMP the record places -- a glyph
  is on screen once per copy it has in the block, so サクラ owns three records
  (1, 2, 3), 大 and 戦 three each (4-6, 7-9), and the emblem, the TM and the
  caption one apiece.  It is written for reading only: encode() ignores it, so
  a five-column line from an older build is still accepted.

  Every one of them carries the screen's 256-colour palette in its BMP header,
  but only so an image editor can display the artwork in its real colours.
  encode() never writes the palette: the file's own grading is kept byte for
  byte, and a BMP header that disagrees with it is refused.

  大 and 戦 are each three non-adjacent copies, so those BMPs stack the copies
  top to bottom and the codec splits them back at row 72 / 72 / 72 and 80 / 80 /
  80.  Every part is written separately, so a repaint of one stage never rewrites
  the bytes of the others: an untouched stage stays byte-identical to retail.

  サクラ is exposed as its colour copy only, the one the C++ replaces.  Its two
  silhouettes (0x5F80, 0x80C0) are still retail; adding them is one more `parts`
  entry each, exactly like 大.

  SAKURA.bmp is accepted in either orientation, which costs nothing because
  56x152 and 152x56 are the same 8,512 bytes -- only the row stride differs:

      56x152   as shipped: vertical, and its record stays at -24,-104
      152x56   the US layout: written with rows of 152, and the sprite record at
               0x628A patched to -128,-48,152,56, byte for byte what
               PatchIntroLogo writes (FF80 FFD0 0098 0038).  Supplying the
               vertical artwork again puts the retail record back, so the two
               orientations can be swapped as often as you like.

  ## How the fan comes in

  The fan's entrance is code, not art.  The module calls its setup routine with
  the map's two dimensions as arguments, and the orientation of the word decides
  which way round they are:

      0x387A   E7 13   mov #19,R7   JP, with 0x387E E6 07  mov #7,R6
      0x387A   E7 07   mov  #7,R7   US, with 0x387E E6 13  mov #19,R6

  19 and 7 are the map's 19 columns and 7 rows.  Retail sweeps the word in from
  the side; the US build swaps the two and it arrives from the top.  encode()
  writes these two words to follow the SAKURA.bmp it was given -- 56x152 keeps
  retail's pair, 152x56 writes the swapped pair -- so a horizontal logo brings
  the horizontal entrance with it and the vertical artwork puts the original
  back.  A module that carries neither pair (another revision) is left alone.

  The US build also changes two bytes of that same call, at 0x392A
  (41 44 -> 48 10; the 25 E6 before them is the same in both).  Swapping 19 and
  7 only changes the order the cells are read in; it does not move the layer, and
  on its own the fan still appears in its final corner and stays there.  With
  this third word as well, the word sweeps in across the middle of the screen the
  way the US release does.  What the value means is not established, so encode()
  only ever writes the two signatures it knows -- 41 44 for the vertical word,
  48 10 for the horizontal one -- and leaves any other value alone.

  Only the colour copy turns.  Its silhouettes are still the vertical JP shapes
  and only record 0x628A is patched -- the same single record the C++ patches --
  so those stages keep drawing at their own place and size.

  This matches the US team's own working files, which are the same geometry:
  `SakuraLogo_Sakura.bmp` is 152x56 (the rotation), and `SakuraLogo_Wars.bmp` is
  64x312 -- one contiguous strip covering 0xE740..0x13540, i.e. 大's colour copy
  over all three 戦 copies, with the "Wars" artwork drawn into the 戦 stages and
  大 left as retail pixels (its record is moved off screen instead).  TAI.bmp +
  SEN.bmp cover exactly those same bytes.

  ## Palettes

  Five consecutive 512-byte palettes follow the block, 0x28F24 .. 0x29924, i.e.
  256 big-endian BGR555 entries each.  The original tool never touches them (its
  blob only carried pixel data), so which slot a given intro frame loads is not
  recorded anywhere in the pipeline.

  The screen carries *one* palette at a time, not one per sprite: the US team's
  two bitmaps above even share a single 256-entry palette.  Measured over the
  five slots:

      0x28F24  241 distinct colours, ends in thirteen repeats of 0x7E5F
      0x29124  254 distinct colours, no filler -- a complete grading
      0x29324  171 distinct, 86-entry constant tail, and entries 240..242 are all
               0x56B5, which would make the silhouettes invisible
      0x29524  253 distinct, differs from 0x29124 in 19 entries (3 of 0..239)
      0x29724   18 distinct colours only: a different kind of art entirely

  So 0x29124 and 0x29524 are the reveal's colour stages -- nearly the same
  grading, shading the silhouette trio differently -- and 0x28F24 is a separate
  one-off.  This codec paints with 0x29124, the grading that reproduces the
  retail look: pink サクラ, silver-teal 大戦, on the card.

  ## The palette is read-only

  The palette in each BMP header exists so that an image editor shows the
  artwork in the colours the game will use.  It is display-only: encode() reads
  it, compares it against the file's own grading at 0x29124, and keeps the
  file's bytes in either case.  A header that disagrees is an error naming the
  file, not a write -- that is what stops an accidental recolour from reaching
  the disc, and what made a swapped-channel header show up as a blue screen
  rather than as a silent palette edit.

  What that means while painting:

    * only the pixel indices travel.  Use the entries the retail artwork uses
      and the colours stay exactly the retail ones.
    * an editor that re-saves the same colours (or changes only the ignored
      alpha byte) is accepted, because the comparison is made on the 5-bit
      result: a channel snaps to round(v * 31 / 255).
    * index 0 is the transparency key.  It is what lets the fan and the card
      show through the sprites, so a colour placed there is never drawn.
    * if a genuinely different grade is ever wanted, it belongs in the file,
      not in a BMP header.  The candidates are 0x28F24, 0x29124, 0x29324,
      0x29524 and 0x29724; 0x29124 is the grading that reproduces the retail
      look.

  ## Rebalancing the block

  The thirteen rectangles tile 83,584 bytes exactly, so there is no free space in
  the decompressed buffer -- but there is slack in two other places:

    * compressed headroom: 14,543 of 15,123 bytes, so ~580 bytes of new art
      compress for free;
    * ink slack: several rectangles are taller/wider than their pixels.  戦 is
      64x80 but its ink only spans rows 6..78, 大 is 64x72 with ink to row 71,
      サクラ is 56x152 with ink from row 2, the mark is 24x24 with ink to row 17,
      the emblem 96x96 with ink rows 5..90.

  Shrinking a rectangle means editing its sprite record (x, y, w, h) and moving
  the art that follows it, since the record's art offset is a byte offset divided
  by eight -- the whole buffer is one contiguous image, not a set of slots.  Done
  by hand that is a record rewrite plus a rebuild; this codec keeps the shipped
  geometry so a build stays byte-identical, and refuses an artwork that does not
  match its rectangle.

  ## Disc 1 vs disc 2

  No switch is needed, and PatchIntroLogo has none either.  Both discs ship a
  243,200-byte LOGO.SH2; the disc-2 copy differs from the disc-1 copy in 379
  bytes, all of them below 0x6020 (instructions and their literal pools, which
  moved by 0x140).  The block at 0x25410, the palettes at 0x28F24..0x29924 and
  the sprite table at 0x6260 are byte-identical, so these offsets are disc
  independent.  can_handle() recognizes the exact CD1 and CD2 module hashes
  from shared/constants.lua.
]]

local bmp = dofile(LUDARED.SCRIPTS .. "/shared/bmp.lua")
local prs = LUDARED.codec("std/sega/compression/prs")

local can_handle = dofile(LUDARED.SCRIPTS .. "/shared/can_handle.lua")

local codec = {}

codec.name        = "Sakura Taisen Intro Logo"
codec.description = "Patches the boot logo fan, card, glyphs and palette in SAKURA1/LOGO.SH2"
codec.version     = 9
codec.kind        = "patch"

local BLOCK_OFFSET   = 0x00025410
local BLOCK_SLOT     = 15123          -- retail stream size, and the C++'s limit
local BLOCK_BYTES    = 83584          -- decompressed buffer
local PALETTE_OFFSET = 0x00028F24     -- first of five consecutive 512-byte palettes
local PALETTE_BYTES  = 256 * 2
local PAINT_SLOT     = 1              -- 0x29124: the grading the artwork is painted with
local BPP            = 8

-- The word is its own PRS stream in its own slot, above the glyph block, and a
-- tile map directly after it.
local SWIRL_OFFSET   = 0x00024B8C
local SWIRL_SLOT     = 1644
local SWIRL_BYTES    = 5888
local SWIRL_MAP      = 0x000251F8     -- 134 u32 cells; only the first 133 are read
local SWIRL_COLUMNS  = 19             -- 19 x 7 = 133 cells = 152 x 56 pixels
local SWIRL_ROWS     = 7
local SWIRL_WIDTH    = SWIRL_COLUMNS * 8
local SWIRL_HEIGHT   = SWIRL_ROWS * 8
local SWIRL_CELLS    = SWIRL_COLUMNS * SWIRL_ROWS
local SWIRL_NAME     = "SWIRL.bmp"

-- The twelve VDP1 sprite records at 0x6260, 14 bytes each: x, y, w, h as
-- big-endian i16, then the art offset (u16, * 8) and two flag bytes.  Only the
-- first eight bytes are the layout, and those are what LAYOUT.csv carries.
-- The records follow the SH-2 code, so a revision whose code is longer would
-- push them along with the rest of the data.  Every module we have -- the
-- extraction from the retail disc, the copy in the project root and the
-- US-patched one -- keeps them at 0x6260; 0x70A0 is 0xE40 later and is tried as
-- a fallback for a revision we do not have.  Guessing wrong is not loud: writing
-- these records into the wrong address edits the shift-JIS text or compressed
-- data that lives there and leaves the sprites where they were, so both
-- addresses are probed and only one whose twelve records could be sprites is
-- used.
local RECORD_SLOTS   = { 0x000070A0, 0x00006260 }
local RECORD_BYTES   = 14
local RECORD_COUNT   = 12
local LAYOUT_NAME    = "LAYOUT.csv"
local SWIRL_TILE     = 64             -- one 8x8 8bpp tile, stored column-major
local SWIRL_TILES    = SWIRL_BYTES // SWIRL_TILE   -- 92

-- Where the fan comes in from is not in the artwork: it is two `mov #imm` words
-- in the module's own code, 0x387A (`mov #<columns>,R7`) and 0x387E
-- (`mov #<rows>,R6`), which are the two arguments of the setup call at 0x387C.
-- Retail passes 19 columns and 7 rows, i.e. the fan's own map dimensions and the
-- vertical サクラ of the Japanese screen.  The US build passes them the other
-- way round (0x07 and 0x13) and also changes the argument at 0x392A, and that is
-- the pair that makes the word travel in across the middle instead of appearing
-- in its corner.  All three are written to match the orientation of the
-- SAKURA.bmp that was supplied, so the horizontal artwork keeps the horizontal
-- word and the motion that belongs to it.
local MOTION = {
  columns = { at = 0x0000387A, vertical = "\xE7\x13", turned = "\xE7\x07" },
  rows    = { at = 0x0000387E, vertical = "\xE6\x07", turned = "\xE6\x13" },
  sweep   = { at = 0x0000392A, vertical = "\x41\x44", turned = "\x48\x10" },
}

-- One BMP per piece of the screen; `parts` are the rectangles it is made of,
-- top to bottom, each 8bpp linear with the artwork's width as its row stride.
local IMAGES = {
  {
    name = "BACKDROP.bmp", width = 112, height = 136,
    parts = { { offset = 0x000000, rows = 136 } },
  },
  {
    name = "EMBLEM.bmp", width = 96, height = 96,
    parts = { { offset = 0x003B80, rows = 96 } },
    records = { 0 },
  },
  {
    -- Three frames, one per sprite record, like 大 and 戦: the glyph is drawn
    -- three times on top of itself, and the two flat copies are the state it is
    -- in before the colour arrives.  Their pixels use indices 240 (white),
    -- 241 (the same white, tinted) and 242 (pale pink) instead of the artwork's
    -- own colours -- they are hand-drawn, not a recolour the codec could make --
    -- so they are a frame of this BMP like any other.
    name = "SAKURA.bmp", width = 56, height = 456,
    parts = {
      { offset = 0x005F80, rows = 152 },   -- white, and 242
      { offset = 0x0080C0, rows = 152 },   -- 241 instead of the 240
      { offset = 0x00A200, rows = 152 },   -- colour
    },
    records = { 1, 2, 3 },
    -- The US release turns the glyph on its side: the same bytes with rows of
    -- 152, plus a 152x56 source rectangle on all three of its records.
    alternate = {
      width = 152, height = 168,
      parts = {
        { offset = 0x005F80, rows = 56 },
        { offset = 0x0080C0, rows = 56 },
        { offset = 0x00A200, rows = 56 },
      },
      slots = { 1, 2, 3 },
      vertical = { -24, -104, 56, 152 },
      horizontal = { -128, -48, 152, 56 },
    },
  },
  {
    name = "TAI.bmp", width = 64, height = 216,
    parts = {
      { offset = 0x00C340, rows = 72 },   -- silhouette
      { offset = 0x00D540, rows = 72 },   -- silhouette
      { offset = 0x00E740, rows = 72 },   -- colour
    },
    records = { 4, 5, 6 },
  },
  {
    name = "SEN.bmp", width = 64, height = 240,
    parts = {
      { offset = 0x00F940, rows = 80 },   -- silhouette
      { offset = 0x010D40, rows = 80 },   -- silhouette
      { offset = 0x012140, rows = 80 },   -- colour
    },
    records = { 7, 8, 9 },
  },
  {
    name = "MARK.bmp", width = 24, height = 24,
    parts = { { offset = 0x013540, rows = 24 } },
    records = { 10 },
  },
  {
    name = "CAPTION.bmp", width = 160, height = 24,
    parts = { { offset = 0x013780, rows = 24 } },
    records = { 11 },
  },
}

-- Which sprite record places each image, for the `file` column of LAYOUT.csv.
-- A glyph is drawn once per copy it has in the block, and the copies are not
-- adjacent, so each image lists its records by index rather than relying on the
-- order of `parts`.
local RECORD_OWNER = {}
for _, image in ipairs(IMAGES) do
  for _, index in ipairs(image.records or {}) do
    RECORD_OWNER[index] = image.name
  end
end

local function prefix(args)
  local value
  if type(args) == "table" then value = args.prefix else value = args end
  if not value or value == "" then value = "INTRO_LOGO" end
  return (value:gsub("/+$", ""))
end

local function part_bytes(image, part)
  return part.rows * image.width
end

-- The BMP header's dimensions, without parsing the whole file: used to tell the
-- two accepted orientations of SAKURA.bmp apart before reading its pixels.
local function bmp_dimensions(data)
  if type(data) ~= "string" or #data < 26 or data:sub(1, 2) ~= "BM" then
    return nil, nil
  end
  local width, height = string.unpack("<i4i4", data, 19)
  return width, math.abs(height)
end

local be_i16, records_offset        -- defined with the rest of the table reader

local function rect_bytes(rect)
  return string.pack(">i2i2i2i2", rect[1], rect[2], rect[3], rect[4])
end

-- Does this artwork use the image's alternate geometry (the turned サクラ)?
local function turned_artwork(image, picture)
  if not image.alternate then return false end
  local width, height = bmp_dimensions(picture)
  return width == image.alternate.width and height == image.alternate.height
end

-- And does the file itself already carry the turned record, so decode() hands
-- back the artwork in the orientation the build was made with?
local function turned_record(image, data)
  if not image.alternate then return false end
  local table_at = records_offset(data)
  if not table_at then return false end
  local at = table_at + image.alternate.slots[1] * RECORD_BYTES
  return data:sub(at + 1, at + 8) == rect_bytes(image.alternate.horizontal)
end

local function geometry_of(image, turned)
  if turned and image.alternate then
    return image.alternate.width, image.alternate.height, image.alternate.parts
  end
  return image.width, image.height, image.parts
end

-- A BMP palette is BGRA; LOGO.SH2 stores big-endian BGR555 words.
local function bmp_to_bgr555(pal_bgra, colours)
  if type(pal_bgra) ~= "string" or #pal_bgra < colours * 4 then
    error("intro_logo: artwork palette is incomplete", 0)
  end
  local out = {}
  for i = 0, colours - 1 do
    local b = pal_bgra:byte(i * 4 + 1) // 8
    local g = pal_bgra:byte(i * 4 + 2) // 8
    local r = pal_bgra:byte(i * 4 + 3) // 8
    local v = (b << 10) | (g << 5) | r
    out[i * 2 + 1] = v >> 8
    out[i * 2 + 2] = v & 0xFF
  end
  return string.char(table.unpack(out))
end

local function decompress(data)
  if type(data) ~= "string" then
    error("intro_logo: expected a binary string", 0)
  end
  if #data < BLOCK_OFFSET + BLOCK_SLOT then
    error("intro_logo: input LOGO.SH2 is too short for the intro logo block", 0)
  end

  local ok, decoded = pcall(function()
    return prs:decode(data:sub(BLOCK_OFFSET + 1, BLOCK_OFFSET + BLOCK_SLOT))[1].data
  end)
  if not ok then
    error("intro_logo: the block at 0x25410 is not a PRS stream: " .. tostring(decoded), 0)
  end
  if #decoded ~= BLOCK_BYTES then
    error(string.format(
      "intro_logo: the block at 0x25410 decompresses to %d bytes, expected %d",
      #decoded, BLOCK_BYTES), 0)
  end
  for _, image in ipairs(IMAGES) do
    local rows = 0
    for _, part in ipairs(image.parts) do
      rows = rows + part.rows
      if part.offset + part_bytes(image, part) > BLOCK_BYTES then
        error("intro_logo: an artwork region lies outside the block", 0)
      end
    end
    if rows ~= image.height then
      error(string.format("intro_logo: %s is %d rows, its parts total %d",
        image.name, image.height, rows), 0)
    end
  end
  return decoded
end

function be_i16(data, at)
  local value = data:byte(at + 1) * 256 + data:byte(at + 2)
  if value >= 0x8000 then value = value - 0x10000 end
  return value
end

-- Where this build keeps its sprite table, or nil when neither address holds
-- twelve records that could be sprites.
function records_offset(data)
  for _, base in ipairs(RECORD_SLOTS) do
    local ok = base + RECORD_COUNT * RECORD_BYTES <= #data
    if ok then
      for index = 0, RECORD_COUNT - 1 do
        local at = base + index * RECORD_BYTES
        local w, h = be_i16(data, at + 4), be_i16(data, at + 6)
        if w < 1 or w > 256 or h < 1 or h > 256 then ok = false break end
      end
    end
    if ok then return base end
  end
  return nil
end

local function sprite_rect(data, base, index)
  local at = base + index * RECORD_BYTES
  return be_i16(data, at), be_i16(data, at + 2), be_i16(data, at + 4), be_i16(data, at + 6)
end

local function palette_at(data, index)
  local at = PALETTE_OFFSET + index * PALETTE_BYTES
  return bmp.from_bgr555(data:sub(at + 1, at + PALETTE_BYTES), 256)
end

local function swirl_sheet(data)
  local ok, decoded = pcall(function()
    return prs:decode(data:sub(SWIRL_OFFSET + 1, SWIRL_OFFSET + SWIRL_SLOT))[1].data
  end)
  if not ok or type(decoded) ~= "string" or #decoded ~= SWIRL_BYTES then
    return nil
  end
  return decoded
end

-- The map at 0x251F8: 133 cells, each a tile index * 2, big endian.
local function swirl_cells(data)
  local cells = {}
  for cell = 0, SWIRL_CELLS - 1 do
    local at = SWIRL_MAP + cell * 4
    local value = data:byte(at + 1) * 0x1000000 + data:byte(at + 2) * 0x10000
      + data:byte(at + 3) * 0x100 + data:byte(at + 4)
    local tile = value // 2
    if tile >= SWIRL_TILES then
      error(string.format(
        "intro_logo: cell %d of the map at 0x251F8 names tile %d, but the sheet "
        .. "holds %d", cell, tile, SWIRL_TILES), 0)
    end
    cells[cell + 1] = tile
  end
  return cells
end

-- Which arrangement of the fan the module asks for.  Retail calls its setup
-- with (19, 7), and that layer is rotated: the artwork is stored transposed to
-- compensate, so cells run down the columns and a tile's 64 bytes are
-- column-major.  The US build calls with (7, 19) -- the same two words the
-- motion patch writes -- which takes the rotation away, and then the identical
-- artwork has to be stored plainly: cells across the rows, each tile eight rows
-- of eight pixels.  Writing the retail arrangement into a module that asks for
-- the swapped pair is what made the fan come out as shreds.
local function swirl_turned(data)
  local word = data:sub(MOTION.columns.at + 1, MOTION.columns.at + 2)
  return word == MOTION.columns.turned
end

-- One cell of the picture, as the 64 bytes the sheet stores for it.
local function cell_bytes(picture, cell, turned)
  local bytes = {}
  if turned then
    local x, y = (cell % SWIRL_COLUMNS) * 8, (cell // SWIRL_COLUMNS) * 8
    for row = 0, 7 do
      for column = 0, 7 do
        bytes[#bytes + 1] = picture:sub((y + row) * SWIRL_WIDTH + x + column
          + 1, (y + row) * SWIRL_WIDTH + x + column + 1)
      end
    end
  else
    local x, y = (cell // SWIRL_ROWS) * 8, (cell % SWIRL_ROWS) * 8
    for column = 0, 7 do
      for row = 0, 7 do
        bytes[#bytes + 1] = picture:sub((y + row) * SWIRL_WIDTH + x + column
          + 1, (y + row) * SWIRL_WIDTH + x + column + 1)
      end
    end
  end
  return table.concat(bytes)
end

-- Tile bank + map -> picture: 19 cells across, 7 down.
local function untiled(sheet, cells, turned)
  local rows = {}
  for row = 0, SWIRL_HEIGHT - 1 do
    local pieces = {}
    local within = row % 8
    for column = 0, SWIRL_COLUMNS - 1 do
      local cell = turned and (row // 8) * SWIRL_COLUMNS + column
        or column * SWIRL_ROWS + (row // 8)
      local tile = cells[cell + 1]
      local line = {}
      for pixel = 0, 7 do
        local at = turned and tile * SWIRL_TILE + within * 8 + pixel
          or tile * SWIRL_TILE + pixel * 8 + within
        line[#line + 1] = sheet:sub(at + 1, at + 1)
      end
      pieces[#pieces + 1] = table.concat(line)
    end
    rows[#rows + 1] = table.concat(pieces)
  end
  return table.concat(rows)
end

-- Picture -> tile sheet, plus a replacement map when the sheet had to be renumbered.
-- Every cell first keeps the slot the retail map gave it, so an untouched picture
-- rebuilds the shipped bytes exactly.
local function retiled(picture, sheet, cells, turned)
  local slots, consistent = {}, true
  for cell = 0, SWIRL_CELLS - 1 do
    local bytes = cell_bytes(picture, cell, turned)
    local slot = cells[cell + 1]
    if slots[slot + 1] == nil then
      slots[slot + 1] = bytes
    elseif slots[slot + 1] ~= bytes then
      consistent = false
    end
  end

  if consistent then
    local body = {}
    for slot = 0, SWIRL_TILES - 1 do
      body[#body + 1] = slots[slot + 1]
        or sheet:sub(slot * SWIRL_TILE + 1, (slot + 1) * SWIRL_TILE)
    end
    return table.concat(body), nil
  end

  -- Two cells that shared a tile no longer match: renumber the whole sheet.
  -- Tile 0 stays empty and the map names tiles from 1, which is how the retail
  -- sheet is numbered -- the module never asks for tile 0.
  local by_content, body, map = {}, { string.rep("\x00", SWIRL_TILE) }, {}
  local count = 1
  for cell = 0, SWIRL_CELLS - 1 do
    local bytes = cell_bytes(picture, cell, turned)
    local slot = by_content[bytes]
    if slot == nil then
      if count >= SWIRL_TILES then
        error(string.format(
          "intro_logo: the picture now needs more than the %d tiles the sheet "
          .. "holds; reuse indices or raise the 1,644-byte slot", SWIRL_TILES), 0)
      end
      slot = count
      count = count + 1
      by_content[bytes] = slot
      body[slot + 1] = bytes
    end
    map[cell + 1] = slot
  end

  local encoded = {}
  for cell = 0, SWIRL_CELLS - 1 do
    local value = map[cell + 1] * 2
    encoded[#encoded + 1] = string.char(value >> 24 & 0xFF, value >> 16 & 0xFF,
      value >> 8 & 0xFF, value & 0xFF)
  end
  local joined = table.concat(body)
  return joined .. string.rep("\x00", SWIRL_BYTES - #joined), table.concat(encoded)
end

function codec.can_handle(data)
  return can_handle.can_handle_logo_sh2(data)
end

function codec.decode_name(args)
  return (prefix(args))
end

function codec.decode(data, args)
  local buffer = decompress(data)
  local palette = palette_at(data, PAINT_SLOT)
  local dir = prefix(args)

  local artifacts = {}
  artifacts[#artifacts + 1] = {
    name = dir .. "/" .. SWIRL_NAME,
    data = bmp.build(untiled(swirl_sheet(data), swirl_cells(data),
      swirl_turned(data)), SWIRL_WIDTH, SWIRL_HEIGHT, BPP, palette),
  }

  local table_at = records_offset(data)
  if not table_at then
    error("intro_logo: no VDP1 sprite table found at 0x70A0 or 0x6260", 0)
  end
  local layout = { "index,x,y,w,h,file" }
  for index = 0, RECORD_COUNT - 1 do
    local x, y, w, h = sprite_rect(data, table_at, index)
    layout[#layout + 1] = string.format("%d,%d,%d,%d,%d,%s", index, x, y, w, h,
      RECORD_OWNER[index] or "")
  end
  artifacts[#artifacts + 1] = {
    name = dir .. "/" .. LAYOUT_NAME,
    data = table.concat(layout, "\n") .. "\n",
  }

  for _, image in ipairs(IMAGES) do
    local turned = turned_record(image, data)
    local width, height, parts = geometry_of(image, turned)
    local pixels = {}
    for _, part in ipairs(parts) do
      pixels[#pixels + 1] = buffer:sub(part.offset + 1, part.offset + part.rows * width)
    end
    artifacts[#artifacts + 1] = {
      name = dir .. "/" .. image.name,
      data = bmp.build(table.concat(pixels), width, height, BPP, palette),
    }
  end

  return artifacts
end

function codec.encode(original, artifacts, args)
  local buffer = decompress(original)
  local dir = prefix(args)

  local by_name = {}
  for _, artifact in ipairs(artifacts or {}) do
    if type(artifact) == "table" then by_name[artifact.name] = artifact.data end
  end

  local sheet = swirl_sheet(original)
  if not sheet then
    error("intro_logo: the layer at 0x24B8C is not a 5,888-byte PRS stream", 0)
  end
  local cells = swirl_cells(original)
  local table_at = records_offset(original)
  if not table_at then
    error("intro_logo: no VDP1 sprite table found at 0x70A0 or 0x6260", 0)
  end
  local edited_sheet = sheet
  local edited_map
  local edited = buffer
  local palettes = {}                  -- every palette the build was handed
  local changed = false
  local records = {}

  -- The layer's arrangement and the motion arguments are one decision: the
  -- swapped (7, 19) pair is what rotates the layer, and the artwork is then
  -- stored plainly to compensate.  A SAKURA.bmp that says which orientation it
  -- wants makes the decision; otherwise the module's own words do.
  local turned_sakura                  -- nil: no SAKURA.bmp supplied
  for _, image in ipairs(IMAGES) do
    if image.alternate then
      local picture = by_name[dir .. "/" .. image.name]
      if picture then         turned_sakura = turned_artwork(image, picture) end
    end
  end
  local turned_layer = turned_sakura
  if turned_layer == nil then turned_layer = swirl_turned(original) end

  local swirl_picture = by_name[dir .. "/" .. SWIRL_NAME]
  if swirl_picture then
    local pixels, palette = bmp.parse(swirl_picture, SWIRL_WIDTH, SWIRL_HEIGHT, BPP)
    local next_sheet, next_map = retiled(pixels, sheet, cells, turned_layer)
    if next_sheet ~= sheet then edited_sheet = next_sheet end
    edited_map = next_map
    palettes[#palettes + 1] = { name = SWIRL_NAME, palette = palette }
  end

  for _, image in ipairs(IMAGES) do
    local picture = by_name[dir .. "/" .. image.name]
    if picture then
      local turned = turned_artwork(image, picture)
      local width, height, parts = geometry_of(image, turned)
      local pixels, palette = bmp.parse(picture, width, height, BPP)
      palettes[#palettes + 1] = { name = image.name, palette = palette }
      -- Every part is written separately: the copies of a glyph are not adjacent
      -- in the block, and an untouched stage is skipped so its bytes stay
      -- exactly as shipped.
      local row = 0
      for _, part in ipairs(parts) do
        local size = part.rows * width
        local top = row * width + 1
        local part_pixels = pixels:sub(top, top + size - 1)
        local current = edited:sub(part.offset + 1, part.offset + size)
        if part_pixels ~= current then
          edited = edited:sub(1, part.offset) .. part_pixels
            .. edited:sub(part.offset + size + 1)
          changed = true
        end
        row = row + part.rows
      end

            -- The turned サクラ also needs its sprite records changed -- all three of
      -- them: the two flat states sit exactly where the colour copy does, which
      -- is why the word arrives in one piece instead of pausing on a blank.  The
      -- vertical artwork puts retail's rectangles back.
      if image.alternate then
        local rect = turned and image.alternate.horizontal or image.alternate.vertical
        local want = rect_bytes(rect)
        for _, slot in ipairs(image.alternate.slots) do
          local at = table_at + slot * RECORD_BYTES
          if original:sub(at + 1, at + 8) ~= want then
            records[#records + 1] = { at = at, bytes = want }
          end
        end
        turned_sakura = turned
      end

    end
  end

  -- The motion follows the orientation of that artwork, in both directions: the
  -- horizontal word gets the US call (it sweeps in across the middle), the
  -- vertical one puts retail's back.  Three words are written -- the map's two
  -- dimensions and the argument at 0x392A -- and only a file that carries one of
  -- the known signatures is touched, so a different revision of the module is
  -- left alone rather than guessed at.
  if turned_sakura ~= nil then
    for _, word in pairs(MOTION) do
      local current = original:sub(word.at + 1, word.at + 2)
      local want = turned_sakura and word.turned or word.vertical
      if current ~= want and (current == word.vertical or current == word.turned) then
        records[#records + 1] = { at = word.at, bytes = want }
      end
    end
  end

  -- The palette is fixed.  encode() never writes the five 512-byte palettes:
  -- the file's own grading at 0x29124 is kept byte for byte, whatever the BMP
  -- headers say.  A header that disagrees with it is refused rather than
  -- ignored, so an accidental recolour cannot pass silently.  The comparison is
  -- on the 5-bit result, so an editor that merely re-saves the same colours is
  -- accepted and writes nothing.
  local current_palette = original:sub(
    PALETTE_OFFSET + PAINT_SLOT * PALETTE_BYTES + 1,
    PALETTE_OFFSET + (PAINT_SLOT + 1) * PALETTE_BYTES)
  for _, entry in ipairs(palettes) do
    if bmp_to_bgr555(entry.palette, 256) ~= current_palette then
      error(string.format(
        "intro_logo: %s carries a palette the file does not have.  The logo "
        .. "screen's palette is not editable: encode keeps 0x%05X byte for byte "
        .. "and never writes CRAM.  Re-export the artwork with the palette the "
        .. "decoder wrote into its BMP header",
        entry.name, PALETTE_OFFSET + PAINT_SLOT * PALETTE_BYTES), 0)
    end
  end

  local out = original
  if edited_sheet ~= sheet then
    local compressed = prs:encode("", { { name = "SWIRL", data = edited_sheet } })
    if #compressed > SWIRL_SLOT then
      error(string.format(
        "encode: the compressed fan is %d bytes, %d over the %d-byte slot at "
        .. "0x24B8C.  Flatten the artwork or reuse indices; adding tiles would "
        .. "need the tile map at 0x251F8 rewritten too", #compressed,
        #compressed - SWIRL_SLOT, SWIRL_SLOT), 0)
    end
    compressed = compressed .. string.rep("\x00", SWIRL_SLOT - #compressed)
    out = out:sub(1, SWIRL_OFFSET) .. compressed
      .. out:sub(SWIRL_OFFSET + SWIRL_SLOT + 1)
  end

  if edited_map then
    out = out:sub(1, SWIRL_MAP) .. edited_map
      .. out:sub(SWIRL_MAP + #edited_map + 1)
  end

  if changed then
    local compressed = prs:encode("", { { name = "INTRO_LOGO", data = edited } })
    if #compressed > BLOCK_SLOT then
      error(string.format(
        "encode: compressed intro logo is %d bytes, %d over the %d-byte slot at "
        .. "0x25410.  Flatten the artwork or reuse indices", #compressed,
        #compressed - BLOCK_SLOT, BLOCK_SLOT), 0)
    end
    compressed = compressed .. string.rep("\x00", BLOCK_SLOT - #compressed)
    out = out:sub(1, BLOCK_OFFSET) .. compressed
      .. out:sub(BLOCK_OFFSET + BLOCK_SLOT + 1)
  end

  -- LAYOUT.csv goes last, so a hand-written position wins over the turned
  -- サクラ record above.
  local layout = by_name[dir .. "/" .. LAYOUT_NAME]
  if layout then
    for line in layout:gmatch("[^\r\n]+") do
      -- The trailing file name is documentation: it is not read back, so an
      -- older five-column line is still accepted.
      local index, x, y, w, h = line:match(
        "^%s*(%d+)%s*,%s*(-?%d+)%s*,%s*(-?%d+)%s*,%s*(-?%d+)%s*,%s*(-?%d+)")
      if index then
        index, x, y, w, h = tonumber(index), tonumber(x), tonumber(y),
          tonumber(w), tonumber(h)
        if index >= RECORD_COUNT then
          error(string.format(
            "intro_logo: LAYOUT.csv names sprite %d; the table at 0x6260 has %d",
            index, RECORD_COUNT), 0)
        end
        if w < 0 or h < 0 or w > 32767 or h > 32767
          or x < -32768 or x > 32767 or y < -32768 or y > 32767 then
          error(string.format(
            "intro_logo: LAYOUT.csv sprite %d is outside the 16-bit range",
            index), 0)
        end
        local at = table_at + index * RECORD_BYTES
        local want = rect_bytes({ x, y, w, h })
        if original:sub(at + 1, at + 8) ~= want then
          records[#records + 1] = { at = at, bytes = want }
        end
      end
    end
  end

  for _, record in ipairs(records) do
    out = out:sub(1, record.at) .. record.bytes
      .. out:sub(record.at + #record.bytes + 1)
  end

  return out
end

return codec
