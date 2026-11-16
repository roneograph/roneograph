import CoreGraphics
import Foundation
import ScannerKit

/// A made-up first page with the details a person would file it under.
public struct CorpusDocument: Sendable {
    public var name: String
    public var category: DocumentCategory
    public var issuer: String?
    /// ISO day, such as 2026-03-14.
    public var date: String?
    public var number: String?
    public var monthFirst: Bool
    /// Width over height.
    public var aspectRatio: CGFloat
    public var lines: [TextLine]

    /// The language code at the end of the name, such as "fr".
    public var language: String { String(name.split(separator: "-").last ?? "") }

    /// Each row is "x y size text", with x and y in percent of the page and size T (title), H (heading), B (body) or S (small).
    public init(_ name: String, _ category: DocumentCategory, issuer: String?, date: String?, number: String? = nil, monthFirst: Bool = false, aspectRatio: CGFloat = 210.0 / 297.0, _ rows: String) {
        self.name = name
        self.category = category
        self.issuer = issuer
        self.date = date
        self.number = number
        self.monthFirst = monthFirst
        self.aspectRatio = aspectRatio
        lines = rows.split(separator: "\n").map { row in
            let fields = row.split(separator: " ", maxSplits: 3).map(String.init)
            let x = Double(fields[0])! / 100
            let y = Double(fields[1])! / 100
            let height = ["T": 0.028, "H": 0.018, "B": 0.011, "S": 0.008][fields[2]]!
            let text = fields[3]
            let width = min(0.98 - x, Double(text.count) * height * 0.55 / aspectRatio)
            return TextLine(text: text, frame: CGRect(x: x, y: y, width: width, height: height))
        }
    }
}

public enum DocumentCorpus {
    /// The names and addresses of the people receiving the corpus documents, one per language.
    public static let ownTexts = [
        "Jordan Ellery", "14 Willow Crescent", "Bramford BR4 7QT",
        "Camille Rouvière", "8 rue des Glycines", "69007 Lyon",
        "Lena Brückner", "Lindenweg 12", "04109 Leipzig",
        "Lucía Ferrándiz Soler", "Calle del Olmo 23, 3º B", "28014 Madrid",
        "Giulia Fabbretti", "Via dei Gelsomini 9", "40125 Bologna",
    ]

    /// The fingerprints of the lines a user would have learned as their own: their name and address lines.
    public static var ownLines: Set<String> {
        let markers = ["Ellery", "14 Willow Crescent", "BR4 7QT", "Rouvière", "Glycines", "69007 Lyon", "Brückner", "Lindenweg", "04109 Leipzig", "Ferrándiz", "Calle del Olmo", "28014 Madrid", "Fabbretti", "Gelsomini", "40125 Bologna"]
        let lines = documents.flatMap(\.lines).map(\.text).filter { text in markers.contains { text.contains($0) } && text.count < 40 }
        return Set(lines.map(DocumentDetector.fingerprint))
    }

    public static let documents: [CorpusDocument] = invoices + receipts + quotes + contracts + payslips + statements + taxNotices + insurance + medical + certificates + letters + others

