--[[
  Sakura Taisen (Saturn) — Battle-menu VDP1 anchors

  PATCH plugin for SAKURA2/SLG.BIN and SAKURA2/0SLG.BIN.  This is the SLG half
  of PatchWKLFiles (SakuraTaisen.cpp:6668): when the command region of a WKL
  changes size, the VDP1 addresses the strategy-game program holds for the
  command art have to move by the same delta.

  ## Where the delta comes from

  Nothing is configured by hand.  Like the other *_metadata.lua plugins this one
  reads the workspace overrides of the file it describes -- the
  COMBAT/command_<block>_<image>.bmp canvases that
  scripts/combat_commands_gfx.lua produces, plus its CMD_MAIN.bmp sheet, which
  is one authored file for the whole disc -- and asks that codec for the region
  size they imply (combat_commands_gfx.region_size, built on its retail layout
  table).  A canvas with no override keeps its retail size, so a build with no
  command edit yields delta 0 and returns the executable untouched.

  The command region belongs to SLG.BIN, not to one WKL: the program holds a
  single set of anchors and every WKL is loaded where they point.  The anchors
  therefore follow the largest region any WKL implies, and a build where they
  disagree says so and lists the sizes it read.  A WKL with smaller art is
  harmless — it uploads at the same addresses and leaves a gap — but a region
  bigger than the anchors describe would run into the next VDP1 block.

  ## The sites

  Disc 1 (SakuraTaisen.cpp:7209-7250 and 7414-7427).  `textDelta` is zero in
  this build — FIX_SLG_FONT_DRAWING_SIZE is 1 — so every site takes the plain
  battle-menu delta:

      0x14058  u32  0x25C15D80   battle-menu cursor image
      0x140F0  u32  0x00015D80   the same address, 20-bit form
      0x14528  u32  0x25C15100   second cursor image
      0x10F8C  u32  0x25C17B00   battle sprites VDP1 address
      0xFF68   u32  0x00017B00   the same address, 20-bit form
      0x1070   u32  0x25C2B600   battle reaction sprites
      0x10FE4  u32  0x25C2B600   the same address again
      0xFF78   u32  0x0002B600   the same address, 20-bit form
      0x10A4   u32  0x0002B600   the same address, 20-bit form
      0x142A6  u16  0x2B10       face blink image, packed address / 8
      0x14434  u16  0x2B60       face blink image, packed address / 8
      0x1444C  u16  0x2A20       face blink image, packed address / 8

  Packed u16 fields are VDP1 addresses divided by 8, so the codec applies the
  delta in address units and re-divides, as PatchWKLFiles does
  (`((offset<<3) + delta) >> 3`).  That is only exact for a delta that is a
  multiple of 8; anything else would misalign a sprite, so such a delta is
  refused.  In practice it cannot arise: every command image is padded to a
  whole number of 8-byte VDP1 characters, so every block, region and delta is a
  multiple of 8.

  PatchWKLFiles also rewrites the two dialogue-text addresses (0x21590 and
  0x219C4) in both executables, but only by `textDelta`, which is zero here.
  They are not anchors of this codec: scripts/SLG/patch_vwf_font.lua owns them
  and has already moved the font to 0x25C43600 by the time this codec runs, so
  writing them from a retail base would be wrong.

  ## Where the command labels sit

  The six battle-menu commands are placed by a small data block in the
  executable, at 0x46C60 in both files (the block PatchWKLFiles writes from its
  BattleMenuFormatting.bin when USE_LARGE_BATTLE_MENU is on; it is off in the
  reference build, which is why their labels stay 16 pixels wide):

      { i16 x; i16 y; u16 pad; u16 entries }   x 6, at 0x46C60

  x is the popup's left edge, y = -16 * (entries - 1) lifts the label clear of
  its submenu, and entries counts that submenu including its cancel row.  The
  retail x values are 0, 16, 32, 48, 64, 88: a 16-pixel pitch, with 8 pixels of
  extra space before 特.

  The labels themselves are drawn where each command's entry list says, 8
  pixels right of that popup edge: six lists of

      { u16 pad; i16 x; i16 y; u16 pad; u16 image }   10 bytes per entry

  at the offsets the table at 0x46E0C points to, with retail x 8, 24, 40, 56,
  72, 96.  Patching only 0x46C60 therefore slides the popups while the labels
  stay put; both have to move together.

  Two more tables repeat those columns, and both have to follow:

      0x46C90  { u16 image; u16 x; u16 y; u16 pad } x 6
               the main-command panel's own label list
      0x46E3C  { u16 0; i16 x1; u16 0; i16 y1; u16 0; i16 x2; u16 0; i16 y2 } x 6
               the selection box drawn for each command (16 pixels wide)

  A sheet whose cells are wider than 16 pixels cannot fit that pitch, so this
  codec rewrites the six popup x values, the x of every entry in the six lists,
  the panel's six x values and both edges of the six selection boxes from the
  sheet's cell width, keeping the retail gaps (popups 0, 32, 64, 96, 128, 168;
  labels, entries and panel 8, 40, 72, 104, 136, 176; boxes one cell wide).  y,
  images and entry counts are left alone, and a table that holds anything else
  is an error rather than silently overwritten.

  ## The right-edge clamp

  FUN_06029254 (case 0) builds the menu anchor from the acting unit's position
  and clamps it against two 16.16 bounds: 0x060293D8 = 0xFF600000 (-160.0) and
  0x060293DC = 0x00300000 (+48.0, file 0x253DC).  The upper bound is what keeps
  the panel off the right edge of the screen: with the retail art the rightmost
  pixel the panel draws is 128 pixels right of the anchor, so +48 puts that edge
  at 176 of the 320.  Widen the art and the edge walks right one for one --
  which is what happened when the French menu grew.

  The reference tool's `USE_LARGE_BATTLE_MENU` patch hit the same wall and
  solved it by hand: it overwrites 0x253DC with 0xFFA0 (-96.0) and drops a
  32-pixel-pitch BattleMenuFormatting.bin at 0x46C60.  So the knob is a fixed
  pixel budget and it moves *left*, not right -- a wider menu has to start
  further from the unit, never closer to the screen edge.

  This codec derives the bound instead: it measures the widest thing the panel
  draws (the bar, every label, every popup box) from the pool art and the
  layout it is about to write, and lowers the bound by however much that grew
  past the retail 128.

      0x253DC  u16  high half of the 16.16 bound   0x0030 (+48) retail

  A retail build therefore leaves the byte alone, and any width change keeps
  the panel's right edge where retail puts it.

  ## The "x n" count

  Cover's "x8" count is placed by `add #24,r1` at 0x2512A, whose
  immediate byte is at 0x2512B.  The code loads the command's x from the panel
  table at 0x46C90 and adds that immediate, so the count starts label width plus
  a gap right of the column (retail labels are 16 wide: 16 + 8 = 24 = 0x18).

  The reference tool writes 0x30 (48) there as `itemCountXOffset`, but only
  under `#if !FIX_SLG_FONT_DRAWING_SIZE`: with its 16-pixel text labels that is
  the same 16 + 32, and this build's VWF font fix compiles the write out.  Its
  `USE_LARGE_BATTLE_MENU` block moves the clipping bound and the command pitch,
  not the count.

  The panel table is already moved with CMD_MAIN.bmp.  The count immediate is
  therefore its cell width plus the retail 8-pixel gap, not a submenu width.
  Repair draws its `x` and digit with separate instructions, 8 pixels apart.

  ## The confirmation dialog

  The START menu's confirmation box (WKL block 14, MENU_CONFIRM_*) is placed by
  two copies of one routine, RETRY at 0x25AF4 and QUIT at 0x25C50.  Each starts
  with the panel's anchor as instruction immediates (`mov #-52,r10` /
  `mov.w r10,@r14` at 0x25B02 and 0x25C5E for xa, `mov #-28,r10` at 0x25B0A and
  0x25C66 for ya), then copies a 16-byte table of `{ colr, dx, dy, flag }` --
  panel, title, YES, NO -- and appends two inline entries for the hover.

  A child is drawn at anchor + (dx, dy); the offsets are unsigned bytes, so
  every child sits right of and below the panel's origin, and the anchor is
  what moves the whole box.  Both hover entries share one dy immediate, so YES
  and NO have to stay on one row.

  Their positions live in `<workspace>/combat/commands/MENU_CONFIRM.json`:

      {
        "MENU_CONFIRM": {
          "00_BG":    { "x": -52, "y": -28 },
          "01_RETRY": { "x": -44, "y": -20 },
          "02_QUIT":  { "x": -44, "y": -20 },
          "03_YES":   { "x": -44, "y":   4 },
          "04_NO":    { "x":   4, "y":   4 }
        }
      }

  x/y are screen positions in the VDP1 space the packets use: (0,0) is the
  centre of the 320x224 screen, +x right, +y down.  The retail 104x56 panel at
  (-52,-28) therefore starts at screen x 108 and y 84, centred both ways.  The
  file is only read when it exists: a workspace without it keeps retail
  geometry.  Children cannot be placed left of or above the panel, and a layout
  that puts YES and NO on different rows is refused.

  ## Identification and idempotence

  can_handle uses the exact SHA-256 of the disc-1 executable from
  shared/constants.lua (`certain`), falling back to the site pattern for a file
  this codec already shifted (`possible`).  decode() and encode() read the delta
  currently applied from the sites themselves — all fourteen must agree — and
  encode() moves from that value to the one the canvases imply, so running it
  twice, or resizing the art again, is safe.

  The block PatchWKLFiles anchors highest is 0x25C2B600, and it deliberately
  leaves the block at 0x25C49100 alone, so the delta may not exceed 0x1DB00
  bytes (121,600).  Given the art this margin is ample; exceeding it is an
  error, not a silently overlapping upload.

  EVT address fixups (FIX_EVT_FILES) are not part of this build, so this codec
  touches only the two executables.
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

