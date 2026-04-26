#!/bin/bash
# Install the packages needed to build the Arm GNU toolchain with build.sh.
# Package lists follow src/gnu-devtools-for-arm/README.md ("Install prerequisite
# packages") plus what build.sh additionally needs.
set -euo pipefail

#git submodule update --init --recursive

# Distribution id: /etc/os-release is always present on systemd distros, while
# lsb_release is not installed by default on Manjaro or minimal Ubuntu images.
distribution=""
distribution_like=""
if [[ -r /etc/os-release ]]; then
	# shellcheck disable=SC1091
	distribution="$(. /etc/os-release && printf '%s' "${ID:-}")"
	# shellcheck disable=SC1091
	distribution_like="$(. /etc/os-release && printf '%s' "${ID_LIKE:-}")"
elif command -v lsb_release >/dev/null 2>&1; then
	distribution="$(lsb_release -is | tr '[:upper:]' '[:lower:]')"
fi

# Ubuntu/Debian package names (from gnu-devtools-for-arm README + extras)
ubuntu_packages=(
	autoconf
	autogen
	automake
	autotools-dev
	binutils-mingw-w64-i686
	binutils-mingw-w64-x86-64
	binutils
	bison
	build-essential
	cgdb
	cmake
	coreutils
	cpio
	curl
	dblatex
	dejagnu
	dh-autoreconf
	docbook-xsl-doc-html
	docbook-xsl-doc-pdf
	docbook-xsl-ns
	doxygen
	dwarves
	emacs
	expect
	flex
	flip
	g++-mingw-w64-i686
	g++-mingw-w64-x86-64
	g++
	gawk
	gcc-mingw-w64-base
	gcc-mingw-w64-i686
	gcc-mingw-w64-x86-64
	gcc-mingw-w64
	gcc-multilib
	gcc
	gdb
	gettext
	gfortran
	ghostscript
	git
	git-core
	golang
	google-mock
	keychain
	less
	libbz2-dev
	libc-dev
	libc6-dev
	libelf-dev
	libglib2.0-dev
	libgmp-dev
	libgmp3-dev
	libisl-dev
	libltdl-dev
	libmpc-dev
	libmpfr-dev
	libncurses-dev
	libncurses5-dev
	libpugixml-dev
	libreadline-dev
	libtool
	libx11-dev
	libxml2-utils
	linux-libc-dev
	libssl-dev
	make
	mingw-w64-common
	mingw-w64-i686-dev
	mingw-w64-x86-64-dev
	ninja-build
	nsis
	perl
	php-cli
	pkg-config
	python3
	python3-venv
	libpixman-1-0
	qemu-system-arm
	qemu-user
	qemu-utils
	ruby-nokogiri
	ruby
	rsync
	scons
	shtool
	swig
	tcl
	texinfo
	texlive-extra-utils
	texlive-full
	texlive
	time
	transfig
	valgrind
	vim
	wget
	xsltproc
	zlib1g-dev
	python3-pip
	pipx
	# build.sh builds the Linux-hosted GDB with --enable-gdb-with-python=yes,
	# which needs Python.h and python3-config.
	python3-dev
	# build.sh requires MinGW compilers with the POSIX thread model (win32
	# threads break the MinGW GDB build). On Debian/Ubuntu these are separate
	# alternatives; the meta packages above do not guarantee them.
	gcc-mingw-w64-x86-64-posix
	g++-mingw-w64-x86-64-posix
	gcc-mingw-w64-i686-posix
	g++-mingw-w64-i686-posix
)

# Arch/Manjaro package names covering the same roles as ubuntu_packages
# Mapping notes: build-essential→base-devel, mingw-*→mingw-w64-toolchain,
# texlive-full→texlive-meta, transfig→fig2dev, gfortran→gcc-fortran,
# google-mock→gmock/gtest, pkg-config→pkgconf, git-core→git
# Note: Arch's mingw-w64-gcc already uses POSIX threads, there are no
# *-posix suffixed binaries; build.sh detects this case.
manjaro_packages=(
	base-devel
	autoconf
	autogen
	automake
	binutils
	bison
	cgdb
	cmake
	coreutils
	cpio
	curl
	dblatex
	dejagnu
	docbook-xsl
	doxygen
	dwarves
	emacs
	expect
	flex
	gawk
	gcc
	gcc-fortran
	gdb
	gettext
	ghostscript
	git
	go
	gmock
	gtest
	keychain
	less
	bzip2
	libelf
	glib2
	gmp
	isl
	libmpc
	mpfr
	ncurses
	pugixml
	readline
	libtool
	libx11
	libxml2
	linux-api-headers
	openssl
	make
	mingw-w64-toolchain
	ninja
	perl
	php
	pkgconf
	python
	python-pip
	python-pipx
	pixman
	qemu-system-arm
	qemu-system-aarch64
	qemu-user
	qemu-img
	ruby
	rsync
	scons
	swig
	tcl
	texinfo
	texlive-meta
	time
	fig2dev
	valgrind
	vim
	wget
	libxslt
	zlib
)

# Packages typically only in the AUR (install via yay/paru if available)
manjaro_aur_packages=(
	flip
	nsis
	shtool
	ruby-nokogiri
)

