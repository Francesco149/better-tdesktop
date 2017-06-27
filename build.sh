#!/bin/sh

# TODO: parallelize builds
# TODO: *maybe* make a makefile when I know how every part of the
#       build works

rm -rf out
mkdir -p out

# -----------------------------------------------------------------

cxx=${CXX:-g++}
sourcedir="Telegram/SourceFiles"

# first of all, we build the codegen's. these will be used to
# generate code for localization, emoji, and other stuff.

cxxflags="-std=c++14 -pipe -Wall -fPIC -I$sourcedir $CXXFLAGS"
b="$sourcedir/codegen"

# lang and numbers codegens didn't actually need Qt5Gui
# the devs simply forgot to remove the QtImage include they
# copypasted
pkgs="Qt5Core"
pkgflags="$(pkg-config --cflags $pkgs)"
pkglibs="$(pkg-config --libs $pkgs)"

for type in lang numbers
do
    exe="out/codegen_${type}"
    echo $exe

    $cxx \
      $cxxflags \
      $pkgflags \
      "$b/common/"*.cpp \
      "$b/$type/"*.cpp \
      $pkglibs \
      -o "$exe" \
      || exit 1
done

# emoji actually uses Qt5Gui
pkgs="Qt5Core Qt5Gui"
pkgflags="$(pkg-config --cflags $pkgs)"
pkglibs="$(pkg-config --libs $pkgs)"

for type in emoji style
do
    exe="out/codegen_${type}"
    echo $exe

    $cxx \
      $cxxflags \
      $pkgflags \
      "$b/common/"*.cpp \
      "$b/$type/"*.cpp \
      $pkglibs \
      -o "$exe" \
      || exit 1
done

# -----------------------------------------------------------------

# TODO: run codegens
# TODO: run moc, rcc, ...
# TODO: compile rest

