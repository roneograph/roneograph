# Privacy policy

Last updated: November 17, 2026

Roneograph collects no data: nothing you scan or type is ever sent to us or to anyone else. What the app needs to work is kept on your iPhone only, and a PDF goes only where you send it.

## What stays on your iPhone

- **Scans.** The photos you take, the cleaned pages and the details found on them (category, issuer, date, reference number, owner) are kept in the app's private storage. The PDFs are kept in the app's folder, which the Files app shows under On My iPhone › Roneograph.
- **Settings.** Your email addresses, owners, file name formats, your own categories, how long scans are kept, the folder picked for Save to Files (a reference to it, not a copy), and the address and storage path of the Paperless-ngx server connected for Archive. Its API token is kept in the iPhone's Keychain, for this iPhone only.
- **Corrections.** The names, issuers, categories and owners you correct are kept to be reused for the next documents from the same issuer, with what identifies the issuer on the page, such as its web or email domain or its company number. To recognize your own name and address, and never take them for the issuer, the app keeps fingerprints of the lines that come back on your documents, not their text; each scan keeps the fingerprints of its own header lines. With several owners, these fingerprints are linked to the owners of the documents you send, to recognize the owner of the next ones.

Like any app data, all of this except the Paperless token is part of your iPhone's iCloud or computer backup, if you make one.

## How it is used

- **Camera.** The camera is used only to capture the pages you scan, while the scanner is open.
- **Text recognition.** The text of the pages is read on your iPhone, to suggest a file name, to find the details of the document and its owner, and to add an invisible text layer to the PDF so it can be searched. The text itself is kept only inside the PDF.
- **No servers of ours.** Roneograph has no servers, no analytics, no crash reporting, no ads, no tracking and no account. The app connects to the network only to reach the Paperless-ngx server you connected: to check its address and token and list its storage paths when you connect it, and when you archive a PDF, to find the document type named like its category, create it when missing, and upload the PDF. It never reads, lists or downloads your documents there.

## Sharing

A PDF leaves your iPhone only when you send it: with Email or Share, to the recipient or app you pick, with Save to Files, to the folder you picked, or with Archive, to the Paperless-ngx server you connected, with its title, the date of the document and its category. An upload that cannot reach the server is tried again later, until it is delivered or you delete the scan. From then on, that app or service handles it under its own privacy policy. Roneograph shares nothing with anyone else.

## How long it is kept, and deleting it

- Scans you sent or saved with Save to Files are deleted after the time chosen in Settings › Keep sent scans for (7 days by default, or 1 day, 30 days or Forever), counted from when they were sent, the next time the app is opened. Scans never sent stay until you delete them. Delete a scan at any time from the app, or all of them with Settings › Delete All Scans. PDFs you sent or saved with Save to Files are not affected.
- Corrections and fingerprints are kept until you forget them: Settings › Memory shows what is remembered for each issuer, and forgets one issuer or everything.
- Settings are kept until you change them: clear an email address, forget the folder, disconnect Paperless, or delete an owner.
- Deleting the app deletes everything it kept.

As we hold no data about you, there is nothing to ask us to delete.

## Open source

The app is open source under the MIT license, so all of this can be checked in its source code.

Questions: https://github.com/roneograph/roneograph/issues (the issues are public: never attach your documents).
