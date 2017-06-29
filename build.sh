#!/bin/sh

if [ $(pwd | grep -o " " | wc -l) -ne 0 ]
then
    echo "Paths with spaces are not supported by this build script"
    echo "because the author is too lazy"
    echo ""
    echo "Please move me to a normal directory"
    exit 1
fi

sd=$(pwd)

# -----------------------------------------------------------------

without_pulse=0

for param in $@
do
    case "$param" in
        "--help")
            echo "Usage: $0 [parameters]"
            echo "--without-pulse: don't build pulseaudio support"
            echo "--threads=n: number of parallel build threads"
            exit 0
            ;;

        "--without-pulse")
            without_pulse=1 ;;

        "--threads=*")
            MAKE_THREADS=$(echo $param | cut -d"=" -f2-) ;;

        *)
            echo "ABUNAI: unknown parameter $param"
    esac
done

# TODO: *maybe* make a makefile when I know how every part of the
#       build works

# -----------------------------------------------------------------
# just some rudimentary parallel job manager
# TODO: tweak jobs so they are more equally sized (currently the
#       cpu isn't being fully utilized towards the end of the
#       build)

threads=${MAKE_THREADS:-9}
pids=""

addjob() {
    while [ true ]
    do
        # trim completed processes off pids
        tmp=$pids
        newpids=""
        while [ true ]
        do
            pid=$(echo $tmp | cut -d"," -f1-1)
            [ -z $pid ] && break
            kill -0 $pid && newpids=$pid,$newpids
            tmp=$(echo $tmp | cut -d"," -f2-)
        done

        pids=$newpids

        # wait until there's room for new jobs
        if [ $(echo $pids | grep -o "," | wc -l) -ge $threads ]
        then
            sleep 0.1
        else
            break
        fi
    done

    $@ > "$(mktemp -p "$sd/out" -u tmp.XXXXXX)" 2>&1 &
    pids=$!,$pids
}

handle_sigint() {
    echo "Caught SIGINT, killing jobs..."
    while [ true ]
    do
        pid=$(echo $pids | cut -d"," -f1-1)
        [ -z $pid ] && break
        kill -9 $pid
        wait $pid
        pids=$(echo $pids | cut -d"," -f2-)
    done
}

trap handle_sigint SIGINT

join() {
    while [ true ]
    do
        pid=$(echo $pids | cut -d"," -f1-1)
        [ -z $pid ] && break
        wait $pid
        retcode=$?

        # TODO: busybox doesn't hold the exit code unless
        # you call wait before the process terminates,
        # so we end up getting
        # 127 = already terminated
        # which doesn't help figuring out if the process
        # errored or not.
        # find out a portable way to do this
        if [ $retcode != 0 ] && [ $retcode != 127 ]
        then
            handle_sigint
            echo "job $pid failed with code $retcode"
            echo "Check 'out/build.log' for more details"
            cat "$sd"/out/tmp.* >> "$sd"/out/build.log
            cd $sd
            exit $retcode
        fi
        pids=$(echo $pids | cut -d"," -f2-)
    done
}

# -----------------------------------------------------------------

rm -rf "$sd"/out
mkdir -p "$sd"/out

echo "Build started on $(date)" > "$sd/out"/build.log

starttime=$(date +"%s")

cxx=${CXX:-g++}

cxxflags="-std=gnu++14 -pipe -Wall -fPIC"
cxxflags="$cxxflags -I$sd/Telegram/SourceFiles"
cxxflags="$cxxflags $CXXFLAGS"

# -----------------------------------------------------------------

# first of all, we build the codegen's. these will be used to
# generate code for localization, emoji, and other stuff.

b="$sd"/Telegram/SourceFiles/codegen

# lang and numbers codegens didn't actually need Qt5Gui
# the devs simply forgot to remove the QtImage include they
# copypasted
pkgs="Qt5Core"
pkgflags="$(pkg-config --cflags $pkgs)"
pkglibs="$(pkg-config --libs $pkgs)"

