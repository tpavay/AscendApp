//
//  FormFieldView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 7/13/25.
//

import SwiftUI

struct FormFieldView: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var isSecure: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.gray)

            if isSecure {
                SecureField(placeholder, text: $text)
                    .textFieldStyle(CustomTextFieldStyle())
                    .textContentType(textContentType)
            } else {
                TextField(placeholder, text: $text)
                    .textFieldStyle(CustomTextFieldStyle())
                    .keyboardType(keyboardType)
                    .textContentType(textContentType)
                    .autocapitalization(.none)
            }
        }
    }
}

#Preview {
    @Previewable @State var sampleText = ""

    return VStack {
        FormFieldView(
            title: "Email",
            text: $sampleText,
            placeholder: "Enter your email",
            keyboardType: .emailAddress
        )

        FormFieldView(
            title: "Password",
            text: $sampleText,
            placeholder: "Enter your password",
            isSecure: true
        )
    }
    .padding()
    .background(Color.black)
}
