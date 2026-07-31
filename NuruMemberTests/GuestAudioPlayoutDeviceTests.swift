// Nuru Live — host-stability audit (2026-07-31). Pins the one piece of
// genuinely pure logic introduced by `GuestAudioPlayoutDevice`'s realtime-
// thread hardening: the round-robin index into the preallocated PCM buffer
// pool that CoreAudio's render callback advances on every call. Everything
// else that file does needs a real AudioUnit/AVAudioSession/WebRTC ADM
// callback to exercise — this test deliberately does NOT claim coverage of
// that; see `nextPoolIndex`'s own doc comment.
import XCTest
@testable import NuruMember

final class GuestAudioPlayoutDeviceTests: XCTestCase {
    func testAdvancesByOneWithinCapacity() {
        XCTAssertEqual(GuestAudioPlayoutDevice.nextPoolIndex(current: 0, capacity: 8), 1)
        XCTAssertEqual(GuestAudioPlayoutDevice.nextPoolIndex(current: 3, capacity: 8), 4)
    }

    func testWrapsAroundAtCapacity() {
        XCTAssertEqual(GuestAudioPlayoutDevice.nextPoolIndex(current: 7, capacity: 8), 0)
    }

    func testSingleSlotPoolAlwaysStaysAtZero() {
        XCTAssertEqual(GuestAudioPlayoutDevice.nextPoolIndex(current: 0, capacity: 1), 0)
    }

    /// Defensive floor — a zero-capacity pool should never happen (the pool
    /// is only ever built with `poolSize == 8`), but a render callback that
    /// somehow raced a teardown and saw an empty pool must not divide by
    /// zero and crash the realtime thread; it must return a harmless index.
    func testZeroCapacityNeverCrashes() {
        XCTAssertEqual(GuestAudioPlayoutDevice.nextPoolIndex(current: 5, capacity: 0), 0)
    }

    func testCyclesThroughEveryIndexExactlyOnceBeforeRepeating() {
        let capacity = 8
        var index = 0
        var seen: [Int] = []
        for _ in 0..<capacity {
            seen.append(index)
            index = GuestAudioPlayoutDevice.nextPoolIndex(current: index, capacity: capacity)
        }
        XCTAssertEqual(seen, Array(0..<capacity))
        XCTAssertEqual(index, 0, "should be back at the start after one full lap")
    }
}
