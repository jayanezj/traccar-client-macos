# Application artwork

`AppIcon.svg` is the vector master for the application icon. The circular Traccar mark remains dominant; the small Apple silhouette is transparent negative space within the lower-left dish.

The integrated master uses the agreed solid green `#2d7930`. It preserves the approved vector paths and canvas. The Xcode asset catalog contains the generated macOS application icon slots (16–1024 pixels) and a monochrome 18-point menu-bar template at 1× and 2×.

The About panel uses the bundled application icon. The menu-bar template follows system appearance and retains the artwork's transparent cutouts.

## Regeneration

Normal Xcode builds use the checked-in assets and require no additional packages. To regenerate after editing the SVG, run `node scripts/generate-icons.cjs` from the repository with Node.js and the `sharp` package available. If installed outside this repository, set `NODE_PATH` to that installation's `node_modules` directory. The initial asset generation used sharp 0.35.5.

The generator writes `TraccarClient/Resources/Assets.xcassets`. Each size is rasterized directly from the vector master. Preserve the SVG as the editable source.
