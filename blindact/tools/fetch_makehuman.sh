#!/usr/bin/env bash
# Fetch the MakeHuman 1.1.1 system assets that tools/build_humans.py dresses
# the two characters with (clothes, shoes, hair, eyebrows, eyelashes, teeth,
# tongue, eyes and two skin textures) into art/makehuman/mh111 (not committed:
# only the built models and textures are).
#
# Source: the Ubuntu archive package makehuman-data 1.1.1. The MakeHuman
# project has released all of these assets (base mesh, proxies, targets,
# textures, MHCLO clothes) under CC0 1.0, see art/makehuman/README.md.
set -euo pipefail
cd "$(dirname "$0")/.."
DST=art/makehuman/mh111
if [ -f "$DST/.complete" ]; then echo "already fetched: $DST"; exit 0; fi
URL=http://archive.ubuntu.com/ubuntu/pool/universe/m/makehuman/makehuman-data_1.1.1-1_all.deb
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "downloading $URL (~260 MB)"
curl -sSL --retry 3 -o "$TMP/mh.deb" "$URL"
mkdir -p "$TMP/x"
if command -v dpkg-deb >/dev/null; then
  dpkg-deb -x "$TMP/mh.deb" "$TMP/x"
else
  (cd "$TMP" && ar x mh.deb && tar -xf data.tar.* -C x)
fi
D="$TMP/x/usr/share/makehuman/data"
mkdir -p "$DST"
for p in clothes/male_casualsuit01 clothes/female_elegantsuit01 clothes/shoes03 \
         hair/short02 hair/long01 eyebrows/eyebrow009 eyebrows/eyebrow010 \
         eyelashes/eyelashes01 eyelashes/eyelashes02 teeth/teeth_base teeth/materials \
         tongue/tongue01 eyes/high-poly eyes/materials; do
  mkdir -p "$DST/$(dirname "$p")"
  cp -r "$D/$p" "$DST/$p"
done
mkdir -p "$DST/skins/textures"
cp "$D/skins/textures/middleage_lightskinned_male_diffuse.png" \
   "$D/skins/textures/young_lightskinned_female_diffuse.png" "$DST/skins/textures/"
touch "$DST/.complete"
du -sh "$DST"
