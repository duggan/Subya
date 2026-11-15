import CaptionKit
import AVKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var isTargeted = false
    @FocusState private var focusedCaption: Caption.ID?
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // Bars are stacked, not overlaid: HSplitView ignores safe-area insets, so an inset bar
        // would sit on top of the transport controls.
        VStack(spacing: 0) {
            Group {
                if let player = model.player {
                    HSplitView {
                        VStack(spacing: 0) {
                            PlayerView(player: player)
                                .contentShape(Rectangle())
                                .overlay {
                                    if model.isCropping { CropOverlay(model: model) } else { VideoControls(model: model) }
                                }
                                .overlay(alignment: .topLeading) {
                                    if !model.isCropping { CropButton(model: model).padding(12) }
                                }
                                .overlay(alignment: .top) { if model.isCropping { CropToolbar(model: model) } }
                                .layoutPriority(-1)
                            Divider()
                            CaptionTimeline(model: model)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                            TransportBar(model: model)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(minWidth: 420, minHeight: 260)
                        VStack(spacing: 0) {
                            styleBar
                            Divider()
                            captionList
                        }
                        .frame(minWidth: 380, idealWidth: 440)
                    }
                } else {
                    dropZone
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            bottomBar
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.open(url)
            return true
        } isTargeted: { isTargeted = $0 }
        .alert("Something went wrong", isPresented: .constant(model.errorMessage != nil)) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .frame(minWidth: 900, minHeight: 560)
        .background(InitialWindowSize(width: 1280, height: 820))
        .onAppear {
            // Developer option: --settings <tab> opens Settings at launch.
            if CommandLine.arguments.contains("--settings") { openSettings() }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "captions.bubble").font(.system(size: 52)).foregroundStyle(.secondary)
            Text("Drop a video here").font(.title2.bold())
            Text("It's transcribed on this Mac, then you can fix the text and export.")
                .foregroundStyle(.secondary)
            Button("Choose Video…") { model.chooseFile() }.controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
            .foregroundStyle(isTargeted ? Color.accentColor : .secondary.opacity(0.4))
            .padding(20))
    }

    /// Style, position, caps and size. Changes show in the paused preview straight away.
    /// Styles are made and edited in Settings.
    private var styleBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("Style", selection: Binding(get: { model.choice.styleID }, set: { model.selectStyle($0) })) {
                    ForEach(CaptionStyle.builtIns) { style in
                        Text(style.name).tag(style.id)
                    }
                    if !model.styles.custom.isEmpty {
                        Divider()
                        ForEach(model.styles.custom) { style in
                            Text(style.name).tag(style.id)
                        }
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                .help("Caption style")
                SettingsLink {
                    Image(systemName: "paintbrush")
                }
                .buttonStyle(.borderless)
                .help("Make and edit styles in Settings")
                Picker("Position", selection: $model.choice.position) {
                    ForEach(CaptionStyle.Position.allCases) { position in
                        Text(position.displayName).tag(Optional(position))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Where captions sit in the frame")
                Toggle(isOn: $model.choice.allCaps) { Text("AA").fontWeight(.heavy) }
                    .toggleStyle(.button)
                    .help("All caps")
            }
            HStack(spacing: 6) {
                Toggle(isOn: Binding(get: { model.choice.display == .word },
                                     set: { model.choice.display = $0 ? .word : .line })) {
                    Label("One word", systemImage: "text.word.spacing")
                }
                .toggleStyle(.button)
                .help("Show one word at a time, as each is spoken")
                Image(systemName: "textformat.size.smaller").foregroundStyle(.secondary)
                    .padding(.leading, 6)
                Slider(value: $model.choice.scale, in: 0.6...1.8)
                Image(systemName: "textformat.size.larger").foregroundStyle(.secondary)
            }
            .help("Text size")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var captionList: some View {
        ScrollViewReader { proxy in
        List {
            ForEach($model.captions) { $cap in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Button { model.play(cap) } label: { Image(systemName: "play.circle") }
                        .buttonStyle(.borderless).help("Play from this caption")
                    TextField("Start", value: $cap.start, format: .number.precision(.fractionLength(2)))
                        .frame(width: 52).monospacedDigit()
                    Text("–").foregroundStyle(.secondary)
                    TextField("End", value: $cap.end, format: .number.precision(.fractionLength(2)))
                        .frame(width: 52).monospacedDigit()
                    TextField("Caption", text: $cap.text, axis: .vertical)
                        .focused($focusedCaption, equals: cap.id)
                    Button { model.delete(cap) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).help("Remove caption")
                }
                .textFieldStyle(.roundedBorder)
                .padding(.vertical, 2)
                .listRowBackground(isShowing(cap) ? Color.accentColor.opacity(0.18) : Color.clear)
            }
        }
        .overlay {
            if model.captions.isEmpty {
                if model.isBusy {
                    ProgressView(model.status)
                } else {
                    VStack(spacing: 8) {
                        Text("No captions yet").font(.headline)
                        Text("Move the playhead and press + Line (⌘N)\nto add a caption there.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: model.focusRequest) { _, id in
            guard let id else { return }
            model.focusRequest = nil
            withAnimation { proxy.scrollTo(id, anchor: .center) }
            // Wait a moment for the new row to exist before focusing its text field.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                focusedCaption = id
            }
        }
        }
    }

    private func isShowing(_ cap: Caption) -> Bool {
        model.currentCaptionID == cap.id
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            if model.player != nil {
                Button("Open Another…") { model.chooseFile() }
            }
            if model.isBusy && !model.captions.isEmpty { ProgressView().controlSize(.small) }
            Text(model.status).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if model.player != nil {
                Button("Export…") { model.exportVideo() }
                    .keyboardShortcut("e")
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy || model.captions.isEmpty)
            }
        }
        .padding(10)
        .background(.bar)
    }
}

/// Opens the window roomy (up to 1280×820, within 90% of the screen) the first time, so
/// the preview and timeline have space. SwiftUI's `defaultSize` and
/// `defaultWindowPlacement` were both ignored here (the window opened at its minimum),
/// so this sets the size through AppKit once macOS has no saved frame for the window.
/// After that, macOS remembers whatever size the user picks.
private struct InitialWindowSize: NSViewRepresentable {
    let width: CGFloat
    let height: CGFloat

    func makeNSView(context: Context) -> NSView { Sizer(size: CGSize(width: width, height: height)) }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Sizer: NSView {
        let size: CGSize
        private var done = false

        init(size: CGSize) {
            self.size = size
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !done, let window else { return }
            done = true
            let key = "NSWindow Frame \(window.frameAutosaveName)"
            guard window.frameAutosaveName.isEmpty || UserDefaults.standard.string(forKey: key) == nil,
                  let screen = window.screen ?? NSScreen.main else { return }
            let visible = screen.visibleFrame
            let target = CGSize(width: min(size.width, visible.width * 0.9), height: min(size.height, visible.height * 0.9))
            // Let SwiftUI finish its own sizing first, then apply ours.
            DispatchQueue.main.async {
                window.setContentSize(target)
                window.center()
            }
        }
    }
}

/// Play/pause, the scrubber, the time, timeline zoom and "+ Line". A view of its own so
/// that only it re-renders as the playhead moves, not the whole window.
private struct TransportBar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 18)
            }
            .buttonStyle(.borderless)
            .font(.title3)
            .help(model.isPlaying ? "Pause" : "Play")
            Slider(value: Binding(get: { model.currentTime }, set: { model.seek(to: $0) }),
                   in: 0...max(model.duration, 0.1))
            Text("\(Self.format(model.currentTime)) / \(Self.format(model.duration))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            zoomControl
            Button { model.addCaption() } label: { Label("Line", systemImage: "plus") }
                .disabled(model.isBusy)
                .help("Add a caption line at the playhead (⌘N)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Timeline zoom: −/+ and a slider on a log scale, from fitting the whole video to
    /// `maxTimelineZoom`.
    private var zoomControl: some View {
        let maxZoom = max(model.maxTimelineZoom, 1.01)
        return HStack(spacing: 2) {
            Button { model.zoomTimeline(by: 1 / 1.5) } label: { Image(systemName: "minus.magnifyingglass") }
                .disabled(model.timelineZoom <= 1)
            Slider(value: Binding(get: { log(model.timelineZoom) / log(maxZoom) },
                                  set: { model.setTimelineZoom(exp($0 * log(maxZoom))) }),
                   in: 0...1)
                .frame(width: 70)
            Button { model.zoomTimeline(by: 1.5) } label: { Image(systemName: "plus.magnifyingglass") }
                .disabled(model.timelineZoom >= maxZoom)
        }
        .buttonStyle(.borderless)
        .help("Zoom the timeline (⌘+ and ⌘−, ⌘0 to fit, or pinch on it)")
    }

    private static func format(_ t: Double) -> String {
        let t = max(0, t.isFinite ? t : 0)
        return String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
    }
}
