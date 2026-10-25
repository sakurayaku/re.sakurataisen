--[[
  Sakura Taisen (Saturn) — Options menu label and selection-mark codec

  PATCH plugin for the five graphical labels and the two selection marks of
  the Options screen.  They are not in LOGO.SH2: the assets live in the
  SAKURA executable on disc 1 (391,712 bytes, sha256 1729cd87…), which is
  what `can_handle` recognises.

  ## Layout

      0x05ad98    64 bytes   options palette, two 16-colour BGR555 banks
                             (uploaded to CRAM 0x580 by the setup routine)
      0x05b320    3782 bytes compressed slot for the glyph atlas
      0x05c1e6               next resource; the slot never grows past this
      0x05a7e0..  5 x 32     option row descriptors (exit, controls, voice,
      0x05ab68               sound, cursor — file order, not menu order)
      0x05a796..  44 x 10    label records, interleaved with the descriptors

  The five descriptors, in menu (descriptor-table) order, are

      row      descriptor   retail label records   count   composed width
      cursor   0x05ab68     0x05aa50               11      256
      sound    0x05aa30     0x05a974               12      256
      voice    0x05a954     0x05a8c8                7      240
      controls 0x05a8a8     0x05a800               10      256
      exit     0x05a7e0     0x05a796                4       64

  ## Descriptor fields (verified by disassembling both consumers)

      +0   u16     unused
      +2   s16     row y
      +4   u16     choice count (high half of a BE u32)
      +8   u32     choice-indicator list pointer
      +12  u16     label glyph count (high half of a BE u32)   <- encoded here
      +16  u32     label record list pointer (0x06004000-relative) <- reused
      +20  u32     texture base, 0x0000D860
      +24  u32     selection-mark pair list (two 10-byte records per choice)
      +28  u32     selection-mark centre list (one BE u32 per choice)

  `+24` and `+28` are read only by the drawer's second pass (rows 0..3; the
  exit row skips it).  `+4` 10-byte records at `+24` hold the left and right
  marks; `+28[k]` supplies the choice centre.  The centre is the high s16 of
  the BE u32 (the low half is preserved, not interpreted).  `+8` is the
  input-only hit-rectangle list: the mark pass never reads it, which is what
  lets the codec move a mark without moving its click target.

  The label drawer at 0x0603ec90 walks exactly `+12` 10-byte records starting
  at `+16`, adding `+20` to each record's `characterOffset`.  There is no end
  pointer: `+8` is the choice-indicator list, and the five row handlers read
  only `+4` and `+8`.  A whole label therefore becomes one record by writing
  `+12 = 0x00010000` and leaving `+16` pointing at that record.

  ## Records

      10 bytes, big-endian: s16 x, s16 y, u16 w, u16 h, u16 characterOffset

  `characterOffset = texture byte offset / 8`, so `co * 8` is the byte offset
  into the decompressed sheet.  The retail labels are 16 x 16 glyph tiles at
  `y = -8`; a rebuilt label is one `w x 16` strip placed at the origin of the
  bounding box it replaces, not centred: the retail rows are left-aligned at
  `x = -128` except `exit` (a 64-pixel label at `-32`), and `voice` ends at
  `+112`, so centring a 240-pixel strip would shift that row 8 pixels right and
  misalign its choice bars.  A label that grows extends to the right.

  ## Atlas

  The 3,782-byte PRS stream decodes to 73 tiles (9,344 bytes) of 16 x 16 4bpp.
  The options setup routine stages it at 0x060ec300 and uploads the block to
  VDP1 0x60000, so the sheet maps to 0x6c300 = 0xd860 << 3.  The next texture
  is staged at 0x060ef000, i.e. VDP1 0x6f000, which leaves

      0x6f000 - 0x6c300 = 0x2d00 = 11,520 bytes       (90 tiles)

  for the sheet.  The retail sheet is 9,344 bytes and recompresses to 3,734,
  only 48 bytes under the slot, so strips cannot be appended: one real
  256 x 16 strip already compresses to 4,157 bytes.  This codec therefore
  replaces the sheet wholesale with one strip per label.

  The first 64 bytes of the retail sheet are copied verbatim as a conservative
  guard for the sheet's own head.  They are not the selection marks: those are
  the last 128 bytes of the background stream (see below), not glyphs in this
  atlas.

  ## Background

      0x05ae38    1,256 bytes   PRS stream (1,255 used at retail) decoding to
                              49,920 bytes: a 288 x 144 4bpp image (20,736
                              bytes) followed by 29,184 bytes of other data

The image is the pink Options panel and its `オプション` tab.  It is packed
row-major, top-down, two pixels per byte (high nibble first), with a 144-byte
stride.  That is *not* the 144 x 288 sprite geometry: the 288-wide texture is
drawn rotated, so the BMP is the natural layout the C++ pipeline uses
(`OptionsBgndPatched.bmp`, 288 x 144, 4bpp).

The first 20,736 bytes are editable through `OPTIONS/BACKGROUND.bmp`.  The
29,184-byte tail is otherwise opaque engine data and is copied verbatim; the
only editable part of it is its final 128 bytes, exposed as the two bracket
BMPs.  The stream is recompressed into the same 1,256-byte slot, so it needs
the deeper PRS search (`chain = 512`): the retail bytes recompress to 1,271
with the default 256-entry chain, over the slot, and to 1,245 with 512.  The
unchanged fast path means an untouched background is never recompressed.

  ## Selection marks

  The 128 bytes at decoded `0xC280..0xC2FF` are two `8 x 16` 4bpp sprites,
  left then right.  The setup stages the background at `0x060E0000`, so the
  pair lands at `0x060EC280` and maps to VDP1 texture base `0xD850`; each
  mark samples 64 bytes (`characterOffset` 0 and 8).  They are not glyphs in
  the label atlas and not part of `OPTIONS/BACKGROUND.bmp`.

  `OPTIONS/BRACKET_LEFT.bmp` and `OPTIONS/BRACKET_RIGHT.bmp` expose those two
  sprites.  They share one PRS stream: a background edit, a left edit and a
  right edit are composed into one tail and recompressed once, so none can
  overwrite another.  Every other decoded tail byte is preserved.  The BMP
  palette is display-only and uses the background's `0x05AD98` bank; encode
  compares pixels only, and a palette-only edit is not a change.

  The textures are **shared by all rows**.  Editing them changes every
  Options row that draws a mark; it cannot give one row a unique indicator.
  Per-choice placement is independent, through `BRACKET_POSITIONS.json`.

The mark texture base is the literal `0xD850` at `0x603EFDA`, not
`descriptor+20 - 0x10`, so changing a row's texture base cannot give its marks
different art.  Each `+24` record does carry its own `characterOffset`, so a
future data-only design could point a row at extra 64-byte blocks elsewhere in
VDP1 memory (for example spare space after the label strips).  Nothing places
or exposes such blocks today: the only reserved mark art is this shared
128-byte pair, and the `BRACKET_POSITIONS.json` schema deliberately writes only
`x` and the centre while preserving `co`.  A unique Cursor Speed slider is
therefore possible without an SH-2 patch in principle, but not by editing these
two BMPs alone; it needs a new sprite-slot channel.

## Artifacts

      OPTIONS/CURSOR_SPEED.bmp   4bpp, 256 x 16 at retail
      OPTIONS/SOUND.bmp          4bpp, 256 x 16
      OPTIONS/VOICE.bmp          4bpp, 240 x 16
      OPTIONS/CONTROLS.bmp       4bpp, 256 x 16
      OPTIONS/EXIT.bmp           4bpp,  64 x 16
      OPTIONS/BACKGROUND.bmp     4bpp, 288 x 144 (index 0 transparent)
      OPTIONS/BRACKET_LEFT.bmp   4bpp,   8 x 16
      OPTIONS/BRACKET_RIGHT.bmp  4bpp,   8 x 16
      OPTIONS/BRACKET_POSITIONS.json

  Each label BMP is the composed label, not a grid of tiles.  Palette index 0
  is transparent and stays 0.  Heights are fixed at 16; widths are free
  positive multiples of 8 up to 2,040 pixels (VDP1's 8-bit width field), and
  the five widths together must satisfy `64 + 8 * sum(w) <= 11,520`, i.e.
  sum(w) <= 1,432.

  `BRACKET_POSITIONS.json` is declarative metadata, one entry per row and one
  per choice:

      { "center": -8, "left": -16, "right": 8 }

  `center` is the choice centre; `left` and `right` are the mark offsets from
  the row origin (the same values as the two records at `+24`).  The mark's
  screen x is `record.x + center`.  `y`, `w`, `h` and `characterOffset` are
  preserved from the parent; only `x` and the centre can change.  The file is
  optional: absent means "keep the retail coordinates".

  ## Preview palette

  The BMP palette is the parent's own options palette, not a dialogue ramp:
  the 64 bytes at 0x05ad98 are two 16-colour banks, the first for the options
  background (144 x 288, 4bpp) and the second for the label glyphs.  The second
  bank at 0x05adb8 renders the retail labels as the outlined white text the
  screen shows; the first bank renders the same pixels as a washed-out pink
  gradient, and `shared/palettes.lua`'s adv_dialogue_i18n renders them blue.
  The bracket BMPs use the first (background) bank because their pixels come
  from the background stream.  The palette is display only: encode() ignores
  it completely, and a palette-only edit is not a change.

  ## Round-tripping

  If no label's composed pixels or width change, the background and both
  bracket BMPs are absent or pixel-identical, and the positions metadata is
  absent or identical to the parent, encode() returns the parent byte for
  byte — that is what keeps a re-decode from rewriting a retail sheet into
  strips.  `rebuild=always` (a codec argument, recorded by Ludared at decode
  time) bypasses that fast path so the same labels are rewritten as strips;
  it is how the reconstruction path is validated.  The three edit domains are
  independent: a label edit does not touch 0x05ae38, a background or bracket
  edit does not rebuild labels, and a positions edit touches neither pixel
  stream.

  Encode writes only

      * the 1,256-byte background slot at 0x05ae38, when the panel or either
        bracket sprite changed (all three compose into one stream),
      * the 3,782-byte atlas slot at 0x05b320, when the labels changed,
      * `+12..+15` of each of the five descriptors and the first 10 bytes of
        each label record list (the target of `+16`),
      * the `+24`/`+28` lists when `BRACKET_POSITIONS.json` changed.

  The `+8` input hit rectangles and the SH-2 rendering routines are never
  written.  Everything else — the other descriptor fields, the choice-
  indicator lists, the unused retail records, OptionsSubmenu, SystemMenu,
  PauseOptions, GameOptions and the LoadMenu block — is copied.  A byte
  comparison before returning enforces that.
]]

