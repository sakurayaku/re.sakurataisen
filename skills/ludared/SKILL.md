---
name: ludared
description: Work with Ludared, the asset decoding and rebuilding CLI, in projects containing ludared.toml or a .ludared manifest. Use for virtual paths, decode trees, artifacts, cache, workspace overrides, source rebuilding, and Ludared CLI commands.
---

# Using Ludared

Ludared decodes ROMs, ISOs, and archives into a tree of named artifacts, allows selected artifacts to be edited, and rebuilds the original container. Before implementing an extractor, inspect existing codecs with `ludared codecs list` and `ludared codecs detect <file>`; prefer existing codecs and tracked decode nodes to ad hoc extraction.

## Project layout

`ludared.toml` is configuration; the separate `<name>.ludared` manifest contains **JSON** describing sources, decode nodes, and overrides.

```toml
[project]
name = "mygame"
manifest = "mygame.ludared"

[paths]
sources = "sources"
workspace = "workspace"
scripts = "scripts"
builds = "builds"
cache = "builds/cache"
```

Run commands from the project root. Paths including `builds` and `cache` are resolved against the current working directory; do not assume a different CWD is harmless.

## Virtual paths and decode tree

Virtual paths are relative `/`-separated names beginning with a source, for example:

```text
mygame.sfc
mygame.sfc/rom_bank_00.bin
mygame.sfc/rom_bank_00.bin/TITLE.txt
```

The depth-one name is a source whose bytes reside under `sources/`; deeper paths identify decoded artifacts. Intermediate path components can also serve as implicit tree parents. Leading/trailing `/`, empty components, `.` and `..` components, and backslashes are invalid.

**Each decode operation applies one codec to one input artifact and creates exactly one decode node with an ordered list of zero or more outputs.** A codec must not create additional decode nodes, modify artifacts outside its returned outputs, or alter the manifest. Declare further decoding explicitly as separate nodes. Filesystem writes are not tracked outputs.

```text
mygame.sfc
└── rom_banks               (decode node)
    ├── rom_bank_00.bin     (artifact)
    │   └── TITLE.txt       (artifact from another decode)
    └── rom_bank_01.bin     (artifact)
```

The ordered outputs of `decode` become the ordered inputs of `encode`. Preserve both their names and positions: Ludared does not sort or regroup them. Artifacts with no further decodes are *terminal*; only terminal artifacts may be overridden. `ludared artifacts list [PATH] [--tree]` reads manifest declarations even if the cache is empty.

## Codec kinds

| Kind | Meaning | `encode` receives |
|---|---|---|
| `Rebuild` | Reconstructs the whole parent from outputs | Empty original buffer |
| `Patch` | Modifies an existing parent, preserving untouched bytes | Current parent buffer |

Think of `Rebuild` as reconstructing a ZIP archive from its extracted files, and `Patch` as applying modifications to an existing stream, similarly to an IPS patch.

One artifact may have **one Rebuild or several Patches, never a mix**. Successive patches on the same node are applied in manifest order, with later changes taking precedence. **There is no guaranteed execution order between independent branches.** Codecs must not rely on workspace writes or other mutations by a different codec during the same operation. Project-specific Lua codecs may read stable workspace resources; see `ludared-lua`.

## Where bytes live

| Location | Contents | Owner |
|---|---|---|
| `sources/` | Original source files | User |
| `<cache>/decodes/` | Canonical decoded artifacts, content-addressed | `unpack`, `decode add` |
| `workspace/` | Editable copies of selected artifacts | `override add`, user edits |
| `builds/` | Rebuilt sources | `build` |
| Manifest | Recipe and override declarations | CLI |

The cache contains pristine decoded bytes and is **not** changed by overrides or builds. For the original decoded bytes of an edited artifact:

```sh
ludared cache cat mygame.sfc/rom_bank_00.bin/TITLE.txt
ludared cache path mygame.sfc/rom_bank_00.bin/TITLE.txt
```

`cache cat` emits canonical decoded bytes, **not** source bytes or workspace edits. `override refresh <vpath>` restores those canonical bytes into the workspace and **discards edits**.

## Commands

```text
ludared init [--name N] [--manifest P] [--sources D] [--workspace D]
             [--scripts D] [--builds D] [--cache D] [--non-interactive]
ludared sources add <FILE> | list [--status] | remove <FILE>
ludared codecs list [--tree] | info <CODEC> | detect <FILE>
ludared decode add <PATH> <CODEC> [ARGS] [--name NAME] [--force]
ludared decode remove <PATH> [NAME] [--clean]
ludared unpack
ludared artifacts list [PATH] [--tree]
ludared cache cat <PATH> | path <PATH>
ludared override list [PATH] [--tree]
ludared override add <PATH> [--force]
ludared override refresh <PATH>
ludared override remove <PATH> [--clean]
ludared build [SOURCE]
ludared doctor
ludared clean [--dry-run]
ludared completions [SHELL]
```

