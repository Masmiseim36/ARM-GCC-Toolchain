#!/bin/bash
# Make only build-related scripts executable (no recursive chmod of whole trees).
# Sourced by prepare.sh and build.sh.
#
# Covers scripts invoked directly or indirectly by the Arm GNU toolchain build:
# - gnu-devtools-for-arm drivers (build-*.sh, python-config.sh)
# - autoconf/libtool helpers run by configure/make (configure, install-sh, …)
# - shebang helpers in host libraries (e.g. gmp/mpn/m4-ccas, mpfr tools)

ensure_build_executables() {
	local root="${1:?root directory required}"
	local src="$root/src"
	local d
	local -a found=()

	chmod_paths() {
		local -a paths=("$@")
		local -a existing=()
		local p
		for p in "${paths[@]}"; do
			[[ -f $p ]] && existing+=("$p")
		done
		if ((${#existing[@]} > 0)); then
			chmod +x "${existing[@]}"
			found+=("${existing[@]}")
		fi
	}

	chmod_find() {
		local dir="$1"
		shift
		local -a matches=()
		mapfile -d '' matches < <(
			find "$dir" \
				\( -path '*/.git/*' -o -path '*/.git' \
					-o -path '*/testsuite/*' -o -path '*/testsuite' \
					-o -path '*/tests/*' -o -path '*/tests' \
					-o -path '*/testcase/*' -o -path '*/testcase' \
				\) -prune -o \
				-type f \( "$@" \) -print0 2>/dev/null
		)
		if ((${#matches[@]} > 0)); then
			chmod +x "${matches[@]}"
			found+=("${matches[@]}")
		fi
	}

	chmod_shebangs() {
		local dir="$1"
		local -a matches=()
		mapfile -d '' matches < <(
			find "$dir" \
				\( -path '*/.git/*' -o -path '*/.git' \
					-o -path '*/testsuite/*' -o -path '*/testsuite' \
					-o -path '*/tests/*' -o -path '*/tests' \
				\) -prune -o \
				-type f -print0 2>/dev/null \
				| xargs -0 -r grep -Zl '^#!' 2>/dev/null
		)
		if ((${#matches[@]} > 0)); then
			chmod +x "${matches[@]}"
			found+=("${matches[@]}")
		fi
	}

	echo "Setting executable bits on build scripts only..."

	# Top-level repo scripts
	chmod_paths \
		"$root/prepare.sh" \
		"$root/build.sh" \
		"$root/ensure-executables.sh"

	# Toolchain driver scripts (build.sh / prepare.sh → these)
	if [[ -d $src/gnu-devtools-for-arm ]]; then
		chmod_paths \
			"$src/gnu-devtools-for-arm/build-gnu-toolchain.sh" \
			"$src/gnu-devtools-for-arm/build-baremetal-toolchain.sh" \
			"$src/gnu-devtools-for-arm/build-cross-linux-toolchain.sh" \
			"$src/gnu-devtools-for-arm/build-newlib-for-mingw-toolchain.sh" \
			"$src/gnu-devtools-for-arm/python-config.sh"
		# Any additional helpers under extras (e.g. source-fetch.py if executed directly)
		if [[ -d $src/gnu-devtools-for-arm/extras ]]; then
			chmod_find "$src/gnu-devtools-for-arm/extras" -name '*.sh' -o -name '*.py'
		fi
	fi

	# Optional GCC helper referenced by the README (not always used)
	chmod_paths "$src/gcc/contrib/download_prerequisites"

	# Host libraries: configure/make invoke many small helpers (incl. extensionless shebangs)
	for d in gmp mpfr mpc isl zstd libexpat libiconv; do
		[[ -d $src/$d ]] || continue
		chmod_find "$src/$d" \
			-name '*.sh' -o -name configure -o -name 'config.*' \
			-o -name '*.guess' -o -name '*.sub' \
			-o -name install-sh -o -name missing -o -name compile \
			-o -name depcomp -o -name ltmain.sh -o -name libtool \
			-o -name ar-lib -o -name test-driver -o -name ylwrap \
			-o -name move-if-change -o -name mkinstalldirs -o -name 'm4-*'
		chmod_shebangs "$src/$d"
	done

	# Large trees: only well-known autoconf/make helpers and *.sh (not every source file)
	for d in binutils-gdb binutils-gdb--gdb gcc newlib-cygwin glibc linux qemu; do
		[[ -d $src/$d ]] || continue
		chmod_find "$src/$d" \
			-name '*.sh' -o -name configure -o -name 'config.*' \
			-o -name '*.guess' -o -name '*.sub' \
			-o -name install-sh -o -name missing -o -name compile \
			-o -name depcomp -o -name ltmain.sh -o -name libtool \
			-o -name ar-lib -o -name test-driver -o -name ylwrap \
			-o -name move-if-change -o -name mkinstalldirs
	done

	# Deduplicate count for the summary
	local -A seen=()
	local f count=0
	for f in "${found[@]}"; do
		[[ -n ${seen[$f]+x} ]] && continue
		seen[$f]=1
		count=$((count + 1))
	done
	echo "Marked $count script(s) executable."
}
