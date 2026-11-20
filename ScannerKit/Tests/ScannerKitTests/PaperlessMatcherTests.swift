import ScannerKit
import Testing

struct PaperlessMatcherTests {
    private func matcher(_ names: String...) -> PaperlessMatcher {
        PaperlessMatcher(names.enumerated().map { PaperlessObject(id: $0.offset + 1, name: $0.element) })
    }

    @Test(arguments: [
        ("lumen energy", "Lumen Energy"),
        ("LUMEN ÉNERGIE", "Lumen Énergie"),
        ("Lumen Energie", "Lumen Énergie"),
        ("Lumen-Énergie.", "Lumen Énergie"),
        ("Lumen Énergie S.A.S.", "Lumen Énergie"),
        ("Fernwood GmbH", "Fernwood Ltd"),
        ("Fernwood, Inc.", "Fernwood Ltd"),
        ("Northwind LLC", "Northwind SARL"),
    ])
    func ignoresCaseAccentsPunctuationAndLegalForms(name: String, expected: String) {
        let matcher = matcher("Lumen Énergie", "Fernwood Ltd", "Northwind SARL", "Lumen Energy")
        #expect(matcher.match(name)?.name == expected)
    }

    @Test func prefersTheNameThatOnlyDiffersByCase() {
        #expect(matcher("Voltaria SA", "voltaria").match("VOLTARIA")?.id == 2)
    }

    @Test(arguments: [("Taxi V7", "V7"), ("V7", "Taxi V7"), ("Voltaria Énergie Services", "Voltaria Énergie"), ("Fernwood", "Fernwood Holding SAS")])
    func matchesANameHoldingTheOtherAsWholeWords(name: String, expected: String) {
        #expect(matcher(expected, "Lumen").match(name)?.name == expected)
    }

    @Test(arguments: [("Taxi V7", "V7"), ("V7", "Taxi V7"), ("Fernwood Cloud Services EMEA", "Fernwood Cloud Services")])
    func aCosmeticToleranceNeverMatchesANameHoldingTheOther(name: String, existing: String) {
        let matcher = matcher(existing, "Fernwood", "Lumen")
        #expect(matcher.match(name)?.name == existing)
        #expect(matcher.match(name, tolerance: .cosmetic) == nil)
    }

    @Test(arguments: [("lumen energy sas", "Lumen Energy"), ("Lumen-Énergie", "Lumen Énergie"), ("Northwind Labs", "NorthwindLabs")])
    func aCosmeticToleranceStillIgnoresCaseAccentsPunctuationLegalFormsAndSpaces(name: String, expected: String) {
        #expect(matcher("Lumen", "Lumen Énergie", "Lumen Energy", "NorthwindLabs").match(name, tolerance: .cosmetic)?.name == expected)
    }

    @Test(arguments: ["Taxis V7x", "Voltariane", "Énergie Voltaria"])
    func refusesWordsThatOnlyStartAlikeOrComeInAnotherOrder(name: String) {
        #expect(matcher("Taxi V7", "Voltaria Énergie").match(name) == nil)
    }

    @Test(arguments: ["AB Conseil", "Banque de France", "Holding Lumen", "The Lumen Company"])
    func refusesANameTooShortOrTooGenericToBeHeld(name: String) {
        #expect(matcher("AB", "de", "Holding", "The Company").match(name) == nil)
    }

    @Test func refusesSeveralNamesThatCouldBeMeant() {
        #expect(matcher("Taxi", "V7").match("Taxi V7") == nil)
        #expect(matcher("Lumen Store", "Lumen Music").match("Lumen") == nil)
        #expect(matcher("Lumen SA", "Lumen Inc").match("Lumen SARL") == nil)
        #expect(matcher("Lumen", "Lumen Energy Services").match("Lumen Energy") == nil)
        #expect(matcher("Fernwood", "Fernwood Cloud", "Cloud Bank").match("Fernwood Cloud Bank") == nil)
        #expect(matcher("Fernwood Cloud", "Fernwood Cloud SA").match("Fernwood Cloud Services") == nil)
    }

    @Test(arguments: [("Northwind Labs", "NorthwindLabs"), ("NorthwindLabs", "Northwind Labs"), ("Open Lumen SAS", "OpenLumen"), ("Volt-Aria", "Voltaria")])
    func matchesTheSameWordsJoinedOrSplit(name: String, expected: String) {
        #expect(matcher("Northwind", expected, "Lumen").match(name)?.name == expected)
    }

    @Test func refusesSeveralNamesWithTheSameLettersJoined() {
        #expect(matcher("Northwind Labs", "North Wind Labs").match("NorthwindLabs") == nil)
    }

    @Test func picksTheMostSpecificOfNestedNamesTheIssuerHolds() {
        let matcher = matcher("Fernwood", "Fernwood Cloud Services", "Fernwood Cloud", "Lumen")
        #expect(matcher.match("Fernwood Cloud Services EMEA SARL")?.name == "Fernwood Cloud Services")
        #expect(matcher.match("Fernwood Cloud Paris")?.name == "Fernwood Cloud")
    }

    @Test func prefersTheSameWordsToANameHoldingThem() {
        #expect(matcher("Lumen", "Lumen SAS Services").match("Lumen Ltd")?.name == "Lumen")
    }

    @Test(arguments: ["", "  ", "-", "SAS"])
    func matchesNothingWithoutAName(name: String) {
        #expect(matcher("Lumen", "SA").match(name) == nil)
    }

    @Test func suggestsTheMatchThenNamesStartingLikeTheTextThenNamesSharingAWord() {
        let matcher = matcher("Voltaria Énergie", "Volt Services", "Lumen Énergie", "Énergies Nouvelles", "Northwind")
        #expect(matcher.suggestions(for: "volt").map(\.name) == ["Volt Services", "Voltaria Énergie"])
        #expect(matcher.suggestions(for: "Voltaria Énergie Services").map(\.name) == ["Voltaria Énergie", "Lumen Énergie", "Volt Services"])
        #expect(matcher.suggestions(for: "ener").map(\.name) == ["Énergies Nouvelles", "Lumen Énergie", "Voltaria Énergie"])
        #expect(matcher.suggestions(for: "", limit: 3).isEmpty)
        #expect(matcher.suggestions(for: "e", limit: 2).count == 2)
    }
}
