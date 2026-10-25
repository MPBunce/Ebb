//
//  ScreenshotImport.swift
//  Ebb
//
//  iPhone doesn't let apps list what's installed, but the App Library's list view (and
//  Home Screens with app names) shows it. Ebb reads the names in screenshots of it with
//  on-device text recognition, then matches each to a known app or the App Store.
//  Nothing leaves the phone except App Store searches for names Ebb doesn't know.
//

import UIKit
import Vision

enum ScreenshotImport {
    struct Result {
        var apps: [PickerApp]
        /// Names that looked like apps but couldn't be matched.
        var unmatched: [String]
    }

    /// Words on Home Screens and the App Library that aren't app names.
    private static let ignored: Set<String> = [
        "app library", "search", "search app library", "edit", "done", "cancel", "today", "suggestions",
        "recently added", "utilities", "productivity", "productivity & finance", "social", "entertainment",
        "information & reading", "creativity", "health & fitness", "shopping & food", "travel", "games",
        "other", "education", "lifestyle", "finance", "sports", "news & magazines", "music", "photo & video",
        "remove", "edit home screen", "share app", "add widget", "siri", "no events today", "no events",
        "all day", "tomorrow", "now", "up next",
    ]

    /// Day and month names, which widgets (Calendar, Clock) put on Home Screens.
    private static let calendarWords: Set<String> = {
        let calendar = Calendar.current
        let english = Calendar(identifier: .gregorian)
        let lists = [calendar.weekdaySymbols, calendar.shortWeekdaySymbols, calendar.monthSymbols, calendar.shortMonthSymbols,
                     english.weekdaySymbols, english.shortWeekdaySymbols, english.monthSymbols, english.shortMonthSymbols]
        return Set(lists.flatMap { $0 }.map { $0.lowercased() })
    }()

    /// App names found in screenshots, in the order they appear, without repeats.
    static func names(in images: [UIImage]) async -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for image in images {
            for line in await lines(in: image) where looksLikeAppName(line) {
                let key = line.lowercased()
                if seen.insert(key).inserted { names.append(line) }
            }
        }
        return names
    }

    private static func lines(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                // Top to bottom, then left to right, like reading the screen.
                let sorted = observations.sorted {
                    abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.01
                        ? $0.boundingBox.midY > $1.boundingBox.midY
                        : $0.boundingBox.minX < $1.boundingBox.minX
                }
                continuation.resume(returning: sorted.compactMap { $0.topCandidates(1).first?.string })
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([request]) } catch { continuation.resume(returning: []) }
            }
        }
    }

    static func looksLikeAppName(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        guard (2...32).contains(trimmed.count), !ignored.contains(lower), !calendarWords.contains(lower) else { return false }
        // The search field ("Q Search", "Search App Library").
        if lower.hasSuffix("search") || lower.hasPrefix("search ") { return false }
        // Clock, battery, and section letters.
        if trimmed.range(of: #"^[\d:%.,\s]+$"#, options: .regularExpression) != nil { return false }
        if trimmed.range(of: #"^\d{1,2}:\d{2}"#, options: .regularExpression) != nil { return false }
        guard trimmed.rangeOfCharacter(from: .letters) != nil else { return false }
        return trimmed.split(separator: " ").count <= 5
    }

    /// Matches names to apps: Ebb's list first, then the App Store. App Store searches are
    /// rate-limited, so at most `storeLookups` names are looked up there.
    static func match(_ names: [String], storeLookups: Int = 20,
                      progress: @escaping @MainActor (Int, Int) -> Void = { _, _ in }) async -> Result {
        var apps: [PickerApp] = []
        var unmatched: [String] = []
        var seen = Set<String>()
        var lookups = 0
        for (index, name) in names.enumerated() {
            await progress(index + 1, names.count)
            if let known = AppCatalog.app(named: name) {
                let app = PickerApp(known)
                if seen.insert(app.id).inserted { apps.append(app) }
                continue
            }
            guard lookups < storeLookups else { unmatched.append(name); continue }
            lookups += 1
            let cleaned = name.replacingOccurrences(of: "…", with: "").trimmingCharacters(in: .whitespaces)
            let results = await AppStoreSearchView.search(cleaned)
            let match = results.first { $0.shortName(matching: cleaned).caseInsensitiveCompare(cleaned) == .orderedSame }
                ?? results.first { $0.shortName(matching: cleaned).lowercased().hasPrefix(cleaned.lowercased()) && cleaned.count >= 4 }
            if let match {
                var app = PickerApp(match, query: cleaned)
                app.name = cleaned.count < name.count ? app.name : name
                if seen.insert(app.id).inserted { apps.append(app) }
            } else {
                unmatched.append(name)
            }
        }
        return Result(apps: apps, unmatched: unmatched)
    }
}
