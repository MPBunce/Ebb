//
//  Preferences.swift
//  Ebb
//

import Foundation

/// `@AppStorage` keys, so views agree on names. Settings the widgets also read live in
/// `AppGroup.Key` instead.
enum PrefKey {
    static let hasOnboarded = "hasOnboarded"
    static let pauseSeconds = "pauseSeconds"
    static let askWhy = "askWhy"
}
