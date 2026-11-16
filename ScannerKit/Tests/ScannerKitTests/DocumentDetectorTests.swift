import CoreGraphics
import Foundation
import ScannerKit
import ScannerKitTesting
import Testing

struct DocumentDetectorTests {
    let detector = DocumentDetector(monthFirst: false)

    // MARK: Corpus

    @Test func reportsHitRatesOnTheCorpus() {
        let report = CorpusReport(documents: DocumentCorpus.documents)
        let learned = CorpusReport(documents: DocumentCorpus.documents, ownLines: DocumentCorpus.ownLines)
        let holdout = CorpusReport(documents: DocumentCorpus.holdout)
        print("First scans:\n\(report.table)\n\(report.misses.joined(separator: "\n"))")
        print("With the user's own lines learned:\n\(learned.table)")
        print("Holdout:\n\(holdout.table)\n\(holdout.misses.joined(separator: "\n"))")
        #expect(report.rate("issuer") >= 0.9)
        #expect(report.rate("date") >= 0.95)
        #expect(report.rate("number") >= 0.95)
        #expect(holdout.rate("issuer") >= 0.8)
        #expect(holdout.rate("date") >= 0.8)
        #expect(holdout.rate("number") >= 0.8)
    }

    @Test(arguments: DocumentCorpus.documents + DocumentCorpus.holdout)
    func detectsTheCategoryOfEveryCorpusDocument(document: CorpusDocument) {
        let detected = DocumentDetector(monthFirst: document.monthFirst).detect(lines: document.lines, aspectRatio: document.aspectRatio)
        #expect(detected.details.category == document.category)
    }

    @Test func theCorpusCoversEveryCategoryInEveryLanguage() {
        for language in ["en", "fr", "de", "es", "it"] {
            let categories = Set(DocumentCorpus.documents.filter { $0.language.hasPrefix(language) }.map(\.category))
            #expect(categories == Set(DocumentCategory.builtIn), "\(language)")
        }
    }

    @Test func detectionIsDeterministic() {
        for document in DocumentCorpus.documents {
            #expect(detector.detect(lines: document.lines) == detector.detect(lines: document.lines.reversed()))
        }
    }

    // MARK: Category

    @Test(arguments: [
        ("ATTESTATION D'ASSURANCE HABITATION", DocumentCategory.insurance),
        ("CERTIFICATE OF MOTOR INSURANCE", .insurance),
        ("Arbeitsunfähigkeitsbescheinigung", .medical),
        ("CERTIFICATO DI ASSICURAZIONE", .insurance),
        ("FACTURA SIMPLIFICADA", .receipt),
        ("Stromrechnung", .invoice),
    ])
    func aMoreSpecificPhraseWins(title: String, category: DocumentCategory) {
        #expect(detector.detect(lines: [line(title, y: 0.2, height: 0.02), line("Lorem ipsum", y: 0.3)]).details.category == category)
    }

    @Test func aLetterLosesToACategoryWithEvidence() {
        let letter = [
            line("Objet : votre consommation", y: 0.3),
            line("Madame,", y: 0.35),
            line("Veuillez agréer, Madame, nos salutations distinguées.", y: 0.45),
        ]
        #expect(detector.detect(lines: letter).details.category == .letter)
        let invoice = letter + [line("FACTURE", y: 0.2, height: 0.02), line("Total TTC", y: 0.4)]
        #expect(detector.detect(lines: invoice).details.category == .invoice)
    }

    @Test func aTitleWordInASentenceIsNotATitle() {
        let lines = [line("Veuillez trouver ci-joint votre facture du mois de mars et une copie de votre contrat.", y: 0.3)]
        #expect(detector.detect(lines: lines).details.category == .other)
        #expect(detector.detect(lines: lines).parts.type == nil)
    }

    @Test func theEndOfAWrappedSentenceIsNotATitle() {
        let lines = [
            line("Objet : votre consommation", y: 0.25),
            line("Madame,", y: 0.3),
            line("Nous avons relevé votre compteur le 3 mars et ajusté votre consommation selon les", y: 0.4),
            line("conditions de votre contrat de fourniture.", y: 0.413),
            line("Veuillez agréer, Madame, nos salutations distinguées.", y: 0.5),
        ]
        #expect(detector.detect(lines: lines).details.category == .letter)
    }

    @Test func narrowPagesLeanTowardsReceipts() {
        let lines = [line("PAIN DE CAMPAGNE 3,20", y: 0.1), line("CB SANS CONTACT 3,20", y: 0.2)]
        #expect(detector.detect(lines: lines).details.category == .other)
        #expect(detector.detect(lines: lines, aspectRatio: 0.35).details.category == .receipt)
    }

