--[[ Test harness for options_menu_gfx.lua — run from the project root:
     ludared codecs test tests/test_options_menu_gfx.lua

  The oracle is written independently of the codec: descriptors are read here,
  labels are composed here, and every byte of every output is compared here.
]]

local codec    = dofile(LUDARED.SCRIPTS .. "/options_menu_gfx.lua")
local prs      = LUDARED.codec("std/sega/compression/prs")
local palettes = dofile(LUDARED.SCRIPTS .. "/shared/palettes.lua")

local pass, fail = 0, 0
local function check(name, ok, detail)
  if ok then pass = pass + 1; print("  ok    " .. name)
  else fail = fail + 1; print("  FAIL  " .. name .. (detail and ("  -- " .. detail) or "")) end
end
local function check_err(name, fn, pattern)
  local ok, err = pcall(fn)
  if ok then fail = fail + 1; print("  FAIL  " .. name .. "  -- expected an error")
  elseif pattern and not tostring(err):find(pattern, 1, true) then
    fail = fail + 1; print("  FAIL  " .. name .. "  -- wrong error: " .. tostring(err))
  else pass = pass + 1; print("  ok    " .. name) end
end

local function load(path)
  local f = assert(io.open(path, "rb")); local d = f:read("*a"); f:close(); return d
end

-- Constants mirrored from options_menu_gfx.lua so the harness does not import
-- the implementation's own numbers.
local ATLAS_OFFSET   = 0x05b320
local ATLAS_SLOT     = 3782
local ATLAS_LIMIT    = 11520
local PREFIX_BYTES   = 64
local PALETTE_BLOCK  = 0x05ad98   -- first (background) bank starts here
local PALETTE_BANK   = 0x05adb8   -- second (label) bank of the same block
local BG_OFFSET      = 0x05ae38
local BG_SLOT        = 1256
local BG_W, BG_H     = 288, 144
local BG_PIXELS      = BG_W * BG_H // 2
local BG_END         = 0x0c300
local MARK_OFFSET    = 0x0c280
local MARK_BYTES     = 64
local MARK_W, MARK_H = 8, 16
local LABEL_H        = 16
local LABEL_ALIGN    = 8
local LABEL_MAX_W    = 255 * 8
local RAM_BASE       = 0x06004000

local DESC = {
  { name = "CURSOR_SPEED", off = 0x05ab68, count = 11, width = 256 },
  { name = "SOUND",        off = 0x05aa30, count = 12, width = 256 },
  { name = "VOICE",        off = 0x05a954, count = 7,  width = 240 },
  { name = "CONTROLS",     off = 0x05a8a8, count = 10, width = 256 },
  { name = "EXIT",         off = 0x05a7e0, count = 4,  width = 64  },
}
local N = #DESC
local NB = N + 1
local BG_NAME = "OPTIONS/BACKGROUND.bmp"
local LEFT_I, RIGHT_I, POS_I = NB + 1, NB + 2, NB + 3
local LEFT_NAME  = "OPTIONS/BRACKET_LEFT.bmp"
local RIGHT_NAME = "OPTIONS/BRACKET_RIGHT.bmp"
local POS_NAME   = "OPTIONS/BRACKET_POSITIONS.json"
local NA = N + 4

local function artifact_name(i) return "OPTIONS/" .. DESC[i].name .. ".bmp" end

