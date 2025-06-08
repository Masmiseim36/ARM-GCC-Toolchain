#!/bin/bash

distribution="$(lsb_release -is)"
packages="autoconf autogen automake \
	  binutils-mingw-w64-i686 binutils-mingw-w64-x86-64 binutils bison build-essential \
	  cgdb cmake coreutils curl \
	  dblatex dejagnu dh-autoreconf docbook-xsl-doc-html docbook-xsl-doc-pdf docbook-xsl-ns doxygen \
	  emacs expect \
	  flex flip \
	  g++-mingw-w64-i686 g++-mingw-w64-x86-64 g++ gawk gcc-mingw-w64-base gcc-mingw-w64-i686 gcc-mingw-w64-x86-64 gcc-mingw-w64 gcc-multilib gcc gdb gettext gfortran ghostscript git-core golang google-mock \
	  keychain \
	  less \
	  libbz2-dev \
	  libc-dev \
	  libc6-dev \
	  libelf-dev \
	  libglib2.0-dev \
	  libgmp-dev \
	  libgmp3-dev \
	  libisl-dev \
	  libltdl-dev \
	  libmpc-dev \
	  libmpfr-dev \
	  libncurses5-dev \
	  libpugixml-dev \
	  libreadline-dev \
	  libtool \
	  libx11-dev \
	  libxml2-utils \
	  linux-libc-dev \
	  make \
	  mingw-w64-common \
	  mingw-w64-i686-dev \
	  mingw-w64-x86-64-dev \
	  ninja-build \
	  nsis \
	  perl \
	  php-cli \
	  pkg-config \
	  python3 \
	  python3-venv \
	  libpixman-1-0 \
	  qemu-system-arm \
	  qemu-user \
	  ruby-nokogiri \
	  ruby rsync \
	  scons shtool swig \
	  tcl \
	  texinfo \
	  texlive-extra-utils \
	  texlive-full \
	  texlive time \
	  transfig \
	  valgrind vim \
	  wget \
	  xsltproc \
	  zlib1g-dev"

if [[ $distribution = "Ubuntu" ]] ; then
	echo "Hello Ubuntu Linux"

	sudo apt-get update
	sudo apt install -y $packages
	  
	#sudo apt-get build-dep python3
	#sudo apt-get install pkg-config

	sudo apt-get install build-essential gdb lcov pkg-config \
		  libbz2-dev libffi-dev libgdbm-dev libgdbm-compat-dev liblzma-dev \
		  libncurses5-dev libreadline6-dev libsqlite3-dev libssl-dev \
		  lzma lzma-dev tk-dev uuid-dev zlib1g-dev

	sudo apt install -y python3-pip
	sudo apt install -y pipx
	pip install tomli


	cd src

	cd gmp
	chmod +x -R ./
	cd ..

	cd mpc
	chmod +x -R ./
	cd ..

	cd mpfr
	chmod +x -R ./
	cd ..

	cd gcc
#	chmod +x -R ./
	./contrib/download_prerequisites --force --directory=..
	cd ..
	
	cd gnu-devtools-for-arm
	chmod +x -R ./
	cd ..

	cd ..
elif [[ $distribution = "ManjaroLinux" ]] ; then
	echo "Hello Manjano Linux"
	echo pacman -S --noconfirm $packages
	sudo pacman -S --noconfirm $packages
	# https://www.reddit.com/r/archlinux/comments/1b2c63p/pac_aptlike_aliases_for_pacman_yay_and_paru_with/?rdt=42473
	# https://wiki.archlinux.org/title/Pacman/Rosetta
else
	echo "Hello Unknown";
fi