`<PATH>` is a virtual path. `<CODEC>` is a registered codec ID. `[ARGS]` is one opaque string passed verbatim to the codec; absent arguments and an empty string are different. Use `ludared <command> --help` to confirm syntax. `codecs list` and `codecs info` work outside projects for built-ins; inside a project they also show Lua codecs. `codecs detect` requires a project.

## Workflows

### Register and decode a source

```sh
# The source file must already be under sources/.
ludared sources add mygame.sfc
ludared codecs detect sources/mygame.sfc
ludared decode add mygame.sfc std/nintendo/snes/cart/lorom
ludared artifacts list --tree
```

`decode add` runs the codec immediately, writes canonical artifacts to the cache, and records the decode in the manifest. When targeting a source, it checks the registered SHA-256. It refuses `can_handle = No` unless `--force` is specified.

### Decode an existing artifact

```sh
ludared unpack
ludared decode add mygame.sfc/rom_bank_00.bin std/generic/extract \
  '{"name":"TITLE.txt","offset":385,"length":37}'
```

The target artifact must already be cached. Run `unpack` after a fresh clone or clean before adding deeper decodes. In the observed CLI version, missing cached input can trigger a `TODO: Missing file in Manifest` panic.

### Remove a decode

```sh
ludared decode remove mygame.sfc/rom_bank_00.bin
ludared decode remove mygame.sfc tail --clean
```

`<PATH>` is the artifact the decode is attached to. `NAME` is only optional when that artifact has a single decode; when several share it, name the one to remove. Only a terminal decode can be removed: a decode with child decodes is refused until those children are removed first. Any overrides declared by the removed decode are lifted; `--clean` also deletes their workspace files, exactly as `override remove --clean` does. The outputs of the removed decode are forgotten from the cache index. A content-addressed blob is deleted only after that updated index is persisted and only when no entry references it; a blob still shared with another virtual path stays on disk. Once the manifest is saved, cache-index persistence and physical cleanup are best-effort, so a failed index write or deletion can leave a stale cache entry or an orphaned blob or workspace file without undoing the removal.

### Edit and rebuild

```sh
ludared override add mygame.sfc/rom_bank_00.bin/TITLE.txt
# Edit workspace/mygame.sfc/rom_bank_00.bin/TITLE.txt
ludared build
ludared build mygame.sfc  # alternatively, one source
```

`override add` copies canonical bytes to the workspace and records the override. An existing workspace file is preserved without `--force`; `--force` overwrites it but cannot take over an already overridden artifact (use `override refresh`). Only terminal artifacts may be overridden; overridden artifacts cannot be decoded further.

During build, an output is resolved from (1) nested decodes, (2) its declared workspace override, or (3) the canonical cache. `build` writes to `builds/`, not to cache, workspace, or manifest.

### Inspect

```sh
ludared artifacts list --tree
ludared override list --tree
ludared cache cat <vpath>
ludared doctor
ludared clean --dry-run
```

## Invariants and pitfalls

- **Use the CLI to modify the manifest** where supported: source registration, `decode add`/`decode list`/`decode remove`, and override operations validate names, duplicates, and declarations. `decode list <PATH>` lists the decodes directly attached to a virtual artifact.
- **The manifest is JSON**, despite its `.ludared` extension.
- **SHA-256 checks** protect registered sources during source-level `decode add`, `unpack`, `build`, and `doctor`.
- **Only declared overrides matter.** An undeclared workspace file is ignored by `build`; `override remove` leaves its file unless `--clean` is used.
- **Cache misses are errors**, never implicit zero-filled artifacts. `unpack` recreates the canonical cache from sources and manifest without changing the manifest.
- **Output names** must be relative, unique within a decode, and non-overlapping (including ancestor/descendant conflicts) with outputs of other decodes on the same input.
- **Cache blobs are content-addressed**: different virtual paths with identical bytes may refer to the same blob. Blob paths do not encode virtual paths.
- **No ordering between independent branches.** Only explicitly ordered operations, such as successive patches on one node, have an ordering guarantee. Never rely on a codec writing files that another codec will read during the same build.

## Related skills

- Project-specific Lua codec implementation: `ludared-lua`.
- Native Rust codec development inside Ludared: `ludared-codec-authoring`.
