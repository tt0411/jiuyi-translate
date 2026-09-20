import AppKit
import ApplicationServices
import AVFoundation
import SwiftUI
import Translation

struct TranslationView: View {
    @FocusState private var isSourceFocused: Bool
    @State private var text: String
    @State private var translated = ""
    @State private var source = "auto"
    @State private var target = "auto"
    @State private var detected = ""
    @State private var outputLanguage = ""
    @State private var configuration: TranslationSession.Configuration?
    @State private var requestID = UUID()
    @State private var busy = false
    @State private var failure: String?
    @State private var pinned = false
    @State private var expanded = true
    @State private var sourceContentHeight: CGFloat = 78
    @State private var resultContentHeight: CGFloat = 40
    @State private var copied: String?
    @State private var speaker = AVSpeechSynthesizer()
    @State private var permissionTrusted = AXIsProcessTrusted()
    let permissionHelp: Bool
    let message: String?
    let shortcut: String
    let onPin: (Bool) -> Void
    let onClose: () -> Void
    let onSettings: () -> Void
    let maximumContentHeight: CGFloat
    let onSizeChange: (CGSize) -> Void

    private let languages = [("auto", "自动"), ("zh-Hans", "中文（简体）"), ("en", "英语")]
    private let card = Color(.sRGB, red: 246 / 255, green: 246 / 255, blue: 246 / 255, opacity: 1)
    private let cardHeader = Color(.sRGB, red: 240 / 255, green: 240 / 255, blue: 240 / 255, opacity: 1)
    private let languageBadge = Color(.sRGB, red: 234 / 255, green: 234 / 255, blue: 234 / 255, opacity: 1)

