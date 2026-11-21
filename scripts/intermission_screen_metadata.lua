-- SAKURA draws one texture per row. Reuse its row pointers, selection colors
-- and sprite submission. Each 12-byte record holds source/8 + 1, a zero
-- terminator, width, height, and four padding bytes. Origins remain separate.
local can_handle = dofile(LUDARED.SCRIPTS .. "/shared/can_handle.lua")
local constants = dofile(LUDARED.SCRIPTS .. "/shared/constants.lua")
local layout = dofile(LUDARED.SCRIPTS .. "/shared/intermission_layout.lua")
local bmp = dofile(LUDARED.SCRIPTS .. "/shared/bmp.lua")

local codec = {
  name = "Sakura Taisen Intermission Screen Metadata",
  description = "Derives the intermission texture dimensions and row origins from the label BMP",
  version = 3,
  kind = "patch",
}

local discs = {
  [constants.CD1_SAKURA_BYTES] = { number = 1, rows = 0x5F5C8, renderer = 0x3F4A8 },
  [constants.CD2_SAKURA_BYTES] = { number = 2, rows = 0x5F700, renderer = 0x3F4C0 },
}

codec.can_handle = can_handle.can_handle_sakura1

function codec.decode_name()
  return "INTERMISSION"
end

function codec.decode()
  return {}
end

local function replace(data, offset, bytes)
  return data:sub(1, offset) .. bytes .. data:sub(offset + #bytes + 1)
end

function codec.patch_layout(original, sheet)
  local disc = assert(discs[#original], "intermission_screen: unknown SAKURA size")
  local strip = bmp.parse(sheet, layout.WIDTH, layout.HEIGHT, 4)
  local cells, rows = layout.pack(strip)
  layout.compress(cells)

  local packed, anchors = {}, {}
  for r, row in ipairs(rows) do
    -- The renderer subtracts one, then uses the VDP1 address unit of 8 bytes.
    packed[r] = string.pack(">I2I2I2I2I4", row.offset // 8 + 1, 0, row.width, layout.ROW_HEIGHT, 0)
    anchors[r] = string.pack(">i2", row.x)
  end

  -- mov.l @(4,r8),r2; mov.l r2,@r1 loads width/height together.
  -- The existing height store writes the same low word (16) afterward.
  local size_code = "\x52\x81\x21\x22"
  local current = original:sub(disc.renderer + 1, disc.renderer + 4)
  if current ~= "\xE2\x10\x21\x21" and current ~= size_code then
    error("intermission_screen: unexpected SH-2 texture size instructions in SAKURA", 0)
  end
  local source_site = disc.renderer + 0x18
  current = original:sub(source_site + 1, source_site + 4)
  if current ~= "\x41\x08\x41\x08" and current ~= "\x00\x09\x00\x09" then
    error("intermission_screen: unexpected SH-2 texture stride instructions in SAKURA", 0)
  end

  original = replace(original, disc.renderer, size_code)
  -- Source is already in VDP1 units; remove the old (index - 1) * 16.
  original = replace(original, source_site, "\x00\x09\x00\x09")
  original = replace(original, disc.rows, table.concat(packed))
  return replace(original, disc.rows + 0x34, table.concat(anchors))
end

function codec.encode(original)
  local disc = assert(discs[#original], "intermission_screen: unknown SAKURA size")
  local path = ("SakTaiCD%d_Track1.bin/SAKURA1/ICATALL.DAT/%s"):format(disc.number, layout.NAME)
  -- Removing a Ludared override leaves its file in the workspace. Only consume
  -- the painting if the graphics codec is also going to receive it.
  local query = assert(io.popen("ludared override list " .. path, "r"))
  local active = query:read("*l")
  assert(query:close(), "intermission_screen: could not resolve the label override")
  if active ~= path then return original end

  local file = assert(io.open(LUDARED.WORKSPACE .. "/" .. path, "rb"))
  local sheet = assert(file:read("*a"))
  file:close()
  return codec.patch_layout(original, sheet)
end

return codec
