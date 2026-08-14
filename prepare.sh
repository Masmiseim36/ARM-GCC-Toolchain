#!/bin/bash

#git submodule update --init --recursive

distribution="$(lsb_release -is)"

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
)

# Arch/Manjaro package names covering the same roles as ubuntu_packages
# Mapping notes: build-essential→base-devel, mingw-*→mingw-w64-toolchain,
# texlive-full→texlive-meta, transfig→fig2dev, gfortran→gcc-fortran,
# google-mock→gmock/gtest, pkg-config→pkgconf, git-core→git
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

if [[ $distribution = "Ubuntu" ]] ; then
	echo "Hello Ubuntu Linux"

	sudo apt-get update
	sudo apt install -y "${ubuntu_packages[@]}"
	echo "Install complete"
elif [[ $distribution = "ManjaroLinux" ]] ; then
	echo "Hello Manjaro Linux"
	# https://wiki.archlinux.org/title/Pacman/Rosetta
	sudo pacman -Syu --needed --noconfirm "${manjaro_packages[@]}"
	echo "Official repo install complete"

	aur_helper=""
	if command -v yay >/dev/null 2>&1; then
		aur_helper=yay
	elif command -v paru >/dev/null 2>&1; then
		aur_helper=paru
	fi

	if [[ -n $aur_helper ]]; then
		echo "Installing optional AUR packages with $aur_helper"
		"$aur_helper" -S --needed --noconfirm "${manjaro_aur_packages[@]}"
	else
		echo "No yay/paru found; skipping AUR packages: ${manjaro_aur_packages[*]}"
		echo "Install an AUR helper and re-run, or install them manually if needed."
	fi
	echo "Install complete"
else
	echo "Hello Unknown (unsupported distro: ${distribution:-unknown})"
	exit 1
fi


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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ensure-executables.sh
source "$SCRIPT_DIR/ensure-executables.sh"
ensure_build_executables "$SCRIPT_DIR"

echo "Setup done"

#mkdir -p build-mingw-aarch64-none-elf
#./src/gnu-devtools-for-arm/build-gnu-toolchain.sh --target=aarch64-none-elf
