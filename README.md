# VisibleIsland — iOS 15 metadata test build

This is the **exact same compiled binary** as `com_ethxnn88_visibleisland_2_0_iphoneos-arm64.deb`
you uploaded — byte-for-byte identical `data.tar.lzma` (verified). The only
change is the `control` file's `Depends:` line, from `firmware (>= 16.0)` to
`firmware (>= 15.0)`, plus a `-ios15test1` version suffix so it's clearly
distinguishable and won't collide with a future real update.

## Why this exists

VisibleIsland works by unhiding/repositioning Apple's own native Dynamic
Island renderer (`SBSystemApertureWindow`, `_SBGainMapView`, etc.) — classes
Apple only ships from iOS 16 onward, for the iPhone 14 Pro's camera-cutout
hardware. Those classes almost certainly don't exist in iOS 15's SpringBoard
at all, since Dynamic Island didn't exist yet. Logos `%hook` targets that
don't resolve at runtime just get silently skipped — no crash — so the
realistic outcome here is: **installs fine, does nothing.**

## What to actually check when you test it

1. Install it (`dpkg -i ...` over SSH, or via Filza) and respring.
2. Does it install without errors? (Expected: yes, since it's already
   rootless-pathed and the firmware constraint is now satisfied.)
3. Does the Dynamic Island toggle in the tweak's Settings page do anything
   visually? (Expected: no change at all.)
4. If you *do* see any visual effect — even a glitch — that's a genuinely
   useful data point and worth telling me, since it would mean iOS 15
   carries some remnant of that class hierarchy I didn't account for.

## Uninstalling

Same as any tweak: remove "VisibleIsland" from Sileo/Zebra, or
`dpkg -r com.ethxnn88.visibleisland` over SSH.
