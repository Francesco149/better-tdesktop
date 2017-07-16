Fork of the linux version of Telegram Desktop with less bloat and customizable fonts.

As of 1.1.7-b1, you can embed almost every video format and it will be visible to
vanilla clients. Web and android users should be able to play most of these custom
embeds, while iOS and desktop users will see the thumbnail but won't be able to play
them unless it's mp4 or mov.

![](http://hnng.moe/f/SI9)

![](https://media.giphy.com/media/3ohryB1G18DNauuUrC/giphy.gif)

# Project status
* customizable font overrides in ```~/.config/TelegramDesktop/TelegramDesktop.conf```
* allow embedding of every video format supported by the ffmpeg version you are
  building against
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

If you have multiple versions of Qt installed you might need to
enable qt5 specifically so that tools like moc use the correct
qt version (check with ```moc -v``` ).

qtchooser is often used for this, and I've provided a wrapper
script for it, just run build like so:

```
./build.sh --qt-tools-prefix="$(pwd)/qtchooser-wrapper.sh"
```

If you want to keep your previous telegram login and settings, create this
compatibility symlink:

```
ln -s . "$HOME"/.local/share/TelegramDesktop/TelegramDesktop
```

If you want to install better-tdesktop system-wide or you are a package maintainer,
use the install.sh script as a reference or run it directly.

# Font override
After starting Telegram once, ```~/.config/TelegramDesktop/TelegramDesktop.conf```
should be created. Edit it with your desired fonts, or leave the values empty for
the defaults, then restart telegram.

