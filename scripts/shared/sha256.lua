--[[ SHA-256 (FIPS 180-4) in plain Lua 5.3+ arithmetic.

  Ludared's Lua API exposes no crypto module, and a codec that wants to say
  "this is the exact file I was built against" needs a real digest rather than
  a hand-rolled checksum.  Only the one-shot form is provided:

      local sha256 = dofile("scripts/shared/sha256.lua")
      sha256.hex(data)   --> 64 lowercase hex characters

  Words are held as non-negative 32-bit values (masked after every addition),
  so `>>` stays a logical shift.
]]

local M = {}

local K = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local MASK = 0xFFFFFFFF

local function rotr(x, n)
  return ((x >> n) | (x << (32 - n))) & MASK
end

local function compress(H, block)
  local w = {}
  for i = 0, 15 do
    local o = i * 4
    w[i] = ((block:byte(o + 1) << 24) | (block:byte(o + 2) << 16)
      | (block:byte(o + 3) << 8) | block:byte(o + 4)) & MASK
  end
  for i = 16, 63 do
    local x, y = w[i - 15], w[i - 2]
    local s0 = rotr(x, 7) ~ rotr(x, 18) ~ (x >> 3)
    local s1 = rotr(y, 17) ~ rotr(y, 19) ~ (y >> 10)
    w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & MASK
  end

  local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
  for i = 0, 63 do
    local s1 = rotr(e, 6) ~ rotr(e, 11) ~ rotr(e, 25)
    local ch = (e & f) ~ ((~e) & g)
    local t1 = (h + s1 + ch + K[i + 1] + w[i]) & MASK
    local s0 = rotr(a, 2) ~ rotr(a, 13) ~ rotr(a, 22)
    local maj = (a & b) ~ (a & c) ~ (b & c)
    local t2 = (s0 + maj) & MASK
    h, g, f, e, d, c, b, a =
      g, f, e, (d + t1) & MASK, c, b, a, (t1 + t2) & MASK
  end

  H[1] = (H[1] + a) & MASK
  H[2] = (H[2] + b) & MASK
  H[3] = (H[3] + c) & MASK
  H[4] = (H[4] + d) & MASK
  H[5] = (H[5] + e) & MASK
  H[6] = (H[6] + f) & MASK
  H[7] = (H[7] + g) & MASK
  H[8] = (H[8] + h) & MASK
end

function M.hex(data)
  if type(data) ~= "string" then
    error("sha256: expected a string, got " .. type(data), 2)
  end

  local H = {
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  }

  -- Only the final partial block is copied: the bulk is walked in place, so a
  -- multi-megabyte input costs no extra allocations beyond the output.
  local len = #data
  local full = len - len % 64
  for i = 1, full, 64 do
    compress(H, data:sub(i, i + 63))
  end

  local rest = data:sub(full + 1)
  local pad = #rest < 56 and 56 - #rest or 120 - #rest
  local bits = len * 8
  local tail = rest .. "\x80" .. string.rep("\x00", pad - 1)
    .. string.pack(">I4I4", (bits // 0x100000000) & MASK, bits & MASK)
  for i = 1, #tail, 64 do
    compress(H, tail:sub(i, i + 63))
  end

  local out = {}
  for i = 1, 8 do
    out[i] = string.format("%08x", H[i])
  end
  return table.concat(out)
end

return M
