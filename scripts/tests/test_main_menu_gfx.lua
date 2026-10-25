--[[ Test harness for main_menu_gfx.lua — run from the project root:
     ludared codecs test tests/test_main_menu_gfx.lua ]]

local codec = dofile(LUDARED.SCRIPTS .. "/main_menu_gfx.lua")
local prs = LUDARED.codec("std/sega/compression/prs")

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

local FONT_OFFSET, FONT_SIZE = 0x0000ff20, 2280
local BGND_SIZE = 3942
local BUDGET = FONT_SIZE + BGND_SIZE
local TAIL_OFFSET = FONT_OFFSET + BUDGET
local POINTER_OFFSET, POINTER_BASE, PALETTE_OFFSET, PALETTE_BYTES = 0x38a0, 0x214808, 0x29324, 512
local DMA_OFFSET = 0x3890
local TABLE_POINTERS, TABLE_COUNTS, MODULE_BASE = 0x6234, 0x624c, 0x204000
local BG_W, BG_H = 208, 152
local LABEL_H = 16
local LABEL_W = { 128, 80, 128, 112, 112, 128 }
local LABEL_NAMES = {
  "00_NEW_GAME", "01_OPTIONS", "02_CONTINUE",
  "03_RESUME", "04_THEATER", "05_BATTLE_TRIAL",
}

