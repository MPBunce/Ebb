//
//  AppearanceView.swift
//  Ebb
//
//  Background/text colors shared by the app and every widget, plus wallpapers in the
//  same color so the widgets blend into the Home Screen.
//

import Photos
import PhotosUI
import SwiftUI
import WidgetKit

struct AppearanceView: View {
    @AppStorage(AppGroup.Key.backgroundHex, store: AppGroup.defaults)
    private var backgroundHex = Appearance.defaultBackground
    @AppStorage(AppGroup.Key.textHex, store: AppGroup.defaults)
    private var textHex = Appearance.defaultText


    private var background: HexColor { HexColor(hex: backgroundHex) ?? HexColor(red: 0, green: 0, blue: 0) }
    private var text: HexColor { HexColor(hex: textHex) ?? HexColor(red: 1, green: 1, blue: 1) }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    ForEach(Appearance.wallpaperPresets) { preset in
                        WallpaperCard(
                            title: preset.name,
                            background: HexColor(hex: preset.background)!,
                            text: HexColor(hex: preset.text)!,
                            isSelected: backgroundHex == preset.background
                        ) {
                            apply(preset)
                        }
                    }
                    if !Appearance.wallpaperPresets.contains(where: { $0.background == backgroundHex }) {
                        WallpaperCard(title: "Your color", background: background, text: text, isSelected: true) {}
                    }
                }
                .padding(.vertical, 8)

                WallpaperSaveFlow(background: background)
            } header: {
                Text("Wallpaper")
            } footer: {
                Text("Because the wallpaper and widgets share one color, the widgets blend in and only the app names show. iPhone doesn't let apps change your wallpaper, so you set it from Photos.")
            }

            WallpaperMatchSection(background: background)

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Appearance.presets) { preset in
                            Button {
                                apply(preset)
                            } label: {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(HexColor(hex: preset.background)!.color)
                                        .overlay {
                                            Text("Aa")
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(HexColor(hex: preset.text)!.color)
                                        }
                                        .overlay {
                                            Circle().strokeBorder(
                                                backgroundHex == preset.background ? Color.accentColor : Color.secondary.opacity(0.3),
                                                lineWidth: backgroundHex == preset.background ? 2 : 1
                                            )
                                        }
                                        .frame(width: 48, height: 48)
                                    Text(preset.name)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }

                ColorPicker("Background", selection: colorBinding($backgroundHex), supportsOpacity: false)
                ColorPicker("Text", selection: colorBinding($textHex), supportsOpacity: false)
                Button("Pick a readable text color") {
                    textHex = background.isDark ? Appearance.defaultText : "#1F1D1A"
                }
            } header: {
                Text("Colors")
            } footer: {
                Text("Used by Ebb and all of its widgets. iOS doesn't allow see-through widgets, so matching colors is how they disappear into your wallpaper.")
            }
        }
        .navigationTitle("Colors & wallpaper")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: backgroundHex) { WidgetCenter.shared.reloadAllTimelines() }
        .onChange(of: textHex) { WidgetCenter.shared.reloadAllTimelines() }
    }

    private func apply(_ preset: ColorPreset) {
        backgroundHex = preset.background
        textHex = preset.text
    }

    private func colorBinding(_ hex: Binding<String>) -> Binding<Color> {
        Binding {
            HexColor(hex: hex.wrappedValue)?.color ?? .black
        } set: { color in
            hex.wrappedValue = HexColor(color).hex
        }
    }
}

/// A phone-shaped preview of a wallpaper with widget text on it.
struct WallpaperCard: View {
    let title: String
    let background: HexColor
    let text: HexColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(background.color)
                    .aspectRatio(9 / 19.5, contentMode: .fit)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("9:41").font(.system(size: 20, weight: .thin))
                            Spacer().frame(height: 18)
                            ForEach(["Phone", "Messages", "Maps", "Music"], id: \.self) {
                                Text($0).font(.system(size: 10, weight: .light))
                            }
                        }
                        .foregroundStyle(text.color)
                        .padding(10)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                                          lineWidth: isSelected ? 2 : 1)
                    }
                    .frame(height: 170)
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) wallpaper")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