for type in lang numbers
do
    exe="$sd/out/codegen_${type}"

    job() {
        echo $exe

        $cxx \
          $cxxflags \
          $pkgflags \
          "$b/common/"*.cpp \
          "$b/$type/"*.cpp \
          $pkglibs \
          -o "$exe"
    }

    addjob job
done

# emoji actually uses Qt5Gui
pkgs="Qt5Core Qt5Gui"
pkgflags="$(pkg-config --cflags $pkgs)"
pkglibs="$(pkg-config --libs $pkgs)"

for type in emoji style
do
    exe="$sd/out/codegen_${type}"

    job() {
        echo $exe

        $cxx \
          $cxxflags \
          $pkgflags \
          "$b/common/"*.cpp \
          "$b/$type/"*.cpp \
          $pkglibs \
          -o "$exe"
    }

    addjob job
done

join
cat "$sd"/out/tmp.* >> "$sd"/out/build.log
rm "$sd"/out/tmp.*

# -----------------------------------------------------------------

b="$sd/Telegram/Resources"

codegenjob() {
  echo "Generating langs"
  "$sd"/out/codegen_lang \
    -o "$sd"/out "$b"/langs/lang.strings

  echo "Generating numbers"
  "$sd"/out/codegen_numbers \
    -o "$sd"/out "$b"/numbers.txt

  echo "Generating emoji"
  "$sd"/out/codegen_emoji -o "$sd"/out
}

addjob codegenjob

relpath() {
    python - "$1" "${2:-$PWD}" << "EOF"
import sys
import os.path
print(os.path.relpath(sys.argv[1], sys.argv[2]))
EOF
}

stylejob() {
    rsd="$(relpath "$sd")"
    rb="$(relpath "$b")"

    find "$sd"/Telegram -name "*.style" \
                     -o -name "*.palette" | \
    while read style
    do
        # for some reason codegen-style wants relative paths
        # TODO: clean this up
        # TODO: check if there's any issues with absolute paths
        #       in the other codegen tools
        echo "$style"
        "$sd"/out/codegen_style \
          -I "$rb" \
          -I "$rsd/Telegram/SourceFiles" \
          -o "$rsd/out/styles" \
          -w "$rsd" \
          "$style" || return 1
    done
}

addjob stylejob

schemejob() {
    echo "Generating scheme"
    codegen_scheme_dir="$sd"/Telegram/SourceFiles/codegen/scheme
    python $codegen_scheme_dir/codegen_scheme.py \
      -o "$sd"/out \
      "$b"/scheme.tl
}

addjob schemejob

# -----------------------------------------------------------------

# QT uses special metaprogramming syntax that needs to be handled
# by moc, which will generate an additional cpp file

b="$sd"/Telegram/SourceFiles

# moc needs to be aware of the defines we will use to later compile
# the main code, otherwise it might define/undefine stuff that
# we want to disable
defines="-DQ_OS_LINUX64=1"
defines="$defines -DTDESKTOP_DISABLE_UNITY_INTEGRATION=1"
defines="$defines -DTDESKTOP_DISABLE_AUTOUPDATE=1"
defines="$defines -DTDESKTOP_DISABLE_CRASH_REPORTS=1"
defines="$defines -D_REENTRANT=1 -DQT_PLUGIN=1"

run_moc() {
    for file in $@
    do
        echo "moc'ing $file"
        prefix="$(dirname "$file")"
        prefix="$(relpath "$prefix")"
        mocprefix="$sd/out/moc/"
        mkdir -p "$mocprefix/$prefix"
        dstfile="$mocprefix/$prefix"/moc_"$(basename $file)".cpp
        moc $defines --no-notes "$file" -o "$dstfile"
        [ $(wc -c < "$dstfile") -eq 0 ] && rm "$dstfile"
    done

    return 0
}

