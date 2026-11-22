-- Exact detection for the retail executable and logo modules.
local constants = dofile(LUDARED.SCRIPTS .. "/shared/constants.lua")

local function matches(data, byte_count, hash)
  return type(data) == "string" and #data == byte_count
    and LUDARED.sha256(data) == hash
end

local function sakura1_disc(data)
  if matches(data, constants.CD1_SAKURA_BYTES, constants.CD1_SAKURA_SHA256) then
    return 1
  end
  if matches(data, constants.CD2_SAKURA_BYTES, constants.CD2_SAKURA_SHA256) then
    return 2
  end
  return nil
end

local function can_handle_sakura1(data)
  return sakura1_disc(data) and "certain" or "no"
end



-- A WKL header: a 98-entry block list, the battle-menu table pointer at 0xE8
-- with that region's size at 0xEC, and the compressed-name table pointer at
-- 0x100.  The three have to agree with each other, and the first command block
-- has to start right after the table, which no other file on the disc does.
local WKL_HEADER_BYTES  = 0x310
local WKL_MENU_POINTER  = 0x0E8
local WKL_MENU_SIZE     = 0x0EC
local WKL_MOVES_POINTER = 0x100
local WKL_MOVES_ENTRIES = 64

local function wkl_u32(data, offset)
  if offset + 4 > #data then return nil end
  return string.unpack(">I4", data, offset + 1)
end

local function can_handle_combat_commands(data)
  if type(data) ~= "string" or #data < WKL_HEADER_BYTES + 8 then return "no" end

  local menu = wkl_u32(data, WKL_MENU_POINTER)
  local size = wkl_u32(data, WKL_MENU_SIZE)
  if not menu or menu < WKL_HEADER_BYTES or menu + 8 > #data then return "no" end
  if not size or size < 8 or menu + size > #data then return "no" end

  -- The table describes 16 blocks at retail and is a whole number of entries.
  local table_bytes = wkl_u32(data, menu)
  if not table_bytes or table_bytes < 8 or table_bytes % 8 ~= 0
      or table_bytes > 256 * 8 or table_bytes > size
      or menu + table_bytes + 8 > #data then
    return "no"
  end

  -- The blocks follow the table contiguously: the first block's offset is the
  -- table's own byte length, and it has to hold at least a header.
  local block = wkl_u32(data, menu + 4)
  if not block or block == 0 or menu + table_bytes + block > menu + size then
    return "no"
  end

  -- The 64-entry compressed-name table follows its own entries: its first
  -- stream starts at 64 * 8 bytes from the table.
  local moves = wkl_u32(data, WKL_MOVES_POINTER)
  if not moves or moves < WKL_HEADER_BYTES
      or moves + WKL_MOVES_ENTRIES * 8 > #data then
    return "no"
  end
  if wkl_u32(data, moves) ~= WKL_MOVES_ENTRIES * 8 then return "no" end

  return "likely"
end

local function can_handle_slg(data)
  -- The strategy-game executable.  SLG.BIN and 0SLG.BIN are byte-identical on
  -- the disc, so the one hash identifies either name.
  return matches(data, constants.CD1_SLG_BYTES, constants.CD1_SLG_SHA256)
    and "certain" or "no"
end

local function can_handle_logo_sh2(data)
  if type(data) ~= "string" then return "no" end
  if #data ~= constants.CD1_LOGO_SH2_BYTES
      and #data ~= constants.CD2_LOGO_SH2_BYTES then
    return "no"
  end

  local hash = LUDARED.sha256(data)
  if hash == constants.CD1_LOGO_SH2_SHA256 or hash == constants.CD2_LOGO_SH2_SHA256 then
    return "certain"
  end
  return "no"
end

local function identify_theater_map(data)
  if matches(data, constants.CD1_TMAPSP_BYTES, constants.CD1_TMAPSP_SHA256)
      or matches(data, constants.CD2_TMAPSP_BYTES, constants.CD2_TMAPSP_SHA256) then
    return "TMAPSP"
  end
  if matches(data, constants.CD1_FUKAGAWA_BYTES, constants.CD1_FUKAGAWA_SHA256)
      or matches(data, constants.CD2_FUKAGAWA_BYTES, constants.CD2_FUKAGAWA_SHA256) then
    return "FUKAGAWA"
  end
  return nil
end

local function can_handle_theater_map(data)
  return identify_theater_map(data) and "certain" or "no"
end

local function can_handle_icatall(data)
  return matches(data, constants.CD1_ICATALL_BYTES, constants.CD1_ICATALL_SHA256) and "certain" or "no"
end

local function can_handle_sakura4(data)
  -- TODO: Restore me with proper values
  return "likely"
end

return {
  can_handle_sakura1 = can_handle_sakura1,
  can_handle_sakura4 = can_handle_sakura4,
  can_handle_logo_sh2 = can_handle_logo_sh2,
  identify_theater_map = identify_theater_map,
  can_handle_theater_map = can_handle_theater_map,
  can_handle_icatall = can_handle_icatall,
  can_handle_combat_commands = can_handle_combat_commands,
  can_handle_slg = can_handle_slg,
}