    /// Documents written after the rules were tuned on `documents`, to measure how well they carry over.
    public static let holdout: [CorpusDocument] = [
        CorpusDocument("hold-invoice-en", .invoice, issuer: "Pinecrest Plumbing", date: "2026-03-04", number: "5521", monthFirst: true, """
        8 4 T Pinecrest Plumbing LLC
        8 8 S 410 Cedar Ave, Fairview, OR 97035 · (503) 555-0142
        60 4 H INVOICE
        60 9 B Invoice # 5521
        60 11 B Invoice Date 03/04/2026
        60 13 B Due Date 04/03/2026
        8 18 B Bill To
        8 20 B Jordan Ellery
        8 22 B 2250 Larkspur Lane
        8 30 B Description
        70 30 B Amount
        8 33 B Replace kitchen faucet
        70 33 B $185.00
        8 35 B Labor 1.5 hours
        70 35 B $142.50
        60 42 B Total Due
        80 42 B $327.50
        8 50 B Make checks payable to Pinecrest Plumbing LLC. Thank you for your business!
        """),
        CorpusDocument("hold-bill-en", .invoice, issuer: "Northfield Power", date: "2026-02-20", number: "300 118 442", """
        8 4 T northfield power
        8 15 B Mr J Ellery
        8 17 B 14 Willow Crescent
        8 19 B Bramford BR4 7QT
        60 15 B Bill date 20 February 2026
        60 17 B Customer number 300 118 442
        8 27 T Your electricity bill
        8 32 B For the period 15 January 2026 to 14 February 2026
        8 37 B Electricity used 412 kWh
        75 37 B £98.88
        8 39 B Standing charge 31 days
        75 39 B £16.27
        8 41 B VAT 5%
        75 41 B £5.76
        8 45 B Total to pay
        75 45 B £120.91
        8 50 B We'll collect this by Direct Debit on or after 6 March 2026.
        8 93 S Northfield Power Ltd, registered office Lantern House, Bramford. www.northfieldpower.co.uk
        """),
        CorpusDocument("hold-certificate-en", .certificate, issuer: "Bramford Swimming Club", date: "2026-02-08", number: nil, """
        25 8 H Bramford Swimming Club
        20 20 T Certificate of Achievement
        30 30 B Awarded to
        30 34 H Jordan Ellery
        20 40 B for swimming 1,500 metres freestyle
        30 52 B 8 February 2026
        """),
        CorpusDocument("hold-payslip-fr", .payslip, issuer: "Boulangerie Ferlac", date: "2026-03-31", number: nil, """
        8 4 H Boulangerie Ferlac SARL
        8 7 S 4 place Bellecour 69002 Lyon · SIRET 321 654 987 00011
        60 4 H BULLETIN DE SALAIRE
        60 8 B Mois : mars 2026
        60 10 B Payé le 31/03/2026 par virement
        8 15 B Mme Camille Rouvière
        8 17 B Vendeuse · Coefficient 160
        8 24 B Salaire de base 151,67 h
        75 24 B 1 823,03
        8 26 B Heures supplémentaires
        75 26 B 98,40
        8 28 B Total cotisations et contributions salariales
        75 28 B -420,11
        8 33 H NET À PAYER
        75 33 H 1 501,32
        """),
        CorpusDocument("hold-tax-fr", .taxNotice, issuer: "Direction Générale des Finances Publiques", date: "2026-08-29", number: nil, """
        8 4 B DIRECTION GÉNÉRALE DES FINANCES PUBLIQUES
        8 6 S impots.gouv.fr
        55 15 B MME ROUVIÈRE CAMILLE
        55 17 B 8 RUE DES GLYCINES
        55 19 B 69007 LYON
        10 25 T AVIS DE TAXE FONCIÈRE 2026
        8 31 B Numéro fiscal : 00 00 000 000 000
        8 33 B Date d'établissement : 29/08/2026
        8 35 B Date limite de paiement : 15/10/2026
        8 40 B Base d'imposition
        75 40 B 1 812
        8 42 B Montant de votre impôt
        75 42 B 1 044 €
        """),
        CorpusDocument("hold-medical-fr", .medical, issuer: "Centre d'Imagerie Saint-Clair", date: "2026-03-18", number: nil, """
        8 4 T Centre d'Imagerie Saint-Clair
        8 8 S 30 rue Duguesclin 69006 Lyon
        8 15 H COMPTE RENDU D'ÉCHOGRAPHIE ABDOMINALE
        8 20 B Patiente : Mme Camille Rouvière, née le 12/06/1991
        8 22 B Examen du 18/03/2026
        8 26 B Indication : douleurs abdominales.
        8 29 B Résultat : foie de taille normale, pas d'anomalie décelée.
        8 34 B Conclusion : examen normal.
        8 42 B Dr Paul Verdier, radiologue
        """),
        CorpusDocument("hold-quote-de", .quote, issuer: "Elektro Brandt", date: "2026-03-16", number: "KV-0193", """
        10 4 T Elektro Brandt
        10 8 S Elektro Brandt e.K. · Merseburger Straße 90 · 04177 Leipzig · info@elektro-brandt.de
        10 16 B Frau Lena Brückner
        10 18 B Lindenweg 12
        10 20 B 04109 Leipzig
        60 16 B Leipzig, 16.03.2026
        10 28 H Kostenvoranschlag KV-0193
        10 33 B Austausch Sicherungskasten inkl. Material
        75 33 B 1.180,00 €
        10 37 B Summe netto
        75 37 B 1.180,00 €
        10 39 B zzgl. 19 % MwSt.
        75 39 B 224,20 €
        10 44 B Der Kostenvoranschlag ist bis zum 15.04.2026 gültig.
        """),
        CorpusDocument("hold-insurance-de", .insurance, issuer: "Rheinauen Krankenversicherung", date: "2026-01-12", number: "K-77120-33", """
        10 4 T Rheinauen Krankenversicherung
        10 16 S Rheinauen Krankenversicherung a.G. · Postfach 50 · 50667 Köln
        10 18 B Frau Lena Brückner
        10 20 B Lindenweg 12
        10 22 B 04109 Leipzig
        60 18 B Köln, 12. Januar 2026
        60 20 B Versicherungsnummer K-77120-33
        10 30 H Versicherungsbestätigung
        10 35 B Hiermit bestätigen wir, dass Frau Lena Brückner, geboren am 03.11.1992,
        10 37 B seit dem 01.01.2026 bei uns krankenversichert ist.
        10 42 B Mit freundlichen Grüßen
        """),
        CorpusDocument("hold-receipt-de", .receipt, issuer: "Drogerie Weißdorn", date: "2026-03-20", number: nil, aspectRatio: 0.38, """
        20 3 H Drogerie Weißdorn
        15 6 S Karl-Liebknecht-Str. 41 · 04275 Leipzig
        10 11 B Zahnpasta
        75 11 B 1,95
        10 13 B Duschgel
        75 13 B 2,45
        10 18 H Gesamt EUR
        70 18 H 4,40
        10 21 B Kartenzahlung girocard
        70 21 B 4,40
        10 25 B 20.03.26 16:12
        15 29 B Danke für Ihren Einkauf!
        """),
        CorpusDocument("hold-invoice-es", .invoice, issuer: "Telecomunicaciones Brisa", date: "2026-03-01", number: "BR26-0088123", """
        8 4 T Telecomunicaciones Brisa
        8 8 S Telecomunicaciones Brisa S.A.U. · NIF A11223344 · www.brisatel.es
        55 15 B Lucía Ferrándiz Soler
        55 17 B Calle del Olmo 23, 3º B
        55 19 B 28014 Madrid
        8 26 H Tu factura de marzo
        8 30 B Número de factura: BR26-0088123
        8 32 B Fecha de factura: 01/03/2026
        8 34 B Nº de cliente: 4410-22
        8 38 B Periodo de facturación: 01/02/2026 - 28/02/2026
        8 43 B Fibra + móvil
        70 43 B 41,32 €
        60 49 B IVA (21%)
        80 49 B 8,68 €
        60 51 B Total
        80 51 B 50,00 €
        8 56 B Se cargará en tu cuenta el 05/03/2026.
        """),
        CorpusDocument("hold-contract-es", .contract, issuer: nil, date: "2026-02-25", number: nil, """
        10 6 T CONTRATO DE ARRENDAMIENTO DE VIVIENDA
        8 14 B En Madrid, a 25 de febrero de 2026
        8 19 B REUNIDOS
        8 22 B De una parte, D. Ernesto Valcárcel Ruiz, en calidad de arrendador.
        8 25 B De otra parte, Dña. Lucía Ferrándiz Soler, en calidad de arrendataria.
        8 30 B EXPONEN
        8 33 B Que el arrendador es propietario de la vivienda sita en Calle del Olmo 23, 3º B.
        8 38 B CLÁUSULAS
        8 41 B Primera. Duración: un año a contar desde el 1 de marzo de 2026.
        8 44 B Segunda. Renta: 950 euros mensuales.
        """),
        CorpusDocument("hold-receipt-es", .receipt, issuer: nil, date: "2026-03-01", number: nil, """
        25 6 T RECIBO DE ALQUILER
        8 16 B He recibido de Dña. Lucía Ferrándiz Soler la cantidad de 950,00 euros
        8 18 B en concepto de renta del mes de marzo de 2026 de la vivienda sita en
        8 20 B Calle del Olmo 23, 3º B, 28014 Madrid.
        8 30 B Madrid, 1 de marzo de 2026
        8 36 B Fdo.: Ernesto Valcárcel Ruiz
        """),
        CorpusDocument("hold-statement-it", .bankStatement, issuer: "Banca Valtorre", date: "2026-02-28", number: nil, """
        8 4 T Banca Valtorre
        55 15 B Giulia Fabbretti
        55 17 B Via dei Gelsomini 9
        55 19 B 40125 Bologna
        8 26 H Estratto conto carta di credito
        8 30 B Carta n. **** **** **** 4417
        8 32 B Data estratto conto: 28/02/2026
        8 34 B Addebito in conto il 15/03/2026
        8 39 B 03/02/2026 Libreria del Portico
        75 39 B 24,00
        8 41 B 17/02/2026 Ristorante Da Nello
        75 41 B 58,50
        8 45 B Totale addebiti
        75 45 B 82,50
        8 93 S Banca Valtorre S.p.A. · www.bancavaltorre.it
        """),
        CorpusDocument("hold-medical-it", .medical, issuer: "Dott. Marco Ferretti", date: "2026-03-17", number: nil, """
        8 4 H Dott. Marco Ferretti
        8 7 B Medico Chirurgo · Specialista in Cardiologia
        8 9 S Via Mazzini 12, 40137 Bologna
        25 18 T CERTIFICATO MEDICO
        8 25 B Si certifica che la Sig.ra Giulia Fabbretti, nata il 05/05/1990,
        8 27 B è stata visitata in data odierna e risulta idonea all'attività sportiva non agonistica.
        8 35 B Bologna, 17/03/2026
        """),
        CorpusDocument("hold-letter-it", .letter, issuer: "Condominio Le Querce", date: "2026-03-03", number: nil, """
        8 4 H Condominio Le Querce
        8 7 S Amministrazione: Studio Bertoni, Via Marconi 8, Bologna
        55 15 B Gent.ma Sig.ra Giulia Fabbretti
        55 17 B Via dei Gelsomini 9
        55 19 B 40125 Bologna
        8 26 B Bologna, 3 marzo 2026
        8 30 B Oggetto: convocazione assemblea ordinaria
        8 35 B Gentile condomina,
        8 38 B l'assemblea ordinaria è convocata per il giorno 24 marzo 2026 alle ore 18.
        8 43 B Distinti saluti
        8 48 B L'amministratore
        """),
        CorpusDocument("hold-insurance-fr", .insurance, issuer: "Brisemer Assurances", date: "2026-03-01", number: "AUTO-55120", """
        8 4 T Brisemer Assurances
        55 15 B Mme Camille Rouvière
        55 17 B 8 rue des Glycines
        55 19 B 69007 Lyon
        8 26 H AVIS D'ÉCHÉANCE
        8 30 B Contrat n° AUTO-55120 · Automobile
        8 32 B Émis le 01/03/2026
        8 34 B Date d'échéance : 01/04/2026
        8 39 B Cotisation annuelle TTC
        75 39 B 512,40 €
        8 44 B Prélèvement le 05/04/2026 sur votre compte.
        8 93 S Brisemer Assurances SA · RCS Nantes 678 912 345 · www.brisemer-assurances.fr
        """),
        CorpusDocument("hold-invoice-it", .invoice, issuer: "Luce Alpina", date: "2026-03-05", number: "2026/123", """
        8 4 T LUCE ALPINA
        55 15 B Giulia Fabbretti
        55 17 B Via dei Gelsomini 9
        55 19 B 40125 Bologna
        8 26 H BOLLETTA LUCE
        8 30 B Fattura n. 2026/123 del 05/03/2026
        8 32 B Periodo: gennaio - febbraio 2026
        8 37 B Spesa per la materia energia
        75 37 B 61,20 €
        8 39 B Spesa per il trasporto
        75 39 B 18,44 €
        8 43 B Totale da pagare
        75 43 B 79,64 €
        8 45 B Scadenza 25/03/2026
        8 93 S Luce Alpina S.p.A. · P.IVA 03456789012 · www.lucealpina.it
        """),
        CorpusDocument("hold-order-en", .other, issuer: "Fernleaf Books", date: "2026-03-08", number: "10234", """
        8 4 T Fernleaf Books
        8 12 H Thanks for your order!
        8 17 B Order #10234
        8 19 B Order date: 8 March 2026
        8 24 B The Lantern Keeper (paperback)
        75 24 B £9.99
        8 26 B Delivery
        75 26 B £2.99
        8 30 B Subtotal
        75 30 B £12.98
        8 32 B Total
        75 32 B £12.98
        8 36 B We'll email you when your parcel is on its way.
        8 93 S www.fernleafbooks.co.uk
        """),
        CorpusDocument("hold-letter-de", .letter, issuer: "Ondine Mobilfunk", date: "2026-03-12", number: "MF-2231-8", """
        10 4 T Ondine Mobilfunk
        10 16 S Ondine Mobilfunk GmbH · Postfach 11 22 · 10001 Berlin
        10 18.5 B Frau
        10 20.5 B Lena Brückner
        10 22.5 B Lindenweg 12
        10 24.5 B 04109 Leipzig
        60 20.5 B Berlin, 12.03.2026
        10 32 B Bestätigung Ihrer Kündigung
        10 34 B Vertragsnummer: MF-2231-8
        10 39 B Sehr geehrte Frau Brückner,
        10 42 B hiermit bestätigen wir die Kündigung Ihres Vertrags zum 30.04.2026.
        10 47 B Mit freundlichen Grüßen
        10 52 B Ihr Ondine-Team
        """),
        CorpusDocument("hold-receipt-fr", .receipt, issuer: "Boulangerie du Parc", date: "2026-03-21", number: nil, aspectRatio: 0.4, """
        20 3 B CARTE BANCAIRE
        20 5 B SANS CONTACT
        10 9 B LE 21/03/26 A 12:31
        10 11 B BOULANGERIE DU PARC
        10 13 B 69007 LYON
        10 17 B MONTANT = 7,80 EUR
        10 19 B DEBIT
        20 23 B TICKET CLIENT
        20 25 B A CONSERVER
        """),
        CorpusDocument("hold-receipt-es2", .receipt, issuer: "Banco Mirasol", date: "2026-03-18", number: "0098123", """
        8 4 T BANCO MIRASOL
        8 14 H JUSTIFICANTE DE PAGO
        8 20 B Fecha de la operación: 18/03/2026
        8 22 B Referencia: 0098123
        8 24 B Ordenante: Lucía Ferrándiz Soler
        8 26 B Beneficiario: Gestoría Albar S.L.
        8 28 B Importe: 121,00 €
        8 32 B Concepto: honorarios marzo
        """),
    ]

