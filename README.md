# Roneograph

A free, open source document scanner for iPhone: point the camera at a page, it is captured and cleaned up, and a small PDF is ready to send. No ads, no account, no tracking.

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
- `make screenshots`: takes the App Store screenshots in the iPhone 17 Pro Max simulator, from the fake documents in `tools/sample-photos`
- `make app-icon-preview`: renders the app icon in every appearance to `build/app-icon`
- `make testflight`: runs the tests, archives a Release build and uploads it to App Store Connect

The app icon is drawn in `tools/app-icon.svg`; export it to a 1024 × 1024 PNG without transparency as `App/AppIcon.icon/Assets/icon.png`.

The simulator has no camera: in Debug builds, set `RONEOGRAPH_SAMPLE_PHOTOS` to a folder of photos to scan them on launch. Page detection is less reliable in the simulator than on a device.

`ScannerKit/` holds the scanning logic and its tests; `page-cleanup` (`swift run -c release page-cleanup <output> <images...>` in `ScannerKit/`) runs the cleanup and the PDF writer on any images.

## Privacy

Roneograph collects nothing and never connects to the network; see [PRIVACY.md](PRIVACY.md).

## License

MIT, see [LICENSE](LICENSE).
