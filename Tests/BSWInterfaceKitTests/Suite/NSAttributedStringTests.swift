#if canImport(UIKit)

import XCTest
import BSWInterfaceKit
import SnapshotTesting

class NSAttributedStringTests: XCTestCase {
    func testLinks() {
        let attributedString = NSAttributedString(string: "Welcome to the jungle")
            .addingLink(onSubstring: "jungle", linkURL: URL(string: "https://www.youtube.com/watch?v=o1tj2zJ2Wvg")!, linkColor: .systemBlue)
        assertSnapshot(matching: attributedString, as: .dump)
    }
    
    func testBolding() {
        let attributedString = TextStyler.styler.attributedString("Welcome to the jungle")
        let boldingJungle = attributedString.bolding(substring: "jungle")
        assertSnapshot(matching: boldingJungle, as: .dump)
    }

    func testLineHeightMultiplier() {
        let attributedString = TextStyler.styler.attributedString("Welcome to the jungle\nwe've got fun and games").settingLineHeightMultiplier(1.2)
        assertSnapshot(matching: attributedString, as: .dump)
    }
}

#endif
