--[[
  Sega Saturn PRS compression/decompression library.

  This is the bit-packed PRS variant used by Sakura Taisen's LOGO.SH2 (and the
  other Saturn assets unpacked by RomHackingTools). It matches
  RomHackingTools/Utils/prs-decomp.cpp:

    flag bit 1        -> literal byte follows
    flag bits 0 1     -> long back-reference: 16-bit word, or end marker when 0
    flag bits 0 0     -> short back-reference: 2 size bits + 1 offset byte

  Bits are consumed LSB-first out of each flag byte.
]]

local M = {}

-- A long reference at distance 8192 with a size byte would encode as the
-- end marker (word 0), so the encoder stays one byte short of the limit.
local MAX_DISTANCE = 8191
local MAX_LENGTH   = 256

-- Candidates examined per position.  Longer chains buy a few bytes at a
-- quadratic cost: the main-menu background goes from 3,781 bytes at 256 to
-- 3,763 at 384, but the pair takes 14 seconds instead of 10.
local SAME_CHAIN   = 256

local function make_reader(data)
  local pos, len = 1, #data
  local flags, bits = 0, 0

  local function read_bit()
    if bits == 0 then
      if pos > len then
        return nil
      end
      flags = string.byte(data, pos)
      pos = pos + 1
      bits = 8
    end

    local value = flags & 1
    flags = flags >> 1
    bits = bits - 1
    return value
  end

  local function read_byte()
    if pos > len then
      return nil
    end
    local value = string.byte(data, pos)
    pos = pos + 1
    return value
  end

  local function read_word()
    local lo = read_byte()
    if lo == nil then
      return nil
    end
    local hi = read_byte()
    if hi == nil then
      return nil
    end
    return lo | (hi << 8)
  end

  return read_bit, read_byte, read_word
end