local can_handle = load_shared("can_handle")
-- The sibling codec, for the retail layout table and the workspace canvas
-- sizes: both plugins must agree on what a command region weighs.
local gfx = load_shared("../combat_commands_gfx")

local codec = {}

codec.name        = "Sakura Taisen Battle-Menu VDP1 Anchors"
codec.description = "PATCH plugin for SAKURA2/SLG.BIN and 0SLG.BIN that moves the "
                 .. "battle-menu VDP1 addresses by the delta the command canvases imply"
codec.version     = 6
codec.kind        = "patch"

local LABEL = "combat_commands_metadata"


-- The six main command labels' placement, as data at 0x46C60 in both
-- executables.  See "Where the command labels sit" above.
local LAYOUT          = 0x46C60
local LAYOUT_STRIDE   = 8
local LAYOUT_RETAIL_X = { 0, 16, 32, 48, 64, 88 }
local LAYOUT_ENTRIES  = { 2, 3, 4, 4, 2, 2 }
local LAYOUT_PITCH    = 16

-- Each command's entries follow its label as { u16 pad; i16 x; i16 y; u16 pad;
-- u16 image }, 10 bytes each, at the offsets the parallel table at 0x46E0C
-- points to.  These x values are where the label *and* its entries are drawn:
-- the label's own x from 0x46C60 is 8 pixels less, the popup's left edge.
local LAYOUT_LISTS = {
  { offset = 0x46CC2, count = 2, x = 8 },
  { offset = 0x46CFE, count = 3, x = 24 },
  { offset = 0x46D1C, count = 4, x = 40 },
  { offset = 0x46D44, count = 4, x = 56 },
  { offset = 0x46D80, count = 2, x = 72 },
  { offset = 0x46D6C, count = 2, x = 96 },
}
local LAYOUT_ENTRY_STRIDE = 10
local LAYOUT_LABEL_GAP    = 8

