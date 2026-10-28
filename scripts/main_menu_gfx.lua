--[[
  Sakura Taisen (Saturn) — Main Menu Graphics Patch Plugin

  PATCH plugin for the main-menu graphics PatchMainMenu() rewrites in
  SAKURA1/LOGO.SH2 (SakuraTaisen.cpp:8632), plus the six label descriptors that
  live in the same module:

      0x0000ff20   2280 bytes  main-menu font atlas, PRS
      0x00010808   3942 bytes  main-menu background, PRS
      0x000038a0   4 bytes     RAM address of the background block,
                              0x214808 + max(0, fontSize - 2280)
      0x00003890   2 bytes     font DMA length (0x1600 at retail)
      0x00006234   24 bytes    six big-endian u32 label record pointers
      0x0000624c   6 bytes     six u8 label record counts
      0x00029324   512 bytes   background palette, 256 x BGR555 big-endian

  ## The labels

  Each of the six menu entries is a list of records, ten bytes each, five
  big-endian u16 fields:

      +0  x                 signed, label space, origin at the window centre
      +2  y                 signed
      +4  w                 sprite width in pixels (VDP1 CMDSIZE units of 8)
      +6  h                 sprite height in pixels
      +8  characterOffset   VDP1 address of the texture / 8

  The renderer turns the last field into CMDSRCA = 0x1400 + characterOffset and
  reads the texture from VDP1 0xA000 + 8 * characterOffset, i.e. from the font
  atlas this codec compresses at 0xFF20.  Records may share a texture: the
  Japanese labels reuse glyph 0 in four of the six entries.

  The shipped Japanese labels are 16x16 glyph records - 8, 5, 8, 7, 7 and 8 of
  them, in descriptor-table order:

      00_NEW_GAME  01_OPTIONS  02_CONTINUE  03_RESUME  04_THEATER  05_BATTLE_TRIAL

  The numbers are the descriptor indices, not the on-screen order.  LOGO.SH2's
  renderer draws at most five slots per frame and takes each slot's descriptor
  from menu state at run time, so the six tables are a catalogue, not a layout.
  See SAKTAI_MAIN_MENU.md for the renderer, the upload pipeline and the budget
  arithmetic; this codec does not touch any of that state.

  ## Artifacts

      MAINMENU/00_NEW_GAME.bmp      4bpp, 128 x 16 at retail
      MAINMENU/01_OPTIONS.bmp       4bpp,  80 x 16
      MAINMENU/02_CONTINUE.bmp      4bpp, 128 x 16
      MAINMENU/03_RESUME.bmp        4bpp, 112 x 16
      MAINMENU/04_THEATER.bmp       4bpp, 112 x 16
      MAINMENU/05_BATTLE_TRIAL.bmp  4bpp, 128 x 16
      MAINMENU/BG.bmp               8bpp, 208 x 152, the file's 256 colours

  A label BMP is the whole rendered label, not a grid of tiles.  decode()
  composes it from the records: the bounding box of every rectangle becomes the
  BMP, each record's texture is blitted at (x, y) relative to that box, and
  palette index 0 is left transparent (the renderer draws colour 0 as
  transparent too).  The Japanese labels therefore come out as one strip each,
  even though the file stores them as separate 16x16 glyph records.

  Editing a label BMP replaces all of that label's records with one record:

      x = -width / 2,  y = -8,  w = width,  h = 16
      characterOffset = texture_byte_offset / 8

  All six labels are then repacked as independent linear 4bpp textures, in
  descriptor-table order, each one width*8 bytes long (width*16 pixels at
  4bpp).  x = -width / 2 centres the sprite on the menu window, and y = -8
  keeps its middle on the label baseline; that is the convention the shipped
  data uses.  Offsets are multiples of 64 bytes, so every characterOffset is a
  multiple of 8 and the VDP1 address stays 8-byte aligned.

  Widths are free (a positive multiple of 8, up to the 2,040 pixels VDP1's
  width field can hold; past 320 the screen clips the edges); heights are not:
  every label is exactly 16 pixels high because every record is.  A label
  narrower or wider than its original is expected - the renderer uses the
  record, not a shared 144-pixel allocation.

  ## Palette

  Label BMPs carry the ADV dialogue ramp from shared/palettes.lua
  (adv_dialogue_i18n) as a display palette and nothing else.  The labels are
  4bpp indices recoloured by the game; those colours never reach LOGO.SH2, so
  encode() ignores a label palette completely and a palette-only edit is not a
  change.  Index 0 is transparency: leave it 0 for the background of a label.

  BG.bmp's palette is real: all 256 entries of BGR555 big-endian at 0x29324,
  read from there and written back.  A palette-only background edit is a real
  change and is encoded.

  ## Round-tripping

  If no label pixel changes - and the background and its palette do not either
  - encode() returns the input byte for byte.  That is what keeps a
  BG.bmp-only edit from converting the Japanese glyph atlas into strips: the
  font block, all six record tables, the counts and the DMA length are copied
  untouched.  Whether a file is glyph-based or strip-based is never inferred
  from its record counts; each record is read through its own w/h/characterOffset
  and the composed pixels are compared.

  ## DMA length

  LOGO.SH2's init (0x2077CE) loads the transfer length with `mov.w
  0x207890`, a literal-pool word at file offset 0x3890.  The retail value is
  0x1600 = 5,632 bytes: the 5,120-byte atlas plus 512 bytes of slack, and
  enough for the 43 records (33 distinct glyphs) the Japanese labels use.  A
  rebuilt strip atlas is usually longer than that, so encode() raises the word
  to the decompressed atlas length - never lowers it, because a shorter
  transfer leaves whatever the previous decode left in the staging buffer.
  `mov.w` sign-extends, so 0x7FFF is the largest safe positive length; the
  atlas is also bounded by the next VDP1 upload at 0xA000 + 0x18800.  No SH-2
  instruction is modified: this is a data word in the module's literal pool.

  The atlas must compress into the same 6,222-byte region as the background
  (0xFF20 .. 0x1176E):

      font slot   max(font PRS, 2280)   the background starts after this
      background  its PRS, 3,942 at retail (3,781 recompressed)

  If the font fits 2,280 bytes the background keeps its address.  If it does
  not, the background moves right inside the region and the pointer at 0x38A0
  is rewritten, exactly as PatchMainMenu does.  When that still does not fit
  and the background itself was not edited, encode() recompresses the
  background to reclaim the difference before refusing.  Running out of budget
  is an explicit error that reports both sizes and the bytes to shed; nothing
  outside 0xFF20 .. 0x1176E is ever written, and LOGO.SH2 keeps its size.

  The shipping file is 243,200 bytes:

      md5     8d8a7a4affd6bc2e73ccd5ed4a3592a9
      sha256 dbe0c2e777ddbc47a46856e79ee7ccf06b546d3e4a7d7be7dc10d9bb3c32cf1d
]]

local function script_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then
    return src:sub(2):match("^(.*)[/\\][^/\\]*$") or "."
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

local prs      = LUDARED.codec("std/sega/compression/prs")
local palettes = load_shared("palettes")
local sha256   = load_shared("sha256")

local codec = {}

codec.name        = "Sakura Taisen Main Menu Graphics"
codec.description = "PATCH plugin for the six main-menu labels and the background in LOGO.SH2"
-- 3: FONT.bmp is gone.  The six labels are separate, variable-width BMPs and
-- the record tables, counts and DMA length are written with them, so cached
-- decodes from version 2 cannot be re-encoded.
codec.version     = 3
codec.kind        = "patch"

local FONT_OFFSET   = 0x0000ff20
local FONT_SIZE     = 2280
local BGND_SIZE     = 3942                              -- the background's slot
                                                        -- at the shipped 0x00010808
local BUDGET        = FONT_SIZE + BGND_SIZE          -- 6222
-- The writable region stops at 0x1176E.  Do not extend it to the next
-- interesting-looking offset: 0x11770 is the first byte of LOGO export #6's
-- disc-1 scene background (a PRS stream that decodes to 0xF240 bytes), and
-- the only slack is the two zero bytes at 0x1176E..0x11770.  encode() copies
-- everything from TAIL_OFFSET on unchanged.
local TAIL_OFFSET   = FONT_OFFSET + BUDGET           -- 0x1176e
local POINTER_OFFSET = 0x000038a0
local POINTER_BASE   = 0x214808
-- The background palette is real data: 256 entries of BGR555 big-endian at
-- 0x29324 in LOGO.SH2 itself -- the same field PatchMainMenu overwrites.
local PALETTE_OFFSET = 0x00029324
local PALETTE_SIZE   = 512

local FILE_BYTES  = 243200
local FILE_SHA256 = "dbe0c2e777ddbc47a46856e79ee7ccf06b546d3e4a7d7be7dc10d9bb3c32cf1d"
-- md5 8d8a7a4affd6bc2e73ccd5ed4a3592a9

-- Label descriptor tables, as file offsets.  Pointers are RAM addresses and
-- resolve against the module's load address; the records themselves sit just
-- after the count table in the shipping file.
local MODULE_BASE    = 0x00204000
local TABLE_POINTERS = 0x00006234
local TABLE_COUNTS   = 0x0000624c
local RECORD_BYTES   = 10
local LABEL_COUNT    = 6

-- Font DMA length: a literal-pool word read by `mov.w`, sign-extended.
local DMA_OFFSET = 0x00003890
local DMA_MAX    = 0x7FFF
-- The font is uploaded to VDP1 0xA000; the next upload starts at 0x22800.
local ATLAS_VRAM = 0x0000a000
local ATLAS_NEXT = 0x00022800

local LABEL_H       = 16
-- VDP1's CMDSIZE width field is 8 bits of 8-pixel columns.  Anything wider
-- cannot be expressed in a record at all; anything over 320 is clipped by the
-- screen, but that is the artist's call, not the codec's.
local LABEL_MAX_W   = 255 * 8
local LABEL_ALIGN   = 8

local LABEL_NAMES = {
  "00_NEW_GAME",
  "01_OPTIONS",
  "02_CONTINUE",
  "03_RESUME",
  "04_THEATER",
  "05_BATTLE_TRIAL",
}

local BGND_W, BGND_H   = 208, 152
local BGND_PIXELS      = BGND_W * BGND_H           -- 31616, one byte each

local BMP_FILE_HEADER = 14
local BMP_INFO_HEADER = 40
local BMP_CLR_USED    = 46                         -- 0-based biClrUsed

local function row_stride(width, bpp)
  return ((width * bpp + 31) // 32) * 4
end

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

local function bmp_to_bgr555(pal_bgra, colours)
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

-- Label BMPs are drawn with the ADV dialogue palette from shared/palettes.lua,
-- which is the ramp the SAKURA executable applies to menu text.  It is display
-- only: the label carries 4bpp indices, these colours never reach LOGO.SH2, and
-- encode() ignores them.
-- local function default_label_palette()
--   return bgr555_to_bmp(palettes.raw("adv_dialogue_i18n"), 16)
-- end
local function default_label_palette()
  local pal = bgr555_to_bmp(palettes.raw("adv_dialogue_i18n"), 16)
  return pal:sub(1, 60) .. "\x00\x00\xFF\x00"
end

local function build_bmp(pixels, width, height, pal, bpp)
  local stride   = row_stride(width, bpp)
  local row_bytes = width * bpp // 8
  local rows = {}
  for y = 0, height - 1 do
    local row = pixels:sub(y * row_bytes + 1, (y + 1) * row_bytes)
    if #row < row_bytes then row = row .. string.rep("\x00", row_bytes - #row) end
    rows[y + 1] = row .. string.rep("\x00", stride - row_bytes)
  end
  local body = table.concat(rows)
  local off  = BMP_FILE_HEADER + BMP_INFO_HEADER + #pal
  local hdr = string.pack("<c2I4I2I2I4I4i4i4I2I2I4I4I4I4I4I4",
    "BM", off + #body, 0, 0, off,
    BMP_INFO_HEADER, width, -height, 1, bpp, 0, #body, 0, 0, #pal // 4, 0)
  return hdr .. pal .. body
end

local function parse_bmp(bmp, stage, want_bpp)
  if #bmp < BMP_FILE_HEADER + BMP_INFO_HEADER then
    error(stage .. ": BMP too short", 0)
  end
  if bmp:sub(1, 2) ~= "BM" then
    error(stage .. ": not a BMP file", 0)
  end
  local off, info_len, width, height, planes, bpp, comp =
    string.unpack("<I4I4i4i4I2I2I4", bmp, 11)
  if planes ~= 1 then error(stage .. ": biPlanes != 1", 0) end
  if comp ~= 0 then error(stage .. ": compressed BMP", 0) end
  if info_len < BMP_INFO_HEADER then error(stage .. ": DIB header too small", 0) end
  if width <= 0 or height == 0 then error(stage .. ": empty image", 0) end
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
    error(stage .. ": truncated pixel data", 0)
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

  -- The palette sits immediately before the pixels whatever the DIB header
  -- length; editors other than this codec can write a longer header.  biClrUsed
  -- is authoritative when it is set.
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

-- Walk the six descriptor tables and check every record against the atlas.
-- Returns { { pointer, count, recs }, ... } or nil plus a reason.  A record is
-- accepted on its own w/h/characterOffset: nothing here assumes 16x16 tiles or
-- a strip, so a single-record Japanese label and a generated strip read alike.
local function read_records(data, font)
  local labels = {}
  for i = 1, LABEL_COUNT do
    local pointer = be32(data, TABLE_POINTERS + (i - 1) * 4)
    local count   = data:byte(TABLE_COUNTS + i)
    local base    = pointer - MODULE_BASE
    if base < 0 or base + count * RECORD_BYTES > #data then
      return nil, string.format(
        "label %d: %d records at 0x%06X do not fit in the file",
        i - 1, count, pointer)
    end
    if count == 0 then
      return nil, string.format("label %d: no records", i - 1)
    end

    local recs = {}
    for k = 0, count - 1 do
      local off = base + k * RECORD_BYTES
      local w, h = be16(data, off + 4), be16(data, off + 6)
      local co   = be16(data, off + 8)
      if w == 0 or h == 0 then
        return nil, string.format("label %d record %d: empty sprite", i - 1, k)
      end
      if w % LABEL_ALIGN ~= 0 then
        return nil, string.format(
          "label %d record %d: width %d is not a multiple of %d",
          i - 1, k, w, LABEL_ALIGN)
      end
      local tex = co * 8
      if tex + w * h // 2 > #font then
        return nil, string.format(
          "label %d record %d: texture %d+%d runs past the %d-byte font atlas",
          i - 1, k, tex, w * h // 2, #font)
      end
      recs[k + 1] = {
        x = sbe16(data, off), y = sbe16(data, off + 2),
        w = w, h = h, co = co,
      }
    end

    -- The composed BMP is one linear strip: an odd bounding box would need a
    -- half-byte per row, which no 4bpp image can hold.
    local x0, x1 = math.huge, -math.huge
    for _, r in ipairs(recs) do
      x0 = math.min(x0, r.x); x1 = math.max(x1, r.x + r.w)
    end
    if (x1 - x0) % 2 ~= 0 then
      return nil, string.format(
        "label %d: records span %d pixels, a half byte per row", i - 1, x1 - x0)
    end

    labels[i] = { pointer = pointer, count = count, recs = recs }
  end
  return labels
end

-- Compose a label's records into one linear 4bpp image: the bounding box of
-- every rectangle, with each texture blitted at its record's offset.  Index 0
-- is transparent, exactly as VDP1 draws it, so overlapping glyphs composite
-- instead of punching holes.  The original labels arrive as 16x16 records and
-- leave as a single strip, which is the point.
local function compose_label(label, font)
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for _, r in ipairs(label.recs) do
    x0 = math.min(x0, r.x); y0 = math.min(y0, r.y)
    x1 = math.max(x1, r.x + r.w); y1 = math.max(y1, r.y + r.h)
  end

  local w, h = x1 - x0, y1 - y0
  local stride = w // 2
  local px = {}
  for i = 1, stride * h do px[i] = 0 end

  for _, r in ipairs(label.recs) do
    local tex, src_stride = r.co * 8, r.w // 2
    for row = 0, r.h - 1 do
      for col = 0, r.w - 1 do
        local b = font:byte(tex + row * src_stride + (col >> 1) + 1)
        local v = (col & 1) == 0 and (b >> 4) or (b & 0x0F)
        if v ~= 0 then
          local dx, dy = r.x - x0 + col, r.y - y0 + row
          local di = dy * stride + (dx >> 1) + 1
          local db = px[di]
          if (dx & 1) == 0 then db = (db & 0x0F) | (v << 4)
          else db = (db & 0xF0) | v end
          px[di] = db
        end
      end
    end
  end

  return string.char(table.unpack(px)), w, h
end

local function pack_record(x, y, w, h, co)
  return string.pack(">i2i2I2I2I2", x, y, w, h, co)
end

-- Replace #bytes at a 0-based file offset; the length never changes.
local function put(s, offset, bytes)
  return s:sub(1, offset) .. bytes .. s:sub(offset + #bytes + 1)
end

-- Read the file the way decode() will and say whether the main menu is really
-- there: the pointer must imply a font slot that fits, the six descriptor
-- tables must read against the decompressed atlas, and the background must
-- decompress to the one pixel count the game uploads.  Cheap, because it only
-- ever looks at 6,222 bytes, and it is what separates a LOGO.SH2 from any
-- other file this size -- including a rebuild whose hash no longer matches.
local function probe(data)
  if #data ~= FILE_BYTES then return false end

  local pointer = string.unpack(">I4", data, POINTER_OFFSET + 1)
  local slot = pointer - POINTER_BASE + FONT_SIZE
  if slot < FONT_SIZE or FONT_OFFSET + slot >= TAIL_OFFSET then return false end

  local font = prs:decode(data:sub(FONT_OFFSET + 1, FONT_OFFSET + slot))[1].data
  if #font == 0 then return false end
  if not read_records(data, font) then return false end

  local bgnd = prs:decode(data:sub(FONT_OFFSET + slot + 1, TAIL_OFFSET))[1].data
  return #bgnd == BGND_PIXELS
end

function codec.can_handle(data)
  if type(data) ~= "string" then return "no" end
  if not probe(data) then return "no" end
  if sha256.hex(data) == FILE_SHA256 then return "certain" end
  -- The main menu reads as this codec expects it to, but the file is not the
  -- build these offsets were mapped on: same format, unverified edges.
  return "likely"
end

function codec.decode_name(args)
  return "MAINMENU"
end

function codec.decode(data, args)
  if type(data) ~= "string" then error("decode: expected binary string", 0) end
  if #data < TAIL_OFFSET then error("decode: LOGO.SH2 is too small", 0) end

  -- The background does not always sit at its shipped offset: a rebuilt file
  -- whose font grew pushes it right and records the move in the pointer, so
  -- recover the font slot from there.  A pristine file yields 2280.
  local pointer = string.unpack(">I4", data, POINTER_OFFSET + 1)
  local slot = pointer - POINTER_BASE + FONT_SIZE
  if slot < FONT_SIZE or FONT_OFFSET + slot >= TAIL_OFFSET then
    error(string.format(
      "decode: background pointer 0x%06X implies a %d-byte font slot, which does "
      .. "not fit the main menu region", pointer, slot), 0)
  end

  local font = prs:decode(data:sub(FONT_OFFSET + 1, FONT_OFFSET + slot))[1].data
  local bgnd = prs:decode(data:sub(FONT_OFFSET + slot + 1, TAIL_OFFSET))[1].data
  if #font == 0 then
    error("decode: the font block decompresses to nothing", 0)
  end
  if #bgnd ~= BGND_PIXELS then
    error(string.format(
      "decode: background block is %d bytes, but %dx%d at 8bpp is %d",
      #bgnd, BGND_W, BGND_H, BGND_PIXELS), 0)
  end

  local labels, why = read_records(data, font)
  if not labels then error("decode: " .. why, 0) end

  local palette = default_label_palette()
  local artifacts = {}
  for i, label in ipairs(labels) do
    local px, w, h = compose_label(label, font)
    artifacts[#artifacts + 1] = {
      name = "MAINMENU/" .. LABEL_NAMES[i] .. ".bmp",
      data = build_bmp(px, w, h, palette, 4),
    }
  end

  artifacts[#artifacts + 1] = {
    name = "MAINMENU/BG.bmp",
    data = build_bmp(bgnd, BGND_W, BGND_H,
      bgr555_to_bmp(data:sub(PALETTE_OFFSET + 1, PALETTE_OFFSET + PALETTE_SIZE), 256), 8),
  }
  return artifacts
end

function codec.encode(original, artifacts, args)
  if type(original) ~= "string" then
    error("encode: expected binary string for `original`", 0)
  end
  if #original < TAIL_OFFSET then
    error("encode: LOGO.SH2 is too small for the main menu blocks", 0)
  end

  local by_name = {}
  for _, artifact in ipairs(artifacts or {}) do
    if type(artifact) == "table" and type(artifact.name) == "string" then
      by_name[artifact.name] = artifact.data
    end
  end

  local labels = {}
  for i = 1, LABEL_COUNT do
    local name = "MAINMENU/" .. LABEL_NAMES[i] .. ".bmp"
    local bmp = by_name[name]
    if not bmp then error("encode: " .. name .. " is missing", 0) end

    local px, w, h = parse_bmp(bmp, name, 4)
    if h ~= LABEL_H then
      error(string.format(
        "encode: %s is %dx%d, but a menu label is exactly %d pixels high",
        name, w, h, LABEL_H), 0)
    end
    if w % LABEL_ALIGN ~= 0 then
      error(string.format(
        "encode: %s is %d pixels wide, not a multiple of %d",
        name, w, LABEL_ALIGN), 0)
    end
    if w > LABEL_MAX_W then
      error(string.format(
        "encode: %s is %d pixels wide; a VDP1 sprite record cannot express "
        .. "more than %d", name, w, LABEL_MAX_W), 0)
    end
    labels[i] = { name = name, px = px, w = w }
  end

  local bgnd_bmp = by_name["MAINMENU/BG.bmp"]
  if not bgnd_bmp then error("encode: MAINMENU/BG.bmp is missing", 0) end
  local bgnd, bw, bh, pal = parse_bmp(bgnd_bmp, "MAINMENU/BG.bmp", 8)
  if bw ~= BGND_W or bh ~= BGND_H then
    error(string.format(
      "encode: MAINMENU/BG.bmp is %dx%d, but the background is %dx%d",
      bw, bh, BGND_W, BGND_H), 0)
  end

  -- The parent is not necessarily pristine: an earlier pass on this node, or a
  -- grown font, moves the background right and records the slot in the pointer.
  -- Slice from there the way decode() does instead of assuming 2,280 bytes.
  local parent_pointer = string.unpack(">I4", original, POINTER_OFFSET + 1)
  local parent_slot = parent_pointer - POINTER_BASE + FONT_SIZE
  if parent_slot < FONT_SIZE or FONT_OFFSET + parent_slot >= TAIL_OFFSET then
    error(string.format(
      "encode: background pointer 0x%06X implies a %d-byte font slot, which does "
      .. "not fit the main menu region", parent_pointer, parent_slot), 0)
  end

  local original_font = prs:decode(original:sub(FONT_OFFSET + 1, FONT_OFFSET + parent_slot))[1].data
  local original_bgnd = prs:decode(original:sub(FONT_OFFSET + parent_slot + 1, TAIL_OFFSET))[1].data
  if #original_font == 0 then
    error("encode: the parent's font block decompresses to nothing", 0)
  end
  if #original_bgnd ~= BGND_PIXELS then
    error(string.format(
      "encode: the parent's background block is %d bytes, not %d",
      #original_bgnd, BGND_PIXELS), 0)
  end

  local parent_labels, why = read_records(original, original_font)
  if not parent_labels then
    error("encode: the parent's label table does not read: " .. why, 0)
  end

  -- A label changed if its pixels or its width differ from what the parent
  -- composes to.  Counts are deliberately not part of this: a Japanese label
  -- with one record and a generated strip are told apart by their pixels.
  local labels_changed = false
  for i = 1, LABEL_COUNT do
    local px, w = compose_label(parent_labels[i], original_font)
    if px ~= labels[i].px or w ~= labels[i].w then labels_changed = true end
  end

  local original_palette = original:sub(PALETTE_OFFSET + 1, PALETTE_OFFSET + PALETTE_SIZE)
  local bgnd_changed = bgnd ~= original_bgnd
  local pal_changed  = pal ~= bgr555_to_bmp(original_palette, 256)

  -- Nothing changed: keep the parent's bytes byte for byte.  The palette counts
  -- as content, but a label BMP's palette does not: it is a display ramp.
  if not labels_changed and not bgnd_changed and not pal_changed then
    return original
  end

  local font_prs, new_records, new_dma
  if labels_changed then
    -- Repack all six labels as independent strips, in descriptor order.  Each
    -- one is width*8 bytes; every offset is therefore a multiple of 64 and
    -- stays 8-byte aligned for the VDP1 address.
    local parts, offsets = {}, {}
    local at = 0
    for i = 1, LABEL_COUNT do
      offsets[i] = at
      parts[i] = labels[i].px
      at = at + #labels[i].px
    end
    local atlas = table.concat(parts)

    if at > DMA_MAX then
      error(string.format(
        "encode: the label atlas is %d bytes of 4bpp pixels, over the %d-byte "
        .. "limit of the font DMA length", at, DMA_MAX), 0)
    end
    if ATLAS_VRAM + at > ATLAS_NEXT then
      error(string.format(
        "encode: the label atlas needs %d bytes at VDP1 0x%05X, past the next "
        .. "upload at 0x%05X", at, ATLAS_VRAM, ATLAS_NEXT), 0)
    end

    local dma = sbe16(original, DMA_OFFSET)
    new_dma = math.max(dma, at)
    if new_dma > DMA_MAX then
      error(string.format(
        "encode: the font DMA would need %d bytes, over the %d-byte positive "
        .. "range of `mov.w`", new_dma, DMA_MAX), 0)
    end

    new_records = {}
    for i = 1, LABEL_COUNT do
      new_records[i] = {
        offset = parent_labels[i].pointer - MODULE_BASE,
        bytes = pack_record(-(labels[i].w // 2), -LABEL_H // 2, labels[i].w, LABEL_H,
          offsets[i] // 8),
      }
    end

    font_prs = prs:encode("", { { name = "DECOMPRESSED", data = atlas } })
    if #font_prs % 2 == 1 then font_prs = font_prs .. "\x00" end   -- PatchMainMenu pads to even
  else
    -- Only the background or its palette changed: the Japanese atlas, its
    -- records, counts and DMA length are copied exactly as they are.
    font_prs = original:sub(FONT_OFFSET + 1, FONT_OFFSET + parent_slot)
  end

  local bgnd_prs
  if bgnd_changed then
    bgnd_prs = prs:encode("", { { name = "DECOMPRESSED", data = bgnd } }, '{"chain": 2048}')
  else
    -- Everything between the font slot and the fixed tail is the background
    -- plus its padding; copying the lot keeps an unchanged block byte for byte.
    bgnd_prs = original:sub(FONT_OFFSET + parent_slot + 1, TAIL_OFFSET)
  end

  local font_slot = math.max(#font_prs, FONT_SIZE)
  if font_slot + #bgnd_prs > BUDGET and not bgnd_changed then
    -- The font grew past its slot and the background is still the shipped
    -- bytes.  Recompress it for real to reclaim the difference; only use the
    -- result if it actually helps.
    local squeezed = prs:encode("", { { name = "DECOMPRESSED", data = original_bgnd } })
    if #squeezed < #bgnd_prs then bgnd_prs = squeezed end
  end
  if font_slot + #bgnd_prs > BUDGET then
    error(string.format(
      "encode: compressed main menu data needs %d bytes (font %d + background %d), "
      .. "but only %d bytes fit in 0xFF20..0x1176E.  Shed %d byte%s",
      font_slot + #bgnd_prs, font_slot, #bgnd_prs, BUDGET,
      font_slot + #bgnd_prs - BUDGET,
      font_slot + #bgnd_prs - BUDGET == 1 and "" or "s"), 0)
  end

  local pointer = POINTER_BASE + font_slot - FONT_SIZE
  local out = original:sub(1, FONT_OFFSET)
    .. font_prs
    .. string.rep("\x00", font_slot - #font_prs)
    .. bgnd_prs
    .. string.rep("\x00", TAIL_OFFSET - (FONT_OFFSET + font_slot + #bgnd_prs))
    .. original:sub(TAIL_OFFSET + 1)

  -- Pointer and palette, big-endian, at fixed offsets.
  -- An untouched palette is copied, not regenerated: the 5-bit round trip would
  -- be lossless anyway, but a BMP editor can rewrite the reserved bits.
  local palette_bytes = pal_changed and bmp_to_bgr555(pal, 256) or original_palette
  out = put(out, POINTER_OFFSET, string.pack(">I4", pointer))
  out = put(out, PALETTE_OFFSET, palette_bytes)

  if labels_changed then
    -- One record per label and a count of 1: the strip is the whole label.
    -- Records after the first are left in place, unused.
    for i = 1, LABEL_COUNT do
      out = put(out, new_records[i].offset, new_records[i].bytes)
      out = put(out, TABLE_COUNTS + i - 1, "\x01")
    end
    if new_dma ~= sbe16(original, DMA_OFFSET) then
      out = put(out, DMA_OFFSET, string.pack(">I2", new_dma))
    end
  end

  return out
end

return codec
