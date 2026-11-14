#!/bin/sh
# Host test of the CarPlay mod's turns in the car's own format (mod/.../wireless/dipo/CarTurns.java,
# setting tbt_standard): types, directions, the distance bar and the window. Needs a JDK.
set -e
cd "$(dirname "$0")/.."
CP=$(mktemp -d); trap 'rm -rf "$CP"' EXIT
javac --release 8 -Xlint:-options -nowarn -d "$CP" $(find tests/carturns -name '*.java') mod/src/hmgapi/mods/wireless/dipo/CarTurns.java
java -cp "$CP" hmgapi.mods.wireless.dipo.CarTurnsTest
