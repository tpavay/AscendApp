////
////  CustomTextFieldConfiguration.swift
////  AscendApp
////
////  Created by Tyler Pavay on 8/21/25.
////
//
//import SwiftUI
//
//struct CustomTextFieldConfiguration {
//    let labelText: String?
//    let placeHolderText: String?
//    let isSecure: Bool
//    let submitLabel: SubmitLabel
//    var focusBinding: FocusState<NameInputFocusField?>.Binding?
//    var focusValue: NameInputFocusField?
//
//    class Builder {
//        var labelText: String? = nil
//        var placeHolderText: String? = nil
//        var isSecure: Bool = false
//        var submitLabel: SubmitLabel = .next
//        var focusBinding: FocusState<NameInputFocusField?>.Binding
//        var focusValue: NameInputFocusField?
//
//        func setLabelText(_ t: String) -> Builder { labelText = t; return self }
//
//        func setPlaceHolderText(_ t: String) -> Builder { placeHolderText = t; return self }
//
//        func setIsSecure(_ b: Bool) -> Builder { isSecure = b; return self }
//
//        func setSubmitLabel(_ l: SubmitLabel) -> Builder { submitLabel = l; return self}
//
//        func setFocusState(_ binding: FocusState<NameInputFocusField?>.Binding?, equals value: NameInputFocusField) -> Builder {
//            focusBinding = binding
//            focusValue = value
//            return self
//        }
//
//        func build() -> CustomTextFieldConfiguration {
//            return CustomTextFieldConfiguration(
//                labelText: labelText,
//                placeHolderText: placeHolderText,
//                isSecure: isSecure,
//                submitLabel: submitLabel,
//                focusBinding: focusBinding,
//                focusValue: focusValue
//            )
//        }
//    }
//
//    static func builder() -> Builder { Builder() }
//}
