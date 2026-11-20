MakeHuman data, used only by tools/build_humans.py (this folder is not
exported with the game).

In this folder (committed)
  base.obj, rigs/, targets/, eyes/   the base mesh, default skeleton and
      weights, a few macro / expression targets and the high-poly eye.
      Source: https://github.com/makehumancommunity/makehuman (makehuman/data)

In mh111/ (not committed; fetch with tools/fetch_makehuman.sh)
  The MakeHuman 1.1.1 system assets the two characters wear: clothes
  (male_casualsuit01, female_elegantsuit01, shoes03), hair (short02,
  long01), eyebrows (eyebrow009, eyebrow010), eyelashes (01, 02), teeth,
  tongue, eye materials and two skin textures (middle-aged / young light
  skin). Source: the Ubuntu archive package makehuman-data 1.1.1.

License: the MakeHuman project releases its assets (base mesh, proxies,
targets, textures, MHCLO clothes, poses) under CC0 1.0 Universal; see
LICENSE-CC0.md and section C of
https://github.com/makehumancommunity/makehuman/blob/master/LICENSE.md
(the 1.1.1 package still carries the older AGPL headers in its files; the
project has since relicensed the same assets to CC0).
