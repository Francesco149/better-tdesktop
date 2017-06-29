# Note
This is a work-in-progress fork of telegram desktop that will aim to minimize dependencies and make it simpler to build and customize telegram.

It only focuses on linux for now.

# Project status
* can be built without pulseaudio or pulseaudio headers
* patched to build on musl libc
* patched to build with libressl
* patched to use dynamically linked system qt
* patched to work with qt versions older than 5.6.0
* removed breakpad
* downgraded gtk3 to gtk2
* removed cmake
* removed gyp
* build script doesn't require bash (compatible with smaller shells such
  as busybox's ash)
* removed unity integration and dependency on unity libs

Effort will be made to shrink the dependencies further.
Credits to debian maintainers for the qt patches.

# Usage
The project is still at a very early, unoptimized and unpolished state but
it's already possible to build it (it's still slower than the normal
gyp/cmake build though).

This was developed and tested on sabotage linux, a musl libc based distro.

Requirements:
* qt5
* zlib
* gtk-2.0
* libdrm
* libva
* opus
* ffmpeg
* libappindicator
* liblzma
* openal
* a g++ version that supports c++14 and C11

```
git clone https://github.com/Francesco149/better-tdesktop.git
cd better-tdesktop
./build.sh --without-pulse --threads=9

# ... wait a million years
# ... wait some more
# ... watch your ram and cpu struggle

out/Telegram
```

