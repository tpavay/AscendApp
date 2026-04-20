import SwiftUI

struct InternalQASignInView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var email = ""
    @State private var password = ""
    @State private var localCredentials: InternalQALocalCredentials?
    @State private var didLoadLocalCredentials = false

    @FocusState private var isEmailFocused: Bool
    @FocusState private var isPasswordFocused: Bool

    private var isSigningIn: Bool {
        authVM.authenticationState == .authenticatingWithInternalQA
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection

                if let localCredentials {
                    localCredentialsSection(credentials: localCredentials)
                }

                manualCredentialsSection

                if let errorMessage = authVM.errorMessage {
                    Text(errorMessage)
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.leading)
                }

                signInButton

                guidanceSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .themedBackground()
        .navigationTitle("Internal QA")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneToolbar {
            isEmailFocused = false
            isPasswordFocused = false
        }
        .task {
            authVM.errorMessage = nil
            loadLocalCredentialsIfNeeded()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Internal QA Sign-In")
                .font(.montserratBold(size: 28))
                .foregroundStyle(colorScheme == .dark ? .white : .black)

            Text("Use a dedicated dev or staging Firebase email/password account. This path is excluded from production builds.")
                .font(.montserratRegular(size: 15))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.72) : .gray.opacity(0.9))
        }
    }

    private func localCredentialsSection(credentials: InternalQALocalCredentials) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Local Credentials Detected")
                .font(.montserratSemiBold(size: 16))
                .foregroundStyle(colorScheme == .dark ? .white : .black)

            Text(credentials.email)
                .font(.montserratRegular(size: 14))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.72) : .gray.opacity(0.9))
                .privacySensitive()

            Button {
                Task {
                    await signIn(email: credentials.email, password: credentials.password)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text(isSigningIn ? "Signing In..." : "Use Local QA Credentials")
                        .font(.montserratSemiBold)
                    Spacer()
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.orange)
                )
            }
            .disabled(isSigningIn)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(colorScheme == .dark ? Color.orange.opacity(0.12) : Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.orange.opacity(colorScheme == .dark ? 0.4 : 0.28), lineWidth: 1)
        )
    }

    private var manualCredentialsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localCredentials == nil ? "Credentials" : "Use Another QA Account")
                .font(.montserratSemiBold(size: 16))
                .foregroundStyle(colorScheme == .dark ? .white : .black)

            HStack(spacing: 12) {
                Image(systemName: "envelope")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.gray)
                    .frame(width: 24)

                TextField("qa@example.com", text: $email)
                    .font(.montserratRegular(size: 16))
                    .focused($isEmailFocused)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .onSubmit {
                        isPasswordFocused = true
                    }
            }
            .padding(16)
            .background(fieldBackground)

            HStack(spacing: 12) {
                Image(systemName: "lock")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.gray)
                    .frame(width: 24)

                SecureField("Password", text: $password)
                    .font(.montserratRegular(size: 16))
                    .focused($isPasswordFocused)
                    .textContentType(.password)
                    .onSubmit {
                        Task {
                            await signIn(email: email, password: password)
                        }
                    }
            }
            .padding(16)
            .background(fieldBackground)
        }
    }

    private var signInButton: some View {
        Button {
            Task {
                await signIn(email: email, password: password)
            }
        } label: {
            HStack {
                Spacer()
                if isSigningIn {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.85)
                }
                Text(isSigningIn ? "Signing In..." : "Sign In")
                    .font(.montserratSemiBold)
                Spacer()
            }
            .foregroundStyle(.white)
            .frame(height: 55)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(canSubmit ? .accent : .gray.opacity(0.45))
            )
        }
        .disabled(!canSubmit || isSigningIn)
    }

    private var guidanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local setup")
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.85))

            Text(guidanceText)
                .font(.montserratRegular(size: 13))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.58) : .gray.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var guidanceText: String {
        if InternalQASignInAvailability.supportsEnvironmentCredentials {
            return "For one-tap simulator testing, set ASC_INTERNAL_QA_EMAIL and ASC_INTERNAL_QA_PASSWORD in your personal Xcode scheme or automation environment."
        }

        return "Use a dedicated dev or staging QA email/password account. Do not ship QA credentials in production builds."
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(colorScheme == .dark ? .white.opacity(0.05) : .gray.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(colorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
            )
    }

    private func loadLocalCredentialsIfNeeded() {
        guard !didLoadLocalCredentials else { return }
        didLoadLocalCredentials = true

        let credentials = InternalQALocalCredentialsLoader().load()
        localCredentials = credentials

        guard let credentials else { return }
        email = credentials.email
        password = credentials.password
    }

    private func signIn(email: String, password: String) async {
        await authVM.signInWithInternalQA(email: email, password: password)

        if authVM.authenticationState == .authenticated {
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        InternalQASignInView()
            .environment(AuthenticationViewModel())
    }
}