if [[ $EUID -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
	echo "error: need root privileges or sudo to install packages" >&2
	exit 1
fi

as_root() {
	if [[ $EUID -eq 0 ]]; then
		"$@"
	else
		sudo "$@"
	fi
}

install_warnings=0

# Drop package names apt cannot resolve in this release. The README list predates
# newer Ubuntu releases: on 24.04 for example "libc-dev" and "libncurses5-dev"
# are purely virtual with several providers, and apt-get install then fails for
# the whole transaction. Virtual names with exactly one provider are kept, apt
# resolves those (e.g. transfig -> fig2dev).
apt_filter_available() {
	local pkg policy candidate providers
	local -a keep=() drop=()

	for pkg in "$@"; do
		policy="$(apt-cache policy -- "$pkg" 2>/dev/null || true)"
		if [[ -z $policy ]]; then
			# apt does not know the name at all.
			drop+=("$pkg")
			continue
		fi
		candidate="$(printf '%s' "$policy" | awk '/Candidate:/ {c = $2} END {print c}')"
		if [[ -n $candidate && $candidate != "(none)" ]]; then
			keep+=("$pkg")
			continue
		fi
		# Purely virtual: apt can only resolve it with exactly one provider.
		# "|| true" because apt-cache exits non-zero for unknown names, which
		# pipefail would turn into a silent abort.
		providers="$({ apt-cache showpkg "$pkg" 2>/dev/null || true; } |
			awk '/Reverse Provides:/ {f = 1; next} f && NF {c++} END {print c + 0}')"
		if [[ $providers == "1" ]]; then
			keep+=("$pkg")
			continue
		fi
		drop+=("$pkg")
	done

	if ((${#drop[@]} > 0)); then
		echo "note: skipping packages not installable in this release: ${drop[*]}" >&2
	fi
	if ((${#keep[@]} > 0)); then
		printf '%s\n' "${keep[@]}"
	fi
}

# Install everything in one transaction, but fall back to one package at a time:
# a single package name that no longer exists in the current release would
# otherwise abort the whole installation.
apt_install() {
	local -a packages=("$@")
	local -a failed=()
	local pkg

	if as_root apt-get install -y "${packages[@]}"; then
		return 0
	fi

	echo "warning: bulk apt install failed; retrying package by package" >&2
	for pkg in "${packages[@]}"; do
		if ! as_root apt-get install -y "$pkg"; then
			failed+=("$pkg")
		fi
	done
	if ((${#failed[@]} > 0)); then
		install_warnings=1
		echo "warning: could not install: ${failed[*]}" >&2
		echo "         Check whether these packages still exist in this release." >&2
	fi
}

pacman_install() {
	local -a packages=("$@")
	local -a failed=()
	local pkg

	if as_root pacman -Syu --needed --noconfirm "${packages[@]}"; then
		return 0
	fi

	echo "warning: bulk pacman install failed; retrying package by package" >&2
	for pkg in "${packages[@]}"; do
		if ! as_root pacman -S --needed --noconfirm "$pkg"; then
			failed+=("$pkg")
		fi
	done
	if ((${#failed[@]} > 0)); then
		install_warnings=1
		echo "warning: could not install: ${failed[*]}" >&2
		echo "         Check whether these packages still exist in this release." >&2
	fi
}

case " $distribution $distribution_like " in
*" ubuntu "* | *" debian "*)
	echo "Hello Debian/Ubuntu Linux ($distribution)"

	as_root apt-get update
	declare -a apt_available=()
	mapfile -t apt_available < <(apt_filter_available "${ubuntu_packages[@]}")
	if ((${#apt_available[@]} == 0)); then
		echo "error: none of the required packages are available via apt" >&2
		exit 1
	fi
	apt_install "${apt_available[@]}"
	echo "Install complete"
	;;

*" manjaro "* | *" arch "*)
	echo "Hello Arch/Manjaro Linux ($distribution)"
	# https://wiki.archlinux.org/title/Pacman/Rosetta
	pacman_install "${manjaro_packages[@]}"
	echo "Official repo install complete"

	aur_helper=""
	if command -v yay >/dev/null 2>&1; then
		aur_helper=yay
	elif command -v paru >/dev/null 2>&1; then
		aur_helper=paru
	fi

	if [[ -n $aur_helper ]]; then
		echo "Installing optional AUR packages with $aur_helper"
		if ! "$aur_helper" -S --needed --noconfirm "${manjaro_aur_packages[@]}"; then
			install_warnings=1
			echo "warning: AUR install failed; continuing" >&2
		fi
	else
		echo "No yay/paru found; skipping AUR packages: ${manjaro_aur_packages[*]}"
		echo "Install an AUR helper and re-run, or install them manually if needed."
	fi
	echo "Install complete"
	;;

*)
	echo "Hello Unknown (unsupported distro: ${distribution:-unknown})" >&2
	echo "Install the packages listed in src/gnu-devtools-for-arm/README.md manually." >&2
	exit 1
	;;
esac

#if grep -qi microsoft /proc/version; then
#	echo "We are in WSL - install WSL2-Kernel-Header"
#	git clone https://github.com/microsoft/WSL2-Linux-Kernel.git
#	cd WSL2-Linux-Kernel
#		git checkout linux-msft-wsl-6.6.y
#		make headers_install
#	cd ..
#else
#	echo "No WSL - nothing to do"
#fi

if [[ $install_warnings -eq 1 ]]; then
	echo "Setup finished with warnings: some packages were not installed (see above)." >&2
	exit 1
fi

echo "Setup done"

#mkdir -p build-mingw-aarch64-none-elf
#./src/gnu-devtools-for-arm/build-gnu-toolchain.sh --target=aarch64-none-elf
