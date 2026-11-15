# PDF Scanner

A free, open source document scanner for iPhone: point the camera at a page, it is captured and cleaned up, and a small PDF is ready to send. No ads, no account, no tracking.

Work in progress: the app is currently a camera spike, comparing our own page detection and auto capture with Apple's scanner.

## Requirements

- Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- An iPhone with iOS 26

## Development

Put your Apple development team in `local.mk`:

```make
PDFSCANNER_DEVELOPMENT_TEAM = ABCDE12345
```

Then:

- `make test`: runs the ScannerKit tests on the Mac and builds the app
- `make install`: builds and installs the app on the first paired iPhone (`IPHONE=<name>` to pick one)
- `make spike-pull`: copies the spike sessions from the iPhone to `build/spike`

## License

MIT, see [LICENSE](LICENSE).
