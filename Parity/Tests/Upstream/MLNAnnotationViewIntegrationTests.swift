// Copied from platform/ios/test/MLNAnnotationViewIntegrationTests.swift at ios-v7.0.0 by Parity/Tests/Upstream/import-upstream.py.
// See ADAPTATIONS.md before editing.

import MapLibre
import XCTest

class CustomAnnotationView: MLNAnnotationView {
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}

class MLNAnnotationViewIntegrationTests: XCTestCase {
    func testCreatingCustomAnnotationView() {
        let customAnnotationView = CustomAnnotationView(reuseIdentifier: "resuse-id")
        XCTAssertNotNil(customAnnotationView)
    }
}
