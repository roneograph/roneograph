/// The words the document detector looks for, in English, French, German, Spanish and Italian.
///
/// In phrases, "n°" stands for any number marker (n°, nº, no, nr, #), a leading "*" also matches the end of a longer word
/// (German compounds such as "Stromrechnung"), and a leading "^" only matches at the start of a line.
enum DocumentVocabulary {
    struct Entry: Sendable {
        var category: DocumentCategory?
        /// Document titles, such as "Facture".
        var titles: [String] = []
        /// Titles that weigh less because they are vague, such as "Statement".
        var weakTitles: [String] = []
        /// Words that are often a title but also appear in the names of issuers, such as "Assurances".
        var nameWords: [String] = []
        /// Field labels and wording typical of the category.
        var labels: [String] = []
        /// Labels followed by the reference number of the document.
        var numberLabels: [String] = []
    }

    static let entries: [Entry] = [
        Entry(
            category: .invoice,
            titles: [
                "invoice", "tax invoice", "credit note", "facture", "facture acquittée", "note d'honoraires", "rechnung", "*rechnung", "gutschrift",
                "factura", "fattura", "fattura elettronica", "nota di credito", "nota de crédito",
            ],
            weakTitles: ["bill", "your bill"],
            labels: [
                "amount due", "total due", "balance due", "invoice date", "invoice number", "payment terms", "subtotal", "vat", "billing period",
                "total ttc", "total ht", "montant ttc", "montant ht", "net à payer", "date de facture", "date de facturation", "échéance", "date d'échéance",
                "conditions de paiement", "tva", "période de facturation", "rechnungsnummer", "rechnungsdatum", "zahlbar bis", "nettobetrag", "mwst",
                "umsatzsteuer", "gesamtbetrag", "zahlungsziel", "lieferzeitraum", "abrechnungszeitraum", "fecha de factura", "número de factura",
                "base imponible", "iva", "total a pagar", "vencimiento", "forma de pago", "periodo de facturación", "data fattura", "numero fattura",
                "imponibile", "totale da pagare", "scadenza", "periodo di fatturazione",
            ],
            numberLabels: [
                "invoice n°", "invoice number", "n° de facture", "numéro de facture", "facture n°", "rechnungsnummer", "rechnungs-nr", "rechnung n°",
                "n° factura", "n° de factura", "número de factura", "factura n°", "numero fattura", "fattura n°", "n° fattura", "fattura numero",
            ]
        ),
        Entry(
            category: .receipt,
            titles: [
                "receipt", "sales receipt", "payment receipt", "till receipt", "rent receipt", "reçu", "reçu de paiement", "ticket de caisse", "quittance",
                "quittance de loyer", "quittung", "kassenbon", "kassenbeleg", "kassenzettel", "zahlungsbeleg", "recibo", "ticket de compra",
                "factura simplificada", "ricevuta", "ricevuta fiscale", "scontrino", "scontrino fiscale", "documento commerciale",
                "payment confirmation", "proof of payment", "preuve de paiement", "zahlungsbestätigung", "justificante de pago",
                "comprobante de pago", "ricevuta di pagamento",
            ],
            weakTitles: ["ticket", "beleg"],
            labels: [
                "change", "cash", "card", "paid", "thank you for shopping", "merci de votre visite", "rendu", "espèces", "cb", "carte bancaire",
                "sans contact", "caisse", "reconnais avoir reçu", "total réglé", "bar", "rückgeld", "gegeben", "ec-karte", "kartenzahlung", "summe",
                "vielen dank für ihren einkauf", "efectivo", "cambio", "tarjeta", "gracias por su compra", "gracias por su visita", "contanti", "resto",
                "pagamento elettronico", "grazie e arrivederci", "totale complessivo", "beleg-nr", "receipt n°",
            ],
            numberLabels: [
                "receipt n°", "receipt number", "ticket n°", "n° de ticket", "beleg-nr", "belegnummer", "bon n°", "^n°", "documento n°", "scontrino n°",
                "ricevuta n°", "transaction n°",
            ]
        ),
        Entry(
            category: .quote,
            titles: [
                "quote", "quotation", "estimate", "devis", "proposition commerciale", "angebot", "kostenvoranschlag", "presupuesto", "cotización",
                "preventivo", "offerta commerciale", "offerta economica",
            ],
            labels: [
                "valid until", "to accept this quote", "acceptance", "valable jusqu'au", "validité de l'offre", "devis valable", "bon pour accord",
                "gültig bis", "angebotsnummer", "validez", "validez del presupuesto", "aceptación", "aceptación del cliente", "validità dell'offerta",
                "per accettazione",
            ],
            numberLabels: [
                "quote n°", "quote number", "quotation n°", "devis n°", "n° de devis", "numéro de devis", "angebotsnummer", "angebot n°",
                "n° presupuesto", "número de presupuesto", "presupuesto n°", "preventivo n°", "numero preventivo",
            ]
        ),
        Entry(
            category: .contract,
            titles: [
                "contract", "agreement", "tenancy agreement", "employment contract", "contrat", "contrat de travail", "contrat de location", "bail",
                "vertrag", "*vertrag", "vereinbarung", "contrato", "contrato de arrendamiento", "contrato de trabajo", "contrato de prestación de servicios",
                "contratto", "contratto di locazione", "contratto di lavoro", "contratto di fornitura",
            ],
            labels: [
                "between", "the parties", "the employer", "the employee", "the landlord", "the tenant", "signed by", "signature", "entre les soussignés",
                "il a été convenu", "article 1", "les parties", "en deux exemplaires", "le bailleur", "le locataire", "le preneur", "zwischen", "§ 1",
                "vermieter", "mieter", "mieterin", "vertragsparteien", "unterschrift", "reunidos", "cláusulas", "de una parte", "de otra parte",
                "el arrendador", "el arrendatario", "firma", "tra", "le parti", "premesso che", "si conviene", "articolo 1", "vertragsnummer",
                "contract number", "n° de contrat", "número de contrato", "numero contratto",
            ],
            numberLabels: [
                "contract number", "contract n°", "agreement number", "n° de contrat", "numéro de contrat", "contrat n°", "vertragsnummer", "vertrag n°",
                "n° de contrato", "número de contrato", "contrato n°", "numero contratto", "contratto n°", "n° contratto",
            ]
        ),
        Entry(
            category: .payslip,
            titles: [
                "payslip", "pay slip", "pay stub", "pay statement", "earnings statement", "bulletin de paie", "bulletin de salaire", "fiche de paie",
                "lohnabrechnung", "gehaltsabrechnung", "entgeltabrechnung", "verdienstabrechnung", "*lohnabrechnung", "nómina", "recibo de salarios",
                "recibo individual de salarios", "recibo de nómina", "busta paga", "cedolino", "cedolino paga", "prospetto paga",
            ],
            labels: [
                "gross pay", "net pay", "basic salary", "tax code", "national insurance", "year to date", "pay date", "pay period", "employee n°",
                "salaire de base", "salaire brut", "net à payer avant impôt sur le revenu", "net payé", "cotisations salariales", "convention collective",
                "salarié", "salariée", "employeur", "emploi", "prélevé à la source", "bruttolohn", "bruttogehalt", "nettolohn", "auszahlungsbetrag",
                "steuerklasse", "sozialversicherung", "lohnsteuer", "personalnummer", "salario base", "total devengado", "líquido a percibir",
                "total a deducir", "periodo de liquidación", "trabajador", "trabajadora", "retribuzione", "retribuzione base", "netto in busta",
                "trattenute", "contributi previdenziali", "periodo di paga", "dipendente",
            ]
        ),
        Entry(
            category: .bankStatement,
            titles: [
                "bank statement", "account statement", "statement of account", "current account statement", "relevé de compte", "relevé bancaire",
                "relevé de compte courant", "extrait de compte", "kontoauszug", "extracto bancario", "extracto de cuenta", "estratto conto",
                "estratto conto corrente",
            ],
            weakTitles: ["statement", "relevé", "extracto"],
            labels: [
                "opening balance", "closing balance", "previous balance", "new balance", "sort code", "account number", "card payment", "ancien solde",
                "nouveau solde", "solde créditeur", "solde débiteur", "iban", "bic", "débit", "crédit", "date valeur", "prlv", "vir", "virement",
                "alter saldo", "neuer saldo", "kontostand", "lastschrift", "saldo anterior", "saldo final", "fecha valor", "movimientos",
                "saldo iniziale", "saldo finale", "bonifico", "addebito", "data valuta", "movimenti",
            ],
            numberLabels: [
                "relevé n°", "statement n°", "statement number", "kontoauszug n°", "auszug n°", "extracto n°", "estratto conto n°",
            ]
        ),
        Entry(
            category: .taxNotice,
            titles: [
                "avis d'impôt", "avis d'imposition", "avis de taxe foncière", "avis de taxe d'habitation", "taxe foncière", "steuerbescheid",
                "*steuerbescheid", "notice of assessment", "tax assessment", "tax notice", "tax bill", "council tax bill",
                "property tax", "liquidación provisional", "notificación de liquidación", "avviso di accertamento", "cartella di pagamento",
                "comunicazione di irregolarità", "avviso di pagamento",
            ],
            weakTitles: ["bescheid"],
            nameWords: [
                "finances publiques", "impots.gouv.fr", "council tax", "hm revenue & customs", "internal revenue service", "finanzamt",
                "agencia tributaria", "agenzia delle entrate",
            ],
            labels: [
                "revenu fiscal de référence", "nombre de parts", "impôt sur le revenu", "impôt sur le revenu net", "numéro fiscal",
                "référence de l'avis", "date de mise en recouvrement", "date limite de paiement", "taxable income", "tax year", "valuation band",
                "amount payable", "steuernummer", "festsetzung", "festgesetzte", "zu versteuerndes einkommen", "einkommensteuer",
                "solidaritätszuschlag", "erstattung", "ejercicio", "base liquidable", "cuota resultante", "irpf", "impuesto sobre la renta",
                "plazo de ingreso", "anno d'imposta", "imposta dovuta", "dichiarazione", "modello 730", "codice atto", "sanzioni",
            ],
            numberLabels: [
                "référence de l'avis", "numéro d'avis", "account reference", "reference number", "notice number", "justificante",
                "número de referencia", "codice atto", "numero atto",
            ]
        ),
        Entry(
            category: .insurance,
            titles: [
                "insurance certificate", "certificate of insurance", "certificate of motor insurance", "insurance policy", "policy schedule",
                "attestation d'assurance", "contrat d'assurance", "conditions particulières", "avis d'échéance", "carte verte", "versicherungsschein",
                "versicherungspolice", "versicherungsbestätigung", "póliza", "póliza de seguro", "certificado de seguro", "polizza",
                "polizza assicurativa", "certificato di assicurazione", "quietanza",
            ],
            nameWords: [
                "assurance", "assurances", "insurance", "versicherung", "*versicherung", "seguro", "seguros", "assicurazione", "assicurazioni",
            ],
            labels: [
                "policy number", "policyholder", "insured", "premium", "deductible", "coverage", "excess", "entitled to drive", "assuré", "assurée",
                "souscripteur", "assureur", "garanties", "franchise", "prime", "cotisation annuelle", "responsabilité civile", "police n°", "n° de police",
                "versicherungsnehmer", "versicherungsnehmerin", "versicherungsnummer", "versicherungsschein-nr", "versicherungssumme", "beitrag",
                "jahresbeitrag", "selbstbeteiligung", "tomador", "asegurado", "prima", "prima anual", "coberturas", "franquicia", "n° de póliza",
                "responsabilidad civil", "contraente", "assicurato", "premio", "premio annuo", "massimale", "garanzie", "polizza n°",
                "periodo di copertura", "responsabilità civile",
            ],
            numberLabels: [
                "policy number", "policy n°", "n° de police", "police n°", "numéro de police", "contrat n°", "n° de contrat", "numéro de contrat",
                "versicherungsschein-nr", "versicherungsscheinnummer", "versicherungsnummer", "vertragsnummer", "n° de póliza", "número de póliza",
                "póliza n°", "polizza n°", "numero di polizza", "n° polizza",
            ]
        ),
        Entry(
            category: .medical,
            titles: [
                "prescription", "medical certificate", "lab report", "laboratory report", "test results", "medical report", "discharge summary",
                "ordonnance", "certificat médical", "compte rendu", "compte-rendu", "résultats d'analyses", "arztbrief", "rezept", "befund", "*befund",
                "arbeitsunfähigkeitsbescheinigung", "informe médico", "receta", "receta médica", "analítica", "ricetta", "ricetta medica", "referto",
                "certificato medico",
            ],
            labels: [
                "patient", "patient name", "reference range", "doctor", "physician", "dosage", "tablet", "tablets", "twice a day", "pathology",
                "hospital", "laboratory", "patiente", "dr", "docteur", "médecin", "médecin généraliste", "rpps", "posologie", "comprimé", "comprimés",
                "fois par jour", "mg", "hôpital", "clinique", "laboratoire", "valeurs de référence", "arzt", "ärztin", "facharzt", "allgemeinmedizin",
                "praxis", "diagnose", "arbeitsunfähig", "tabletten", "täglich", "klinik", "krankenhaus", "labor", "referenzbereich", "paciente",
                "diagnóstico", "tratamiento", "médico", "médico de familia", "motivo de consulta", "dosis", "comprimidos", "clínica", "laboratorio",
                "valores de referencia", "paziente", "dott", "dott.ssa", "terapia", "esame obiettivo", "al giorno", "ospedale", "poliambulatorio",
                "valori di riferimento",
            ]
        ),
        Entry(
            category: .certificate,
            titles: [
                "certificate", "certificate of completion", "certificat", "certificat de scolarité", "attestation", "attestation de scolarité",
                "attestation employeur", "attestation sur l'honneur", "relevé de notes", "bescheinigung", "*bescheinigung", "meldebescheinigung",
                "zertifikat", "urkunde", "meldebestätigung", "certificado", "certificado de empadronamiento", "constancia", "certificato",
                "certificato di residenza", "attestato",
            ],
            weakTitles: ["récépissé"],
            labels: [
                "this is to certify", "hereby certify", "certifies that", "has successfully completed", "certifie que", "atteste que", "je soussigné",
                "je soussignée", "pour servir et valoir ce que de droit", "délivrée", "bescheinigt", "hiermit wird bescheinigt", "hiermit bestätigen wir",
                "certifica", "certifico", "hace constar", "si certifica", "certifica che", "si attesta", "attesta che",
            ],
            numberLabels: [
                "certificate n°", "certificate number", "n° d'attestation", "numéro d'attestation", "attestation n°", "certificat n°",
                "bescheinigungsnummer", "zertifikatsnummer", "certificado n°", "número de certificado", "certificato n°", "numero certificato",
            ]
        ),
        Entry(
            category: nil,
            titles: ["order", "purchase order", "commande", "bon de commande", "bestellung", "auftragsbestätigung", "pedido", "ordine", "avis", "bulletin"],
            numberLabels: [
                "customer number", "customer n°", "customer reference", "account reference", "our ref", "your ref", "case number", "file number",
                "référence client", "réf client", "n° client", "numéro client", "n° de client", "votre référence", "notre référence", "n° de dossier",
                "dossier n°", "kundennummer", "kunden-nr", "unser zeichen", "ihr zeichen", "aktenzeichen", "número de cliente", "n° cliente",
                "n° de cliente", "referencia", "codice cliente", "riferimento", "n° pratica",
            ]
        ),
    ]

