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
| Hard to customize | GCC and Binutils as **forks** when extensions are needed |

Build orchestration still comes from Arm (`src/gnu-devtools-for-arm`). Components under `src/` are laid out as the Arm scripts expect (`./src/...` relative to the working directory).

### Submodules and forks

- **Upstream via submodule** (among others): Newlib, Glibc, Linux, QEMU, the GDB tree (`binutils-gdb--gdb`), `gnu-devtools-for-arm`
- **Forks** (for local changes):
  - [`src/gcc`](https://github.com/Masmiseim36/gcc.git)
  - [`src/binutils-gdb`](https://github.com/Masmiseim36/binutils-gdb.git)

Host libraries such as GMP, MPFR, MPC, ISL, Zstd, and similar also live under `src/` and are discovered by the Arm scripts during the build.

## Prerequisites

- A Linux host or **WSL2** (Ubuntu recommended; Manjaro is supported by `prepare.sh`)
- Prefer building on a **native Linux filesystem** (not under `/mnt/c/...` — builds there are slow and fragile due to CRLF/`PATH` issues)
- For Windows-hosted toolchains: MinGW (`x86_64-w64-mingw32-gcc`)

## Quick start

```bash
# Clone the repository including submodules
git clone --recurse-submodules <url-of-this-repo>
cd ARM-GCC-Toolchain

# If submodules are still missing:
git submodule update --init --recursive

# Install dependencies and mark build scripts executable
./prepare.sh

# Build arm-none-eabi for Linux x64 and Windows x64 (MinGW)
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
2. Calls `ensure-executables.sh` so only build-relevant scripts get the executable bit (no blanket `chmod -R` over entire source trees)

```bash
./prepare.sh
```

### `build.sh`

Builds the **arm-none-eabi** toolchain following the Arm instructions in `src/gnu-devtools-for-arm/README.md`:

1. **Linux x64** host → output under `build-arm-none-eabi/`
2. **Windows x64** (MinGW `x86_64-w64-mingw32`) → `build-mingw-arm-none-eabi/`  
   (requires a successful Linux build; includes Newlib integration)

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

Shared helper used by `prepare.sh` and `build.sh`. Marks build scripts and Autoconf/Make helpers executable (for example `build-*.sh`, `configure`, `install-sh`, shebang helpers under GMP/MPFR/…). Can also be used on its own:

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
    ├── gnu-devtools-for-arm/
    ├── gcc/
    ├── binutils-gdb/
    ├── binutils-gdb--gdb/
    ├── newlib-cygwin/
    ├── glibc/
    ├── linux/
    ├── gmp/ mpfr/ mpc/ isl/ zstd/ …
    └── qemu/                 # optional, for QEMU-based testing
```

## Line endings (Windows / WSL)

- `.gitattributes` forces **LF** for shell scripts on checkout
- `build.sh` also normalizes critical CRLF files and, under WSL, sanitizes `PATH` (no Windows `git.exe`) so configure/make do not fail on `^M`

## Further links

- [Arm GNU Toolchain](https://developer.arm.com/tools-and-software/gnu-toolchain)
- [gnu-toolchains-for-arm (GitLab)](https://gitlab.arm.com/tooling/gnu-toolchains-for-arm)
- [gnu-devtools-for-arm](https://git.gitlab.arm.com/tooling/gnu-devtools-for-arm) (build scripts, vendored here as a submodule)
- Official release downloads / source snapshots: [Arm GNU Toolchain Downloads](https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads)
