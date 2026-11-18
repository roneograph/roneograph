# Privacy policy

Last updated: November 18, 2026

Roneograph collects no data: nothing you scan or type is ever sent to us or to anyone else. What the app needs to work is kept on your iPhone only, and a PDF goes only where you send it.

## What stays on your iPhone

- **Scans.** The photos you take, the cleaned pages, the text read on them, the details found in that text (document type, issuer, date, reference number, owner) and the comment you add are kept in the app's private storage. The PDFs are kept in the app's folder, which the Files app shows under On My iPhone › Roneograph.
- **Settings.** Owners with the names and addresses their mail is sent to (kept as text, to recognize the owner of a page and never take these lines for the issuer), file name formats, your own document types, and the address and storage path of the Paperless-ngx server connected for Archive. Its API token is kept in the iPhone's Keychain, for this iPhone only.
- **Corrections.** The names, issuers, document types and owners you correct are kept to be reused for the next documents from the same issuer, with what identifies the issuer on the page, such as its web or email domain or its company number.

Like any app data, all of this except the Paperless token is part of your iPhone's iCloud or computer backup, if you make one.

## How it is used

- **Camera.** The camera is used only to capture the pages you scan, while the scanner is open.
- **Local network.** iOS asks for it only when the Paperless-ngx server you connect is on your local network; the app uses it only to reach that server.
- **Text recognition.** The text of the pages is read on your iPhone, to suggest a file name, to find the details of the document and its owner, and to add an invisible text layer to the PDF so it can be searched. The text is kept with the scan, so a page is read only once, and is deleted with it.
- **No servers of ours.** Roneograph has no servers, no analytics, no crash reporting, no ads, no tracking and no account. The app connects to the network only to reach the Paperless-ngx server you connected: to check its address and token and list its storage paths when you connect it, and when you archive a PDF, to find the correspondent and the document type named like its issuer and its document type, and the Owner and Comment custom fields, create them when missing, and upload the PDF. It never reads, lists or downloads your documents there.

## Sharing

A PDF leaves your iPhone only when you send it: with Share, to the app or recipient you pick, or with Archive, to the Paperless-ngx server you connected, with its title, the date of the document, its issuer, its document type, the name of its owner and its comment. The comment is also written in the PDF, as its subject. An upload that cannot reach the server is tried again later, until it is delivered or you delete the scan. From then on, that app or service handles it under its own privacy policy. Roneograph shares nothing with anyone else.

## How long it is kept, and deleting it

- Scans you sent are deleted from your iPhone 24 hours after they were sent, when the app next comes back to the front. A scan is sent once the Paperless-ngx server took it (an upload waiting or failed is kept) or once the share sheet completed, whatever the destination. Scans never sent stay until you delete them. Delete a scan at any time from the app. PDFs you archived or shared are not affected.
- Corrections are kept until you forget them: Settings › Memory shows what is remembered for each issuer, and forgets one issuer or everything.
- Settings are kept until you change them: delete a name or an address, disconnect Paperless, or delete an owner.
- Deleting the app deletes everything it kept, except a Paperless token, which iOS keeps in the Keychain: disconnect Paperless before deleting the app to delete it, otherwise it is deleted when the app is installed again.

As we hold no data about you, there is nothing to ask us to delete.

## Open source

The app is open source under the MIT license, so all of this can be checked in its source code.

Questions: https://github.com/roneograph/roneograph/issues (the issues are public: never attach your documents).