local function script_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then
    return src:sub(2):match("^(.*)[/\\\\][^/\\\\]*$") or "."
  end
  return "."
end

-- Codecs run under Ludared (which knows the scripts root) and standalone under
-- the test harness; both cases have to find shared/ helpers.
local function load_shared(name)
  if LUDARED and LUDARED.SCRIPTS then
    return dofile(LUDARED.SCRIPTS .. "/shared/" .. name .. ".lua")
  end
  return dofile(script_dir() .. "/shared/" .. name .. ".lua")
end

local prs         = LUDARED.codec("std/sega/compression/prs")
local args_parser = load_shared("args_parser")
local sha256      = load_shared("sha256")

local codec = {}

codec.name        = "Sakura Taisen Options Menu Graphics"
codec.description = "PATCH plugin for the Options-screen labels and selection marks in SAKURA"
codec.kind        = "patch"
codec.version     = 3

local FILE_BYTES  = 391712
local FILE_SHA256 = "1729cd8701fa8da30b203d0bf97e47e2dc9cf06b50ca91589ea760fe0cb8ff87"

local ATLAS_OFFSET  = 0x05b320
local ATLAS_SLOT    = 3782              -- fixed compressed slot
local ATLAS_PREFIX  = 64                -- preserved head of the sheet
local ATLAS_LIMIT   = 0x2d00            -- 11,520 bytes before the next texture
local TEXTURE_BASE  = 0xd860            -- VDP1 0x6c300 >> 3
local RAM_BASE      = 0x06004000        -- file offset -> RAM address

local PALETTE_OFFSET     = 0x05ad98     -- two 16-colour BGR555 banks
local PALETTE_BANK_BYTES = 32           -- 16 entries x 2 bytes
local PALETTE_TEXT       = PALETTE_OFFSET + PALETTE_BANK_BYTES

local BACKGROUND_OFFSET = 0x05ae38     -- PRS, fixed 1,256-byte slot
local BACKGROUND_SLOT   = 1256
local BACKGROUND_W      = 288
local BACKGROUND_H      = 144
local BACKGROUND_PIXELS = BACKGROUND_W * BACKGROUND_H // 2   -- 20,736
local BACKGROUND_END    = 0xc300        -- 49,920 decoded bytes
local BACKGROUND_CHAIN  = 512           -- deeper search keeps the slot

-- The two selection marks are the last 128 bytes of the background stream:
-- 8 x 16 4bpp sprites, left then right.  They are staged at 0x060ec280 and
-- are therefore VDP1 texture base 0xd850, independently of the label atlas.
local BRACKET_OFFSET   = 0xc280
local BRACKET_BYTES    = 64
local BRACKET_W        = 8
local BRACKET_H        = 16
local BRACKET_TAIL_AT  = BRACKET_OFFSET - BACKGROUND_PIXELS

local RECORD_BYTES  = 10
local LABEL_H       = 16
local LABEL_ALIGN   = 8
local LABEL_MAX_W   = 255 * 8           -- VDP1 CMDSIZE width field
local MAX_RECORDS   = 64
local MAX_CHOICES   = 32

