// Nuru Live — guest-video auth-can-never-authenticate fix (2026-07-31). Pins
// the one piece of this fix that's pure logic: the HTTP Basic
// `Authorization` header `WhipHTTP` now builds for the WHIP/WHEP POST (and
// best-effort on the session DELETE), replacing the `?user=&pass=` query
// parameters MediaMTX v1.19.3 was proven (against production, same night) to
// silently ignore for WHIP/WHEP. See `WhipBasicAuth`'s header comment in
// WebRTCSupport.swift for the full story — this test does not exercise the
// network call itself (that needs a real MediaMTX), only the header value.
import XCTest
@testable import NuruMember

final class WhipBasicAuthTests: XCTestCase {
    func testHeaderValueIsStandardBase64EncodedUserColonPass() {
        let value = WhipBasicAuth.headerValue(user: "alice", pass: "s3cr3t")
        XCTAssertEqual(value, "Basic YWxpY2U6czNjcjN0")
        // Round-trip: decoding the base64 payload back out must reproduce
        // exactly "user:pass" — the RFC 7617 wire format MediaMTX (and every
        // other Basic-auth consumer) expects.
        let encoded = String(value.dropFirst("Basic ".count))
        let decoded = Data(base64Encoded: encoded).flatMap { String(data: $0, encoding: .utf8) }
        XCTAssertEqual(decoded, "alice:s3cr3t")
    }

    func testHeaderValueHandlesAUUIDUserAndTokenPass() {
        // The real shape: `user` is a stream/guest UUID, `pass` is an
        // opaque, potentially long, random guest token / stream key.
        let user = "3f9b6d2e-1c4a-4e9a-8b2f-6b6e2e9b0a11"
        let pass = "gTk_7hQpL9xR2vMzAeUuFb3c"
        let value = WhipBasicAuth.headerValue(user: user, pass: pass)
        XCTAssertTrue(value.hasPrefix("Basic "))
        let encoded = String(value.dropFirst("Basic ".count))
        let decoded = Data(base64Encoded: encoded).flatMap { String(data: $0, encoding: .utf8) }
        XCTAssertEqual(decoded, "\(user):\(pass)")
    }

    func testApplySetsTheAuthorizationHeaderOnTheRequest() {
        var request = URLRequest(url: URL(string: "https://live.example.org/whip/guest/stream1-guest-u1")!)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        WhipBasicAuth.apply(user: "u1", pass: "tok", to: &request)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), WhipBasicAuth.headerValue(user: "u1", pass: "tok"))
    }

    /// Guards the actual bug: credentials must never leak back into the
    /// query string this fix deliberately removed them from.
    func testCredentialsNeverAppearInAURLQueryString() {
        let url = URL(string: "https://live.example.org/whip/guest/stream1-guest-u1")!
        var request = URLRequest(url: url)
        WhipBasicAuth.apply(user: "u1", pass: "super-secret-token", to: &request)
        XCTAssertEqual(request.url, url, "the URL itself must be untouched by applying auth")
        XCTAssertFalse(request.url?.absoluteString.contains("super-secret-token") ?? true)
        XCTAssertFalse(request.url?.query?.contains("user") ?? false)
    }
}
