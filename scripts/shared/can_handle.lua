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



return {
  can_handle_sakura1 = can_handle_sakura1,
  can_handle_logo_sh2 = can_handle_logo_sh2,
  identify_theater_map = identify_theater_map,
  can_handle_theater_map = can_handle_theater_map,
  can_handle_icatall = can_handle_icatall,
}
