#!/bin/bash
# Build arm-none-eabi toolchains for Linux x64 and Windows x64 (MinGW) hosts.
# Follows src/gnu-devtools-for-arm/README.md release / Mingw instructions.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# Prefer Linux tools under WSL. Windows git.exe in PATH emits CRLF and breaks
# configure/make (e.g. isl gitversion.h).
if grep -qi microsoft /proc/version 2>/dev/null; then
	PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '^/mnt/' | paste -sd: -)"
	export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin${PATH:+:$PATH}"
fi

TARGET="arm-none-eabi"
DEVTOOLS="$ROOT/src/gnu-devtools-for-arm"
BUILD_WRAPPER="$DEVTOOLS/build-gnu-toolchain.sh"
NEWLIB_MINGW="$DEVTOOLS/build-newlib-for-mingw-toolchain.sh"

LINUX_BUILDDIR="$ROOT/build-arm-none-eabi"
MINGW_BUILDDIR="$ROOT/build-mingw-arm-none-eabi"
MINGW_HOST="x86_64-w64-mingw32"

do_linux=1
do_windows=1
quick=0
debug_flags=()
stage="start"

usage() {
	cat <<EOF
Usage: $(basename "$0") [OPTIONS] [STAGE]

Build $TARGET binaries for:
  - Linux x64 host  -> $LINUX_BUILDDIR
  - Windows x64 host (MinGW) -> $MINGW_BUILDDIR

Options:
  --linux-only       Build only the Linux-hosted toolchain
  --windows-only     Build only the Windows/MinGW-hosted toolchain
                     (requires a completed Linux build under $LINUX_BUILDDIR)
  --quick            Faster smoke build: single multilib, no full release set
  --debug            Pass --debug --debug-target to the toolchain scripts
  -h, --help         Show this help

STAGE defaults to "start" (full rebuild from the beginning).
Any other stage name accepted by build-gnu-toolchain.sh may be passed
(e.g. gcc2) as the final argument.

Examples:
  ./build.sh
  ./build.sh --linux-only
  ./build.sh --quick --linux-only
  ./build.sh --windows-only
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--linux-only)
			do_linux=1
			do_windows=0
			;;
		--windows-only)
			do_linux=0
			do_windows=1
			;;
		--quick)
			quick=1
			;;
		--debug)
			debug_flags=(--debug --debug-target)
			;;
		-h|--help)
			usage
			exit 0
			;;
		--)
			shift
			break
			;;
		-*)
			echo "error: unknown option: $1" >&2
			usage >&2
			exit 1
			;;
		*)
			stage="$1"
			shift
			break
			;;
	esac
	shift
done