    // MARK: Issuer

    @Test func neverTakesTheUserOwnLinesAsTheIssuer() {
        let lines = [line("Jordan Ellery", y: 0.04, height: 0.03), line("Northwind Analytics", y: 0.1, height: 0.012), line("Lorem ipsum", y: 0.5)]
        #expect(detector.detect(lines: lines).details.issuer == "Jordan Ellery")
        let detected = detector.detect(lines: lines, ownLines: [DocumentDetector.fingerprint("JORDAN ELLERY")])
        #expect(detected.details.issuer == "Northwind Analytics")
        #expect(detected.headerLines == ["Jordan Ellery", "Northwind Analytics"].map(DocumentDetector.fingerprint))
    }

    @Test func prefersANameWithALegalForm() {
        let lines = [line("Bright Ideas", y: 0.04, height: 0.018), line("LUMEN ÉNERGIE SAS", y: 0.08), line("Lorem ipsum", y: 0.5)]
        #expect(detector.detect(lines: lines).details.issuer == "Lumen Énergie")
    }

    @Test func capitalizesNamesWrittenInOneCase() {
        #expect(detector.detect(lines: [line("northfield power", y: 0.04, height: 0.03)]).details.issuer == "Northfield Power")
        #expect(detector.detect(lines: [line("CAISSE DES ÉCOLES DE LYON", y: 0.04, height: 0.03)]).details.issuer == "Caisse des Écoles de Lyon")
    }

    @Test func readsANameWrappedOnSeveralLinesAsOne() {
        let lines = [
            line("Cabinet", y: 0.08, height: 0.02),
            line("d'Orthodontie", y: 0.101, height: 0.025),
            line("de la Butte", y: 0.127, height: 0.02),
            line("Lorem ipsum", y: 0.5),
        ]
        #expect(detector.detect(lines: lines).details.issuer == "Cabinet d'Orthodontie de la Butte")
    }

    @Test func readsACenteredNameWrappedOnSeveralLinesAsOne() {
        let lines = [
            TextLine(text: "Maison", frame: CGRect(x: 0.2, y: 0.05, width: 0.2, height: 0.02)),
            TextLine(text: "d'Horlogerie", frame: CGRect(x: 0.15, y: 0.071, width: 0.3, height: 0.02)),
            TextLine(text: "de Vence", frame: CGRect(x: 0.22, y: 0.092, width: 0.16, height: 0.02)),
            line("Lorem ipsum", y: 0.5),
        ]
        #expect(detector.detect(lines: lines).details.issuer == "Maison d'Horlogerie de Vence")
    }

    @Test func takesALogoReadUncertainlyWhenTheWebDomainConfirmsIt() {
        let lines = [
            TextLine(text: "VeRDaLiS", frame: CGRect(x: 0.08, y: 0.03, width: 0.2, height: 0.03), confidence: 0.5),
            TextLine(text: "Urgent", frame: CGRect(x: 0.75, y: 0.1, width: 0.12, height: 0.02)),
            line("Lorem ipsum", y: 0.5),
            line("www.verdalis.fr", y: 0.95),
        ]
        #expect(detector.detect(lines: lines).details.issuer == "Verdalis")
        #expect(detector.detect(lines: Array(lines.dropLast())).details.issuer != "Verdalis")
    }

    @Test func aDomainSharingOneWordDoesNotConfirmALogoReadUncertainly() {
        let lines = [
            line("CHAMBRE DES MÉTIERS", y: 0.04, height: 0.012),
            TextLine(text: "_ DE LA METROPOLE E", frame: CGRect(x: 0.1, y: 0.06, width: 0.2, height: 0.02), confidence: 0.5),
            line("Lorem ipsum", y: 0.5),
            line("contact@artisans-metropole.fr", y: 0.95),
        ]
        #expect(detector.detect(lines: lines).details.issuer == "Chambre des Métiers")
    }

    @Test func leavesOutTheLoneLettersOfALogo() {
        let lines = [
            TextLine(text: "Q Verdalis Énergie", frame: CGRect(x: 0.08, y: 0.03, width: 0.3, height: 0.03), confidence: 0.5),
            line("Lorem ipsum", y: 0.5),
            line("www.verdalis-energie.fr", y: 0.95),
        ]
        #expect(detector.detect(lines: lines).details.issuer == "Verdalis Énergie")
    }

