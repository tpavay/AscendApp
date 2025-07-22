//
//  AuthenticationFormView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 7/13/25.
//

import SwiftUI

struct AuthenticationFormView: View {
    @State private var viewModel: AuthenticationViewModel = AuthenticationViewModel()

    @FocusState private var focusedField: FormField?

    enum FormField {
        case email, firstName, lastName, password, confirmPassword
    }

    var body: some View {
        VStack(spacing: 24) {

            // Mode Toggle
            ModeToggleView(viewModel: viewModel)

            // Form Fields
            VStack(spacing: 16) {

                if (!viewModel.isLogin) {
                    FormFieldView(
                        title: "First Name",
                        text: Binding(
                            get: { viewModel.firstName },
                            set: { viewModel.firstName = $0 }
                        ),
                        placeholder: "Enter your first name",
                        textContentType: .givenName
                    )
                    .focused($focusedField, equals: .firstName)

                    FormFieldView(
                        title: "Last Name",
                        text: Binding(
                            get: { viewModel.lastName },
                            set: { viewModel.lastName = $0 }
                        ),
                        placeholder: "Enter your last name",
                        textContentType: .familyName
                    )
                    .focused($focusedField, equals: .lastName)
                }

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
                .autocorrectionDisabled()

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
                        textContentType: .password,
                        isSecure: true
                    )
                    .focused($focusedField, equals: .confirmPassword)
                }
            }

            // Error Message
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(errorMessage.contains("sent") ? .green : .red)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
            }

            // Action Button
            PrimaryButtonView(
                title: viewModel.buttonTitle,
                isEnabled: viewModel.isFormValid,
                isLoading: viewModel.isLoading
            ) {
                Task {
                    await viewModel.authenticate()
                }
            }
            .padding(.top, 8)

            // Forgot Password
            if viewModel.isLogin {
                Button("Forgot Password?") {
                    Task {
                        await viewModel.forgotPassword()
                    }
                }
                .font(.subheadline)
                .foregroundColor(.accent)
                .disabled(viewModel.isLoading)
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
}
