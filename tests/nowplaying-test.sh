#!/bin/sh
# Host test of the CarPlay mod's song info on wireless CarPlay (mod/.../dipo/NowPlaying.java): when
# NowPlaying starts, once per CarPlay-channel session, its retries and stale tries. Needs a JDK.
set -e
cd "$(dirname "$0")/.."
CP=$(mktemp -d); trap 'rm -rf "$CP"' EXIT
javac --release 8 -Xlint:-options -nowarn -d "$CP" $(find tests/nowplaying -name '*.java') mod/src/hmgapi/mods/wireless/dipo/NowPlaying.java
java -cp "$CP" hmgapi.mods.wireless.dipo.NowPlayingTest