    @Test func dropsAPeriodEndingTheIssuerButNotAnAbbreviation() {
        #expect(detector.detect(lines: [line("Caisse des Retraites.", y: 0.04, height: 0.03)]).details.issuer == "Caisse des Retraites")
        #expect(detector.detect(lines: [line("Garage Leroy et Cie.", y: 0.04, height: 0.03)]).details.issuer == "Garage Leroy et Cie.")
    }

    @Test func neverTakesALineStartingWithDeAsTheIssuer() {
        let lines = [line("Cabinet", y: 0.08, height: 0.02), line("de la Butte", y: 0.2, height: 0.03), line("Lorem ipsum", y: 0.5)]
        #expect(detector.detect(lines: lines).details.issuer == "Cabinet")
    }

    @Test func neverTakesTheEndOfAWrappedSentenceAsTheIssuer() {
        let lines = [
            line("Objet : Relevé de vos consommations", y: 0.25, height: 0.012),
            line("d'électricité.", y: 0.265, height: 0.01),
            line("Madame,", y: 0.3),
        ]
        #expect(detector.detect(lines: lines).details.issuer == nil)
    }

    @Test func prefersTheNameOfTheWebDomain() {
        let lines = [line("Atelier Nord", y: 0.04), line("Maison Ferlac", y: 0.06), line("Lorem ipsum", y: 0.5), line("www.maison-ferlac.fr · contact@gmail.com", y: 0.95)]
        let detected = detector.detect(lines: lines)
        #expect(detected.details.issuer == "Maison Ferlac")
        #expect(detected.issuerKeys == ["maison-ferlac.fr", "maison ferlac"])
    }

    @Test func ignoresMailProviders() {
        let lines = ["jo@gmail.com", "info@orange.fr", "a.b@web.de", "x@hotmail.co.uk", "y@yahoo.it", "z@icloud.com", "w@free.fr", "v@laposte.net", "u@gmx.de", "t@outlook.es"]
            .enumerated().map { line($1, y: 0.05 + Double($0) * 0.02) }
        #expect(detector.detect(lines: lines).issuerEvidence.isEmpty)
    }

    @Test(arguments: [
        ("SIRET 123 456 789 00012", ["123456789"]),
        ("RCS Lyon 123 456 789", ["123456789"]),
        ("N° TVA intracommunautaire : FR 12 123 456 789", ["FR12123456789", "123456789"]),
        ("USt-IdNr. DE123456789 · Amtsgericht Leipzig HRB 12345", ["DE123456789", "HRB12345"]),
        ("VAT Reg No. GB 123 4567 89 · Company No. 01234567", ["GB123456789", "CRN01234567"]),
        ("C.F. e P.IVA 01234567890", ["IT01234567890"]),
        ("CIF: B12345678", ["ESB12345678"]),
        ("IBAN FR76 0000 0000 0000 0000 0000 000", []),
    ])
    func readsCompanyIdentifiers(text: String, identifiers: [String]) {
        #expect(detector.detect(lines: [line(text, y: 0.95)]).issuerEvidence == identifiers)
    }

    @Test func listsDomainsThenIdentifiersThenTheName() {
        let lines = [
            line("VOLTARIA ÉNERGIE", y: 0.04, height: 0.03),
            line("FACTURE", y: 0.2, height: 0.02),
            line("Voltaria Énergie SAS · SIRET 123 456 789 00012 · TVA FR12 123456789 · www.voltaria-energie.fr", y: 0.95, height: 0.008),
        ]
        let detected = detector.detect(lines: lines)
        #expect(detected.details.issuer == "Voltaria Énergie")
        #expect(detected.issuerKeys == ["voltaria-energie.fr", "123456789", "FR12123456789", "voltaria energie"])
        #expect(detected.issuerEvidence == ["voltaria-energie.fr", "123456789", "FR12123456789"])
        #expect(detected.headerLines == [DocumentDetector.fingerprint("VOLTARIA ÉNERGIE")])
    }

    @Test func usesTheNameBeforeALegalFormWithoutAHeader() {
        let lines = [
            line("Mr Jordan Ellery", y: 0.15),
            line("Your bill", y: 0.25, height: 0.02),
            line("Lorem ipsum", y: 0.5),
            line("Brightwater Broadband Ltd · Registered in England and Wales No. 01234567", y: 0.94, height: 0.008),
        ]
        #expect(detector.detect(lines: lines).details.issuer == "Brightwater Broadband")
    }

    @Test func prefersANameWithEvidenceOverAPlainHeaderLine() {
        let lines = [
            line("Service clients", y: 0.04),
            line("Lorem ipsum", y: 0.5),
            line("Brightwater Broadband Ltd · Company No. 01234567", y: 0.94, height: 0.008),
        ]
        #expect(detector.detect(lines: lines).details.issuer == "Brightwater Broadband")
    }

