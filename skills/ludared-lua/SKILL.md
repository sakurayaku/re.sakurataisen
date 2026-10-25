---
name: ludared-lua
description: Implement, modify, review, debug, or test Lua codecs for Ludared projects. Use for Lua codec behavior, registration, decode/encode contracts, round-trip failures, builtin codec interop, and script-specific errors; not merely because a project contains Lua files.
---

# Developing Ludared Lua codecs

Use this skill for **codec development**, not ordinary work on a Ludared project. Read [references/lua-api.md](references/lua-api.md) for the Lua module contract, globals, builtin codec handles, and examples. When source code and documentation disagree, inspect the current Rust implementation and follow it.

Generate a skeleton with `ludared codecs create my_codec.lua` when appropriate. The generated path is relative to `paths.scripts`; check the current CLI for filename restrictions.

## Mental model and contracts

- One decode applies **one codec to one input** and records **one decode node with an ordered list of zero or more artifacts**. Codecs do not create other decode nodes or edit the manifest; additional steps are declared separately.
- Return **ordered arrays** of `{ name = ..., data = ... }` records, never maps keyed by artifact name. This is also the representation exchanged with builtin Rust codecs exposed through `LUDARED.codec(id)`.
- Output names are relative artifact paths: no leading `/`, `..`, duplicate names, or ancestor/descendant conflicts within one decode.
- Treat the workspace and project files as **read-only** during Ludared operations. Codecs return generated artifacts rather than writing them to disk. Lua is **not sandboxed**; this is a project contract, not a security boundary.
- `kind = "rebuild"`: `encode` constructs the full parent from artifacts; `original` is empty. `kind = "patch"`: `encode` receives current parent bytes and applies targeted changes. Do not mix patch and rebuild on the same node. Successive patches on a node follow their declared order; independent branches have no guaranteed execution order.
- An unchanged decode/encode round-trip should reproduce the original bytes for supported inputs. Validate artifact count, names, order, sizes, and internal consistency; workspace overrides may change them.
- Codec `args` are opaque strings (or `nil`) supplied by Ludared to relevant callbacks. The codec defines their syntax; do not assume JSON or key/value formatting.
- Codecs may read project-specific lookup tables or other stable resources using `LUDARED.WORKSPACE` and `LUDARED.SCRIPTS`. These may be untracked dependencies; document them. Prefer pristine reference data to potentially absent workspace overrides during decode.
- Do not rely on persistent Lua state across detection, decode, and encode. Discovery loads modules eagerly; avoid initialization side effects.

## Confidence semantics

`can_handle(data)` returns one lowercase string:

- `"no"`: "I cannot decode that data meaningfully, no way."
- `"possible"`: "I may extract something out of that data, maybe garbage, maybe gold."
- `"likely"`: "All signs point to yes, but false positives are possible."
- `"certain"`: "I know that data, I know that format, I'm in charge."

Detection must not mutate project state or produce artifacts. `ludared decode add` refuses `no` without `--force` and warns on `possible`; choose confidence based on evidence, not warning suppression.

## Discovery and layout

- Lua codec IDs identify script paths relative to the configured scripts root and include `.lua`. A module's `name` is display metadata, not its ID.
- **Check the current discovery implementation.** The planned shared `ScriptDiscovery` traverses `SCRIPTS` once, excludes `shared/` subtrees, classifies `tests/` subtrees as tests, and dispatches paths to language engines by extension. Do not assume this refactor is already shipped.
- Keep reusable helpers outside discoverable codec locations according to the current implementation. A malformed eagerly loaded codec can prevent project initialization.
- Ludared embeds **Lua 5.5** through **mlua**. Standard Lua 5.3+ binary features such as `string.pack`, `string.unpack`, and bitwise operators are available. Do not assume third-party modules are installed.
- `require` does not automatically search the scripts root. Use explicit paths or configure `package.path` when needed.

## Implementation workflow

1. **Inspect first.** Check `ludared codecs list`, `ludared codecs info <codec-id>`, nearby project codecs, and the Lua API reference. Prefer builtin codecs or existing cached artifacts over duplicate format implementations.
2. **Define the contract.** Choose `patch` or `rebuild`; define recognition, output names and ordering, reconstruction metadata, argument syntax, and round-trip expectations.
3. **Implement narrowly.** Validate bounds, lengths, offsets, arguments, and structural assumptions; provide useful errors. Avoid unrelated manifest or project changes.
4. **Preserve reconstruction information.** If required, emit metadata as an ordinary artifact. A sidecar is optional, not a mandated format or position.
5. **Test representative inputs.** Cover malformed and boundary cases, untouched round-trips, and intentional edits. Do not commit or redistribute commercial game data as fixtures.

## CLI validation

Run from the project directory, adapting paths and IDs:

```sh
ludared codecs list
ludared codecs info scripts/my_codec.lua
ludared unpack
ludared decode add <input-virtual-path> scripts/my_codec.lua
ludared artifacts list --tree
ludared cache cat <output-virtual-path>
ludared build <input-virtual-path>
```

`decode add` may require the input to be populated in the cache first. Compare untouched builds byte-for-byte against the original, then override an artifact and confirm the intended edit appears without changing unrelated bytes.

## API reference

Read [references/lua-api.md](references/lua-api.md) before implementing or modifying a codec. Treat the examples as interface demonstrations, not mandatory implementation patterns.
