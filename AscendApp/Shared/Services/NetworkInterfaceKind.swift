import Foundation
import Network

/// The kind of link the phone's current network path runs over. Diagnostics only: a failed read
/// during a Wi-Fi to cellular handoff looks identical to any other until this is recorded with it.
enum NetworkInterfaceKind: String, Sendable, CaseIterable {
    case wifi
    case cellular
    case wired
    case other
    case none

    init(path: NWPath) {
        guard path.status == .satisfied else {
            self = .none
            return
        }

        if path.usesInterfaceType(.wifi) {
            self = .wifi
        } else if path.usesInterfaceType(.cellular) {
            self = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            self = .wired
        } else {
            self = .other
        }
    }
}
