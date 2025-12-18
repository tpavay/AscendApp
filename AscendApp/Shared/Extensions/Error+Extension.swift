//
//  Error+Extension.swift
//  AscendApp
//
//  Created by Claude on 12/18/25.
//

import Foundation

extension Error {
    /// Returns a user-friendly error message suitable for display in alerts
    var userFriendlyMessage: String {
        let nsError = self as NSError

        // Check for common URL/network error codes
        if nsError.domain == NSURLErrorDomain || nsError.domain == "NSURLErrorDomain" {
            switch nsError.code {
            case -1200: // NSURLErrorSecureConnectionFailed / TLS error
                return "Secure connection failed. Try a different network (or disable VPN) and try again."
            case -1009: // NSURLErrorNotConnectedToInternet
                return "You're offline. Connect to the internet and try again."
            case -1001, -1003, -1004, -1006: // Timeout, cannot find/connect to host, DNS lookup failed
                return "Can't reach the server right now. Try again."
            case -1005: // NSURLErrorNetworkConnectionLost
                return "Can't reach the server right now. Try again."
            case -1011, -1015, -1017: // Bad server response, cannot decode/parse (5xx-like)
                return "Server issue on our end. Try again in a few minutes."
            case -1018: // NSURLErrorInternationalRoamingOff
                return "Data roaming is off. Enable it or use Wi-Fi."
            case -1020: // NSURLErrorDataNotAllowed
                return "Cellular data is off for Ascend. Enable it in Settings or use Wi-Fi."
            default:
                break
            }
        }

        // Check for Firebase Storage errors by examining the error message
        let errorDescription = nsError.localizedDescription.lowercased()
        if errorDescription.contains("unexpected") && errorDescription.contains("code from backend") {
            // This is a Firebase error wrapping a network error - extract the underlying cause
            if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                return underlyingError.userFriendlyMessage
            }
            // Check if it contains network-related codes
            if errorDescription.contains("-1200") || errorDescription.contains("tls") || errorDescription.contains("secure connection") {
                return "Secure connection failed. Try a different network (or disable VPN) and try again."
            }
            if errorDescription.contains("-1009") || errorDescription.contains("not connected") {
                return "You're offline. Connect to the internet and try again."
            }
            if errorDescription.contains("-1001") || errorDescription.contains("timed out") {
                return "Can't reach the server right now. Try again."
            }
            // Generic fallback for unknown backend errors
            return "We couldn't sync right now. Try again."
        }

        // Check for "serverError" in userInfo (Firebase pattern)
        if let serverError = nsError.userInfo["serverError"] as? [String: Any] {
            if let responseCode = serverError["ResponseErrorCode"] as? Int {
                let tempError = NSError(domain: NSURLErrorDomain, code: responseCode, userInfo: nil)
                let friendlyMessage = tempError.userFriendlyMessage
                // Only use if we got a specific message (not the generic fallback)
                if !friendlyMessage.contains("couldn't sync") {
                    return friendlyMessage
                }
            }
        }

        // Default fallback
        return "We couldn't sync right now. Try again."
    }
}
