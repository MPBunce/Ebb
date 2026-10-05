//
//  ScenesSection.swift
//  Ebb
//
//  Picture wallpapers. Picking one cuts matching slices for the widgets, saves the
//  wallpaper to Photos, and explains the one extra step: telling each widget where it sits.
//

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
