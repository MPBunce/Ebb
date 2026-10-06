//
//  ScenesSection.swift
//  Ebb
//
//  Picture wallpapers. Picking one cuts matching slices for the widgets, saves the
//  wallpaper to Photos, and explains the one extra step: telling each widget where it sits.
//

import PhotosUI
import SwiftUI

struct ScenesSection: View {
    @Environment(\.openURL) private var openURL

    @State private var current = SceneWallpaper.current
    @State private var layout = IconLayout.current
    @State private var thumbnails: [SceneWallpaper: UIImage] = [:]
    @State private var lastImage: UIImage?
    @State private var saveResult: Wallpaper.SaveResult?
    @State private var isWorking = false

    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(SceneWallpaper.allCases) { scene in
                        Button { choose(scene) } label: { card(scene) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(scene.name) scene")
                            .accessibilityAddTraits(current == scene ? .isSelected : [])
                    }
                }
                .padding(.vertical, 6)
            }
            .disabled(isWorking)

            if current != nil {
                Picker("Home Screen icons", selection: $layout) {
                    ForEach(IconLayout.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: layout) { _, new in
                    IconLayout.current = new
                    SceneRenderer.refreshSlices()
                }

                Button {
                    Task { await save() }
                } label: {
                    Label(isWorking ? "Saving…" : (saveResult == .saved ? "Saved to Photos" : "Save wallpaper to Photos"),
                          systemImage: saveResult == .saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                }
                .disabled(isWorking)

                if case .denied = saveResult {
                    Button("Allow Photos access in Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }

                Button("Use a plain color instead", role: .destructive) {
                    SceneRenderer.clear()
                    current = nil
                    saveResult = nil
                }
            }
        } header: {
            Text("Scenes")
        } footer: {
            if current != nil {
                Text("**Set it up:** save the wallpaper, then in Photos tap Share › Use as Wallpaper, pinch it so it fills the screen exactly, and turn off Perspective Zoom. Then long-press each Ebb widget › Edit Widget, and set **Row** (the icon row its top edge is on) and, for small widgets, **Side**. Pick the icon size you use under Home Screen › Edit › Customize.")
            } else {
                Text("Picture wallpapers with widgets that blend into them. Ebb draws each scene for your iPhone's screen and gives every widget the piece of the picture behind it.")
            }
        }
        .task { await loadThumbnails() }
    }

    private func card(_ scene: SceneWallpaper) -> some View {
        VStack(spacing: 6) {
            Group {
                if let image = thumbnails[scene] {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill((HexColor(hex: scene.baseHex) ?? HexColor(red: 0, green: 0, blue: 0)).color)
                }
            }
            .frame(width: 78, height: 168)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(current == scene ? Color.accentColor : Color.secondary.opacity(0.3),
                                  lineWidth: current == scene ? 2.5 : 1)
            }
            Text(scene.name)
                .font(.footnote)
                .foregroundStyle(current == scene ? .primary : .secondary)
        }
    }

    private func loadThumbnails() async {
        for scene in SceneWallpaper.allCases where thumbnails[scene] == nil {
            thumbnails[scene] = SceneRenderer.thumbnail(scene)
            await Task.yield()
        }
    }

    private func choose(_ scene: SceneWallpaper) {
        isWorking = true
        saveResult = nil
        lastImage = SceneRenderer.apply(scene, layout: layout)
        current = scene
        isWorking = false
    }

    private func save() async {
        guard let scene = current else { return }
        isWorking = true
        defer { isWorking = false }
        let image = lastImage ?? SceneRenderer.apply(scene, layout: layout)
        saveResult = await SceneRenderer.saveToPhotos(image, name: scene.name)
    }
}

/// Cuts the widget slices from a screenshot of the user's own Home Screen, so the widgets
/// match the wallpaper exactly as iOS draws it. Works with Ebb's scenes or any photo.
struct ScreenMatchSection: View {
    @State private var item: PhotosPickerItem?
    @State private var layout = IconLayout.current
    @State private var matched = SceneSlices.fromScreenshot
    @State private var message: String?
    @State private var isWorking = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                step(1, "Set your wallpaper (one of the scenes above, or any photo).")
                step(2, "On your Home Screen, long-press an empty spot, then swipe left past your last page to an empty page.")
                step(3, "Take a screenshot there (side button + volume up), then tap Done.")
                step(4, "Choose that screenshot below.")
            }
            .padding(.vertical, 4)

            Picker("Home Screen icons", selection: $layout) {
                ForEach(IconLayout.allCases) { Text($0.label).tag($0) }
            }

            PhotosPicker(selection: $item, matching: .screenshots) {
                Label(isWorking ? "Matching…" : (matched ? "Match again with a new screenshot" : "Choose screenshot"),
                      systemImage: matched ? "checkmark.circle.fill" : "photo.badge.checkmark")
            }
            .disabled(isWorking)

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(matched ? Color.green : Color.red)
            }

            if matched {
                NavigationLink("Which row is my widget on?") { WidgetRowGuide(layout: layout) }
            }
        } header: {
            Text("Match my Home Screen")
        } footer: {
            Text("iPhone zooms, dims and color-shifts wallpapers a little. Matching from a screenshot copies exactly what's on your screen, so widgets blend in as much as iOS allows (iOS still draws a faint outline around every widget). Then set each widget's Row in Edit Widget.")
        }
        .onChange(of: item) { _, new in
            guard let new else { return }
            Task { await match(new) }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(.tint)
            Text(text).font(.subheadline)
        }
    }

    private func match(_ item: PhotosPickerItem) async {
        isWorking = true
        defer { isWorking = false; self.item = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            matched = false
            message = "Couldn't open that screenshot."
            return
        }
        switch SceneRenderer.matchScreenshot(image, layout: layout) {
        case .success:
            matched = true
            message = "Matched. Your widgets now use your screen's wallpaper."
        case .failure(.wrongSize):
            matched = false
            message = "That screenshot isn't from this iPhone's screen. Take it on this iPhone, in portrait."
        case .failure(.looksBusy):
            matched = false
            message = "That screenshot has apps or widgets on it. Use an empty Home Screen page."
        case .failure(.unreadable):
            matched = false
            message = "Couldn't read that screenshot."
        }
    }
}

/// Shows which Row value a widget needs, counted in app-icon rows from the top.
struct WidgetRowGuide: View {
    let layout: IconLayout

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    ForEach(0..<6, id: \.self) { row in
                        HStack(spacing: 8) {
                            Text(row == 0 ? "Top" : row < 5 ? "\(row + 1)\(suffix(row + 1)) row" : "")
                                .font(.caption.monospacedDigit())
                                .frame(width: 64, alignment: .trailing)
                                .foregroundStyle(.secondary)
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(row < 5 ? Color.secondary.opacity(0.25) : Color.clear)
                                    .frame(height: 34)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            } footer: {
                Text("Each row is one row of app icons. A small or medium widget covers 2 rows, a large one covers 4. Set Row to the row its top edge is on: a widget under a medium or small widget at the top is on the 3rd row.")
            }
        }
        .navigationTitle("Widget rows")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func suffix(_ n: Int) -> String {
        switch n { case 2: "nd"; case 3: "rd"; default: "th" }
    }
}