    /// Salutations, closings and subject lines.
    static let letter = [
        "^madame", "^monsieur", "^madame monsieur", "^cher", "^chère", "^objet", "veuillez agréer", "je vous prie d'agréer", "nous vous prions d'agréer",
        "salutations distinguées", "^cordialement", "^bien cordialement", "^dear", "yours sincerely", "yours faithfully", "^kind regards",
        "^best regards", "^re", "^subject", "^sehr geehrte", "^sehr geehrter", "mit freundlichen grüßen", "^freundliche grüße", "^betreff",
        "^estimado", "^estimada", "^estimados", "^atentamente", "^un saludo", "^cordialmente", "^asunto", "^muy señor mío", "^gentile", "^egregio",
        "distinti saluti", "cordiali saluti", "^oggetto", "^spettabile",
    ]

    // MARK: Dates

    static let months: [String: Int] = [
        "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6, "july": 7, "august": 8, "september": 9, "october": 10, "november": 11, "december": 12,
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "sept": 9, "oct": 10, "nov": 11, "dec": 12,
        "janvier": 1, "fevrier": 2, "mars": 3, "avril": 4, "mai": 5, "juin": 6, "juillet": 7, "aout": 8, "septembre": 9, "octobre": 10, "novembre": 11, "decembre": 12,
        "janv": 1, "fevr": 2, "fev": 2, "avr": 4, "juil": 7,
        "januar": 1, "janner": 1, "februar": 2, "marz": 3, "juni": 6, "juli": 7, "oktober": 10, "dezember": 12, "okt": 10, "dez": 12,
        "enero": 1, "febrero": 2, "marzo": 3, "abril": 4, "mayo": 5, "junio": 6, "julio": 7, "agosto": 8, "septiembre": 9, "setiembre": 9, "octubre": 10,
        "noviembre": 11, "diciembre": 12, "ene": 1, "abr": 4, "ago": 8, "dic": 12,
        "gennaio": 1, "febbraio": 2, "aprile": 4, "maggio": 5, "giugno": 6, "luglio": 7, "settembre": 9, "ottobre": 10, "dicembre": 12,
        "gen": 1, "giu": 6, "lug": 7, "set": 9, "ott": 10,
    ]

