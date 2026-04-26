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

## Prerequisites

- A Linux host or **WSL2** (Ubuntu recommended; Manjaro is supported by `prepare.sh`)
- Prefer building on a **native Linux filesystem** (not under `/mnt/c/...` — builds there are slow and fragile due to CRLF/`PATH` issues)
- For Windows-hosted toolchains: MinGW-w64 with the **POSIX** thread model (`x86_64-w64-mingw32-gcc-posix` / `g++-posix`). `build.sh` selects these automatically; the default Ubuntu `*-win32` alternatives break the MinGW GDB build.

## Quick start

```bash
# Clone the repository including submodules
git clone --recurse-submodules <url-of-this-repo>
cd ARM-GCC-Toolchain

# If submodules are still missing:
git submodule update --init --recursive

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

1. Installs required packages (Ubuntu via `apt`, Manjaro via `pacman`, optional AUR packages via `yay`/`paru`)
2. Does **not** chmod the source trees: executable bits are stored in git (`100755`)

```bash
./prepare.sh
```

### `build.sh`

Builds the **arm-none-eabi** toolchain following the Arm instructions in `src/gnu-devtools-for-arm/README.md`:

1. **Linux x64** host → output under `build-arm-none-eabi/`
2. **Windows x64** (MinGW `x86_64-w64-mingw32`, POSIX threads) → `build-mingw-arm-none-eabi/`  
   (requires a successful Linux build under `build-arm-none-eabi/install`; includes Newlib integration)

Behaviour worth knowing:

- Under WSL, `PATH` is sanitized (no `/mnt/...` / Windows `git.exe`)
- MinGW builds force the **POSIX** MinGW compilers via a temporary PATH overlay
- Before Linux/MinGW host-tool stages, in-tree `src/zstd/lib` artifacts are cleaned (Arm builds zstd in-source; leftover Linux archives break `mingw-ar`)
- CRLF rewriting runs **only** when the repo is on a Windows mount (`/mnt/...`); on a native Linux tree it is a no-op — prefer [`.gitattributes`](.gitattributes) for LF

All console output (this script and every invoked tool) is also written to **`build.log`**.

```bash
./build.sh                  # Linux and Windows hosts
./build.sh --linux-only     # Linux host only
./build.sh --windows-only   # MinGW only (needs a Linux build)
./build.sh --quick --linux-only   # faster smoke test (single multilib)
./build.sh --debug          # pass debug options through to the Arm scripts
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
- `build.sh` still has an optional CRLF strip for `/mnt/...` checkouts only (safety net). Prefer building under `$HOME` in WSL so that path is unused

Build outputs (`build-*/`, `build.log`) are listed in [`.gitignore`](.gitignore).

## Further links

- [Arm GNU Toolchain](https://developer.arm.com/tools-and-software/gnu-toolchain)
- [gnu-toolchains-for-arm (GitLab)](https://gitlab.arm.com/tooling/gnu-toolchains-for-arm)
- [gnu-devtools-for-arm](https://git.gitlab.arm.com/tooling/gnu-devtools-for-arm) (build scripts, vendored here as a submodule)
- Official release downloads / source snapshots: [Arm GNU Toolchain Downloads](https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads)
