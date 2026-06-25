# genesi-packageinstaller — integration plan

Genesi fork of [CachyOS/packageinstaller](https://github.com/CachyOS/packageinstaller)
(Qt6 / C++23 + Rust backend). Opened by the Welcome app's "Install programs"
button. Catalog (`pkglist.yaml`) is curated for Genesi with Gaming and local-AI
bundles.

## Status
- [x] Genesi catalog drafted — `pkglist.yaml`
- [x] PKGBUILD drafted (mirrors upstream cmake/llvm recipe + catalog overlay)
- [ ] Fork created: `Genesi-OS/genesi-packageinstaller`  ← **user action**
- [ ] Fork added as submodule `genesi-packageinstaller-full`
- [ ] Branding in the fork: name `genesi-pi`, icon, desktop file, "CachyOS" →
      "Genesi" strings, About text, repo URLs
- [ ] Verify where the app reads `pkglist.yaml` (qrc-compiled vs installed data)
      and confirm the overlay path in the PKGBUILD `prepare()` is right
- [ ] Add `genesi-packageinstaller` to the `PACKAGES` array in
      `.github/workflows/publish-packages.yml`
- [ ] Add the submodule pointer to that workflow's trigger `paths`
- [ ] Add `genesi-packageinstaller` to the ISO package list
      (`genesi-arch/archiso/packages_desktop.x86_64`)
- [ ] First CI build will likely need 1–2 iterations to nail the build/overlay

## Architecture decision
- The **catalog lives in the monorepo** (`genesi-arch/packages/genesi-packageinstaller/pkglist.yaml`)
  so editing it triggers `publish-packages.yml` directly (path `packages/**`) —
  no submodule bump needed to update the app list.
- The **fork holds the branded source**; PKGBUILD overlays our catalog at build
  time, keeping the fork close to upstream for easy merges.

## Build recipe (from upstream)
Qt6 + Rust, built with the llvm/clang stack:
`cmake -GNinja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr` then
`cmake --build build`. makedepends: cmake ninja git polkit-qt6 qt6-tools cargo
lld clang llvm. depends: qt6-base polkit.