    @Test func breaksTiesWithOrganizationNames() {
        let header = [line("Jordan Ellery", y: 0.04), line("Corvane Analytics", y: 0.05)]
        #expect(detector.detect(lines: header + [line("Lorem ipsum", y: 0.5)]).details.issuer == "Jordan Ellery")
        #expect(detector.detect(lines: header + [line("Thank you for choosing Corvane Analytics.", y: 0.5)]).details.issuer == "Corvane Analytics")
    }

    // MARK: Date

    @Test(arguments: [
        ["Valable jusqu'au 30/04/2026", "Date d'échéance : 28/03/2026", "Période du 01/02/2026 au 28/02/2026", "Née le 12/06/1991", "Date de facture : 14/03/2026"],
        ["Due date: 28 March 2026", "Valid until 30 April 2026", "Date of birth: 04/11/1998", "Billing period 1 February 2026 to 28 February 2026", "Invoice date: 14 March 2026"],
        ["Zahlbar bis 28.03.2026", "Geburtsdatum 03.11.1992", "Leistungszeitraum 01.02.2026 bis 28.02.2026", "Rechnungsdatum 14.03.2026"],
        ["Vencimiento: 28/03/2026", "Fecha de nacimiento: 22/07/1993", "Periodo del 01/02/2026 al 28/02/2026", "Fecha de emisión: 14/03/2026"],
        ["Scadenza 28/03/2026", "Nata il 05/05/1990", "Periodo dal 01/02/2026 al 28/02/2026", "Data di emissione 14/03/2026"],
    ])
    func prefersTheIssueDateOverOtherDates(texts: [String]) {
        let lines = texts.enumerated().map { line($1, y: 0.1 + Double($0) * 0.03) }
        #expect(iso(detector.detect(lines: lines).details.date) == "2026-03-14")
    }

    @Test(arguments: ["14 mars 2026", "14. März 2026", "14 de marzo de 2026", "14 marzo 2026", "March 14th, 2026", "14 Mar. 2026", "14.03.26", "14/03/26", "Lyon, le 14 mars 2026", "Leipzig, den 14.03.2026"])
    func readsDates(text: String) {
        #expect(iso(detector.detect(lines: [line(text, y: 0.5)]).details.date) == "2026-03-14")
    }

    @Test func leavesTheDateEmptyWhenOnlyDueOrBirthDatesArePrinted() {
        let lines = [line("Date de naissance : 12/06/1991", y: 0.1), line("À payer avant le 28/03/2026", y: 0.2)]
        #expect(detector.detect(lines: lines).details.date == nil)
    }

    @Test func usesTheEndOfThePeriodOfAStatement() {
        let lines = [line("Relevé de compte du 01/02/2026 au 28/02/2026", y: 0.25), line("05/02/2026 Prélèvement", y: 0.5)]
        #expect(iso(detector.detect(lines: lines).details.date) == "2026-02-28")
    }

    // MARK: Number

    @Test(arguments: [
        ("FACTURE", "N° de facture : FA-2026-00417", "FA-2026-00417"),
        ("INVOICE", "Invoice no. INV-104829", "INV-104829"),
        ("Rechnung", "Rechnungsnummer: RE-2026-1182", "RE-2026-1182"),
        ("EMPLOYMENT CONTRACT", "Contract number: CT-55120", "CT-55120"),
        ("ATTESTATION D'ASSURANCE", "Police n° HAB-4471209", "HAB-4471209"),
        ("PÓLIZA DE SEGURO", "Nº de póliza: 0045-778812", "0045-778812"),
        ("CONTRATTO DI FORNITURA", "Numero contratto: 7781-2026-03", "7781-2026-03"),
        ("DEVIS", "Devis n° D-2026-031 du 02/03/2026", "D-2026-031"),
        ("Madame,", "Référence client : 0042 1187", "0042 1187"),
        ("Sehr geehrte Frau Brückner,", "Unser Zeichen: KB-4471", "KB-4471"),
    ])
    func readsTheNumberNextToItsLabel(title: String, label: String, number: String) {
        let lines = [line(title, y: 0.2, height: 0.02), line(label, y: 0.25)]
        #expect(detector.detect(lines: lines).details.number == number)
    }

