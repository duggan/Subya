import AppKit
import CaptionKit
import Speech
import SwiftUI

/// The Settings window (⌘,): General preferences and the caption style editor.
struct SettingsView: View {
    @Bindable var model: AppModel

    /// `--settings styles` (a developer option) opens on the Styles tab.
    @State private var tab = CommandLine.arguments.firstIndex(of: "--settings")
        .flatMap { CommandLine.arguments.indices.contains($0 + 1) ? CommandLine.arguments[$0 + 1] : nil } ?? "general"

    var body: some View {
        TabView(selection: $tab) {
            Tab("General", systemImage: "gearshape", value: "general") {
                GeneralSettings()
            }
            Tab("Styles", systemImage: "paintbrush", value: "styles") {
                StylesSettings(model: model)
            }
        }
        .frame(width: 760, height: 560)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @AppStorage(Pref.language) private var language = ""
    @AppStorage(Pref.maxLineLength) private var maxLineLength = 40
    @AppStorage(Pref.splitPause) private var splitPause = 0.6
    @AppStorage(Pref.linger) private var linger = 0.6
    @AppStorage(Pref.exportLocation) private var exportLocation = ExportLocation.beside.rawValue
    @AppStorage(Pref.exportFolder) private var exportFolder = ""
    @AppStorage(Pref.exportSuffix) private var exportSuffix = "-captioned"
    @AppStorage(Pref.exportQuality) private var exportQuality = ExportQuality.high.rawValue
    @AppStorage(Pref.revealAfterExport) private var revealAfterExport = true

    @State private var locales: [Locale] = []

    var body: some View {
        Form {
            Section("Transcription") {
                Picker("Language", selection: $language) {
                    Text("Same as this Mac (\(Self.name(of: .current)))").tag("")
                    if !locales.isEmpty { Divider() }
                    ForEach(locales, id: \.identifier) { locale in
                        Text(Self.name(of: locale)).tag(locale.identifier)
                    }
                }
                Text("The first video in a new language downloads its speech model.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Longest line") {
                    Stepper("\(maxLineLength) characters", value: $maxLineLength, in: 15...80, step: 5)
                }
                LabeledContent("New caption after a pause of") {
                    HStack {
                        Slider(value: $splitPause, in: 0.2...1.5, step: 0.1)
                        Text(String(format: "%.1f s", splitPause)).monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                LabeledContent("Keep captions up after speech") {
                    HStack {
                        Slider(value: $linger, in: 0...2, step: 0.1)
                        Text(String(format: "%.1f s", linger)).monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            } header: {
                Text("Caption splitting")
            } footer: {
                Text("Applies to the next video you open. To apply it to the open one, choose Captions › Re-split Captions.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Export") {
                Picker("Save to", selection: $exportLocation) {
                    ForEach(ExportLocation.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if exportLocation == ExportLocation.folder.rawValue {
                    LabeledContent("Folder") {
                        HStack {
                            Text(exportFolder.isEmpty ? "None chosen" : (exportFolder as NSString).abbreviatingWithTildeInPath)
                                .lineLimit(1).truncationMode(.middle)
                                .foregroundStyle(exportFolder.isEmpty ? .secondary : .primary)
                            Button("Choose…") { chooseFolder() }
                        }
                    }
                }
                TextField("Add to the file name", text: $exportSuffix, prompt: Text("-captioned"))
                Text("clip.mov is saved as clip\(exportSuffix).mp4, never replacing an existing file.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Quality", selection: $exportQuality) {
                    ForEach(ExportQuality.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("Show the file in Finder after exporting", isOn: $revealAfterExport)
            }
        }
        .formStyle(.grouped)
        .task {
            let supported = await SpeechTranscriber.supportedLocales
            locales = supported.sorted { Self.name(of: $0) < Self.name(of: $1) }
        }
    }

    private static func name(of locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { exportFolder = url.path }
    }
}

// MARK: - Styles

private struct StylesSettings: View {
    @Bindable var model: AppModel
    @State private var selection: CaptionStyle.ID?

    private var store: StyleStore { model.styles }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    Section("Built In") {
                        ForEach(CaptionStyle.builtIns) { Text($0.name).tag($0.id) }
                    }
                    Section("My Styles") {
                        if store.custom.isEmpty {
                            Text("Duplicate a style to make your own").foregroundStyle(.secondary).font(.caption)
                        }
                        ForEach(store.custom) { Text($0.name).tag($0.id) }
                    }
                }
                Divider()
                HStack(spacing: 2) {
                    Button { newStyle() } label: { Image(systemName: "plus").frame(width: 20, height: 18) }
                        .help("New style, copied from the selected one")
                    Button { deleteSelected() } label: { Image(systemName: "minus").frame(width: 20, height: 18) }
                        .disabled(selectedCustomIndex == nil)
                        .help("Delete the selected style")
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 200)

            Divider()

            if let id = selection, let style = store.style(id: id) {
                StyleEditor(style: binding(for: style), isBuiltIn: style.isBuiltIn) {
                    selection = store.duplicate(style).id
                }
            } else {
                Text("Select a style").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { selection = selection ?? model.choice.styleID }
    }

    private var selectedCustomIndex: Int? {
        store.custom.firstIndex { $0.id == selection }
    }

    /// Edits write straight to the store; built-ins get a read-only binding.
    private func binding(for style: CaptionStyle) -> Binding<CaptionStyle> {
        Binding(
            get: { store.style(id: style.id) ?? style },
            set: { newValue in
                if let i = store.custom.firstIndex(where: { $0.id == style.id }) { store.custom[i] = newValue }
            })
    }

    private func newStyle() {
        let source = selection.flatMap { store.style(id: $0) } ?? .default
        selection = store.duplicate(source).id
    }

    private func deleteSelected() {
        guard let i = selectedCustomIndex else { return }
        let id = store.custom[i].id
        store.delete(id: id)
        selection = store.custom.indices.contains(i) ? store.custom[i].id
            : store.custom.last?.id ?? CaptionStyle.default.id
    }
}

private struct StyleEditor: View {
    @Binding var style: CaptionStyle
    let isBuiltIn: Bool
    let duplicate: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            StylePreview(style: style)
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 4)
            Form {
                if isBuiltIn {
                    HStack {
                        Text("Built-in styles can't be changed.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Duplicate to Edit", action: duplicate)
                    }
                }
                Group {
                    TextField("Name", text: $style.name)
                    FontPicker(fontName: $style.fontName)
                    ColorPicker("Text", selection: $style.textColor.color, supportsOpacity: false)
                    LabeledContent("Outline") {
                        HStack {
                            Slider(value: $style.outlineWidth, in: 0...0.2)
                            Text(style.outlineWidth < 0.005 ? "None" : String(format: "%.0f%%", style.outlineWidth * 100))
                                .monospacedDigit().frame(width: 44, alignment: .trailing)
                            ColorPicker("Outline colour", selection: $style.outlineColor.color, supportsOpacity: false)
                                .labelsHidden()
                                .disabled(style.outlineWidth < 0.005)
                        }
                    }
                    Toggle("Shadow", isOn: $style.shadow)
                    LabeledContent("Box behind text") {
                        HStack {
                            Toggle("Box behind text", isOn: $style.box).labelsHidden()
                            ColorPicker("Box colour", selection: $style.boxColor.color, supportsOpacity: true)
                                .labelsHidden()
                                .disabled(!style.box)
                        }
                    }
                    Picker("Position", selection: $style.position) {
                        ForEach(CaptionStyle.Position.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("Size") {
                        Slider(value: $style.scale, in: 0.6...1.8)
                    }
                    Toggle("All caps", isOn: $style.allCaps)
                }
                .disabled(isBuiltIn)
            }
            .formStyle(.grouped)
        }
    }
}

/// Typeface picker: font family, then the face within it. Includes the system's
/// rounded face, which has no family name of its own.
private struct FontPicker: View {
    @Binding var fontName: String

    private static let roundedFamily = "System Rounded"
    private static let families = [roundedFamily] + NSFontManager.shared.availableFontFamilies

    private var family: String {
        if fontName == CaptionStyle.systemRounded { return Self.roundedFamily }
        return NSFont(name: fontName, size: 12)?.familyName ?? ""
    }

    /// (PostScript name, face name) for each face in the family.
    private func faces(of family: String) -> [(name: String, title: String)] {
        if family == Self.roundedFamily { return [(CaptionStyle.systemRounded, "Black")] }
        return (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap { member in
            guard let name = member.first as? String, let title = member.dropFirst().first as? String else { return nil }
            return (name, title)
        }
    }

    var body: some View {
        LabeledContent("Font") {
            HStack {
                Picker("Family", selection: Binding(get: { family }, set: { pickFamily($0) })) {
                    if !Self.families.contains(family) { Text(fontName).tag(family) }
                    ForEach(Self.families, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                Picker("Face", selection: $fontName) {
                    ForEach(faces(of: family), id: \.name) { Text($0.title).tag($0.name) }
                }
                .labelsHidden()
                .frame(width: 130)
            }
        }
    }

    /// Switching family picks its boldest face, which suits captions best.
    private func pickFamily(_ family: String) {
        let faces = faces(of: family)
        let boldest = faces.max { weight(of: $0.name) < weight(of: $1.name) }
        if let boldest { fontName = boldest.name }
    }

    private func weight(of name: String) -> Int {
        guard let font = NSFont(name: name, size: 12) else { return 0 }
        return NSFontManager.shared.weight(of: font)
    }
}

/// The style drawn on a dusky stand-in for a video frame.
private struct StylePreview: View {
    let style: CaptionStyle

    var body: some View {
        if let image = Self.render(style) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        }
    }

    private static let size = CGSize(width: 960, height: 540)

    private static let background: CGImage? = {
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [NSColor(srgbRed: 0.91, green: 0.64, blue: 0.42, alpha: 1).cgColor,
                      NSColor(srgbRed: 0.24, green: 0.29, blue: 0.55, alpha: 1).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        ctx.setFillColor(NSColor(srgbRed: 0.16, green: 0.18, blue: 0.29, alpha: 1).cgColor)
        ctx.move(to: CGPoint(x: 0, y: 200))
        ctx.addCurve(to: CGPoint(x: size.width, y: 240), control1: CGPoint(x: 300, y: 300), control2: CGPoint(x: 620, y: 150))
        ctx.addLine(to: CGPoint(x: size.width, y: 0))
        ctx.addLine(to: .zero)
        ctx.fillPath()
        return ctx.makeImage()
    }()

    private static func render(_ style: CaptionStyle) -> NSImage? {
        guard let background,
              let caption = CaptionRenderer.image(text: "When the clip hits just right", size: size, style: style),
              let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(origin: .zero, size: size)
        ctx.draw(background, in: rect)
        ctx.draw(caption, in: rect)
        return ctx.makeImage().map { NSImage(cgImage: $0, size: size) }
    }
}

extension Binding where Value == RGBA {
    /// Bridges a saved colour to SwiftUI's ColorPicker.
    var color: Binding<Color> {
        Binding<Color>(
            get: { Color(nsColor: wrappedValue.nsColor) },
            set: { wrappedValue = RGBA(NSColor($0)) })
    }
}