-- The main-command panel: one record per command, { u16 image; u16 x; u16 y;
-- u16 pad } at 0x46C90, and the panel's selection box for that command,
-- { u16 0; i16 x1; u16 0; i16 y1; u16 0; i16 x2; u16 0; i16 y2 } at 0x46E3C.
-- Both start their columns at the entry x.
local LAYOUT_PANEL = 0x46C90
local LAYOUT_PANEL_STRIDE = 8
local LAYOUT_RECTS = 0x46E3C
local LAYOUT_RECT_STRIDE = 16
local LAYOUT_RECT_Y1 = 8
local LAYOUT_RECT_Y2 = 24
local LAYOUT_RECT_WIDTH = 16

-- PatchWKLFiles moves anchors as high as 0x25C2B600 and leaves the block at
-- 0x25C49100 in place.
local MAX_DELTA = 0x1DB00

local SITES = {
  { offset = 0x14058, kind = "u32", value = 0x25C15D80, what = "battle-menu cursor image" },
  { offset = 0x140F0, kind = "u32", value = 0x00015D80, what = "battle-menu cursor image (20-bit)" },
  { offset = 0x14528, kind = "u32", value = 0x25C15100, what = "second cursor image" },
  { offset = 0x10F8C, kind = "u32", value = 0x25C17B00, what = "battle sprites" },
  { offset = 0x0FF68, kind = "u32", value = 0x00017B00, what = "battle sprites (20-bit)" },
  { offset = 0x01070, kind = "u32", value = 0x25C2B600, what = "battle reaction sprites" },
  { offset = 0x10FE4, kind = "u32", value = 0x25C2B600, what = "battle reaction sprites (copy)" },
  { offset = 0x0FF78, kind = "u32", value = 0x0002B600, what = "battle reaction sprites (20-bit)" },
  { offset = 0x010A4, kind = "u32", value = 0x0002B600, what = "battle reaction sprites (20-bit copy)" },
  { offset = 0x142A6, kind = "u16", value = 0x2B10,    what = "face blink image, address / 8" },
  { offset = 0x14434, kind = "u16", value = 0x2B60,    what = "face blink image, address / 8" },
  { offset = 0x1444C, kind = "u16", value = 0x2A20,    what = "face blink image, address / 8" },
}

local function read_u16(data, offset)
  if offset + 2 > #data then
    error(string.format("%s: u16 at 0x%X is outside the file", LABEL, offset), 0)
  end
  return string.unpack(">I2", data, offset + 1)
end

local function read_u32(data, offset)
  if offset + 4 > #data then
    error(string.format("%s: u32 at 0x%X is outside the file", LABEL, offset), 0)
  end
  return string.unpack(">I4", data, offset + 1)
end

local function read_site(data, site)
  if site.kind == "u16" then return read_u16(data, site.offset) end
  return read_u32(data, site.offset)
end

-- The value a site holds once `delta` bytes have been added to the VDP1
-- layout.  Packed addresses are divided by 8, so the delta is added in address
-- units first, exactly as PatchWKLFiles computes it.
local function shifted(site, delta)
  if site.kind == "u16" then
    local address = site.value * 8 + delta
    if address < 0 then return nil end
    local packed = address // 8
    if packed > 0xFFFF then return nil end
    return packed & 0xFFFF
  end
  local address = site.value + delta
  if address < 0 or address > 0xFFFFFFFF then return nil end
  return address
end

local function describe(site, value)
  if site.kind == "u16" then
    return string.format("0x%04X", value)
  end
  return string.format("0x%08X", value)
end

-- The delta currently applied to the file, or nil when some site holds a value
-- this codec does not know.  All sites must agree on one delta.
local function applied_delta(data)
  local first = SITES[1]
  local delta = read_site(data, first) - first.value

  for _, site in ipairs(SITES) do
    local expected = shifted(site, delta)
    if expected == nil or read_site(data, site) ~= expected then
      return nil, site
    end
  end
  return delta
end

local function report(data, offender)
  local lines = {}
  if offender then
    lines[#lines + 1] = string.format("  0x%06X (%s) holds %s",
      offender.offset, offender.what, describe(offender, read_site(data, offender)))
  end
  for _, site in ipairs(SITES) do
    lines[#lines + 1] = string.format("  0x%06X  %-42s %s",
      site.offset, site.what, describe(site, read_site(data, site)))
  end
  return table.concat(lines, "\n")
end

-- The region size the command art implies.  Every WKL is rebuilt on its own
-- from the same pool, so the anchors and the art come from one folder.
local function canvas_region_size()
  local workspace = LUDARED and LUDARED.WORKSPACE
  if not workspace then return gfx.retail_region end

  local directory = workspace .. "/combat/commands"
  local file = io.open(directory .. "/CMD_MAIN.bmp", "rb")
  if not file then return gfx.retail_region end
  file:close()

  return gfx.region_size(directory, gfx.pool_sheets())
end

