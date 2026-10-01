//
//  LaunchTarget.swift
//  Ebb
//

import Foundation

/// An app (or anything else) Ebb can open. iOS doesn't let apps list or launch other
/// installed apps directly, so each entry says *how* to open it.
struct LaunchTarget: Codable, Hashable, Identifiable {
    enum Method: Codable, Hashable {
        /// A URL scheme such as `spotify://`. Fast, works for most popular apps.
        case urlScheme(String)
        /// A Shortcut the user created (e.g. an "Open App" action). Works for every app.
        case shortcut(String)
        /// A website, opened in the default browser.
        case website(String)
    }

    var id = UUID()
    var name: String
    var method: Method
    /// Apps that need a mindful pause before opening.
    var isMindful = false
    /// Hidden apps are only reachable through search.
    var isHidden = false

    var url: URL? {
        switch method {
        case .urlScheme(let scheme):
            let normalized = scheme.contains(":") ? scheme : scheme + "://"
            return URL(string: normalized)
        case .shortcut(let name):
            var components = URLComponents(string: "shortcuts://run-shortcut")
            components?.queryItems = [URLQueryItem(name: "name", value: name)]
            return components?.url
        case .website(let address):
            let normalized = address.contains("://") ? address : "https://" + address
            return URL(string: normalized)
        }
    }

    var methodDescription: String {
        switch method {
        case .urlScheme(let scheme): scheme
        case .shortcut(let name): "Shortcut: \(name)"
        case .website(let address): address
        }
    }
}

/// A record of one attempt to open an app, kept on-device for Insights.
struct LaunchEvent: Codable, Hashable {
    enum Outcome: String, Codable {
        case opened
        /// The user backed out during a mindful pause.
        case resisted
    }

    var targetID: UUID
    var name: String
    var date: Date
    var outcome: Outcome
    var intention: String?
}