    static let invoices = [
        CorpusDocument("invoice-fr", .invoice, issuer: "Voltaria Énergie", date: "2026-03-14", number: "FA-2026-00417", """
        8 4 T VOLTARIA ÉNERGIE
        8 8 S 12 avenue des Tilleuls · 69003 Lyon
        8 9.5 S www.voltaria-energie.fr
        55 15 B Mme Camille Rouvière
        55 17 B 8 rue des Glycines
        55 19 B 69007 Lyon
        8 26 H FACTURE
        8 30 B Période de consommation du 01/02/2026 au 28/02/2026
        8 32 B N° de facture : FA-2026-00417
        8 34 B Date de facture : 14/03/2026
        8 36 B Référence client : 0042 1187
        8 42 B Désignation
        70 42 B Montant HT
        8 45 B Abonnement électricité
        70 45 B 14,20 €
        8 47 B Consommation 312 kWh
        70 47 B 61,48 €
        60 55 B Total HT
        80 55 B 75,68 €
        60 57 B TVA 20 %
        80 57 B 15,14 €
        60 59 B Total TTC
        80 59 B 90,82 €
        8 64 B Date d'échéance : 28/03/2026, prélèvement sur IBAN FR76 **** **** 0451
        8 94 S Voltaria Énergie SAS au capital de 500 000 € · RCS Lyon 123 456 789 · SIRET 123 456 789 00012 · TVA FR12 123456789
        """),
        CorpusDocument("invoice-en", .invoice, issuer: "Brightwater Broadband", date: "2026-03-02", number: "INV-104829", """
        8 14 B Mr Jordan Ellery
        8 16 B 14 Willow Crescent
        8 18 B Bramford BR4 7QT
        62 14 B Invoice date
        80 14 B 2 March 2026
        62 16 B Invoice no.
        80 16 B INV-104829
        62 18 B Account number
        80 18 B 7720 4418
        8 27 T Your invoice
        8 33 B Billing period 1 Feb 2026 to 28 Feb 2026
        8 38 B Fibre 500 package
        75 38 B £32.00
        8 40 B Line rental
        75 40 B £18.50
        8 44 B Subtotal
        75 44 B £50.50
        8 46 B VAT at 20%
        75 46 B £10.10
        8 48 B Total due
        75 48 B £60.60
        8 53 B Payment due by 16 March 2026 by Direct Debit.
        8 58 B Questions? Email billing@brightwater-broadband.co.uk
        8 93 S Brightwater Broadband Ltd · Registered in England and Wales No. 01234567 · VAT Reg No. GB 123 4567 89
        """),
        CorpusDocument("invoice-de", .invoice, issuer: "Stadtwerke Neustadt", date: "2026-03-12", number: "RE-2026-1182", """
        60 4 T Stadtwerke Neustadt
        60 8 S Energie · Wasser · Wärme
        10 16 S Stadtwerke Neustadt GmbH · Hafenstraße 4 · 04103 Leipzig
        10 18.5 B Frau
        10 20.5 B Lena Brückner
        10 22.5 B Lindenweg 12
        10 24.5 B 04109 Leipzig
        60 18.5 B Kundennummer
        78 18.5 B 448 120
        60 20.5 B Rechnungsnummer
        78 20.5 B RE-2026-1182
        60 22.5 B Rechnungsdatum
        78 22.5 B 12.03.2026
        10 32 H Rechnung Strom
        10 36 B Lieferzeitraum 01.02.2026 bis 28.02.2026
        10 40 B Arbeitspreis 298 kWh
        75 40 B 89,40 €
        10 42 B Grundpreis
        75 42 B 12,90 €
        10 46 B Nettobetrag
        75 46 B 102,30 €
        10 48 B Umsatzsteuer 19 %
        75 48 B 19,44 €
        10 50 B Gesamtbetrag
        75 50 B 121,74 €
        10 55 B Zahlbar bis 26.03.2026 ohne Abzug.
        10 93 S Stadtwerke Neustadt GmbH · Amtsgericht Leipzig HRB 12345 · USt-IdNr. DE123456789 · www.stadtwerke-neustadt.de
        """),
        CorpusDocument("invoice-es", .invoice, issuer: "Ferretería Almendro", date: "2026-03-05", number: "F2026/0315", """
        8 4 T Ferretería Almendro S.L.
        8 8 S Avenida de los Pinos 41 · 28045 Madrid
        8 9.5 S CIF: B12345678 · info@ferreteria-almendro.es
        55 15 B Lucía Ferrándiz Soler
        55 17 B Calle del Olmo 23, 3º B
        55 19 B 28014 Madrid
        8 26 H FACTURA
        8 30 B Nº factura: F2026/0315
        8 32 B Fecha: 05/03/2026
        8 34 B Vencimiento: 05/04/2026
        8 40 B Concepto
        70 40 B Importe
        8 43 B Taladro percutor 750 W
        70 43 B 69,00 €
        8 45 B Juego de brocas
        70 45 B 12,40 €
        60 52 B Base imponible
        80 52 B 81,40 €
        60 54 B IVA 21 %
        80 54 B 17,09 €
        60 56 B Total a pagar
        80 56 B 98,49 €
        8 62 B Forma de pago: transferencia bancaria
        """),
        CorpusDocument("invoice-it", .invoice, issuer: "Ondaverde Telecomunicazioni", date: "2026-03-09", number: "112/2026", """
        8 4 T ONDAVERDE TELECOMUNICAZIONI
        8 8 S Ondaverde Telecomunicazioni S.p.A. · Via Emilia Ponente 120 · 40133 Bologna
        8 9.5 S P.IVA 01234567890 · www.ondaverde.it
        55 15 B Gentile Giulia Fabbretti
        55 17 B Via dei Gelsomini 9
        55 19 B 40125 Bologna
        8 26 H Fattura n. 112/2026 del 09/03/2026
        8 30 B Codice cliente: OV-55120
        8 32 B Periodo di fatturazione dal 01/02/2026 al 28/02/2026
        8 38 B Canone fibra
        70 38 B 24,59 €
        8 40 B Traffico extra soglia
        70 40 B 1,20 €
        60 46 B Imponibile
        80 46 B 25,79 €
        60 48 B IVA 22%
        80 48 B 5,67 €
        60 50 B Totale da pagare
        80 50 B 31,46 €
        8 55 B Scadenza: 30/03/2026
        """),
    ]

    static let receipts = [
        CorpusDocument("receipt-fr", .receipt, issuer: "Épicerie des Halles", date: "2026-03-14", number: nil, aspectRatio: 0.36, """
        20 3 H ÉPICERIE DES HALLES
        15 6 S 3 place du Marché 69002 Lyon
        15 7.5 S SIRET 345 678 912 00024
        10 12 B Pain de campagne
        75 12 B 3,20
        10 14 B Comté 250 g
        75 14 B 6,90
        10 16 B Pommes 1,2 kg
        75 16 B 3,48
        10 21 H TOTAL
        70 21 H 13,58
        10 25 B CB SANS CONTACT
        70 25 B 13,58
        10 29 B 14/03/2026 18:42 Caisse 2
        20 34 B MERCI DE VOTRE VISITE
        """),
        CorpusDocument("receipt-fr2", .receipt, issuer: "Cabinet Delorme Immobilier", date: "2026-03-01", number: nil, """
        8 4 H Cabinet Delorme Immobilier
        8 7 S 22 quai Saint-Vincent · 69001 Lyon · gestion@delorme-immo.fr
        55 15 B Mme Camille Rouvière
        55 17 B 8 rue des Glycines
        55 19 B 69007 Lyon
        25 28 T QUITTANCE DE LOYER
        8 34 B Période : mars 2026
        8 38 B Je soussigné, gérant du Cabinet Delorme Immobilier, mandataire du bailleur, reconnais avoir reçu
        8 40 B de Mme Camille Rouvière la somme de 820,00 € au titre du loyer et des charges.
        8 44 B Loyer
        70 44 B 760,00 €
        8 46 B Provision sur charges
        70 46 B 60,00 €
        8 48 B Total réglé
        70 48 B 820,00 €
        8 56 B Fait à Lyon, le 1er mars 2026
        """),
        CorpusDocument("receipt-en", .receipt, issuer: "Hollybrook Garden Centre", date: "2026-03-07", number: "0218-4471", aspectRatio: 0.36, """
        15 3 H Hollybrook Garden Centre
        15 6 S Mill Lane, Bramford
        15 7.5 S VAT No. GB 987 6543 21
        30 10 B SALES RECEIPT
        10 13 B Lavender 2L pot x2
        75 13 B 11.98
        10 15 B Compost 50L
        75 15 B 6.50
        10 20 H TOTAL
        70 20 H 18.48
        10 23 B Card
        70 23 B 18.48
        10 25 B Change
        70 25 B 0.00
        10 29 B 07/03/2026 11:05
        10 31 B Receipt no 0218-4471
        15 35 B Thank you for shopping with us
        """),
        CorpusDocument("receipt-de", .receipt, issuer: "Bäckerei Kornblum", date: "2026-03-11", number: "5521", aspectRatio: 0.36, """
        15 3 H Bäckerei Kornblum
        15 6 S Karl-Heine-Straße 8, 04229 Leipzig
        15 7.5 S USt-IdNr. DE987654321
        30 10 B KASSENBON
        10 13 B 2x Roggenbrötchen
        75 13 B 1,10
        10 15 B Bauernbrot 750g
        75 15 B 4,20
        10 20 H SUMME EUR
        70 20 H 5,30
        10 23 B Bar
        70 23 B 10,00
        10 25 B Rückgeld
        70 25 B 4,70
        10 29 B 11.03.2026 07:42 Beleg-Nr. 5521
        15 33 B Vielen Dank für Ihren Einkauf
        """),
        CorpusDocument("receipt-es", .receipt, issuer: "Supermercados Brezal", date: "2026-03-10", number: "T001-004521", aspectRatio: 0.36, """
        15 3 H SUPERMERCADOS BREZAL
        15 6 S Calle Mayor 12, 28013 Madrid
        15 7.5 S NIF: B87654321
        20 10 B FACTURA SIMPLIFICADA
        10 12 B Nº: T001-004521
        10 15 B Leche entera 1L x3
        75 15 B 2,85
        10 17 B Pan de molde
        75 17 B 1,65
        10 22 H TOTAL
        70 22 H 4,50
        10 25 B Efectivo
        70 25 B 5,00
        10 27 B Cambio
        70 27 B 0,50
        10 30 B 10/03/2026 19:20
        15 34 B Gracias por su compra
        """),
        CorpusDocument("receipt-it", .receipt, issuer: "Farmacia del Portico", date: "2026-03-13", number: "0123-0045", aspectRatio: 0.36, """
        15 3 H FARMACIA DEL PORTICO
        15 6 S Via Saragozza 40 - 40123 Bologna
        15 7.5 S P.IVA 09876543210
        10 10 B DOCUMENTO COMMERCIALE
        10 11.5 B di vendita o prestazione
        10 15 B Collirio monodose
        75 15 B 8,90
        10 17 B Cerotti
        75 17 B 3,50
        10 22 H TOTALE COMPLESSIVO
        70 22 H 12,40
        10 25 B Pagamento elettronico
        70 25 B 12,40
        10 28 B 13-03-2026 10:14
        10 30 B DOCUMENTO N. 0123-0045
        15 34 B Grazie e arrivederci
        """),
    ]

