local shared = assert(loadfile(LUDARED.SCRIPTS .. "/shared/options_menu.lua"))
local codec = shared("sakura")
local can_handle = dofile(LUDARED.SCRIPTS .. "/shared/can_handle.lua")

function codec.can_handle(data)
  return can_handle.can_handle_sakura1(data)
end

return codec
