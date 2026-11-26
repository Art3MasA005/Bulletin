# Launcher icon sources

All three PNGs are rendered from `docs/design/handoff/assets/bulletin-logo.svg`
(logo "2a Peeking Panda, refined"). The SVGs in `source/` are that file with its
C2PA metadata removed, in three framings:

| File | Framing | Used for |
|---|---|---|
| `app_icon.png` | brand tile, corner 27/120 | Android before API 26 |
| `app_icon_ios.png` | full-bleed brand square, no alpha | iOS (the OS applies its own mask) |
| `app_icon_foreground.png` | the mark alone at 62%, transparent | Android adaptive icon, over `#FF7A2E` |

The foreground is scaled to 62% so the mark stays inside the adaptive icon's
66 dp safe zone (of 108 dp) under every launcher mask.

To regenerate after a logo change: render each `source/*.svg` at 1024 x 1024 with a
transparent background (headless Chrome works:
`chrome --headless=new --window-size=1024,1024 --default-background-color=00000000 --screenshot=out.png file.html`
with the SVG inlined in a bare HTML page), copy the PNGs here, then run
`dart run flutter_launcher_icons`.

The in-app mark is NOT one of these PNGs: `lib/core/widgets/bulletin_logo.dart`
paints it from the same SVG coordinates, so it is sharp at every size.
