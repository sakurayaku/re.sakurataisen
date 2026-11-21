-- Three row-major 4bpp textures, each 16 pixels high and 8-pixel aligned.
local M = {}

M.NAME = "INTERMISSION_LABELS.bmp"
M.ROWS = 3
M.WIDTH = 96
M.ROW_HEIGHT = 16
M.HEIGHT = M.ROWS * M.ROW_HEIGHT
M.RETAIL_ATLAS_BYTES = 1920
M.ATLAS_BYTES = 2048
M.BLOCK_OFFSET = 0x2800
M.RETAIL_COMPRESSED = 966
M.RETAIL = {
  { 2, 1, 3, 4, 5, 0 },
  { 6, 7, 8, 9, 10, 0 },
  { 11, 1, 12, 13, 14, 15 },
}

function M.pack(strip)
  local textures, rows = {}, {}
  local used = 0
  for band = 0, M.ROWS - 1 do
    local first, last = nil, 0
    for column = 0, M.WIDTH // 8 - 1 do
      for y = 0, M.ROW_HEIGHT - 1 do
        local start = (band * M.ROW_HEIGHT + y) * (M.WIDTH // 2) + column * 4
        if strip:sub(start + 1, start + 4) ~= "\0\0\0\0" then
          first = first or column
          last = column
          break
        end
      end
    end

    -- A fully transparent row uses one 8x16 texture.
    first = first or 0
    local width = (last - first + 1) * 8
    local lines = {}
    for y = 0, M.ROW_HEIGHT - 1 do
      local start = (band * M.ROW_HEIGHT + y) * (M.WIDTH // 2) + first * 4
      lines[y + 1] = strip:sub(start + 1, start + width // 2)
    end
    rows[band + 1] = { width = width, x = -width // 2, offset = used }
    textures[band + 1] = table.concat(lines)
    used = used + width * M.ROW_HEIGHT // 2
  end

  if used > M.ATLAS_BYTES then
    error(("intermission_screen: widths %d + %d + %d px need %d decoded bytes, only %d fit (%d over budget)")
      :format(rows[1].width, rows[2].width, rows[3].width, used, M.ATLAS_BYTES, used - M.ATLAS_BYTES), 0)
  end
  return table.concat(textures) .. string.rep("\0", M.ATLAS_BYTES - used), rows, used
end

function M.compress(cells)
  if not M.valid_atlas_size(#cells) then
    error(("intermission_screen: atlas needs %d bytes; the existing VRAM transfer allows %d bytes")
      :format(#cells, M.ATLAS_BYTES), 0)
  end
  local prs = LUDARED.codec("std/sega/compression/prs")
  local data = prs:encode("", { { name = "DECOMPRESSED", data = cells } })
  if #data > M.RETAIL_COMPRESSED then
    error(("intermission_screen: labels need %d compressed bytes, only %d fit at 0x2800 (%d over budget)")
      :format(#data, M.RETAIL_COMPRESSED, #data - M.RETAIL_COMPRESSED), 0)
  end
  return data
end

function M.valid_atlas_size(size)
  return size == M.RETAIL_ATLAS_BYTES or size == M.ATLAS_BYTES
end

return M
