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
        .init(name: "Safari", scheme: "x-web-search://", category: .essentials),
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

    /// App Store bundle IDs, used to fetch each app's official icon.
    static let bundleIDs: [String: String] = [
        "Phone": "com.apple.mobilephone",
        "Messages": "com.apple.MobileSMS",
        "Mail": "com.apple.mobilemail",
        "Safari": "com.apple.mobilesafari",
        "Calendar": "com.apple.mobilecal",
        "Photos": "com.apple.mobileslideshow",
        "Maps": "com.apple.Maps",
        "Music": "com.apple.Music",
        "Notes": "com.apple.mobilenotes",
        "Reminders": "com.apple.reminders",
        "Weather": "com.apple.weather",
        "Wallet": "com.apple.Passbook",
        "Files": "com.apple.DocumentsApp",
        "Health": "com.apple.Health",
        "Podcasts": "com.apple.podcasts",
        "Books": "com.apple.iBooks",
        "Shortcuts": "com.apple.shortcuts",
        "WhatsApp": "net.whatsapp.WhatsApp",
        "Signal": "org.whispersystems.signal",
        "Telegram": "ph.telegra.Telegraph",
        "Messenger": "com.facebook.Messenger",
        "Discord": "com.hammerandchisel.discord",
        "Slack": "com.tinyspeck.chatlyio",
        "Microsoft Teams": "com.microsoft.skype.teams",
        "Zoom": "us.zoom.videomeetings",
        "Gmail": "com.google.Gmail",
        "Outlook": "com.microsoft.Office.Outlook",
        "Google Calendar": "com.google.calendar",
        "Google Drive": "com.google.Drive",
        "Notion": "notion.id",
        "Chrome": "com.google.chrome.ios",
        "Google": "com.google.GoogleMobile",
        "Google Docs": "com.google.Docs",
        "Google Sheets": "com.google.Sheets",
        "Brave": "com.brave.ios.browser",
        "Microsoft Word": "com.microsoft.Office.Word",
        "Microsoft Excel": "com.microsoft.Office.Excel",
        "PayPal": "com.yourcompany.PPClient",
        "Cash App": "com.squareup.cash",
        "Firefox": "org.mozilla.ios.Firefox",
        "Duolingo": "com.duolingo.DuolingoMobile",
        "Strava": "com.strava.stravaride",
        "Venmo": "net.kortina.labs.Venmo",
        "Spotify": "com.spotify.client",
        "YouTube Music": "com.google.ios.youtubemusic",
        "Shazam": "com.shazam.Shazam",
        "Twitch": "tv.twitch",
        "YouTube": "com.google.ios.youtube",
        "Netflix": "com.netflix.Netflix",
        "Audible": "com.audible.iphone",
        "Kindle": "com.amazon.Lassen",
        "Google Photos": "com.google.photos",
        "Google Maps": "com.google.Maps",
        "Waze": "com.waze.iphone",
        "Uber": "com.ubercab.UberClient",
        "Lyft": "com.zimride.instant",
        "Uber Eats": "com.ubercab.UberEats",
        "Airbnb": "com.airbnb.app",
        "Instagram": "com.burbn.instagram",
        "TikTok": "com.zhiliaoapp.musically",
        "X": "com.atebits.Tweetie2",
        "Threads": "com.burbn.barcelona",
        "Facebook": "com.facebook.Facebook",
        "Reddit": "com.reddit.Reddit",
        "Snapchat": "com.toyopagroup.picaboo",
        "LinkedIn": "com.linkedin.LinkedIn",
        "Pinterest": "pinterest",
    ]

    /// The App Store bundle ID for an app added from the catalog, if known.
    static func bundleID(forName name: String) -> String? { bundleIDs[name] }

    /// A sensible first-run home screen.
    static let starterNames: Set<String> = ["Phone", "Messages", "Calendar", "Maps", "Music", "Notes"]
}
