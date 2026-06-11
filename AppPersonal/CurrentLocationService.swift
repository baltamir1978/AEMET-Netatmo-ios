import Foundation
import CoreLocation

/// One-shot GPS fix using the CLLocationManager delegate, exposed as async/await.
final class CurrentLocationService: NSObject, CLLocationManagerDelegate {
    static let shared = CurrentLocationService()

    enum LocError: Error { case denied }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Returns the current coordinate, requesting permission the first time.
    func currentCoordinate() async throws -> CLLocationCoordinate2D {
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted { throw LocError.denied }
        return try await withCheckedThrowingContinuation { cont in
            continuation = cont
            if status == .notDetermined {
                manager.requestWhenInUseAuthorization()   // resolved in didChangeAuthorization
            } else {
                manager.requestLocation()
            }
        }
    }

    private func finish(_ result: Result<CLLocationCoordinate2D, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(with: result)
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        if let c = locs.last?.coordinate { finish(.success(c)) }
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(error))
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        guard continuation != nil else { return }
        switch m.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: m.requestLocation()
        case .denied, .restricted:                    finish(.failure(LocError.denied))
        default: break
        }
    }
}
