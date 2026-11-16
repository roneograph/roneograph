<p align="center">
  <img src="App/Assets.xcassets/Logo.imageset/logo@2x.png" width="120" height="120" alt="Roneograph app icon">
</p>

# Roneograph

A free, open source iPhone scanner for administrative paper: letters, invoices, contracts, payslips, statements. Point the camera at a page and get a clean, small PDF/A, ready to archive or send. No ads, no account, no tracking.

The [manifesto](MANIFESTO.md) says what Roneograph is for and how features are chosen.

[Download Roneograph on the App Store](https://apps.apple.com/app/id6835211020).

## Requirements

- Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- An iPhone with iOS 26

## Development

Put your Apple development team in `local.mk`:

```make
RONEOGRAPH_DEVELOPMENT_TEAM = ABCDE12345
```

Then:

- `make test`: runs the ScannerKit tests on the Mac and builds the app
- `make install`: builds and installs the app on the first paired iPhone (`IPHONE=<name>` to pick one)
- `make scans-pull`: copies the scans from the iPhone to `build/scans`, to tune the page cleanup on real pages
- `make app-icon-preview`: renders the app icon in every appearance to `build/app-icon`

The app icon is drawn in `tools/app-icon.svg`; export it to a 1024 × 1024 PNG without transparency as `App/AppIcon.icon/Assets/icon.png`, then resize it to 120, 240 and 360 px for the home screen logo in `App/Assets.xcassets/Logo.imageset`.

The simulator has no camera: in Debug builds, set `RONEOGRAPH_SAMPLE_PHOTOS` to a folder of photos to scan them on launch. Page detection is less reliable in the simulator than on a device.

`ScannerKit/` holds the scanning logic and its tests; `page-cleanup` (`swift run -c release page-cleanup <output> <images...>` in `ScannerKit/`) runs the cleanup and the PDF writer on any images.

## Privacy

Roneograph collects nothing and never connects to the network; see [PRIVACY.md](PRIVACY.md).

## License

MIT, see [LICENSE](LICENSE).
