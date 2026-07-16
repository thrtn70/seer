import SeerSpikeCore

func runCompletionStreamParserChecks(_ c: Check) {
    c.expect(CompletionStreamParser.parse(line: #"data: {"content":" refund","stop":false}"#)
             == CompletionChunk(text: " refund", done: false), "parses content")
    c.expect(CompletionStreamParser.parse(line: #"data: {"content":"","stop":true}"#)
             == CompletionChunk(text: "", done: true), "parses stop")
    c.expect(CompletionStreamParser.parse(line: "") == nil, "ignores blank line")
    c.expect(CompletionStreamParser.parse(line: ": keep-alive") == nil, "ignores keep-alive")
    c.expect(CompletionStreamParser.parse(line: "data: not-json") == nil, "ignores malformed json")
}
