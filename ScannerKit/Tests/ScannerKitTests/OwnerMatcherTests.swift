import CoreGraphics
import Foundation
import ScannerKit
import Testing

struct OwnerMatcherTests {
    let camille = Owner(name: "Camille Rouvière", symbol: .person)
    let holding = Owner(name: "Fernwood Holding", symbol: .building)

    private func line(_ text: String, x: CGFloat = 0.55, y: CGFloat) -> TextLine {
        TextLine(text: text, frame: CGRect(x: x, y: y, width: 0.3, height: 0.011))
    }

    private func owner(of texts: [String], among owners: [Owner], defaultOwner: Owner? = nil) -> RecognizedOwner? {
        let lines = texts.enumerated().map { line($1, y: 0.15 + CGFloat($0) * 0.02) }
        return OwnerMatcher(owners: owners, defaultOwnerID: (defaultOwner ?? owners[0]).id).match(lines).owner
    }

    private func matches(_ text: String, _ owner: Owner) -> Bool {
        owner.id == self.owner(of: [text], among: [owner])?.id
    }

    // MARK: Person

    @Test(arguments: [
        "Camille Rouvière", "ROUVIERE CAMILLE", "Mme Camille Rouvière", "Madame ROUVIÈRE Camille", "M. et Mme Camille Rouvière",
        "C. Rouvière", "Mme C. ROUVIERE", "Mme Rouvière", "M. et Mme Rouvière", "Monsieur et Madame Rouvière", "Famille Rouvière", "The Rouvière Family",
    ])
    func recognizesAPerson(text: String) {
        #expect(matches(text, camille))
    }

    @Test(arguments: ["Rouvière", "Camille", "Rouvière Immobilier", "Camille Rouvière Conseil", "Et Rouvière", "Mme Camille", "Noé Rouvière", "N. Rouvière"])
    func recognizesNoOtherPerson(text: String) {
        #expect(!matches(text, camille))
    }

    @Test func takesEveryWordAfterTheFirstNameAsAFamilyName() {
        let lucia = Owner(name: "Lucía Ferrándiz Soler", symbol: .person)
        for text in ["Sra. Lucía Ferrándiz Soler", "L. Ferrándiz Soler", "Sra. Ferrándiz Soler", "Sra. Ferrándiz", "Familia Soler"] {
            #expect(matches(text, lucia), "\(text)")
        }
        #expect(!matches("Ferrándiz Soler", lucia))
    }

    @Test func recognizesAHouseholdByItsFamilyName() {
        let household = Owner(name: "Famille Rouvière", symbol: .house)
        #expect(matches("M. et Mme Rouvière", household))
        #expect(matches("Mme Rouvière", household))
        #expect(!matches("Rouvière", household))
    }

    @Test func aSingleWordTellsNoPerson() {
        let personal = Owner(name: "Personal", symbol: .house)
        #expect(!matches("Personal", personal))
        #expect(!matches("Mme Personal", personal))
    }

    @Test func thePlaceholderNameTellsNothing() {
        let me = Owner(name: Owner.placeholderName, symbol: .person)
        #expect(!matches("Me", me))
        #expect(!matches("M. Me", me))
    }

    @Test func recognizesTheOtherNames() {
        var me = Owner(name: Owner.placeholderName, symbol: .person)
        me.names = ["Camille Delmas", "Delmas Conseil SARL"]
        #expect(matches("Mme C. Delmas", me))
        #expect(matches("DELMAS CONSEIL", me))
        #expect(!matches("Mme Rouvière", me))
    }

    // MARK: Company

    @Test(arguments: ["Fernwood Holding", "FERNWOOD HOLDING SAS", "Fernwood Holding S.A.S.", "Fernwood SAS", "Fernwood", "Holding Fernwood"])
    func recognizesACompany(text: String) {
        #expect(matches(text, holding))
    }

    @Test(arguments: ["Holding", "Holding SAS", "Fernwood Holding Conseil", "Fernwood Immobilier", "M. Fernwood"])
    func recognizesNoOtherCompany(text: String) {
        #expect(!matches(text, holding))
    }