    static let quotes = [
        CorpusDocument("quote-fr", .quote, issuer: "Plomberie Arnaud & Fils", date: "2026-03-02", number: "D-2026-031", """
        8 4 T Plomberie Arnaud & Fils
        8 8 S SARL au capital de 8 000 € · 5 rue Tronchet · 69006 Lyon
        8 9.5 S plomberie.arnaud@gmail.com · 04 78 00 00 00
        55 15 B Mme Camille Rouvière
        55 17 B 8 rue des Glycines
        55 19 B 69007 Lyon
        8 26 H DEVIS N° D-2026-031
        8 30 B Date : 02/03/2026
        8 32 B Objet : remplacement du chauffe-eau
        8 38 B Chauffe-eau électrique 200 L
        70 38 B 640,00 €
        8 40 B Main d'œuvre (4 h)
        70 40 B 220,00 €
        60 46 B Total HT
        80 46 B 860,00 €
        60 48 B TVA 10 %
        80 48 B 86,00 €
        60 50 B Total TTC
        80 50 B 946,00 €
        8 56 B Devis valable jusqu'au 02/04/2026
        8 62 B Bon pour accord, date et signature du client :
        8 93 S SIRET 456 789 123 00017
        """),
        CorpusDocument("quote-en", .quote, issuer: "Hartley & Finch Roofing", date: "2026-03-03", number: "Q-10482", """
        8 4 T HARTLEY & FINCH ROOFING
        8 8 S Unit 3, Tanner's Yard, Bramford · www.hartleyfinch.co.uk
        8 15 B Mr J. Ellery
        8 17 B 14 Willow Crescent
        8 19 B Bramford BR4 7QT
        8 27 H QUOTATION
        8 31 B Quote No: Q-10482
        8 33 B Date: 3 March 2026
        8 35 B Valid until: 2 April 2026
        8 41 B Replace slipped roof tiles and repoint ridge
        75 41 B £540.00
        8 43 B Scaffolding hire, 1 week
        75 43 B £380.00
        8 49 B Total excl. VAT
        75 49 B £920.00
        8 51 B VAT 20%
        75 51 B £184.00
        8 53 B Total
        75 53 B £1,104.00
        8 59 B To accept this quote, please sign and return a copy.
        8 93 S Hartley & Finch Roofing Ltd · Company No. 07654321
        """),
        CorpusDocument("quote-de", .quote, issuer: "Malerbetrieb Kessler", date: "2026-03-04", number: "AN-2026-077", """
        10 4 T Malerbetrieb Kessler
        10 8 S Meisterbetrieb seit 1998 · info@maler-kessler.de
        10 16 S Malerbetrieb Kessler GmbH · Gartenstraße 3 · 04177 Leipzig
        10 18.5 B Frau
        10 20.5 B Lena Brückner
        10 22.5 B Lindenweg 12
        10 24.5 B 04109 Leipzig
        60 20.5 B Datum: 04.03.2026
        10 32 H Angebot Nr. AN-2026-077
        10 36 B Sehr geehrte Frau Brückner, wir bieten Ihnen folgende Leistungen an:
        10 40 B Wände streichen, 3 Räume
        75 40 B 1.240,00 €
        10 42 B Decken streichen
        75 42 B 380,00 €
        10 46 B Nettobetrag
        75 46 B 1.620,00 €
        10 48 B MwSt. 19 %
        75 48 B 307,80 €
        10 50 B Gesamtbetrag
        75 50 B 1.927,80 €
        10 55 B Dieses Angebot ist gültig bis 03.04.2026.
        10 93 S Amtsgericht Leipzig HRB 54321 · USt-IdNr. DE234567891
        """),
        CorpusDocument("quote-es", .quote, issuer: "Reformas Brezo", date: "2026-03-06", number: "P-2026-019", """
        8 4 T REFORMAS BREZO
        8 8 S Reformas Brezo S.L. · CIF B23456789 · presupuestos@reformasbrezo.es
        55 15 B Lucía Ferrándiz Soler
        55 17 B Calle del Olmo 23, 3º B
        55 19 B 28014 Madrid
        8 26 H PRESUPUESTO
        8 30 B Nº presupuesto: P-2026-019
        8 32 B Fecha: 06/03/2026
        8 38 B Alicatado de baño
        70 38 B 1.150,00 €
        8 40 B Sustitución de plato de ducha
        70 40 B 480,00 €
        60 46 B Base imponible
        80 46 B 1.630,00 €
        60 48 B IVA 21 %
        80 48 B 342,30 €
        60 50 B Total
        80 50 B 1.972,30 €
        8 56 B Validez del presupuesto: 30 días
        8 60 B Aceptación del cliente (firma):
        """),
        CorpusDocument("quote-it", .quote, issuer: "Edilcasa Ruggeri", date: "2026-03-07", number: "45/2026", """
        8 4 T Edilcasa Ruggeri S.r.l.
        8 8 S Via Stalingrado 77 · 40128 Bologna · P.IVA 02345678901
        55 15 B Gent.ma Sig.ra Giulia Fabbretti
        55 17 B Via dei Gelsomini 9
        55 19 B 40125 Bologna
        8 26 H PREVENTIVO N. 45/2026
        8 30 B Data: 07/03/2026
        8 36 B Rifacimento intonaco facciata
        70 36 B 3.200,00 €
        8 38 B Tinteggiatura
        70 38 B 900,00 €
        60 44 B Imponibile
        80 44 B 4.100,00 €
        60 46 B IVA 10%
        80 46 B 410,00 €
        60 48 B Totale
        80 48 B 4.510,00 €
        8 54 B Validità dell'offerta: 30 giorni
        8 58 B Per accettazione:
        """),
    ]

