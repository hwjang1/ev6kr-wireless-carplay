#!/bin/sh
# Host test of the CarPlay mod's cluster song line (mod/.../wireless/ClusterText.java): "artist -
# title", empty titles, the 63-character limit. Needs a JDK.
set -e
cd "$(dirname "$0")/.."
CP=$(mktemp -d); trap 'rm -rf "$CP"' EXIT
javac --release 8 -Xlint:-options -nowarn -d "$CP" $(find tests/clustertext -name '*.java') mod/src/hmgapi/mods/wireless/ClusterText.java
java -cp "$CP" hmgapi.mods.wireless.ClusterTextTest
