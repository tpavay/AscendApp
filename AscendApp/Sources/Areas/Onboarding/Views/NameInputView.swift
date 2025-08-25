//
//  NameInputView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/19/25.
//

import SwiftUI

enum NameInputFocusField: Hashable {
    case firstName, lastName
}

struct NameInputView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.colorScheme) private var colorScheme

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @FocusState private var focusedField: NameInputFocusField?

    private var isFormValid: Bool {
        return
            !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

//    let firstNameTextFieldConfig = CustomTextFieldConfiguration
//        .builder()
//        .setPlaceHolderText("First Name")
//        .setSubmitLabel(.next)
//        .build()
//
//    let lastNameTextFieldConfig = CustomTextFieldConfiguration
//        .builder()
//        .setPlaceHolderText("Last Name")
//        .setSubmitLabel(.done)
//        .build()

    var body: some View {
        VStack(spacing: 12) {
            Text("What's your name?")
                .font(.montserratBold(size: 32))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                
                Text("This is the name that will be displayed in your profile and can be changed later in settings.")
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.8) : .gray)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 20)
                
                VStack(spacing: 16) {
                    TextField("First Name", text: $firstName)
                        .focused($focusedField, equals: .firstName)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .lastName
                        }
                    
                    TextField("Last Name", text: $lastName)
                        .focused($focusedField, equals: .lastName)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                        .onSubmit {
                            if isFormValid {
                                Task {
                                    await authVM.setDisplayName(firstName: firstName, lastName: lastName)
                                }
                            }
                        }
                }

                Button(action: {
                    Task {
                        await authVM.setDisplayName(firstName: firstName, lastName: lastName)
                    }
                }) {
                    Text("Continue")
                        .font(.montserratSemiBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(isFormValid ? .accent : .gray)
                        )
                }
                .disabled(!isFormValid)
        }
        .padding()
        .themedBackground()
        .onAppear {
            focusedField = .firstName
        }
    }
}

#Preview {
    NavigationStack {
        NameInputView()
            .environment(AuthenticationViewModel())
    }
}
