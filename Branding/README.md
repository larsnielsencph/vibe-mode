# VibeMode identity

`AppIcon.png` is the shared 1024 × 1024 master: a white rocket, charcoal background and a small gray flame. The website and product animations use the same artwork as the app.

After replacing the master on macOS, run:

```sh
./scripts/sync-brand-icons.sh
```

This generates every size declared in the macOS asset catalog. When the local `landingpage` Sites checkout is present, it also refreshes its favicon, touch icon, header/footer icon and both HyperFrames source images. Re-render the two animations after updating their images.

The menu bar retains macOS template symbols: `moon.zzz` for Normal and `bolt.horizontal.fill` for Vibe. These remain monochrome, adapt to the menu bar appearance and communicate the current state.
