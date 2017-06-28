#!/bin/sh

# TODO: *maybe* make a makefile when I know how every part of the
#       build works

# -----------------------------------------------------------------
# just some rudimentary parallel job manager

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

    $@ 2>&1 > "$(mktemp -p out -u tmp.XXXXXX)" &
    pids=$!,$pids
}

join() {
    while [ true ]
    do
        pid=$(echo $pids | cut -d"," -f1-1)
        [ -z $pid ] && break
        wait $pid
        retcode=$?

        # 127 = already terminated
        if [ $retcode != 0 ] && [ $retcode != 127 ]
        then
            echo "job $pid failed with code $retcode"
            cat out/tmp.* >> out/build.log
            exit $retcode
        fi
        pids=$(echo $pids | cut -d"," -f2-)
    done
}

handle_sigint() {
    echo "Caught SIGINT, killing jobs..."
    while [ true ]
    do
        pid=$(echo $pids | cut -d"," -f1-1)
        [ -z $pid ] && break
        kill -INT $pid
        pids=$(echo $pids | cut -d"," -f2-)
    done
}

trap handle_sigint SIGINT

# -----------------------------------------------------------------

rm -rf out
mkdir -p out

echo "Build started on $(date)" > out/build.log
starttime=$(date +"%s")

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
    exe="out/codegen_${type}"

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
cat out/tmp.* >> out/build.log
rm out/tmp.*

# -----------------------------------------------------------------

resdir="Telegram/Resources"

codegenjob() {
  echo "Generating langs"
  out/codegen_lang -o out "$resdir"/langs/lang.strings

  echo "Generating numbers"
  out/codegen_numbers -o out "$resdir"/numbers.txt

  echo "Generating emoji"
  out/codegen_emoji -o out
}

addjob codegenjob

find . -name "*.style" | while read style
do
    job() {
      echo $style
      out/codegen_style \
        -I "$resdir" \
        -I "$sourcedir" \
        -o out/styles \
        $style
    }

    addjob job
done

schemejob() {
    echo "Generating scheme"
    python "$sourcedir/codegen/scheme/codegen_scheme.py" \
      -o out \
      "$resdir"/scheme.tl
}

addjob schemejob

sourcedir_moc() {
    for file in "$sourcedir"/*.cpp "$sourcedir"/*.h
    do
        echo "moc'ing $file"
        dstfile=out/moc_sourcedir_"$(basename $file)".cpp
        moc --no-notes "$file" -o "$dstfile"
        [ $(wc -c < "$dstfile") -eq 0 ] && rm "$dstfile"
    done
}

addjob sourcedir_moc

join
cat out/tmp.* >> out/build.log
rm out/tmp.*

# TODO: run rcc, ...
# TODO: compile rest

endtime=$(date +"%s")
diff=$(expr $endtime - $starttime)
mins=$(expr $diff / 60)
secs=$(expr $diff % 60)

timemsg="Time spent: ${mins}m ${secs}s"
echo $timemsg >> out/build.log

echo ""
echo $timemsg
echo "Check 'out/build.log' for more details"

