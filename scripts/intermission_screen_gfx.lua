-- The editable sheet is 96x48, three 16-pixel-high labels. Retail decode
-- expands the Japanese glyph atlas. Encode crops transparent 8-pixel columns
-- from each label and packs three textures for intermission_screen_metadata.lua.
-- Palette index 0 is transparent.
local function load_shared(name)
  return dofile(LUDARED.SCRIPTS .. "/shared/" .. name .. ".lua")
end

local bmp       = load_shared("bmp")
local layout    = load_shared("intermission_layout")
local palettes  = load_shared("palettes")
local can_handle = load_shared("can_handle")
local prs       = LUDARED.codec("std/sega/compression/prs")

local codec = {}

codec.name        = "Sakura Taisen Intermission Screen Labels"
codec.description = "PATCH plugin for the intermission-screen command labels in SAKURA1/ICATALL.DAT"
codec.version     = 5
codec.kind        = "patch"

local BLOCK_OFFSET = layout.BLOCK_OFFSET
local BLOCK_SLOT = layout.RETAIL_COMPRESSED

local CELL = layout.ROW_HEIGHT
local CELL_ROW_BYTES = CELL // 2
local CELL_BYTES = CELL * CELL // 2

-- The game's palette for these labels: the fifteen-step grey ramp of
-- shared/palettes.lua's adv_dialogue_jp (white #ffffff down to #e6e6e6), which
-- is what the library's IntermediateScreen.bmp ships in its BMP palette.  Its
-- last entry is replaced by 0x001F, pure red, so index 15 is unmistakable in an
-- editor; the shipping labels never use index 15.
local function label_palette()
  local raw = palettes.raw("adv_dialogue_jp")
  return bmp.from_bgr555(raw:sub(1, #raw - 2) .. string.char(0x00, 0x1F), 16)
end

-- The decompressed atlas the parent holds, validated against the geometry the
-- renderer assumes.
local function read_block(data)
  if type(data) ~= "string" then
    error("intermission_screen: expected a binary string", 0)
  end
  if #data < BLOCK_OFFSET + BLOCK_SLOT then
    error("intermission_screen: input is too small for ICATALL.DAT", 0)
  end

  local pixels = prs:decode(data:sub(BLOCK_OFFSET + 1, BLOCK_OFFSET + BLOCK_SLOT))[1].data
  if not layout.valid_atlas_size(#pixels) then
    error(("intermission_screen: unexpected atlas size of %d bytes at 0x2800"):format(#pixels), 0)
  end
  return pixels
end

-- Atlas -> 96x48 row-major strip, one line per command, in the retail layout.
local function detile(cells)
  local rows = {}
  for y = 0, layout.HEIGHT - 1 do
    local band = y // CELL
    local inner = y % CELL
    local slots = layout.RETAIL[band + 1]
    local row = {}
    for slot = 1, (layout.WIDTH // CELL) do
      local cell = slots[slot]
      if cell == 0 then
        row[#row + 1] = string.rep("\0", CELL_ROW_BYTES)
      else
        local start = (cell - 1) * CELL_BYTES + inner * CELL_ROW_BYTES
        row[#row + 1] = cells:sub(start + 1, start + CELL_ROW_BYTES)
      end
    end
    rows[#rows + 1] = table.concat(row)
  end
  return table.concat(rows)
end

function codec.can_handle(data)
  return can_handle.can_handle_icatall(data)
end

function codec.decode_name()
  return "INTERMISSION"
end

function codec.decode(data)
  return {
    {
      name = layout.NAME,
      data = bmp.build(detile(read_block(data)), layout.WIDTH, layout.HEIGHT, 4, label_palette()),
    },
  }
end

function codec.encode(original, artifacts)
  local cells = read_block(original)

  local edited
  for _, artifact in ipairs(artifacts or {}) do
    if type(artifact) == "table" and artifact.name == layout.NAME then
      edited = artifact.data
    end
  end

  -- No artifact for this codec's strip: nothing to rebuild.
  if not edited then return original end

  local strip = bmp.parse(edited, layout.WIDTH, layout.HEIGHT, 4)
  -- An untouched canonical artifact keeps the retail graphics and renderer.
  if strip == detile(cells) then return original end
  local new_cells = layout.pack(strip)

  local compressed = layout.compress(new_cells)
  compressed = compressed .. string.rep("\0", BLOCK_SLOT - #compressed)

  return original:sub(1, BLOCK_OFFSET)
    .. compressed
    .. original:sub(BLOCK_OFFSET + BLOCK_SLOT + 1)
end

return codec
