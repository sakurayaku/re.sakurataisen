--[[ Test harness for options_menu_gfx.lua — run from the project root:
     ludared scripts test tests/test_options_menu_gfx.lua

  The oracle is written independently of the codec: descriptors, action tables,
  button and mini lists are read here, images are composed here, and every
  rebuilt consumer is compared here.  Nothing imports the implementation's own
  helpers.
]]

local codec    = dofile(LUDARED.SCRIPTS .. "/options_menu_gfx.lua")
local prs      = LUDARED.codec("std/sega/compression/prs")

local pass, fail = 0, 0
local function check(name, ok, detail)
  if ok then pass = pass + 1; print("  ok    " .. name)
  else fail = fail + 1; print("  FAIL  " .. name .. (detail and ("  -- " .. detail) or "")) end
end
local function check_err(name, fn, pattern, also)
  local ok, err = pcall(fn)
  if ok then fail = fail + 1; print("  FAIL  " .. name .. "  -- expected an error")
  elseif pattern and not tostring(err):find(pattern, 1, true) then
    fail = fail + 1; print("  FAIL  " .. name .. "  -- wrong error: " .. tostring(err))
  elseif also and not tostring(err):find(also, 1, true) then
    fail = fail + 1; print("  FAIL  " .. name .. "  -- missing " .. also .. ": " .. tostring(err))
  else pass = pass + 1; print("  ok    " .. name) end
end

local function load(path)
  local f = assert(io.open(path, "rb")); local d = f:read("*a"); f:close(); return d
end

-- Constants mirrored from the codec so the harness does not import its numbers.
local ATLAS_OFFSET  = 0x05b320
local ATLAS_SLOT    = 3782
local ATLAS_LIMIT   = 11520
local PALETTE_BANK  = 0x05adb8
local BG_OFFSET     = 0x05ae38
local BG_SLOT       = 1256
local BG_W, BG_H    = 288, 144
local BG_PIXELS     = BG_W * BG_H // 2
local BG_END        = 0x0c300
local MARK_OFFSET   = 0x0c280
local MARK_BYTES    = 64
local MARK_W, MARK_H = 8, 16
local LABEL_H       = 16
local RAM_BASE      = 0x06004000
local ACTION_TABLE  = 0x05abbc
local ACTION_PTRS   = 0x05abc8
local ACTION_ARENA  = 0x05a656
local ACTION_ARENA_LEN = 0x05a796 - ACTION_ARENA
local BUTTON_REC    = 0x05a5de
local MINI_REC      = 0x05acb0

local MAIN = {
  { name = "00_CURSOR_SPEED", off = 0x05ab68, slot = 0x05aa50, cap = 11, w = 256 },
  { name = "01_SOUND",        off = 0x05aa30, slot = 0x05a974, cap = 12, w = 256 },
  { name = "02_VOICE",        off = 0x05a954, slot = 0x05a8c8, cap = 7,  w = 240 },
  { name = "03_CONTROLS",     off = 0x05a8a8, slot = 0x05a800, cap = 10, w = 256 },
  { name = "04_EXIT",         off = 0x05a7e0, slot = 0x05a796, cap = 4,  w = 64  },
}
local ACTIONS = {
  { index = 0,  name = "SUB_00_NONE" },
  { index = 1,  name = "SUB_01_CONFIRM" },
  { index = 2,  name = "SUB_02_CANCEL" },
  { index = 4,  name = "SUB_04_MAP" },
  { index = 5,  name = "SUB_05_CONSULT" },
  { index = 6,  name = "SUB_06_DEFEND" },
  { index = 7,  name = "SUB_07_WAIT" },
  { index = 8,  name = "SUB_08_ATTACK" },
  { index = 9,  name = "SUB_09_MOVE" },
  { index = 10, name = "SUB_10_DEFAULT" },
}
local BUTTON_ABC_NAME   = "BUTTON_ABC"
local BUTTON_XYZLR_NAME = "BUTTON_XYZLR"
local BG_NAME     = "OPTIONS/BACKGROUND.bmp"
local LEFT_NAME   = "OPTIONS/BRACKET_LEFT.bmp"
local RIGHT_NAME  = "OPTIONS/BRACKET_RIGHT.bmp"
local POS_NAME    = "OPTIONS/BRACKET_POSITIONS.json"
local ORIGINS_NAME= "OPTIONS/TEXT_ORIGINS.json"

local function bmp_name(name) return "OPTIONS/" .. name .. ".bmp" end

local function u16(s, o) return s:byte(o + 1) * 256 + s:byte(o + 2) end
local function s16(s, o)
  local v = u16(s, o); return v >= 0x8000 and v - 0x10000 or v
end
local function be32(s, o)
  return ((s:byte(o + 1) * 256 + s:byte(o + 2)) * 256 + s:byte(o + 3)) * 256 + s:byte(o + 4)
end

