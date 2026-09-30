import SwiftUI
import Translation

struct CaptionOverlayView: View {
    @Environment(CaptionController.self) private var controller

    private let microphoneYellow = Color(red: 1, green: 0.84, blue: 0.22)

    var body: some View {
        @Bindable var controller = controller

        VStack(alignment: .leading, spacing: 12) {
            controlBar
            Divider().opacity(0.35)
            captionList
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 220)
        .background(.ultraThinMaterial)
        .translationTask(controller.translationConfiguration) { session in
            await controller.attachTranslationSession(session)
        }
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button(controller.isRunning ? "Detener" : "Iniciar") {
                controller.toggleRunning()
            }
            .keyboardShortcut(.space, modifiers: [.command])
            .controlSize(.large)

            if controller.transcribeSystemAudio || controller.transcribeMyVoice {
                VStack(alignment: .leading, spacing: 3) {
                    if controller.transcribeSystemAudio {
                        AudioMeter(level: controller.audioLevel, tint: .green)
                    }
                    if controller.transcribeMyVoice {
                        AudioMeter(level: controller.microphoneLevel, tint: microphoneYellow)
                    }
                }
                .frame(width: 72)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(controller.statusLabel)
                    .font(.callout)
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
                if let hint = controller.translationHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                if let hint = controller.systemAudioHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                if let hint = controller.microphoneHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }

            Spacer()

            Toggle("Audio", isOn: Binding(
                get: { controller.transcribeSystemAudio },
                set: { controller.transcribeSystemAudio = $0 }
            ))
            .toggleStyle(.checkbox)
            .help("Lo que suena en la Mac (Zoom, Meet, YouTube). Dejalo apagado si solo querés transcribir tu micrófono.")

            Toggle("Mi voz", isOn: Binding(
                get: { controller.transcribeMyVoice },
                set: { controller.transcribeMyVoice = $0 }
            ))
            .toggleStyle(.checkbox)
            .help("Activá esto con auriculares para transcribir lo que decís, en amarillo. Dejalo apagado si usás parlantes.")

            Toggle("Inglés", isOn: Binding(
                get: { controller.showEnglish },
                set: { controller.showEnglish = $0 }
            ))
            .toggleStyle(.checkbox)

            Button("Limpiar") {
                controller.clearHistory()
            }
            .disabled(controller.lines.isEmpty && !controller.hasLiveText)
        }
        .font(.system(.body, design: .rounded))
    }

    private var captionList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(controller.lines) { line in
                        captionRow(
                            spanish: line.spanish,
                            english: line.english,
                            source: line.source,
                            translating: line.isTranslating
                        )
                        .id(line.id)
                    }

                    if !controller.liveSystemEnglish.isEmpty {
                        captionRow(
                            spanish: controller.liveSystemEnglish,
                            english: controller.liveSystemEnglish,
                            source: .system,
                            translating: true,
                            isLive: true
                        )
                        .id("live-system")
                    }

                    if !controller.liveMicrophoneEnglish.isEmpty {
                        captionRow(
                            spanish: controller.liveMicrophoneEnglish,
                            english: controller.liveMicrophoneEnglish,
                            source: .microphone,
                            translating: true,
                            isLive: true
                        )
                        .id("live-microphone")
                    }

                    if controller.lines.isEmpty && !controller.hasLiveText {
                        emptyState
                    }
                }
                .padding(.trailing, 4)
            }
            .onChange(of: controller.lines.count) {
                scrollToBottom(proxy)
            }
            .onChange(of: controller.liveSystemEnglish) {
                scrollToBottom(proxy)
            }
            .onChange(of: controller.liveMicrophoneEnglish) {
                scrollToBottom(proxy)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Subtítulos en español")
                .font(.title2.weight(.semibold))
            Text("Tocá Iniciar. “Audio” transcribe lo que suena en la Mac (blanco). “Mi voz” transcribe lo que decís (amarillo). Podés usar uno, el otro, o los dos. ⌘⇧H muestra u oculta esta ventana.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if showsPermissionHelp {
                HStack {
                    Button("Permiso de audio del sistema") {
                        controller.openSystemAudioSettings()
                    }
                    Button("Permiso de micrófono") {
                        controller.openMicrophoneSettings()
                    }
                    Button("Packs de traducción") {
                        controller.openTranslationSettings()
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }

    private func captionRow(
        spanish: String,
        english: String,
        source: CaptionSource,
        translating: Bool,
        isLive: Bool = false
    ) -> some View {
        let isMic = source == .microphone
        let textColor = isMic
            ? microphoneYellow.opacity(isLive ? 0.78 : 1)
            : Color.primary.opacity(isLive ? 0.72 : 1)

        return HStack(alignment: .top, spacing: 8) {
            if isMic {
                Capsule()
                    .fill(microphoneYellow)
                    .frame(width: 4)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(spanish.isEmpty ? "…" : spanish)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(textColor)
                    .textSelection(.enabled)

                if controller.showEnglish {
                    Text(english)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(isMic ? microphoneYellow.opacity(0.7) : Color.secondary)
                        .textSelection(.enabled)
                }

                if translating && !isLive {
                    Text("Traduciendo…")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var showsPermissionHelp: Bool {
        if case .error = controller.status { return true }
        return controller.status == .idle
    }

    private var statusColor: Color {
        switch controller.status {
        case .listening:
            return .green
        case .error:
            return .orange
        case .starting, .downloadingSpeech:
            return .secondary
        case .idle:
            return .secondary
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                if !controller.liveMicrophoneEnglish.isEmpty {
                    proxy.scrollTo("live-microphone", anchor: .bottom)
                } else if !controller.liveSystemEnglish.isEmpty {
                    proxy.scrollTo("live-system", anchor: .bottom)
                } else if let last = controller.lines.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

struct AudioMeter: View {
    let level: Float
    var tint: Color = .green

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(level > Float(index) / 5 ? tint.opacity(0.9) : Color.secondary.opacity(0.25))
                    .frame(width: 8, height: 6)
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
        .accessibilityLabel("Nivel de audio")
    }
}