addjob run_moc "$b"/*.h

for dirname in base boxes calls core chat_helpers data dialogs \
               history inline_bots intro media mtproto overview \
               platform/linux profile settings storage ui window
do
    addjob run_moc "$b"/$dirname/*.h
done

# -----------------------------------------------------------------

# resource files are compiled to hardcoded cpp files by qt's rcc

b="$sd/Telegram/Resources/qrc"

run_rcc() {
    for file in $@
    do
        echo "rcc'ing $file"
        mkdir -p "$sd/out/qrc"
        filename=$(basename "$file")
        filename_noext=$(echo $filename | rev | cut -d"." -f2- | rev)

        rcc \
          -no-compress \
          -name $filename_noext \
          "$file" \
          -o "$sd/out/qrc/qrc_$filename_noext.cpp"
    done
}

addjob run_rcc "$b"/*.qrc

join
cat "$sd"/out/tmp.* >> "$sd"/out/build.log
rm "$sd"/out/tmp.*

# -----------------------------------------------------------------

qt_private_headers() {
    flags=""

    # telegram uses private Qt headers, which I assume are supposed
    # to be internal. they are located at module_include_dir/qtver
    for pkg in $@
    do
        pkgver="$(pkg-config --modversion $pkg)"
        for includedir in \
          $(pkg-config --cflags-only-I $pkg | sed 's|-I||g')
        do
            flags="-I$includedir/$pkgver $flags"

            for privatedir in "$includedir/$pkgver"/*; do
                flags="-I$privatedir $flags"
            done
        done
    done

    echo $flags
}

# -----------------------------------------------------------------

cd "$sd"/out

cxxflags="-std=gnu++14 -pipe -Wall -fPIC -Wno-unused-variable"
cxxflags="$cxxflags -I$sd/Telegram/SourceFiles -I$sd/out"
cxxflags="$defines $cxxflags"

# TODO: not all these packages are needed for the pch
#       move the ones that are exclusive to the main source
#       same goes for defines
qtpkgs="Qt5Core Qt5Gui"
pkgs="$qtpkgs gtk+-2.0 appindicator-0.1 opus zlib"
pkgflags="$(pkg-config --cflags $pkgs)"
pkgflags="$pkgflags $(qt_private_headers $qtpkgs)"
pkglibs="$(pkg-config --libs $pkgs)"

# mkspec, some more half-undocumented include dirs
qarchdata="$(qmake -query QT_INSTALL_ARCHDATA)"
qspec="$(qmake -query QMAKE_SPEC)"
cxxflags="$cxxflags -I$qarchdata/mkspecs/$qspec"

# third-party lib includes
tp="$sd"/Telegram/ThirdParty
for includedir in GSL/include libtgvoip minizip variant/include
do
    cxxflags="$cxxflags -I$tp/$includedir"
done

cxxflags="$cxxflags $CXXFLAGS"

b="$sd"/Telegram/SourceFiles

if [ -e "$b/stdafx.h.gch" ]; then
    echo "Found precompiled header"
else
    echo "Compiling precompiled header..."

    $cxx \
      -x c++-header \
      $cxxflags \
      $pkgflags \
      "$b"/stdafx.cpp \
      -o "$b"/stdafx.h.gch \
      || exit $?

    # this piece of crap is like 280 MB btw lol
fi

# now including stdafx.h will automatically use the .gch
# precompiled file

# -----------------------------------------------------------------

echo "Compiling Telegram"
echo "Go get a coffee, this is gonna take a while..."

addjob \
  $cxx -c \
    -include "stdafx.h" \
    $cxxflags \
    $pkgflags \
    $(echo "$b"/*.cpp | sed 's|$b/stdafx.cpp||g')

for dirname in base boxes calls core chat_helpers data dialogs \
               history inline_bots intro media mtproto overview \
               platform/linux profile settings storage ui window
do
    addjob \
      $cxx -c \
        -include "stdafx.h" \
        $cxxflags \
        $pkgflags \
        "$b"/$dirname/*.cpp
done

# TODO: compile rest

join
cat "$sd"/out/tmp.* >> "$sd"/out/build.log
rm "$sd"/out/tmp.*

# -----------------------------------------------------------------

endtime=$(date +"%s")
diff=$(expr $endtime - $starttime)
mins=$(expr $diff / 60)
secs=$(expr $diff % 60)

timemsg="Time spent: ${mins}m ${secs}s"
echo $timemsg >> "$sd"/out/build.log

echo ""
echo $timemsg
echo "Check 'out/build.log' for more details"

cd $sd

