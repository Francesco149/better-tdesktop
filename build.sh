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
without_sse=0

with_gold=0

for param in "$@"
do
    case "$param" in
        "--help")
            echo "Usage: $0 [parameters]"
            echo "--without-pulse: don't build pulseaudio support"
            echo "--without-sse: don't enable SSE optimization"
            echo "--with-gold: uses the gold multithreaded linker"
            echo "--threads=n: number of parallel build threads"
            exit 0
            ;;

        "--without-pulse")
            without_pulse=1 ;;

        "--without-sse")
            without_sse=1 ;;

        "--with-gold")
            with_gold=1 ;;

        "--threads="*)
            MAKE_THREADS=$(echo $param | cut -d"=" -f2-) ;;

        *)
            echo "ABUNAI: unknown parameter $param"
    esac
done

# TODO: *maybe* make a makefile when I know how every part of the
#       build works

# -----------------------------------------------------------------

all_pkgs="Qt5Core Qt5Gui Qt5Widgets Qt5Network gtk+-2.0"
all_pkgs="$all_pkgs appindicator-0.1 opus zlib x11 libcrypto"
all_pkgs="$all_pkgs libavformat libavcodec libswresample"
all_pkgs="$all_pkgs libswscale libavutil liblzma openal libdrm"
all_pkgs="$all_pkgs libva opus"

pkg-config --cflags --libs "$all_pkgs" > /dev/null || exit $?

# -----------------------------------------------------------------

build_end() {
    [ $1 -ne 0 ] && echo "Build failed with code $1"
    echo "Check 'out/build.log' for more details"

    cd $sd
    cat "$sd"/out/tmp.* >> "$log"
    rm "$sd"/out/tmp.*

    exit $1
}

# TODO: is QT_PLUGIN necessary?

# qt and system libraries
defines="-DQ_OS_LINUX64=1 -DQT_PLUGIN=1 -D_REENTRANT=1"

# telegram
defines="$defines -DTDESKTOP_DISABLE_UNITY_INTEGRATION=1"
defines="$defines -DTDESKTOP_DISABLE_AUTOUPDATE=1"
defines="$defines -DTDESKTOP_DISABLE_CRASH_REPORTS=1"

# libtgvoip
defines="$defines -DWEBRTC_APM_DEBUG_DUMP=0"
defines="$defines -DTGVOIP_USE_DESKTOP_DSP=1"
defines="$defines -DWEBRTC_POSIX=1"

if [ $without_pulse -ne 0 ]
then
    defines="$defines -DLIBTGVOIP_WITHOUT_PULSE=1"
else
    pkg-config --cflags libpulse > /dev/null || exit $?
fi

# -----------------------------------------------------------------

cxx=${CXX:-g++}

# NOTE: not all include dirs are necessary for all files, I should
#       check how much extra include dirs slow compilation down

cxxflags="-pipe -Wall -fPIC"
cxxflags="$cxxflags -Wno-strict-aliasing -Wno-unused-variable"
cxxflags="$cxxflags -Wno-switch -Wno-unused-but-set-variable"
cxxflags="$cxxflags -Wno-sign-compare"
# TODO: fix all signed->unsigned comparisons in the code

cxxflags="$cxxflags -flto -Ofast"
cxxflags="$cxxflags -ffunction-sections -fdata-sections"
cxxflags="$cxxflags -g0 -fno-unwind-tables -s"
cxxflags="$cxxflags -fno-asynchronous-unwind-tables"

cxxflags="$cxxflags -I$sd/Telegram/SourceFiles -I$sd/out"

# mkspec, half-undocumented qt include dirs
qarchdata="$(qmake -query QT_INSTALL_ARCHDATA)"
qspec="$(qmake -query QMAKE_SPEC)"
cxxflags="$cxxflags -I$qarchdata/mkspecs/$qspec"

# third-party lib includes
tp="$sd"/Telegram/ThirdParty
for includedir in GSL/include libtgvoip minizip \
                  variant/include libtgvoip/webrtc_dsp
