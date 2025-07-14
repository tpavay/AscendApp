//
//  AuthenticationFormView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 7/13/25.
//

import SwiftUI

struct AuthenticationFormView: View {
    let viewModel: AuthenticationViewModel
    @FocusState private var focusedField: FormField?

    enum FormField {
        case email, password, confirmPassword
    }

    var body: some View {
        VStack(spacing: 24) {
            // Mode Toggle
            ModeToggleView(viewModel: viewModel)

            // Form Fields
            VStack(spacing: 16) {
                FormFieldView(
                    title: "Email",
                    text: Binding(
                        get: { viewModel.email },
                        set: { viewModel.email = $0 }
                    ),
                    placeholder: "Enter your email",
                    keyboardType: .emailAddress,
                    textContentType: .emailAddress
                )
                .focused($focusedField, equals: .email)

                FormFieldView(
                    title: "Password",
                    text: Binding(
                        get: { viewModel.password },
                        set: { viewModel.password = $0 }
                    ),
                    placeholder: "Enter your password",
                    textContentType: .password,
                    isSecure: true
                )
                .focused($focusedField, equals: .password)

                if !viewModel.isLogin {
                    FormFieldView(
                        title: "Confirm Password",
                        text: Binding(
                            get: { viewModel.confirmPassword },
                            set: { viewModel.confirmPassword = $0 }
                        ),
                        placeholder: "Confirm your password",
                        textContentType: .newPassword,
                        isSecure: true
                    )
                    .focused($focusedField, equals: .confirmPassword)
                }
            }

            // Error Message
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            // Action Button
            PrimaryButtonView(
                title: viewModel.buttonTitle,
                isEnabled: viewModel.isFormValid,
                isLoading: viewModel.isLoading
            ) {
                viewModel.authenticate()
            }
            .padding(.top, 8)

            // Forgot Password
            if viewModel.isLogin {
                ForgotPasswordView(viewModel: viewModel)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                HStack {
                    Spacer()

                    // Done button
                    Button("Done") {
                        focusedField = nil
                    }
                    .fontWeight(.semibold)
                }
                .foregroundColor(.accent)
            }
        }
    }

    private var previousField: FormField? {
        switch focusedField {
        case .email: return nil
        case .password: return .email
        case .confirmPassword: return .password
        case .none: return nil
        }
    }

    private var nextField: FormField? {
        switch focusedField {
        case .email: return .password
        case .password: return viewModel.isLogin ? nil : .confirmPassword
        case .confirmPassword: return nil
        case .none: return nil
        }
    }

    private var lastField: FormField {
        viewModel.isLogin ? .password : .confirmPassword
    }
}

#Preview {
    @Previewable @State var viewModel = AuthenticationViewModel()

    return NavigationView {
        AuthenticationFormView(viewModel: viewModel)
            .padding()
            .background(Color.black)
    }
}
