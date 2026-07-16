import Foundation

let check = Check()
runSmokeChecks(check)
runGeometryChecks(check)
runWordTokenizerChecks(check)
runCompletionStreamParserChecks(check)
runPasteboardGuardChecks(check)
check.summary("SeerSpikeCore")
exit(check.exitCode)