do
    cxxflags="$cxxflags -I$tp/$includedir"
done

[ $without_sse -eq 0 ] && \
    cxxflags="$cxxflags -msse2"

# -----------------------------------------------------------------

cc=${CC:-gcc}
cflags="$cxxflags"

# -----------------------------------------------------------------

ldflags="$cxxflags $LDFLAGS"
cxxflags="$defines -std=gnu++14 $cxxflags $CXXFLAGS"
cflags="$defines -std=gnu11 $cflags $CFLAGS"

if [ $with_gold -ne 0 ]
then
    ldflags="$ldflags -fuse-ld=gold"
    ldflags="$ldflags -Wl,--threads,--thread-count=$MAKE_THREADS"
fi

# -----------------------------------------------------------------

rm -rf "$sd"/out
mkdir -p "$sd"/out

log="$sd"/out/build.log

echo "Build started on $(date)" >> "$log"

starttime=$(date +"%s")

echo "c++ info"                                >> "$log"
printf "%s" "-------------------------------"  >> "$log"
echo "----------------------------------"      >> "$log"
echo "$cxx $cxxflags"                          >> "$log"
printf "%s" "-------------------------------"  >> "$log"
echo "----------------------------------"      >> "$log"

echo "c info"                                  >> "$log"
printf "%s" "-------------------------------"  >> "$log"
echo "----------------------------------"      >> "$log"
echo "$cc $cflags"                             >> "$log"
printf "%s" "-------------------------------"  >> "$log"
echo "----------------------------------"      >> "$log"

# -----------------------------------------------------------------
# just some rudimentary parallel job manager
# TODO: tweak jobs so they are more equally sized (currently the
#       cpu isn't being fully utilized towards the end of the
#       build)

threads=${MAKE_THREADS:-9}
pids=""
all_pids=""

addjob() {
    while [ ! -e "$sd"/out/abort ]
    do
        # trim completed processes off pids
        tmp=$pids
        newpids=""
        while [ ! -e "$sd"/out/abort ]
        do
            pid=$(echo $tmp | cut -d"," -f1-1)
            [ -z $pid ] && break
            [ "$(ps | grep $pid | wc -l)" -ne 0 ] && \
                newpids=$pid,$newpids
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

    if [ ! -e "$sd"/out/abort ]
    then
        $@ > "$(mktemp -p "$sd/out" -u tmp.XXXXXX)" 2>&1 &
        newpid=$!
        pids=$newpid,$pids
        all_pids=$newpid,$all_pids
    fi
}

handle_sigint() {
    echo "Caught SIGINT, killing jobs..."
    touch "$sd"/out/abort
    while [ true ]
    do
        pid=$(echo $all_pids | cut -d"," -f1-1)
        [ -z $pid ] && break
        [ "$(ps | grep $pid | wc -l)" -ne 0 ] && \
            kill -9 $pid
        wait $pid
        all_pids=$(echo $all_pids | cut -d"," -f2-)
    done
    build_end 1
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
            cat "$sd"/out/tmp.* >> "$log"
            cd $sd
            build_end $retcode
        fi
        pids=$(echo $pids | cut -d"," -f2-)
    done
}

# -----------------------------------------------------------------

if [ -e "$sd"/tools ]
then
    echo "Found code generation tools"
else
    echo "Compiling code generation tools"
    # first of all, we build the codegen's. these will be used to
    # generate code for localization, emoji, and other stuff.

    b="$sd"/Telegram/SourceFiles/codegen

    # lang and numbers codegens didn't actually need Qt5Gui
    # the devs simply forgot to remove the QtImage include they
    # copypasted
    pkgs="Qt5Core"
    pkgflags="$(pkg-config --cflags $pkgs)"
    pkglibs="$(pkg-config --libs $pkgs)"

    mkdir -p "$sd/tools"

    for type in lang numbers
    do
        exe="$sd/tools/codegen_${type}"

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
        exe="$sd/tools/codegen_${type}"

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
    cat "$sd"/out/tmp.* >> "$log"
    rm "$sd"/out/tmp.*