    static let contracts = [
        CorpusDocument("contract-fr", .contract, issuer: "Agence Immobilière du Parc", date: "2026-02-15", number: nil, """
        8 4 H Agence Immobilière du Parc
        8 7 S 40 cours Gambetta · 69007 Lyon · www.agence-du-parc.fr
        20 15 T CONTRAT DE LOCATION
        25 19 B Logement vide soumis à la loi du 6 juillet 1989
        8 25 B ENTRE LES SOUSSIGNÉS :
        8 28 B Le bailleur : SCI Les Platanes, représentée par l'Agence Immobilière du Parc,
        8 32 B Et le locataire : Mme Camille Rouvière, née le 12/06/1991
        8 37 B Il a été convenu ce qui suit :
        8 40 B Article 1 – Objet du contrat : appartement de 3 pièces, 8 rue des Glycines, 69007 Lyon.
        8 44 B Article 2 – Date de prise d'effet : 1er mars 2026, pour une durée de trois ans.
        8 48 B Article 3 – Loyer mensuel : 760,00 € hors charges.
        8 80 B Fait à Lyon, le 15 février 2026, en deux exemplaires.
        8 85 B Le bailleur
        60 85 B Le locataire
        """),
        CorpusDocument("contract-en", .contract, issuer: "Corvane Analytics", date: "2026-02-02", number: nil, """
        8 4 T Corvane Analytics
        8 8 S 2 Riverside Walk, Bramford · hr@corvane-analytics.co.uk
        20 16 H EMPLOYMENT CONTRACT
        8 22 B This agreement is made on 2 February 2026 between Corvane Analytics Ltd (the Employer)
        8 24 B and Jordan Ellery (the Employee).
        8 29 B 1. Start date: your employment begins on 1 March 2026.
        8 32 B 2. Job title: Data Analyst.
        8 35 B 3. Salary: £38,000 per year, paid monthly.
        8 38 B 4. Hours: 37.5 hours per week.
        8 41 B 5. Notice period: one month.
        8 80 B Signed for the Employer
        60 80 B Signed by the Employee
        8 93 S Corvane Analytics Ltd · Registered in England and Wales No. 09876543
        """),
        CorpusDocument("contract-de", .contract, issuer: "Hausverwaltung Sommerfeld", date: "2026-03-10", number: "MV-2026-014", """
        10 4 T Hausverwaltung Sommerfeld
        10 8 S Hausverwaltung Sommerfeld GmbH · Brühl 50 · 04109 Leipzig
        30 16 T Mietvertrag
        10 21 B Vertragsnummer: MV-2026-014
        10 25 B zwischen der Hausverwaltung Sommerfeld GmbH (Vermieter)
        10 27 B und Frau Lena Brückner, geboren am 03.11.1992 (Mieterin)
        10 31 B § 1 Mietsache: Wohnung im 2. OG, Lindenweg 12, 04109 Leipzig
        10 34 B § 2 Mietbeginn: 01.04.2026
        10 37 B § 3 Miete: 690,00 € monatlich zuzüglich Nebenkosten
        10 80 B Leipzig, den 10.03.2026
        10 85 B Unterschrift Vermieter
        60 85 B Unterschrift Mieter
        """),
        CorpusDocument("contract-es", .contract, issuer: "Grupo Lirio Servicios", date: "2026-02-12", number: "CS-2026-0042", """
        8 4 T Grupo Lirio Servicios S.L.
        8 8 S CIF B34567890 · www.grupolirio.es
        15 15 H CONTRATO DE PRESTACIÓN DE SERVICIOS
        8 19 B Nº de contrato: CS-2026-0042
        8 23 B En Madrid, a 12 de febrero de 2026
        8 27 B REUNIDOS
        8 30 B De una parte, Grupo Lirio Servicios S.L., en adelante el prestador.
        8 33 B De otra parte, Dña. Lucía Ferrándiz Soler, en adelante la clienta.
        8 37 B CLÁUSULAS
        8 40 B Primera. El prestador realizará la limpieza del domicilio dos veces por semana.
        8 43 B Segunda. El contrato entra en vigor el 1 de marzo de 2026.
        8 80 B Firma del prestador
        60 80 B Firma de la clienta
        """),
        CorpusDocument("contract-it", .contract, issuer: "Luce Alpina", date: "2026-02-18", number: "7781-2026-03", """
        8 4 T LUCE ALPINA
        8 8 S Luce Alpina S.p.A. · Viale Masini 12 · 40126 Bologna · www.lucealpina.it
        55 15 B Giulia Fabbretti
        55 17 B Via dei Gelsomini 9
        55 19 B 40125 Bologna
        8 26 H CONTRATTO DI FORNITURA DI ENERGIA ELETTRICA
        8 30 B Numero contratto: 7781-2026-03
        8 32 B Data: 18/02/2026
        8 34 B Data di attivazione prevista: 01/04/2026
        8 39 B Tra Luce Alpina S.p.A. (il Fornitore) e il Cliente si conviene quanto segue.
        8 42 B Articolo 1 – Oggetto: fornitura di energia elettrica per uso domestico.
        8 45 B Articolo 2 – Durata: 12 mesi con rinnovo tacito.
        8 80 B Firma del Cliente
        8 93 S P.IVA 03456789012
        """),
    ]

    static let payslips = [
        CorpusDocument("payslip-fr", .payslip, issuer: "Atelier Corvelle", date: "2026-02-27", number: nil, """
        8 4 H BULLETIN DE PAIE
        8 8 B Période du 01/02/2026 au 28/02/2026
        8 10 B Date de paiement : 27/02/2026
        8 15 B Employeur
        8 17 B Atelier Corvelle SAS
        8 19 S 17 rue de la Charité · 69002 Lyon
        8 21 S SIRET 234 567 891 00015 · Code NAF 7410Z
        55 15 B Salarié
        55 17 B Mme Camille Rouvière
        55 19 B Née le 12/06/1991
        55 21 B Emploi : Graphiste
        8 28 B Convention collective : Bureaux d'études techniques
        8 34 B Salaire de base
        75 34 B 2 650,00
        8 36 B Cotisations salariales
        75 36 B -582,80
        8 42 B Net à payer avant impôt sur le revenu
        75 42 B 2 067,20
        8 44 B Impôt sur le revenu prélevé à la source
        75 44 B -95,09
        8 48 H Net payé
        75 48 H 1 972,11
        """),
        CorpusDocument("payslip-en", .payslip, issuer: "Corvane Analytics", date: "2026-02-27", number: nil, """
        8 4 T Corvane Analytics Ltd
        8 8 S 2 Riverside Walk, Bramford
        60 4 H PAYSLIP
        8 15 B Employee: Jordan Ellery
        8 17 B Employee no: 0047
        8 19 B Tax code: 1257L
        60 15 B Pay date: 27 February 2026
        60 17 B Pay period: 1 Feb 2026 – 28 Feb 2026
        8 26 B Basic salary
        75 26 B £3,166.67
        8 28 B Gross pay
        75 28 B £3,166.67
        8 30 B Income tax
        75 30 B -£424.20
        8 32 B National Insurance
        75 32 B -£165.47
        8 36 H Net pay
        75 36 H £2,577.00
        8 40 B Year to date gross £6,333.34
        """),
        CorpusDocument("payslip-de", .payslip, issuer: "Kessler Logistik", date: "2026-02-27", number: nil, """
        10 4 T Kessler Logistik GmbH
        10 8 S Torgauer Straße 210 · 04347 Leipzig
        10 16 B Frau Lena Brückner
        10 18 B Lindenweg 12
        10 20 B 04109 Leipzig
        60 16 B Personalnummer 2291
        60 18 B Geburtsdatum 03.11.1992
        60 20 B Steuerklasse 1
        10 28 H Entgeltabrechnung Februar 2026
        10 34 B Bruttolohn
        75 34 B 3.400,00
        10 36 B Lohnsteuer
        75 36 B -412,58
        10 38 B Sozialversicherung
        75 38 B -697,00
        10 42 H Auszahlungsbetrag
        75 42 H 2.290,42
        10 47 B Auszahlung am 27.02.2026 auf IBAN DE02 **** **** 7711
        """),
        CorpusDocument("payslip-es", .payslip, issuer: "Grupo Lirio Servicios", date: "2026-02-28", number: nil, """
        8 4 H RECIBO INDIVIDUAL DE SALARIOS
        8 9 B Empresa: Grupo Lirio Servicios S.L.
        8 11 B CIF: B34567890
        8 13 S Calle de Atocha 102, 28012 Madrid
        55 9 B Trabajadora: Lucía Ferrándiz Soler
        55 11 B Categoría: Coordinadora
        8 19 B Periodo de liquidación: del 01/02/2026 al 28/02/2026
        8 21 B Fecha de pago: 28/02/2026
        8 27 B Salario base
        75 27 B 1.950,00
        8 29 B Total devengado
        75 29 B 2.120,00
        8 31 B Total a deducir
        75 31 B -398,40
        8 36 H Líquido a percibir
        75 36 H 1.721,60
        """),
        CorpusDocument("payslip-it", .payslip, issuer: "Ruggeri Costruzioni", date: "2026-02-27", number: nil, """
        8 4 T Ruggeri Costruzioni S.r.l.
        8 8 S Via del Lavoro 15 · 40127 Bologna · P.IVA 04567890123
        60 4 H CEDOLINO PAGA
        8 15 B Dipendente: Giulia Fabbretti
        8 17 B Data di nascita: 05/05/1990
        60 15 B Periodo di paga: Febbraio 2026
        60 17 B Data pagamento: 27/02/2026
        8 25 B Retribuzione base
        75 25 B 2.100,00
        8 27 B Contributi previdenziali
        75 27 B -193,20
        8 29 B Trattenute IRPEF
        75 29 B -310,15
        8 34 H Netto in busta
        75 34 H 1.596,65
        """),
    ]

