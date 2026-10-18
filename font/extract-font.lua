local codec = dofile("../scripts/font.lua")

local input = assert(io.open(assert(arg[1], "Usage: lua extract-font.lua <file>"), "rb"))
local artifacts = codec.decode(input:read("*a"))
input:close()

for _, artifact in ipairs(artifacts) do
  local output = assert(io.open(artifact.name, "wb"))
  output:write(artifact.data)
  output:close()
end