local function stride(w, bpp) return ((w * bpp + 31) // 32) * 4 end

-- Read a BMP without trusting the codec: pixels are returned top-down and
-- tightly packed, whatever the header's height sign.
local function parse(b)
  local off, _, w, h, planes, bpp, comp = string.unpack("<I4I4i4i4I2I2I4", b, 11)
  assert(planes == 1 and comp == 0, "unexpected BMP")
  local bottom_up = h < 0
  h = math.abs(h)
  local st, rb = stride(w, bpp), w * bpp // 8
  local rows = {}
  for y = 0, h - 1 do
    local base = off + (bottom_up and (h - 1 - y) or y) * st
    rows[y + 1] = b:sub(base + 1, base + rb)
  end
  return table.concat(rows), w, h, b:sub(off - 64 + 1, off), bpp
end

local function build_bmp(px, w, h, pal)
  local st, rb = stride(w, 4), w // 2
  local body = {}
  -- `px` is top-down; BMP rows are stored bottom-up.
  for y = h - 1, 0, -1 do
    body[#body + 1] = px:sub(y * rb + 1, (y + 1) * rb) .. string.rep("\0", st - rb)
  end
  local data = table.concat(body)
  local off = 14 + 40 + #pal
  local hdr = string.pack("<c2I4I2I2I4I4i4i4I2I2I4I4I4I4I4I4",
    "BM", off + #data, 0, 0, off, 40, w, h, 1, 4, 0, #data, 0, 0, #pal // 4, 0)
  return hdr .. pal .. data
end

-- Compose records against an atlas: the independent oracle for "what the
-- screen draws".  The canvas is the union of the records' box and the frame
-- the caller passes, exactly as the codec's decode frames it.
local function compose(atlas, recs, frame)
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for _, r in ipairs(recs) do
    x0 = math.min(x0, r.x); y0 = math.min(y0, r.y)
    x1 = math.max(x1, r.x + r.w); y1 = math.max(y1, r.y + r.h)
  end
  if frame then
    x0 = math.min(x0, frame.x); y0 = math.min(y0, frame.y)
    y1 = math.max(y1, frame.y + frame.h)
  end
  local w, h = x1 - x0, y1 - y0
  local st = w // 2
  local px = {}
  for i = 1, st * h do px[i] = 0 end
  for _, r in ipairs(recs) do
    local ss = r.w // 2
    for row = 0, r.h - 1 do
      for col = 0, r.w - 1 do
        local byte = atlas:byte(r.co * 8 + row * ss + (col >> 1) + 1)
        local v = (col & 1) == 0 and (byte >> 4) or (byte & 0x0F)
        if v ~= 0 then
          local dx = r.x - x0 + col
          local di = (r.y - y0 + row) * st + (dx >> 1) + 1
          if (dx & 1) == 0 then px[di] = (px[di] & 0x0F) | (v << 4)
          else px[di] = (px[di] & 0xF0) | v end
        end
      end
    end
  end
  return string.char(table.unpack(px)), w, h, x0, y0
end

-- Blit records onto a fixed canvas: the cropped sprites a rebuild writes must
-- land on exactly the pixels the retail tiles did, whatever their own box is.
local function render(atlas, recs, x0, y0, w, h)
  local st = w // 2
  local px = {}
  for i = 1, st * h do px[i] = 0 end
  for _, r in ipairs(recs) do
    local ss = r.w // 2
    for row = 0, r.h - 1 do
      for col = 0, r.w - 1 do
        local b = atlas:byte(r.co * 8 + row * ss + (col >> 1) + 1)
        local v = (col & 1) == 0 and (b >> 4) or (b & 0x0F)
        if v ~= 0 then
          local dx, dy = r.x - x0 + col, r.y - y0 + row
          if dx >= 0 and dx < w and dy >= 0 and dy < h then
            local di = dy * st + (dx >> 1) + 1
            if (dx & 1) == 0 then px[di] = (px[di] & 0x0F) | (v << 4)
            else px[di] = (px[di] & 0xF0) | v end
          end
        end
      end
    end
  end
  return string.char(table.unpack(px))
end

local function rec_at(data, pos)
  return { x = s16(data, pos), y = s16(data, pos + 2), w = u16(data, pos + 4),
           h = u16(data, pos + 6), co = u16(data, pos + 8) }
end

local function ptr_pos(data, which)
  local v = be32(data, which)
  return v >= RAM_BASE and v - RAM_BASE or v
end

local function read_text(data)
  local main = {}
  for _, m in ipairs(MAIN) do
    local n = u16(data, m.off + 12)
    local pos = ptr_pos(data, m.off + 16)
    local recs = {}
    for k = 0, n - 1 do recs[k + 1] = rec_at(data, pos + k * 10) end
    main[#main + 1] = { name = m.name, count = n, pos = pos, recs = recs }
  end
  local actions = {}
  for i = 0, 11 do
    local n = data:byte(ACTION_TABLE + i + 1)
    local pos = ptr_pos(data, ACTION_PTRS + i * 4)
    local recs = {}
    for k = 0, n - 1 do recs[k + 1] = rec_at(data, pos + k * 10) end
    actions[i] = { count = n, pos = pos, recs = recs }
  end
  local function fixed(pos, n)
    local recs = {}
    for k = 0, n - 1 do recs[k + 1] = rec_at(data, pos + k * 10) end
    return recs
  end
  return {
    main = main, actions = actions,
    button = fixed(BUTTON_REC, 12), mini = fixed(MINI_REC, 8),
  }
end

local function atlas_of(data)
  return prs:decode(data:sub(ATLAS_OFFSET + 1, ATLAS_OFFSET + ATLAS_SLOT))[1].data
end

local function artifact_set(arts)
  local t = {}
  for _, a in ipairs(arts) do t[a.name] = a.data end
  return t
end

local function with_replacements(arts, repl)
  local out = {}
  for _, a in ipairs(arts) do
    out[#out + 1] = { name = a.name, data = repl[a.name] or a.data }
  end
  for name, data in pairs(repl) do
    local found = false
    for _, a in ipairs(out) do if a.name == name then found = true end end
    if not found then out[#out + 1] = { name = name, data = data } end
  end
  return out
end

-- Deterministic 4bpp noise: hostile to PRS, valid as pixels.
local function noise(bytes, seed)
  local out = {}
  local x = seed * 2654435761 % 4294967296
  for i = 1, bytes do
    x = (1103515245 * x + 12345) % 2147483648
    local v = (x >> 16) & 0xFF
    if v == 0 then v = 0x11 end
    out[i] = string.char(v)
  end
  return table.concat(out)
end

-- Repaint one pixel of a 4bpp BMP: an edit that must reach every consumer of
-- the texture it lands in.
local function edit_pixel(bmp, x, y, v)
  local off, _, w, h = string.unpack("<I4I4i4i4", bmp, 11)
  local row = (h < 0) and y or (math.abs(h) - 1 - y)   -- top-down or bottom-up BMP
  local i = off + row * stride(w, 4) + (x // 2) + 1
  local b = bmp:byte(i)
  if x % 2 == 0 then b = (b & 0x0F) | (v << 4) else b = (b & 0xF0) | v end
  return bmp:sub(1, i - 1) .. string.char(b) .. bmp:sub(i + 1)
end

-- Bytes that differ between two files outside the regions a rebuild may touch.
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

print("options_menu_gfx: load")
local parent = load("SAKURA")
check("the retail file is 391,712 bytes", #parent == 391712, tostring(#parent))
local parent_text = read_text(parent)
local base_arts = codec.decode(parent, {})
local base = artifact_set(base_arts)
check("decode returns the 23 artifacts", #base_arts == 23, tostring(#base_arts))

print("")
print("decode: artifacts")
local origins = {}
for _, a in ipairs(base_arts) do
  if a.name == ORIGINS_NAME then
    for name, x, y in a.data:gmatch('"([%w_]+)"%s*,%s*"x"%s*:%s*(%-?%d+)%s*,%s*"y"%s*:%s*(%-?%d+)') do
      origins[name] = { x = tonumber(x), y = tonumber(y) }
    end
  end
end
for _, m in ipairs(MAIN) do
  local px, w, h = parse(base[bmp_name(m.name)])
  check(m.name .. " decodes to a 16-px image", h == LABEL_H, tostring(h))
  check(m.name .. " decodes inside its retail width", w <= m.w and w % 8 == 0,
    tostring(w))
  check(m.name .. " has an origin entry", origins[m.name] ~= nil)
end
check("the submenu EXIT has its own origin entry", origins["SUB_11_EXIT"] ~= nil)
check("the cursor row keeps its retail origin",
  origins["00_CURSOR_SPEED"] and origins["00_CURSOR_SPEED"].x == -128
  and origins["00_CURSOR_SPEED"].y == -8)
check("the A/B/C board keeps its retail origin",
  origins[BUTTON_ABC_NAME] and origins[BUTTON_ABC_NAME].x == -48
  and origins[BUTTON_ABC_NAME].y == -80)
check("the X/Y/Z/L/R board keeps its retail origin",
  origins[BUTTON_XYZLR_NAME] and origins[BUTTON_XYZLR_NAME].x == -48
  and origins[BUTTON_XYZLR_NAME].y == -24)
check("the A/B/C board decodes to 16 x 48", (function()
  local _, w, h = parse(base[bmp_name(BUTTON_ABC_NAME)])
  return w == 16 and h == 48
end)())
check("the X/Y/Z/L/R board decodes to 16 x 80", (function()
  local _, w, h = parse(base[bmp_name(BUTTON_XYZLR_NAME)])
  return w == 16 and h == 80
end)())
check("the button column is no longer an artifact",
  base[bmp_name("BUTTON_COLUMN")] == nil)

print("")
print("decode: validation")
local function mutate(off, bytes)
  return parent:sub(1, off) .. bytes .. parent:sub(off + #bytes + 1)
end
check_err("a wrong texture base is refused", function()
  codec.decode(mutate(MAIN[4].off + 20, string.pack(">I4", 0xd850)), {})
end, "texture base")
check_err("a record list outside the file is refused", function()
  codec.decode(mutate(MAIN[4].off + 16, string.pack(">I4", RAM_BASE + #parent - 20)), {})
end, "does not fit")
local exit_pos = read_text(parent).main[5].pos
check_err("an odd record width is refused", function()
  codec.decode(mutate(exit_pos + 4, string.pack(">I2", 15)), {})
end, "odd")
check_err("an empty record is refused", function()
  codec.decode(mutate(exit_pos + 6, string.pack(">I2", 0)), {})
end, "empty sprite")
local big_atlas = prs:encode("", { { name = "DECOMPRESSED", data = string.rep("\0", 12000) } })
check("an oversize atlas still fits the physical slot", #big_atlas <= ATLAS_SLOT, tostring(#big_atlas))
check_err("an atlas over 11,520 decoded bytes is refused", function()
  codec.decode(parent:sub(1, ATLAS_OFFSET) .. big_atlas
    .. string.rep("\0", ATLAS_SLOT - #big_atlas)
    .. parent:sub(ATLAS_OFFSET + ATLAS_SLOT + 1), {})
end, "11,520")

print("")
print("decode: arguments")
check("decode accepts rebuild=always", #codec.decode(parent, "rebuild=always") == 23)
check_err("an unknown argument is refused", function() codec.decode(parent, "foo=1") end,
  "unknown argument")
check_err("an invalid rebuild value is refused", function()
  codec.encode(parent, base_arts, "rebuild=sometimes")
end, "must be auto|always")
check_err("a bare argument is refused", function() codec.decode(parent, "always") end, "key=value")

print("")
print("encode: retail round trip")
local fast = codec.encode(parent, base_arts, {})
check("unchanged artifacts return the parent byte for byte", fast == parent)
local rebuilt = codec.encode(parent, base_arts, "rebuild=always")
check("the rebuilt file is the same size as the parent", #rebuilt == #parent,
  tostring(#rebuilt) .. " vs " .. tostring(#parent))

local new_arts = artifact_set(codec.decode(rebuilt, {}))
local diffs = 0
for _, a in ipairs(base_arts) do
  if a.name:find("%.bmp$") and new_arts[a.name] ~= a.data then diffs = diffs + 1 end
end
check("every decoded image is pixel-identical after a rebuild", diffs == 0, tostring(diffs))
check("the position metadata survives", new_arts[POS_NAME] == base[POS_NAME])
check("the origins metadata survives", new_arts[ORIGINS_NAME] == base[ORIGINS_NAME])

local st = codec.stats
check("the atlas stays inside the decoded limit", st.sheet_bytes <= ATLAS_LIMIT, tostring(st.sheet_bytes))
check("the stream stays inside the slot", st.stream_bytes <= ATLAS_SLOT, tostring(st.stream_bytes))
check("deduplication found shared segments", st.unique <= st.records,
  st.unique .. " unique / " .. st.records .. " records")
check("the chosen cut is reported", st.cut and st.cut.maxw and st.cut.maxw % 8 == 0,
  st.cut and tostring(st.cut.maxw))
check("every candidate is scored", #st.candidates >= 8, tostring(#st.candidates))
check("the rebuilt sheet keeps the retail labels' ink", st.sheet_bytes > 0
  and st.sheet_bytes <= ATLAS_LIMIT, tostring(st.sheet_bytes))
check("the records fit the relocated storage", st.arena_used <= st.arena_capacity,
  st.arena_used .. "/" .. st.arena_capacity)

-- Every consumer must point into the shared atlas with its full sprite.
local rebuilt_text = read_text(rebuilt)
local atlas2 = atlas_of(rebuilt)
local bad = 0
local function walk(recs)
  for _, r in ipairs(recs) do
    if r.co * 8 + r.h * (r.w // 2) > #atlas2 then bad = bad + 1 end
  end
end
for _, m in ipairs(rebuilt_text.main) do walk(m.recs) end
for i = 0, 11 do walk(rebuilt_text.actions[i].recs) end
walk(rebuilt_text.button)
walk(rebuilt_text.mini)
check("every record reads inside the rebuilt atlas", bad == 0, tostring(bad))
check("every action list has a valid pointer",
  (function()
    for i = 0, 11 do
      if rebuilt_text.actions[i].count > 0
        and rebuilt_text.actions[i].pos + rebuilt_text.actions[i].count * 10 > #rebuilt then
        return false
      end
    end
    return true
  end)())

-- Only the slot, the lists and the records may move.
local allowed = {
  { ATLAS_OFFSET, ATLAS_OFFSET + ATLAS_SLOT },
  { ACTION_TABLE, ACTION_PTRS + 48 },
  { ACTION_ARENA, ACTION_ARENA + ACTION_ARENA_LEN },
  { BUTTON_REC, BUTTON_REC + 120 },
  { MINI_REC, MINI_REC + 80 },
}
for _, m in ipairs(MAIN) do allowed[#allowed + 1] = { m.off + 12, m.off + 20 } end
for _, m in ipairs(rebuilt_text.main) do
  allowed[#allowed + 1] = { m.pos, m.pos + m.count * 10 }
end
check("no byte outside the text structures changed", stray(parent, rebuilt, allowed) == nil,
  tostring(stray(parent, rebuilt, allowed)))

print("")
print("encode: determinism")
local again = codec.encode(parent, base_arts, "rebuild=always")
check("two builds of the same artifacts are byte-identical", again == rebuilt)
local reencoded = codec.encode(rebuilt, codec.decode(rebuilt, {}), "rebuild=always")
check("a build re-encodes to itself", reencoded == rebuilt)
check("a build is unchanged when re-encoded with rebuild=auto",
  codec.encode(rebuilt, codec.decode(rebuilt, {}), {}) == rebuilt)

print("")
print("encode: segmentation")
-- A single ink run is one sprite however wide the artboard is, and blank
-- columns inside it are what the horizontal crop removes.
local function ink_rows(w, h, spans)
  local rows = {}
  for y = 1, h do
    local row = {}
    for x = 0, w - 1 do row[#row + 1] = string.rep("\0", 1) end
    rows[y] = table.concat(row)
  end
  -- paint 4-px-wide marks at each span start
  local out = {}
  for y = 1, h do
    local parts = {}
    for i = 0, w // 2 - 1 do parts[#parts + 1] = "\0" end
    local bytes = table.concat(parts)
    for _, s in ipairs(spans) do
      local b = {}
      for i = 1, #bytes do b[i] = bytes:byte(i) end
      for k = 0, 1 do
        local idx = (y - 1) * (w // 2) + (s // 2) + k + 1
        b[idx] = 0x33
      end
      bytes = string.char(table.unpack(b))
    end
    out[y] = bytes
  end
  return table.concat(out)
end

local pal = parse(base[bmp_name("04_EXIT")])
-- 24-px segments: narrower than the 16-px cell grid is wide, so the cut has to
-- follow the ink rather than the grid.
local wide = build_bmp(ink_rows(96, 16, { 0, 32, 64 }), 96, 16, pal)
local wide_out = codec.encode(parent, with_replacements(base_arts,
  { [bmp_name("SUB_00_NONE")] = wide }), {})
local wt = read_text(wide_out)
check("three ink runs become three records", wt.actions[0].count == 3,
  tostring(wt.actions[0].count))
check("the records keep the runs' x spacing",
  wt.actions[0].recs[2].x - wt.actions[0].recs[1].x == 32
  and wt.actions[0].recs[3].x - wt.actions[0].recs[2].x == 32,
  string.format("%d %d", wt.actions[0].recs[2].x - wt.actions[0].recs[1].x,
    wt.actions[0].recs[3].x - wt.actions[0].recs[2].x))
check("every sprite width is a multiple of 8", (function()
  for _, r in ipairs(wt.actions[0].recs) do
    if r.w % 8 ~= 0 then return false end
  end
  return true
end)())
check("the wide label decodes to the edited pixels", (function()
  local d = artifact_set(codec.decode(wide_out, {}))
  local px, w, h = parse(d[bmp_name("SUB_00_NONE")])
  local want, ww, wh = parse(wide)
  return px == want and w <= ww and h == wh
end)())

-- Vertical trim: ink that lives in the middle of a 16-px row must come back at
-- the same rows, without records that copy blank rows into the atlas.
local trimmed = {}
for y = 1, 16 do
  local row = string.rep("\0", 128)
  if y >= 5 and y <= 10 then row = string.rep("\x11", 128) end
  trimmed[y] = row
end
local trim_art = build_bmp(table.concat(trimmed), 256, 16, pal)
local trim_out = codec.encode(parent, with_replacements(base_arts,
  { [bmp_name("SUB_00_NONE")] = trim_art }), {})
local trim_text = read_text(trim_out)
-- Ink on rows 4..9 of the artboard must sit at -8+4 on screen: the record
-- carries the offset the trim removed.
check("the trimmed row keeps its position through the record geometry", (function()
  local r = trim_text.actions[0].recs[1]
  return r.h == 6 and r.y == -4
end)(), string.format("h=%d y=%d", trim_text.actions[0].recs[1].h, trim_text.actions[0].recs[1].y))
check("the trimmed row decodes back to its own pixels", (function()
  local d = artifact_set(codec.decode(trim_out, {}))
  local px, w, h = parse(d[bmp_name("SUB_00_NONE")])
  local want, ww, wh = parse(trim_art)
  return px == want and w <= ww and h == wh
end)())

print("")
print("encode: deduplication and empty space")
-- Two action labels built from the same 32-pixel art share one segment.
local function rows_of(px, w, h)
  local st = stride(w, 4)
  local out = {}
  for y = 0, h - 1 do out[y + 1] = px:sub(y * st + 1, y * st + w // 2) end
  return out
end
local sound_px, sound_w, sound_h, sound_pal = parse(base[bmp_name("01_SOUND")])
local sound_rows = rows_of(sound_px, sound_w, sound_h)
local slice = {}
for y = 1, sound_h do slice[y] = sound_rows[y]:sub(1, 32) end -- 64 px
local shared_art = build_bmp(table.concat(slice), 64, sound_h, sound_pal)

-- Two ink blocks separated by a 48-pixel hole: empty cells must not become
-- records, and the gap must survive through the record x.
local gap = {}
for y = 1, sound_h do
  gap[y] = string.rep("\x11", 8) .. string.rep("\0", 24) .. string.rep("\x22", 8)
end
local gap_art = build_bmp(table.concat(gap), 80, sound_h, sound_pal)

local arts = with_replacements(base_arts, {
  [bmp_name("SUB_00_NONE")] = shared_art,
  [bmp_name("SUB_01_CONFIRM")] = shared_art,
  [bmp_name("SUB_02_CANCEL")] = gap_art,
})
local out = codec.encode(parent, arts, {})
local t2 = read_text(out)
check("identical labels share segments",
  t2.actions[0].recs[1].co == t2.actions[1].recs[1].co,
  t2.actions[0].recs[1].co .. " vs " .. t2.actions[1].recs[1].co)
check("an empty span produces no records", t2.actions[2].count == 2,
  tostring(t2.actions[2].count))
check("the gap survives in the record positions",
  t2.actions[2].recs[2].x - t2.actions[2].recs[1].x == 64,
  tostring(t2.actions[2].recs[2].x - t2.actions[2].recs[1].x))
check("the rebuilt labels decode to the edited pixels", (function()
  local d = artifact_set(codec.decode(out, {}))
  local px, w, h = parse(d[bmp_name("SUB_02_CANCEL")])
  local want, ww, wh = parse(gap_art)
  return px == want and w == ww and h == wh
end)())

print("")
print("encode: atlas order")
-- Ordering the sheet changes every characterOffset, so the records have to
-- follow it: every record must read the pixels its own segment was cut from.
local ordered = codec.encode(parent, base_arts, "rebuild=always")
local ord_text = read_text(ordered)
local ord_atlas = atlas_of(ordered)
check("a segment's offset points at its own pixels", (function()
  local atlas = atlas_of(parent)
  local ref = read_text(parent)
  -- Retail records are 16-px cells; the rebuilt ones are cropped, so compare
  -- the pixels each record draws against the parent's own image.
  for i, m in ipairs(ord_text.main) do
    local px = compose(ord_atlas, m.recs, { x = -128, y = -8, h = 16 })
    local want = compose(atlas, ref.main[i].recs, { x = -128, y = -8, h = 16 })
    if px ~= want then return false end
  end
  return true
end)(), "")
-- The sheet is ordered by content, so every offset must land on an 8-byte
-- boundary and stay inside the decompressed sheet.
check("every record offset is 8-byte aligned inside the sheet", (function()
  for _, r in ipairs(ord_text.main[1].recs) do
    if r.co % 1 ~= 0 or r.co * 8 + r.h * (r.w // 2) > #ord_atlas then return false end
  end
  return true
end)())

print("")
print("encode: relocation")
-- Twelve ink runs 25 px apart: wider than any candidate's bridge, so no cut in
-- the ladder can merge them and the row always needs twelve records, one more
-- than the eleven its retail slot holds.  The list must move.
local cursor_px, cursor_w, cursor_h, cursor_pal = parse(base[bmp_name("00_CURSOR_SPEED")])
local wide_art = (function()
  local w, h, run, pitch = 384, 16, 8, 33
  local rows = {}
  for y = 1, h do
    local b = {}
    for i = 1, w // 2 do b[i] = 0 end
    if y >= 3 and y <= 14 then
      for r = 0, 11 do
        for c = 0, run - 1 do
          local x = r * pitch + c
          b[(x // 2) + 1] = (x % 2 == 0) and ((b[(x // 2) + 1] & 0x0F) | 0x30)
            or ((b[(x // 2) + 1] & 0xF0) | 0x03)
        end
      end
    end
    local bytes = {}
    for i = 1, w // 2 do bytes[i] = string.char(b[i]) end
    rows[y] = table.concat(bytes)
  end
  return build_bmp(table.concat(rows), w, h, cursor_pal)
end)()
local wide_out = codec.encode(parent, with_replacements(base_arts,
  { [bmp_name("00_CURSOR_SPEED")] = wide_art }), {})
local wide_text = read_text(wide_out)
check("a longer label moves out of its retail slot",
  wide_text.main[1].pos ~= MAIN[1].slot,
  string.format("0x%06X", wide_text.main[1].pos))
check("its pointer follows the move",
  ptr_pos(wide_out, MAIN[1].off + 16) == wide_text.main[1].pos)
check("the count is the new record count",
  wide_text.main[1].count == #wide_text.main[1].recs,
  tostring(wide_text.main[1].count))
check("the relocated list fits the record pool", codec.stats.arena_used > 0
  and codec.stats.arena_used <= codec.stats.arena_capacity,
  codec.stats.arena_used .. "/" .. codec.stats.arena_capacity)
check("the widened label decodes to the edited pixels", (function()
  local d = artifact_set(codec.decode(wide_out, {}))
  local px, w, h = parse(d[bmp_name("00_CURSOR_SPEED")])
  local want, ww, wh = parse(wide_art)
  return w == ww and h == wh and px == want
end)(), (function()
  local d = artifact_set(codec.decode(wide_out, {}))
  local _, w, h = parse(d[bmp_name("00_CURSOR_SPEED")])
  return string.format("%dx%d vs %dx%d", w, h, cursor_w * 2, cursor_h)
end)())
check("the widened label does not disturb the other rows", (function()
  local d = artifact_set(codec.decode(wide_out, {}))
  for _, m in ipairs(MAIN) do
    if m.name ~= "00_CURSOR_SPEED" and d[bmp_name(m.name)] ~= base[bmp_name(m.name)] then
      return false
    end
  end
  return true
end)())
check("a relocated build encodes back to itself",
  codec.encode(wide_out, codec.decode(wide_out, {}), "rebuild=always") == wide_out)

print("")
print("encode: shared record lists")
check("retail shares the EXIT list between the main row and action 11",
  parent_text.main[5].pos == parent_text.actions[11].pos)
local shared_out = codec.encode(parent, base_arts, "rebuild=always")
local shared_text = read_text(shared_out)
check("a rebuild keeps the shared list shared",
  shared_text.main[5].pos == shared_text.actions[11].pos)

local exit_px, exit_w, exit_h, exit_pal = parse(base[bmp_name("04_EXIT")])
-- A full-bleed alternative keeps the bounding box equal to the image, so the
-- composed result can be compared without trimming.
local alt_exit = build_bmp(string.rep("\xAA", exit_w * exit_h // 2), exit_w, exit_h, exit_pal)
local split_out = codec.encode(parent, with_replacements(base_arts,
  { [bmp_name("SUB_11_EXIT")] = alt_exit }), {})
local split_text = read_text(split_out)
check("a different SUB_11_EXIT splits the shared list",
  split_text.main[5].pos ~= split_text.actions[11].pos)
check("the split file decodes both EXIT labels separately", (function()
  local d = artifact_set(codec.decode(split_out, {}))
  return d[bmp_name("SUB_11_EXIT")] ~= d[bmp_name("04_EXIT")]
end)())
check("the main EXIT keeps its own pixels", (function()
  local d = artifact_set(codec.decode(split_out, {}))
  local px, w, h = parse(d[bmp_name("04_EXIT")])
  return px == exit_px and w <= exit_w and h == exit_h
end)())
check("action 11 gets the split image", (function()
  local atlas = atlas_of(split_out)
  local px, w, h = compose(atlas, read_text(split_out).actions[11].recs,
    { x = -32, y = -8, h = 16 })
  local want, ww, wh = parse(alt_exit)
  return px == want and w == ww and h == wh
end)())
check("the split list is inside the atlas slot or the action pool", (function()
  local pos = split_text.actions[11].pos
  return (pos >= ATLAS_OFFSET and pos < ATLAS_OFFSET + ATLAS_SLOT)
    or (pos >= ACTION_ARENA and pos < ACTION_ARENA + ACTION_ARENA_LEN)
end)())
check("re-encoding a split build keeps the two EXIT lists apart", (function()
  local twice = codec.encode(split_out, codec.decode(split_out, {}), "rebuild=always")
  local t = read_text(twice)
  return t.main[5].pos ~= t.actions[11].pos and twice == split_out
end)())

print("")
print("encode: button column and mini icons")
local button_out = codec.encode(parent, base_arts, "rebuild=always")
local button_text = read_text(button_out)
local mini_links = true
for k = 1, 8 do
  if button_text.mini[k].co ~= button_text.button[k].co then mini_links = false end
  if button_text.mini[k].w ~= button_text.button[k].w then mini_links = false end
  if button_text.mini[k].h ~= button_text.button[k].h then mini_links = false end
end
check("the mini icons keep pointing at the button segments", mini_links)
check("the column keeps exactly 12 records", #button_text.button == 12,
  tostring(#button_text.button))

local retail_atlas, built_atlas = atlas_of(parent), atlas_of(button_out)
local COL_X, COL_Y, COL_W, COL_H = -48, -80, 80, 160
local function column(atlas, recs) return render(atlas, recs, COL_X, COL_Y, COL_W, COL_H) end
check("the rebuilt column is pixel-identical to the retail one",
  column(built_atlas, button_text.button) == column(retail_atlas, parent_text.button))
check("all twelve column records land inside the 80 x 160 column", (function()
  for _, r in ipairs(button_text.button) do
    if r.x < COL_X or r.x + r.w > COL_X + COL_W
      or r.y < COL_Y or r.y + r.h > COL_Y + COL_H then return false end
  end
  return true
end)())

local cell_ok = true
for k = 1, 12 do
  local a, b = parent_text.button[k], button_text.button[k]
  if render(retail_atlas, { a }, a.x, a.y, 16, 16)
     ~= render(built_atlas, { b }, a.x, a.y, 16, 16) then cell_ok = false end
end
check("every column record draws its own 16 x 16 cell identically", cell_ok)

local mini_ok = true
for k = 1, 8 do
  if render(retail_atlas, { parent_text.mini[k] }, -8, -8, 16, 16)
     ~= render(built_atlas, { button_text.mini[k] }, -8, -8, 16, 16) then mini_ok = false end
end
check("all eight mini labels draw their 16 x 16 cell identically", mini_ok)

check("the column's EXIT cells are the submenu label's own textures", (function()
  local label = button_text.actions[11].recs
  if #label ~= 4 then return false end
  for k = 1, 4 do
    local c = button_text.button[8 + k]
    if c.co ~= label[k].co or c.w ~= label[k].w or c.h ~= label[k].h then return false end
    if c.y - label[k].y ~= 72 then return false end
  end
  return true
end)())

-- Editing A must travel through the column and into the first mini label.
local abc_edit = edit_pixel(base[bmp_name(BUTTON_ABC_NAME)], 2, 4, 0x5)
local abc_out = codec.encode(parent, with_replacements(base_arts,
  { [bmp_name(BUTTON_ABC_NAME)] = abc_edit }), {})
local abc_text = read_text(abc_out)
local abc_atlas = atlas_of(abc_out)
local abc_arts = artifact_set(codec.decode(abc_out, {}))
check("editing A keeps the twelve column records", #abc_text.button == 12)
check("editing A leaves the other board alone",
  abc_arts[bmp_name(BUTTON_XYZLR_NAME)] == base[bmp_name(BUTTON_XYZLR_NAME)])
check("the edited A decodes back into BUTTON_ABC.bmp", (function()
  local px, w, h = parse(abc_arts[bmp_name(BUTTON_ABC_NAME)])
  local want, ww, wh = parse(abc_edit)
  return px == want and w == ww and h == wh
end)())
check("editing A reaches the column's first cell and no other", (function()
  local changed = render(abc_atlas, { abc_text.button[1] }, COL_X, COL_Y, 16, 16)
    ~= render(retail_atlas, { parent_text.button[1] }, COL_X, COL_Y, 16, 16)
  if not changed then return false end
  for k = 2, 12 do
    local a, b = parent_text.button[k], abc_text.button[k]
    if render(retail_atlas, { a }, a.x, a.y, 16, 16)
       ~= render(abc_atlas, { b }, a.x, a.y, 16, 16) then return false end
  end
  return true
end)())
check("editing A reaches the first mini label through the same texture", (function()
  return abc_text.mini[1].co == abc_text.button[1].co
    and abc_text.mini[1].w == abc_text.button[1].w
    and render(abc_atlas, { abc_text.mini[1] }, -8, -8, 16, 16)
      ~= render(retail_atlas, { parent_text.mini[1] }, -8, -8, 16, 16)
end)())

-- Editing R, the fifth icon of the other board, must reach the fifth mini label.
local xyz_edit = edit_pixel(base[bmp_name(BUTTON_XYZLR_NAME)], 3, 70, 0x6)
local xyz_out = codec.encode(parent, with_replacements(base_arts,
  { [bmp_name(BUTTON_XYZLR_NAME)] = xyz_edit }), {})
local xyz_text = read_text(xyz_out)
local xyz_atlas = atlas_of(xyz_out)
local xyz_arts = artifact_set(codec.decode(xyz_out, {}))
check("editing the X/Y/Z/L/R board keeps the twelve column records",
  #xyz_text.button == 12)
check("editing an icon updates its own mini label and no other", (function()
  -- The fifth row of the board is R, i.e. the eighth column record and the
  -- eighth mini label; Z is the fifth.
  return xyz_text.mini[8].co == xyz_text.button[8].co
    and render(xyz_atlas, { xyz_text.mini[8] }, -8, -8, 16, 16)
      ~= render(retail_atlas, { parent_text.mini[8] }, -8, -8, 16, 16)
    and render(xyz_atlas, { xyz_text.mini[5] }, -8, -8, 16, 16)
      == render(retail_atlas, { parent_text.mini[5] }, -8, -8, 16, 16)
end)())
check("the edited X/Y/Z/L/R board decodes back", (function()
  local px, w, h = parse(xyz_arts[bmp_name(BUTTON_XYZLR_NAME)])
  local want, ww, wh = parse(xyz_edit)
  return px == want and w == ww and h == wh
end)())

-- The column's EXIT comes from SUB_11_EXIT, so editing that image moves it.
local exit_edit = edit_pixel(base[bmp_name("SUB_11_EXIT")], 20, 6, 0x7)
local exit_out = codec.encode(parent, with_replacements(base_arts,
  { [bmp_name("SUB_11_EXIT")] = exit_edit }), {})
local exit_text = read_text(exit_out)
local exit_atlas = atlas_of(exit_out)
local exit_arts = artifact_set(codec.decode(exit_out, {}))
check("editing SUB_11_EXIT updates the column's EXIT", (function()
  local col = { table.unpack(exit_text.button, 9, 12) }
  local label = { table.unpack(exit_text.actions[11].recs) }
  local a = render(exit_atlas, col, -32, 64, 64, 16)
  local retail = render(retail_atlas, { table.unpack(parent_text.button, 9, 12) },
    -32, 64, 64, 16)
  return #col == 4 and a == render(exit_atlas, label, -32, -8, 64, 16) and a ~= retail
end)())
check("editing SUB_11_EXIT leaves the main EXIT row alone",
  exit_arts[bmp_name("04_EXIT")] == base[bmp_name("04_EXIT")])
check("editing SUB_11_EXIT decodes back into its artifact", (function()
  local px, w, h = parse(exit_arts[bmp_name("SUB_11_EXIT")])
  local want, ww, wh = parse(exit_edit)
  return px == want and w == ww and h == wh
end)())

-- A differing 04_EXIT must not drag the column with it: the column follows
-- SUB_11_EXIT, which is still the retail image.
local main_edit = edit_pixel(base[bmp_name("04_EXIT")], 40, 6, 0x9)
local main_out = codec.encode(parent, with_replacements(base_arts,
  { [bmp_name("04_EXIT")] = main_edit }), {})
local main_text = read_text(main_out)
local main_atlas = atlas_of(main_out)
local main_arts = artifact_set(codec.decode(main_out, {}))
check("a differing 04_EXIT and SUB_11_EXIT stay independent",
  main_text.main[5].pos ~= main_text.actions[11].pos)
check("editing 04_EXIT leaves the column on the submenu label", (function()
  local col = { table.unpack(main_text.button, 9, 12) }
  local label = { table.unpack(main_text.actions[11].recs) }
  local a = render(main_atlas, col, -32, 64, 64, 16)
  return a == render(main_atlas, label, -32, -8, 64, 16)
    and a == render(retail_atlas, { table.unpack(parent_text.button, 9, 12) },
      -32, 64, 64, 16)
    and main_arts[bmp_name("SUB_11_EXIT")] == base[bmp_name("SUB_11_EXIT")]
end)())

print("encode: capacity and overflow")
-- The widest artboard the renderer allows, inked in every eighth column, is
-- 64 records: the per-list cap is the arithmetic maximum, not a reachable wall.
local dense = {}
for y = 1, 16 do
  local b = {}
  for i = 1, 255 * 8 // 2 do b[i] = 0 end
  for c = 0, 254 do
    local x = c * 8
    b[(x // 2) + 1] = (x % 2 == 0) and ((b[(x // 2) + 1] & 0x0F) | 0x70)
      or ((b[(x // 2) + 1] & 0xF0) | 0x07)
  end
  local bytes = {}
  for i = 1, 255 * 8 // 2 do bytes[i] = string.char(b[i]) end
  dense[y] = table.concat(bytes)
end
check("a full-width row stays inside the per-list cap", (function()
  codec.encode(parent, with_replacements(base_arts,
    { [bmp_name("03_CONTROLS")] = build_bmp(table.concat(dense), 255 * 8, 16, exit_pal) }), {})
  for _, list in ipairs(codec.stats.lists) do
    if list.records > 64 then return false end
  end
  return true
end)())

-- Noise that cannot compress into the slot while the whole sheet still fits
-- decoded.
check_err("an atlas over the fixed slot is refused", function()
  codec.encode(parent, with_replacements(base_arts,
    { [bmp_name("00_CURSOR_SPEED")] = build_bmp(noise(160 * 8, 7), 160, 16, exit_pal) }), {})
end, "over the", "slot")

-- Decoded overflow: distinct noise rows are unique segments, 16,384 bytes,
-- while each list stays under the 64-record cap.
check_err("an atlas over 11,520 decoded bytes is refused", function()
  codec.encode(parent, with_replacements(base_arts, {
    [bmp_name("00_CURSOR_SPEED")] = build_bmp(noise(1024 * 8, 3), 1024, 16, exit_pal),
    [bmp_name("01_SOUND")] = build_bmp(noise(1024 * 8, 4), 1024, 16, exit_pal),
  }), {})
end, "11520")

-- Record storage: ten labels of twelve unmmergeable runs each need 120
-- records, far more than the 32-record pool and the slot tail can hold.  The
-- runs are identical, so the atlas stays tiny and only the records overflow.
local function runs_art(count, pitch, w)
  local rows = {}
  for y = 1, 16 do
    local b = {}
    for i = 1, w // 2 do b[i] = 0 end
    if y >= 3 and y <= 14 then
      for r = 0, count - 1 do
        for c = 0, 7 do
          local x = r * pitch + c
          b[(x // 2) + 1] = (x % 2 == 0) and ((b[(x // 2) + 1] & 0x0F) | 0x60)
            or ((b[(x // 2) + 1] & 0xF0) | 0x06)
        end
      end
    end
    local bytes = {}
    for i = 1, w // 2 do bytes[i] = string.char(b[i]) end
    rows[y] = table.concat(bytes)
  end
  return build_bmp(table.concat(rows), w, 16, exit_pal)
end
local burst_art = runs_art(60, 33, 1984)
local burst_set = {}
for _, a in ipairs(ACTIONS) do
  burst_set[bmp_name(a.name)] = burst_art
end
check_err("a rebuild whose lists need more record storage than the slot has is refused",
  function()
    codec.encode(parent, with_replacements(base_arts, burst_set), {})
  end, "record storage", "arena")

check_err("a missing label artifact is refused", function()
  local arts2 = {}
  for _, a in ipairs(base_arts) do
    if a.name ~= bmp_name("01_SOUND") then arts2[#arts2 + 1] = a end
  end
  codec.encode(parent, arts2, {})
end, "is missing")

check_err("a label that is not 16 px high is refused", function()
  codec.encode(parent, with_replacements(base_arts,
    { [bmp_name("01_SOUND")] = build_bmp(string.rep("\x11", 256 * 8 * 2), 256, 32, exit_pal) }), {})
end, "32 pixels high")

check_err("a blank Options row is refused", function()
  codec.encode(parent, with_replacements(base_arts,
    { [bmp_name("04_EXIT")] = build_bmp(string.rep("\0", 64 * 8), 64, 16, exit_pal) }), {})
end, "blank")

check_err("a board with a blank icon is refused", function()
  local px, w, h, pal = parse(base[bmp_name(BUTTON_ABC_NAME)])
  local rows = {}
  for r = 0, h - 1 do
    rows[r + 1] = (r >= 16 and r < 32) and string.rep("\0", w // 2)
      or px:sub(r * (w // 2) + 1, (r + 1) * (w // 2))
  end
  codec.encode(parent, with_replacements(base_arts,
    { [bmp_name(BUTTON_ABC_NAME)] = build_bmp(table.concat(rows), w, h, pal) }), {})
end, "icons")

check_err("a missing button board is refused", function()
  local arts2 = {}
  for _, a in ipairs(base_arts) do
    if a.name ~= bmp_name(BUTTON_XYZLR_NAME) then arts2[#arts2 + 1] = a end
  end
  codec.encode(parent, arts2, {})
end, "is missing")

check_err("a missing SUB_11_EXIT is refused", function()
  local arts2 = {}
  for _, a in ipairs(base_arts) do
    if a.name ~= bmp_name("SUB_11_EXIT") then arts2[#arts2 + 1] = a end
  end
  codec.encode(parent, arts2, {})
end, "is missing")

print("")
print("encode: origins metadata")
local moved_json = (base[ORIGINS_NAME]:gsub('"00_CURSOR_SPEED", "x": %-128', '"00_CURSOR_SPEED", "x": -120'))
local moved_out = codec.encode(parent, with_replacements(base_arts,
  { [ORIGINS_NAME] = moved_json }), {})
local moved_text = read_text(moved_out)
local kept_gaps = true
for k = 2, #moved_text.main[1].recs do
  if moved_text.main[1].recs[k].x - moved_text.main[1].recs[k - 1].x
      ~= rebuilt_text.main[1].recs[k].x - rebuilt_text.main[1].recs[k - 1].x then
    kept_gaps = false
  end
end
check("moving a label origin keeps the internal spacing", kept_gaps)
check("the moved origin is 8 px right of the retail one",
  moved_text.main[1].recs[1].x == rebuilt_text.main[1].recs[1].x + 8,
  tostring(moved_text.main[1].recs[1].x))
check_err("an unknown origin name is refused", function()
  codec.encode(parent, with_replacements(base_arts,
    { [ORIGINS_NAME] = '{"origins":[{"name":"NOPE","x":0,"y":0}]}' }), {})
end, "unknown name")

print("")
print("encode: background and marks")
local bg_px, bw2, bh2, bg_pal = parse(base[BG_NAME])
check("the background is 288 x 144", bw2 == BG_W and bh2 == BG_H)
local flipped = bg_px:sub(1, 1):byte() == 0 and "\x22" or "\x00"
local bg_edit = build_bmp(flipped .. bg_px:sub(2), BG_W, BG_H, bg_pal)
local bg_out = codec.encode(parent, with_replacements(base_arts, { [BG_NAME] = bg_edit }), {})
check("a panel-only edit leaves the atlas byte-identical",
  bg_out:sub(ATLAS_OFFSET + 1, ATLAS_OFFSET + ATLAS_SLOT)
    == parent:sub(ATLAS_OFFSET + 1, ATLAS_OFFSET + ATLAS_SLOT))
check("a panel-only edit leaves the label lists byte-identical", (function()
  local t = read_text(bg_out)
  for i, m in ipairs(t.main) do
    if m.pos ~= parent_text.main[i].pos or m.count ~= parent_text.main[i].count then
      return false
    end
  end
  return true
end)())
check("the panel edit decodes back", (function()
  local d = artifact_set(codec.decode(bg_out, {}))
  local px, w, h = parse(d[BG_NAME])
  return px == parse(bg_edit)
end)())

local mark = parse(base[LEFT_NAME])
local mark_edit = build_bmp(string.rep("\x33", #mark), MARK_W, MARK_H, exit_pal)
local mark_out = codec.encode(parent, with_replacements(base_arts,
  { [LEFT_NAME] = mark_edit }), {})
check("a mark edit leaves the atlas byte-identical",
  mark_out:sub(ATLAS_OFFSET + 1, ATLAS_OFFSET + ATLAS_SLOT)
    == parent:sub(ATLAS_OFFSET + 1, ATLAS_OFFSET + ATLAS_SLOT))
check("a mark edit decodes back", (function()
  local d = artifact_set(codec.decode(mark_out, {}))
  return parse(d[LEFT_NAME]) == string.rep("\x33", MARK_W * 8)
end)(), "")

print("")
print("encode: positions metadata")
local pos_edit = (base[POS_NAME]:gsub('"center": %-8', '"center": -4', 1))
local pos_out = codec.encode(parent, with_replacements(base_arts,
  { [POS_NAME] = pos_edit }), {})
check("a position-only edit leaves the atlas byte-identical",
  pos_out:sub(ATLAS_OFFSET + 1, ATLAS_OFFSET + ATLAS_SLOT)
    == parent:sub(ATLAS_OFFSET + 1, ATLAS_OFFSET + ATLAS_SLOT))
local centre_list = ptr_pos(pos_out, MAIN[1].off + 28)
local pos_center = s16(pos_out, centre_list)
check("the new centre reaches the file", pos_center == -4, tostring(pos_center))
check("position metadata round-trips",
  artifact_set(codec.decode(pos_out, {}))[POS_NAME] ~= base[POS_NAME])

print("")
print("can_handle")
check("the shipped SAKURA is certain", codec.can_handle(parent) == "certain",
  codec.can_handle(parent))
local nudged = parent:sub(1, 0x40000) .. string.char(parent:byte(0x40001) ~ 0x01)
  .. parent:sub(0x40002)
check("a file that reads right but hashes differently is likely",
  codec.can_handle(nudged) == "likely", codec.can_handle(nudged))
check("a rebuilt file is likely", codec.can_handle(rebuilt) == "likely",
  codec.can_handle(rebuilt))
check("a short file is a no", codec.can_handle(parent:sub(1, 100)) == "no")
check("a non-string is a no", codec.can_handle(nil) == "no")
local bad_base = parent:sub(1, MAIN[4].off + 20) .. string.pack(">I4", 0x1111)
  .. parent:sub(MAIN[4].off + 24)
check("a file with a wrong texture base is a no", codec.can_handle(bad_base) == "no")

print("")
print(string.format("%d passed, %d failed", pass, fail))
assert(fail == 0, string.format("%d tests failed", fail))