fi

# -----------------------------------------------------------------

b="$sd/Telegram/Resources"

echo "Running code generation tools"

codegenjob() {
  echo "Generating langs"
  "$sd"/tools/codegen_lang \
    -o "$sd"/out "$b"/langs/lang.strings

  echo "Generating numbers"
  "$sd"/tools/codegen_numbers \
    -o "$sd"/out "$b"/numbers.txt

  echo "Generating emoji"
  "$sd"/tools/codegen_emoji -o "$sd"/out
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
        "$sd"/tools/codegen_style \
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
               platform/linux profile settings storage ui window \
               media/view media/player ui/effects ui/style \
               ui/text ui/toast ui/widgets window/themes
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
cat "$sd"/out/tmp.* >> "$log"
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

# TODO: not all these packages are needed for the pch
#       move the ones that are exclusive to the main source
#       same goes for defines
qtpkgs="Qt5Core Qt5Gui"
pkgs="$qtpkgs gtk+-2.0 appindicator-0.1 opus zlib"
pkgflags="$(pkg-config --cflags $pkgs)"
pkgflags="$pkgflags $(qt_private_headers $qtpkgs)"

[ $without_pulse -eq 0 ] && \
    pkgflags="$pkgflags $(pkg-config --cflags libpulse)"

b="$sd"/Telegram/SourceFiles

if [ -e "$b/stdafx.h.gch" ]; then
    echo "Found precompiled header"
else
    echo "Compiling precompiled header..."

    $cxx \
      -x c++-header \
      $cxxflags \
      $pkgflags \
      "$b"/stdafx.h \
      -o "$b"/stdafx.h.gch \
      || build_end $?

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
    "$b"/*.cpp

# TODO: cd to correct dirs in case there's name clashes
#       (there probably aren't though)

for dirname in base boxes calls core chat_helpers data dialogs \
               history inline_bots intro media mtproto overview \
               platform/linux profile settings storage ui window \
               media/view media/player ui/effects ui/style \
               ui/text ui/toast ui/widgets window/themes
do
    addjob \
      $cxx -c \
        -include "stdafx.h" \
        $cxxflags \
        $pkgflags \
        "$b"/$dirname/*.cpp
done

compile_generated_code() {
    find "$sd"/out -name "*.cpp" | \
    while read file
    do
        addjob \
        $cxx -c \
          -include "stdafx.h" \
          $cxxflags \
          $pkgflags \
          "$file"
    done
}

compile_generated_code

tp="$sd"/Telegram/ThirdParty

addjob \
  $cc -c \
    $cflags \
    $pkgflags \
    "$tp"/minizip/*.c

compile_libtgvoip() {
    find "$tp"/libtgvoip -name "*.cpp" -o -name "*.cc" | \
    while read file
    do
        $cxx -c \
          $cxxflags $tgvoipflags \
          $pkgflags \
          "$file" \
          || return 1
    done

    find "$tp"/libtgvoip -name "*.c" | \
    while read file
    do
        $cc -c \
          $cflags $tgvoipflags \
          $pkgflags \
          "$file" \
          || return 1
    done
}

addjob compile_libtgvoip

join
cat "$sd"/out/tmp.* >> "$log"
rm "$sd"/out/tmp.*

# -----------------------------------------------------------------

pkglibs="$(pkg-config --libs $all_pkgs)"

echo "Linking"
$cxx \
  $ldflags \
  "$sd"/out/*.o \
  $pkglibs \
  -o "$sd"/out/Telegram \
  > "$(mktemp -p "$sd/out" -u tmp.XXXXXX)" 2>&1 \
  || build_end $?

# -----------------------------------------------------------------

endtime=$(date +"%s")
diff=$(expr $endtime - $starttime)
mins=$(expr $diff / 60)
secs=$(expr $diff % 60)

timemsg="Time spent: ${mins}m ${secs}s"
echo $timemsg >> "$log"
echo ""
echo $timemsg

build_end 0