    static let statements = [
        CorpusDocument("statement-fr", .bankStatement, issuer: "Banque Clairevoie", date: "2026-02-28", number: nil, """
        8 4 T Banque Clairevoie
        8 8 S Agence Lyon Jean Macé · 04 72 00 00 00
        55 15 B Mme Camille Rouvière
        55 17 B 8 rue des Glycines
        55 19 B 69007 Lyon
        8 26 H RELEVÉ DE COMPTE COURANT
        8 30 B Relevé n° 2 du 01/02/2026 au 28/02/2026
        8 32 B IBAN FR76 0000 0000 0000 0000 0000 000
        8 38 B Date
        25 38 B Libellé
        65 38 B Débit
        80 38 B Crédit
        8 40 B 01/02/2026
        25 40 B Ancien solde
        80 40 B 1 204,10
        8 42 B 03/02/2026
        25 42 B PRLV SEPA Voltaria Énergie
        65 42 B 90,82
        8 44 B 05/02/2026
        25 44 B VIR Atelier Corvelle
        80 44 B 1 972,11
        8 46 B 28/02/2026
        25 46 B Nouveau solde créditeur
        80 46 B 3 085,39
        8 93 S Banque Clairevoie SA · RCS Lyon 567 891 234 · ORIAS 07 000 000
        """),
        CorpusDocument("statement-en", .bankStatement, issuer: "Quellwater Bank", date: "2026-02-28", number: nil, """
        8 4 T Quellwater Bank
        8 15 B Mr Jordan Ellery
        8 17 B 14 Willow Crescent
        8 19 B Bramford BR4 7QT
        60 15 B Statement date: 28 February 2026
        60 17 B Sort code 00-00-00
        60 19 B Account number 0000 1234
        8 27 H Your current account statement
        8 31 B 1 February to 28 February 2026
        8 36 B Opening balance
        75 36 B £1,402.33
        8 38 B 03 Feb Card payment Hollybrook Garden Centre
        75 38 B £18.48
        8 40 B 27 Feb Salary Corvane Analytics
        75 40 B £2,577.00
        8 44 B Closing balance
        75 44 B £3,960.85
        8 93 S Quellwater Bank plc · www.quellwaterbank.co.uk
        """),
        CorpusDocument("statement-de", .bankStatement, issuer: "Auenbank Leipzig", date: "2026-02-28", number: "2/2026", """
        10 4 T Auenbank Leipzig eG
        10 16 B Frau Lena Brückner
        10 18 B Lindenweg 12
        10 20 B 04109 Leipzig
        10 28 H Kontoauszug Nr. 2/2026
        60 28 B Erstellt am 28.02.2026
        10 32 B IBAN DE02 0000 0000 0000 0000 00
        10 37 B Alter Saldo per 31.01.2026
        75 37 B 2.118,40
        10 39 B 02.02.2026 Lastschrift Stadtwerke Neustadt
        75 39 B -121,74
        10 41 B 27.02.2026 Gehalt Kessler Logistik
        75 41 B 2.290,42
        10 45 B Neuer Saldo per 28.02.2026
        75 45 B 4.287,08
        10 93 S Auenbank Leipzig eG · www.auenbank.de · BIC GENODEF1XXX
        """),
        CorpusDocument("statement-es", .bankStatement, issuer: "Banco Mirasol", date: "2026-03-01", number: nil, """
        8 4 T BANCO MIRASOL
        55 15 B Lucía Ferrándiz Soler
        55 17 B Calle del Olmo 23, 3º B
        55 19 B 28014 Madrid
        8 26 H EXTRACTO DE CUENTA
        8 30 B Periodo: 01/02/2026 - 28/02/2026
        8 32 B Fecha de emisión: 01/03/2026
        8 34 B IBAN ES00 0000 0000 0000 0000 0000
        8 39 B Saldo anterior
        75 39 B 3.210,00
        8 41 B 04/02/2026 Recibo Ferretería Almendro
        75 41 B -98,49
        8 43 B 28/02/2026 Nómina Grupo Lirio
        75 43 B 1.721,60
        8 47 B Saldo final
        75 47 B 4.833,11
        8 93 S Banco Mirasol, S.A. · CIF A45678901 · www.bancomirasol.es
        """),
        CorpusDocument("statement-it", .bankStatement, issuer: "Banca Valtorre", date: "2026-01-31", number: nil, """
        8 4 T Banca Valtorre
        8 8 S Filiale di Bologna Centro
        55 15 B Giulia Fabbretti
        55 17 B Via dei Gelsomini 9
        55 19 B 40125 Bologna
        8 26 H ESTRATTO CONTO CORRENTE
        8 30 B Periodo dal 01/01/2026 al 31/01/2026
        8 35 B Saldo iniziale
        75 35 B 1.540,22
        8 37 B 05/01/2026 Bonifico Ruggeri Costruzioni
        75 37 B 1.596,65
        8 39 B 12/01/2026 Addebito Ondaverde
        75 39 B -31,46
        8 43 B Saldo finale
        75 43 B 3.105,41
        8 93 S Banca Valtorre S.p.A. · P.IVA 05678901234 · www.bancavaltorre.it
        """),
    ]

    static let taxNotices = [
        CorpusDocument("tax-fr", .taxNotice, issuer: "Direction Générale des Finances Publiques", date: "2026-07-31", number: "26 69 A123456 78", """
        8 4 H DIRECTION GÉNÉRALE DES FINANCES PUBLIQUES
        8 7 S Centre des Finances publiques de Lyon · impots.gouv.fr
        55 15 B MME ROUVIÈRE CAMILLE
        55 17 B 8 RUE DES GLYCINES
        55 19 B 69007 LYON
        8 25 T AVIS D'IMPÔT 2026
        8 29 B sur les revenus de l'année 2025
        8 33 B Référence de l'avis : 26 69 A123456 78
        8 35 B Date d'établissement : 31/07/2026
        8 37 B Date limite de paiement : 15/09/2026
        8 43 B Revenu fiscal de référence
        75 43 B 31 870
        8 45 B Nombre de parts
        75 45 B 1
        8 47 B Impôt sur le revenu net
        75 47 B 1 142
        """),
        CorpusDocument("tax-en", .taxNotice, issuer: "Bramford District Council", date: "2026-03-09", number: "4410287713", """
        8 4 T Bramford District Council
        8 8 S Council Offices, Market Square, Bramford · www.bramford.gov.uk
        8 15 B Mr Jordan Ellery
        8 17 B 14 Willow Crescent
        8 19 B Bramford BR4 7QT
        60 15 B Date of issue: 9 March 2026
        60 17 B Account reference: 4410287713
        8 27 H Council Tax Bill 2026/27
        8 32 B Valuation band C
        8 36 B Annual charge
        75 36 B £1,874.20
        8 38 B Single person discount 25%
        75 38 B -£468.55
        8 40 B Amount payable
        75 40 B £1,405.65
        8 45 B 10 instalments due on the 1st of each month from 1 April 2026
        """),
        CorpusDocument("tax-de", .taxNotice, issuer: "Finanzamt Leipzig II", date: "2026-05-14", number: nil, """
        10 4 H Finanzamt Leipzig II
        10 7 S Erich-Weinert-Straße 20 · 04105 Leipzig
        10 16 B Frau Lena Brückner
        10 18 B Lindenweg 12
        10 20 B 04109 Leipzig
        60 16 B Steuernummer 231/456/78901
        60 18 B Datum 14.05.2026
        10 28 H Bescheid für 2025
        10 30 B über Einkommensteuer und Solidaritätszuschlag
        10 35 B Festsetzung
        10 38 B Zu versteuerndes Einkommen
        75 38 B 38.412 €
        10 40 B Festgesetzte Einkommensteuer
        75 40 B 6.211 €
        10 42 B Erstattung
        75 42 B 388 €
        """),
        CorpusDocument("tax-es", .taxNotice, issuer: "Agencia Tributaria", date: "2026-06-20", number: "1002026123456", """
        8 4 T Agencia Tributaria
        8 8 S Delegación Especial de Madrid · www.agenciatributaria.es
        55 15 B Lucía Ferrándiz Soler
        55 17 B Calle del Olmo 23, 3º B
        55 19 B 28014 Madrid
        8 26 H NOTIFICACIÓN DE LIQUIDACIÓN PROVISIONAL
        8 30 B Impuesto sobre la Renta de las Personas Físicas · Ejercicio 2025
        8 33 B Nº de justificante: 1002026123456
        8 35 B Fecha: 20/06/2026
        8 40 B Base liquidable general
        75 40 B 29.300,00
        8 42 B Cuota resultante
        75 42 B 412,77
        8 46 B Plazo de ingreso: hasta el 20/07/2026
        """),
        CorpusDocument("tax-it", .taxNotice, issuer: "Agenzia delle Entrate", date: "2026-04-15", number: "0123456789012", """
        8 4 T Agenzia delle Entrate
        8 8 S Direzione Provinciale di Bologna
        55 15 B Giulia Fabbretti
        55 17 B Via dei Gelsomini 9
        55 19 B 40125 Bologna
        8 26 H COMUNICAZIONE DI IRREGOLARITÀ
        8 30 B Dichiarazione Modello 730/2025 · Anno d'imposta 2024
        8 33 B Codice atto: 0123456789012
        8 35 B Data di emissione: 15/04/2026
        8 40 B Imposta dovuta
        75 40 B 214,00
        8 42 B Sanzioni e interessi
        75 42 B 18,40
        8 46 B Il pagamento va effettuato entro 30 giorni dal ricevimento.
        """),
    ]

