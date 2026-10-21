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

    -- Longest match for p, searching the most recent candidates first.
    local function find(p)
      local best_len, best_dist = 0, 0

      if p + 1 <= n then
        local max_len = math.min(MAX_LENGTH, n - p + 1)
        local candidate = head[key_at(p)]
        local chain = 0

        while candidate and (p - candidate) <= MAX_DISTANCE and chain < 1024 do
          local length = 0
          while length < max_len
            and string.byte(data, candidate + length) == string.byte(data, p + length) do
            length = length + 1
          end

          if length > best_len then
            best_len = length
            best_dist = p - candidate
            if best_len == max_len then
              break
            end
          end

          candidate = prev[candidate]
          chain = chain + 1
        end
      end

      return best_len, best_dist
    end

    local pos = 1
    while pos <= n do
      local best_len, best_dist = find(pos)

      -- Lazy matching: if the next byte starts a longer match, emit a literal.
      if best_len >= 2 and pos < n and find(pos + 1) > best_len then
        best_len = 0
      end

      local emitted = 1

      if best_len >= 2 then
        local encoded = false

        if best_dist <= 256 and best_len <= 5 then
          -- Short back-reference: 00 + 2 size bits + offset byte
          local size_bits = best_len - 2
          local high = (size_bits >> 1) & 1
          local low = size_bits & 1
          add("00" .. (high == 1 and "1" or "0") .. (low == 1 and "1" or "0"),
              string.char(256 - best_dist))
          encoded = true
        end

        if not encoded and best_len >= 3 then
          -- Long back-reference: 01 + 16-bit word (+ size byte for len >= 10)
          local size_bits = 0
          local extra = nil
          if best_len <= 9 then
            size_bits = best_len - 2
          else
            extra = best_len - 1
          end

          local value = ((8192 - best_dist) << 3) | size_bits
          local bytes = string.char(value & 0xFF, (value >> 8) & 0xFF)
          if extra then
            bytes = bytes .. string.char(extra)
          end

          add("01", bytes)
          encoded = true
        end

        if encoded then
          emitted = best_len
        end
      end

      if emitted == 1 then
        add("1", string.sub(data, pos, pos))
      end

      for p = pos, pos + emitted - 1 do
        insert(p)
      end
      pos = pos + emitted
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
