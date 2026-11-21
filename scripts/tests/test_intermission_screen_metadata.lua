-- Verify descriptor fields and all texels independently from the shared packer.
local meta = dofile(LUDARED.SCRIPTS .. "/intermission_screen_metadata.lua")
local gfx = dofile(LUDARED.SCRIPTS .. "/intermission_screen_gfx.lua")
local bmp = dofile(LUDARED.SCRIPTS .. "/shared/bmp.lua")
local assets = dofile(LUDARED.SCRIPTS .. "/tests/shared/real_assets.lua")
local prs = LUDARED.codec("std/sega/compression/prs")
local sakura = assets.read("SakTaiCD1_Track1.bin/SAKURA")
local icatall = assets.read("SakTaiCD1_Track1.bin/SAKURA1/ICATALL.DAT")
assert(meta.can_handle(sakura) == "certain" and meta.can_handle("") == "no")

local function verify(widths, lefts)
  local lines, textures = {}, {}
  for band = 1, 3 do
    local rows = {}
    for y = 0, 15 do
      local row = {}
      for byte = 1, widths[band] // 2 do
        row[byte] = string.char((band * 37 + y * 13 + byte) % 255 + 1)
      end
      rows[y + 1] = table.concat(row)
      lines[#lines + 1] = string.rep("\0", lefts[band] // 2) .. rows[y + 1]
        .. string.rep("\0", (96 - lefts[band] - widths[band]) // 2)
    end
    textures[band] = table.concat(rows)
  end
  local sheet = bmp.build(table.concat(lines), 96, 48, 4)
  local patched = meta.patch_layout(sakura, sheet)
  local picture = gfx.encode(icatall, { { name = "INTERMISSION_LABELS.bmp", data = sheet } })
  local atlas = prs:decode(picture:sub(0x2801, 0x2800 + 966))[1].data
  assert(meta.patch_layout(patched, sheet) == patched)
  assert(#patched == #sakura and #picture == #icatall)
  assert(patched:sub(0x3F4A8 + 1, 0x3F4AC) == "\x52\x81\x21\x22")
  assert(patched:sub(0x3F4C0 + 1, 0x3F4C4) == "\x00\x09\x00\x09")

  local offset = 0
  for band = 1, 3 do
    local pointer = string.unpack(">I4", patched, 0x5F5F0 + (band - 1) * 4 + 1)
    local record = pointer - 0x06004000
    local source, terminator, width, height = string.unpack(">I2I2I2I2", patched, record + 1)
    local x = string.unpack(">i2", patched, 0x5F5FC + (band - 1) * 2 + 1)
    -- The patched size load reads the width/height longword at record + 4.
    assert(width == widths[band] and height == 16)
    assert(x == -width // 2)
    -- Existing source calculation subtracts one; its two shifts are removed.
    assert((source - 1) * 8 == offset)
    assert(terminator == 0, "a second draw would be submitted")
    assert(atlas:sub(offset + 1, offset + #textures[band]) == textures[band])
    offset = offset + #textures[band]
  end
  assert(#atlas == 2048 and atlas:sub(offset + 1) == string.rep("\0", 2048 - offset))
  assert(string.unpack(">I4", patched, 0x5F548 + 1) == 966)
  assert(string.unpack(">I2", patched, 0x3F88A + 1) == 0x800)
  assert(picture:sub(0x2800 + 966 + 1) == icatall:sub(0x2800 + 966 + 1))

  -- Exactly two instruction pairs, the row records, and the origins may differ.
  local restored = patched
  for _, range in ipairs({ {0x3F4A8,4}, {0x3F4C0,4}, {0x5F5C8,36}, {0x5F5FC,6} }) do
    local at, size = range[1], range[2]
    restored = restored:sub(1, at) .. sakura:sub(at + 1, at + size) .. restored:sub(at + size + 1)
  end
  assert(restored == sakura)
end

verify({96,48,72}, {0,8,16})
verify({96,96,56}, {0,0,24}) -- original atlas size exceeded within the existing transfer
verify({96,96,64}, {0,0,24}) -- exact transfer boundary
verify({8,8,8}, {0,40,88})

-- Fully transparent rows still submit valid 8x16 textures.
local empty = bmp.build(string.rep("\0", 96 * 48 // 2), 96, 48, 4)
local patched = meta.patch_layout(sakura, empty)
for band = 0, 2 do
  assert(string.unpack(">I2", patched, 0x5F5C8 + band * 12 + 5) == 8)
end

local too_wide = bmp.build(string.rep("\x11", 96 * 48 // 2), 96, 48, 4)
local ok, err = pcall(meta.patch_layout, sakura, too_wide)
assert(not ok and tostring(err):find("2304 decoded bytes, only 2048 fit"))
print("Intermission metadata: three centered sprites, texture addresses and original load budgets passed")