function M.decompress(data)
  if type(data) ~= "string" then
    error("PRS decompress: expected string data", 2)
  end
  if #data == 0 then
    return ""
  end

  local read_bit, read_byte, read_word = make_reader(data)

  local out, count = {}, 0

  while true do
    local flag = read_bit()
    if flag == nil then
      break
    end

    if flag == 1 then
      -- Literal byte
      local byte = read_byte()
      if byte == nil then
        break
      end
      count = count + 1
      out[count] = byte
    else
      local long = read_bit()
      if long == nil then
        break
      end

      local size, distance

      if long == 1 then
        -- Long back-reference, or the end marker when the word is zero
        local value = read_word()
        if value == nil or value == 0 then
          break
        end

        local size_bits = value & 7
        distance = 8192 - (value >> 3)

        if size_bits == 0 then
          local extra = read_byte()
          if extra == nil then
            break
          end
          size = extra + 1
        else
          size = size_bits + 2
        end
      else
        -- Short back-reference (2..5 bytes, within 256 bytes)
        local high = read_bit()
        if high == nil then
          break
        end
        local low = read_bit()
        if low == nil then
          break
        end
        size = (low | (high << 1)) + 2

        local offset = read_byte()
        if offset == nil then
          break
        end
        distance = 256 - offset
      end

      local src = count - distance + 1
      if src < 1 then
        -- Corrupt stream: reference before the start of the buffer
        break
      end

      for _ = 1, size do
        count = count + 1
        out[count] = out[src]
        src = src + 1
      end
    end
  end

  local parts = {}
  for i = 1, count, 2048 do
    local chunk = {}
    for j = i, math.min(i + 2047, count) do
      chunk[#chunk + 1] = out[j]
    end
    parts[#parts + 1] = string.char(table.unpack(chunk))
  end

  return table.concat(parts)
end

function M.compress(data)
  if type(data) ~= "string" then
    error("PRS compress: expected string data", 2)
  end

  local n = #data

  -- Items are collected first and serialised afterwards: the flag bytes form a
  -- continuous bit stream, and an item's payload follows the flag byte that
  -- holds its final bit (items may straddle a flag byte).
  local items = {}

  local function add(bits, payload)
    items[#items + 1] = { bits = bits, payload = payload or "" }
  end

  if n == 0 then
    add("01", "\0\0")
  else
    local head, prev = {}, {}

    local function key_at(p)
      return (string.byte(data, p) << 8) | string.byte(data, p + 1)
    end

    local function insert(p)
      if p + 1 <= n then
        local key = key_at(p)
        prev[p] = head[key]
        head[key] = p
      end
    end

    -- Two passes.  The first walks forward and records, for every position,
    -- the longest match available and the longest one a short reference can
    -- carry; the second walks backward choosing the cheapest encoding of the
    -- suffix.  Greedy parsing left roughly 1% on the table versus the shipping
    -- encoder, which matters here: the main-menu blocks sit in a fixed budget
    -- and the original art already fills it.
    --
    -- Bit costs: literal 9 (1 flag + 8), short reference 10 (2 + 8), long
    -- reference 18 (2 + 16) for lengths 3..9 and 26 (2 + 16 + 8) from length 10
    -- up.  Within a flat-cost class a longer match is always at least as good,
    -- because the cost of the remaining suffix never grows with a later start,
    -- so only one candidate per class has to be tried.
    local max_long, dist_long, max_short, dist_short = {}, {}, {}, {}

    for p = 1, n do
      local best_len, best_dist, short_len, short_dist = 0, 0, 0, 0

      if p + 1 <= n then
        local limit = math.min(MAX_LENGTH, n - p + 1)
        local candidate = head[key_at(p)]
        local chain = 0

        while candidate and (p - candidate) <= MAX_DISTANCE and chain < SAME_CHAIN do
          local distance = p - candidate
          -- The hash key already established that the first two bytes match.
          local length = 2
          while length < limit
            and string.byte(data, candidate + length) == string.byte(data, p + length) do
            length = length + 1
          end

          if length > best_len then
            best_len, best_dist = length, distance
          end
          if length > short_len and distance <= 256 then
            short_len, short_dist = length, distance
          end

          if best_len == limit and short_len >= math.min(5, limit) then
            break
          end

          candidate = prev[candidate]
          chain = chain + 1
        end
      end

      max_long[p], dist_long[p] = best_len, best_dist
      if short_len >= 2 then
        -- A short reference carries at most five bytes.
        max_short[p], dist_short[p] = math.min(short_len, 5), short_dist
      end
      insert(p)
    end

    local cost, kind, length, distance = {}, {}, {}, {}
    cost[n + 1] = 0

    for p = n, 1, -1 do
      local best_bits = 9 + cost[p + 1]
      local best_kind, best_len, best_dist = "lit", 1, 0

      local short = max_short[p]
      if short then
        local bits = 10 + cost[p + short]
        if bits < best_bits then
          best_bits, best_kind, best_len, best_dist = bits, "short", short, dist_short[p]
        end
      end

      local long = max_long[p]
      if long >= 3 then
        local mid = math.min(9, long)
        local bits = 18 + cost[p + mid]
        if bits < best_bits then
          best_bits, best_kind, best_len, best_dist = bits, "long", mid, dist_long[p]
        end

        if long >= 10 then
          bits = 26 + cost[p + long]
          if bits < best_bits then
            best_bits, best_kind, best_len, best_dist = bits, "long", long, dist_long[p]
          end
        end
      end

      cost[p], kind[p], length[p], distance[p] = best_bits, best_kind, best_len, best_dist
    end

    local pos = 1
    while pos <= n do
      local len = length[pos]

      if kind[pos] == "short" then
        local size_bits = len - 2
        add("00" .. (size_bits >> 1 == 1 and "1" or "0") .. (size_bits & 1 == 1 and "1" or "0"),
            string.char(256 - distance[pos]))
      elseif kind[pos] == "long" then
        local size_bits, extra = 0, nil
        if len <= 9 then
          size_bits = len - 2
        else
          extra = len - 1
        end
        local value = ((8192 - distance[pos]) << 3) | size_bits
        local bytes = string.char(value & 0xFF, (value >> 8) & 0xFF)
        if extra then
          bytes = bytes .. string.char(extra)
        end
        add("01", bytes)
      else
        add("1", string.sub(data, pos, pos))
        len = 1
      end

      pos = pos + len
    end

    add("01", "\0\0")
  end

  -- Group the bit stream into flag bytes, attaching each payload to the byte
  -- that holds the item's last bit.
  local groups, bitpos = {}, 0

  for _, item in ipairs(items) do
    local nbits = #item.bits

    for k = 1, nbits do
      local bit = bitpos + k - 1
      local group = bit // 8
      local entry = groups[group]
      if not entry then
        entry = { flag = 0, payload = {} }
        groups[group] = entry
      end
      if item.bits:byte(k) == 49 then -- "1"
        entry.flag = entry.flag | (1 << (bit % 8))
      end
    end

    local last_group = (bitpos + nbits - 1) // 8
    local entry = groups[last_group]
    if not entry then
      entry = { flag = 0, payload = {} }
      groups[last_group] = entry
    end
    if #item.payload > 0 then
      entry.payload[#entry.payload + 1] = item.payload
    end

    bitpos = bitpos + nbits
  end

  local out = {}
  for group = 0, (bitpos + 7) // 8 - 1 do
    local entry = groups[group]
    if entry then
      out[#out + 1] = string.char(entry.flag)
      if #entry.payload > 0 then
        out[#out + 1] = table.concat(entry.payload)
      end
    end
  end

  return table.concat(out)
end

return M