    @Test func aLegalFormMakesACompanyWhateverTheSymbol() {
        let company = Owner(name: "Rouvière Conseil SARL", symbol: .person)
        #expect(matches("ROUVIÈRE CONSEIL", company))
        #expect(!matches("Mme Conseil", company))
    }

    @Test func aCompanyNamedOnlyWithGenericWordsKeepsThem() {
        let group = Owner(name: "Holding Group", symbol: .building)
        #expect(matches("Holding Group SA", group))
        #expect(!matches("Group", group))
    }

    // MARK: Address

    @Test func recognizesAnAddressOnOneOrTwoLines() {
        var owner = camille
        owner.addresses = ["8 rue des Glycines\n69007 Lyon"]
        let owners = [holding, owner]
        #expect(self.owner(of: ["8 rue des Glycines", "69007 Lyon"], among: owners) == RecognizedOwner(id: owner.id, clue: .address))
        #expect(self.owner(of: ["8, rue des Glycines 69007 LYON"], among: owners)?.id == owner.id)
        #expect(self.owner(of: ["Résidence du Parc", "8 RUE DES GLYCINES", "69007 LYON CEDEX 07"], among: owners)?.id == owner.id)
        #expect(self.owner(of: ["8 rue des Glycines", "69008 Lyon"], among: owners) == nil)
        #expect(self.owner(of: ["8 rue des Glycines", "Bâtiment B", "Escalier 2", "69007 Lyon"], among: owners) == nil)
    }

    @Test func readsAnAddressDownItsColumnOnly() {
        var owner = camille
        owner.addresses = ["8 rue des Glycines 69007 Lyon"]
        let lines = [
            line("Facture n° 2026-0042", x: 0.08, y: 0.15),
            line("8 rue des Glycines", y: 0.15),
            line("Date : 03/04/2026", x: 0.08, y: 0.17),
            line("69007 Lyon", y: 0.17),
        ]
        let match = OwnerMatcher(owners: [holding, owner], defaultOwnerID: holding.id).match(lines)
        #expect(match.owner?.id == owner.id)
        #expect(match.ownLines == [1, 3])
        let elsewhere = [line("8 rue des Glycines", x: 0.08, y: 0.15), line("69007 Lyon", x: 0.55, y: 0.17)]
        #expect(OwnerMatcher(owners: [holding, owner], defaultOwnerID: holding.id).match(elsewhere).owner == nil)
    }

    @Test func anAddressOfASingleWordTellsNothing() {
        var owner = camille
        owner.addresses = ["Lyon"]
        #expect(self.owner(of: ["Lyon"], among: [holding, owner]) == nil)
    }

    // MARK: Other forms

    @Test func listsTheOtherFormsOfThePersonNames() {
        var owner = camille
        owner.names = ["Camille Delmas"]
        #expect(owner.otherForms(region: "FR", language: "en") == ["C. Rouvière", "Mme Rouvière", "M. et Mme Rouvière", "Famille Rouvière", "C. Delmas", "Mme Delmas"])
        #expect(camille.otherForms(region: "GB", language: "en") == ["C. Rouvière", "Mrs Rouvière", "Mr and Mrs Rouvière", "The Rouvière Family"])
        #expect(camille.otherForms(region: "CH", language: "de") == ["C. Rouvière", "Frau Rouvière", "Herrn und Frau Rouvière", "Familie Rouvière"])
    }

    @Test func listsTheOtherFormsOfTheCompanyNames() {
        #expect(holding.otherForms(region: "FR", language: "fr") == ["Fernwood Holding SAS", "Fernwood SAS", "Fernwood"])
        #expect(Owner(name: "Fernwood Holding GmbH").otherForms(region: "FR", language: "fr") == ["Fernwood GmbH", "Fernwood", "Fernwood Holding"])
        #expect(Owner(name: "Halcyon Labs", symbol: .briefcase).otherForms(region: "US", language: "en") == ["Halcyon Labs LLC"])
    }

    @Test func listsNoOtherFormOfANameThatTellsNothing() {
        #expect(Owner(name: Owner.placeholderName, symbol: .person).otherForms(region: "FR", language: "fr").isEmpty)
        #expect(Owner(name: "Personal", symbol: .house).otherForms(region: "FR", language: "fr").isEmpty)
    }

