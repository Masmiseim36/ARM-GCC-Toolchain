#!/bin/bash
# Build arm-none-eabi toolchains for Linux x64 and Windows x64 (MinGW) hosts.
# Follows src/gnu-devtools-for-arm/README.md release / Mingw instructions.
# -E: propagate the ERR trap into functions, so an abort is never silent.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# Prefer Linux tools under WSL. Windows git.exe in PATH emits CRLF and breaks
# configure/make (e.g. isl gitversion.h).
if grep -qi microsoft /proc/version 2>/dev/null; then
	# "|| true": grep exits 1 if every entry was /mnt/..., which pipefail would
	# turn into a silent abort.
	PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '^/mnt/' | paste -sd: - || true)"
	export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin${PATH:+:$PATH}"
fi

TARGET="arm-none-eabi"
DEVTOOLS="$ROOT/src/gnu-devtools-for-arm"
BUILD_WRAPPER="$DEVTOOLS/build-gnu-toolchain.sh"
BAREMETAL="$DEVTOOLS/build-baremetal-toolchain.sh"
NEWLIB_MINGW="$DEVTOOLS/build-newlib-for-mingw-toolchain.sh"

LINUX_BUILDDIR="$ROOT/build-arm-none-eabi"
MINGW_BUILDDIR="$ROOT/build-mingw-arm-none-eabi"
MINGW_HOST="x86_64-w64-mingw32"
LOGFILE="$ROOT/build.log"

# Single multilib used by --quick (README "quick iteration" example).
QUICK_ARCH="armv8.1-m.main+mve.fp+fp.dp"

# Link the Windows-hosted binaries statically so they run without the MinGW
# runtime DLLs (libwinpthread-1.dll, libgcc_s_seh-1.dll, libstdc++-6.dll).
# This has to be LDFLAGS: "-Wl,-Bstatic -lwinpthread" in CFLAGS lands before the
# objects on the link line and resolves nothing. Passing it via
# --config-flags-host-tools reaches exactly the MinGW-hosted components
# (host libraries, Binutils, GDB, gcc2) and not the native gcc1 of the same
# Canadian cross; LDFLAGS_FOR_BUILD does not inherit LDFLAGS when
# build != host (see gcc/binutils configure), so build-side tools stay dynamic.
# Must stay a single shell word: the Arm scripts expand the flag unquoted.
MINGW_STATIC_LDFLAGS="-static"
# Binutils (ld, as, objdump, ...) is linked through libtool, which silently
# swallows a plain "-static" (only "-all-static" reaches the compiler), so those
# programs would still import libwinpthread-1.dll. "-Wl,-static" is passed on to
# the linker unchanged and has the same effect there (verified with
# objdump -p on every binutils/gas/ld/gprof program). Binutils is C only, so
# the driver-level libgcc/libstdc++ decisions that make "-static" necessary for
# GCC and GDB do not matter. It replaces LDFLAGS for the Binutils configure only
# (the Arm script appends --config-flags-binutils after the host-tools flags).
MINGW_BINUTILS_LDFLAGS="-Wl,-static"

do_linux=1
do_windows=1
quick=0
enable_log=1
do_strip=1
do_package=1
ld_warnings=0
tag=""
mingw_not_standalone=0
debug_flags=()
stage="start"

# A silent abort in a multi-hour build is painful to debug: report where we died.
# Bash runs the ERR trap even while errexit is off, so failures the script
# handles itself (the MinGW gcc2 retry) set expect_failure to stay quiet.
expect_failure=0
report_failure() {
	local rc="$1" line="$2" command="$3"
	[[ $expect_failure -eq 1 ]] && return 0
	echo "error: build.sh failed at line $line (exit $rc): $command" >&2
}
trap 'report_failure "$?" "$LINENO" "$BASH_COMMAND"' ERR

