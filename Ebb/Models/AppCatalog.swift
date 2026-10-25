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
    /// The app's launch link, or nil for apps iOS gives no link (Camera, Clock…), which
    /// open through an "Open App" Shortcut instead.
    var scheme: String?
    var category: Category

    var id: String { name }

    var bundleID: String? { AppCatalog.bundleID(forName: name) }

    /// Opens through a Shortcut the user makes once, because the app has no launch link.
    var needsShortcut: Bool { scheme == nil }

    /// Social and endless-feed apps get a mindful pause by default.
    var suggestsPause: Bool { category == .social }

    /// The name Ebb suggests for this app's "Open App" shortcut.
    var shortcutName: String { "Open \(name)" }

    func makeTarget() -> LaunchTarget {
        let method: LaunchTarget.Method = scheme.map { .urlScheme($0) } ?? .shortcut(shortcutName)
        return LaunchTarget(name: name, method: method, isMindful: suggestsPause, bundleID: bundleID)
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
        .init(name: "Find My", scheme: "findmy://", category: .essentials),
        .init(name: "News", scheme: "applenews://", category: .essentials),
        .init(name: "Stocks", scheme: "stocks://", category: .essentials),
        .init(name: "Voice Memos", scheme: "voicememos://", category: .essentials),
        .init(name: "Home", scheme: "com.apple.home://", category: .essentials),
        .init(name: "TestFlight", scheme: "itms-beta://", category: .essentials),
        // Built-in apps iOS gives no launch link; these open with an "Open App" Shortcut.
        .init(name: "Camera", scheme: nil, category: .essentials),
        .init(name: "Clock", scheme: nil, category: .essentials),
        .init(name: "Calculator", scheme: nil, category: .essentials),
        .init(name: "Settings", scheme: nil, category: .essentials),
        .init(name: "FaceTime", scheme: nil, category: .essentials),
        .init(name: "Contacts", scheme: nil, category: .essentials),
        .init(name: "Translate", scheme: nil, category: .essentials),
        .init(name: "Fitness", scheme: nil, category: .essentials),

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
        "App Store": "com.apple.AppStore",
        "Camera": "com.apple.camera",
        "Clock": "com.apple.mobiletimer",
        "Calculator": "com.apple.calculator",
        "Settings": "com.apple.Preferences",
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
        "Find My": "com.apple.findmy",
        "News": "com.apple.news",
        "Stocks": "com.apple.stocks",
        "Voice Memos": "com.apple.VoiceMemos",
        "Home": "com.apple.Home",
        "TestFlight": "com.apple.TestFlight",
        "FaceTime": "com.apple.facetime",
        "Contacts": "com.apple.MobileAddressBook",
        "Translate": "com.apple.Translate",
        "Fitness": "com.apple.Fitness",
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

    /// Launch links for more apps, keyed by App Store bundle ID. These can't be checked
    /// for being installed (iOS caps that at 50), but they open fine once added.
    static let extraSchemes: [String: String] = [
        "com.amazon.Amazon": "com.amazon.mobile.shopping://", // Amazon
        "com.evernote.iPhone.Evernote": "evernote://", // Evernote
        "com.todoist.ios": "todoist://", // Todoist
        "com.culturedcode.ThingsiPhone": "things:///", // Things 3
        "fm.overcast.overcast": "overcast://", // Overcast
        "au.com.shiftyjelly.podcasts": "pktc://", // Pocket Casts
        "net.shinyfrog.bear-iOS": "bear://", // Bear
        "com.agiletortoise.Drafts5": "drafts://", // Drafts
        "com.flexibits.fantastical2.iphone": "fantastical://", // Fantastical
        "md.obsidian": "obsidian://", // Obsidian
        "com.1password.1password": "onepassword://", // 1Password
        "com.fogcreek.trello": "trello://", // Trello
        "com.tumblr.tumblr": "tumblr://", // Tumblr
        "com.vimeo": "vimeo://", // Vimeo
        "com.soundcloud.TouchApp": "soundcloud://", // SoundCloud
        "doordash.DoorDashConsumer": "doordash://", // DoorDash
        "com.robinhood.release.Robinhood": "robinhood://", // Robinhood
        "com.calm.calmapp": "calm://", // Calm
        "com.getsomeheadspace.headspace": "headspace://", // Headspace
        "azdev.citymapper": "citymapper://", // Citymapper
        "com.samvermette.Transit": "transit://", // Transit
        "com.google.Translate": "googletranslate://", // Google Translate
        "com.microsoft.Office.Powerpoint": "ms-powerpoint://", // Microsoft PowerPoint
        "com.microsoft.onenote": "onenote://", // OneNote
        "com.viber": "viber://", // Viber
        "jp.naver.line": "line://", // LINE
        "com.tencent.xin": "weixin://", // WeChat
        "com.medium.reader": "medium://", // Medium
        "com.espn.ScoreCenter": "sportscenter://", // ESPN
        "com.hulu.plus": "hulu://", // Hulu
        "com.disney.disneyplus": "disneyplus://", // Disney+
        "com.amazon.aiv.AIVApp": "aiv://", // Prime Video
        "com.plexapp.plex": "plex://", // Plex
        "org.videolan.vlc-ios": "vlc://", // VLC
        "com.pandora": "pandora://", // Pandora
        "com.deezer.Deezer": "deezer://", // Deezer
        "com.aspiro.TIDAL": "tidal://", // TIDAL
        "com.asana.Asana": "asana://", // Asana
        "com.nytimes.NYTimes": "nytimes://", // The New York Times
        "com.yelp.yelpiphone": "yelp://", // Yelp
        "com.booking.BookingApp": "booking://", // Booking.com
        "com.cardify.tinder": "tinder://", // Tinder
        "com.google.Keep": "comgooglekeep://", // Google Keep
        "com.google.ios.youtubekids": "youtubekids://", // YouTube Kids
        "com.google.GoogleMeet": "gmeet://", // Google Meet
        "com.microsoft.skype.skype": "skype://", // Skype
        "com.grailr.CARROTweather": "carrotweather://", // CARROT Weather
        "com.etsy.etsyforios": "etsy://", // Etsy
        "com.ebay.iphone": "ebay://", // eBay
        "com.myfitnesspal.mfp": "mfp://", // MyFitnessPal
        "com.goodreads.Goodreads": "goodreads://", // Goodreads
        "com.hbo.hbonow": "hbomax://", // Max
        "com.crunchyroll.iphone": "crunchyroll://", // Crunchyroll
        "com.mojang.minecraftpe": "minecraft://", // Minecraft
    ]

    /// Ready-made groups of apps, for filling widgets in one tap. Third-party apps only
    /// join a set when they're on this iPhone (or iPhone won't say, in which case they're left out).
    struct StarterSet: Identifiable {
        let name: String
        let icon: String
        let apps: [String]
        var id: String { name }
    }

    static let starterSets: [StarterSet] = [
        StarterSet(name: "Essentials", icon: "star", apps: ["Phone", "Messages", "Camera", "Maps", "Music", "Calendar"]),
        StarterSet(name: "Minimal", icon: "minus.circle", apps: ["Phone", "Messages", "Maps", "Notes"]),
        StarterSet(name: "Work", icon: "briefcase", apps: ["Mail", "Calendar", "Notes", "Slack", "Microsoft Teams", "Zoom", "Outlook", "Gmail", "Google Calendar", "Notion"]),
        StarterSet(name: "Listen & read", icon: "headphones", apps: ["Music", "Podcasts", "Books", "Spotify", "Audible", "Kindle", "Overcast"]),
        StarterSet(name: "Get around", icon: "map", apps: ["Maps", "Wallet", "Weather", "Google Maps", "Uber", "Lyft", "Waze"]),
    ]

    /// The apps in a set that can be added here: Apple apps, plus third-party ones found
    /// on this iPhone. At most one widget's worth.
    static func apps(in set: StarterSet, installed: [CatalogApp]) -> [CatalogApp] {
        let installedNames = Set(installed.map(\.name))
        return set.apps.compactMap { name in apps.first { $0.name == name } }
            .filter { $0.category == .essentials || installedNames.contains($0.name) }
            .prefix(AppWidgetList.capacity)
            .map { $0 }
    }

    /// The catalog app a name refers to, allowing for Home Screen labels cut short with "…".
    static func app(named label: String) -> CatalogApp? {
        let cleaned = label.replacingOccurrences(of: "…", with: "").replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard cleaned.count >= 2 else { return nil }
        if let exact = apps.first(where: { $0.name.caseInsensitiveCompare(cleaned) == .orderedSame }) { return exact }
        if cleaned.count < label.count, cleaned.count >= 4 {
            return apps.first { $0.name.lowercased().hasPrefix(cleaned.lowercased()) }
        }
        return nil
    }

    /// The launch link for an App Store app, if Ebb knows it.
    static func scheme(forBundleID bundleID: String) -> String? {
        if let name = bundleIDs.first(where: { $0.value == bundleID })?.key,
           let app = apps.first(where: { $0.name == name }) {
            return app.scheme
        }
        return extraSchemes[bundleID]
    }

    /// A sensible first-run home screen.
    static let starterNames: Set<String> = ["Phone", "Messages", "Calendar", "Maps", "Music", "Notes"]
}
