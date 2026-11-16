<p align="center">
  <img src="App/Assets.xcassets/Logo.imageset/logo@2x.png" width="120" height="120" alt="Roneograph app icon">
</p>

# Roneograph

A free, open source iPhone scanner for administrative paper: letters, invoices, contracts, payslips, statements. Point the camera at a page and get a clean, small, searchable PDF/A, ready to archive or send. No ads, no account, no tracking.

The [manifesto](MANIFESTO.md) says what Roneograph is for and how features are chosen.

[Download Roneograph on the App Store](https://apps.apple.com/app/id6835211020).

## What it does

Capturing:

- Opens on the camera and captures a page on its own once it is held still; a Manual mode leaves it to the shutter.
- Captures each page once: turning pages in a pile does not take the same page twice.
- Tells you what to fix: move closer or farther, more light, a dirty lens; a flash helps in dark rooms.
- Adds pages to a scan at any time, even days later.

Cleaning up:

- Cuts the page out of the photo and flattens it, even when it was shot at an angle.
- Turns the page upright from the direction of its text, and straightens slightly tilted text.
- Removes shadows, whitens the paper and keeps faint ink, pencil, stamps and signatures.
- Makes pages gray, or color when they have color; each page can be switched.
- Fixes a wrong outline on the original photo, with corners that snap and a magnifier.

The PDF:

- Gives pages their real paper size: A4 or Letter from their proportions, otherwise estimated from the size of the text.
- Makes every PDF searchable, with the recognized text invisible under each page.
- Writes PDF/A, the ISO standard for long-term archiving, and shows the file size before sending.

Naming:

- Suggests a name from the text, such as the document type, the sender and its number.
- Reads the details of the document: its category (invoice, payslip, tax notice, or one of your own), its issuer, the date printed on it and its reference number; you can change any of them.
- Remembers a corrected name, issuer and category and reuses them for the next documents from the same issuer; a month, date or number in your name follows the next document. Remembered values are marked on the review screen and can be forgotten there or in Settings.
- Follows your file name format: date first or last, in three formats, from the document or the scan day, with spaces, dashes or underscores, lowercase or not.
- Or a custom format built from variables, such as `{CATEGORY}/{YYYY}-{MM} {ISSUER}`, which can file scans into folders.

Sending:

- Email fills in your default address, the name as the subject and the PDF; you only tap Send.
- Save to Files puts the PDF in a folder picked once, or in the folders of a custom format inside it, without replacing a file already there.
- Share reaches any other app.
- Selecting several scans on Home sends them at once, all PDFs in one email; a shortcut selects the scans not sent yet.
- Keeps scans 1, 7 or 30 days, or forever, visible in Files.

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