local DESCRIPTORS = {
  { name = "CURSOR_SPEED", offset = 0x05ab68 },
  { name = "SOUND",        offset = 0x05aa30 },
  { name = "VOICE",        offset = 0x05a954 },
  { name = "CONTROLS",     offset = 0x05a8a8 },
  { name = "EXIT",         offset = 0x05a7e0 },
}

local ARTIFACT_PREFIX    = "OPTIONS/"
local BACKGROUND_NAME    = ARTIFACT_PREFIX .. "BACKGROUND.bmp"
local BRACKET_LEFT_NAME  = ARTIFACT_PREFIX .. "BRACKET_LEFT.bmp"
local BRACKET_RIGHT_NAME = ARTIFACT_PREFIX .. "BRACKET_RIGHT.bmp"
local POSITIONS_NAME     = ARTIFACT_PREFIX .. "BRACKET_POSITIONS.json"

local BMP_FILE_HEADER = 14
local BMP_INFO_HEADER = 40
local BMP_CLR_USED    = 46              -- 0-based biClrUsed

local function be16(s, off)
  return s:byte(off + 1) * 256 + s:byte(off + 2)
end

local function sbe16(s, off)
  local v = be16(s, off)
  return v >= 0x8000 and v - 0x10000 or v
end

local function be32(s, off)
  return ((s:byte(off + 1) * 256 + s:byte(off + 2)) * 256 + s:byte(off + 3)) * 256
    + s:byte(off + 4)
end

-- Pack a 10-byte record; x and y are signed, the rest unsigned.
local function pack_record(x, y, w, h, co)
  return string.pack(">i2i2I2I2I2", x, y, w, h, co)
end