    static let insurance = [
        CorpusDocument("insurance-fr", .insurance, issuer: "Brisemer Assurances", date: "2026-01-05", number: "HAB-4471209", """
        8 4 T Brisemer Assurances
        8 8 S 9 boulevard Guist'hau · 44000 Nantes · www.brisemer-assurances.fr
        55 15 B Mme Camille Rouvière
        55 17 B 8 rue des Glycines
        55 19 B 69007 Lyon
        15 26 H ATTESTATION D'ASSURANCE HABITATION
        8 31 B Contrat n° HAB-4471209
        8 35 B Brisemer Assurances atteste que Mme Camille Rouvière est assurée au titre du contrat
        8 37 B multirisque habitation pour le logement situé 8 rue des Glycines, 69007 Lyon.
        8 41 B Période de validité : du 01/01/2026 au 31/12/2026
        8 45 B Garanties : responsabilité civile, incendie, dégâts des eaux.
        8 60 B Fait à Nantes, le 5 janvier 2026
        8 93 S Brisemer Assurances SA · Entreprise régie par le Code des assurances · RCS Nantes 678 912 345
        """),
        CorpusDocument("insurance-en", .insurance, issuer: "Kestrel Mutual Insurance", date: "2026-01-20", number: "KM-5530-2291", """
        8 4 T Kestrel Mutual Insurance
        8 8 S Kestrel House, Bramford · www.kestrelmutual.co.uk
        15 16 H CERTIFICATE OF MOTOR INSURANCE
        8 21 B Policy number: KM-5530-2291
        8 23 B Date of issue: 20 January 2026
        8 26 B Policyholder: Jordan Ellery
        8 28 B Vehicle registration: AB12 CDE
        8 31 B Effective date of commencement of insurance: 1 February 2026
        8 33 B Date of expiry of insurance: 31 January 2027
        8 37 B Persons or classes of persons entitled to drive: the policyholder only.
        8 93 S Kestrel Mutual Insurance plc · Registered in England No. 02468135
        """),
        CorpusDocument("insurance-de", .insurance, issuer: "Lindgrün Versicherung", date: "2026-02-18", number: "HR-20-447812", """
        10 4 T Lindgrün Versicherung
        10 16 S Lindgrün Versicherung AG · Postfach 1234 · 50000 Köln
        10 18.5 B Frau
        10 20.5 B Lena Brückner
        10 22.5 B Lindenweg 12
        10 24.5 B 04109 Leipzig
        60 20.5 B Ausgestellt am 18.02.2026
        10 32 H Versicherungsschein Hausratversicherung
        10 36 B Versicherungsschein-Nr. HR-20-447812
        10 38 B Versicherungsnehmerin: Lena Brückner
        10 40 B Versicherungsbeginn: 01.03.2026
        10 42 B Versicherungssumme: 45.000 €
        10 44 B Jahresbeitrag: 98,40 €
        10 93 S www.lindgruen-versicherung.de
        """),
        CorpusDocument("insurance-es", .insurance, issuer: "Seguros Almendro", date: "2026-02-15", number: "0045-778812", """
        8 4 T Seguros Almendro
        8 8 S Seguros Almendro, S.A. · Paseo de la Castellana 300 · 28046 Madrid
        8 15 H PÓLIZA DE SEGURO DE HOGAR
        8 20 B Nº de póliza: 0045-778812
        8 22 B Fecha de emisión: 15/02/2026
        8 24 B Fecha de efecto: 01/03/2026
        8 28 B Tomador: Lucía Ferrándiz Soler
        8 30 B Asegurado: el tomador
        8 34 B Coberturas: incendio, daños por agua, responsabilidad civil
        8 36 B Prima anual: 214,60 €
        8 93 S CIF A56789012 · www.segurosalmendro.es
        """),
        CorpusDocument("insurance-it", .insurance, issuer: "Assicurazioni Riva Serena", date: "2026-01-10", number: "RS-889102", """
        8 4 T Assicurazioni Riva Serena
        8 8 S Assicurazioni Riva Serena S.p.A. · Piazza Cavour 2 · 20121 Milano
        55 15 B Giulia Fabbretti
        55 17 B Via dei Gelsomini 9
        55 19 B 40125 Bologna
        8 26 H CERTIFICATO DI ASSICURAZIONE
        8 29 B Responsabilità civile auto
        8 33 B Polizza n. RS-889102
        8 35 B Data di emissione: 10/01/2026
        8 37 B Contraente: Giulia Fabbretti
        8 39 B Periodo di copertura: dal 15/01/2026 al 15/01/2027
        8 41 B Premio annuo: 412,00 €
        8 93 S P.IVA 06789012345 · www.rivaserena.it
        """),
    ]

    static let medical = [
        CorpusDocument("medical-fr", .medical, issuer: "Dr Hélène Marsac", date: "2026-03-09", number: nil, """
        8 4 H Dr Hélène Marsac
        8 7 B Médecin généraliste
        8 9 S 15 rue Chevreul · 69007 Lyon · 04 78 11 11 11
        8 11 S N° RPPS 10001234567
        60 15 B Lyon, le 9 mars 2026
        30 22 T ORDONNANCE
        8 28 B Mme Camille Rouvière
        8 34 B Paracétamol 1 g : 1 comprimé 3 fois par jour pendant 5 jours
        8 37 B Ibuprofène 400 mg : 1 comprimé matin et soir si douleur
        """),
        CorpusDocument("medical-en", .medical, issuer: "Ashcombe Pathology Laboratory", date: "2026-03-03", number: nil, """
        8 4 T Ashcombe Pathology Laboratory
        8 8 S Ashcombe Hospital, Bramford
        8 15 H LABORATORY REPORT
        8 20 B Patient: Jordan Ellery
        8 22 B Date of birth: 04/11/1988
        8 24 B Sample collected: 2 March 2026
        8 26 B Report date: 3 March 2026
        8 32 B Test
        40 32 B Result
        65 32 B Reference range
        8 34 B Haemoglobin
        40 34 B 148 g/L
        65 34 B 130 – 170
        8 36 B Ferritin
        40 36 B 92 µg/L
        65 36 B 30 – 400
        8 42 B Requested by Dr A. Patel, Willow Surgery
        """),
        CorpusDocument("medical-de", .medical, issuer: "Dr. med. Jonas Feldhaus", date: "2026-03-09", number: nil, """
        10 4 H Dr. med. Jonas Feldhaus
        10 7 B Facharzt für Allgemeinmedizin
        10 9 S Praxis am Südplatz · Südplatz 3 · 04275 Leipzig
        10 15 H Arbeitsunfähigkeitsbescheinigung
        10 20 B Versicherte: Lena Brückner, geb. 03.11.1992
        10 23 B Erstbescheinigung
        10 26 B arbeitsunfähig seit 09.03.2026
        10 28 B voraussichtlich arbeitsunfähig bis einschließlich 13.03.2026
        10 30 B festgestellt am 09.03.2026
        10 36 B Diagnose: J06.9
        """),
        CorpusDocument("medical-es", .medical, issuer: "Clínica Vallehermoso", date: "2026-03-11", number: nil, """
        8 4 T Clínica Vallehermoso
        8 8 S Calle de Vallehermoso 80 · 28015 Madrid
        8 15 H INFORME MÉDICO
        8 20 B Paciente: Lucía Ferrándiz Soler
        8 22 B Fecha de nacimiento: 22/07/1993
        8 24 B Fecha: 11/03/2026
        8 29 B Motivo de consulta: dolor lumbar de una semana de evolución.
        8 32 B Diagnóstico: lumbalgia mecánica.
        8 35 B Tratamiento: ibuprofeno 600 mg cada 8 horas durante 5 días.
        8 45 B Dra. Marta Ibarra, médico de familia
        """),
        CorpusDocument("medical-it", .medical, issuer: "Poliambulatorio Santa Viola", date: "2026-03-12", number: nil, """
        8 4 T Poliambulatorio Santa Viola
        8 8 S Via Irnerio 21 · 40126 Bologna
        8 15 H REFERTO DI VISITA SPECIALISTICA
        8 20 B Paziente: Giulia Fabbretti
        8 22 B Data di nascita: 05/05/1990
        8 24 B Data referto: 12/03/2026
        8 29 B Esame obiettivo: nella norma.
        8 32 B Terapia: collirio due volte al giorno per 7 giorni.
        8 45 B Dott.ssa Paola Gentili
        """),
    ]

    static let certificates = [
        CorpusDocument("certificate-fr", .certificate, issuer: "Lycée des Quatre Vents", date: "2026-09-04", number: nil, """
        8 4 H Lycée des Quatre Vents
        8 7 S 2 allée des Écoles · 69008 Lyon
        20 18 T ATTESTATION DE SCOLARITÉ
        8 26 B Je soussigné, proviseur du Lycée des Quatre Vents, certifie que l'élève
        8 29 B Noé Rouvière, né le 14/02/2010,
        8 32 B est inscrit en classe de seconde pour l'année scolaire 2026-2027.
        8 37 B Attestation délivrée pour servir et valoir ce que de droit.
        50 50 B Fait à Lyon, le 4 septembre 2026
        """),
        CorpusDocument("certificate-en", .certificate, issuer: "Northgate Training Institute", date: "2026-01-21", number: "NTI-2026-0193", """
        30 6 H Northgate Training Institute
        25 18 T CERTIFICATE OF COMPLETION
        30 26 B This is to certify that
        35 30 H Jordan Ellery
        20 35 B has successfully completed the course Advanced Spreadsheet Modelling
        30 45 B Date: 21 January 2026
        30 48 B Certificate No. NTI-2026-0193
        """),
        CorpusDocument("certificate-de", .certificate, issuer: "Stadt Leipzig", date: "2026-02-03", number: nil, """
        10 4 T Stadt Leipzig
        10 8 B Bürgeramt Mitte
        25 18 T Meldebescheinigung
        10 25 B Hiermit wird bescheinigt, dass die nachstehend genannte Person gemeldet ist:
        10 29 B Familienname: Brückner
        10 31 B Vorname: Lena
        10 33 B Geburtsdatum: 03.11.1992
        10 35 B Anschrift: Lindenweg 12, 04109 Leipzig
        10 37 B Einzugsdatum: 01.04.2026
        10 50 B Leipzig, 03.02.2026
        """),
        CorpusDocument("certificate-es", .certificate, issuer: "Ayuntamiento de Madrid", date: "2026-01-16", number: nil, """
        8 4 T Ayuntamiento de Madrid
        8 8 S Oficina de Atención a la Ciudadanía
        15 16 H CERTIFICADO DE EMPADRONAMIENTO
        8 22 B CERTIFICA: que según los datos del Padrón Municipal de Habitantes,
        8 25 B Dña. Lucía Ferrándiz Soler, nacida el 22/07/1993,
        8 28 B figura empadronada en Calle del Olmo 23, 3º B, 28014 Madrid.
        8 40 B Madrid, a 16 de enero de 2026
        """),
        CorpusDocument("certificate-it", .certificate, issuer: "Comune di Bologna", date: "2026-01-20", number: nil, """
        8 4 T Comune di Bologna
        8 8 S Servizi Demografici
        15 16 H CERTIFICATO DI RESIDENZA
        8 22 B L'Ufficiale d'Anagrafe, visti gli atti d'ufficio, certifica che
        8 25 B Fabbretti Giulia, nata a Bologna il 05/05/1990,
        8 28 B risulta residente in Via dei Gelsomini 9, 40125 Bologna.
        8 40 B Bologna, 20/01/2026
        """),
    ]

