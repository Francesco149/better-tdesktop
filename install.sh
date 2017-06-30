#!/bin/sh

dest="$PREFIX/$DESTDIR"

install -Dm755 out/Telegram "$dest"/bin/Telegram
install -Dm755 lib/xdg/telegram-desktop.desktop \
               "$dest"/share/applications/telegram-desktop.desktop

install -Dm644 lib/xdg/telegram-desktop.appdata.xml \
               "$dest"/share/appdata/telegram-desktop.appdata.xml

for sz in 16 32 48 64 128 256 512
do
    iconpath="$dest/share/icons/hicolor/${sz}x${sz}/apps"
    install -Dm644 "Telegram/Resources/art/icon${sz}.png" \
                   "$iconpath/telegram-desktop.png"
done

