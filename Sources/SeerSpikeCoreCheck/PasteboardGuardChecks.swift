import SeerSpikeCore

func runPasteboardGuardChecks(_ c: Check) {
    c.expect(PasteboardGuard.shouldRestore(afterSetChangeCount: 11, currentChangeCount: 11),
             "restore when untouched")
    c.expect(!PasteboardGuard.shouldRestore(afterSetChangeCount: 11, currentChangeCount: 12),
             "skip restore when clipboard manager interfered")
}