    /// Labels that make the date next to them the date of the document.
    static let issueDateLabels = [
        "date de facture", "date de facturation", "date d'émission", "date d'établissement", "date d'édition", "date du devis", "émis le", "émise le",
        "édité le", "fait le", "date de paiement", "invoice date", "date of issue", "issue date", "issued on", "date issued", "statement date",
        "report date", "pay date", "payment date", "made on", "dated", "rechnungsdatum", "ausgestellt am", "erstellt am", "ausstellungsdatum",
        "belegdatum", "festgestellt am", "auszahlung am", "fecha de emisión", "fecha de expedición", "fecha factura", "fecha de factura",
        "fecha de pago", "data fattura", "data di emissione", "data emissione", "data referto", "data documento", "data pagamento",
    ]

    static let dateLabels = ["date", "datum", "fecha", "data", "le", "den", "del"]

    /// Words before a date that make it something else than the date of the document: due, validity, birth, start or delivery dates.
    static let otherDateLabels = [
        "échéance", "due", "payable", "pay by", "à payer avant", "limite", "zahlbar", "fällig", "vencimiento", "plazo", "scadenza", "scade", "entro",
        "valable", "validité", "valid", "expiry", "expire", "expires", "expiration", "gültig", "validez", "válido", "valido", "validità",
        "né le", "née le", "né(e) le", "naissance", "birth", "born", "dob", "geb", "geboren", "geburtsdatum", "nacimiento", "nacido", "nacida",
        "nato", "nata", "nascita", "effet", "effective", "commencement", "start", "begins", "beginn", "mietbeginn", "versicherungsbeginn",
        "einzugsdatum", "efecto", "vigor", "decorrenza", "attivazione", "à compter", "à partir", "a partir", "seit", "ab dem", "desde",
        "livraison", "delivery", "lieferdatum", "entrega", "consegna", "collected", "jusqu'au", "until", "hasta", "fino al", "bis",
    ]

