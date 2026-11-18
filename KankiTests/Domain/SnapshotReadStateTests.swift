import XCTest
@testable import Kanki

final class SnapshotReadStateTests: XCTestCase {
    func testFailedReadInvalidatesPriorRequestEvenAfterSuccessfulReload() {
        var state = SnapshotReadState()
        let sent = state.generation
        XCTAssertTrue(state.acceptsResult(from: sent))
        state.didFail("Недоступно")
        XCTAssertFalse(state.isReadable)
        XCTAssertFalse(state.acceptsResult(from: sent))
        XCTAssertFalse(state.acceptsResult(from: state.generation))
        state.didLoad()
        XCTAssertFalse(state.acceptsResult(from: sent))
        XCTAssertTrue(state.acceptsResult(from: state.generation))
    }
}
