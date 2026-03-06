import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class LocationPermissionManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationPermissionManager()

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var locationSummary: UserLocationSummary = .empty

    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    private override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func requestWhenInUse() async -> CLAuthorizationStatus {
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            return authorizationStatus
        }

        manager.requestWhenInUseAuthorization()

        while authorizationStatus == .notDetermined {
            try? await Task.sleep(for: .milliseconds(120))
        }

        return authorizationStatus
    }

    func fetchLocationSummary() async -> UserLocationSummary? {
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            return nil
        }

        let location = await requestCurrentLocation()
        guard let location else { return nil }

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }

            let summary = UserLocationSummary(
                country: placemark.country ?? "",
                region: placemark.administrativeArea ?? "",
                city: placemark.locality ?? ""
            )
            locationSummary = summary
            return summary
        } catch {
            return nil
        }
    }

    private func requestCurrentLocation() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let updatedStatus = manager.authorizationStatus
        Task { @MainActor in
            authorizationStatus = updatedStatus
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.first?.coordinate

        Task { @MainActor in
            guard let coordinate else {
                locationContinuation?.resume(returning: nil)
                locationContinuation = nil
                return
            }

            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(returning: nil)
            locationContinuation = nil
        }
    }
}