    /// Words between two dates of a period, or before its first date.
    static let periodStarts = ["du", "from", "vom", "dal", "del", "période", "period", "zeitraum", "periodo"]
    static let periodEnds = ["au", "to", "bis", "al", "-", "–", "hasta"]

    // MARK: Issuer

    /// Legal forms of companies, folded and without dots.
    static let legalForms: Set<String> = [
        "sa", "sas", "sasu", "sarl", "eurl", "sci", "scop", "snc", "gmbh", "ag", "eg", "kg", "ohg", "ug", "ev", "kgaa", "ltd", "limited", "plc", "llp",
        "inc", "llc", "corp", "sl", "slu", "sau", "spa", "srl", "srls", "sapa", "bv", "nv",
    ]

    /// What heads the letters of a state rather than names who sent them.
    static let emblems = [
        "république française", "liberté égalité fraternité", "liberté", "égalité", "fraternité", "repubblica italiana",
        "bundesrepublik deutschland",
    ]

    /// The first words of a recipient line: "Mme", "Herrn", "Sig.ra".
    static let recipientPrefixes: Set<String> = [
        "m", "mme", "mlle", "madame", "monsieur", "mr", "mrs", "ms", "miss", "herr", "herrn", "frau", "sr", "sra", "srta", "d", "dna", "don", "dona",
        "sig", "sigra", "signor", "signora", "gentile", "gentma", "gentmo", "egregio", "spettle", "attn", "a l'attention",
    ]

    /// The first words of a professional who issues documents in their own name.
    static let professionalTitles: Set<String> = ["dr", "dra", "docteur", "doctor", "dott", "dottssa", "prof", "me", "maitre"]

    static let streetWords: Set<String> = [
        "rue", "avenue", "av", "boulevard", "bd", "allee", "place", "quai", "chemin", "impasse", "route", "cours", "bp", "cs", "cedex",
        "street", "st", "road", "rd", "lane", "crescent", "way", "close", "drive", "square", "walk", "po", "box",
        "strasse", "str", "weg", "platz", "allee", "ring", "gasse", "postfach", "calle", "avenida", "paseo", "plaza", "via", "viale", "piazza",
        "corso", "vicolo",
    ]

    /// Mail providers whose domains say nothing about the sender.
    static let mailProviders: Set<String> = [
        "gmail", "googlemail", "yahoo", "ymail", "outlook", "hotmail", "live", "msn", "icloud", "me", "mac", "aol", "orange", "wanadoo", "free",
        "laposte", "sfr", "neuf", "bbox", "gmx", "web", "t-online", "freenet", "libero", "virgilio", "tiscali", "alice", "tim", "proton",
        "protonmail", "btinternet", "sky", "telefonica", "movistar",
    ]
}
