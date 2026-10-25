--[[ Test harness for sha256.lua — run from the project root: ludared codecs test tests/test_sha256.lua ]]

local sha256 = dofile(LUDARED.SCRIPTS .. "/shared/sha256.lua")

local pass, fail = 0, 0
local function check(name, ok, detail)
  if ok then pass = pass + 1; print("  ok    " .. name)
  else fail = fail + 1; print("  FAIL  " .. name .. (detail and ("  -- " .. detail) or "")) end
end

print("sha256.lua test harness")
print("")
print("published vectors")

-- FIPS 180-4 / NIST samples, plus the padding boundaries either side of 56
-- bytes, which is where an off-by-one in the length trailer shows up.
for _, case in ipairs({
  { "the empty string", "",
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" },
  { "\"abc\"", "abc",
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" },
  { "55 a's (one short of the trailer)", string.rep("a", 55),
    "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318" },
  { "56 a's (needs a second block)", string.rep("a", 56),
    "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a" },
  { "64 a's (exactly one block)", string.rep("a", 64),
    "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb" },
  { "a million a's", string.rep("a", 1000000),
    "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0" },
}) do
  local got = sha256.hex(case[2])
  check(case[1], got == case[3], got)
end

print("")
print("binary input")
-- Bytes above 127 must not be mangled by the string/char path.
local bytes = {}
for i = 0, 255 do bytes[i + 1] = string.char(i) end
local all = table.concat(bytes)
check("all 256 byte values", sha256.hex(all) ==
  "40aff2e9d2d8922e47afd4648e6967497158785fbd1da870e7110266bf944880", sha256.hex(all))

print("")
print("errors")
local ok, err = pcall(sha256.hex, nil)
check("nil input is refused", not ok and tostring(err):find("expected a string", 1, true),
  tostring(err))

print("")
print(string.format("%d passed, %d failed", pass, fail))
assert(fail == 0, string.format("%d tests failed", fail))