    @Test func readsTheNumberInTheNextColumn() {
        let lines = [line("INVOICE", y: 0.05, height: 0.02), TextLine(text: "Invoice no.", frame: CGRect(x: 0.6, y: 0.2, width: 0.15, height: 0.011)), TextLine(text: "INV-104829", frame: CGRect(x: 0.8, y: 0.2, width: 0.15, height: 0.011))]
        #expect(detector.detect(lines: lines).details.number == "INV-104829")
    }

    @Test func readsTheNumberUnderItsLabelInABox() {
        let lines = [line("FACTURE", y: 0.05, height: 0.02), line("Numéro de facture", y: 0.2), line("FA-2026-00417", y: 0.215), line("Montant", y: 0.3), line("90,82 €", y: 0.315)]
        #expect(detector.detect(lines: lines).details.number == "FA-2026-00417")
    }

    @Test func readsLabelsGluedToTheirValue() {
        let lines = [line("FACTURE", y: 0.05, height: 0.02), line("Facture N°:FA-2026-00417", y: 0.2), line("Date de facture:14/03/2026 à 18:42", y: 0.25)]
        let details = detector.detect(lines: lines).details
        #expect(details.number == "FA-2026-00417")
        #expect(iso(details.date) == "2026-03-14")
    }

    @Test func ignoresYearsAndAmountsAsNumbers() {
        #expect(detector.detect(lines: [line("Bescheid für 2025", y: 0.2, height: 0.02)]).details.number == nil)
        #expect(detector.detect(lines: [line("FACTURE", y: 0.2, height: 0.02), line("N° de facture : 1 234,50 €", y: 0.25)]).details.number == nil)
    }

    private func iso(_ date: Date?) -> String? {
        date?.formatted(Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day())
    }

    private func line(_ text: String, y: Double, height: Double = 0.011) -> TextLine {
        TextLine(text: text, frame: CGRect(x: 0.1, y: y, width: 0.5, height: height))
    }
}

extension CorpusDocument: CustomTestStringConvertible {
    public var testDescription: String { name }
}

/// Hit rates per detail and language over made-up documents.
struct CorpusReport {
    struct Tally {
        var hits = 0
        var total = 0
        var rate: String { total == 0 ? "-" : "\(hits)/\(total)" }
    }

    static let details = ["category", "issuer", "date", "number"]
    var tallies: [String: [String: Tally]] = [:]
    var misses: [String] = []

    init(documents: [CorpusDocument], ownLines: Set<String> = []) {
        for document in documents {
            let detected = DocumentDetector(monthFirst: document.monthFirst).detect(lines: document.lines, ownLines: ownLines, aspectRatio: document.aspectRatio)
            let found = detected.details
            let checks: [(String, Bool, String)] = [
                ("category", found.category == document.category, found.category.rawValue),
                ("issuer", Self.sameIssuer(found.issuer, document.issuer), found.issuer ?? "nil"),
                ("date", found.date.map(Self.iso) == document.date, found.date.map(Self.iso) ?? "nil"),
                ("number", found.number == document.number, found.number ?? "nil"),
            ]
            for (detail, hit, value) in checks {
                for language in [document.language.prefix(2).description, "all"] {
                    tallies[detail, default: [:]][language, default: Tally()].total += 1
                    if hit { tallies[detail, default: [:]][language, default: Tally()].hits += 1 }
                }
                if !hit { misses.append("\(document.name) \(detail): got \(value)") }
            }
        }
    }

    func rate(_ detail: String, _ language: String = "all") -> Double {
        let tally = tallies[detail]?[language] ?? Tally()
        return tally.total == 0 ? 0 : Double(tally.hits) / Double(tally.total)
    }

    var table: String {
        let languages = ["en", "fr", "de", "es", "it", "all"]
        let header = "detail    " + languages.map { $0.padding(toLength: 7, withPad: " ", startingAt: 0) }.joined()
        let rows = Self.details.map { detail in
            detail.padding(toLength: 10, withPad: " ", startingAt: 0) + languages.map { (tallies[detail]?[$0]?.rate ?? "-").padding(toLength: 7, withPad: " ", startingAt: 0) }.joined()
        }
        return ([header] + rows).joined(separator: "\n")
    }

    static func sameIssuer(_ found: String?, _ expected: String?) -> Bool {
        found.map(normalized) == expected.map(normalized)
    }

    private static let legalForms: Set<String> = ["sa", "sas", "sarl", "gmbh", "ag", "eg", "ltd", "plc", "inc", "llc", "sl", "spa", "srl", "bv"]

    private static func normalized(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacing(".", with: "")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "&" })
            .filter { !legalForms.contains(String($0)) }
            .joined(separator: " ")
    }

    private static func iso(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day())
    }
}
