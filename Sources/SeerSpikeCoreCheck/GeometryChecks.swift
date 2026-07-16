import CoreGraphics
import SeerSpikeCore

func runGeometryChecks(_ c: Check) {
    let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    c.equal(Geometry.flipY(axTop: 100, height: 20, primaryHeight: 1000), 880, "flipY")
    c.expect(!Geometry.isValid(.zero, primaryFrame: primary), "reject zero rect")
    c.expect(!Geometry.isValid(CGRect(x: 5000, y: 5000, width: 2, height: 18), primaryFrame: primary), "reject offscreen")
    c.expect(Geometry.isValid(CGRect(x: 120, y: 300, width: 2, height: 18), primaryFrame: primary), "accept onscreen")
    c.expect(!Geometry.isValid(CGRect(x: 0, y: 0, width: 50_000, height: 18), primaryFrame: primary), "reject absurd size")
}