if [[ $# -gt 0 ]]; then
	echo "error: unexpected arguments: $*" >&2
	exit 1
fi

require_file() {
	if [[ ! -x $1 && ! -f $1 ]]; then
		echo "error: missing required file: $1" >&2
		exit 1
	fi
}

require_dir() {
	if [[ ! -d $1 ]]; then
		echo "error: missing required directory: $1" >&2
		exit 1
	fi
}

require_file "$BUILD_WRAPPER"
require_file "$NEWLIB_MINGW"
require_dir "$ROOT/src/gcc"
require_dir "$ROOT/src/binutils-gdb"
require_dir "$ROOT/src/newlib-cygwin"
require_dir "$ROOT/src/gmp"
require_dir "$ROOT/src/mpfr"
require_dir "$ROOT/src/mpc"
require_dir "$ROOT/src/isl"
require_dir "$ROOT/src/zstd"

# Sources checked out on Windows often have CRLF; strip so WSL/configure can run.
# Prefer building on a native Linux filesystem (~/...) for speed and reliability.
fix_script_newlines() {
	local d
	echo "Normalizing text file line endings for WSL..."

	# Host libraries: configure/m4 parse many text files (CRLF breaks GMP etc.)
	for d in gmp mpfr mpc isl zstd libexpat libiconv; do
		[[ -d $ROOT/src/$d ]] || continue
		find "$ROOT/src/$d" \( -path '*/.git/*' -o -path '*/.git' \) -prune -o \
			-type f \( \
				-name '*.sh' -o -name '*.sub' -o -name '*.guess' \
				-o -name '*.c' -o -name '*.h' -o -name '*.cc' -o -name '*.cpp' \
				-o -name '*.S' -o -name '*.s' -o -name '*.asm' -o -name '*.m4' \
				-o -name '*.ac' -o -name '*.am' -o -name '*.in' -o -name '*.txt' \
				-o -name '*.def' -o -name Makefile -o -name makefile \
				-o -name configure -o -name 'config.*' -o -name 'm4-*' \
				-o -name install-sh -o -name missing -o -name compile \
				-o -name depcomp -o -name ltmain.sh -o -name libtool \
				-o -name ar-lib -o -name test-driver -o -name ylwrap \
				-o -name move-if-change -o -name mkinstalldirs \
			\) -print0 2>/dev/null \
			| xargs -0 -r sed -i 's/\r$//'
		# Catch remaining shebang helpers (e.g. m4-ccas) without known extensions
		find "$ROOT/src/$d" \( -path '*/.git/*' -o -path '*/.git' \) -prune -o \
			-type f -print0 2>/dev/null \
			| xargs -0 -r grep -Zl '^#!' 2>/dev/null \
			| xargs -0 -r sed -i 's/\r$//'
	done

	# Large trees: only shell/autoconf helpers (C sources are fine with CRLF for gcc)
	for d in gnu-devtools-for-arm binutils-gdb binutils-gdb--gdb gcc newlib-cygwin; do
		[[ -d $ROOT/src/$d ]] || continue
		find "$ROOT/src/$d" \( -path '*/.git/*' -o -path '*/.git' \) -prune -o \
			-type f \( \
				-name '*.sh' -o -name '*.sub' -o -name '*.guess' \
				-o -name configure -o -name 'config.*' \
				-o -name install-sh -o -name missing -o -name compile \
				-o -name depcomp -o -name ltmain.sh -o -name libtool \
				-o -name ar-lib -o -name test-driver -o -name ylwrap \
				-o -name move-if-change -o -name mkinstalldirs \
			\) -print0 2>/dev/null \
			| xargs -0 -r sed -i 's/\r$//'
	done
}
fix_script_newlines

if [[ $ROOT == /mnt/* ]]; then
	echo "warning: repository is on a Windows mount ($ROOT)." >&2
	echo "         Toolchain builds are slow and fragile here; prefer a copy under \$HOME." >&2
fi

if [[ $do_windows -eq 1 ]]; then
	if ! command -v "${MINGW_HOST}-gcc" >/dev/null 2>&1; then
		echo "error: ${MINGW_HOST}-gcc not found in PATH (install mingw-w64)" >&2
		exit 1
	fi
fi

# Common top-level flags for arm-none-eabi (A- and RM-profile multilibs)
common_top=(--target="$TARGET" --aprofile --rmprofile "${debug_flags[@]}")

# Lower-level flags after "--" (release packaging etc.)
if [[ $quick -eq 1 ]]; then
	# README "quick iteration" style: one multilib, much faster under WSL
	common_top=(--target="$TARGET" --with-arch=armv8.1-m.main+mve.fp+fp.dp --disable-multilib "${debug_flags[@]}")
	linux_bottom=(--config-flags-gcc=--with-float=hard)
	mingw_bottom=(--config-flags-gcc=--with-float=hard)
	newlib_bottom=(--config-flags-gcc=--with-float=hard)
else
	# README release-mode invocation for x86_64 Linux host / arm-none-eabi
	linux_bottom=(--release --package --enable-newlib-nano --enable-gdb-with-python=yes)
	# Windows hosts: no gdb-with-python (portability note in README)
	mingw_bottom=(--release --package --enable-newlib-nano)
	newlib_bottom=(--enable-newlib-nano --config-flags-gcc=--with-multilib-list=aprofile,rmprofile)
fi

build_linux() {
	echo "=== Building Linux x64 host toolchain ($TARGET) ==="
	echo "Build dir: $LINUX_BUILDDIR"
	bash "$BUILD_WRAPPER" \
		"${common_top[@]}" \
		-- \
		--builddir="$LINUX_BUILDDIR" \
		"${linux_bottom[@]}" \
		"$stage"
	echo "Linux toolchain installed at: $LINUX_BUILDDIR/install"
}

build_windows() {
	local host_tools="$LINUX_BUILDDIR/install/bin"
	if [[ ! -d $host_tools ]]; then
		echo "error: Linux toolchain not found at $host_tools" >&2
		echo "       Build the Linux host first (./build.sh --linux-only) or run without --windows-only." >&2
		exit 1
	fi

	mkdir -p "$MINGW_BUILDDIR"

	echo "=== Building Windows x64 (MinGW) host toolchain ($TARGET) ==="
	echo "Build dir: $MINGW_BUILDDIR"
	echo "Host toolchain: $host_tools"
	bash "$BUILD_WRAPPER" \
		"${common_top[@]}" \
		-- \
		--builddir="$MINGW_BUILDDIR" \
		"${mingw_bottom[@]}" \
		--host="$MINGW_HOST" \
		--host-toolchain-path="$host_tools" \
		"$stage"

	echo "=== Building Newlib for MinGW toolchain ==="
	bash "$NEWLIB_MINGW" \
		--target="$TARGET" \
		--builddir="$MINGW_BUILDDIR" \
		-- \
		"${newlib_bottom[@]}"

	echo "Windows toolchain installed at: $MINGW_BUILDDIR/install"
}

echo "Repository root: $ROOT"
echo "Target: $TARGET"
[[ $quick -eq 1 ]] && echo "Mode: quick (single multilib)"
[[ $quick -eq 0 ]] && echo "Mode: release (aprofile + rmprofile)"

if [[ $do_linux -eq 1 ]]; then
	build_linux
fi

if [[ $do_windows -eq 1 ]]; then
	build_windows
fi

echo "=== Done ==="
if [[ $do_linux -eq 1 ]]; then
	echo "Linux x64:   $LINUX_BUILDDIR/install/bin/${TARGET}-gcc"
fi
if [[ $do_windows -eq 1 ]]; then
	echo "Windows x64: $MINGW_BUILDDIR/install/bin/${TARGET}-gcc.exe"
fi