-- Replace #bytes at a 0-based file offset; the length never changes.
local function put(s, offset, bytes)
  return s:sub(1, offset) .. bytes .. s:sub(offset + #bytes + 1)
end

-- True when [pos, pos + len) overlaps one of the five 32-byte descriptors.
local function overlaps_descriptor(pos, len)
  for _, desc in ipairs(DESCRIPTORS) do
    if pos < desc.offset + 32 and desc.offset < pos + len then
      return desc.name
    end
  end
  return nil
end

-- string.char(table.unpack(...)) runs out of stack on a 2,040-pixel strip, so
-- convert in chunks.
local function bytes_to_string(px)
  local out = {}
  for i = 1, #px, 512 do
    out[#out + 1] = string.char(table.unpack(px, i, math.min(i + 511, #px)))
  end
  return table.concat(out)
end

local function row_stride(width, bpp)
  return ((width * bpp + 31) // 32) * 4
end

-- BGR555 (Saturn, big-endian) -> BGRA (BMP), 8 bits per channel.
local function bgr555_to_bmp(palette, colours)
  local out = {}
  for i = 0, colours - 1 do
    local v = palette:byte(i * 2 + 1) * 256 + palette:byte(i * 2 + 2)
    local b5, g5, r5 = (v >> 10) & 0x1F, (v >> 5) & 0x1F, v & 0x1F
    out[i * 4 + 1] = (b5 * 255 + 15) // 31
    out[i * 4 + 2] = (g5 * 255 + 15) // 31
    out[i * 4 + 3] = (r5 * 255 + 15) // 31
    out[i * 4 + 4] = 0
  end
  return string.char(table.unpack(out))
end

local function build_bmp(pixels, width, height, pal, bpp)
  local stride    = row_stride(width, bpp)
  local row_bytes = width * bpp // 8
  local rows = {}
  for y = 0, height - 1 do
    local row = pixels:sub(y * row_bytes + 1, (y + 1) * row_bytes)
    if #row < row_bytes then row = row .. string.rep("\0", row_bytes - #row) end
    rows[y + 1] = row .. string.rep("\0", stride - row_bytes)
  end
  local body = table.concat(rows)
  local off  = BMP_FILE_HEADER + BMP_INFO_HEADER + #pal
  local hdr = string.pack("<c2I4I2I2I4I4i4i4I2I2I4I4I4I4I4I4",
    "BM", off + #body, 0, 0, off,
    BMP_INFO_HEADER, width, -height, 1, bpp, 0, #body, 0, 0, #pal // 4, 0)
  return hdr .. pal .. body
end

local function parse_bmp(bmp, stage, want_bpp)
  if type(bmp) ~= "string" or #bmp < BMP_FILE_HEADER + BMP_INFO_HEADER then
    error(stage .. ": BMP is too short", 0)
  end
  if bmp:sub(1, 2) ~= "BM" then
    error(stage .. ": not a BMP file", 0)
  end
  local off, info_len, width, height, planes, bpp, comp =
    string.unpack("<I4I4i4i4I2I2I4", bmp, 11)
  if planes ~= 1 then error(stage .. ": biPlanes is not 1", 0) end
  if comp ~= 0 then error(stage .. ": compressed BMP is not supported", 0) end
  if info_len < BMP_INFO_HEADER then error(stage .. ": DIB header is too small", 0) end
  if width <= 0 or height == 0 then error(stage .. ": the image is empty", 0) end
  if want_bpp and bpp ~= want_bpp then
    error(string.format("%s: needs a %dbpp image, this one is %dbpp",
      stage, want_bpp, bpp), 0)
  end
  if bpp ~= 4 and bpp ~= 8 then
    error(string.format("%s: %dbpp is not supported (4 or 8)", stage, bpp), 0)
  end

  height = math.abs(height)
  local bottom_up = string.unpack("<i4", bmp, 23) > 0
  local stride    = row_stride(width, bpp)
  local row_bytes = width * bpp // 8
  if #bmp < off + stride * height then
    error(stage .. ": the pixel data is truncated", 0)
  end

  local rows = {}
  for y = 0, height - 1 do
    local base = off + y * stride
    rows[y + 1] = bmp:sub(base + 1, base + row_bytes)
  end
  if bottom_up then
    local flipped = {}
    for y = 1, height do flipped[y] = rows[height - y + 1] end
    rows = flipped
  end

  -- The palette sits immediately before the pixels; biClrUsed is authoritative
  -- when set, and editors may write a longer DIB header than this codec does.
  local colours = string.unpack("<I4", bmp, BMP_CLR_USED + 1)
  if colours == 0 or colours > (1 << bpp) then colours = 1 << bpp end
  local pal_start = off - colours * 4
  if pal_start < BMP_FILE_HEADER then
    error(string.format("%s: no room for a %d-colour palette before the pixels",
      stage, colours), 0)
  end
  local pal = bmp:sub(pal_start + 1, off)
  return table.concat(rows), width, height, pal, bpp, colours
end

-- The five label records, read through each descriptor's own `+16` pointer.
local function read_labels(data, stage)
  local labels = {}

  for _, desc in ipairs(DESCRIPTORS) do
    local off = desc.offset
    if off + 32 > #data then
      error(string.format("%s: the %s descriptor at 0x%06X is outside the file",
        stage, desc.name, off), 0)
    end

    local count = be16(data, off + 12)
    local base  = be32(data, off + 20)
    if base ~= TEXTURE_BASE then
      error(string.format("%s: the %s texture base is 0x%04X, expected 0x%04X",
        stage, desc.name, base, TEXTURE_BASE), 0)
    end
    if count < 1 or count > MAX_RECORDS then
      error(string.format("%s: the %s label count is %d at +12; expected 1..%d",
        stage, desc.name, count, MAX_RECORDS), 0)
    end

    -- `+16` is a 0x06004000-relative address in every shipped descriptor; a raw
    -- file offset is accepted too so a hand-built parent still reads.
    local ptr = be32(data, off + 16)
    local rec_pos = ptr >= RAM_BASE and ptr - RAM_BASE or ptr
    if rec_pos + count * RECORD_BYTES > #data then
      error(string.format(
        "%s: the %s record list 0x%08X (+16) does not fit: %d bytes from 0x%06X, the file ends at 0x%06X",
        stage, desc.name, ptr, count * RECORD_BYTES, rec_pos, #data), 0)
    end

    local recs = {}
    for k = 0, count - 1 do
      local ro = rec_pos + k * RECORD_BYTES
      local x  = sbe16(data, ro)
      local y  = sbe16(data, ro + 2)
      local w  = be16(data, ro + 4)
      local h  = be16(data, ro + 6)
      local co = be16(data, ro + 8)
      if w == 0 or h == 0 then
        error(string.format("%s: %s record %d is an empty sprite",
          stage, desc.name, k), 0)
      end
      if w % 2 ~= 0 then
        error(string.format("%s: %s record %d has an odd width %d; a 4bpp row is whole bytes",
          stage, desc.name, k, w), 0)
      end
      recs[k + 1] = { x = x, y = y, w = w, h = h, co = co }
    end

    labels[#labels + 1] = {
      name      = desc.name,
      desc_off  = off,
      rec_pos   = rec_pos,
      pointer   = ptr,
      count     = count,
      recs      = recs,
    }
  end

  return labels
end

-- The selection-mark geometry: descriptor +4 is the choice count, +24 is a
-- list of 20-byte pairs (left record, right record) per choice and +28 is one
-- BE u32 per choice whose low s16 is the centre.  Unlike the +16 label list,
-- these two lists are read only by the drawer's second pass.
local function read_positions(data, stage)
  local rows = {}

  for _, desc in ipairs(DESCRIPTORS) do
    local off = desc.offset
    if off + 32 > #data then
      error(string.format("%s: the %s descriptor at 0x%06X is outside the file",
        stage, desc.name, off), 0)
    end

    local count = be16(data, off + 4)
    if count < 1 or count > MAX_CHOICES then
      error(string.format("%s: the %s choice count is %d at +4; expected 1..%d",
        stage, desc.name, count, MAX_CHOICES), 0)
    end

    local pair_ptr   = be32(data, off + 24)
    local centre_ptr = be32(data, off + 28)
    local pair_pos   = pair_ptr >= RAM_BASE and pair_ptr - RAM_BASE or pair_ptr
    local centre_pos = centre_ptr >= RAM_BASE and centre_ptr - RAM_BASE or centre_ptr
    local pair_len   = count * 20
    local centre_len = count * 4

    if pair_pos + pair_len > #data then
      error(string.format(
        "%s: the %s +24 list 0x%08X does not fit: %d bytes from 0x%06X, the file ends at 0x%06X",
        stage, desc.name, pair_ptr, pair_len, pair_pos, #data), 0)
    end
    if centre_pos + centre_len > #data then
      error(string.format(
        "%s: the %s +28 list 0x%08X does not fit: %d bytes from 0x%06X, the file ends at 0x%06X",
        stage, desc.name, centre_ptr, centre_len, centre_pos, #data), 0)
    end

    local choices = {}
    for k = 0, count - 1 do
      local ro = pair_pos + k * 20
      local left = {
        x = sbe16(data, ro), y = sbe16(data, ro + 2),
        w = be16(data, ro + 4), h = be16(data, ro + 6), co = be16(data, ro + 8),
      }
      local right = {
        x = sbe16(data, ro + 10), y = sbe16(data, ro + 12),
        w = be16(data, ro + 14), h = be16(data, ro + 16), co = be16(data, ro + 18),
      }
      if left.w == 0 or left.h == 0 or right.w == 0 or right.h == 0 then
        error(string.format("%s: %s choice %d has an empty mark sprite",
          stage, desc.name, k), 0)
      end

      local co = centre_pos + k * 4
      choices[k + 1] = {
        center  = sbe16(data, co),
        center2 = be16(data, co + 2),
        left    = left,
        right   = right,
      }
    end

    rows[#rows + 1] = {
      name       = desc.name,
      desc_off   = off,
      count      = count,
      pair_ptr   = pair_ptr,
      centre_ptr = centre_ptr,
      pair_pos   = pair_pos,
      centre_pos = centre_pos,
      choices    = choices,
    }
  end

  return rows
end

-- Metadata is deliberately small and declarative: one entry per row, one entry
-- per choice, with the three values a layout edit actually needs.  Everything
-- else in the pair records (y, w, h, characterOffset) is preserved.
local function positions_json(rows)
  local out = { "{\n  \"rows\": [" }
  for i, row in ipairs(rows) do
    out[#out + 1] = string.format(
      "%s    {\n      \"name\": \"%s\",\n      \"choices\": [",
      i == 1 and "\n" or ",\n", row.name)
    for k, choice in ipairs(row.choices) do
      out[#out + 1] = string.format(
        "%s        { \"center\": %d, \"left\": %d, \"right\": %d }",
        k == 1 and "\n" or ",\n", choice.center, choice.left.x, choice.right.x)
    end
    out[#out + 1] = "\n      ]\n    }"
  end
  out[#out + 1] = "\n  ]\n}\n"
  return table.concat(out)
end

-- A second, private copy of the project's minimal JSON reader.  font.lua keeps
-- its version local; copying the ~90 lines here avoids changing that codec.
local function json_decode(text)
  local i = 1
  local function skip_ws()
    while i <= #text and text:sub(i, i):match("%s") do i = i + 1 end
  end
  local function parse_val()
    skip_ws()
    local c = text:sub(i, i)
    if c == '"' then
      i = i + 1
      local start = i
      while i <= #text and text:sub(i, i) ~= '"' do
        if text:sub(i, i) == '\\' then i = i + 2 else i = i + 1 end
      end
      if i > #text then error("unterminated string", 0) end
      local str = text:sub(start, i - 1)
      i = i + 1
      return str
    elseif c == '{' then
      i = i + 1
      local obj = {}
      while true do
        skip_ws()
        if text:sub(i, i) == '}' then i = i + 1 return obj end
        local key = parse_val()
        if type(key) ~= "string" then error("object key is not a string", 0) end
        skip_ws()
        if text:sub(i, i) ~= ':' then error("expected ':'", 0) end
        i = i + 1
        obj[key] = parse_val()
        skip_ws()
        if text:sub(i, i) == '}' then i = i + 1 return obj end
        if text:sub(i, i) ~= ',' then error("expected ',' or '}'", 0) end
        i = i + 1
      end
    elseif c == '[' then
      i = i + 1
      local arr = {}
      while true do
        skip_ws()
        if text:sub(i, i) == ']' then i = i + 1 return arr end
        arr[#arr + 1] = parse_val()
        skip_ws()
        if text:sub(i, i) == ']' then i = i + 1 return arr end
        if text:sub(i, i) ~= ',' then error("expected ',' or ']'", 0) end
        i = i + 1
      end
    elseif c == 't' then
      if text:sub(i, i + 3) == "true" then i = i + 4 return true end
    elseif c == 'f' then
      if text:sub(i, i + 4) == "false" then i = i + 5 return false end
    elseif c == 'n' then
      if text:sub(i, i + 3) == "null" then i = i + 4 return nil end
    elseif c:match("[%d%-]") then
      local start = i
      while i <= #text and text:sub(i, i):match("[%d%.%-eE]+") do i = i + 1 end
      return tonumber(text:sub(start, i - 1))
    end
    error("unexpected character at byte " .. i, 0)
  end

  skip_ws()
  local val = parse_val()
  skip_ws()
  if i <= #text then error("trailing characters after the value", 0) end
  return val
end

local function only_keys(tbl, allowed, where, stage)
  for key in pairs(tbl) do
    if not allowed[key] then
      error(string.format("%s: %s has an unknown key %q", stage, where, key), 0)
    end
  end
end

-- Validate the metadata and return { ROW_NAME = { {center,left,right}, ... } }.
local function parse_positions(text, rows, stage)
  local ok, root = pcall(json_decode, text)
  if not ok then
    error(stage .. ": invalid JSON: " .. tostring(root), 0)
  end
  if type(root) ~= "table" then
    error(stage .. ": the top level must be an object", 0)
  end
  only_keys(root, { rows = true }, "the top level", stage)
  if type(root.rows) ~= "table" or type(root.rows[1]) ~= "table" then
    error(stage .. ": expected a non-empty \"rows\" array", 0)
  end

  local expected = {}
  for _, row in ipairs(rows) do expected[row.name] = row.count end

  local by_name = {}
  for i, entry in ipairs(root.rows) do
    local where = "rows[" .. i .. "]"
    if type(entry) ~= "table" then
      error(stage .. ": " .. where .. " must be an object", 0)
    end
    only_keys(entry, { name = true, choices = true }, where, stage)
    if type(entry.name) ~= "string" then
      error(stage .. ": " .. where .. ".name must be a string", 0)
    end
    if not expected[entry.name] then
      error(string.format("%s: unknown row %q", stage, entry.name), 0)
    end
    if by_name[entry.name] then
      error(string.format("%s: row %q appears twice", stage, entry.name), 0)
    end
    if type(entry.choices) ~= "table" then
      error(string.format("%s: %s.choices must be an array", stage, where), 0)
    end

    local choices = {}
    for k, choice in ipairs(entry.choices) do
      local cwhere = where .. ".choices[" .. k .. "]"
      if type(choice) ~= "table" then
        error(stage .. ": " .. cwhere .. " must be an object", 0)
      end
      only_keys(choice, { center = true, left = true, right = true }, cwhere, stage)
      for _, key in ipairs({ "center", "left", "right" }) do
        local value = choice[key]
        if type(value) ~= "number" or value % 1 ~= 0 then
          error(string.format("%s: %s.%s must be an integer", stage, cwhere, key), 0)
        end
        if value < -32768 or value > 32767 then
          error(string.format("%s: %s.%s = %d is outside the signed 16-bit range",
            stage, cwhere, key, value), 0)
        end
      end
      choices[k] = { center = choice.center, left = choice.left, right = choice.right }
    end

    if #choices ~= expected[entry.name] then
      error(string.format("%s: %s has %d choices, but the descriptor says %d",
        stage, entry.name, #choices, expected[entry.name]), 0)
    end
    by_name[entry.name] = choices
  end

  for _, row in ipairs(rows) do
    if not by_name[row.name] then
      error(string.format("%s: row %q is missing", stage, row.name), 0)
    end
  end

  return by_name
end

-- Build the two lists without touching y, w, h or characterOffset.  Returns
-- whether anything differs and one write per list that differs.
local function encode_positions(rows, meta, data, stage, labels)
  local writes, changed = {}, false

  for _, row in ipairs(rows) do
    local values = meta[row.name]
    local pair_parts, centre_parts = {}, {}
    for k, src in ipairs(row.choices) do
      local value = values[k]
      pair_parts[#pair_parts + 1] = pack_record(value.left,
        src.left.y, src.left.w, src.left.h, src.left.co)
      pair_parts[#pair_parts + 1] = pack_record(value.right,
        src.right.y, src.right.w, src.right.h, src.right.co)
      local word = (value.center & 0xffff) * 65536 + src.center2
      centre_parts[#centre_parts + 1] = string.pack(">I4", word)
    end

    local pair_bytes   = table.concat(pair_parts)
    local centre_bytes = table.concat(centre_parts)
    local old_pair = data:sub(row.pair_pos + 1, row.pair_pos + #pair_bytes)
    local old_centre = data:sub(row.centre_pos + 1, row.centre_pos + #centre_bytes)
    if pair_bytes ~= old_pair then
      changed = true
      writes[#writes + 1] = { offset = row.pair_pos, data = pair_bytes, name = row.name .. " +24" }
    end
    if centre_bytes ~= old_centre then
      changed = true
      writes[#writes + 1] = { offset = row.centre_pos, data = centre_bytes, name = row.name .. " +28" }
    end
  end

  if not changed then return false, {} end

  -- Distinct lists, and none may sit inside a descriptor, the atlas, the
  -- background stream or a label record that the same encode will write.
  for _, write in ipairs(writes) do
    if write.offset < 0 or write.offset + #write.data > #data then
      error(string.format("%s: the %s list runs outside the file", stage, write.name), 0)
    end
    local clash = overlaps_descriptor(write.offset, #write.data)
    if clash then
      error(string.format("%s: the %s list overlaps the %s descriptor",
        stage, write.name, clash), 0)
    end
    for _, range in ipairs({
      { ATLAS_OFFSET, ATLAS_OFFSET + ATLAS_SLOT, "atlas slot" },
      { BACKGROUND_OFFSET, BACKGROUND_OFFSET + BACKGROUND_SLOT, "background slot" },
    }) do
      if write.offset < range[2] and range[1] < write.offset + #write.data then
        error(string.format("%s: the %s list overlaps the %s",
          stage, write.name, range[3]), 0)
      end
    end
    for _, label in ipairs(labels or {}) do
      if write.offset < label.rec_pos + RECORD_BYTES
        and label.rec_pos < write.offset + #write.data then
        error(string.format("%s: the %s list overlaps the %s label record",
          stage, write.name, label.name), 0)
      end
    end
  end

  for i = 1, #writes do
    for j = i + 1, #writes do
      local a, b = writes[i], writes[j]
      if a.offset < b.offset + #b.data and b.offset < a.offset + #a.data then
        error(string.format("%s: the %s and %s lists overlap",
          stage, a.name, b.name), 0)
      end
    end
  end

  return true, writes
end

-- Compose a label's records into one linear 4bpp strip.  Index 0 is
-- transparent.  Returns the packed pixels, width, height and the origin of the
-- bounding box, which encode reuses so a rebuild keeps the row in place.
local function compose_label(recs, atlas, stage)
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for _, r in ipairs(recs) do
    x0 = math.min(x0, r.x)
    y0 = math.min(y0, r.y)
    x1 = math.max(x1, r.x + r.w)
    y1 = math.max(y1, r.y + r.h)
  end

  local w, h = x1 - x0, y1 - y0
  if w <= 0 or h <= 0 then
    error(stage .. ": the records have an empty bounding box", 0)
  end
  if w % 2 ~= 0 then
    error(string.format("%s: composed width is %d, an odd number of pixels; a 4bpp row is whole bytes",
      stage, w), 0)
  end

  local stride = w // 2
  local px = {}
  for i = 1, stride * h do px[i] = 0 end

  for _, r in ipairs(recs) do
    local src_stride = r.w // 2
    local last = r.co * 8 + (r.h - 1) * src_stride + (r.w - 1) // 2
    if last >= #atlas then
      error(string.format(
        "%s: a record at characterOffset %d reads past the %d-byte sheet",
        stage, r.co, #atlas), 0)
    end

    for row = 0, r.h - 1 do
      for col = 0, r.w - 1 do
        local b = atlas:byte(r.co * 8 + row * src_stride + (col >> 1) + 1)
        local v = (col & 1) == 0 and (b >> 4) or (b & 0x0F)
        if v ~= 0 then
          local dx = r.x - x0 + col
          local di = (r.y - y0 + row) * stride + (dx >> 1) + 1
          local db = px[di]
          if (dx & 1) == 0 then
            px[di] = (db & 0x0F) | (v << 4)
          else
            px[di] = (db & 0xF0) | v
          end
        end
      end
    end
  end

  return bytes_to_string(px), w, h, x0, y0
end

local function atlas_of(data)
  return prs:decode(data:sub(ATLAS_OFFSET + 1, ATLAS_OFFSET + ATLAS_SLOT))[1].data
end

-- The only argument is `rebuild=auto|always`; decode validates it so a typo in
-- the manifest fails at decode time, and encode consumes it.  An empty table is
-- treated as "no arguments" because the house test harness passes `{}`.
local function parse_args(args)
  if type(args) == "table" and next(args) == nil then args = nil end
  return args_parser.parse(args, {
    rebuild = { values = { "auto", "always" }, default = "auto" },
  }, "options menu gfx")
end

-- BMP palette from the parent's second 16-colour bank (label glyphs).
local function preview_palette(data, stage)
  if #data < PALETTE_TEXT + PALETTE_BANK_BYTES then
    error(string.format("%s: the options palette at 0x%06X is outside the file",
      stage, PALETTE_TEXT), 0)
  end
  return bgr555_to_bmp(
    data:sub(PALETTE_TEXT + 1, PALETTE_TEXT + PALETTE_BANK_BYTES), 16)
end

-- The background uses the *first* bank of the same 64-byte palette block.
local function background_palette(data, stage)
  if #data < PALETTE_OFFSET + PALETTE_BANK_BYTES then
    error(string.format("%s: the options palette at 0x%06X is outside the file",
      stage, PALETTE_OFFSET), 0)
  end
  return bgr555_to_bmp(
    data:sub(PALETTE_OFFSET + 1, PALETTE_OFFSET + PALETTE_BANK_BYTES), 16)
end

function codec.decode(data, args)
  if type(data) ~= "string" then
    error("decode: expected binary data, got " .. type(data), 0)
  end
  parse_args(args)
  if #data < ATLAS_OFFSET + ATLAS_SLOT then
    error(string.format("decode: the file is %d bytes; the options atlas slot ends at 0x%06X",
      #data, ATLAS_OFFSET + ATLAS_SLOT), 0)
  end

  local atlas = atlas_of(data)
  if #atlas < ATLAS_PREFIX then
    error(string.format("decode: the options atlas decompresses to %d bytes, expected at least %d",
      #atlas, ATLAS_PREFIX), 0)
  end
  if #atlas > ATLAS_LIMIT then
    error(string.format("decode: the options atlas decompresses to %d bytes, over the 11,520-byte limit",
      #atlas), 0)
  end

  if #data < BACKGROUND_OFFSET + BACKGROUND_SLOT then
    error(string.format("decode: the file is %d bytes; the options background slot ends at 0x%06X",
      #data, BACKGROUND_OFFSET + BACKGROUND_SLOT), 0)
  end
  local background = prs:decode(
    data:sub(BACKGROUND_OFFSET + 1, BACKGROUND_OFFSET + BACKGROUND_SLOT))[1].data
  if #background < BACKGROUND_END then
    error(string.format(
      "decode: the options background decompresses to %d bytes, expected at least %d (the panel plus the 128-byte mark pair)",
      #background, BACKGROUND_END), 0)
  end

  local labels = read_labels(data, "decode")
  local positions = read_positions(data, "decode")
  local pal = preview_palette(data, "decode")
  local bg_pal = background_palette(data, "decode")

  local artifacts = {}
  for _, label in ipairs(labels) do
    local stage = "decode: " .. label.name
    local px, w, h = compose_label(label.recs, atlas, stage)
    if h ~= LABEL_H then
      error(string.format("%s: composed height %d, expected %d", stage, h, LABEL_H), 0)
    end
    artifacts[#artifacts + 1] = {
      name = ARTIFACT_PREFIX .. label.name .. ".bmp",
      data = build_bmp(px, w, LABEL_H, pal, 4),
    }
  end

  artifacts[#artifacts + 1] = {
    name = BACKGROUND_NAME,
    data = build_bmp(
      background:sub(1, BACKGROUND_PIXELS), BACKGROUND_W, BACKGROUND_H,
      bg_pal, 4),
  }

  -- The mark texture is the last 128 bytes of the same background stream.  It
  -- is not in the label atlas, so it is exposed separately and previewed with
  -- the background's own bank (0x05ad98).  The BMP palette never reaches the
  -- file; encode compares pixels only.
  artifacts[#artifacts + 1] = {
    name = BRACKET_LEFT_NAME,
    data = build_bmp(
      background:sub(BRACKET_OFFSET + 1, BRACKET_OFFSET + BRACKET_BYTES),
      BRACKET_W, BRACKET_H, bg_pal, 4),
  }
  artifacts[#artifacts + 1] = {
    name = BRACKET_RIGHT_NAME,
    data = build_bmp(
      background:sub(BRACKET_OFFSET + BRACKET_BYTES + 1, BRACKET_OFFSET + 2 * BRACKET_BYTES),
      BRACKET_W, BRACKET_H, bg_pal, 4),
  }

  artifacts[#artifacts + 1] = {
    name = POSITIONS_NAME,
    data = positions_json(positions),
  }

  return artifacts
end

function codec.encode(original, artifacts, args)
  if type(original) ~= "string" then
    error("encode: expected the parent bytes, got " .. type(original), 0)
  end
  if #original < ATLAS_OFFSET + ATLAS_SLOT then
    error("encode: the parent is too small for the options atlas slot", 0)
  end

  local opts = parse_args(args)

  local labels = read_labels(original, "encode")
  local positions = read_positions(original, "encode")

  -- encode() writes one record into each `+16` target, so those targets must be
  -- distinct, must not sit inside the descriptor table, and must not sit inside
  -- the atlas slot that is rewritten first.
  local seen = {}
  for _, label in ipairs(labels) do
    local clash = overlaps_descriptor(label.rec_pos, RECORD_BYTES)
    if clash then
      error(string.format("encode: the %s record list 0x%08X overlaps the %s descriptor",
        label.name, label.rec_pos, clash), 0)
    end
    if label.rec_pos < ATLAS_OFFSET + ATLAS_SLOT
      and ATLAS_OFFSET < label.rec_pos + RECORD_BYTES then
      error(string.format("encode: the %s record list 0x%08X overlaps the atlas slot",
        label.name, label.rec_pos), 0)
    end
    if label.rec_pos < BACKGROUND_OFFSET + BACKGROUND_SLOT
      and BACKGROUND_OFFSET < label.rec_pos + RECORD_BYTES then
      error(string.format("encode: the %s record list 0x%08X overlaps the background slot",
        label.name, label.rec_pos), 0)
    end
    if seen[label.rec_pos] then
      error(string.format("encode: %s and %s share the record list at 0x%08X",
        seen[label.rec_pos], label.name, label.rec_pos), 0)
    end
    seen[label.rec_pos] = label.name
  end

  local by_name = {}
  for _, artifact in ipairs(artifacts or {}) do
    if type(artifact) == "table" and type(artifact.name) == "string"
      and type(artifact.data) == "string" then
      by_name[artifact.name] = artifact.data
    end
  end

  local strip = {}
  local sum_w = 0
  for _, label in ipairs(labels) do
    local name = ARTIFACT_PREFIX .. label.name .. ".bmp"
    local bmp = by_name[name]
    if not bmp then
      error("encode: " .. name .. " is missing", 0)
    end

    local px, w, h, _, bpp = parse_bmp(bmp, "encode: " .. name, 4)
    if h ~= LABEL_H then
      error(string.format("encode: %s is %d pixels high, but an options label is exactly %d",
        name, h, LABEL_H), 0)
    end
    if bpp ~= 4 then
      error(string.format("encode: %s is %dbpp, but options labels are 4bpp",
        name, bpp), 0)
    end
    if w == 0 or w % LABEL_ALIGN ~= 0 then
      error(string.format("encode: %s is %d pixels wide, not a positive multiple of %d",
        name, w, LABEL_ALIGN), 0)
    end
    if w > LABEL_MAX_W then
      error(string.format("encode: %s is %d pixels wide; a VDP1 record can express at most %d",
        name, w, LABEL_MAX_W), 0)
    end

    strip[#strip + 1] = { name = name, px = px, w = w }
    sum_w = sum_w + w
  end

  -- The background and brackets are optional so a label-only caller keeps
  -- working: absent means "do not touch 0x05ae38".  Both bracket BMPs share
  -- that one stream, so they are composed into the parent tail together and
  -- recompressed once.
  local background_px, background_changed, background_tail
  local background_bmp    = by_name[BACKGROUND_NAME]
  local bracket_left_bmp  = by_name[BRACKET_LEFT_NAME]
  local bracket_right_bmp = by_name[BRACKET_RIGHT_NAME]
  if background_bmp or bracket_left_bmp or bracket_right_bmp then
    local decoded = prs:decode(
      original:sub(BACKGROUND_OFFSET + 1, BACKGROUND_OFFSET + BACKGROUND_SLOT))[1].data
    if #decoded < BACKGROUND_END then
      error(string.format(
        "encode: the parent background decompresses to %d bytes, expected at least %d (the panel plus the 128-byte mark pair)",
        #decoded, BACKGROUND_END), 0)
    end

    local retail_head = decoded:sub(1, BACKGROUND_PIXELS)
    background_px = retail_head
    background_tail = decoded:sub(BACKGROUND_PIXELS + 1)

    if background_bmp then
      local px, w, h = parse_bmp(background_bmp, "encode: " .. BACKGROUND_NAME, 4)
      if w ~= BACKGROUND_W or h ~= BACKGROUND_H then
        error(string.format("encode: %s is %dx%d, but the options background is exactly %dx%d",
          BACKGROUND_NAME, w, h, BACKGROUND_W, BACKGROUND_H), 0)
      end
      background_px = px
      background_changed = px ~= retail_head
    end

    local left = background_tail:sub(BRACKET_TAIL_AT + 1,
      BRACKET_TAIL_AT + BRACKET_BYTES)
    local right = background_tail:sub(BRACKET_TAIL_AT + BRACKET_BYTES + 1,
      BRACKET_TAIL_AT + 2 * BRACKET_BYTES)

    local function read_bracket(bmp, name)
      local px, w, h = parse_bmp(bmp, "encode: " .. name, 4)
      if w ~= BRACKET_W or h ~= BRACKET_H then
        error(string.format("encode: %s is %dx%d, but a selection mark is exactly %dx%d",
          name, w, h, BRACKET_W, BRACKET_H), 0)
      end
      return px
    end

    local new_left  = bracket_left_bmp  and read_bracket(bracket_left_bmp,  BRACKET_LEFT_NAME)  or left
    local new_right = bracket_right_bmp and read_bracket(bracket_right_bmp, BRACKET_RIGHT_NAME) or right
    if new_left ~= left or new_right ~= right then
      background_tail = background_tail:sub(1, BRACKET_TAIL_AT)
        .. new_left .. new_right
        .. background_tail:sub(BRACKET_TAIL_AT + 2 * BRACKET_BYTES + 1)
      background_changed = true
    end
  end

  -- The positions metadata is independent of the pixels and of the label
  -- records.  It writes only +24/+28, never the +8 hit rectangles.
  local positions_changed, position_writes = false, {}
  local positions_bmp = by_name[POSITIONS_NAME]
  if positions_bmp then
    local meta = parse_positions(positions_bmp, positions, "encode: " .. POSITIONS_NAME)
    positions_changed, position_writes = encode_positions(
      positions, meta, original, "encode: " .. POSITIONS_NAME, labels)
  end

  -- The unchanged fast path is a pixel comparison, so it works the same for a
  -- glyph-based parent and for one this codec already rebuilt as strips.  The
  -- composed origin is what the replacement strip is anchored on.
  local atlas = atlas_of(original)
  if #atlas < ATLAS_PREFIX then
    error(string.format("encode: the parent atlas decompresses to %d bytes, expected at least %d",
      #atlas, ATLAS_PREFIX), 0)
  end
  local origin = {}
  local changed = false
  for i, label in ipairs(labels) do
    local px, w, _, x0, y0 = compose_label(label.recs, atlas,
      "encode: " .. label.name)
    origin[i] = { x = x0, y = y0 }
    if w ~= strip[i].w or px ~= strip[i].px then
      changed = true
    end
  end
  -- A background-only edit must not rebuild the label sheet: the retail
  -- glyphs 42..71 would be replaced by strips for no reason.  Likewise a
  -- label edit leaves the background bytes alone, and a position-only edit
  -- leaves both pixel resources alone.
  local rebuild_labels = changed or opts.rebuild == "always"
  if not rebuild_labels and not background_changed and not positions_changed then
    return original
  end

  local new_data = original
  local offsets = {}

  if rebuild_labels then
    local sheet_len = ATLAS_PREFIX + 8 * sum_w
    if sheet_len > ATLAS_LIMIT then
      error(string.format(
        "encode: the five labels need %d decoded bytes (64 + 8 * %d pixels), over the 11,520-byte sheet limit (at most 1,432 pixels)",
        sheet_len, sum_w), 0)
    end

    -- Preserved head, then one strip per label in descriptor order.  A w-pixel
    -- strip is w * 16 / 2 = w * 8 bytes, so every offset stays 8-byte aligned.
    local parts = { atlas:sub(1, ATLAS_PREFIX) }
    local at = ATLAS_PREFIX
    for i = 1, #strip do
      offsets[i] = at
      parts[#parts + 1] = strip[i].px
      at = at + strip[i].w * 8
    end
    local sheet = table.concat(parts)
    if #sheet ~= sheet_len then
      error(string.format("encode: internal sheet length %d, expected %d", #sheet, sheet_len), 0)
    end

    local stream = prs:encode("", { { name = "DECOMPRESSED", data = sheet } })
    if #stream > ATLAS_SLOT then
      error(string.format(
        "encode: the rebuilt sheet compresses to %d bytes, over the 3,782-byte slot (shed %d bytes)",
        #stream, #stream - ATLAS_SLOT), 0)
    end

    local slot = stream .. string.rep("\0", ATLAS_SLOT - #stream)
    new_data = put(new_data, ATLAS_OFFSET, slot)

    for i, label in ipairs(labels) do
      local w = strip[i].w
      new_data = put(new_data, label.rec_pos,
        pack_record(origin[i].x, origin[i].y, w, LABEL_H, offsets[i] // 8))
      -- `+12` is the label count in the high half of a BE u32; the low half is 0.
      new_data = put(new_data, label.desc_off + 12, "\0\1\0\0")
    end
  end

  if positions_changed then
    for _, write in ipairs(position_writes) do
      new_data = put(new_data, write.offset, write.data)
    end
  end

  if background_changed then
    -- 512-entry chains: the retail tail recompresses to 1,271 bytes with the
    -- default 256, over the slot, and to 1,245 with the deeper search.
    local bg_stream = prs:encode("", { { name = "DECOMPRESSED", data = background_px .. background_tail } },
      string.format('{"chain":%d}', BACKGROUND_CHAIN))
    if #bg_stream > BACKGROUND_SLOT then
      error(string.format(
        "encode: the background (panel plus selection marks) compresses to %d bytes, over the 1,256-byte slot (shed %d bytes)",
        #bg_stream, #bg_stream - BACKGROUND_SLOT), 0)
    end
    new_data = put(new_data, BACKGROUND_OFFSET,
      bg_stream .. string.rep("\0", BACKGROUND_SLOT - #bg_stream))
  end

  -- Only the slots and the two independent data sets may differ.
  local allowed = {}
  if rebuild_labels then
    allowed[#allowed + 1] = { ATLAS_OFFSET, ATLAS_OFFSET + ATLAS_SLOT }
  end
  if background_changed then
    allowed[#allowed + 1] = { BACKGROUND_OFFSET, BACKGROUND_OFFSET + BACKGROUND_SLOT }
  end
  if rebuild_labels then
    for _, label in ipairs(labels) do
      allowed[#allowed + 1] = { label.desc_off + 12, label.desc_off + 16 }
      allowed[#allowed + 1] = { label.rec_pos, label.rec_pos + RECORD_BYTES }
    end
  end
  for _, write in ipairs(position_writes) do
    allowed[#allowed + 1] = { write.offset, write.offset + #write.data }
  end

  local stray
  for off = 0, #original - 1 do
    if new_data:byte(off + 1) ~= original:byte(off + 1) then
      local ok = false
      for _, range in ipairs(allowed) do
        if off >= range[1] and off < range[2] then ok = true; break end
      end
      if not ok and not stray then stray = off end
    end
  end
  if stray then
    error(string.format("encode: first unexpected modified byte at 0x%06X", stray), 0)
  end

  return new_data
end

function codec.can_handle(data)
  if type(data) ~= "string" then
    return "no"
  end
  if #data < ATLAS_OFFSET + ATLAS_SLOT then
    return "no"
  end
  -- Hash only a file of the right size: can_handle also sees whole disc images,
  -- and the codec's offsets are meaningless outside this executable.
  if #data == FILE_BYTES and sha256.hex(data) == FILE_SHA256 then
    return "certain"
  end

  -- Weaker, content-based evidence: the five descriptors must look like option
  -- rows and the atlas must decompress.
  for _, desc in ipairs(DESCRIPTORS) do
    if be32(data, desc.offset + 20) ~= TEXTURE_BASE then
      return "no"
    end
    local count = be16(data, desc.offset + 12)
    if count < 1 or count > MAX_RECORDS then
      return "no"
    end
    local ptr = be32(data, desc.offset + 16)
    local rec_pos = ptr >= RAM_BASE and ptr - RAM_BASE or ptr
    if rec_pos + count * RECORD_BYTES > #data then
      return "no"
    end
  end

  local ok, atlas = pcall(function()
    return prs:decode(data:sub(ATLAS_OFFSET + 1, ATLAS_OFFSET + ATLAS_SLOT))[1].data
  end)
  if not ok or type(atlas) ~= "string" or #atlas < ATLAS_PREFIX then
    return "no"
  end

  return "likely"
end

function codec.decode_name(args)
  return "OPTIONS"
end

return codec
