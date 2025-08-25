////
////  CustomTextField.swift
////  AscendApp
////
////  Created by Tyler Pavay on 8/19/25.
////
//
//import SwiftUI
//
//struct CustomTextField: View {
//    @Binding var text: String
//    @State var configuration: CustomTextFieldConfiguration
//    // Learn how to add focus.
//    // Learn how to add validation.
//
//    init(text: Binding<String>, configuration: CustomTextFieldConfiguration) {
//        self._text = text
//        self.configuration = configuration
//    }
//
//    var body: some View {
//        if let labelText = configuration.labelText {
//            Text(labelText)
//        }
//        TextField(
//            configuration.placeHolderText ?? "",
//            text: $text
//        )
//        .padding()
//        .foregroundStyle(.black)
//        .frame(height: 55)
//        .background(.white)
//        .clipShape(RoundedRectangle(cornerRadius: 14))
//        .shadow(color: .black.opacity(0.1), radius: 8)
//        .submitLabel(configuration.submitLabel)
//        .focused(configuration.focusBinding, equals: configuration.focusValue)
//    }
//}
//
//#Preview("Default") {
//    @Previewable @State var text: String = ""
//
//    let configuration = CustomTextFieldConfiguration
//        .builder()
//        .setPlaceHolderText("Enter your name")
//        .build()
//
//    VStack {
//        CustomTextField(text: $text, configuration: configuration)
//    }
//    .padding()
//}
