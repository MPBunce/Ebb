//
//  AppearanceView.swift
//  Ebb
//
//  Background/text colors shared by the app and every widget, plus wallpapers in the
//  same color so the widgets blend into the Home Screen.
//

import Photos
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
    /// A solid wallpaper at the device's full resolution.
    static func render(background: HexColor) -> UIImage {
        let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen
        let size = screen?.nativeBounds.size ?? CGSize(width: 1206, height: 2622)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
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

    /// Saves a wallpaper in `background`'s color to the photo library.
    static func saveToPhotos(background: HexColor) async -> SaveResult {
        let image = render(background: background)
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .denied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
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
                    detail: "Share is the square with an arrow, bottom left.")
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
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
