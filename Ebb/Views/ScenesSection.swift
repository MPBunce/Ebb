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

/// Makes widgets blend into the wallpaper exactly as iOS shows it, in two screenshots:
/// one of an empty Home Screen page (the wallpaper as iOS draws it), and one while the widgets
/// show measuring colors (where each widget really is). No Row settings needed.
struct ScreenMatchSection: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var wallpaperItem: PhotosPickerItem?
    @State private var measureItem: PhotosPickerItem?
    @State private var layout = IconLayout.current
    @State private var wallpaperMatched = SceneSlices.fromScreenshot
    @State private var measuring = WidgetPlacement.isMeasuring
    @State private var widgetsFound = WidgetPlacement.frames.count
    @State private var message: (text: String, ok: Bool)?
    @State private var isWorking = false

    var body: some View {
        Section {
            stepHeader(1, "Match the wallpaper", done: wallpaperMatched)
            Text("On your Home Screen, long-press an empty spot and swipe left past your last page to an empty page. Take a screenshot there, tap Done, then choose it here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            PhotosPicker(selection: $wallpaperItem, matching: .screenshots) {
                Label(wallpaperMatched ? "Choose a new empty-page screenshot" : "Choose empty-page screenshot",
                      systemImage: "photo")
            }
            .disabled(isWorking)

            stepHeader(2, "Find my widgets", done: widgetsFound > 0 && !measuring)
            if measuring {
                Text("Your Ebb widgets are now bright colors. Go to your Home Screen, wait until they've all changed, take a screenshot, then choose it here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                PhotosPicker(selection: $measureItem, matching: .screenshots) {
                    Label("Choose the colorful screenshot", systemImage: "viewfinder")
                }
                .disabled(isWorking)
                Button("Cancel", role: .cancel) {
                    SceneRenderer.stopMeasuring()
                    measuring = false
                }
            } else {
                Text(widgetsFound > 0
                     ? "Ebb knows where \(widgetsFound) widget\(widgetsFound == 1 ? " is" : "s are"). Measure again if you move or add widgets."
                     : "Ebb briefly turns your widgets bright colors so it can see exactly where each one is from a screenshot.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    SceneRenderer.startMeasuring()
                    measuring = true
                    message = nil
                } label: {
                    Label(widgetsFound > 0 ? "Measure again" : "Start measuring", systemImage: "viewfinder")
                }
            }

            if let message {
                Text(message.text)
                    .font(.footnote)
                    .foregroundStyle(message.ok ? Color.green : Color.red)
            }
        } header: {
            Text("Make widgets disappear")
        } footer: {
            Text("iPhone zooms, dims and color-shifts wallpapers a little, so Ebb copies exactly what's on your screen. Works with Ebb's scenes or any photo. iOS still draws a faint outline around every widget.")
        }
        .onChange(of: wallpaperItem) { _, item in
            guard let item else { return }
            Task { await matchWallpaper(item) }
        }
        .onChange(of: measureItem) { _, item in
            guard let item else { return }
            Task { await measure(item) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { measuring = WidgetPlacement.isMeasuring }
        }
    }

    private func stepHeader(_ n: Int, _ title: String, done: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(n).circle")
                .foregroundStyle(done ? Color.green : Color.accentColor)
                .font(.title3)
            Text(title).font(.headline)
        }
        .padding(.top, 4)
    }

    private func loadImage(_ item: PhotosPickerItem) async -> UIImage? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return UIImage(data: data)
    }

    private func matchWallpaper(_ item: PhotosPickerItem) async {
        isWorking = true
        defer { isWorking = false; wallpaperItem = nil }
        guard let image = await loadImage(item) else {
            message = ("Couldn't open that screenshot.", false); return
        }
        switch SceneRenderer.matchScreenshot(image, layout: layout) {
        case .success:
            wallpaperMatched = true
            message = ("Wallpaper matched.", true)
        case .failure(.wrongSize):
            message = ("That screenshot isn't from this iPhone's screen. Take it on this iPhone, in portrait.", false)
        case .failure(.looksBusy):
            message = ("That screenshot has apps or widgets on it. Use an empty Home Screen page.", false)
        case .failure(.unreadable):
            message = ("Couldn't read that screenshot.", false)
        }
    }

    private func measure(_ item: PhotosPickerItem) async {
        isWorking = true
        defer { isWorking = false; measureItem = nil }
        guard let image = await loadImage(item) else {
            message = ("Couldn't open that screenshot.", false); return
        }
        switch SceneRenderer.measure(image) {
        case .success(let count):
            widgetsFound = count
            measuring = false
            message = ("Found \(count) widget\(count == 1 ? "" : "s"). They now use the wallpaper behind them.", true)
        case .failure(.wrongSize):
            message = ("That screenshot isn't from this iPhone's screen.", false)
        case .failure(.noWidgetsFound):
            message = ("No colored widgets found. Wait for them all to change color, then take the screenshot again.", false)
        case .failure(.unreadable):
            message = ("Couldn't read that screenshot.", false)
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
