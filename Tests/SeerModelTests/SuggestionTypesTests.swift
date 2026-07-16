import Testing
@testable import SeerModel

@Suite struct SuggestionTypesTests {
    @Test func acceptKindCases() {
        #expect(AcceptKind.nextWord != AcceptKind.wholeLine)
    }
    @Test func acceptStateDefaultsComparable() {
        #expect(AcceptState.idle != AcceptState.showing)
        #expect(AcceptState.showing != AcceptState.accepting)
    }
    @Test func suggestionStoresFields() {
        let s = Suggestion(text: " world", chunks: [" world"], forPrefixHash: 42)
        #expect(s.text == " world")
        #expect(s.chunks == [" world"])
        #expect(s.forPrefixHash == 42)
    }
}
