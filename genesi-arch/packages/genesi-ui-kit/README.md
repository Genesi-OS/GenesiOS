# genesi-ui-kit

The **canonical source** for Genesi's shared QML design components — the single
place to edit the look that the Genesi Qt6/QML apps share:

- `components/Theme.qml` — brand palette + helpers (the union of what all apps
  need; instantiate once per root as `Theme { id: theme }`).
- `components/GlassCard.qml` — dark "glass" surface card (sheen + depth + hover
  lift), shader-free.
- `components/GButton.qml` — branded custom-drawn button (filled/tonal/ghost/
  danger) with press feedback.
- `components/StatusBanner.qml` — accent-tinted inline status banner with an
  optional action button.

## This is intentionally NOT a standalone package

It is **not** built or published by the pipeline (it has no `PKGBUILD`, so it's
skipped by both the dependency pre-install glob and the explicit `PACKAGES`
build list). Instead, **each consuming app's `PKGBUILD` copies the components it
uses into its own tree at build time**, e.g.:

```sh
KIT="${startdir}/../genesi-ui-kit/components"
for comp in Theme GlassCard GButton StatusBanner; do
    install -Dm644 "$KIT/${comp}.qml" \
        "$pkgdir/usr/share/<app>/app/${comp}.qml"
done
```

Why bundle instead of ship a real `genesi-ui-kit` package the apps `import`?
Because the build pipeline pre-installs every Genesi package's declared
`depends` with `pacman -S` before building — so **no Genesi package may depend on
another Genesi package built in the same run** (it isn't in any repo yet and the
install fails). Bundling at build keeps ONE source to edit while leaving each app
self-contained at runtime, with no inter-package dependency, no `PACKAGES`/ISO
wiring, and nothing extra to install.

## Polish must stay SHADER-FREE

No `QtQuick.Effects` `MultiEffect` / `DropShadow` / `ShaderEffect`: the apps fall
back to `QT_QUICK_BACKEND=software` inside VMs, where shader effects render blank.
Use gradients, 2D transforms (Translate/scale) and colour animations only.

## Consumers

- `genesi-ai-mode` (AI Mode Monitor) — Theme, GlassCard
- `genesi-sandboxes` — Theme, GlassCard, GButton, StatusBanner
- `genesi-netinspect` (API Inspector) — Theme, GlassCard
