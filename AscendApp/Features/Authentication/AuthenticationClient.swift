import Foundation

@MainActor
protocol AuthenticationClient: AnyObject {
    func signInWithGoogle() async throws
    func signInWithEmail(email: String, password: String) async throws
    func signInWithApple() async throws
    func signOut() throws
    func updateUserDisplayName(displayName: String) async throws
}

@MainActor
final class LiveAuthenticationClient: AuthenticationClient {
    private let service: AuthenticationService

    init(service: AuthenticationService = AuthenticationService()) {
        self.service = service
    }

    func signInWithGoogle() async throws {
        _ = try await service.signInWithGoogle()
    }

    func signInWithEmail(email: String, password: String) async throws {
        _ = try await service.signInWithEmail(email: email, password: password)
    }

    func signInWithApple() async throws {
        _ = try await service.signInWithApple()
    }

    func signOut() throws {
        try service.signOut()
    }

    func updateUserDisplayName(displayName: String) async throws {
        try await service.updateUserDisplayName(displayName: displayName)
    }
}
