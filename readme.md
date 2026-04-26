# ARM-GCC-Toolchain

This repository provides a **source-based, version-flexible** environment for building the [Arm GNU Toolchain](https://developer.arm.com/tools-and-software/gnu-toolchain) with the same build scripts Arm publishes for that purpose — without relying on Arm’s monolithic source blob.

The goal is to build **other GCC/Binutils releases** as well (not only the snapshots bundled by Arm), while still using the official Arm build and test scripts from [`gnu-devtools-for-arm`](https://git.gitlab.arm.com/tooling/gnu-devtools-for-arm). Related Arm projects are also documented under [gnu-toolchains-for-arm](https://gitlab.arm.com/tooling/gnu-toolchains-for-arm).

## Background

Arm ships GNU Toolchain releases as prebuilt binaries and as a **complete source tarball**. That tarball contains the underlying projects (GCC, Binutils, Newlib, and so on) as **frozen copies** of fixed revisions.

This repository takes a different approach:

| Arm source blob | This repository |
| --- | --- |
| Frozen copies of upstream projects | **Git submodules** pointing at the original repositories |
| Fixed release combination | Free choice of revisions/tags |
| Hard to customize | GCC, Binutils, and MPFR as **forks/mirrors** when needed |

Build orchestration still comes from Arm (`src/gnu-devtools-for-arm`). Components under `src/` are laid out as the Arm scripts expect (`./src/...` relative to the working directory).

### Submodules and forks

Most toolchain components are Git submodules under `src/` (see [`.gitmodules`](.gitmodules)):

| Path | Role |
| --- | --- |
| `src/gnu-devtools-for-arm` | Arm build / test scripts |
| `src/gcc` | **Fork** — local GCC changes ([Masmiseim36/gcc](https://github.com/Masmiseim36/gcc.git)) |
| `src/binutils-gdb` | **Fork** — local Binutils changes ([Masmiseim36/binutils-gdb](https://github.com/Masmiseim36/binutils-gdb.git)) |
| `src/binutils-gdb--gdb` | Upstream GDB tree (Sourceware) |
| `src/newlib-cygwin` | Newlib |
| `src/glibc` | Glibc (Linux targets) |
| `src/linux` | Linux kernel headers |
| `src/qemu` | QEMU (optional testing) |
| `src/isl` | ISL |
| `src/mpfr` | **Fork** of MPFR ([Masmiseim36/mpfr](https://github.com/Masmiseim36/mpfr.git)) — mirror used because the upstream server had severe performance / reliability problems |
| `src/libexpat` | Expat (GDB) |
| `src/zstd` | Zstd |

Additional host libraries expected by the Arm scripts (for example GMP, MPC, libiconv) also live under `src/` when present; they are discovered during the build.

## Rowley / CrossWorks branches

Branches whose names start with the **`rowley/`** prefix (for example `rowley/arm-15.3.rel1`, `rowley/arm-13.3.rel1`) carry the **Rowley Associates patches** for building GCC/Binutils variants that match [CrossWorks for ARM](https://www.rowley.co.uk/arm/).

Rowley publishes the corresponding GNU sources and patch files on their open-source page:

- [CrossWorks for ARM — GNU Source Code](https://www.rowley.co.uk/crossworks/open_source_code.htm#CrossWorks%20for%20ARM%20-%20GNU%20Source%20Code)

For each CrossWorks release they list Arm GNU Toolchain source tarballs plus patches such as `gcc-arm-15.3.rel1.patch` and `binutils-arm-15.3.rel1.patch`. The `rowley/*` branches in this repository apply those changes (in the GCC/Binutils forks under `src/`) so you can rebuild a toolchain suitable for CrossWorks instead of a stock Arm GNU Toolchain.

Example:

```bash
git checkout rowley/arm-15.3.rel1
git submodule update --init --recursive
./prepare.sh
./build.sh
```

CrossWorks itself ships pre-built GCC binaries; you only need this build path if you want a custom or newer GCC drop-in for the IDE.

### Files CrossWorks expects (vs. build output)

A stock CrossWorks install keeps a small, flat tool set under:

`<CrossWorks install>/gcc/arm-none-eabi/bin/`

That `bin` directory contains the same tool set on both hosts (Windows adds a `.exe` suffix):

| CrossWorks `bin/` | Role |
| --------------------------------------------------------------- | --- |
| `ar`, `as`, `ld`, `nm`, `objcopy`, `objdump`, `ranlib`, `strip` | Binutils (short names) |
| `arm-none-eabi-addr2line`, `arm-none-eabi-size`                 | Binutils (prefixed) |
| `cc1`, `cc1plus`, `lto1`                                        | GCC middle-end (normally under `libexec` in a full toolchain) |

After a successful build in this repo, map those names as follows.

**Windows / CrossWorks** ← MinGW install `build-mingw-arm-none-eabi/install/`:
**Linux / CrossWorks** ← Linux-hosted install `build-arm-none-eabi/install/`:

| CrossWorks name           | Generated Location |
| ------------------------- | ------------------ |
| `ar`                      | `bin/arm-none-eabi-ar` |
| `as`                      | `bin/arm-none-eabi-as` |
| `ld`                      | `bin/arm-none-eabi-ld` |
| `nm`                      | `bin/arm-none-eabi-nm` |
| `objcopy`                 | `bin/arm-none-eabi-objcopy` |
| `objdump`                 | `bin/arm-none-eabi-objdump` |
| `ranlib`                  | `bin/arm-none-eabi-ranlib` |
| `strip`                   | `bin/arm-none-eabi-strip` |
| `arm-none-eabi-addr2line` | `bin/arm-none-eabi-addr2line` |
| `arm-none-eabi-size`      | `bin/arm-none-eabi-size` |
| `cc1`                     | `libexec/gcc/arm-none-eabi/<gcc-version>/cc1` |
| `cc1plus`                 | `libexec/gcc/arm-none-eabi/<gcc-version>/cc1plus` |
| `lto1`                    | `libexec/gcc/arm-none-eabi/<gcc-version>/lto1` |

Notes:

- Replace Windows CrossWorks tools from **`build-mingw-arm-none-eabi/`**; replace Linux CrossWorks tools from **`build-arm-none-eabi/`**.
- CrossWorks uses **unprefixed** names for most Binutils tools and places `cc1` / `cc1plus` / `lto1` next to them in `bin/`. A full GNU install keeps the `arm-none-eabi-` prefix in `bin/` and the compilers under `libexec/gcc/arm-none-eabi/<version>/`. Copy or symlink/rename accordingly when updating an existing CrossWorks `gcc/arm-none-eabi/bin` folder.
- Each host install also contains drivers (`arm-none-eabi-gcc`, `g++`, …), GDB, libraries under `arm-none-eabi/`, and docs under `share/` — CrossWorks’ stock `bin` folder is only the subset above.

## Prerequisites

- A Linux host or **WSL2** (Ubuntu recommended; Manjaro is supported by `prepare.sh`)
- Prefer building on a **native Linux filesystem** (not under `/mnt/c/...` — builds there are slow and fragile due to CRLF/`PATH` issues)
- For Windows-hosted toolchains: MinGW-w64 with the **POSIX** thread model. `build.sh` selects this automatically: on Debian/Ubuntu it overlays the `*-posix` alternatives (the default `*-win32` ones break the MinGW GDB build), on Arch/Manjaro it uses `x86_64-w64-mingw32-gcc`, which already uses POSIX threads.

## Quick start

```bash
# Clone the repository including submodules
git clone --recurse-submodules <url-of-this-repo>
cd ARM-GCC-Toolchain

# If submodules are still missing:
git submodule update --init --recursive

# Host libraries that are not submodules (gmp, mpc — and libiconv for the
# Windows/MinGW host). Skip whatever is already present under src/.
(cd src/gcc && ./contrib/download_prerequisites --force --directory=..)
(cd src && wget https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz && tar -xf libiconv-1.17.tar.gz)

# Install dependencies
./prepare.sh

# Build arm-none-eabi for Linux x64 and Windows x64 (MinGW)
# Prefer a copy under $HOME on WSL (not /mnt/c/...)
./build.sh
```

If Automake versions conflict, you may need:

```bash
sudo ln -s /usr/bin/aclocal-1.16 /usr/bin/aclocal-1.14
sudo ln -s /usr/bin/automake-1.16 /usr/bin/automake-1.14
```

## Scripts

### `prepare.sh`

Sets up the build environment:

1. Installs required packages (Debian/Ubuntu via `apt`, Arch/Manjaro via `pacman`, optional AUR packages via `yay`/`paru`)
2. Detects the distribution from `/etc/os-release` (`ID` / `ID_LIKE`), so derivatives such as Linux Mint work and no `lsb-release` package is needed
3. Installs the whole list in one transaction and falls back to package-by-package on failure, so a single package name that no longer exists in the current release does not abort the run
4. Does **not** chmod the source trees: executable bits are stored in git (`100755`)
5. Does **not** fetch sources — use `git submodule update --init --recursive` plus, for the non-submodule host libraries, `src/gcc/contrib/download_prerequisites --force --directory=..`

```bash
./prepare.sh
```

### `build.sh`

Builds the **arm-none-eabi** toolchain following the Arm instructions in `src/gnu-devtools-for-arm/README.md`:

1. **Linux x64** host → output under `build-arm-none-eabi/`
2. **Windows x64** (MinGW `x86_64-w64-mingw32`, POSIX threads) → `build-mingw-arm-none-eabi/`  
   (requires a successful Linux build under `build-arm-none-eabi/install`; includes Newlib integration)

Behaviour worth knowing:

- Preconditions are checked up front: the Arm driver scripts (incl. their executable bit), a host GCC (warning below version 9), and the source components under `src/`. Component directories may carry a version suffix (`src/gmp-6.3.0`), as produced by `download_prerequisites`. `src/libiconv` is required for MinGW builds — without it the Arm script aborts mid-build
- Under WSL, `PATH` is sanitized (no `/mnt/...` / Windows `git.exe`)
- MinGW builds use the **POSIX** MinGW compilers: a temporary PATH overlay for the Debian/Ubuntu `*-posix` alternatives, or the default compiler when it already uses POSIX threads (Arch/Manjaro)
- Before Linux/MinGW host-tool stages **and before the Newlib pass**, in-tree `src/zstd/lib` artifacts are cleaned (Arm builds zstd in-source; the Newlib pass bootstraps a native toolchain, so a leftover MinGW archive would break it — and leftover Linux archives break `mingw-ar`)
- The Newlib pass runs only for stages that actually build the toolchain (`start`, `clean`, `gcc1`, `gcc2`, `gcc2-nano`, `newlib`, `newlib-nano`). `build-newlib-for-mingw-toolchain.sh` has no stage interface, so `./build.sh check` no longer triggers a full extra toolchain build
- Host executables are **stripped** after the build, for both hosts (`strip --strip-unneeded`, `x86_64-w64-mingw32-strip` for the Windows tree). Arm's scripts only strip the *target* libraries, so without this `cc1`, `ld`, `as`, `gdb` etc. keep debug sections and the symbol table (about 25 % of their size). Only `bin/`, `libexec/` and `arm-none-eabi/bin/` are touched, never the ARM libraries. Arm creates the `--package` tarball before this step, so `build.sh` recreates `bin-tar/arm-none-eabi-tools.tar.xz` from the stripped tree (for the MinGW host that also adds the files from the separate Newlib pass). `--no-strip` and `--debug` skip all of this
- **Linker defaults:** since 2.39 GNU ld warns about input objects without `.note.GNU-stack` ("implies executable stack") and about `LOAD` segments with RWX permissions. Both fire for ordinary bare-metal links, so `build.sh` configures Binutils with `--disable-warn-execstack --disable-warn-rwx-segments` (the same defaults the CrossWorks `ld`, also 2.45.1, reports in `--help`). `--ld-warnings` keeps the stock defaults. The switches can still be set per link with `--warn-execstack` / `--warn-rwx-segments`
- **Version label:** `build.sh` passes `--tag` (default `ARM-GCC-Toolchain-<git describe>`, override with `--tag NAME`, one word). Without it Arm's `determine_version` only reads the git hash when `<src>/.git` is a *directory*; for a submodule it is a file and the label degrades to the directory name minus its first dash-part, which gave `GNU ld (gdb)` for `src/binutils-gdb`. Do not reuse Arm's own release tags
- Both settings are applied at **configure** time. Arm's `do_config` skips configure when `obj/<component>/Makefile` exists, so an existing tree must be rebuilt (e.g. remove `obj/binutils`, or use a fresh build dir) before they take effect
- `--no-package` passes Arm's `--no-package` after `--release --package`, so no `bin-tar/*.tar.xz` is created. Arm's `perms` stage (removal of debug sections from the ARM target libraries, plus a `chmod`) only runs together with the tarball, so `build.sh` performs that step itself afterwards (Linux tree, and the Windows tree including the Newlib files from the separate pass). Not applied with `--quick`, which never packages or strips target libraries
- `--quick` builds into `quick-<arch>/` instead of the release trees: Arm's `do_config` skips configure when `obj/<component>/Makefile` exists, so sharing a build dir would silently reuse the release configuration (and vice versa)
- Before MinGW `gcc2`, `build.sh` forces a clean `obj/gcc2` when needed: Arm’s `do_config` skips configure if `Makefile` exists, so a broken `auto-host.h` (missing `SIZEOF_INT`) would otherwise persist across `./build.sh` / `--windows-only` retries
- MinGW **host** tools are linked fully statically, so the `.exe` files are standalone (no `libwinpthread-1.dll`, `libgcc_s_seh-1.dll` or `libstdc++-6.dll` next to them). This is done with `LDFLAGS=-static` via `--config-flags-host-tools`, which reaches the MinGW-hosted components only — `gcc1` is still a native Linux build in the Canadian cross, and `LDFLAGS_FOR_BUILD` does not inherit `LDFLAGS` when `build != host`.
  `-static-libgcc -static-libstdc++` alone is **not** enough (static libstdc++ still pulls pthread symbols out of the winpthread *import* library), and `-Wl,-Bstatic,-lpthread,-lwinpthread,-Bdynamic` in `CFLAGS` does not help either: `CFLAGS` land before the objects on the link line, so nothing is resolved there, and the trailing `-Bdynamic` switches the linker back to dynamic mode
- **Binutils** (`ld.exe`, `as.exe`, `objdump.exe`, …) gets `LDFLAGS=-Wl,-static` instead, via `--config-flags-binutils` (it is appended after the host-tools flags, so it wins for that configure only). Binutils programs are linked through libtool, which silently drops a plain `-static`; the result still imports `libwinpthread-1.dll`. `-Wl,-static` is handed to the linker unchanged. Binutils is C only, so the driver-level libgcc/libstdc++ handling that needs `-static` for GCC/GDB is irrelevant there
- After the MinGW build, `build.sh` runs `x86_64-w64-mingw32-objdump -p` over the installed `.exe`/`.dll` files and warns if anything imports a non-system DLL
- CRLF rewriting covers the few driver scripts in `src/gnu-devtools-for-arm` **always** (they are executed directly, and the parent [`.gitattributes`](.gitattributes) does not reach into a submodule), the large host-library trees **only** on a Windows mount (`/mnt/...`)
- If `build.sh` aborts, an `ERR` trap reports the failing line and command on the console and appends it to `build.log`, so a crash cannot disappear silently between `tee` and the shell exiting

All console output (this script and every invoked tool) is also written to **`build.log`**.

```bash
./build.sh                  # Linux and Windows hosts
./build.sh --linux-only     # Linux host only
./build.sh --windows-only   # MinGW only (needs a Linux build)
./build.sh --quick --linux-only   # faster smoke test (single multilib, quick-<arch>/)
./build.sh --debug          # pass debug options through to the Arm scripts (implies --no-strip)
./build.sh --no-strip       # keep debug info and symbols in the host executables
./build.sh --no-package     # no .tar.xz; target libraries are still stripped by build.sh
./build.sh --help
```

An optional final argument selects an Arm build stage (default: `start`).

### `ensure-executables.sh`

Optional repair tool if a checkout lost executable bits (for example `core.filemode=false` on Windows). **Not** invoked by `prepare.sh` or `build.sh` in the normal path — keep `100755` in git instead. To repair a tree:

```bash
source ./ensure-executables.sh
ensure_build_executables "$PWD"
```

### Arm scripts under `src/gnu-devtools-for-arm/`

The actual toolchain build is performed by Arm’s scripts, mainly:

- `build-gnu-toolchain.sh` — entry point / wrapper
- `build-baremetal-toolchain.sh` — bare-metal targets (e.g. `arm-none-eabi`)
- `build-cross-linux-toolchain.sh` — Linux targets
- `build-newlib-for-mingw-toolchain.sh` — Newlib for MinGW hosts

Details, supported targets, and testing: [`src/gnu-devtools-for-arm/README.md`](src/gnu-devtools-for-arm/README.md).

## Expected layout

```text
.
├── prepare.sh
├── build.sh
├── ensure-executables.sh
├── build.log                 # after a build run
├── build-arm-none-eabi/      # Linux-hosted toolchain
├── build-mingw-arm-none-eabi/
├── build-newlib-arm-none-eabi/   # Newlib bootstrap pass for the MinGW host
├── quick-<arch>/             # --quick builds only
└── src/
    ├── gnu-devtools-for-arm/   # submodule
    ├── gcc/                    # fork (submodule)
    ├── binutils-gdb/           # fork (submodule)
    ├── binutils-gdb--gdb/      # submodule
    ├── newlib-cygwin/          # submodule
    ├── glibc/                  # submodule
    ├── linux/                  # submodule
    ├── qemu/                   # submodule (optional testing)
    ├── isl/ mpfr/ libexpat/ zstd/   # submodules (mpfr = fork/mirror)
    └── gmp/ mpc/ …             # other host libs as needed
```

## Line endings and executable bits (Windows / WSL)

- [`.gitattributes`](.gitattributes) forces **LF** on checkout for:
  - shell scripts (`*.sh`, …)
  - Autoconf/Automake/Libtool helpers without a `.sh` suffix (`configure`, `install-sh`, `config.guess`, `config.sub`, …)
  - related inputs (`*.m4`, `*.ac`, `*.am`, `*.in`, …)
- After changing `.gitattributes`, renormalize an existing tree if needed:  
  `git add --renormalize .` (then commit), or re-clone
- Executable bits for build helpers are stored in git as **`100755`**; avoid wholesale `chmod` of `src/`
- `build.sh` strips CR from the `src/gnu-devtools-for-arm` driver scripts on every run, and from the host-library trees only for `/mnt/...` checkouts (safety net). Prefer building under `$HOME` in WSL so the latter path is unused

Build outputs (`build-*/`, `build.log`) are listed in [`.gitignore`](.gitignore).

## Further links

- [Arm GNU Toolchain](https://developer.arm.com/tools-and-software/gnu-toolchain)
- [gnu-toolchains-for-arm (GitLab)](https://gitlab.arm.com/tooling/gnu-toolchains-for-arm)
- [gnu-devtools-for-arm](https://git.gitlab.arm.com/tooling/gnu-devtools-for-arm) (build scripts, vendored here as a submodule)
- Official release downloads / source snapshots: [Arm GNU Toolchain Downloads](https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads)
- [Rowley CrossWorks for ARM — open source / GNU patches](https://www.rowley.co.uk/crossworks/open_source_code.htm#CrossWorks%20for%20ARM%20-%20GNU%20Source%20Code)