    init(text: String, message: String?, permissionHelp: Bool, pinned: Bool, shortcut: String, maximumContentHeight: CGFloat, onPin: @escaping (Bool) -> Void, onClose: @escaping () -> Void, onSettings: @escaping () -> Void, onSizeChange: @escaping (CGSize) -> Void) {
        _text = State(initialValue: text)
        _pinned = State(initialValue: pinned)
        self.message = message
        self.permissionHelp = permissionHelp
        self.shortcut = shortcut
        self.onPin = onPin
        self.onClose = onClose
        self.onSettings = onSettings
        self.maximumContentHeight = maximumContentHeight
        self.onSizeChange = onSizeChange
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                icon(pinned ? "pin.fill" : "pin", label: pinned ? "取消置顶" : "置顶窗口") {
                    pinned.toggle()
                    onPin(pinned)
                }
                Spacer()
                Text(shortcut)
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize()
                    .frame(minWidth: 28, minHeight: 28)
                icon("gearshape", label: "设置", action: onSettings)
                icon("arrow.clockwise", label: "重新翻译") { translate() }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                icon("xmark", label: "关闭") { onClose() }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    Text(text.isEmpty ? " " : text)
                        .font(.system(size: 20))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .accessibilityHidden(true)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            sourceContentHeight = ceil(height)
                        }
                        // hidden() still reserves space, so the probe would stretch the card past the
                        // clamped editor once the text is taller than its allowance.
                        .frame(height: 0, alignment: .top)
                    TextEditor(text: $text)
                        .focused($isSourceFocused)
                        .font(.system(size: 20))
                        .scrollContentBackground(.hidden)
                        .scrollDisabled(sourceContentHeight <= sourceEditorHeight + 0.5)
                        .frame(height: sourceEditorHeight)
                        .accessibilityLabel("原文")
                    if text.isEmpty {
                        // Match the native editor's font metrics and text-container insets.
                        TextEditor(text: .constant("输入或粘贴文字，也可选中文字后按 \(shortcut)"))
                            .font(.system(size: 20))
                            .foregroundColor(Color(nsColor: .placeholderTextColor))
                            .scrollContentBackground(.hidden)
                            .frame(height: sourceEditorHeight)
                            .disabled(true)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                HStack(spacing: 16) {
                    icon("speaker.wave.2", label: "朗读原文") { speak(text, language: source == "auto" ? detected : source) }
                        .disabled(text.isEmpty)
                    icon(copied == "source" ? "checkmark" : "square.on.square", label: "复制原文") { copy(text, kind: "source") }
                        .disabled(text.isEmpty)
                    if !detected.isEmpty {
                        HStack(spacing: 5) {
                            Text(source == "auto" ? "识别为" : "原文").foregroundStyle(.secondary)
                            Text(languageName(detected)).foregroundStyle(.blue)
                        }
                        .font(.system(size: 13))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(languageBadge, in: Capsule())
                    }
                    Spacer()
                }
            }
            .padding(16)
            .background(card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black.opacity(0.025)))

            HStack {
                languageMenu(selection: $source, automatic: "自动检测")
                icon("arrow.left.arrow.right", label: "交换语言") { swapLanguages() }
                    .disabled(translated.isEmpty || busy)
                languageMenu(selection: $target, automatic: "自动选择")
            }
            .padding(.vertical, 10)
            .background(card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black.opacity(0.025)))

            VStack(alignment: .leading, spacing: 0) {
                Button { expanded.toggle() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "character.bubble.fill").foregroundStyle(.blue)
                        Text("翻译").font(.system(size: 16))
                        Spacer()
                        if busy { ProgressView().controlSize(.small) }
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 13))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(cardHeader)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "收起译文" : "展开译文")
                if expanded {
                    VStack(alignment: .leading, spacing: 14) {
                        ScrollView {
                            Text(resultText)
                                .font(.system(size: translated.isEmpty ? 14 : 20))
                                .foregroundStyle(failure != nil ? Color.red : (translated.isEmpty ? Color.secondary : Color.primary))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .onGeometryChange(for: CGFloat.self) { proxy in
                                    proxy.size.height
                                } action: { height in
                                    resultContentHeight = ceil(height)
                                }
                        }
                        .frame(height: resultEditorHeight)
                        if permissionHelp && text.isEmpty && !permissionTrusted {
                            HStack {
                                Button("请求授权") {
                                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                                    permissionTrusted = AXIsProcessTrustedWithOptions(options)
                                }
                                Button("检查权限") { permissionTrusted = AXIsProcessTrusted() }
                                Button("定位当前应用") {
                                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                                }
                            }
                        }
                        HStack(spacing: 16) {
                            icon("speaker.wave.2", label: "朗读译文") { speak(translated, language: outputLanguage) }
                            icon(copied == "target" ? "checkmark" : "square.on.square", label: "复制译文") { copy(translated, kind: "target") }
                            Spacer()
                        }
                        .disabled(translated.isEmpty || busy)
                    }
                    .padding(16)
                }
            }
            .background(card, in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black.opacity(0.025)))
        }
        .padding(18)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .preferredColorScheme(.light)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            onSizeChange(size)
        }
        .task(id: text + "\u{0}" + source + "\u{0}" + target) {
            requestID = UUID()
            configuration = nil
            translated = ""
            failure = nil
            busy = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            translate()
        }
        .translationTask(configuration) { session in
            guard configuration != nil else { return }
            let currentID = requestID
            let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !input.isEmpty else { return }
            do {
                let response = try await session.translate(input)
                guard currentID == requestID, !Task.isCancelled else { return }
                translated = response.targetText
                expanded = true
                busy = false
            } catch {
                guard currentID == requestID, !Task.isCancelled else { return }
                failure = "翻译未完成：\(error.localizedDescription)\n请检查中文、英语系统翻译语言包，然后点击右上角重试。"
                busy = false
            }
        }
        .task {
            guard permissionHelp else { return }
            while !Task.isCancelled {
                permissionTrusted = AXIsProcessTrusted()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        .onAppear { isSourceFocused = true }
        .onDisappear { speaker.stopSpeaking(at: .immediate) }
    }

    private let minSourceHeight: CGFloat = 78
    private let minResultHeight: CGFloat = 40

    private var sourceEditorHeight: CGFloat { allocatedHeights.source }

    private var resultEditorHeight: CGFloat { allocatedHeights.result }

    // Grow both text areas with content, then share leftover screen height so the window stays on-screen.
    private var allocatedHeights: (source: CGFloat, result: CGFloat) {
        let resultFloor = expanded ? minResultHeight : 0
        let budget = max(minSourceHeight + resultFloor, maximumContentHeight)
        let sourceDesired = max(minSourceHeight, sourceContentHeight)
        let resultDesired = expanded ? max(minResultHeight, resultContentHeight) : 0
        let extraDemand = (sourceDesired - minSourceHeight) + (resultDesired - resultFloor)
        let extraBudget = budget - minSourceHeight - resultFloor
        guard extraDemand > extraBudget else { return (sourceDesired, resultDesired) }
        let sourceHeight = minSourceHeight + extraBudget * (sourceDesired - minSourceHeight) / extraDemand
        return (wholeLines(sourceHeight, content: sourceContentHeight, inset: 10),
                wholeLines(budget - sourceHeight, content: resultContentHeight, inset: 0))
    }

    private static let lineHeight: CGFloat = {
        let font = NSFont.systemFont(ofSize: 20)
        return ceil(font.ascender - font.descender + font.leading)
    }()

    // AppKit line metrics can differ from SwiftUI by about a point; that only ever leaves a hairline.
    private func wholeLines(_ height: CGFloat, content: CGFloat, inset: CGFloat) -> CGFloat {
        guard content > height else { return height.rounded(.down) }
        let lines = max(1, ((height - inset) / Self.lineHeight).rounded(.down))
        return lines * Self.lineHeight + inset
    }

    private var resultText: String {
        if let failure { return failure }
        if busy { return "正在使用 Apple 系统翻译…" }
        if !translated.isEmpty { return translated }
        if permissionHelp {
            return permissionTrusted
                ? "辅助功能已授权。回到原来的应用，重新选中文字后按 \(shortcut)。"
                : "划词翻译需要辅助功能权限。请点击「请求授权」，在系统设置中开启「啾译」。若已开启仍无效，先移除旧的「啾译」，再点「定位当前应用」重新添加。"
        }
        return message ?? "仅支持中英文互译。首次使用可能需要下载中文和英语语言包。"
    }

    private func icon(_ name: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.monochrome)
                .frame(width: 16, height: 16)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func languageMenu(selection: Binding<String>, automatic: String) -> some View {
        Menu {
            ForEach(languages, id: \.0) { code, name in
                Button(code == "auto" ? automatic : name) { selection.wrappedValue = code }
            }
        } label: {
            Text(selection.wrappedValue == "auto" ? automatic : languageName(selection.wrappedValue))
                .font(.system(size: 17)).frame(maxWidth: .infinity)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 24)
        .accessibilityLabel(automatic == "自动检测" ? "原文语言" : "译文语言")
    }

    private func languageName(_ code: String) -> String {
        languages.first(where: { $0.0 == code })?.1 ?? Locale(identifier: "zh-Hans").localizedString(forLanguageCode: code) ?? code
    }

    // This app only translates Chinese and English; never ask the system to detect a third language.
    static func inferredSourceLanguage(for text: String) -> String {
        text.range(of: #"\p{Han}"#, options: .regularExpression) == nil ? "en" : "zh-Hans"
    }

    private func translate() {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        requestID = UUID()
        failure = nil
        translated = ""
        guard !input.isEmpty else {
            detected = ""
            busy = false
            configuration = nil
            return
        }
        let inferredSource = Self.inferredSourceLanguage(for: input)
        let sourceCode = ["en", "zh-Hans"].contains(source) ? source : inferredSource
        let targetCode = ["en", "zh-Hans"].contains(target) ? target : (sourceCode == "zh-Hans" ? "en" : "zh-Hans")
        detected = sourceCode
        outputLanguage = targetCode
        if sourceCode == targetCode {
            configuration = nil
            translated = input
            expanded = true
            busy = false
            return
        }
        busy = true
        let newConfiguration = TranslationSession.Configuration(
            source: Locale.Language(identifier: sourceCode),
            target: Locale.Language(identifier: targetCode)
        )
        if configuration == newConfiguration {
            configuration?.invalidate()
        } else {
            configuration = newConfiguration
        }
    }

    private func swapLanguages() {
        guard !translated.isEmpty else { return }
        let previousSource = source == "auto" ? detected : source
        source = outputLanguage
        target = previousSource.isEmpty ? "auto" : previousSource
        text = translated
    }

    private func copy(_ value: String, kind: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copied = kind
    }

    private func speak(_ value: String, language: String) {
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: value)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        speaker.speak(utterance)
    }
}
