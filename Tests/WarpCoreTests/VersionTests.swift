import Testing
@testable import WarpCore
@Test func versionCheck() { #expect(WarpNestVersion.current == "0.1.0-alpha") }