    static let letters = [
        CorpusDocument("letter-fr", .letter, issuer: "Ondine Télécom", date: "2026-03-02", number: "7731 0042", """
        8 4 T Ondine Télécom
        8 8 S Service clients · 31 rue de la Gare · 33000 Bordeaux
        55 15 B Mme Camille Rouvière
        55 17 B 8 rue des Glycines
        55 19 B 69007 Lyon
        55 25 B Bordeaux, le 2 mars 2026
        8 28 B Référence client : 7731 0042
        8 31 B Objet : évolution de vos conditions tarifaires
        8 37 B Madame,
        8 40 B Nous vous informons qu'à compter du 1er mai 2026, le prix de votre forfait mobile évoluera.
        8 42 B Les autres conditions de votre contrat restent inchangées.
        8 47 B Nous vous prions d'agréer, Madame, l'expression de nos salutations distinguées.
        8 53 B Le service clients
        8 93 S Ondine Télécom SAS · 31 rue de la Gare · 33000 Bordeaux · www.ondine-telecom.fr
        """),
        CorpusDocument("letter-en", .letter, issuer: "Halbrook Water Services", date: "2026-03-15", number: "HB/2291", """
        8 4 T Halbrook Water Services
        8 8 S PO Box 77, Bramford · customer.care@halbrookwater.co.uk
        8 15 B Mr Jordan Ellery
        8 17 B 14 Willow Crescent
        8 19 B Bramford BR4 7QT
        60 15 B Our ref: HB/2291
        60 17 B 15 March 2026
        8 27 B Dear Mr Ellery,
        8 30 B Re: Planned maintenance in your area
        8 34 B We will be replacing the water main in Willow Crescent from 6 April 2026.
        8 36 B Your supply may be interrupted for a few hours during the works.
        8 41 B Yours sincerely,
        8 46 B Customer Care Team
        """),
        CorpusDocument("letter-de", .letter, issuer: "Wohnbau Lindental", date: "2026-03-05", number: "KB-4471", """
        10 4 T Wohnbau Lindental eG
        10 16 S Wohnbau Lindental eG · Arno-Nitzsche-Straße 30 · 04277 Leipzig
        10 18.5 B Frau
        10 20.5 B Lena Brückner
        10 22.5 B Lindenweg 12
        10 24.5 B 04109 Leipzig
        60 18.5 B Unser Zeichen: KB-4471
        60 20.5 B Datum: 05.03.2026
        10 32 B Betreff: Ablesung der Heizkostenverteiler
        10 37 B Sehr geehrte Frau Brückner,
        10 40 B am 24.03.2026 werden in Ihrer Wohnung die Heizkostenverteiler abgelesen.
        10 42 B Bitte sorgen Sie dafür, dass die Heizkörper zugänglich sind.
        10 47 B Mit freundlichen Grüßen
        10 52 B Ihre Wohnbau Lindental
        10 93 S www.wohnbau-lindental.de
        """),
        CorpusDocument("letter-es", .letter, issuer: "Gestoría Albar", date: "2026-03-09", number: nil, """
        8 4 T Gestoría Albar
        8 8 S Calle de Toledo 54 · 28005 Madrid · contacto@gestoriaalbar.es
        55 15 B Sra. Lucía Ferrándiz Soler
        55 17 B Calle del Olmo 23, 3º B
        55 19 B 28014 Madrid
        55 25 B Madrid, 9 de marzo de 2026
        8 30 B Asunto: traslado de nuestras oficinas
        8 35 B Estimada Sra. Ferrándiz:
        8 38 B Le informamos de que a partir del 1 de abril de 2026 nuestras oficinas se trasladan.
        8 40 B La atención a clientes seguirá siendo la misma.
        8 45 B Atentamente,
        8 50 B Javier Albar
        8 93 S Gestoría Albar, S.L. · CIF B67890123
        """),
        CorpusDocument("letter-it", .letter, issuer: "Associazione Culturale Il Mosaico", date: "2026-03-10", number: nil, """
        8 4 H Associazione Culturale Il Mosaico
        8 7 S Via Castiglione 31 · 40124 Bologna · segreteria@ilmosaico-bo.it
        55 15 B Gentile Sig.ra Giulia Fabbretti
        55 17 B Via dei Gelsomini 9
        55 19 B 40125 Bologna
        55 25 B Bologna, 10 marzo 2026
        8 30 B Oggetto: rinnovo della tessera associativa
        8 35 B Gentile socia,
        8 38 B le ricordiamo che la sua tessera scade il 31/03/2026 e può essere rinnovata in segreteria.
        8 43 B Cordiali saluti,
        8 48 B La segreteria
        """),
    ]

    static let others = [
        CorpusDocument("other-fr", .other, issuer: nil, date: nil, number: nil, """
        20 6 T Fête des voisins
        25 12 H Résidence Les Platanes
        15 20 B Samedi 30 mai, à partir de 18 h, dans la cour de la résidence.
        15 24 B Chacun apporte un plat ou une boisson à partager.
        15 28 B Tables et chaises fournies par le conseil syndical.
        15 34 B Inscriptions auprès de la loge avant le 25 mai.
        """),
        CorpusDocument("other-fr2", .other, issuer: nil, date: nil, number: nil, """
        15 6 H Liste des pièces à fournir
        15 10 B pour votre dossier de location
        10 16 B - Pièce d'identité en cours de validité
        10 18 B - Trois derniers bulletins de salaire
        10 20 B - Dernier avis d'imposition
        10 22 B - Contrat de travail ou attestation employeur
        10 24 B - Justificatif de domicile de moins de trois mois
        10 26 B - Relevé d'identité bancaire
        10 32 B Les dossiers incomplets ne seront pas étudiés.
        """),
        CorpusDocument("other-en", .other, issuer: "Willow Crescent Residents' Association", date: "2026-03-12", number: nil, """
        20 6 T Willow Crescent Residents' Association
        30 12 H Meeting agenda
        20 16 B Thursday 12 March 2026, 7.30 pm, Community Hall
        15 22 B 1. Welcome and apologies
        15 24 B 2. Minutes of the last meeting
        15 26 B 3. Parking on the Crescent
        15 28 B 4. Spring clean-up day
        15 30 B 5. Any other business
        """),
        CorpusDocument("other-de", .other, issuer: nil, date: nil, number: nil, """
        25 6 T Speiseplan
        20 12 H Kantine am Hafen · Woche vom 09.03. bis 13.03.
        10 20 B Montag: Linsensuppe mit Brot
        10 23 B Dienstag: Gemüselasagne
        10 26 B Mittwoch: Hähnchen mit Reis
        10 29 B Donnerstag: Kartoffelpuffer mit Apfelmus
        10 32 B Freitag: Fisch mit Kartoffelsalat
        10 38 B Alle Gerichte 5,90 €
        """),
        CorpusDocument("other-es", .other, issuer: nil, date: nil, number: nil, """
        25 6 T Horario de clases
        30 12 H 2º de ESO · Grupo B
        10 20 B Lunes: Matemáticas, Lengua, Inglés, Educación Física
        10 23 B Martes: Biología, Historia, Música, Matemáticas
        10 26 B Miércoles: Lengua, Tecnología, Inglés, Plástica
        10 29 B Jueves: Historia, Matemáticas, Física y Química
        10 32 B Viernes: Inglés, Lengua, Tutoría
        """),
        CorpusDocument("other-it", .other, issuer: nil, date: "2026-04-18", number: nil, """
        20 6 T Gita sociale ai colli
        25 12 H Programma della giornata
        10 18 B Sabato 18 aprile 2026
        10 22 B Ore 8.00 ritrovo in piazza
        10 25 B Ore 10.30 visita all'abbazia
        10 28 B Ore 13.00 pranzo al sacco
        10 31 B Ore 17.00 rientro previsto
        10 36 B Portare scarpe comode e acqua.
        """),
    ]
}
