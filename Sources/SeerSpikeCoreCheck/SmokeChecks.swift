import SeerSpikeCore

func runSmokeChecks(_ c: Check) {
    c.equal(SeerSpikeCore.marker, "phase-0", "marker")
}