local function check_delta(delta)
  if delta > MAX_DELTA then
    error(string.format(
      "%s: a delta of %d bytes is past the %d VDP1 has before the block at "
      .. "0x25C49100", LABEL, delta, MAX_DELTA), 0)
  end
  if delta % 8 ~= 0 then
    error(string.format(
      "%s: a delta of %d bytes is not a multiple of 8; the packed face-image "
      .. "offsets are stored in eighths.  Pad the changed art by %d byte%s",
      LABEL, delta, (-delta) % 8, (-delta) % 8 == 1 and "" or "s"), 0)
  end
end

local function apply(data, from, to, stage)
  check_delta(to)

  local out = data
  for _, site in ipairs(SITES) do
    local current  = read_site(data, site)
    local expected = shifted(site, from)
    local wanted   = shifted(site, to)

    if wanted == nil then
      error(string.format("%s: %s: 0x%06X (%s) would not fit",
        LABEL, stage, site.offset, site.what), 0)
    end
    if current ~= expected then
      error(string.format(
        "%s: %s: 0x%06X (%s) holds %s, but a %d-byte delta implies %s\n%s",
        LABEL, stage, site.offset, site.what, describe(site, current),
        from, describe(site, expected), report(data, site)), 0)
    end

    if site.kind == "u16" then
      out = out:sub(1, site.offset) .. string.pack(">I2", wanted) .. out:sub(site.offset + 3)
    else
      out = out:sub(1, site.offset) .. string.pack(">I4", wanted) .. out:sub(site.offset + 5)
    end
  end
  return out
end

-- The cell width the main-command sheet gives the labels, or nil when no
-- sheet is in the workspace.
local function layout_cell_width()
  local sheets = gfx.pool_sheets()
  local main   = gfx.sheets and gfx.sheets[1]
  if not (sheets and main) then return nil end
  local sheet = sheets[main.file]
  if not sheet then return nil end
  return sheet.cell_width
end

