import Testing
@testable import SeerModel

@Suite struct HashingTests {
    @Test func emptyIsOffsetBasis() {
        #expect(Hashing.fnv1a64("".utf8) == 0xcbf29ce484222325)
    }
    @Test func knownVectorA() {
        #expect(Hashing.fnv1a64("a".utf8) == 0xaf63dc4c8601ec8c)
    }
    @Test func deterministicAndDistinct() {
        #expect(Hashing.fnv1a64("hello".utf8) == Hashing.fnv1a64("hello".utf8))
        #expect(Hashing.fnv1a64("hello".utf8) != Hashing.fnv1a64("world".utf8))
    }
}
