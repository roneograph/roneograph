<p align="center">
  <img src="App/Assets.xcassets/Logo.imageset/logo@2x.png" width="120" height="120" alt="Roneograph app icon">
</p>

# Roneograph

A free, open source iPhone scanner for administrative paper: letters, invoices, contracts, payslips, statements. Point the camera at a page and get a clean, small, searchable PDF/A, ready to archive or send. No ads, no account, no tracking.

The [manifesto](MANIFESTO.md) says what Roneograph is for and how features are chosen.

[Download Roneograph on the App Store](https://apps.apple.com/app/id6835211020).

## What it does

Capturing:

- Scan opens the camera, which captures a page on its own once it is held still; a Manual mode leaves it to the shutter.
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
- Keeps files small without changing a letter: gray pages of text in 16 gray levels compressed without loss, pictures and color pages as JPEG.
- Makes every PDF searchable, with the recognized text invisible under each page.
- Writes PDF/A, the ISO standard for long-term archiving, and shows the file size before sending.

Naming:

- Suggests a name from the text, such as the document type, the sender and its number.
- Reads the details of the document: its document type (invoice, payslip, tax notice, or one of your own), its issuer, the date printed on it and its reference number; you can change any of them.
- For an owner connected to Paperless, the server is the source of correspondents and document types: an issuer takes the name of the correspondent it stands for, whatever its case, accents, punctuation, legal form or spaces between words. An issuer read on the page also takes it when one name holds the other as whole words (such as "Taxi V7" for "V7", and the most specific of nested names it holds), unless several could be meant or the name is too short to tell; one you typed stays as typed (such as "Lumen Bank" next to "Lumen"), and archiving adds it as a new correspondent. A document type takes the name of the server's, and the document type menu offers the server's instead of your own.
- While you type an issuer, the review screen suggests the correspondents of the server; an issuer or document type that archiving would add to Paperless is marked New, so a duplicate is caught before sending.
- Remembers a corrected name, issuer and document type and reuses them for the next documents from the same issuer, named like the Paperless correspondent and document type they stand for (an issuer only when it differs from the correspondent's name cosmetically); a month, date or number in your name follows the next document. Remembered values are marked on the review screen and can be forgotten there or in Settings.
- Follows your file name format: date first or last, in three formats, from the document or the scan day, with spaces, dashes or underscores, lowercase or not.
- Or a custom format built from variables, such as `{YYYY}-{MM} {TYPE} {ISSUER}`; the format editor shows what each part gives for a sample invoice.
- The file name is the name of the shared PDF and its original file name in Paperless.

Sending:

- Two ways out: Archive, the main one, sends the PDF to the owner's Paperless-ngx server in one tap once it is connected; Share opens the iOS share sheet for everything else, such as Mail or Files.
- A comment on a scan, such as who was at a lunch, is written in the PDF as its subject, and sent along in a Comment custom field on Paperless.
- The review screen shows at most three buttons: Archive by name (or Share until the owner is connected), the other one, and Delete; a Connect Paperless link sits under the buttons until an owner is connected. A button tapped while the PDF is still being made sends as soon as it is ready.
- Once a scan is sent, a status line on the review screen says how and when, and when it leaves the iPhone.
- New Scan on the review screen starts the next document of a pile right away.
- On Home, swipe a scan from the left to send it: Archive first, which a full swipe does, then Share, also for a scan already sent. Swipe from the right to delete it.
- When more than one scan is not sent, a card at the top of Home archives them all in one tap with Archive All, or offers Share All when the owners are not all connected to Paperless.
- Owners keep your own paper apart from a company's you scan for: each owner has its names, addresses, Paperless server and file name format, and a document gets the owner whose name or address is printed at the top of the page (with or without civility, initials or legal form), or the one remembered for its issuer, or the default one.
- Archive uploads PDFs to a Paperless-ngx server, one per owner, into the storage path picked for the owner, with their title, date, issuer as correspondent, document type, owner's name in an Owner custom field and comment in a Comment one (each created when missing, the fields from Paperless-ngx 2.19; correspondents and document types with Auto matching, so Paperless also learns them for documents that come another way), so a single storage path such as `{{ custom_fields|get_cf_value('Owner', 'unsorted') }}/{{ document_type }}/{{ original_name }}` can sort documents by owner; uploads go on in the background and are tried again until the server takes them. The Paperless setup lists the placeholders that read each field and storage paths to copy.
- Reads the correspondents and document types of each connected owner's server at launch, when the app comes back after a while, once an owner is connected and when you pull down Home or the review screen; it keeps them for when the server cannot be reached, and an upload reads them again once per launch.
- Keeps a scan that was not sent until you delete it, visible in Files; a sent scan is deleted from the iPhone 24 hours after it was sent. Sent means archived, once the Paperless server took it (a waiting or failed upload is kept), or shared, once the share sheet completed, whatever the destination.

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
- `make ui-test`: runs the UI tests on an iOS simulator (`SIMULATOR=<name>` to pick one, iPhone 17 Pro Max by default)
- `make install`: builds and installs the app on the first paired iPhone (`IPHONE=<name>` to pick one)
- `make scans-pull`: copies the scans from the iPhone to `build/scans`, to tune the page cleanup on real pages
- `make app-icon-preview`: renders the app icon in every appearance to `build/app-icon`

The app icon is drawn in `tools/app-icon.svg`; export it to a 1024 × 1024 PNG without transparency as `App/AppIcon.icon/Assets/icon.png`, then resize it to 120, 240 and 360 px for the home screen logo in `App/Assets.xcassets/Logo.imageset`; the 360 px one is also `website/icon.png`.

The simulator has no camera: in Debug builds, set `RONEOGRAPH_SAMPLE_PHOTOS` to a folder of photos to scan them on launch. Page detection is less reliable in the simulator than on a device.

`website/` holds the static site of [roneograph.org](https://roneograph.org), deployed to GitHub Pages on every push to `main`.

`ScannerKit/` holds the scanning logic and its tests; `page-cleanup` (`swift run -c release page-cleanup <output> <images...>` in `ScannerKit/`) runs the cleanup and the PDF writer on any images.

## Privacy

Roneograph collects nothing; see [PRIVACY.md](PRIVACY.md).

## License

MIT, see [LICENSE](LICENSE).