-- The x each command's label starts at for a given cell width, keeping the
-- retail gaps (the last label sits 8 pixels past the previous one's edge).
local function layout_positions(cell_width)
  local xs, at = {}, 0
  for i, retail in ipairs(LAYOUT_RETAIL_X) do
    xs[i] = at + (retail - (i - 1) * LAYOUT_PITCH)
    at = at + cell_width
  end
  return xs
end

-- The x a command's entries are drawn at for a given cell width, keeping the
-- retail relationship with the label (gap of 8, and 特 pushed 8 further).
local function entry_positions(cell_width)
  local xs = layout_positions(cell_width)
  for i = 1, #xs do xs[i] = xs[i] + LAYOUT_LABEL_GAP end
  return xs
end

-- Rewrite the six label positions.  The block must still be the retail one (or
-- already carry the values this cell width asks for), so a file from another
-- build is refused instead of overwritten.
local function apply_layout(data, cell_width, stage)
  if #data < LAYOUT + #LAYOUT_RETAIL_X * LAYOUT_STRIDE then
    error(LABEL .. ": " .. stage .. ": file too short for the command layout", 0)
  end

  local xs  = layout_positions(cell_width)
  local out = data

  for i = 1, #xs do
    local at      = LAYOUT + (i - 1) * LAYOUT_STRIDE
    local x       = string.unpack(">i2", data, at + 1)
    local entries = read_u16(data, at + 6)
    local pad     = read_u16(data, at + 4)

    if pad ~= 0 or entries ~= LAYOUT_ENTRIES[i]
        or (x ~= LAYOUT_RETAIL_X[i] and x ~= xs[i]) then
      error(string.format(
        "%s: %s: the command layout at 0x%X does not look like the retail one "
        .. "(command %d holds x=%d, pad=%d, entries=%d)",
        LABEL, stage, at, i - 1, x, pad, entries), 0)
    end

    if x ~= xs[i] then
      out = out:sub(1, at) .. string.pack(">i2", xs[i]) .. out:sub(at + 3)
    end
  end

  return out
end

-- The main-command panel's label positions: { image; x; y; pad } at 0x46C90.
local function apply_panel(data, cell_width, stage)
  local xs  = entry_positions(cell_width)
  local out = data

  for i = 1, #xs do
    local at = LAYOUT_PANEL + (i - 1) * LAYOUT_PANEL_STRIDE
    if at + LAYOUT_PANEL_STRIDE > #data then
      error(LABEL .. ": " .. stage .. ": file too short for the command panel", 0)
    end

    local x = string.unpack(">i2", data, at + 3)
    local y = read_u16(data, at + 4)
    if y ~= LAYOUT_RECT_Y1 or read_u16(data, at + 6) ~= 0
        or (x ~= LAYOUT_LISTS[i].x and x ~= xs[i]) then
      error(string.format(
        "%s: %s: the command panel at 0x%X does not look like the retail one "
        .. "(command %d holds x=%d, y=%d)",
        LABEL, stage, at, i - 1, x, y), 0)
    end

    if x ~= xs[i] then
      out = out:sub(1, at + 2) .. string.pack(">i2", xs[i]) .. out:sub(at + 5)
    end
  end

  return out
end

-- The selection box of each command in that panel, at 0x46E3C.  Retail boxes
-- are 16 pixels wide, one per label; they follow the label columns.
local function apply_rects(data, cell_width, stage)
  local xs  = entry_positions(cell_width)
  local out = data

  for i = 1, #xs do
    local at = LAYOUT_RECTS + (i - 1) * LAYOUT_RECT_STRIDE
    if at + LAYOUT_RECT_STRIDE > #data then
      error(LABEL .. ": " .. stage .. ": file too short for the selection boxes", 0)
    end

    local check = { 0, 4, 8, 12 }
    for _, k in ipairs(check) do
      if read_u16(data, at + k) ~= 0 then
        error(string.format(
          "%s: %s: the selection boxes at 0x%X do not look like the retail ones",
          LABEL, stage, at), 0)
      end
    end

    local x1 = string.unpack(">i2", data, at + 3)
    local y1 = string.unpack(">i2", data, at + 7)
    local x2 = string.unpack(">i2", data, at + 11)
    local y2 = string.unpack(">i2", data, at + 15)

    local want1 = xs[i]
    local want2 = want1 + cell_width
    if y1 ~= LAYOUT_RECT_Y1 or y2 ~= LAYOUT_RECT_Y2
        or (x1 ~= LAYOUT_LISTS[i].x and x1 ~= want1)
        or (x2 ~= LAYOUT_LISTS[i].x + LAYOUT_RECT_WIDTH and x2 ~= want2) then
      error(string.format(
        "%s: %s: the selection box at 0x%X does not look like the retail one "
        .. "(command %d holds %d,%d-%d,%d)",
        LABEL, stage, at, i - 1, x1, y1, x2, y2), 0)
    end

    if x1 ~= want1 then
      out = out:sub(1, at + 2) .. string.pack(">i2", want1) .. out:sub(at + 5)
    end
    if x2 ~= want2 then
      out = out:sub(1, at + 10) .. string.pack(">i2", want2) .. out:sub(at + 13)
    end
  end

  return out
end

-- How far right of the menu anchor the panel draws, in pixels: the widest of
-- the bar, the command labels and the popup boxes those labels open, using the
-- art in the pool and the layout this codec writes.  Retail works out to 128
-- (the last popup starts at 88 and its box is 40 wide).
local RETAIL_EXTENT = 128

-- 0x253DC holds the high half of the 16.16 upper bound of the menu anchor, in
-- FUN_06029254's case 0; retail holds 0x0030 (+48.0).
local CLIP           = 0x253DC
local CLIP_RETAIL    = 0x0030

-- Immediate bytes for Cover, then Repair's `x` and digit.
local ACTION_COUNT_COVER = 0x2512B
local ACTION_COUNT_REPAIR = { 0x250E5, 0x250AD }

-- The START menu panel is the one panel drawn by code rather than by a layout
-- table.  FUN_06029F08 builds its VDP1 command at 0x06029F36 with
-- `mov #-32,r10 / mov.w r10,@r14` for xa and `mov #-28,r10` at 0x25F40 for ya:
-- the half of the retail 64x56 panel.  The sprite's *size*, on the other hand,
-- comes from the WKL battle-menu image header (width, height), so widening
-- MENU_START_00_BG leaves xa at -32 and grows the panel to the right of the
-- screen's centre.  This codec rewrites the xa immediate to -(width/2).
--
-- Checked on a running build: with the immediate patched in RAM the game's own
-- packet at 0x060600E0 reports xa 0xFFC8 (-56) instead of 0xFFE0, and it stays
-- there across frames because the routine rewrites it from the instruction.
local START_X            = 0x25F37   -- low byte of `mov #-32,r10` at 0x25F36
local START_X_OPCODE     = 0x25F36   -- 0xEA: `mov #imm,r10`
local START_X_RETAIL     = 0xE0      -- -32
local START_WIDTH_RETAIL = 64

-- The width of one command image in the pool, or nil when the pool does not
-- carry it.
local function pool_width(block, image)
  local workspace = LUDARED and LUDARED.WORKSPACE
  if not workspace then return nil end

  local directory = workspace .. "/combat/commands"
  for _, candidate in ipairs(gfx.command_files(block, image)) do
    local file = io.open(directory .. "/" .. (candidate:match("[^/\\]+$") or candidate), "rb")
    if file then
      local data = file:read(22)
      file:close()
      if data and #data == 22 then
        local width = string.unpack("<i4", data, 19)
        if width < 0 then width = -width end
        return width
      end
    end
  end
  return nil
end

-- The width of the popup box a command opens: its image is the one numbered
-- after its entry count (2 rows -> block 0 image 2, and so on).
local function box_width(i)
  return pool_width(0, LAYOUT_ENTRIES[i]) or 40
end

local function menu_extent(cell_width)
  -- command_00_00 is the bar and command_00_01 Ogami's variant, both drawn at
  -- the anchor itself.
  local extent = math.max(pool_width(0, 0) or 96, pool_width(0, 1) or 120)
  local labels = entry_positions(cell_width)
  local popups = layout_positions(cell_width)

  for i = 1, #labels do
    local label_right = labels[i] + cell_width
    if label_right > extent then extent = label_right end

    local popup_right = popups[i] + box_width(i)
    if popup_right > extent then extent = popup_right end
  end

  return extent
end

-- Lower the clamp by however much the panel grew.  Retail art leaves the bound
-- at +48; the reference tool's own large menu asked for -96 with a layout
-- 80 pixels wider, which is the same direction at a coarser step.
local function apply_clip(data, extent, stage)
  local value = 48 - (extent - RETAIL_EXTENT)
  if value < -2048 or value > 2048 then
    error(string.format(
      "%s: %s: the panel would end %d pixels right of the anchor, which is "
      .. "past what the menu clamp can express", LABEL, stage, extent), 0)
  end

  local wanted = value < 0 and (0x10000 + value) or value
  local current = read_u16(data, CLIP)
  if current ~= CLIP_RETAIL and current ~= wanted then
    error(string.format(
      "%s: %s: the menu clamp at 0x%X holds 0x%04X, neither the retail 0x%04X "
      .. "nor the 0x%04X this art asks for",
      LABEL, stage, CLIP, current, CLIP_RETAIL, wanted), 0)
  end

  if current == wanted then return data end
  return data:sub(1, CLIP) .. string.pack(">I2", wanted) .. data:sub(CLIP + 3)
end

-- Keep the START menu background centred on its own width.  Retail art (64)
-- leaves the instruction alone, so a build that has not touched this panel is
-- byte-identical to the retail executable.
local function apply_start_panel(data, stage)
  local width = pool_width(15, 0) or START_WIDTH_RETAIL
  if width % 2 ~= 0 then
    error(string.format("%s: %s: a %d-pixel START menu panel cannot be centred "
      .. "on a half-pixel", LABEL, stage, width), 0)
  end

  local wanted = (-(width // 2)) & 0xFF
  if data:byte(START_X_OPCODE + 1) ~= 0xEA then
    error(string.format(
      "%s: %s: 0x%X holds 0x%02X, not the `mov #imm,r10` that writes the "
      .. "START menu xa", LABEL, stage, START_X_OPCODE, data:byte(START_X_OPCODE + 1)), 0)
  end

  local current = data:byte(START_X + 1)
  if current ~= START_X_RETAIL and current ~= wanted then
    error(string.format(
      "%s: %s: the START menu xa at 0x%X holds %d, neither the retail %d nor "
      .. "the %d a %d-pixel panel asks for",
      LABEL, stage, START_X, current - 256, START_X_RETAIL - 256,
      wanted - 256, width), 0)
  end

  if current == wanted then return data end
  return data:sub(1, START_X) .. string.char(wanted) .. data:sub(START_X + 2)
end

-- The confirmation dialog (WKL block 14, MENU_CONFIRM_*).  Two copies of the
-- same routine place it, one per title image: RETRY at 0x25AF4 and QUIT at
-- 0x25C50.  Each starts with its anchor immediates (`mov #-52,r10 /
-- mov.w r10,@r14` for xa, `mov #-28,r10` for ya), then copies a 16-byte table
-- of `{ colr, dx, dy, flag }` -- panel, title, YES, NO -- and appends two
-- inline entries for the hover, one per button.  A child is drawn at
-- anchor + (dx, dy), and dx/dy are unsigned bytes, so every child sits right
-- of and below the panel's origin; the anchor itself is what moves the box.
-- Both hovers share one dy immediate (r7), so YES and NO must stay on one row.
--
-- Checked on a running build: patching an anchor immediate moves all five
-- sprites together, and patching this table moves the title only, leaving the
-- START menu (which has its own drawer and table) untouched.
local CONFIRM_LAYOUT = "combat/commands/MENU_CONFIRM.json"

-- The keys are the WKL image names without the MENU_CONFIRM_ prefix.  x/y are
-- screen positions in the same centred space as the packet's xa/ya: (0,0) is
-- the middle of the 320x224 screen, +x right, +y down.  Retail puts the 104x56
-- panel at (-52, -28), i.e. its left edge at x = 108 and its top at y = 84.
local CONFIRM_DEFAULTS = {
  ["00_BG"]    = { x = -52, y = -28 },
  ["01_RETRY"] = { x = -44, y = -20 },
  ["02_QUIT"]  = { x = -44, y = -20 },
  ["03_YES"]   = { x = -44, y = 4 },
  ["04_NO"]    = { x = 4,   y = 4 },
}

local CONFIRM_ENTRIES = { "00_BG", "01_RETRY", "02_QUIT", "03_YES", "04_NO" }

-- Where each dialog keeps its anchor, its table (+4 skips the panel entry) and
-- the hover dx/dy immediates.
local CONFIRM_DIALOGS = {
  {
    key = "01_RETRY",
    x = 0x25B02, y = 0x25B0A, table = 0x258B4,
    hover = { dx_yes = 0x258FB, dy = 0x25903, dx_no = 0x25919 },
  },
  {
    key = "02_QUIT",
    x = 0x25C5E, y = 0x25C66, table = 0x25790,
    hover = { dx_yes = 0x257D7, dy = 0x257DF, dx_no = 0x257F5 },
  },
}

local CONFIRM_RETAIL = {
  x = 0xCC, y = 0xE4,
  title = { dx = 8,  dy = 8  },
  yes   = { dx = 8,  dy = 32 },
  no    = { dx = 56, dy = 32 },
}

-- A strict reader for the layout file: it is a two-level object of { x, y }
-- pairs, and anything else in it is a build error rather than a silent
-- default, because a wrong position is invisible until the dialog is opened.
local function read_confirm_json(text, stage)
  local pos = 1
  local function fail(msg)
    error(string.format("%s: %s: %s at byte %d", LABEL, stage, msg, pos), 0)
  end
  local function skip_ws()
    pos = text:find("[^ \t\r\n]", pos) or #text + 1
  end
  local function parse_string()
    skip_ws()
    if text:sub(pos, pos) ~= '"' then fail("expected a quoted name") end
    local close = text:find('"', pos + 1, true)
    if not close then fail("unterminated name") end
    local value = text:sub(pos + 1, close - 1)
    if value:find("[\\\"]") then fail("names here are plain text") end
    pos = close + 1
    return value
  end
  local function parse_number()
    skip_ws()
    local start, stop = text:find("^-?%d+", pos)
    if not start then fail("expected an integer") end
    pos = stop + 1
    return tonumber(text:sub(start, stop))
  end
  local parse_value
  local function parse_object()
    skip_ws()
    if text:sub(pos, pos) ~= "{" then fail("expected an object") end
    pos = pos + 1
    local out = {}
    skip_ws()
    if text:sub(pos, pos) == "}" then pos = pos + 1 return out end
    while true do
      local key = parse_string()
      skip_ws()
      if text:sub(pos, pos) ~= ":" then fail("expected ':' after " .. key) end
      pos = pos + 1
      if out[key] ~= nil then fail("'" .. key .. "' appears twice") end
      out[key] = parse_value()
      skip_ws()
      local c = text:sub(pos, pos)
      if c == "" then fail("unterminated object") end
      pos = pos + 1
      if c == "}" then return out end
      if c ~= "," then fail("expected ',' or '}' after " .. key) end
    end
  end
  parse_value = function()
    skip_ws()
    local c = text:sub(pos, pos)
    if c == "{" then return parse_object() end
    if c == '"' then return parse_string() end
    return parse_number()
  end

  local root = parse_object()
  skip_ws()
  if pos <= #text then fail("trailing characters") end
  return root
end

-- The positions in MENU_CONFIRM.json, or nil when the workspace does not carry
-- the file (a build that has not touched the dialog stays retail).
local function confirm_layout(stage)
  local workspace = LUDARED and LUDARED.WORKSPACE
  if not workspace then return nil end

  local file = io.open(workspace .. "/" .. CONFIRM_LAYOUT, "rb")
  if not file then return nil end
  local text = file:read("a")
  file:close()

  local root = read_confirm_json(text, stage)
  for key in pairs(root) do
    if key ~= "MENU_CONFIRM" then
      error(string.format("%s: %s: the top level holds %q; only MENU_CONFIRM is read",
        LABEL, stage, key), 0)
    end
  end

  local group = root.MENU_CONFIRM
  if type(group) ~= "table" then
    error(string.format("%s: %s: MENU_CONFIRM must be an object of positions",
      LABEL, stage), 0)
  end

  for key in pairs(group) do
    local known = false
    for _, name in ipairs(CONFIRM_ENTRIES) do known = known or name == key end
    if not known then
      error(string.format("%s: %s: MENU_CONFIRM.%s does not name a MENU_CONFIRM image",
        LABEL, stage, key), 0)
    end
  end

  local out = {}
  for _, key in ipairs(CONFIRM_ENTRIES) do
    local entry = group[key]
    if type(entry) ~= "table" then
      error(string.format("%s: %s: MENU_CONFIRM.%s is missing", LABEL, stage, key), 0)
    end
    for name in pairs(entry) do
      if name ~= "x" and name ~= "y" then
        error(string.format("%s: %s: MENU_CONFIRM.%s has an unknown key %q",
          LABEL, stage, key, name), 0)
      end
    end
    for _, axis in ipairs({ "x", "y" }) do
      local value = entry[axis]
      if type(value) ~= "number" or value % 1 ~= 0 then
        error(string.format("%s: %s: MENU_CONFIRM.%s.%s must be an integer",
          LABEL, stage, key, axis), 0)
      end
      if value < -128 or value > 127 then
        error(string.format(
          "%s: %s: MENU_CONFIRM.%s.%s = %d is outside the byte the anchor holds",
          LABEL, stage, key, axis, value), 0)
      end
    end
    out[key] = { x = entry.x, y = entry.y }
  end

  return out
end

-- Write one byte the game reads, refusing anything that is neither retail nor
-- what the layout asks for, so a second run (or a second resize) is safe.
local function put_confirm_byte(out, data, offset, value, retail, what, stage)
  if value < 0 or value > 0xFF then
    error(string.format("%s: %s: %s would be %d, outside the byte the game reads",
      LABEL, stage, what, value), 0)
  end

  local current = data:byte(offset + 1)
  if current ~= retail and current ~= value then
    error(string.format(
      "%s: %s: %s at 0x%X holds %d, neither the retail %d nor the %d "
      .. "MENU_CONFIRM.json asks for",
      LABEL, stage, what, offset, current, retail, value), 0)
  end

  if current == value then return out end
  return out:sub(1, offset) .. string.char(value) .. out:sub(offset + 2)
end

-- Place both confirm dialogs from the layout.  x/y are screen positions, so a
-- child's stored offset is its position minus the panel's.
local function apply_confirm(data, layout, stage)
  local out = data
  local bg = layout["00_BG"]

  for _, dialog in ipairs(CONFIRM_DIALOGS) do
    local title = layout[dialog.key]

    for _, anchor in ipairs({
      { at = dialog.x, value = bg.x, retail = CONFIRM_RETAIL.x, what = "the panel xa" },
      { at = dialog.y, value = bg.y, retail = CONFIRM_RETAIL.y, what = "the panel ya" },
    }) do
      if data:byte(anchor.at + 1) ~= 0xEA then
        error(string.format(
          "%s: %s: 0x%X holds 0x%02X, not the `mov #imm,r10` that places %s",
          LABEL, stage, anchor.at, data:byte(anchor.at + 1), anchor.what), 0)
      end
      out = put_confirm_byte(out, data, anchor.at + 1, anchor.value & 0xFF,
        anchor.retail, anchor.what, stage)
    end

    local children = {
      { pos = title,               at = dialog.table + 4,  retail = CONFIRM_RETAIL.title,
        what = dialog.key .. " title" },
      { pos = layout["03_YES"],    at = dialog.table + 8,  retail = CONFIRM_RETAIL.yes,
        what = "the YES button" },
      { pos = layout["04_NO"],     at = dialog.table + 12, retail = CONFIRM_RETAIL.no,
        what = "the NO button" },
    }
    for _, child in ipairs(children) do
      out = put_confirm_byte(out, data, child.at + 1, child.pos.x - bg.x,
        child.retail.dx, child.what .. " dx", stage)
      out = put_confirm_byte(out, data, child.at + 2, child.pos.y - bg.y,
        child.retail.dy, child.what .. " dy", stage)
    end

    local yes = layout["03_YES"]
    local no  = layout["04_NO"]
    if yes.y - bg.y ~= no.y - bg.y then
      error(string.format(
        "%s: %s: both hover entries share one y, but YES is on row %d and NO on row %d",
        LABEL, stage, yes.y - bg.y, no.y - bg.y), 0)
    end
    for _, site in ipairs({
      { at = dialog.hover.dx_yes, opcode = 0xE1, value = yes.x - bg.x,
        retail = CONFIRM_RETAIL.yes.dx, what = "the YES hover dx" },
      { at = dialog.hover.dy,     opcode = 0xE7, value = yes.y - bg.y,
        retail = CONFIRM_RETAIL.yes.dy, what = "the hover dy" },
      { at = dialog.hover.dx_no,  opcode = 0xE1, value = no.x - bg.x,
        retail = CONFIRM_RETAIL.no.dx, what = "the NO hover dx" },
    }) do
      if data:byte(site.at) ~= site.opcode then
        error(string.format("%s: %s: 0x%X holds 0x%02X, not the `mov #imm` that sets %s",
          LABEL, stage, site.at - 1, data:byte(site.at), site.what), 0)
      end
      out = put_confirm_byte(out, data, site.at, site.value, site.retail, site.what, stage)
    end
  end

  return out
end

-- The panel table already positions each command; only the gap after its label remains.
local function apply_action_counts(data, cell_width)
  local offset = cell_width + 8
  assert(offset + 8 <= 0x7F, "action count offset exceeds the signed immediate")

  local out = data
  for _, site in ipairs({
    { ACTION_COUNT_COVER, 0x18, offset },
    { ACTION_COUNT_REPAIR[1], 0x18, offset },
    { ACTION_COUNT_REPAIR[2], 0x20, offset + 8 },
  }) do
    local at, retail, wanted = table.unpack(site)
    local current = out:byte(at + 1)
    if current ~= retail and current ~= wanted then
      error(string.format("%s: unexpected action count byte at 0x%X", LABEL, at), 0)
    end
    out = out:sub(1, at) .. string.char(wanted) .. out:sub(at + 2)
  end
  return out
end

-- Rewrite the six entry lists.  Every record of one command shares its retail
-- x, so the whole column moves to the new position.
local function apply_entry_lists(data, cell_width, stage)
  local xs  = entry_positions(cell_width)
  local out = data

  for i, list in ipairs(LAYOUT_LISTS) do
    for j = 0, list.count - 1 do
      local at = list.offset + j * LAYOUT_ENTRY_STRIDE
      if at + LAYOUT_ENTRY_STRIDE > #data then
        error(LABEL .. ": " .. stage .. ": file too short for the command entries", 0)
      end

      local pad = read_u16(data, at)
      local x   = string.unpack(">i2", data, at + 3)
      local tail = read_u16(data, at + 6)
      local want = xs[i]

      if pad ~= 0 or tail ~= 0
          or (x ~= list.x and x ~= want) then
        error(string.format(
          "%s: %s: the command entries at 0x%X do not look like the retail "
          .. "ones (command %d entry %d holds x=%d, pad=%d, tail=%d)",
          LABEL, stage, at, i - 1, j, x, pad, tail), 0)
      end

      if x ~= want then
        out = out:sub(1, at + 2) .. string.pack(">i2", want) .. out:sub(at + 5)
      end
    end
  end

  return out
end

function codec.can_handle(data)
  if type(data) ~= "string" then return "no" end
  if can_handle.can_handle_slg(data) == "certain" then return "certain" end

  if #data <= 0x219C4 then return "no" end
  local ok, delta = pcall(applied_delta, data)
  if ok and delta then return "possible" end
  return "no"
end

function codec.decode_name()
  return "combat_commands"
end

function codec.decode(data, args)
  if type(data) ~= "string" then error(LABEL .. ": decode: expected a binary string", 0) end

  local delta, offender = applied_delta(data)
  if not delta then
    error(string.format("%s: decode: no battle-menu anchors here\n%s",
      LABEL, report(data, offender)), 0)
  end

  return {}
end

function codec.encode(original, artifacts, args)
  if type(original) ~= "string" then
    error(LABEL .. ": encode: expected a binary string for `original`", 0)
  end
  if args ~= nil and args ~= "" then
    error(LABEL .. ": this codec takes no arguments, got '" .. tostring(args) .. "'", 0)
  end

  local delta, offender = applied_delta(original)
  if not delta then
    error(string.format("%s: encode: no battle-menu anchors here\n%s",
      LABEL, report(original, offender)), 0)
  end

  local target = canvas_region_size() - gfx.retail_region
  local out    = original
  if target ~= delta then out = apply(original, delta, target, "encode") end

  -- Wider labels cannot keep the retail 16-pixel pitch; see "Where the command
  -- labels sit".  With no sheet the block is left as it is.
  local cell_width = layout_cell_width()
  if cell_width then
    out = apply_layout(out, cell_width, "encode")
    out = apply_entry_lists(out, cell_width, "encode")
    out = apply_panel(out, cell_width, "encode")
    out = apply_rects(out, cell_width, "encode")
    out = apply_action_counts(out, cell_width)
    out = apply_clip(out, menu_extent(cell_width), "encode")
  end

  out = apply_start_panel(out, "encode")

  -- The confirmation dialog's positions, when the workspace carries them.
  local confirm = confirm_layout("encode")
  if confirm then out = apply_confirm(out, confirm, "encode") end

  return out
end

-- Exposed for tests only; the codec contract is decode/encode.
codec._sites = SITES
codec._applied_delta = applied_delta
codec._canvas_region_size = canvas_region_size

return codec
