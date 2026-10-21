-- Run: lua scripts/shared/test_vwf.lua [pristine-SAKURA]
-- Executes the real fnC instructions up to its epilogue, with GLYPH stubbed.
-- This catches cursor/index confusion, delay-slot errors and count overruns.
local script = debug.getinfo(1, "S").source:sub(2)
local root = (script:match("^(.*)/scripts/shared/") or ".")
local function read(path)
  local f = assert(io.open(path, "rb"))
  local data = f:read("*a")
  f:close()
  return data
end
local patch = dofile(root .. "/scripts/SAKURA/patch_vwf_font.lua")
local original = read(arg[1] or root .. "/SAKURA")
local binary = patch.encode(original, {})
assert(#binary == #original)
assert(patch.encode(binary, {}) == binary, "patch must be idempotent")

local function signed(value, bits)
  local mask = (1 << bits) - 1
  value = value & mask
  return value >= (1 << (bits - 1)) and value - (1 << bits) or value
end

local function render(code, words, count)
  local r, draws, t = {}, {}, false
  for i = 0, 15 do r[i] = 0 end
  r[4], r[5], r[6], r[7] = -96, 60, 0x1000, count
  local pc = 0x0601470E -- after fnC's register-saving prologue
  local function load(address, size)
    if address >= 0x06004000 then
      local offset = address - 0x06004000
      return string.unpack(size == 2 and ">I2" or ">I4", code, offset + 1)
    end
    assert(size == 2 and address >= 0x1000 and address % 2 == 0,
      string.format("unexpected read at %08X", address))
    return assert(words[(address - 0x1000) // 2 + 1], "read beyond text buffer")
  end
  local instruction
  instruction = function(address)
    local op = load(address, 2)
    local n, m = (op >> 8) & 15, (op >> 4) & 15
    local kind = op & 0xF00F
    if op == 0x0009 then -- nop
    elseif kind == 0x6003 then r[n] = r[m] -- mov
    elseif kind == 0x600F then r[n] = signed(r[m], 16) -- exts.w
    elseif kind == 0x600D then r[n] = r[m] & 0xFFFF -- extu.w
    elseif kind == 0x600C then r[n] = r[m] & 0xFF -- extu.b
    elseif kind == 0x000D then r[n] = signed(load(r[0] + r[m], 2), 16)
    elseif kind == 0x3000 then t = r[n] == r[m] -- cmp/eq
    elseif kind == 0x2008 then t = (r[n] & r[m]) == 0 -- tst
    elseif kind == 0x300C then r[n] = signed(r[n] + r[m], 32) -- add
    elseif op & 0xF000 == 0x7000 then r[n] = signed(r[n] + signed(op, 8), 32)
    elseif op & 0xF000 == 0xE000 then r[n] = signed(op, 8)
    elseif op & 0xF000 == 0x9000 then
      r[n] = signed(load(address + 4 + (op & 255) * 2, 2), 16)
    elseif op & 0xF000 == 0xD000 then
      r[n] = load((address & ~3) + 4 + (op & 255) * 4, 4)
    elseif op & 0xFF00 == 0x8D00 or op & 0xFF00 == 0x8F00 then
      local taken = t == (op & 0xFF00 == 0x8D00)
      instruction(address + 2) -- delay slot, even if not taken
      return taken and address + 4 + signed(op, 8) * 2 or address + 4
    elseif op & 0xF000 == 0xA000 then
      instruction(address + 2)
      return address + 4 + signed(op, 12) * 2
    elseif op & 0xF0FF == 0x400B then -- jsr @Rn
      local target = r[n]
      instruction(address + 2)
      assert(target == 0x06014364, "unexpected draw target")
      draws[#draws + 1] = { x = r[4], y = r[5], packed = r[6] }
      -- A callee may overwrite caller-saved registers; width must be consumed
      -- before the call, and the loop must keep its state in r8..r13.
      for i = 0, 7 do r[i] = 0xBAD end
      return address + 4
    else
      error(string.format("unsupported instruction %04X at %08X", op, address))
    end
    return address + 2
  end
  for _ = 1, 2000 do
    if pc == 0x06014756 then return draws, r end
    pc = instruction(pc)
  end
  error("fnC failed to return within the instruction budget")
end

local function check_render(words, count)
  local draws, regs = render(binary, words, count)
  local x, y, drawn = -96, 60, 0
  for i = 1, count do
    local word = words[i]
    if word == 0x000D then
      x, y = -96, y + 12
    elseif word ~= 0 then
      drawn = drawn + 1
      local got = assert(draws[drawn], "missing glyph")
      assert(got.x == x and got.y == y and got.packed == word,
        "wrong glyph or position")
      x = x + (word & 255)
    end
  end
  assert(#draws == drawn and regs[9] == count and regs[8] == x)
end

local words = { 0x4109, 0x000D, 0x4209, 0x000D, 0x4309, 0x000D, 0x3409, 0 }
for count = 0, #words do check_render(words, count) end
check_render({ 0x4109, 0x6903, 0x570D, 0xE908, 0 }, 5)
check_render({ 0x000D, 0x000D, 0x4109, 0 }, 4)
check_render({ 0x4109, 0, 0x4209 }, 3)
assert(binary:sub(0x1036D, 0x1036E) == "\x46\x19", "GLYPH must decode the high byte")

-- Prove that this harness catches the reported bug, not just patch byte drift.
local broken = binary:sub(1, 0x10746) .. "\x39\x0C" .. binary:sub(0x10749)
local ok, err = pcall(render, broken, { 0x4109, 0 }, 1)
assert(not ok and tostring(err):find("read beyond text buffer", 1, true),
  "the old index-advance bug must fail")

-- Producer/consumer contract with the actual font table, including newline,
-- metadata, terminator, footer and the unpatched SLG encoding.  TXT lines are
-- numbered (NNNN:); 0x0A0D would be a valid packed word, so the newline code is
-- the assertion that tells the two layouts apart.
ACTIVATE_VWF, ENCODE_FONT = true, "I18N_FONT"
local dialogues = dofile(root .. "/scripts/dialogues.lua")
local input = string.pack(">I2I2I2I2I2I2I2I2", 4, 8, 0x2716, 0, 0xABCD, 2, 0x41, 0) .. "footer"
local output = dialogues.encode(input, { { name = "0100TBL.TXT", data = "0001:A<br>B<br>C<br>4\n" } }, "0100KNJ")
assert(output:sub(9, 12) == "\xAB\xCD\x00\x02")
assert(output:sub(13, 28) == "\x41\x09\x00\x0D\x42\x09\x00\x0D\x43\x09\x00\x0D\x34\x09\x00\x00")
assert(output:sub(29) == "footer")
assert(dialogues.decode(output, "I18N_FONT")[1].data == "0001:A<br>B<br>C<br>4\n")
assert(dialogues.encode(output, dialogues.decode(output, "I18N_FONT"), "I18N_FONT") == output)

-- The unpatched SLG engine keeps the plain-ID layout, whatever ACTIVATE_VWF is.
local slg = dialogues.encode(input, { { name = "M01MES.TXT", data = "0001:A<br>B\n" } }, "M01MES")
assert(slg:sub(13, 20) == "\x00\x41\x0A\x0D\x00\x42\x00\x00")
print("VWF: 4 renderer cases per count, original-bug reproduction, patch idempotence and dialogue ABI passed")
