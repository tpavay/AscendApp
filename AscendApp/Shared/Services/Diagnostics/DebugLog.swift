//
//  DebugLog.swift
//  AscendApp
//
import Foundation

@inline(__always)
func debugLog(_ message: @autoclosure () -> Any) {
#if DEBUG
    print(message())
#endif
}