usage() {
	cat <<EOF
Usage: $(basename "$0") [OPTIONS] [STAGE]

Build $TARGET binaries for:
  - Linux x64 host  -> $LINUX_BUILDDIR
  - Windows x64 host (MinGW) -> $MINGW_BUILDDIR

By default all console output (this script and every invoked tool) is also
written to: $LOGFILE

Options:
  --linux-only       Build only the Linux-hosted toolchain
  --windows-only     Build only the Windows/MinGW-hosted toolchain
                     (requires a completed Linux build under $LINUX_BUILDDIR)
  --quick            Faster smoke build: single multilib ($QUICK_ARCH),
                     no full release set. Uses its own build trees under
                     quick-$QUICK_ARCH/
  --debug            Pass --debug --debug-target to the toolchain scripts
                     (implies --no-strip)
  --no-strip         Keep debug info and symbols in the host executables.
                     By default bin/, libexec/ and $TARGET/bin/ are stripped
                     after the build (Arm's scripts never do this) and the
                     --package tarball is recreated from the stripped tree
  --tag NAME         Version label shown in "ld --version", "gcc --version" etc.
                     as "GNU ld (NAME) 2.45...". One word, [A-Za-z0-9._+-].
                     Default: ARM-GCC-Toolchain-<git describe of this repo>.
                     Do not reuse Arm's own release tags.
  --ld-warnings      Keep GNU ld's stock defaults of warning about objects
                     without .note.GNU-stack and about RWX LOAD segments.
                     By default both warnings are off at build time, like in
                     other bare-metal ARM distributions: they fire for every
                     typical embedded link (flat memory map, assembler objects)
  --no-package       Do not create the bin-tar/*.tar.xz tarballs. Arm ties the
                     removal of debug sections from the target libraries to
                     packaging, so build.sh does that step itself instead
  --no-log           Do not write output to $LOGFILE (console only)
  -h, --help         Show this help

STAGE defaults to "start" (full rebuild from the beginning).
Any other stage name accepted by build-gnu-toolchain.sh may be passed
(e.g. gcc2) as the final argument.

Examples:
  ./build.sh
  ./build.sh --linux-only
  ./build.sh --quick --linux-only
  ./build.sh --windows-only
  ./build.sh --no-log --windows-only
EOF
}

# Mirror stdout/stderr to the console and to build.log for this process and children.
setup_logging() {
	: > "$LOGFILE"
	exec > >(tee -a "$LOGFILE") 2>&1
	echo "Logging to $LOGFILE (started $(date -Is))"
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
		--no-strip)
			do_strip=0
			;;
		--no-package)
			do_package=0
			;;
		--ld-warnings)
			ld_warnings=1
			;;
		--tag)
			if [[ $# -lt 2 ]]; then
				echo "error: --tag needs a value" >&2
				exit 1
			fi
			tag="$2"
			shift
			;;
		--tag=*)
			tag="${1#--tag=}"
			;;
		--no-log)
			enable_log=0
			;;
		-h|--help)
			usage
			exit 0
			;;
		--)
			shift
			if [[ $# -gt 0 ]]; then
				stage="$1"
				shift
			fi
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

# A debug build is meant to be debugged: keep its symbols.
if ((${#debug_flags[@]} > 0)); then
	do_strip=0
fi

# The label ends up in every tool's --version ("GNU ld (<tag>) ..."). Without
# --tag Arm's scripts derive it from the source directory; for a submodule (.git
# is a file there, not a directory) that degrades to the directory name with its
# first dash-part removed, i.e. "GNU ld (gdb)" for src/binutils-gdb.
# The Arm scripts expand it unquoted, so it has to stay a single word.
if [[ -z $tag ]]; then
	tag="ARM-GCC-Toolchain-$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null || echo unknown)"
	tag="${tag//[^A-Za-z0-9._+-]/_}"
fi
if [[ ! $tag =~ ^[A-Za-z0-9._+-]+$ ]]; then
	echo "error: --tag must be a single word of [A-Za-z0-9._+-], got: $tag" >&2
	exit 1
fi

if [[ $quick -eq 1 ]]; then
	# Keep quick (single-multilib) trees out of the release trees: Arm's
	# do_config() only runs configure when obj/<component>/Makefile is missing,
	# so a shared build dir would silently reuse the other mode's configuration.
	# build-newlib-for-mingw-toolchain.sh derives its own build dir from
	# $(dirname MINGW_BUILDDIR), hence nest both hosts in one subdirectory.
	QUICK_BUILDROOT="$ROOT/quick-$QUICK_ARCH"
	LINUX_BUILDDIR="$QUICK_BUILDROOT/build-arm-none-eabi"
	MINGW_BUILDDIR="$QUICK_BUILDROOT/build-mingw-arm-none-eabi"
fi

if [[ $enable_log -eq 1 ]]; then
	setup_logging
else
	echo "Logging to $LOGFILE disabled (--no-log)"
fi
require_file() {
	if [[ ! -f $1 ]]; then
		echo "error: missing required file: $1" >&2
		exit 1
	fi
}

# build-gnu-toolchain.sh runs the lower-level scripts directly (not via bash),
# so those need their executable bit. Git stores them as 100755; a checkout with
# core.filemode=false or a manually replaced file can lose it.
require_exec() {
	require_file "$1"
	if [[ ! -x $1 ]]; then
		echo "error: not executable: $1" >&2
		echo "       Run: chmod +x '$1'  (or use ensure-executables.sh)" >&2
		exit 1
	fi
}

# Arm's find_source_tree() accepts a version suffix too (e.g. src/gmp-6.3.0, as
# created by gcc/contrib/download_prerequisites), so accept the same names here.
require_component() {
	local name="$1"
	shift
	local d
	for d in "$ROOT/src/$name" "$ROOT/src/$name"[0-9.-]* "$@"; do
		[[ -d $d ]] && return 0
	done
	echo "error: missing required source component: src/$name (or src/$name-<version>)" >&2
	exit 1
}

# The Arm scripts and the README expect GCC 9 or later on the host.
require_host_gcc() {
	local version
	if ! command -v gcc >/dev/null 2>&1 || ! command -v g++ >/dev/null 2>&1; then
		echo "error: host gcc/g++ not found in PATH" >&2
		exit 1
	fi
	version="$(gcc -dumpversion 2>/dev/null || true)"
	version="${version%%.*}"
	if [[ $version =~ ^[0-9]+$ && $version -lt 9 ]]; then
		echo "warning: host gcc is version $version; the Arm README recommends GCC 9 or later." >&2
	fi
}

# The two drivers below are started via "bash", the baremetal script is executed
# directly by build-gnu-toolchain.sh and build-newlib-for-mingw-toolchain.sh.
require_file "$BUILD_WRAPPER"
require_file "$NEWLIB_MINGW"
require_exec "$BAREMETAL"
require_host_gcc

for component in binutils-gdb newlib-cygwin linux gmp mpfr mpc isl zstd libexpat; do
	require_component "$component"
done
# gcc may also be unpacked from Arm's source snapshot tarball.
require_component gcc "$ROOT"/src/arm-gnu-toolchain-src-snapshot*
# MinGW-hosted builds run the iconv stage and configure GCC with
# --with-libiconv-prefix; without src/libiconv the Arm script aborts mid-build
# with "libiconv_src: unbound variable".
if [[ $do_windows -eq 1 ]]; then
	require_component libiconv
fi

# Sources checked out on Windows often have CRLF; strip so bash/configure can run.
# The Arm driver scripts are always normalized (few files, and they are executed
# directly). For the host libraries this only happens on a Windows mount: on a
# native Linux filesystem (e.g. WSL $HOME) walking gcc/newlib with sed -i stalls
# the build and dirties submodules. Executable bits are expected from git
# (100755); do not call ensure-executables.sh here.
fix_script_newlines() {
	local d

	strip_cr_in_dir() {
		local dir="$1"
		local -a crlf=()
		[[ -d $dir ]] || return 0
		# Collect the matches instead of piping them straight into sed: "grep -l"
		# exits 1 when nothing matches and xargs turns that into 123, which would
		# abort the whole script via pipefail + set -e.
		mapfile -d '' -t crlf < <(
			find "$dir" \( -path '*/.git/*' -o -path '*/.git' \
					-o -path '*/testsuite/*' -o -path '*/tests/*' \) -prune -o \
				-type f \( \
					-name '*.sh' -o -name '*.sub' -o -name '*.guess' \
					-o -name '*.m4' -o -name '*.ac' -o -name '*.am' -o -name '*.in' \
					-o -name configure -o -name 'config.*' -o -name 'm4-*' \
					-o -name install-sh -o -name missing -o -name compile \
					-o -name depcomp -o -name ltmain.sh -o -name libtool \
					-o -name ar-lib -o -name test-driver -o -name ylwrap \
					-o -name move-if-change -o -name mkinstalldirs \
				\) -print0 2>/dev/null \
				| xargs -0 -r grep -Zl $'\r$' 2>/dev/null || true
		)
		((${#crlf[@]} > 0)) || return 0
		sed -i 's/\r$//' "${crlf[@]}"
		echo "  CRLF normalized in ${#crlf[@]} file(s) under ${dir#"$ROOT/"}"
	}

	# The Arm driver scripts are executed directly, and the parent .gitattributes
	# does not reach into the submodule: with core.autocrlf=true they end up as
	# CRLF and bash aborts with "syntax error near unexpected token $'\r'".
	# Normalize those few files always, also on a native Linux tree.
	strip_cr_in_dir "$ROOT/src/gnu-devtools-for-arm"

	if [[ $ROOT != /mnt/* ]]; then
		return 0
	fi
	echo "Normalizing CRLF on Windows mount (host libraries)..."
	for d in gmp mpfr mpc isl zstd libexpat libiconv ncurses; do
		strip_cr_in_dir "$ROOT/src/$d"
	done
}
fix_script_newlines

if [[ $ROOT == /mnt/* ]]; then
	echo "warning: repository is on a Windows mount ($ROOT)." >&2
	echo "         Toolchain builds are slow and fragile here; prefer a copy under \$HOME." >&2
fi

# GDB (and other C++ host tools) need MinGW with POSIX threads; a win32-threads
# compiler fails with "error: '__gthread_cond_t' does not name a type".
# Debian/Ubuntu ship *-posix and *-win32 variants and often default to win32,
# while Arch/Manjaro ship a single compiler that already uses POSIX threads.
mingw_thread_model() {
	local out
	out="$("$1" -v 2>&1)" || true
	[[ $out == *"Thread model: "* ]] || return 0
	out="${out##*Thread model: }"
	printf '%s\n' "${out%%$'\n'*}"
}

# Echo how POSIX-threaded MinGW compilers can be reached:
#   default - ${MINGW_HOST}-gcc/g++ already use POSIX threads
#   overlay - only the *-posix variants do, so a PATH overlay is needed
# Returns non-zero when neither is available.
mingw_posix_mode() {
	local gcc_bin gxx_bin
	gcc_bin="$(command -v "${MINGW_HOST}-gcc" 2>/dev/null || true)"
	gxx_bin="$(command -v "${MINGW_HOST}-g++" 2>/dev/null || true)"
	if [[ -n $gcc_bin && -n $gxx_bin ]] \
		&& [[ "$(mingw_thread_model "$gcc_bin")" == posix ]] \
		&& [[ "$(mingw_thread_model "$gxx_bin")" == posix ]]; then
		echo default
		return 0
	fi
	if command -v "${MINGW_HOST}-gcc-posix" >/dev/null 2>&1 \
		&& command -v "${MINGW_HOST}-g++-posix" >/dev/null 2>&1; then
		echo overlay
		return 0
	fi
	return 1
}

mingw_compiler_error() {
	echo "error: no MinGW C/C++ compiler with POSIX thread model found for ${MINGW_HOST}." >&2
	echo "       Debian/Ubuntu: install gcc-mingw-w64-x86-64-posix g++-mingw-w64-x86-64-posix" >&2
	echo "                      (or g++-mingw-w64-x86-64, which provides ${MINGW_HOST}-g++-posix)." >&2
	echo "       Arch/Manjaro:  install mingw-w64-gcc (already POSIX threads)." >&2
}

# Prefer *-posix compilers via a PATH overlay (no root / update-alternatives).
prefer_mingw_posix_compilers() {
	local mode overlay tool dst
	mode="$(mingw_posix_mode || true)"

	if [[ $mode == default ]]; then
		echo "MinGW host compilers: POSIX threads (system default)"
		echo "  CC=$(command -v "${MINGW_HOST}-gcc")"
		echo "  CXX=$(command -v "${MINGW_HOST}-g++")"
		return 0
	fi
	if [[ $mode != overlay ]]; then
		mingw_compiler_error
		exit 1
	fi

	overlay="$(mktemp -d "${TMPDIR:-/tmp}/mingw-posix-path.XXXXXX")"
	# shellcheck disable=SC2064
	trap "rm -rf '$overlay'" EXIT

	for tool in gcc g++ c++ cpp; do
		dst="$(command -v "${MINGW_HOST}-${tool}-posix" 2>/dev/null || true)"
		[[ -n $dst ]] || continue
		ln -sf "$dst" "$overlay/${MINGW_HOST}-${tool}"
	done
	# Keep matching binutils from the system PATH behind the overlay.
	export PATH="$overlay:$PATH"

	echo "MinGW host compilers: POSIX threads (*-posix overlay)"
	echo "  CC=$(command -v "${MINGW_HOST}-gcc")"
	echo "  CXX=$(command -v "${MINGW_HOST}-g++")"
	if [[ "$(mingw_thread_model "$(command -v "${MINGW_HOST}-g++")")" != posix ]]; then
		echo "error: ${MINGW_HOST}-g++ is not using Thread model: posix" >&2
		exit 1
	fi
}

if [[ $do_windows -eq 1 ]] && ! mingw_posix_mode >/dev/null; then
	mingw_compiler_error
	exit 1
fi

# Common top-level flags for arm-none-eabi (A- and RM-profile multilibs)
common_top=(--target="$TARGET" --aprofile --rmprofile "${debug_flags[@]}")

# Lower-level flags after "--" (release packaging etc.)
if [[ $quick -eq 1 ]]; then
	# README "quick iteration" style: one multilib, much faster under WSL
	common_top=(--target="$TARGET" --with-arch="$QUICK_ARCH" --disable-multilib "${debug_flags[@]}")
	linux_bottom=(--config-flags-gcc=--with-float=hard)
	mingw_bottom=(--config-flags-gcc=--with-float=hard)
	# build-newlib-for-mingw-toolchain.sh is called directly, so --with-arch /
	# --disable-multilib have to be passed as GCC configure flags here (only
	# build-gnu-toolchain.sh translates the top-level options). Without them
	# Newlib would be built for the full default multilib set and would not
	# match the single-multilib MinGW compiler.
	newlib_bottom=(
		--config-flags-gcc=--with-float=hard
		--config-flags-gcc=--with-arch="$QUICK_ARCH"
		--config-flags-gcc=--disable-multilib
	)
else
	# README release-mode invocation for x86_64 Linux host / arm-none-eabi
	linux_bottom=(--release --package --enable-newlib-nano --enable-gdb-with-python=yes)
	# Windows hosts: no gdb-with-python (portability note in README)
	mingw_bottom=(--release --package --enable-newlib-nano)
	newlib_bottom=(--enable-newlib-nano --config-flags-gcc=--with-multilib-list=aprofile,rmprofile)
fi

linux_bottom+=(--tag="$tag")
mingw_bottom+=(--tag="$tag")

# Linker defaults. Since 2.39 GNU ld warns about input objects without a
# .note.GNU-stack section ("implies executable stack") and about LOAD segments
# with RWX permissions. Both fire for ordinary bare-metal links (flat memory
# map, hand-written assembler files), and Rowley's CrossWorks ld, which has the
# same version, is configured with both off ("--no-warn-execstack ... (default)").
if [[ $ld_warnings -eq 0 ]]; then
	linux_bottom+=(--config-flags-binutils=--disable-warn-execstack
		--config-flags-binutils=--disable-warn-rwx-segments)
	mingw_bottom+=(--config-flags-binutils=--disable-warn-execstack
		--config-flags-binutils=--disable-warn-rwx-segments)
fi

# Arm's own --no-package: it comes last, so it overrides --release/--package above.
if [[ $do_package -eq 0 ]]; then
	linux_bottom+=(--no-package)
	mingw_bottom+=(--no-package)
fi

# Applies to both modes: the Windows binaries should be standalone.
mingw_bottom+=(
	--config-flags-host-tools=LDFLAGS="$MINGW_STATIC_LDFLAGS"
	--config-flags-binutils=LDFLAGS="$MINGW_BINUTILS_LDFLAGS"
)

# Arm's zstd stage builds inside src/zstd/lib (not per-host obj/). Linux and
# MinGW then share archives; mingw-ar cannot update a GNU/Linux or truncated
# archive ("malformed archive").
clean_intree_zstd() {
	local lib="$ROOT/src/zstd/lib"
	[[ -d $lib ]] || return 0
	echo "Cleaning in-tree zstd artifacts in $lib"
	make -C "$lib" clean >/dev/null 2>&1 || true
	rm -rf "$lib/obj"
	rm -f "$lib"/libzstd.a "$lib"/libzstd.dll "$lib"/libzstd.so "$lib"/libzstd.so.* \
		"$lib"/libzstd.dylib "$lib"/dll/libzstd.dll
}

# Verify the installed Windows binaries only import Windows system DLLs, i.e.
# that they run without a MinGW runtime next to them.
check_mingw_standalone() {
	local objdump binary dll
	local -a offenders=() binaries=()
	# Windows system DLLs that are always present on the target machine.
	local system_dlls='^(advapi32|api-ms-win-.*|bcrypt|comctl32|comdlg32|crypt32|dbghelp|gdi32|imm32|iphlpapi|kernel32|msvcrt|netapi32|ntdll|ole32|oleaut32|psapi|rpcrt4|secur32|setupapi|shell32|shlwapi|user32|userenv|usp10|uuid|version|winmm|winspool|ws2_32|wsock32)\.(dll|drv)$'

	objdump="$(command -v "${MINGW_HOST}-objdump" 2>/dev/null || true)"
	if [[ -z $objdump ]]; then
		echo "note: ${MINGW_HOST}-objdump not found; skipping DLL dependency check"
		return 0
	fi
	mapfile -d '' -t binaries < <(
		find "$MINGW_BUILDDIR/install" -type f \
			\( -name '*.exe' -o -name '*.dll' \) -print0 2>/dev/null
	)
	if ((${#binaries[@]} == 0)); then
		echo "note: no Windows binaries under $MINGW_BUILDDIR/install; skipping DLL check"
		return 0
	fi

	echo "Checking ${#binaries[@]} Windows binaries for non-system DLL dependencies..."
	for binary in "${binaries[@]}"; do
		while read -r dll; do
			[[ -n $dll ]] || continue
			if [[ ! ${dll,,} =~ $system_dlls ]]; then
				offenders+=("${binary#"$MINGW_BUILDDIR/install/"} -> $dll")
			fi
		done < <("$objdump" -p "$binary" 2>/dev/null | awk '/DLL Name:/ {print $3}')
	done

	if ((${#offenders[@]} > 0)); then
		mingw_not_standalone=1
		echo "warning: these Windows binaries are not standalone:" >&2
		printf '  %s\n' "${offenders[@]}" >&2
		echo "         Ship the listed DLLs alongside them, or check that" >&2
		echo "         LDFLAGS=$MINGW_STATIC_LDFLAGS reached the affected component." >&2
		return 1
	fi
	echo "All Windows binaries import Windows system DLLs only."
}

# Arm's do_config() only runs configure when $objdir/Makefile is missing.
# A failed MinGW gcc2 configure can leave Makefile + a broken auto-host.h
# (SIZEOF_INT / GATHER_STATISTICS as #undef). Retries then skip configure and
# fail again with "GATHER_STATISTICS must be defined" / cpplib SIZEOF errors.
# Works for ./build.sh, --windows-only, and explicit gcc2 stages.
mingw_gcc_autohost_ok() {
	local ah="$1/gcc/auto-host.h"
	[[ -f $ah ]] || return 1
	grep -qE '^#define SIZEOF_INT[[:space:]]+[0-9]+' "$ah" \
		&& grep -qE '^#define GATHER_STATISTICS[[:space:]]+' "$ah"
}

remove_mingw_gcc_objdir() {
	local d="$1"
	[[ -e $d ]] || return 0
	echo "Removing $d (force MinGW GCC reconfigure)"
	rm -rf "$d"
}

prepare_mingw_gcc_objdirs() {
	# $1 = "force"  → always wipe gcc2 trees
	# $1 = "check"  → wipe only when auto-host.h is missing/broken
	# default        → force for start/clean/gcc2/gcc2-nano, else check
	local mode="${1:-}"
	local gcc2="$MINGW_BUILDDIR/obj/gcc2"
	local gcc2_nano="$MINGW_BUILDDIR/obj/gcc2-nano"
	local force=0

	case "$mode" in
		force) force=1 ;;
		check) force=0 ;;
		*)
			case "$stage" in
				start|clean|gcc2|gcc2-nano) force=1 ;;
			esac
			;;
	esac

	if [[ $force -eq 1 ]]; then
		echo "Preparing MinGW GCC objects for stage '$stage' (force reconfigure)..."
		remove_mingw_gcc_objdir "$gcc2"
		remove_mingw_gcc_objdir "$gcc2_nano"
		return 0
	fi

	if [[ -d $gcc2 ]] && ! mingw_gcc_autohost_ok "$gcc2"; then
		echo "MinGW obj/gcc2 auto-host.h is missing or broken; forcing reconfigure."
		remove_mingw_gcc_objdir "$gcc2"
		remove_mingw_gcc_objdir "$gcc2_nano"
	elif [[ -d $gcc2_nano ]] && ! mingw_gcc_autohost_ok "$gcc2_nano"; then
		echo "MinGW obj/gcc2-nano auto-host.h is missing or broken; forcing reconfigure."
		remove_mingw_gcc_objdir "$gcc2_nano"
	fi
}

# Run Arm's top-level driver with args in an array so a missing '\' on a
# continued line cannot turn the stage name (start/gcc2/...) into a shell command.
run_toolchain_wrapper() {
	local -a args=("$@")
	bash "$BUILD_WRAPPER" "${args[@]}"
}

# Stages that actually (re)build the toolchain. build-newlib-for-mingw-toolchain.sh
# has no stage interface: it always runs a full "start-bootstrap-newlib" pass plus
# "install-newlib". Only do that for these stages - otherwise "./build.sh check"
# would kick off a complete extra toolchain build after the test run. The same
# condition decides whether the install tree is stripped.
stage_builds_toolchain() {
	case "$stage" in
	start | clean | gcc1 | gcc2 | gcc2-nano | newlib | newlib-nano) return 0 ;;
	*) return 1 ;;
	esac
}

# Strip debug info and symbols from the host executables of one install tree.
# Arm's scripts only strip the *target* libraries (strip_lib), never the host
# programs, so cc1/ld/as/gdb ship with debug sections and the COFF/ELF symbol
# table (~25% of the size, see the comparison with other distributions).
#
# Only bin/, libexec/ and $TARGET/bin/ are touched: the ARM libraries under
# lib/ and $TARGET/lib are target objects that the host strip must not see.
# $1 label, $2 install dir, $3 strip tool, $4 kind: "pe" (*.exe, *.dll) | "elf"
strip_host_binaries() {
	local label="$1" install="$2" strip_tool="$3" kind="$4"
	local dir f total_before total_after
	local -a files=() failed=() find_args=()

	if [[ $do_strip -eq 0 ]]; then
		echo "Stripping $label binaries skipped (--no-strip / --debug)"
		return 0
	fi
	if ! command -v "$strip_tool" >/dev/null 2>&1; then
		echo "warning: $strip_tool not found; $label binaries stay unstripped" >&2
		return 0
	fi
	[[ -d $install ]] || return 0

	if [[ $kind == pe ]]; then
		find_args=(-type f \( -name '*.exe' -o -name '*.dll' \))
	else
		find_args=(-type f)
	fi
	for dir in bin libexec "$TARGET/bin"; do
		[[ -d $install/$dir ]] || continue
		while IFS= read -r -d '' f; do
			# ELF: skip shell scripts (e.g. gdb-add-index) by magic number.
			if [[ $kind == elf && "$(head -c4 "$f" | od -An -tx1 | tr -d ' \n')" != 7f454c46 ]]; then
				continue
			fi
			files+=("$f")
		done < <(find "$install/$dir" "${find_args[@]}" -print0)
	done
	if ((${#files[@]} == 0)); then
		echo "note: no $label executables found under $install; nothing to strip"
		return 0
	fi

	total_before="$(stat -c %s "${files[@]}" | awk '{s += $1} END {print s + 0}')"
	for f in "${files[@]}"; do
		if ! "$strip_tool" --strip-unneeded "$f" 2>/dev/null; then
			failed+=("${f#"$install/"}")
		fi
	done
	total_after="$(stat -c %s "${files[@]}" | awk '{s += $1} END {print s + 0}')"

	echo "Stripped $((${#files[@]} - ${#failed[@]})) $label binaries:" \
		"$((total_before / 1048576)) MiB -> $((total_after / 1048576)) MiB"
	if ((${#failed[@]} > 0)); then
		echo "warning: could not strip: ${failed[*]}" >&2
	fi
	repack_tarball "$label" "$(dirname "$install")"
}

# Arm's "tar" stage runs before this script can strip anything, so a --package
# build leaves a tarball with the unstripped binaries. Recreate it from the
# stripped tree with the same tar options. For the MinGW host this also picks up
# the Newlib files rsync'ed in by the separate Newlib pass afterwards.
repack_tarball() {
	local label="$1" builddir="$2"
	local tarball="$builddir/bin-tar/$TARGET-tools.tar.xz"
	# With --no-package a leftover tarball from an earlier run is not ours to touch.
	[[ $do_package -eq 1 && -f $tarball ]] || return 0
	echo "Repacking $label tarball from the stripped tree (xz, this takes a while)..."
	rm -f "$tarball.t"
	tar -c -C "$builddir/install" -J -f "$tarball.t" --owner 0 --group 0 \
		--mode=a+u,og-w --exclude='*gccbug' .
	rm -f "$tarball"
	mv "$tarball.t" "$tarball"
	chmod 444 "$tarball"
	echo "  $tarball ($(($(stat -c %s "$tarball") / 1048576)) MiB)"
}

# Arm's "perms" stage (strip_lib in utilities.sh + chmod) only runs together with
# the tarball, i.e. with --package. With --no-package do the same here, otherwise
# every target library (libc.a, libgcc.a, ...) keeps its debug sections.
# Same section list and file selection as strip_lib; an ARM-aware objcopy is
# needed for both trees, so always use the one from the Linux toolchain.
# $1 label, $2 install dir
finish_target_libs() {
	local label="$1" install="$2"
	local objcopy="$LINUX_BUILDDIR/install/bin/$TARGET-objcopy"

	[[ $do_package -eq 0 && $quick -eq 0 ]] || return 0
	[[ -d $install ]] || return 0
	if [[ ! -x $objcopy ]]; then
		echo "warning: $objcopy not found; $label target libraries stay unstripped" >&2
		return 0
	fi

	echo "Removing debug sections from $label target libraries (replaces Arm's perms stage)..."
	find "$install" -type f \( -name '*.a' -o -name '*.o' \) ! -path '*dll*' -print0 |
		xargs -0 -r -n1 -P"$(nproc)" "$objcopy" \
			-R .comment -R .note -R .debug_info -R .debug_aranges -R .debug_pubnames \
			-R .debug_pubtypes -R .debug_abbrev -R .debug_line -R .debug_str \
			-R .debug_ranges -R .debug_loc -R .debug_rnglists -R .debug_loclists \
			2>/dev/null || true
	# user: read/write; group: read-only; others: read-only (as Arm's perms stage)
	# Cosmetic only, so never fail the build over it (e.g. on a Windows mount).
	chmod -R u+rw,go+r,go-w "$install" 2>/dev/null || true
	find "$install" -perm -0100 -print0 | xargs -0 -r chmod g+x 2>/dev/null || true
}

# If auto-host.h is broken, wipe and rebuild from gcc2 once.
# Returns 0 on healthy tree (or successful retry), 1 on failure.
retry_mingw_gcc2_if_autohost_broken() {
	local gcc2="$MINGW_BUILDDIR/obj/gcc2"
	local retry_stage="gcc2"
	if mingw_gcc_autohost_ok "$gcc2"; then
		return 0
	fi

	# Resuming at "gcc2" stops right after that stage, so a full run would lose
	# the remaining stages (gcc2-nano, perms, tar and hence --package).
	if [[ $stage == "start" ]]; then
		retry_stage="start"
	fi

	echo "warning: MinGW gcc2 auto-host.h broken; retrying from $retry_stage with forced reconfigure..." >&2
	remove_mingw_gcc_objdir "$gcc2"
	remove_mingw_gcc_objdir "$MINGW_BUILDDIR/obj/gcc2-nano"
	run_toolchain_wrapper \
		"${common_top[@]}" \
		-- \
		--builddir="$MINGW_BUILDDIR" \
		"${mingw_bottom[@]}" \
		--config-flags-host-tools=--build="$(gcc -dumpmachine)" \
		--host="$MINGW_HOST" \
		--host-toolchain-path="$LINUX_BUILDDIR/install/bin" \
		"$retry_stage"
	if mingw_gcc_autohost_ok "$gcc2"; then
		return 0
	fi
	echo "error: MinGW gcc2 auto-host.h still missing SIZEOF_INT / GATHER_STATISTICS after retry" >&2
	return 1
}

build_linux() {
	echo "=== Building Linux x64 host toolchain ($TARGET) ==="
	echo "Build dir: $LINUX_BUILDDIR"
	# Arm's mk_bin_dirs() only runs in the "start" stage, while every config step
	# appends to install/.build_flags. Resuming at e.g. "gcc2" in a fresh tree
	# would abort in utilities.sh with "No such file or directory".
	mkdir -p "$LINUX_BUILDDIR/install"
	clean_intree_zstd
	run_toolchain_wrapper \
		"${common_top[@]}" \
		-- \
		--builddir="$LINUX_BUILDDIR" \
		"${linux_bottom[@]}" \
		"$stage"
	if stage_builds_toolchain; then
		strip_host_binaries Linux "$LINUX_BUILDDIR/install" strip elf
		finish_target_libs Linux "$LINUX_BUILDDIR/install"
	fi
	echo "Linux toolchain installed at: $LINUX_BUILDDIR/install"
}

build_windows() {
	local host_tools="$LINUX_BUILDDIR/install/bin"
	local build_triple
	local mingw_rc
	local -a mingw_args

	if [[ ! -x $host_tools/$TARGET-gcc ]]; then
		echo "error: Linux toolchain not found at $host_tools/$TARGET-gcc" >&2
		echo "       Build the Linux host first (./build.sh --linux-only) or run without --windows-only." >&2
		exit 1
	fi

	mkdir -p "$MINGW_BUILDDIR/install"
	prefer_mingw_posix_compilers
	# zstd is compiled in-tree under src/zstd/lib. A leftover Linux (or
	# interrupted MinGW) libzstd.a makes x86_64-w64-mingw32-ar fail with
	# "malformed archive". Always start that tree clean for this host.
	clean_intree_zstd

	# When cross-compiling host tools to MinGW, GMP's configure often picks
	# x86_64-w64-mingw32-gcc as CC_FOR_BUILD (especially under WSL2 / wine-binfmt)
	# and then fails with: "Cannot determine executable suffix".
	# Force a native build triple and build compiler for host-tool configures.
	build_triple="$(gcc -dumpmachine)"
	export CC_FOR_BUILD="${CC_FOR_BUILD:-gcc}"
	export CXX_FOR_BUILD="${CXX_FOR_BUILD:-g++}"
	export CPP_FOR_BUILD="${CPP_FOR_BUILD:-$CC_FOR_BUILD -E}"
	echo "MinGW cross host=$MINGW_HOST build=$build_triple CC_FOR_BUILD=$CC_FOR_BUILD"

	echo "=== Building Windows x64 (MinGW) host toolchain ($TARGET) ==="
	echo "Build dir: $MINGW_BUILDDIR"
	echo "Host toolchain: $host_tools"
	prepare_mingw_gcc_objdirs

	mingw_args=(
		"${common_top[@]}"
		--
		--builddir="$MINGW_BUILDDIR"
		"${mingw_bottom[@]}"
		--config-flags-host-tools=--build="${build_triple}"
		--host="$MINGW_HOST"
		--host-toolchain-path="$host_tools"
		"$stage"
	)

	# Keep going past a gcc2 failure so we can detect broken auto-host.h and
	# retry once with a forced reconfigure (Arm will not reconfigure otherwise).
	set +e
	expect_failure=1
	run_toolchain_wrapper "${mingw_args[@]}"
	mingw_rc=$?
	expect_failure=0
	set -e

	if [[ $mingw_rc -ne 0 ]]; then
		if mingw_gcc_autohost_ok "$MINGW_BUILDDIR/obj/gcc2"; then
			exit "$mingw_rc"
		fi
		retry_mingw_gcc2_if_autohost_broken || exit "$mingw_rc"
	elif [[ "$stage" == "start" || "$stage" == "gcc2" || "$stage" == "gcc2-nano" ]]; then
		# Successful make can still leave an incomplete auto-host.h if
		# config.status raced; catch that before Newlib bootstrap.
		retry_mingw_gcc2_if_autohost_broken
	fi

	if ! stage_builds_toolchain; then
		echo "Skipping Newlib for MinGW: stage '$stage' does not build the toolchain"
		echo "Windows toolchain build dir: $MINGW_BUILDDIR"
		check_mingw_standalone || true
		return 0
	fi

	echo "=== Building Newlib for MinGW toolchain ==="
	# The Newlib pass bootstraps a *native* toolchain and rebuilds zstd in-tree
	# again. Drop the MinGW archive left behind by the pass above, otherwise the
	# native host-tools link against (or fail to update) a MinGW libzstd.a.
	clean_intree_zstd
	# Only drop trees if auto-host.h is bad — do not wipe a healthy gcc2
	# after a successful main pass (Newlib would otherwise rebuild it fully).
	prepare_mingw_gcc_objdirs check
	bash "$NEWLIB_MINGW" \
		--target="$TARGET" \
		--builddir="$MINGW_BUILDDIR" \
		-- \
		"${newlib_bottom[@]}"

	strip_host_binaries Windows "$MINGW_BUILDDIR/install" "${MINGW_HOST}-strip" pe
	finish_target_libs Windows "$MINGW_BUILDDIR/install"
	check_mingw_standalone || true

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
	if [[ $mingw_not_standalone -eq 1 ]]; then
		echo "             NOTE: some binaries still need non-system DLLs (see warning above)"
	fi
fi
if [[ $enable_log -eq 1 ]]; then
	echo "Full log:    $LOGFILE"
fi
