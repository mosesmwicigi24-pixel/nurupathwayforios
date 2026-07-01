// LocationManager — a small CoreLocation helper for the Profile "Share my
// approximate location" privacy toggle. When the member turns the toggle ON, we
// need a single coarse (~kilometer) location fix to POST /me/location {lat,lng}.
// Wraps one CLLocationManager and bridges its callback API to async/await; every
// stored continuation is resumed EXACTLY once (nil'd before resume) so we never
// double-resume (a crash) or leak a suspended task. When-In-Use only.
import CoreLocation
import Foundation

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    // Pending continuations. Each is set right before we await, and cleared the
    // instant it is resumed. A delegate callback with no pending continuation is
    // a stray/duplicate event and is ignored.
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var fixContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.delegate = self
    }

    var isAuthorized: Bool {
        let s = manager.authorizationStatus
        return s == .authorizedWhenInUse || s == .authorizedAlways
    }

    var isDenied: Bool {
        let s = manager.authorizationStatus
        return s == .denied || s == .restricted
    }

    /// Ensures When-In-Use authorization (requesting it if `.notDetermined`),
    /// then returns ONE coarse coordinate, or nil if permission is
    /// denied/restricted or the fix fails.
    func requestCoarseFix() async -> CLLocationCoordinate2D? {
        var status = manager.authorizationStatus

        if status == .notDetermined {
            status = await withCheckedContinuation { (cont: CheckedContinuation<CLAuthorizationStatus, Never>) in
                // If a request is somehow already in flight, don't strand it.
                authContinuation?.resume(returning: manager.authorizationStatus)
                authContinuation = cont
                manager.requestWhenInUseAuthorization()
            }
        }

        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            return nil
        }

        return await withCheckedContinuation { (cont: CheckedContinuation<CLLocationCoordinate2D?, Never>) in
            fixContinuation?.resume(returning: nil)
            fixContinuation = cont
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate
    // Delegates are marked nonisolated to satisfy the protocol under strict
    // concurrency; each hops back onto the main actor before touching state.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            // Only meaningful once the pending request has actually resolved.
            guard status != .notDetermined, let cont = self.authContinuation else { return }
            self.authContinuation = nil
            cont.resume(returning: status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.first?.coordinate
        Task { @MainActor in
            guard let cont = self.fixContinuation else { return }
            self.fixContinuation = nil
            cont.resume(returning: coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard let cont = self.fixContinuation else { return }
            self.fixContinuation = nil
            cont.resume(returning: nil)
        }
    }
}
