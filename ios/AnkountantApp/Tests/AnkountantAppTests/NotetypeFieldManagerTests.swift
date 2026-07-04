import AnkiProto
import Testing
@testable import AnkountantApp

@Suite("Notetype field manager")
struct NotetypeFieldManagerTests {
    @Test func validationRequiresAtLeastOneNamedUniqueField() {
        #expect(notetypeFieldValidationIssue(for: []) == .noFields)
        #expect(notetypeFieldValidationIssue(for: [field(" ")]) == .blankName)
        #expect(notetypeFieldValidationIssue(for: [field("Front"), field("front")]) == .duplicateName("front"))
        #expect(notetypeFieldValidationIssue(for: [field("Front"), field("Back")]) == nil)
    }

    @Test func newFieldCopiesDisplayDefaultsButKeepsOrdinalUnset() {
        var template = field("Front", ord: 0)
        var config = template.config
        config.fontName = "Hiragino Sans"
        config.fontSize = 18
        config.rtl = true
        config.plainText = true
        config.id = 123
        config.tag = 456
        template.config = config

        let added = makeNotetypeField(named: "  Extra  ", matching: [template])

        #expect(added.name == "Extra")
        #expect(!added.hasOrd)
        #expect(added.config.fontName == "Hiragino Sans")
        #expect(added.config.fontSize == 18)
        #expect(added.config.rtl)
        #expect(added.config.plainText)
        #expect(!added.config.hasID)
        #expect(!added.config.hasTag)
    }

    private func field(_ name: String, ord: UInt32? = nil) -> Anki_Notetypes_Notetype.Field {
        var field = Anki_Notetypes_Notetype.Field()
        field.name = name
        if let ord {
            var protoOrd = Anki_Generic_UInt32()
            protoOrd.val = ord
            field.ord = protoOrd
        }
        return field
    }
}
