//
//  AppCatalog.swift
//  Ebb
//
//  Well-known URL schemes for common apps. Schemes are maintained by each app's developer
//  and occasionally change; anything missing or broken can be added with a Shortcut instead.
//

import Foundation

struct CatalogApp: Hashable, Identifiable {
    enum Category: String, CaseIterable {
        case essentials = "Essentials"
        case communication = "Communication"
        case productivity = "Productivity"
        case media = "Media"
        case travel = "Travel"
        case social = "Social"
    }

    var name: String
    var scheme: String
    var category: Category

    var id: String { name }

    /// Social and endless-feed apps get a mindful pause by default.
    var suggestsPause: Bool { category == .social }

    func makeTarget() -> LaunchTarget {
        LaunchTarget(name: name, method: .urlScheme(scheme), isMindful: suggestsPause)
    }
}

enum AppCatalog {
    static let apps: [CatalogApp] = [
        // Essentials (built-in)
        .init(name: "Phone", scheme: "mobilephone://", category: .essentials),
        .init(name: "Messages", scheme: "sms://", category: .essentials),
        .init(name: "Mail", scheme: "message://", category: .essentials),
        .init(name: "Calendar", scheme: "calshow://", category: .essentials),
        .init(name: "Photos", scheme: "photos-redirect://", category: .essentials),
        .init(name: "Maps", scheme: "maps://", category: .essentials),
        .init(name: "Music", scheme: "music://", category: .essentials),
        .init(name: "Notes", scheme: "mobilenotes://", category: .essentials),
        .init(name: "Reminders", scheme: "x-apple-reminderkit://", category: .essentials),
        .init(name: "Weather", scheme: "weather://", category: .essentials),
        .init(name: "Wallet", scheme: "shoebox://", category: .essentials),
        .init(name: "Files", scheme: "shareddocuments://", category: .essentials),
        .init(name: "Health", scheme: "x-apple-health://", category: .essentials),
        .init(name: "Podcasts", scheme: "podcasts://", category: .essentials),
        .init(name: "Books", scheme: "ibooks://", category: .essentials),
        .init(name: "App Store", scheme: "itms-apps://", category: .essentials),
        .init(name: "Shortcuts", scheme: "shortcuts://", category: .essentials),

        // Communication
        .init(name: "WhatsApp", scheme: "whatsapp://", category: .communication),
        .init(name: "Signal", scheme: "sgnl://", category: .communication),
        .init(name: "Telegram", scheme: "tg://", category: .communication),
        .init(name: "Messenger", scheme: "fb-messenger://", category: .communication),
        .init(name: "Discord", scheme: "discord://", category: .communication),
        .init(name: "Slack", scheme: "slack://", category: .communication),
        .init(name: "Microsoft Teams", scheme: "msteams://", category: .communication),
        .init(name: "Zoom", scheme: "zoomus://", category: .communication),
        .init(name: "Gmail", scheme: "googlegmail://", category: .communication),
        .init(name: "Outlook", scheme: "ms-outlook://", category: .communication),

        // Productivity
        .init(name: "Google Calendar", scheme: "googlecalendar://", category: .productivity),
        .init(name: "Google Drive", scheme: "googledrive://", category: .productivity),
        .init(name: "Notion", scheme: "notion://", category: .productivity),
        .init(name: "Chrome", scheme: "googlechrome://", category: .productivity),
        .init(name: "Google", scheme: "google://", category: .productivity),
        .init(name: "Google Docs", scheme: "googledocs://", category: .productivity),
        .init(name: "Google Sheets", scheme: "googlesheets://", category: .productivity),
        .init(name: "Brave", scheme: "brave://", category: .productivity),
        .init(name: "Microsoft Word", scheme: "ms-word://", category: .productivity),
        .init(name: "Microsoft Excel", scheme: "ms-excel://", category: .productivity),
        .init(name: "PayPal", scheme: "paypal://", category: .productivity),
        .init(name: "Cash App", scheme: "squarecash://", category: .productivity),
        .init(name: "Firefox", scheme: "firefox://", category: .productivity),
        .init(name: "Duolingo", scheme: "duolingo://", category: .productivity),
        .init(name: "Strava", scheme: "strava://", category: .productivity),
        .init(name: "Venmo", scheme: "venmo://", category: .productivity),

        // Media
        .init(name: "Spotify", scheme: "spotify://", category: .media),
        .init(name: "YouTube Music", scheme: "youtubemusic://", category: .media),
        .init(name: "Shazam", scheme: "shazam://", category: .media),
        .init(name: "Twitch", scheme: "twitch://", category: .media),
        .init(name: "YouTube", scheme: "youtube://", category: .media),
        .init(name: "Netflix", scheme: "nflx://", category: .media),
        .init(name: "Audible", scheme: "audible://", category: .media),
        .init(name: "Kindle", scheme: "kindle://", category: .media),
        .init(name: "Google Photos", scheme: "googlephotos://", category: .media),

        // Travel
        .init(name: "Google Maps", scheme: "comgooglemaps://", category: .travel),
        .init(name: "Waze", scheme: "waze://", category: .travel),
        .init(name: "Uber", scheme: "uber://", category: .travel),
        .init(name: "Lyft", scheme: "lyft://", category: .travel),
        .init(name: "Uber Eats", scheme: "ubereats://", category: .travel),
        .init(name: "Airbnb", scheme: "airbnb://", category: .travel),

        // Social
        .init(name: "Instagram", scheme: "instagram://", category: .social),
        .init(name: "TikTok", scheme: "snssdk1233://", category: .social),
        .init(name: "X", scheme: "twitter://", category: .social),
        .init(name: "Threads", scheme: "barcelona://", category: .social),
        .init(name: "Facebook", scheme: "fb://", category: .social),
        .init(name: "Reddit", scheme: "reddit://", category: .social),
        .init(name: "Snapchat", scheme: "snapchat://", category: .social),
        .init(name: "LinkedIn", scheme: "linkedin://", category: .social),
        .init(name: "Pinterest", scheme: "pinterest://", category: .social),
    ]

    /// A sensible first-run home screen.
    static let starterNames: Set<String> = ["Phone", "Messages", "Calendar", "Maps", "Music", "Notes"]
}