local function stride(w, bpp) return ((w * bpp + 31) // 32) * 4 end

-- Build an indexed BMP the way the codec writes them: 40-byte DIB header,
-- palette immediately before the pixels, top-down.
local function bmp(w, h, px, pal, bpp)
  local s, rb = stride(w, bpp), w * bpp // 8
  local rows = {}
  for y = 0, h - 1 do
    local row = px:sub(y * rb + 1, (y + 1) * rb)
    rows[y + 1] = row .. string.rep("\0", s - #row)
  end
  local body = table.concat(rows)
  local off = 54 + #pal
  local hdr = string.pack("<c2I4I2I2I4I4i4i4I2I2I4I4I4I4I4I4",
    "BM", off + #body, 0, 0, off, 40, w, -h, 1, bpp, 0, #body, 0, 0, #pal // 4, 0)
  return hdr .. pal .. body
end

-- Read a BMP back without trusting the codec.
local function fields(b)
  local off = string.unpack("<I4", b, 11)
  local w, h = string.unpack("<i4i4", b, 19)
  local bpp = string.unpack("<I2", b, 29)
  local colours = string.unpack("<I4", b, 47)
  if colours == 0 then colours = 1 << bpp end
  local rb, s = w * bpp // 8, stride(w, bpp)
  local rows = {}
  for y = 0, math.abs(h) - 1 do
    rows[y + 1] = b:sub(off + y * s + 1, off + y * s + rb)
  end
  return table.concat(rows), w, math.abs(h), b:sub(off - colours * 4 + 1, off), bpp, colours
end

local function u16(s, o) return s:byte(o + 1) * 256 + s:byte(o + 2) end
local function s16(s, o)
  local v = u16(s, o); return v >= 0x8000 and v - 0x10000 or v
end
local function be32(s, o)
  return ((s:byte(o + 1) * 256 + s:byte(o + 2)) * 256 + s:byte(o + 3)) * 256 + s:byte(o + 4)
end

local function sat_to_bgra(pal)
  local out = {}
  for i = 0, #pal // 2 - 1 do
    local v = u16(pal, i * 2)
    local b5, g5, r5 = (v >> 10) & 0x1F, (v >> 5) & 0x1F, v & 0x1F
    out[i * 4 + 1] = (b5 * 255 + 15) // 31
    out[i * 4 + 2] = (g5 * 255 + 15) // 31
    out[i * 4 + 3] = (r5 * 255 + 15) // 31
    out[i * 4 + 4] = 0
  end
  return string.char(table.unpack(out))
end

-- Read a parent's five label groups with plain big-endian reads.  `+16` is
-- followed (± RAM_BASE), which is what the engine does.
local function read_parent(data)
  local out = {}
  for i, d in ipairs(DESC) do
    local count = u16(data, d.off + 12)
    local ptr   = be32(data, d.off + 16)
    local base  = be32(data, d.off + 20)
    local rec_pos = ptr >= RAM_BASE and ptr - RAM_BASE or ptr
    local recs = {}
    for k = 0, count - 1 do
      local ro = rec_pos + k * 10
      recs[k + 1] = {
        x = s16(data, ro), y = s16(data, ro + 2),
        w = u16(data, ro + 4), h = u16(data, ro + 6), co = u16(data, ro + 8),
      }
    end
    out[i] = { name = d.name, desc_off = d.off, rec_pos = rec_pos,
               pointer = ptr, base = base, count = count, recs = recs }
  end
  return out
end

-- Independent oracle for the second-pass geometry.  The centre is the high
-- s16 of each BE u32; the low half is preserved, not interpreted.
local function read_marks(data)
  local out = {}
  for i, d in ipairs(DESC) do
    local count = u16(data, d.off + 4)
    local pair_ptr = be32(data, d.off + 24)
    local centre_ptr = be32(data, d.off + 28)
    local pair_pos = pair_ptr >= RAM_BASE and pair_ptr - RAM_BASE or pair_ptr
    local centre_pos = centre_ptr >= RAM_BASE and centre_ptr - RAM_BASE or centre_ptr
    local choices = {}
    for k = 0, count - 1 do
      local ro = pair_pos + k * 20
      local co = centre_pos + k * 4
      choices[k + 1] = {
        center = s16(data, co), center2 = u16(data, co + 2),
        left  = { x = s16(data, ro),      y = s16(data, ro + 2),
                  w = u16(data, ro + 4),  h = u16(data, ro + 6),
                  co = u16(data, ro + 8) },
        right = { x = s16(data, ro + 10), y = s16(data, ro + 12),
                  w = u16(data, ro + 14), h = u16(data, ro + 16),
                  co = u16(data, ro + 18) },
      }
    end
    out[i] = { name = d.name, desc_off = d.off, count = count,
               pair_pos = pair_pos, centre_pos = centre_pos,
               pair_ptr = pair_ptr, centre_ptr = centre_ptr, choices = choices }
  end
  return out
end

local function hit_list(data, i)
  local d = DESC[i]
  local ptr = be32(data, d.off + 8)
  local pos = ptr >= RAM_BASE and ptr - RAM_BASE or ptr
  local count = u16(data, d.off + 4)
  return data:sub(pos + 1, pos + count * 10)
end

local function marks_json(rows)
  local out = { "{\n  \"rows\": [" }
  for i, row in ipairs(rows) do
    out[#out + 1] = string.format(
      "%s\n    {\n      \"name\": \"%s\",\n      \"choices\": [",
      i == 1 and "" or ",", row.name)
    for k, choice in ipairs(row.choices) do
      out[#out + 1] = string.format(
        "%s\n        { \"center\": %d, \"left\": %d, \"right\": %d }",
        k == 1 and "" or ",", choice.center, choice.left.x, choice.right.x)
    end
    out[#out + 1] = "\n      ]\n    }"
  end
  out[#out + 1] = "\n  ]\n}\n"
  return table.concat(out)
end

-- Independent composition oracle.
local function compose(atlas, recs)
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for _, r in ipairs(recs) do
    x0 = math.min(x0, r.x); y0 = math.min(y0, r.y)
    x1 = math.max(x1, r.x + r.w); y1 = math.max(y1, r.y + r.h)
  end
  local w, h = x1 - x0, y1 - y0
  local px = {}
  for i = 1, (w // 2) * h do px[i] = 0 end
  for _, r in ipairs(recs) do
    local ss = r.w // 2
    for row = 0, r.h - 1 do
      for col = 0, r.w - 1 do
        local b = atlas:byte(r.co * 8 + row * ss + (col >> 1) + 1)
        local v = (col & 1) == 0 and (b >> 4) or (b & 0x0F)
        if v ~= 0 then
          local dx = r.x - x0 + col
          local di = (r.y - y0 + row) * (w // 2) + (dx // 2) + 1
          local db = px[di]
          if (dx & 1) == 0 then px[di] = (db & 0x0F) | (v << 4)
          else px[di] = (db & 0xF0) | v end
        end
      end
    end
  end
  local out = {}
  for i = 1, #px, 512 do
    out[#out + 1] = string.char(table.unpack(px, i, math.min(i + 511, #px)))
  end
  return table.concat(out), w, h, x0, y0
end

-- Deterministic noise; PRS-hostile but valid 4bpp pixels.
local function noise(bytes, seed)
  local state, out = seed or 7, {}
  for i = 1, bytes do
    state = (state * 1103515245 + 12345) & 0x7FFFFFFF
    out[i] = string.char((state >> 16) & 0xFF)
  end
  return table.concat(out)
end

-- The first byte outside `allowed` ({from, to} 0-based half-open ranges).
local function stray(a, b, allowed)
  for off = 0, #a - 1 do
    if a:byte(off + 1) ~= b:byte(off + 1) then
      local ok = false
      for _, r in ipairs(allowed) do
        if off >= r[1] and off < r[2] then ok = true; break end
      end
      if not ok then return off end
    end
  end
  return nil
end

local function slot_of(data)
  return data:sub(ATLAS_OFFSET + 1, ATLAS_OFFSET + ATLAS_SLOT)
end

local function sheet_of(data) return prs:decode(slot_of(data))[1].data end

local parent = load(LUDARED.PROJECT_ROOT .. "/SAKURA")
print("options_menu_gfx.lua test harness")
print("")

local parent_atlas = sheet_of(parent)
local retail = {}
do
  local groups = read_parent(parent)
  for i = 1, N do
    local px, w, h, x0, y0 = compose(parent_atlas, groups[i].recs)
    retail[i] = { px = px, w = w, h = h, x0 = x0, y0 = y0 }
  end
end

print("decode")
local artifacts = codec.decode(parent, {})
check("decode returns nine artifacts", #artifacts == NA, tostring(#artifacts))

local names_ok = true
for i = 1, N do
  names_ok = names_ok and artifacts[i].name == artifact_name(i)
end
check("artifact names follow the descriptor table", names_ok)
check("the background artifact is named and in slot six",
  artifacts[NB].name == BG_NAME, artifacts[NB].name)
check("the bracket artifacts follow the background",
  artifacts[LEFT_I].name == LEFT_NAME and artifacts[RIGHT_I].name == RIGHT_NAME,
  tostring(artifacts[LEFT_I].name) .. ", " .. tostring(artifacts[RIGHT_I].name))
check("the last artifact is the positions metadata",
  artifacts[POS_I].name == POS_NAME, artifacts[POS_I].name)

local label_pal = nil
local dec_ok, dec_detail = true, ""
for i = 1, N do
  local px, w, h, pal, bpp, colours = fields(artifacts[i].data)
  label_pal = label_pal or pal
  local ok = w == DESC[i].width and h == LABEL_H and bpp == 4 and colours == 16
  if not ok then
    dec_ok = false
    dec_detail = string.format("%s is %dx%d %dbpp %d colours",
      DESC[i].name, w, h, bpp, colours)
  end
  if px ~= retail[i].px or w ~= retail[i].w then
    dec_ok = false
    dec_detail = DESC[i].name .. " differs from its own composition"
  end
end
check("the five labels are 256/256/240/256/64 x 16, 4bpp, 16 colours", dec_ok, dec_detail)
check("all five BMPs carry the same display palette", #label_pal == 64, tostring(#label_pal))

-- The preview palette is the parent's options label bank, not a dialogue ramp.
local options_bank = parent:sub(PALETTE_BANK + 1, PALETTE_BANK + 32)
check("BMP palette is the 0x05adb8 bank of the options palette",
  label_pal == sat_to_bgra(options_bank))
check("BMP palette is not adv_dialogue_i18n",
  label_pal ~= sat_to_bgra(palettes.raw("adv_dialogue_i18n")))
check("the retail labels really are the Japanese options text (non-empty)",
  #retail[1].px > 0 and #retail[5].px > 0)

local parent_bg = prs:decode(parent:sub(BG_OFFSET + 1, BG_OFFSET + BG_SLOT))[1].data
check("the background stream decodes to 49,920 bytes", #parent_bg == 49920, tostring(#parent_bg))
local bg_px, bg_w, bg_h, bg_pal, bg_bpp, bg_colours = fields(artifacts[NB].data)
check("the background BMP is 288 x 144, 4bpp, 16 colours",
  bg_w == BG_W and bg_h == BG_H and bg_bpp == 4 and bg_colours == 16,
  string.format("%dx%d %dbpp %d colours", bg_w, bg_h, bg_bpp, bg_colours))
check("the background BMP is the first 20,736 decoded bytes",
  bg_px == parent_bg:sub(1, BG_PIXELS))
check("the background BMP uses the 0x05ad98 bank, not the label bank",
  bg_pal == sat_to_bgra(parent:sub(PALETTE_BLOCK + 1, PALETTE_BLOCK + 32)))
check("the background palette differs from the label palette",
  bg_pal ~= sat_to_bgra(parent:sub(PALETTE_BANK + 1, PALETTE_BANK + 32)))

local left_px, left_w, left_h, left_pal, left_bpp, left_colours = fields(artifacts[LEFT_I].data)
local right_px, right_w, right_h, right_pal, right_bpp, right_colours =
  fields(artifacts[RIGHT_I].data)
check("the bracket BMPs are 8 x 16, 4bpp, 16 colours",
  left_w == MARK_W and left_h == MARK_H and left_bpp == 4 and left_colours == 16
  and right_w == MARK_W and right_h == MARK_H and right_bpp == 4 and right_colours == 16,
  string.format("left %dx%d %dbpp %d, right %dx%d %dbpp %d",
    left_w, left_h, left_bpp, left_colours, right_w, right_h, right_bpp, right_colours))
check("BRACKET_LEFT.bmp is decoded 0xC280..0xC2BF exactly",
  left_px == parent_bg:sub(MARK_OFFSET + 1, MARK_OFFSET + MARK_BYTES))
check("BRACKET_RIGHT.bmp is decoded 0xC2C0..0xC2FF exactly",
  right_px == parent_bg:sub(MARK_OFFSET + MARK_BYTES + 1, MARK_OFFSET + 2 * MARK_BYTES))
check("the two retail marks are different textures", left_px ~= right_px)
check("the bracket BMPs use the 0x05ad98 background bank",
  left_pal == sat_to_bgra(parent:sub(PALETTE_BLOCK + 1, PALETTE_BLOCK + 32))
  and right_pal == left_pal)
check("the bracket palette is the background palette, not the label bank",
  left_pal == bg_pal and left_pal ~= label_pal)

local parent_marks = read_marks(parent)
check("BRACKET_POSITIONS.json matches the retail +24/+28 lists exactly",
  artifacts[POS_I].data == marks_json(parent_marks),
  "metadata differs from the independent oracle")

print("")
print("encode: unchanged round trip")
local rt = codec.encode(parent, artifacts)
check("encode(decode(SAKURA)) is byte-identical", rt == parent,
  string.format("%d vs %d bytes", #rt, #parent))

print("")
print("encode: forced reconstruction of the Japanese labels (rebuild=always)")
local forced = codec.encode(parent, artifacts, "rebuild=always")
check("rebuild=always produces a file of the same size", #forced == #parent)
check("the retail glyph sheet is really replaced",
  slot_of(forced) ~= slot_of(parent))

local forced_atlas = sheet_of(forced)
check("the rebuilt sheet is 64 + 8 * 1072 = 8,640 bytes", #forced_atlas == 8640,
  tostring(#forced_atlas))
check("the first 64 bytes of the sheet are the retail prefix",
  forced_atlas:sub(1, PREFIX_BYTES) == parent_atlas:sub(1, PREFIX_BYTES))

-- One record per label, pointing into the strip that was written for it.
local forced_groups = read_parent(forced)
local layout_ok, co_ok, width_ok, ptr_ok, count_ok = true, true, true, true, true
local at = PREFIX_BYTES
for i = 1, N do
  local g = forced_groups[i]
  local r = g.recs[1]
  count_ok = count_ok and g.count == 1
  ptr_ok   = ptr_ok and g.pointer == read_parent(parent)[i].pointer
  width_ok = width_ok and r.w == retail[i].w
  layout_ok = layout_ok and r.x == retail[i].x0 and r.y == retail[i].y0
    and r.h == LABEL_H
  co_ok = co_ok and r.co * 8 == at and (r.co * 8) % LABEL_ALIGN == 0
  at = at + r.w * 8
end
check("all five descriptor counts become 1", count_ok)
check("all five +16 pointers are left exactly as they were", ptr_ok)
check("each record reuses the label's bounding-box origin and height 16", layout_ok)
check("each record keeps the label's original width", width_ok)
-- The retail voice row is left-aligned at -128 and ends at +112.  Centring its
-- 240-pixel strip would move it to -120 and misalign its choice bars.
check("the voice row keeps its retail left edge", forced_groups[3].recs[1].x == -128
  and retail[3].x0 == -128 and retail[3].w == 240,
  string.format("x=%d, bbox x0=%d, w=%d",
    forced_groups[3].recs[1].x, retail[3].x0, retail[3].w))
check("characterOffset * 8 is the cumulative strip offset", co_ok)
check("the strips end at 8,640 bytes", at == 8640, tostring(at))

-- The sheet must be exactly the expected strips, compressed and zero padded.
local expect_sheet = { parent_atlas:sub(1, PREFIX_BYTES) }
for i = 1, N do expect_sheet[#expect_sheet + 1] = retail[i].px end
expect_sheet = table.concat(expect_sheet)
local expect_stream = prs:encode("", { { name = "DECOMPRESSED", data = expect_sheet } })
check("the sheet is prefix + five retail strips",
  forced_atlas == expect_sheet, string.format("%d vs %d bytes", #forced_atlas, #expect_sheet))
check("the stream fits the 3,782-byte slot", #expect_stream <= ATLAS_SLOT,
  tostring(#expect_stream))
check("the slot is the stream plus zero padding",
  slot_of(forced) == expect_stream .. string.rep("\0", ATLAS_SLOT - #expect_stream),
  string.format("stream %d, slot %d", #expect_stream, #slot_of(forced)))

-- Pixel equivalence: the rebuilt file decodes to the retail labels.
local forced_back = codec.decode(forced, {})
local forced_same = true
for i = 1, N do
  local px, w = fields(forced_back[i].data)
  forced_same = forced_same and px == retail[i].px and w == retail[i].w
end
check("the rebuilt file decodes to the retail pixels and widths", forced_same)

-- Byte preservation: only the slot, the counts and the five first records move.
local forced_allowed = { { ATLAS_OFFSET, ATLAS_OFFSET + ATLAS_SLOT } }
do
  local groups = read_parent(parent)
  for i = 1, N do
    forced_allowed[#forced_allowed + 1] = { groups[i].desc_off + 12, groups[i].desc_off + 16 }
    forced_allowed[#forced_allowed + 1] = { groups[i].rec_pos, groups[i].rec_pos + 10 }
  end
end
check("only the slot, +12..+15 and the first record of each list change",
  stray(forced, parent, forced_allowed) == nil,
  stray(forced, parent, forced_allowed) and
    string.format("first stray byte at 0x%06X", stray(forced, parent, forced_allowed)))
check("bytes after the slot are untouched",
  forced:sub(ATLAS_OFFSET + ATLAS_SLOT + 1) == parent:sub(ATLAS_OFFSET + ATLAS_SLOT + 1))

-- The unused retail records survive: they are still there, just not counted.
local unused_ok = true
for i = 1, N do
  local g = read_parent(parent)[i]
  local from = g.rec_pos + 10
  unused_ok = unused_ok and forced:sub(from + 1, from + (g.count - 1) * 10)
    == parent:sub(from + 1, from + (g.count - 1) * 10)
end
check("the unused retail records are left in place", unused_ok)

check("re-encoding the rebuilt file unchanged returns it byte for byte",
  codec.encode(forced, forced_back) == forced)
check("rebuilding it again is idempotent",
  codec.encode(forced, forced_back, "rebuild=always") == forced)
check("decode -> encode -> decode is stable",
  codec.encode(forced, codec.decode(forced, {})) == forced)

print("")
print("encode: one real label edit")
local target = 2  -- OPTIONS/SOUND.bmp, 256 x 16
-- Replace a 16-byte run (32 pixels) in the middle of the strip, not just one
-- nibble: the whole changed region must survive the round trip.
local edited_px = retail[target].px:sub(1, 32)
  .. string.rep(string.char(0x5A), 16) .. retail[target].px:sub(49)
local edit = {}
for i = 1, N do edit[i] = { name = artifacts[i].name, data = artifacts[i].data } end
edit[target] = { name = artifacts[target].name,
  data = bmp(retail[target].w, LABEL_H, edited_px, label_pal, 4) }
local out = codec.encode(parent, edit)
check("a changed label encodes", out ~= nil and #out == #parent)

local out_groups = read_parent(out)
local desc_ok, desc_detail = true, ""
for i = 1, N do
  local g = out_groups[i]
  local want_ptr = read_parent(parent)[i].pointer
  local want_count = 1
  local hi = u16(out, DESC[i].off + 12)
  local lo = u16(out, DESC[i].off + 14)
  if hi ~= want_count or lo ~= 0 or g.pointer ~= want_ptr then
    desc_ok = false
    desc_detail = string.format("%s: +12=%04X +14=%04X +16=0x%08X (want 1/0/0x%08X)",
      DESC[i].name, hi, lo, g.pointer, want_ptr)
  end
end
check("+12 is 1 for all five rows and +16 is unchanged", desc_ok, desc_detail)

local rec_ok, rec_detail = true, ""
local off = PREFIX_BYTES
for i = 1, N do
  local r = out_groups[i].recs[1]
  local want_w = retail[i].w
  if r.x ~= retail[i].x0 or r.y ~= retail[i].y0 or r.w ~= want_w or r.h ~= LABEL_H
    or r.co * 8 ~= off then
    rec_ok = false
    rec_detail = string.format("%s: x=%d y=%d w=%d h=%d co=%d want co=%d",
      DESC[i].name, r.x, r.y, r.w, r.h, r.co, off // 8)
  end
  off = off + want_w * 8
end
check("each first record sits at its own offset and keeps its origin", rec_ok, rec_detail)

local out_atlas = sheet_of(out)
check("the edited sheet keeps the 64-byte prefix",
  out_atlas:sub(1, PREFIX_BYTES) == parent_atlas:sub(1, PREFIX_BYTES))
check("the edited sheet keeps its 8,640-byte size", #out_atlas == 8640, tostring(#out_atlas))
check("the edited strip is at the expected offset",
  out_atlas:sub(PREFIX_BYTES + retail[1].w * 8 + 1,
    PREFIX_BYTES + retail[1].w * 8 + retail[2].w * 8) == edited_px)

local edit_allowed = { { ATLAS_OFFSET, ATLAS_OFFSET + ATLAS_SLOT } }
for i = 1, N do
  edit_allowed[#edit_allowed + 1] = { DESC[i].off + 12, DESC[i].off + 16 }
  edit_allowed[#edit_allowed + 1] = { out_groups[i].rec_pos, out_groups[i].rec_pos + 10 }
end
local edit_stray = stray(out, parent, edit_allowed)
check("only the slot, +12..+15 and the first records change", edit_stray == nil,
  edit_stray and string.format("first stray byte at 0x%06X", edit_stray))
check("bytes after 0x05c1e6 are untouched",
  out:sub(ATLAS_OFFSET + ATLAS_SLOT + 1) == parent:sub(ATLAS_OFFSET + ATLAS_SLOT + 1))

-- The choice-indicator geometry and the auxiliary lists are untouched.
local geometry_ok = true
for i = 1, N do
  for _, delta in ipairs({ 0, 2, 4, 8, 24, 28 }) do
    if out:sub(DESC[i].off + delta + 1, DESC[i].off + delta + 2)
      ~= parent:sub(DESC[i].off + delta + 1, DESC[i].off + delta + 2) then
      geometry_ok = false
    end
  end
end
check("+0, +2, +4, +8, +24 and +28 are unchanged in all five descriptors", geometry_ok)

-- The important round trip: the modified label comes back, the rest are retail.
local out_back = codec.decode(out, {})
local back_ok, back_detail = true, ""
for i = 1, N do
  local px, w = fields(out_back[i].data)
  local want_px = (i == target) and edited_px or retail[i].px
  if px ~= want_px or w ~= retail[i].w then
    back_ok = false
    back_detail = DESC[i].name
  end
end
check("the edited label round-trips and the other four are unchanged", back_ok, back_detail)
check("the edited label's BMP differs from retail", edited_px ~= retail[target].px)
check("a label-only edit leaves the background slot untouched",
  out:sub(BG_OFFSET + 1, BG_OFFSET + BG_SLOT) == parent:sub(BG_OFFSET + 1, BG_OFFSET + BG_SLOT))

print("")
print("encode: background edits")
-- Flip one nibble in the tab area, well inside the editable image.
local bg_at = BG_PIXELS // 2 + 40
local bg_edited = bg_px:sub(1, bg_at - 1)
  .. string.char(bg_px:byte(bg_at) ~ 0x10) .. bg_px:sub(bg_at + 1)
local bg_artifacts = {}
for i = 1, NB do bg_artifacts[i] = { name = artifacts[i].name, data = artifacts[i].data } end
bg_artifacts[NB] = { name = BG_NAME, data = bmp(BG_W, BG_H, bg_edited, bg_pal, 4) }
local bg_out = codec.encode(parent, bg_artifacts)
check("a changed background encodes without changing the file size",
  #bg_out == #parent, string.format("%d vs %d", #bg_out, #parent))
check("the background slot is rewritten",
  bg_out:sub(BG_OFFSET + 1, BG_OFFSET + BG_SLOT) ~= parent:sub(BG_OFFSET + 1, BG_OFFSET + BG_SLOT))
check("the atlas slot is untouched by a background-only edit",
  bg_out:sub(ATLAS_OFFSET + 1, ATLAS_OFFSET + ATLAS_SLOT)
    == parent:sub(ATLAS_OFFSET + 1, ATLAS_OFFSET + ATLAS_SLOT))
check("the five descriptors are untouched by a background-only edit",
  bg_out:sub(DESC[5].off, DESC[1].off + 32) == parent:sub(DESC[5].off, DESC[1].off + 32))

local bg_back = prs:decode(bg_out:sub(BG_OFFSET + 1, BG_OFFSET + BG_SLOT))[1].data
check("the edited background decodes back to the edited image",
  bg_back:sub(1, BG_PIXELS) == bg_edited)
check("the 29,184-byte tail is preserved",
  bg_back:sub(BG_PIXELS + 1) == parent_bg:sub(BG_PIXELS + 1))
check("a background edit round-trips through decode",
  fields(codec.decode(bg_out, {})[NB].data) == bg_edited)
check("re-encoding the edited background unchanged returns it byte for byte",
  codec.encode(bg_out, codec.decode(bg_out, {})) == bg_out)

-- The tab (bottom-left, inside the first 20,736 bytes) must be editable.
local tab_at = 130 * (BG_W // 2) + 20
local tab_edited = bg_px:sub(1, tab_at - 1)
  .. string.char(bg_px:byte(tab_at) ~ 0x30) .. bg_px:sub(tab_at + 1)
local tab_artifacts = {}
for i = 1, NB do tab_artifacts[i] = { name = artifacts[i].name, data = artifacts[i].data } end
tab_artifacts[NB] = { name = BG_NAME, data = bmp(BG_W, BG_H, tab_edited, bg_pal, 4) }
local tab_out = codec.encode(parent, tab_artifacts)
check("the tab area re-encodes within the 1,256-byte slot",
  #prs:decode(tab_out:sub(BG_OFFSET + 1, BG_OFFSET + BG_SLOT))[1].data == 49920)
check("the tab edit survives",
  prs:decode(tab_out:sub(BG_OFFSET + 1, BG_OFFSET + BG_SLOT))[1].data:sub(1, BG_PIXELS) == tab_edited)

check_err("a background that is not 288 x 144 is refused", function()
  local t = {}
  for i = 1, NB do t[i] = { name = artifacts[i].name, data = artifacts[i].data } end
  t[NB] = { name = BG_NAME, data = bmp(256, BG_H, string.rep("\0", 256 * BG_H // 2), bg_pal, 4) }
  codec.encode(parent, t)
end, "288x144")

check_err("an 8bpp background is refused", function()
  local t = {}
  for i = 1, NB do t[i] = { name = artifacts[i].name, data = artifacts[i].data } end
  t[NB] = { name = BG_NAME,
    data = bmp(BG_W, BG_H, string.rep("\0", BG_W * BG_H), bg_pal, 8) }
  codec.encode(parent, t)
end, "4bpp")

-- A rebuilt file is a valid parent: edit two different labels again.
local reedit = {}
for i = 1, N do reedit[i] = { name = out_back[i].name, data = out_back[i].data } end
local again_px = retail[1].px:sub(1, 16)
  .. string.char(retail[1].px:byte(17) ~ 0x0F) .. retail[1].px:sub(18)
reedit[1] = { name = out_back[1].name, data = bmp(retail[1].w, LABEL_H, again_px, label_pal, 4) }
-- Narrow label 3 from 240 to 200 pixels: the strips after it must move left.
local narrower_px = retail[3].px:sub(1, 200 * 8)
reedit[3] = { name = out_back[3].name,
  data = bmp(200, LABEL_H, narrower_px, label_pal, 4) }
local reedit_out = codec.encode(out, reedit)
check("an already-strip file can be edited again", #reedit_out == #out)
local reedit_back = codec.decode(reedit_out, {})
check("the second edit and the first edit both survive",
  fields(reedit_back[1].data) == again_px
  and fields(reedit_back[2].data) == edited_px
  and fields(reedit_back[3].data) == narrower_px)
local reedit_groups = read_parent(reedit_out)
local reedit_at, reedit_offsets = PREFIX_BYTES, true
for i = 1, N do
  local r = reedit_groups[i].recs[1]
  reedit_offsets = reedit_offsets and r.co * 8 == reedit_at
  reedit_at = reedit_at + r.w * 8
end
check("a width change re-packs the strips after it",
  reedit_offsets and reedit_groups[4].recs[1].co * 8 == 64 + (256 + 256 + 200) * 8,
  string.format("label 4 offset %d", reedit_groups[4].recs[1].co * 8))
check("the narrowed label decodes at its new width",
  select(2, fields(reedit_back[3].data)) == 200)

print("")
print("brackets: extraction, independent overrides and the shared PRS stream")
do
local function all_artifacts()
  local t = {}
  for i = 1, NA do t[i] = { name = artifacts[i].name, data = artifacts[i].data } end
  return t
end
local function bracket_bmp(px)
  return bmp(MARK_W, MARK_H, px, bg_pal, 4)
end
local function replace_once(text, old, new)
  local a, b = text:find(old, 1, true)
  if not a then error("test fixture not found: " .. old, 0) end
  return text:sub(1, a - 1) .. new .. text:sub(b + 1)
end

-- A palette-only edit must not count: encode compares pixels.
local bracket_pal_edit = all_artifacts()
local lb = bracket_pal_edit[LEFT_I].data
local lb_pix = string.unpack("<I4", lb, 11)
local lb_pal = lb_pix - 64
bracket_pal_edit[LEFT_I] = { name = LEFT_NAME,
  data = lb:sub(1, lb_pal + 4) .. string.char(lb:byte(lb_pal + 5) ~ 0x3f)
    .. lb:sub(lb_pal + 6) }
check("a bracket palette-only edit returns the parent unchanged",
  codec.encode(parent, bracket_pal_edit) == parent)

local left_edit = left_px:sub(1, 7) .. string.char(left_px:byte(8) ~ 0x5a) .. left_px:sub(9)
local right_edit = right_px:sub(1, 11) .. string.char(right_px:byte(12) ~ 0x33) .. right_px:sub(13)
check("the two bracket edit fixtures differ from retail",
  left_edit ~= left_px and right_edit ~= right_px)

-- Left only: right, background, labels and metadata are absent, so the codec
-- must preserve the retail right mark and the whole rest of the tail.
local left_only = {}
for i = 1, N do left_only[#left_only + 1] = { name = artifacts[i].name, data = artifacts[i].data } end
left_only[#left_only + 1] = { name = LEFT_NAME, data = bracket_bmp(left_edit) }
local left_out = codec.encode(parent, left_only)
check("a left-only bracket edit encodes at the same file size",
  #left_out == #parent, string.format("%d vs %d", #left_out, #parent))
local left_back = codec.decode(left_out, {})
check("BRACKET_LEFT.bmp round-trips the edited pixels",
  fields(left_back[LEFT_I].data) == left_edit)
check("a left-only edit leaves the right bracket retail",
  fields(left_back[RIGHT_I].data) == right_px)
local left_bg = prs:decode(left_out:sub(BG_OFFSET + 1, BG_OFFSET + BG_SLOT))[1].data
check("the left edit is written to decoded 0xC280..0xC2BF",
  left_bg:sub(MARK_OFFSET + 1, MARK_OFFSET + MARK_BYTES) == left_edit)
check("the right mark and the rest of the tail are preserved byte for byte",
  left_bg:sub(MARK_OFFSET + MARK_BYTES + 1, MARK_OFFSET + 2 * MARK_BYTES) == right_px
  and left_bg:sub(BG_PIXELS + 1, MARK_OFFSET) == parent_bg:sub(BG_PIXELS + 1, MARK_OFFSET)
  and left_bg:sub(MARK_OFFSET + 2 * MARK_BYTES + 1) == parent_bg:sub(MARK_OFFSET + 2 * MARK_BYTES + 1))
check("a left-only edit leaves the atlas, descriptors and marks alone",
  left_out:sub(ATLAS_OFFSET + 1, ATLAS_OFFSET + ATLAS_SLOT)
    == parent:sub(ATLAS_OFFSET + 1, ATLAS_OFFSET + ATLAS_SLOT)
  and marks_json(read_marks(left_out)) == marks_json(parent_marks))
local left_hit_ok = true
for i = 1, N do
  left_hit_ok = left_hit_ok and hit_list(left_out, i) == hit_list(parent, i)
end
check("a left-only edit leaves every +8 input hit list untouched", left_hit_ok)
check("a left-only edit re-encodes unchanged",
  codec.encode(left_out, codec.decode(left_out, {})) == left_out)

-- Right only: the left mark is absent from the artifact set.
local right_only = {}
for i = 1, N do right_only[#right_only + 1] = { name = artifacts[i].name, data = artifacts[i].data } end
right_only[#right_only + 1] = { name = RIGHT_NAME, data = bracket_bmp(right_edit) }
local right_out = codec.encode(parent, right_only)
local right_back = codec.decode(right_out, {})
check("a right-only bracket edit encodes", #right_out == #parent)
check("BRACKET_RIGHT.bmp round-trips the edited pixels",
  fields(right_back[RIGHT_I].data) == right_edit)
check("a right-only edit leaves the left bracket retail",
  fields(right_back[LEFT_I].data) == left_px)
check("a right-only edit leaves the atlas and marks alone",
  right_out:sub(ATLAS_OFFSET + 1, ATLAS_OFFSET + ATLAS_SLOT)
    == parent:sub(ATLAS_OFFSET + 1, ATLAS_OFFSET + ATLAS_SLOT)
  and marks_json(read_marks(right_out)) == marks_json(parent_marks))
local right_hit_ok = true
for i = 1, N do
  right_hit_ok = right_hit_ok and hit_list(right_out, i) == hit_list(parent, i)
end
check("a right-only edit leaves every +8 input hit list untouched", right_hit_ok)

-- Combined: one background stream must carry the panel edit and both marks.
local combo = all_artifacts()
combo[NB] = { name = BG_NAME, data = bmp(BG_W, BG_H, bg_edited, bg_pal, 4) }
combo[LEFT_I] = { name = LEFT_NAME, data = bracket_bmp(left_edit) }
combo[RIGHT_I] = { name = RIGHT_NAME, data = bracket_bmp(right_edit) }
local combo_out = codec.encode(parent, combo)
check("combined background and bracket edits encode", #combo_out == #parent)
local combo_bg = prs:decode(combo_out:sub(BG_OFFSET + 1, BG_OFFSET + BG_SLOT))[1].data
check("the combined edit keeps the panel, left mark and right mark",
  combo_bg:sub(1, BG_PIXELS) == bg_edited
  and combo_bg:sub(MARK_OFFSET + 1, MARK_OFFSET + MARK_BYTES) == left_edit
  and combo_bg:sub(MARK_OFFSET + MARK_BYTES + 1, MARK_OFFSET + 2 * MARK_BYTES) == right_edit)
check("the combined edit preserves every other tail byte",
  combo_bg:sub(BG_PIXELS + 1, MARK_OFFSET) == parent_bg:sub(BG_PIXELS + 1, MARK_OFFSET)
  and combo_bg:sub(MARK_OFFSET + 2 * MARK_BYTES + 1) == parent_bg:sub(MARK_OFFSET + 2 * MARK_BYTES + 1))
check("a pixel-only combined edit does not rebuild labels or move marks",
  combo_out:sub(ATLAS_OFFSET + 1, ATLAS_OFFSET + ATLAS_SLOT)
    == parent:sub(ATLAS_OFFSET + 1, ATLAS_OFFSET + ATLAS_SLOT)
  and marks_json(read_marks(combo_out)) == marks_json(parent_marks))
check("the combined edit re-encodes unchanged",
  codec.encode(combo_out, codec.decode(combo_out, {})) == combo_out)

-- Budget: 128 bytes of noise in a 49,920-byte stream cannot fit the 1,256-byte
-- slot.  The failure must be explicit and must not return a partial file.
local noisy_left = noise(MARK_BYTES, 123)
local budget = all_artifacts()
budget[LEFT_I] = { name = LEFT_NAME, data = bracket_bmp(noisy_left) }
local noisy_tail = parent_bg:sub(BG_PIXELS + 1, MARK_OFFSET) .. noisy_left
  .. parent_bg:sub(MARK_OFFSET + 2 * MARK_BYTES + 1)
local noisy_stream = prs:encode("", { { name = "DECOMPRESSED", data = parent_bg:sub(1, BG_PIXELS) .. noisy_tail } }, '{"chain":512}')
check("the budget fixture really exceeds 1,256 compressed bytes",
  #noisy_stream > BG_SLOT, tostring(#noisy_stream))
check_err("an over-budget bracket edit is refused with the 1,256-byte limit", function()
  codec.encode(parent, budget)
end, "1,256")

print("")
print("positions: declarative per-row, per-choice metadata")
-- Keep every other field and edit only the three exposed values.
local want = read_marks(parent)
want[1].choices[1].center = -6
want[1].choices[1].left.x = -18
want[1].choices[1].right.x = 10
want[1].choices[5].center = 124
want[4].choices[2].center = 98
want[4].choices[2].left.x = -42
want[4].choices[2].right.x = 34
want[5].choices[1].left.x = -38  -- EXIT is decoded even though row 4 skips it
local coord = all_artifacts()
coord[POS_I] = { name = POS_NAME, data = marks_json(want) }
local coord_out = codec.encode(parent, coord)
check("a positions-only edit encodes at the same file size", #coord_out == #parent)
check("the edited +24/+28 values survive decode",
  marks_json(read_marks(coord_out)) == marks_json(want))
check("the exact edited metadata is emitted",
  #codec.decode(coord_out, {}) == NA
  and codec.decode(coord_out, {})[POS_I].data == marks_json(want))
check("a positions-only edit leaves both pixel streams alone",
  coord_out:sub(BG_OFFSET + 1, BG_OFFSET + BG_SLOT)
    == parent:sub(BG_OFFSET + 1, BG_OFFSET + BG_SLOT)
  and coord_out:sub(ATLAS_OFFSET + 1, ATLAS_OFFSET + ATLAS_SLOT)
    == parent:sub(ATLAS_OFFSET + 1, ATLAS_OFFSET + ATLAS_SLOT))
local coord_hit_ok = true
for i = 1, N do
  coord_hit_ok = coord_hit_ok and hit_list(coord_out, i) == hit_list(parent, i)
end
check("the +8 input hit rectangles are preserved exactly", coord_hit_ok)
local coord_allowed = {}
for _, row in ipairs(want) do
  coord_allowed[#coord_allowed + 1] = { row.pair_pos, row.pair_pos + row.count * 20 }
  coord_allowed[#coord_allowed + 1] = { row.centre_pos, row.centre_pos + row.count * 4 }
end
check("only the +24/+28 list bytes change",
  stray(coord_out, parent, coord_allowed) == nil,
  stray(coord_out, parent, coord_allowed) and
    string.format("first stray byte at 0x%06X", stray(coord_out, parent, coord_allowed)))
check("the edited positions re-encode unchanged",
  codec.encode(coord_out, codec.decode(coord_out, {})) == coord_out)

-- Missing metadata is the preserving default.
local no_pos = {}
for i = 1, NA do
  if i ~= POS_I then no_pos[#no_pos + 1] = { name = artifacts[i].name, data = artifacts[i].data } end
end
check("omitting BRACKET_POSITIONS.json keeps the retail coordinates",
  codec.encode(parent, no_pos) == parent)

local function bad_pos(text)
  local t = all_artifacts()
  t[POS_I] = { name = POS_NAME, data = text }
  return t
end
check_err("malformed positions JSON is refused", function()
  codec.encode(parent, bad_pos("{"))
end, "invalid JSON")
check_err("an unknown row is refused", function()
  codec.encode(parent, bad_pos(replace_once(artifacts[POS_I].data,
    "CURSOR_SPEED", "CURSOR")))
end, "unknown row")
local missing_row = read_marks(parent)
table.remove(missing_row, 1)
check_err("a missing row is refused", function()
  codec.encode(parent, bad_pos(marks_json(missing_row)))
end, "is missing")
local short_choices = read_marks(parent)
short_choices[1].choices[5] = nil
check_err("a short choice list is refused", function()
  codec.encode(parent, bad_pos(marks_json(short_choices)))
end, "has 4 choices")
check_err("an unknown choice key is refused", function()
  codec.encode(parent, bad_pos(replace_once(artifacts[POS_I].data,
    '\"center\": -8', '\"centre\": -8')))
end, "unknown key")
check_err("a non-integer centre is refused", function()
  codec.encode(parent, bad_pos(replace_once(artifacts[POS_I].data,
    '\"center\": -8', '\"center\": -8.5')))
end, "must be an integer")
check_err("an out-of-range offset is refused", function()
  codec.encode(parent, bad_pos(replace_once(artifacts[POS_I].data,
    '\"right\": 8', '\"right\": 40000')))
end, "signed 16-bit")
check_err("an 8bpp bracket is refused", function()
  local t = all_artifacts()
  t[LEFT_I] = { name = LEFT_NAME,
    data = bmp(MARK_W, MARK_H, string.rep("\0", MARK_W * MARK_H), bg_pal, 8) }
  codec.encode(parent, t)
end, "4bpp")
check_err("a bracket that is not 8 x 16 is refused", function()
  local t = all_artifacts()
  t[RIGHT_I] = { name = RIGHT_NAME,
    data = bmp(16, MARK_H, string.rep("\0", 16 * MARK_H // 2), bg_pal, 4) }
  codec.encode(parent, t)
end, "8x16")
end

print("")
print("encode: palette-only edits are not changes")
local pal_edit = {}
for i = 1, N do pal_edit[i] = { name = artifacts[i].name, data = artifacts[i].data } end
local sb = artifacts[3].data
local pix_off = string.unpack("<I4", sb, 11)
local pal_off = pix_off - 64
pal_edit[3] = { name = artifacts[3].name,
  data = sb:sub(1, pal_off + 4) .. string.char(sb:byte(pal_off + 5) ~ 0x3F)
    .. sb:sub(pal_off + 6) }
check("a BMP palette edit returns the parent unchanged",
  codec.encode(parent, pal_edit) == parent)

print("")
print("encode: widths, growth and both budgets")
-- 1432 pixels total is the largest sheet: 64 + 8 * 1432 = 11,520 bytes.
local widths = { 320, 320, 320, 320, 152 }
local sum_w = 0
for _, w in ipairs(widths) do sum_w = sum_w + w end
check("the growth case uses exactly 1,432 pixels", sum_w == 1432, tostring(sum_w))

local grown = {}
for i = 1, N do
  grown[i] = { name = artifacts[i].name,
    data = bmp(widths[i], LABEL_H, string.rep("\0", widths[i] * 8), label_pal, 4) }
end
local grown_out = codec.encode(parent, grown)
check("a 1,432-pixel sheet encodes", grown_out ~= nil and #grown_out == #parent)
local grown_atlas = sheet_of(grown_out)
check("the sheet fills the 11,520-byte limit exactly", #grown_atlas == ATLAS_LIMIT,
  tostring(#grown_atlas))
local grown_groups = read_parent(grown_out)
local grown_ok, grown_at = true, PREFIX_BYTES
for i = 1, N do
  local r = grown_groups[i].recs[1]
  grown_ok = grown_ok and r.x == retail[i].x0 and r.y == retail[i].y0
    and r.w == widths[i] and r.h == LABEL_H and r.co * 8 == grown_at
  grown_at = grown_at + widths[i] * 8
end
check("the widened records point at their own strips", grown_ok)
local grown_back = codec.decode(grown_out, {})
local grown_same = true
for i = 1, N do
  local px, w = fields(grown_back[i].data)
  grown_same = grown_same and px == string.rep("\0", widths[i] * 8) and w == widths[i]
end
check("the 11,520-byte sheet decodes back to the five widths", grown_same)
check("the 11,520-byte sheet re-encodes unchanged",
  codec.encode(grown_out, grown_back) == grown_out)

local over_w = { 320, 320, 320, 320, 160 }
local over = {}
for i = 1, N do
  over[i] = { name = artifacts[i].name,
    data = bmp(over_w[i], LABEL_H, string.rep("\0", over_w[i] * 8), label_pal, 4) }
end
check_err("1,440 pixels (11,584 bytes decoded) is refused", function()
  codec.encode(parent, over)
end, "11,520")

-- A PRS-hostile sheet at the retail widths fits decoded (8,640) but compresses
-- to ~9,666 bytes, far over the 3,782-byte slot.
local noisy = {}
for i = 1, N do
  noisy[i] = { name = artifacts[i].name,
    data = bmp(retail[i].w, LABEL_H, noise(retail[i].w * 8, 100 + i), label_pal, 4) }
end
local noisy_sheet = {}
do
  noisy_sheet[1] = parent_atlas:sub(1, PREFIX_BYTES)
  for i = 1, N do noisy_sheet[#noisy_sheet + 1] = noise(retail[i].w * 8, 100 + i) end
end
noisy_sheet = table.concat(noisy_sheet)
check("the compressed-budget case fits the decoded limit", #noisy_sheet == 8640,
  tostring(#noisy_sheet))
check("its stream really is over the slot", #prs:encode("", { { name = "DECOMPRESSED", data = noisy_sheet } }) > ATLAS_SLOT,
  tostring(#prs:encode("", { { name = "DECOMPRESSED", data = noisy_sheet } })))
check_err("a sheet that fits decoded but not compressed is refused", function()
  codec.encode(parent, noisy)
end, "3,782")

print("")
print("encode: rejections")
local function with_label(i, data)
  local t = {}
  for k = 1, N do t[k] = { name = artifacts[k].name, data = artifacts[k].data } end
  t[i] = { name = artifacts[i].name, data = data }
  return t
end

check_err("a 15-pixel-high label is refused", function()
  codec.encode(parent, with_label(1,
    bmp(retail[1].w, 15, string.rep("\0", retail[1].w * 15 // 2), label_pal, 4)))
end, "exactly 16")

check_err("a width that is not a multiple of 8 is refused", function()
  codec.encode(parent, with_label(1,
    bmp(12, LABEL_H, string.rep("\0", 12 * 8), label_pal, 4)))
end, "multiple of 8")

check_err("a width too large for a VDP1 record is refused", function()
  local w = LABEL_MAX_W + 8
  codec.encode(parent, with_label(1,
    bmp(w, LABEL_H, string.rep("\0", w * 8), label_pal, 4)))
end, "2040")

check_err("an 8bpp label is refused", function()
  codec.encode(parent, with_label(1,
    bmp(8, LABEL_H, string.rep("\0", 8 * LABEL_H), label_pal, 8)))
end, "4bpp")

check_err("a missing label BMP is refused", function()
  local t = {}
  for i = 1, N do
    if i ~= 3 then t[#t + 1] = { name = artifacts[i].name, data = artifacts[i].data } end
  end
  codec.encode(parent, t)
end, "is missing")

check_err("a truncated BMP is refused", function()
  codec.encode(parent, with_label(1, string.char(0x42, 0x4D)))
end, "too short")

check_err("a non-BMP artifact is refused", function()
  codec.encode(parent, with_label(1, string.rep("\0", 128)))
end, "not a BMP")

check_err("a zero-width BMP is refused", function()
  codec.encode(parent, with_label(1,
    bmp(0, LABEL_H, "", label_pal, 4)))
end, "empty")

print("")
print("encode: failure atomicity")
local before_parent = parent
local before_artifacts = {}
for i = 1, N do before_artifacts[i] = artifacts[i].data end
local scratch = {}
for i = 1, N do scratch[i] = { name = artifacts[i].name, data = artifacts[i].data } end
scratch[1] = { name = artifacts[1].name,
  data = bmp(retail[1].w, LABEL_H, noise(retail[1].w * 8, 999), label_pal, 4) }
local ok, err = pcall(function() return codec.encode(parent, scratch) end)
check("a refused encode raises instead of returning a partial file", not ok, tostring(err))
check("a refused encode leaves the parent untouched", parent == before_parent)
local inputs_ok = true
for i = 1, N do inputs_ok = inputs_ok and artifacts[i].data == before_artifacts[i] end
check("a refused encode leaves its inputs untouched", inputs_ok)

print("")
print("decode: descriptor and record validation")
-- decode follows +16, not a hardcoded array: point CURSOR_SPEED at the EXIT
-- list and give it EXIT's count, so the descriptor describes that row.
local cursor_ptr = be32(parent, DESC[1].off + 16)
local exit_ptr   = be32(parent, DESC[5].off + 16)
local moved = parent:sub(1, DESC[1].off + 12) .. string.pack(">I2I2", 4, 0)
  .. parent:sub(DESC[1].off + 17)
moved = moved:sub(1, DESC[1].off + 16) .. string.pack(">I4", exit_ptr)
  .. moved:sub(DESC[1].off + 21)
local moved_labels = codec.decode(moved, {})
check("decode reads the records through +16",
  fields(moved_labels[1].data) == retail[5].px, "cursor should become exit")

-- A raw file offset is accepted as well as a RAM address.
local raw_ptr = parent:sub(1, DESC[1].off + 16)
  .. string.pack(">I4", cursor_ptr - RAM_BASE) .. parent:sub(DESC[1].off + 21)
check("a raw file offset in +16 decodes the same label",
  fields(codec.decode(raw_ptr, {})[1].data) == retail[1].px)

local zero_count = parent:sub(1, DESC[3].off + 12) .. string.pack(">I4", 0)
  .. parent:sub(DESC[3].off + 17)
check_err("a label count of 0 is refused", function()
  codec.decode(zero_count, {})
end, "label count")

local bad_base = parent:sub(1, DESC[2].off + 20) .. string.pack(">I4", 0x1234)
  .. parent:sub(DESC[2].off + 25)
check_err("a wrong texture base is refused", function()
  codec.decode(bad_base, {})
end, "texture base")

local bad_ptr = parent:sub(1, DESC[4].off + 16) .. string.pack(">I4", RAM_BASE + #parent - 20)
  .. parent:sub(DESC[4].off + 21)
check_err("a record list outside the file is refused", function()
  codec.decode(bad_ptr, {})
end, "does not fit")

-- The record width field itself, not the descriptor's texture base.
local exit_rec = read_parent(parent)[5].rec_pos
local odd_rec = parent:sub(1, exit_rec + 4) .. string.pack(">I2", 15)
  .. parent:sub(exit_rec + 7)
check_err("an odd record width is refused", function()
  codec.decode(odd_rec, {})
end, "odd")

local empty_rec = parent:sub(1, exit_rec + 4) .. string.pack(">I2", 0)
  .. parent:sub(exit_rec + 7)
check_err("an empty record is refused", function()
  codec.decode(empty_rec, {})
end, "empty sprite")

-- A slot that decompresses over 11,520 bytes is refused by decode.
local big_atlas = prs:encode("", { { name = "DECOMPRESSED", data = string.rep("\0", 12000) } })
check("the oversize atlas stream fits the physical slot", #big_atlas <= ATLAS_SLOT,
  tostring(#big_atlas))
local big = parent:sub(1, ATLAS_OFFSET) .. big_atlas
  .. string.rep("\0", ATLAS_SLOT - #big_atlas) .. parent:sub(ATLAS_OFFSET + ATLAS_SLOT + 1)
check_err("an atlas over the 11,520-byte limit is refused", function()
  codec.decode(big, {})
end, "11,520")

print("")
print("decode: arguments")
check("decode accepts rebuild=always and still returns nine artifacts",
  #codec.decode(parent, "rebuild=always") == NA)
check_err("an unknown argument is refused at decode", function()
  codec.decode(parent, "foo=1")
end, "unknown argument")
check_err("an invalid rebuild value is refused", function()
  codec.encode(parent, artifacts, "rebuild=sometimes")
end, "must be auto|always")
check_err("a bare argument is refused", function()
  codec.decode(parent, "always")
end, "key=value")

print("")
print("can_handle")
check("the shipped SAKURA is certain", codec.can_handle(parent) == "certain",
  codec.can_handle(parent))

local nudged = parent:sub(1, 0x40000) .. string.char(parent:byte(0x40001) ~ 0x01)
  .. parent:sub(0x40002)
check("a file that reads right but hashes differently is likely",
  codec.can_handle(nudged) == "likely", codec.can_handle(nudged))
check("a rebuilt strip file is likely", codec.can_handle(forced) == "likely",
  codec.can_handle(forced))
check("a file with an 11,520-byte sheet is likely", codec.can_handle(grown_out) == "likely",
  codec.can_handle(grown_out))

check("a short file is a no", codec.can_handle(parent:sub(1, 100)) == "no")
check("a non-string is a no", codec.can_handle(nil) == "no")
check("a big zero-filled file is a no",
  codec.can_handle(string.rep("\0", ATLAS_OFFSET + ATLAS_SLOT)) == "no")
check("a file with a wrong texture base is a no",
  codec.can_handle(bad_base) == "no", codec.can_handle(bad_base))
check("a file with a broken record list is a no",
  codec.can_handle(bad_ptr) == "no", codec.can_handle(bad_ptr))

print("")
print(string.format("%d passed, %d failed", pass, fail))
assert(fail == 0, string.format("%d tests failed", fail))
