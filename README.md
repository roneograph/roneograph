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

The simulator has no camera: in Debug builds, set `RONEOGRAPH_SAMPLE_PHOTOS` to a folder of photos to scan them on launch. Page detection is less reliable in the simulator than on a device.

`ScannerKit/` holds the scanning logic and its tests; `page-cleanup` (`swift run -c release page-cleanup <output> <images...>` in `ScannerKit/`) runs the cleanup and the PDF writer on any images.

## License

MIT, see [LICENSE](LICENSE).