enum Wallpaper {
    /// A solid wallpaper at the device's full resolution, in plain sRGB so it matches
    /// the widgets' color exactly.
    static func render(background: HexColor) -> UIImage {
        let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen
        let size = screen?.nativeBounds.size ?? CGSize(width: 1206, height: 2622)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            background.uiColor.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    enum SaveResult: Equatable {
        case saved
        case denied
        case failed(String)
    }

    /// Saves a wallpaper in `background`'s color to the photo library. It's saved as a
    /// lossless PNG; compressed formats can shift a flat color just enough to show
    /// the widget edges.
    static func saveToPhotos(background: HexColor) async -> SaveResult {
        // Use the color tuned for this iPhone, if the user has matched it.
        guard let png = render(background: WallpaperTuning.wallpaperColor(for: background)).pngData() else {
            return .failed("The wallpaper image couldn't be created.")
        }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .denied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = "Ebb Wallpaper \(background.hex.dropFirst()).png"
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: png, options: options)
            }
            return .saved
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

/// Saves the matching wallpaper, then walks the user through setting it, since iOS
/// doesn't let apps change the wallpaper themselves.
struct WallpaperSaveFlow: View {
    @Environment(\.openURL) private var openURL
    let background: HexColor

    @State private var result: Wallpaper.SaveResult?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                isSaving = true
                Task {
                    let outcome = await Wallpaper.saveToPhotos(background: background)
                    withAnimation { result = outcome }
                    isSaving = false
                }
            } label: {
                Label(isSaving ? "Saving…" : (result == .saved ? "Save again" : "Save wallpaper to Photos"),
                      systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .disabled(isSaving)

            switch result {
            case .saved:
                savedGuide
            case .denied:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ebb needs permission to add the wallpaper to Photos.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .font(.footnote.weight(.semibold))
                }
            case .failed(let reason):
                Text("Couldn't save the wallpaper. \(reason)")
                    .font(.footnote)
                    .foregroundStyle(.red)
            case nil:
                EmptyView()
            }
        }
        .buttonStyle(.borderless)
    }

    private var savedGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)

            StepRow(number: 1, title: "Open the wallpaper",
                    detail: "In Photos it's the newest picture, at the bottom of your library.")
            StepRow(number: 2, title: "Tap Share › Use as Wallpaper",
                    detail: "Share is the square with an arrow, bottom left. Don't zoom or swipe to another look; keep it on Natural.")
            StepRow(number: 3, title: "Tap Add › Set as Wallpaper Pair",
                    detail: "Home and Lock Screens then match your widgets.")

            Button {
                if let url = URL(string: "photos-redirect://") { openURL(url) }
            } label: {
                Label("Open Photos", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary)
            .foregroundStyle(Color(.systemBackground))

            Divider().padding(.vertical, 4)
            SeamlessTips()
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// The iPhone settings that can make widgets stand out from a matching wallpaper.
struct SeamlessTips: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("If you can still see widget edges", systemImage: "eye")
                .font(.subheadline.weight(.semibold))
            tip("Home Screen isn't blurred",
                "Settings › Wallpaper › Customize under the Home Screen › pick the photo itself, not Blur, Color, or Gradient.")
            tip("Widgets aren't tinted",
                "Long-press the Home Screen › Edit › Customize › choose Default or Dark. Clear and Tinted recolor widgets so they won't match.")
            tip("Dark Mode doesn't dim the wallpaper",
                "In Dark Mode iPhone can darken the wallpaper but not the widgets. Turn off Dark Appearance Dims Wallpaper in Settings › Wallpaper.")
            tip("Colors match exactly",
                "If you changed colors in Ebb, save the wallpaper again and reapply it. Widgets and wallpaper must be the same color.")
        }
    }

    private func tip(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Measures a Home Screen screenshot and tunes the wallpaper so widget edges disappear.
struct WallpaperMatchSection: View {
    let background: HexColor

    @State private var pickedItem: PhotosPickerItem?
    @State private var status: Status?
    @State private var tuned: HexColor
    @State private var saveResult: Wallpaper.SaveResult?

    enum Status: Equatable {
        case checking
        case perfect
        case corrected(Double)
        case failed(String)
    }

    init(background: HexColor) {
        self.background = background
        _tuned = State(initialValue: WallpaperTuning.wallpaperColor(for: background))
    }

    var body: some View {
        Section {
            PhotosPicker(selection: $pickedItem, matching: .screenshots) {
                Label("Match from a screenshot", systemImage: "wand.and.stars")
            }
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                Task { await analyze(item) }
            }

            if let status {
                switch status {
                case .checking:
                    ProgressView("Measuring…")
                case .perfect:
                    Label("Your wallpaper already matches your widgets.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .corrected(let difference):
                    Text("Your wallpaper was \(Int(difference.rounded())) step\(Int(difference.rounded()) == 1 ? "" : "s") off. Ebb made a corrected one: save it and set it as your wallpaper again.")
                        .font(.footnote)
                case .failed(let message):
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Fine-tune by eye")
                Spacer()
                Button("Darker", systemImage: "minus") { nudge(-1) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                Text(offsetLabel)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 36)
                Button("Lighter", systemImage: "plus") { nudge(1) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
            }

            if tuned != background {
                Button("Save tuned wallpaper") {
                    Task { saveResult = await Wallpaper.saveToPhotos(background: background) }
                }
                Button("Reset to widget color", role: .destructive) {
                    tuned = background
                    WallpaperTuning.setWallpaperColor(nil, for: background)
                    status = nil
                }
            }
            if saveResult == .saved {
                Label("Saved. Set it as your wallpaper from Photos.", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
        } header: {
            Text("Make it seamless")
        } footer: {
            Text("iPhone draws wallpapers slightly differently from widgets, especially light colors. Take a screenshot of your Home Screen with an Ebb widget showing (press the side and volume-up buttons), then choose it here. Ebb measures the difference and adjusts the wallpaper to cancel it out.")
        }
    }

    private var offsetLabel: String {
        let steps = Int(((tuned.red + tuned.green + tuned.blue - background.red - background.green - background.blue) / 3 * 255).rounded())
        return steps == 0 ? "0" : (steps > 0 ? "+\(steps)" : "\(steps)")
    }

    private func nudge(_ steps: Int) {
        tuned = WallpaperMatcher.nudge(tuned, steps: steps)
        WallpaperTuning.setWallpaperColor(tuned, for: background)
        saveResult = nil
    }

    private func analyze(_ item: PhotosPickerItem) async {
        status = .checking
        defer { pickedItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)?.cgImage
        else {
            status = .failed("Couldn't open that screenshot.")
            return
        }
        switch WallpaperMatcher.measure(image, target: background) {
        case .success(let measurement) where measurement.difference < 1:
            status = .perfect
        case .success(let measurement):
            // The wallpaper in the screenshot was saved in the current tuned color.
            tuned = WallpaperMatcher.corrected(saved: tuned, measurement: measurement)
            WallpaperTuning.setWallpaperColor(tuned, for: background)
            saveResult = nil
            status = .corrected(measurement.difference)
        case .failure(.noWidget):
            status = .failed("Couldn't find an Ebb widget in that screenshot. Make sure one is showing and your widget color in Ebb hasn't changed since.")
        case .failure(.noWallpaper):
            status = .failed("Couldn't find Ebb's wallpaper around the widget. Set the wallpaper from Ebb first, then take the screenshot.")
        }
    }
}
