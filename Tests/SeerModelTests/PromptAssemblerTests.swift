import Testing
@testable import SeerModel

@Suite struct PromptAssemblerTests {
    @Test func scaffoldHasChatMLTurnsInOrder() {
        let s = PromptAssembler().scaffold
        #expect(s.hasPrefix("<|im_start|>system\n"))
        #expect(s.contains("<|im_end|>\n<|im_start|>user\n"))
        #expect(s.hasSuffix("<|im_start|>assistant\n"))
    }
    @Test func assemblePutsTextInVolatileContextAndMarksSpecial() {
        let asm = PromptAssembler()
        let p = asm.assemble(textBeforeCaret: "Thanks so much for")
        #expect(p.stablePrefix == asm.scaffold)        // scaffold is the byte-stable prefix
        #expect(p.context == "Thanks so much for")     // text-before-caret is volatile
        #expect(p.parseSpecial == true)                // ChatML markers need parse_special
    }
    @Test func customInstructionFlowsIntoScaffold() {
        let asm = PromptAssembler(system: "SYS", user: "USR")
        #expect(asm.scaffold == "<|im_start|>system\nSYS<|im_end|>\n<|im_start|>user\nUSR<|im_end|>\n<|im_start|>assistant\n")
    }
}