local function stride(w, bpp) return ((w * bpp + 31) // 32) * 4 end

-- Build an indexed BMP the way the codec writes them: 40-byte DIB header,
-- palette right before the pixels, top-down.
local function bmp(w, h, pixels, pal, bpp)
  local s, rb = stride(w, bpp), w * bpp // 8
  local rows = {}
  for y = 0, h - 1 do
    local row = pixels:sub(y * rb + 1, (y + 1) * rb)
    rows[y + 1] = row .. string.rep("\x00", s - #row)
  end
  local body = table.concat(rows)
  local off = 54 + #pal
  local hdr = string.pack("<c2I4I2I2I4I4i4i4I2I2I4I4I4I4I4I4",
    "BM", off + #body, 0, 0, off, 40, w, -h, 1, bpp, 0, #body, 0, 0, #pal // 4, 0)
  return hdr .. pal .. body
end

-- Read one back without trusting the codec: header fields, per-row slices,
-- palette located the same way any BMP reader does (immediately before pixels).
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
local function be16(s, o) return s:byte(o + 1) * 256 + s:byte(o + 2) end
local function sbe16(s, o) local v = be16(s, o); return v >= 0x8000 and v - 0x10000 or v end
local function be32(s, o)
  return ((s:byte(o + 1) * 256 + s:byte(o + 2)) * 256 + s:byte(o + 3)) * 256 + s:byte(o + 4)
end

local function slot_of(data)
  return be32(data, POINTER_OFFSET) - POINTER_BASE + FONT_SIZE
end

local function font_of(data)
  return prs:decode(data:sub(FONT_OFFSET + 1, FONT_OFFSET + slot_of(data)))[1].data
end

local function bgnd_of(data)
  return prs:decode(data:sub(FONT_OFFSET + slot_of(data) + 1, TAIL_OFFSET))[1].data
end

-- Read record k (1-based) of label i (1-based) with a plain big-endian read.
local function rec_at(data, i, k)
  local off = be32(data, TABLE_POINTERS + (i - 1) * 4) - MODULE_BASE + (k - 1) * 10
  return sbe16(data, off), sbe16(data, off + 2),
         be16(data, off + 4), be16(data, off + 6), be16(data, off + 8)
end

-- Independent oracle: compose a label from its records by walking pixels, not
-- by reusing the codec's nibble code.  Index 0 stays transparent.
local function oracle(font, recs)
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for _, r in ipairs(recs) do
    x0 = math.min(x0, r.x); y0 = math.min(y0, r.y)
    x1 = math.max(x1, r.x + r.w); y1 = math.max(y1, r.y + r.h)
  end
  local w, h = x1 - x0, y1 - y0
  local px = {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do px[y * w + x] = 0 end
  end
  for _, r in ipairs(recs) do
    for row = 0, r.h - 1 do
      for col = 0, r.w - 1 do
        local b = font:byte(r.co * 8 + row * (r.w // 2) + (col >> 1) + 1)
        local v = (col & 1) == 0 and (b >> 4) or (b & 0x0F)
        if v ~= 0 then px[(r.y - y0 + row) * w + (r.x - x0 + col)] = v end
      end
    end
  end
  local out = {}
  for y = 0, h - 1 do
    for x = 0, w - 1, 2 do
      out[#out + 1] = string.char(px[y * w + x] * 16 + px[y * w + x + 1])
    end
  end
  return table.concat(out), w, h
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

-- Deterministic sparse noise: a PRS-hostile label that still fits the budget.
local function noise_pixels(w, mod, seed)
  local state = seed or 7
  local out = {}
  for i = 1, w * 8 do
    if i % mod == 0 then
      state = (state * 1103515245 + 12345) & 0x7FFFFFFF
      out[i] = string.char((state >> 16) & 0xFF)
    else
      out[i] = "\x00"
    end
  end
  return table.concat(out)
end

local function random_pixels(w, seed)
  local state = seed or 99
  local out = {}
  for i = 1, w * 8 do
    state = (state * 1103515245 + 12345) & 0x7FFFFFFF
    out[i] = string.char((state >> 16) & 0xFF)
  end
  return table.concat(out)
end

local logo = load(LUDARED.PROJECT_ROOT .. "/LOGO.SH2")
print("main_menu_gfx.lua test harness")
print("")

print("decode")
local artifacts = codec.decode(logo, {})
check("decode returns six labels and the background", #artifacts == 7, tostring(#artifacts))
check("artifact names follow the descriptor table",
  artifacts[1].name == "MAINMENU/00_NEW_GAME.bmp"
  and artifacts[2].name == "MAINMENU/01_OPTIONS.bmp"
  and artifacts[3].name == "MAINMENU/02_CONTINUE.bmp"
  and artifacts[4].name == "MAINMENU/03_RESUME.bmp"
  and artifacts[5].name == "MAINMENU/04_THEATER.bmp"
  and artifacts[6].name == "MAINMENU/05_BATTLE_TRIAL.bmp"
  and artifacts[7].name == "MAINMENU/BG.bmp")

local font_block = font_of(logo)
local label_px, label_pal = {}, nil
local widths_ok = true
for i = 1, 6 do
  local px, w, h, pal, bpp = fields(artifacts[i].data)
  label_px[i] = px
  label_pal = label_pal or pal
  widths_ok = widths_ok and w == LABEL_W[i] and h == LABEL_H and bpp == 4
  check(string.format("%s is %dx%d 4bpp", LABEL_NAMES[i], LABEL_W[i], LABEL_H),
    w == LABEL_W[i] and h == LABEL_H and bpp == 4,
    string.format("%dx%d %dbpp", w, h, bpp))
end
check("all six label palettes are the 16-colour display ramp", #label_pal == 64, tostring(#label_pal))

-- Every label must equal what its records and the atlas say it is.  This is
-- the check that catches a wrong bbox, a wrong blit or a shared glyph read
-- from the wrong offset.
local oracle_ok = true
for i = 1, 6 do
  local recs = {}
  local ptr = be32(logo, TABLE_POINTERS + (i - 1) * 4) - MODULE_BASE
  local count = logo:byte(TABLE_COUNTS + i)
  for k = 1, count do
    local x, y, w, h, co = rec_at(logo, i, k)
    recs[k] = { x = x, y = y, w = w, h = h, co = co }
  end
  local px, w = oracle(font_block, recs)
  local got, gw = fields(artifacts[i].data)
  if px ~= got or w ~= gw then
    oracle_ok = false
    print(string.format("    %s differs from its records", LABEL_NAMES[i]))
  end
end
check("every label equals the composition of its records", oracle_ok)

-- Glyph 0 (characterOffset 0) is shared by labels 0, 2, 3 and 4.  Compare the
-- 16x16 cell in two of them, taken from different on-screen positions.
local function cell(px, px_w, x0, x, w, h)
  local stride = px_w // 2
  local out = {}
  for row = 0, h - 1 do
    local t = {}
    for col = 0, w - 1 do
      local dx = x - x0 + col
      local b = px:byte(row * stride + (dx >> 1) + 1)
      t[#t + 1] = string.char((dx & 1) == 0 and (b >> 4) or (b & 0x0F))
    end
    out[#out + 1] = table.concat(t)
  end
  return table.concat(out)
end
-- Label 0 puts glyph 0 at x = -16, label 3 puts it at x = -24.
local px0, w0 = fields(artifacts[1].data)
local px3, w3 = fields(artifacts[4].data)
check("a shared Japanese glyph is identical in two labels",
  cell(px0, w0, -64, -16, 16, 16) == cell(px3, w3, -56, -24, 16, 16))

local bg_px, bg_w, bg_h, bg_pal, bg_bpp, bg_colours = fields(artifacts[7].data)
check("background is 8bpp 208x152 with 256 colours",
  bg_w == BG_W and bg_h == BG_H and bg_bpp == 8 and bg_colours == 256,
  string.format("%dx%d %dbpp %d colours", bg_w, bg_h, bg_bpp, bg_colours))
local bg_block = bgnd_of(logo)
check("background pixels are the decoded block", bg_px == bg_block,
  string.format("%d vs %d bytes", #bg_px, #bg_block))
check("background palette is the 512 bytes at 0x29324",
  bg_pal == sat_to_bgra(logo:sub(PALETTE_OFFSET + 1, PALETTE_OFFSET + PALETTE_BYTES)))

print("")
print("encode: round trip")
local out = codec.encode(logo, artifacts)
check("encode(decode(logo)) is byte-identical", out == logo,
  out == logo and "" or string.format("%d vs %d bytes", #out, #logo))

print("")
print("encode: editing only the background keeps the Japanese atlas")
local bg_bmp = artifacts[7].data
local pix_off = string.unpack("<I4", bg_bmp, 11)
local edited_bg = bg_bmp:sub(1, pix_off) .. string.char(bg_bmp:byte(pix_off + 1) ~ 0xFF)
  .. bg_bmp:sub(pix_off + 2)
local bg_edit = {}
for i = 1, 7 do bg_edit[i] = { name = artifacts[i].name, data = artifacts[i].data } end
bg_edit[7] = { name = artifacts[7].name, data = edited_bg }
local bg_out = codec.encode(logo, bg_edit)
check("a background edit encodes", bg_out ~= nil)
check("the file keeps its size", #bg_out == #logo)
check("the font block is copied, not recompressed",
  bg_out:sub(FONT_OFFSET + 1, FONT_OFFSET + slot_of(logo)) ==
  logo:sub(FONT_OFFSET + 1, FONT_OFFSET + slot_of(logo)))
check("the record tables are untouched",
  bg_out:sub(TABLE_POINTERS + 1, TABLE_COUNTS + 6) ==
  logo:sub(TABLE_POINTERS + 1, TABLE_COUNTS + 6))
check("the counts are untouched",
  bg_out:byte(TABLE_COUNTS + 1, TABLE_COUNTS + 6) == logo:byte(TABLE_COUNTS + 1, TABLE_COUNTS + 6))
check("the font DMA length is untouched",
  be16(bg_out, DMA_OFFSET) == be16(logo, DMA_OFFSET))
check("the background pointer is unchanged",
  string.unpack(">I4", bg_out, POINTER_OFFSET + 1) == 0x214808)
-- 0x11770 starts LOGO export #6's disc-1 scene PRS.  A recompressed
-- background used to be followed by zeros up to 0x117CE, which ate the first
-- 94 bytes of that stream.
check("the following PRS resource is untouched",
  bg_out:sub(TAIL_OFFSET + 1, 0x117CE + 1) == logo:sub(TAIL_OFFSET + 1, 0x117CE + 1))
check("the whole tail from 0x1176E is byte-identical",
  bg_out:sub(TAIL_OFFSET + 1) == logo:sub(TAIL_OFFSET + 1))
check("the scene stream after 0x11770 still decodes to 62,016 bytes",
  #prs:decode(bg_out:sub(0x11770 + 1))[1].data == 62016)
local bg_back = codec.decode(bg_out, {})
local labels_kept = true
for i = 1, 6 do labels_kept = labels_kept and bg_back[i].data == artifacts[i].data end
check("the six labels decode identically, not as strips", labels_kept)
check("the edited background round-trips", bg_back[7].data == edited_bg)

print("")
print("encode: a label palette edit is not a change")
local pal_edit = {}
for i = 1, 7 do pal_edit[i] = { name = artifacts[i].name, data = artifacts[i].data } end
local lbmp = artifacts[2].data
local pal_off = string.unpack("<I4", lbmp, 11) - 64
pal_edit[2] = { name = artifacts[2].name,
  data = lbmp:sub(1, pal_off + 4) .. string.char(lbmp:byte(pal_off + 5) ~ 0x7F)
    .. lbmp:sub(pal_off + 6) }
check("a label palette-only edit returns the parent unchanged",
  codec.encode(logo, pal_edit) == logo)

print("")
print("encode: one label, rebuilt as strips")
local target = 3   -- 02_CONTINUE
local edit_px = label_px[target]:sub(1, 8) .. string.char(label_px[target]:byte(9) ~ 0x0F)
  .. label_px[target]:sub(10)
local one = {}
for i = 1, 7 do one[i] = { name = artifacts[i].name, data = artifacts[i].data } end
one[target] = { name = artifacts[target].name,
  data = bmp(LABEL_W[target], LABEL_H, edit_px, label_pal, 4) }
local one_out = codec.encode(logo, one)
check("a one-label edit encodes", one_out ~= nil and #one_out == #logo)

local counts_one, records_ok, offsets_ok = true, true, true
local at = 0
local rec_offsets = {}
for i = 1, 6 do
  counts_one = counts_one and one_out:byte(TABLE_COUNTS + i) == 1
  local x, y, w, h, co = rec_at(one_out, i, 1)
  local px, gw = fields(one[i].data)
  records_ok = records_ok and x == -gw // 2 and y == -8 and w == gw and h == LABEL_H
  offsets_ok = offsets_ok and co * 8 == at and (co * 8) % 64 == 0
  rec_offsets[i] = co * 8
  at = at + w * h // 2
end
check("every descriptor count is 1", counts_one)
check("every first record is centred and 16 high", records_ok)
check("texture offsets are cumulative and 8-byte aligned", offsets_ok)

-- Atlases are width*8 bytes per label; 128+80+128+112+112+128 = 688 pixels,
-- 5,504 bytes, so the retail DMA length of 5,632 already covers it.
check("the atlas is 5,504 bytes", at == 5504, tostring(at))
check("the font DMA length is not lowered", be16(one_out, DMA_OFFSET) == 0x1600,
  string.format("0x%04X", be16(one_out, DMA_OFFSET)))
check("the font fits its slot, so the background stays put",
  slot_of(one_out) == FONT_SIZE and be32(one_out, POINTER_OFFSET) == 0x214808)
local one_font = font_of(one_out)
check("the decompressed atlas matches the offsets", #one_font == at, tostring(#one_font))

-- Records beyond the first are still there, untouched.
local tail_ok = true
for i = 1, 6 do
  local ptr = be32(logo, TABLE_POINTERS + (i - 1) * 4)
  local count = logo:byte(TABLE_COUNTS + i)
  local from = ptr - MODULE_BASE + 10
  tail_ok = tail_ok and one_out:sub(from + 1, from + (count - 1) * 10) ==
    logo:sub(from + 1, from + (count - 1) * 10)
end
check("the unused original records are left in place", tail_ok)

-- Nothing outside the font slot, the six first records, the counts and the DMA
-- word may differ: that is where SH-2 instructions and everything else live.
local allowed = { { TABLE_COUNTS, TABLE_COUNTS + 6 }, { DMA_OFFSET, DMA_OFFSET + 2 } }
for i = 1, 6 do
  local p = be32(logo, TABLE_POINTERS + (i - 1) * 4) - MODULE_BASE
  allowed[#allowed + 1] = { p, p + 10 }
end
local stray
for i = 1, FONT_OFFSET do
  if one_out:byte(i) ~= logo:byte(i) then
    local off, ok = i - 1, false
    for _, r in ipairs(allowed) do
      if off >= r[1] and off < r[2] then ok = true end
    end
    if not ok and not stray then stray = off end
  end
end
check("only the record tables, counts and DMA word change before the font",
  stray == nil, stray and string.format("first stray byte at 0x%05X", stray))
check("nothing past 0x1176E moves",
  one_out:sub(TAIL_OFFSET + 1) == logo:sub(TAIL_OFFSET + 1))

local one_back = codec.decode(one_out, {})
local one_same = true
for i = 1, 6 do one_same = one_same and one_back[i].data == one[i].data end
check("all six labels decode back exactly", one_same)
check("the edited label survives decode", fields(one_back[target].data) == edit_px)
check("the background is unchanged", one_back[7].data == artifacts[7].data)
check("decode -> encode -> decode is stable", codec.encode(one_out, one_back) == one_out)

print("")
print("encode: six different widths, one 144-pixel label")
local widths = { 144, 48, 72, 24, 16, 8 }
local varied = {}
local varied_px = {}
for i = 1, 6 do
  local px = string.rep(string.char(0x10 * (i % 8) + (i * 3) % 16), widths[i] * 8)
  varied_px[i] = px
  varied[i] = { name = artifacts[i].name, data = bmp(widths[i], LABEL_H, px, label_pal, 4) }
end
varied[7] = { name = artifacts[7].name, data = artifacts[7].data }
local varied_out = codec.encode(logo, varied)
check("repacking six different widths encodes", varied_out ~= nil and #varied_out == #logo)

local varied_ok, varied_at = true, 0
for i = 1, 6 do
  local x, y, w, h, co = rec_at(varied_out, i, 1)
  varied_ok = varied_ok and x == -widths[i] // 2 and y == -8 and w == widths[i]
    and h == LABEL_H and co * 8 == varied_at
  varied_at = varied_at + widths[i] * 8
end
check("each label gets its own width and x = -width/2", varied_ok)
check("the atlas packs the widths consecutively", varied_at == 2496, tostring(varied_at))
check("a 2,496-byte atlas leaves the DMA length at 0x1600",
  be16(varied_out, DMA_OFFSET) == 0x1600)
local varied_back = codec.decode(varied_out, {})
local varied_same = true
for i = 1, 6 do
  local px, w = fields(varied_back[i].data)
  varied_same = varied_same and px == varied_px[i] and w == widths[i]
end
check("the variable-width labels decode to their own pixels", varied_same)

-- A rebuilt strip file is a valid parent too: edit one of its labels again.
local reedit = {}
for i = 1, 7 do reedit[i] = { name = varied_back[i].name, data = varied_back[i].data } end
local reedit_px = varied_back[4].data
local reedit_off = string.unpack("<I4", reedit_px, 11)
reedit[4] = { name = varied_back[4].name,
  data = reedit_px:sub(1, reedit_off) .. string.char(reedit_px:byte(reedit_off + 1) ~ 0x77)
    .. reedit_px:sub(reedit_off + 2) }
local reedit_out = codec.encode(varied_out, reedit)
local reedit_back = codec.decode(reedit_out, {})
local reedit_ok = #reedit_out == #logo
for i = 1, 7 do reedit_ok = reedit_ok and reedit_back[i].data == reedit[i].data end
check("an already-strip file can be edited again", reedit_ok)

print("")
print("encode: the DMA length follows a bigger atlas")
local wide_px = string.rep("\x00", 320 * 8)
local wide = {}
for i = 1, 6 do
  wide[i] = { name = artifacts[i].name, data = bmp(320, LABEL_H, wide_px, label_pal, 4) }
end
wide[7] = { name = artifacts[7].name, data = artifacts[7].data }
local wide_out = codec.encode(logo, wide)
check("six 320-pixel labels encode", wide_out ~= nil and #wide_out == #logo)
check("the font DMA length is raised to the 15,360-byte atlas",
  be16(wide_out, DMA_OFFSET) == 15360,
  string.format("0x%04X", be16(wide_out, DMA_OFFSET)))
check("the blank atlas still fits its 2,280-byte slot",
  be32(wide_out, POINTER_OFFSET) == 0x214808)
local wide_back = codec.decode(wide_out, {})
local wide_first, wide_first_w = fields(wide_back[1].data)
local wide_last, wide_last_w = fields(wide_back[6].data)
check("the 320-pixel labels decode whole", #font_of(wide_out) == 15360
  and wide_first == wide_px and wide_first_w == 320
  and wide_last == wide_px and wide_last_w == 320)

print("")
print("encode: font growth inside the shared budget")
local grown_px = noise_pixels(144, 4)
local grown = {}
for i = 1, 7 do grown[i] = { name = artifacts[i].name, data = artifacts[i].data } end
grown[1] = { name = artifacts[1].name, data = bmp(144, LABEL_H, grown_px, label_pal, 4) }
local grown_out = codec.encode(logo, grown)
local grown_slot = slot_of(grown_out)
check("a font over 2,280 bytes encodes", grown_out ~= nil and #grown_out == #logo)
check("the font really outgrew its slot", grown_slot > FONT_SIZE, tostring(grown_slot))
check("the background pointer follows the font",
  be32(grown_out, POINTER_OFFSET) == POINTER_BASE + grown_slot - FONT_SIZE,
  string.format("%08X", be32(grown_out, POINTER_OFFSET)))
check("the copied 3,942-byte background could not have fitted",
  grown_slot + BGND_SIZE > BUDGET,
  string.format("%d + %d > %d", grown_slot, BGND_SIZE, BUDGET))
check("the moved background still decodes to 31,616 bytes",
  #bgnd_of(grown_out) == BG_W * BG_H and bgnd_of(grown_out) == bg_block)
local grown_back = codec.decode(grown_out, {})
local grown_same = true
for i = 1, 6 do
  local px, w = fields(grown_back[i].data)
  local want = i == 1 and grown_px or label_px[i]
  local want_w = i == 1 and 144 or LABEL_W[i]
  grown_same = grown_same and px == want and w == want_w
end
check("the grown file decodes all six labels", grown_same)
check("the grown file's background decodes", grown_back[7].data == artifacts[7].data)
check("the grown file re-encodes unchanged", codec.encode(grown_out, grown_back) == grown_out)
check("the squeezed-background path leaves 0x1176E onward untouched",
  grown_out:sub(TAIL_OFFSET + 1) == logo:sub(TAIL_OFFSET + 1))
check("the squeezed-background path keeps the scene stream",
  #prs:decode(grown_out:sub(0x11770 + 1))[1].data == 62016)

print("")
print("encode: within the shared budget")
-- The Lua encoder used 6,221 of the 6,222 bytes for width 176 with seed 28.
-- Keep that ceiling while allowing the native encoder to compress better.
local edge_px = noise_pixels(176, 4, 28)
local edge = {}
for i = 1, 7 do edge[i] = { name = artifacts[i].name, data = artifacts[i].data } end
edge[1] = { name = artifacts[1].name, data = bmp(176, LABEL_H, edge_px, label_pal, 4) }
local edge_out = codec.encode(logo, edge)
local edge_slot = slot_of(edge_out)
local edge_bg = #prs:encode("", { { name = "DECOMPRESSED", data = bg_block } })
check("a font within the budget encodes", edge_out ~= nil and #edge_out == #logo)
check("the encode leaves at least one byte of headroom",
  edge_slot + edge_bg <= BUDGET - 1,
  string.format("slot %d + bg %d = %d of %d", edge_slot, edge_bg, edge_slot + edge_bg, BUDGET))
check("the near-capacity font slot is above the retail slot", edge_slot > FONT_SIZE,
  tostring(edge_slot))
check("the near-capacity background pointer follows",
  be32(edge_out, POINTER_OFFSET) == POINTER_BASE + edge_slot - FONT_SIZE,
  string.format("%08X", be32(edge_out, POINTER_OFFSET)))
check("the near-capacity file leaves 0x1176E onward untouched",
  edge_out:sub(TAIL_OFFSET + 1) == logo:sub(TAIL_OFFSET + 1))
check("the near-capacity file keeps the scene stream",
  #prs:decode(edge_out:sub(0x11770 + 1))[1].data == 62016)
local edge_back = codec.decode(edge_out, {})
local edge_first, edge_first_w = fields(edge_back[1].data)
check("the near-capacity file decodes every label and the background",
  #edge_back == 7 and edge_first == edge_px and edge_first_w == 176
  and edge_back[7].data == artifacts[7].data)
check("the near-capacity file re-encodes unchanged",
  codec.encode(edge_out, edge_back) == edge_out)

print("")
print("encode: formerly over-budget artwork")
-- Seed 3 used 6,223 bytes with the Lua encoder; native compression fits it.
-- Check the budget rather than pinning an exact compressed size.
local over_px = noise_pixels(176, 4, 3)
local over = {}
for i = 1, 7 do over[i] = { name = artifacts[i].name, data = artifacts[i].data } end
over[1] = { name = artifacts[1].name, data = bmp(176, LABEL_H, over_px, label_pal, 4) }
local saved = {}
for i = 1, 7 do saved[i] = artifacts[i].data end
local before_logo = logo
local over_out = codec.encode(logo, over)
local over_slot = slot_of(over_out)
check("the formerly over-budget font fits the shared budget",
  over_slot + edge_bg <= BUDGET,
  string.format("slot %d + bg %d = %d of %d", over_slot, edge_bg, over_slot + edge_bg, BUDGET))
check("the encode preserves file size and everything after the budget",
  #over_out == #logo and over_out:sub(TAIL_OFFSET + 1) == logo:sub(TAIL_OFFSET + 1))
check("the formerly over-budget label round-trips",
  fields(codec.decode(over_out, {})[1].data) == over_px)
local untouched = logo == before_logo
for i = 1, 7 do untouched = untouched and artifacts[i].data == saved[i] end
check("the encode leaves the parent and its inputs untouched", untouched)

print("")
print("encode: rejections")
local function all(width, px)
  local t = {}
  for i = 1, 6 do t[i] = { name = artifacts[i].name, data = bmp(width, LABEL_H, px, label_pal, 4) } end
  t[7] = { name = artifacts[7].name, data = artifacts[7].data }
  return t
end

check_err("an oversized compressed font is refused", function()
  codec.encode(logo, all(320, random_pixels(320)))
end, "0x1176E")

check_err("a 15-pixel label is refused", function()
  local t = {}
  for i = 1, 7 do t[i] = { name = artifacts[i].name, data = artifacts[i].data } end
  t[1] = { name = artifacts[1].name,
    data = bmp(128, 15, string.rep("\x00", 128 * 15 // 2), label_pal, 4) }
  codec.encode(logo, t)
end, "exactly 16")

check_err("a width that is not a multiple of 8 is refused", function()
  local t = {}
  for i = 1, 7 do t[i] = { name = artifacts[i].name, data = artifacts[i].data } end
  t[1] = { name = artifacts[1].name,
    data = bmp(12, LABEL_H, string.rep("\x00", 12 * 8), label_pal, 4) }
  codec.encode(logo, t)
end, "multiple of 8")

check_err("a label too wide for a VDP1 record is refused", function()
  local t = {}
  for i = 1, 7 do t[i] = { name = artifacts[i].name, data = artifacts[i].data } end
  t[1] = { name = artifacts[1].name,
    data = bmp(2048, LABEL_H, string.rep("\x00", 2048 * 8), label_pal, 4) }
  codec.encode(logo, t)
end, "cannot express")

check_err("an 8bpp label is refused", function()
  local t = {}
  for i = 1, 7 do t[i] = { name = artifacts[i].name, data = artifacts[i].data } end
  t[1] = { name = artifacts[1].name,
    data = bmp(8, LABEL_H, string.rep("\x00", 8 * LABEL_H), label_pal, 8) }
  codec.encode(logo, t)
end, "4bpp")

check_err("a missing label BMP is refused", function()
  local t = {}
  for i = 1, 7 do
    if i ~= 2 then t[#t + 1] = { name = artifacts[i].name, data = artifacts[i].data } end
  end
  codec.encode(logo, t)
end, "is missing")

check_err("the background must stay 208x152", function()
  local t = {}
  for i = 1, 7 do t[i] = { name = artifacts[i].name, data = artifacts[i].data } end
  t[7] = { name = artifacts[7].name,
    data = bmp(BG_W, BG_H - 8, string.rep("\x00", BG_W * (BG_H - 8)), bg_pal, 8) }
  codec.encode(logo, t)
end, "208x152")

print("")
print("can_handle")
-- Ludared always presents the pristine input, so the shipped file's hash is the
-- strongest signal available and it must be the one that earns "certain".
check("the shipped file is certain", codec.can_handle(logo) == "certain",
  codec.can_handle(logo))

local nudged = logo:sub(1, 0x20000)
  .. string.char(logo:byte(0x20001) ~ 0x01)
  .. logo:sub(0x20002)
check("a file that reads right but hashes differently is likely",
  codec.can_handle(nudged) == "likely", codec.can_handle(nudged))

-- The codec's own outputs must be recognised, including the strip layout and a
-- raised DMA length, not just the glyph atlas it was mapped on.
check("a rebuilt strip file is likely", codec.can_handle(one_out) == "likely",
  codec.can_handle(one_out))
check("a rebuilt file with a grown font slot is likely",
  codec.can_handle(grown_out) == "likely", codec.can_handle(grown_out))
check("a rebuilt file with a raised DMA length is likely",
  codec.can_handle(wide_out) == "likely", codec.can_handle(wide_out))

check("a short file is a no", codec.can_handle(logo:sub(1, 100)) == "no")
check("a non-string is a no", codec.can_handle(nil) == "no")

local broken = logo:sub(1, POINTER_OFFSET)
  .. string.pack(">I4", 0xDEADBEEF)
  .. logo:sub(POINTER_OFFSET + 5)
check("a file whose pointer cannot fit is a no", codec.can_handle(broken) == "no",
  codec.can_handle(broken))

-- A hand-edited record can make a label span an odd number of pixels; a 4bpp
-- strip cannot hold that, so decode says so instead of writing a broken BMP.
local ptr1 = be32(logo, TABLE_POINTERS + 4) - MODULE_BASE
local skewed = logo:sub(1, ptr1)
  .. string.pack(">i2i2I2I2I2", -39, -8, 16, 16, 400)
  .. logo:sub(ptr1 + 11)
check_err("an odd-width label composition is refused",
  function() codec.decode(skewed, {}) end, "half byte")

print("")
print(string.format("%d passed, %d failed", pass, fail))
assert(fail == 0, string.format("%d tests failed", fail))