    @Test(arguments: ["FR", "DE", "ES", "IT", "GB", "US"])
    func recognizesEveryOtherForm(region: String) {
        var person = Owner(name: "Lucía Ferrándiz Soler", symbol: .person)
        person.names = ["Lucía Ferrándiz", "Famille Rouvière"]
        for owner in [person, holding, Owner(name: "Fernwood Holding SAS", symbol: .person)] {
            let forms = owner.otherForms(region: region, language: nil)
            #expect(!forms.isEmpty)
            for form in forms {
                #expect(matches(form, owner), "\(form)")
            }
        }
    }

    // MARK: Where and which

    @Test func readsOnlyTheTopHalfOfThePage() {
        let matcher = OwnerMatcher(owners: [holding, camille], defaultOwnerID: holding.id)
        #expect(matcher.match([line("Mme Camille Rouvière", y: 0.45)]).owner?.id == camille.id)
        let bottom = matcher.match([line("Mme Camille Rouvière", y: 0.55)])
        #expect(bottom.owner == nil)
        #expect(bottom.ownLines.isEmpty)
    }

    @Test func aNameWinsOverAnAddress() {
        var owner = camille
        owner.addresses = ["8 rue des Glycines 69007 Lyon"]
        #expect(self.owner(of: ["Fernwood SAS", "8 rue des Glycines", "69007 Lyon"], among: [owner, holding]) == RecognizedOwner(id: holding.id, clue: .name))
    }

    @Test func anotherOwnerNamedWithTheDefaultOneWins() {
        let lines = ["Fernwood Holding", "Mme Camille Rouvière"]
        #expect(owner(of: lines, among: [camille, holding]) == RecognizedOwner(id: holding.id, clue: .name))
        #expect(owner(of: lines, among: [camille, holding], defaultOwner: holding) == RecognizedOwner(id: camille.id, clue: .name))
        let employer = Owner(name: "Halcyon Labs", symbol: .briefcase)
        #expect(owner(of: lines + ["Halcyon Labs"], among: [camille, holding, employer]) == nil)
    }

    @Test func twoOwnersWithTheSameFamilyNameTellNothingButTheirAddress() {
        var noe = Owner(name: "Noé Rouvière", symbol: .person)
        noe.addresses = ["3 impasse des Tilleuls 38000 Grenoble"]
        var me = camille
        me.addresses = ["8 rue des Glycines 69007 Lyon"]
        let owners = [holding, me, noe]
        #expect(owner(of: ["Famille Rouvière"], among: owners) == nil)
        #expect(owner(of: ["Famille Rouvière", "3 impasse des Tilleuls", "38000 Grenoble"], among: owners) == RecognizedOwner(id: noe.id, clue: .address))
        #expect(owner(of: ["Mme Camille Rouvière"], among: owners)?.id == me.id)
    }

    @Test func anAddressSharedByTwoOwnersTellsNothing() {
        var me = camille
        me.addresses = ["8 rue des Glycines 69007 Lyon"]
        var company = holding
        company.addresses = ["8, rue des Glycines\n69007 Lyon"]
        #expect(owner(of: ["8 rue des Glycines", "69007 Lyon"], among: [me, company]) == nil)
        #expect(Owner.isSameAddress(me.addresses[0], as: company.addresses[0]))
        #expect(!Owner.isSameAddress(me.addresses[0], as: "8 rue des Glycines 69008 Lyon"))
    }

    @Test func marksTheNameAndAddressOfEveryOwnerAsTheirOwnLines() {
        var me = camille
        me.addresses = ["8 rue des Glycines 69007 Lyon"]
        var noe = Owner(name: "Noé Rouvière", symbol: .person)
        noe.addresses = ["8 rue des Glycines 69007 Lyon"]
        let lines = [line("Lumen Énergie", x: 0.08, y: 0.04), line("Famille Rouvière", y: 0.15), line("8 rue des Glycines", y: 0.17), line("69007 Lyon", y: 0.19)]
        let match = OwnerMatcher(owners: [me, noe], defaultOwnerID: me.id).match(lines)
        #expect(match.owner == nil)
        #expect(match.ownLines == [1, 2, 3])
        #expect(OwnerMatcher(owners: [me], defaultOwnerID: me.id).match(lines).ownLines == [1, 2, 3])
    }
}
