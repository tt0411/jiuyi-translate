import AppKit
import Carbon
import ServiceManagement
import SwiftUI

struct Hotkey: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let display: String

    static let standard = Hotkey(keyCode: UInt32(kVK_ANSI_D), carbonModifiers: UInt32(optionKey), display: "⌥D")

    // Only printable ASCII keys. Function keys and arrows yield private-use scalars.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.isDisjoint(with: [.command, .option, .control]),
              let typed = event.charactersIgnoringModifiers?.uppercased(),
              let scalar = typed.unicodeScalars.first,
              typed.unicodeScalars.count == 1, scalar.isASCII, scalar.value > 32 else { return nil }
        var carbon: UInt32 = 0
        var label = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); label += "⌃" }
        if flags.contains(.option) { carbon |= UInt32(optionKey); label += "⌥" }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey); label += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey); label += "⌘" }
        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: carbon, display: label + typed)
    }

    private init(keyCode: UInt32, carbonModifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.display = display
    }

    static func load(from defaults: UserDefaults) -> Hotkey {
        guard let display = defaults.string(forKey: "hotKeyDisplay"), !display.isEmpty,
              let modifiers = defaults.object(forKey: "hotKeyModifiers") as? Int, modifiers != 0,
              let keyCode = defaults.object(forKey: "hotKeyCode") as? Int, (0..<128).contains(keyCode) else {
            return .standard
        }
        return Hotkey(keyCode: UInt32(keyCode), carbonModifiers: UInt32(modifiers), display: display)
    }

    func save(to defaults: UserDefaults) {
        defaults.set(Int(keyCode), forKey: "hotKeyCode")
        defaults.set(Int(carbonModifiers), forKey: "hotKeyModifiers")
        defaults.set(display, forKey: "hotKeyDisplay")
    }
}

extension Hotkey {
    /// Run with: swift run SelectionTranslate --self-check
    static func selfCheck() {
        let suite = "hotkey-self-check"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        precondition(load(from: defaults) == .standard, "empty defaults must fall back to ⌥D")

        func keyDown(_ flags: NSEvent.ModifierFlags, _ characters: String, _ keyCode: UInt16) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
        }
        precondition(Hotkey(event: keyDown([], "c", 8)) == nil, "a bare key cannot be a global hotkey")
        precondition(Hotkey(event: keyDown([.shift], "c", 8)) == nil, "shift alone cannot be a global hotkey")
        precondition(Hotkey(event: keyDown([.command], "\u{F704}", 122)) == nil, "F1 is not a printable key")
        guard let recorded = Hotkey(event: keyDown([.command, .shift], "c", 8)) else { preconditionFailure("⇧⌘C must record") }
        precondition(recorded.display == "⇧⌘C", "unexpected label: \(recorded.display)")
        precondition(recorded.carbonModifiers == UInt32(cmdKey | shiftKey), "unexpected carbon modifiers")

        recorded.save(to: defaults)
        precondition(load(from: defaults) == recorded, "a recorded hotkey must survive a reload")
        defaults.removePersistentDomain(forName: suite)
    }
}

final class AppPreferences: ObservableObject {
    private let defaults: UserDefaults
    var onVisibilityChange: ((Bool) -> Void)?
    var onDockVisibilityChange: ((Bool) -> Void)?
    var onHotkeyChange: ((Hotkey) -> Void)?
    @Published private(set) var loginStatus = SMAppService.mainApp.status
    @Published private(set) var loginError: String?

    var launchAtLoginRequested: Bool {
        loginStatus == .enabled || loginStatus == .requiresApproval
    }

    var loginStatusText: String {
        switch loginStatus {
        case .enabled:
            return "已启用：登录 Mac 后自动在后台运行，\(hotkey.display) 可直接翻译。"
        case .requiresApproval:
            return "等待系统批准：请打开系统登录项，允许“啾译”自动启动。"
        case .notRegistered:
            return "开启后，登录 Mac 时自动启动。隐藏菜单栏图标不影响自启动。"
        case .notFound:
            return "系统未找到应用。请将应用放到固定位置（建议“应用程序”目录），重新打开后再开启。"
        @unknown default:
            return "无法确认登录项状态，请在系统登录项中检查。"
        }
    }

    func refreshLoginStatus() {
        loginStatus = SMAppService.mainApp.status
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginError = "无法\(enabled ? "开启" : "关闭")自启动：\(error.localizedDescription)"
        }
        refreshLoginStatus()
    }

    @Published var showMenuBarIcon: Bool {
        didSet {
            defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon")
            onVisibilityChange?(showMenuBarIcon)
        }
    }

    @Published var showDockIcon: Bool {
        didSet {
            defaults.set(showDockIcon, forKey: "showDockIcon")
            onDockVisibilityChange?(showDockIcon)
        }
    }

    @Published var hotkey: Hotkey {
        didSet {
            hotkey.save(to: defaults)
            onHotkeyChange?(hotkey)
        }
    }

    @Published var hotkeyError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["showMenuBarIcon": true, "showDockIcon": true])
        showMenuBarIcon = defaults.bool(forKey: "showMenuBarIcon")
        showDockIcon = defaults.bool(forKey: "showDockIcon")
        hotkey = Hotkey.load(from: defaults)
    }

    /// Run with: swift run SelectionTranslate --self-check
    static func selfCheck() {
        let suite = "dock-icon-self-check"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let prefs = AppPreferences(defaults: defaults)
        precondition(prefs.showDockIcon, "dock icon defaults to visible")
        var observed: Bool?
        prefs.onDockVisibilityChange = { observed = $0 }
        prefs.showDockIcon = false
        precondition(observed == false, "hiding the dock icon must notify")
        precondition(defaults.object(forKey: "showDockIcon") as? Bool == false, "hidden dock icon must be stored")
        let reloaded = AppPreferences(defaults: defaults)
        precondition(!reloaded.showDockIcon, "hidden dock icon must persist")
        defaults.removePersistentDomain(forName: suite)
    }
}

private struct HotkeyRecorder: View {
    @ObservedObject var preferences: AppPreferences
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("翻译快捷键")
                Spacer()
                Button(recording ? "请按下新快捷键…" : preferences.hotkey.display) {
                    if recording { stop() } else { start() }
                }
                .frame(minWidth: 120)
                Button("恢复默认") { preferences.hotkey = .standard }
                    .disabled(preferences.hotkey == .standard)
            }
            Text("点按上方按钮后直接按下组合键，需包含 ⌘、⌥ 或 ⌃；按 esc 取消录制。")
                .foregroundStyle(.secondary)
            if let error = preferences.hotkeyError {
                Text(error).foregroundStyle(.red).font(.callout)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard event.type == .keyDown else { return nil }
            if event.keyCode != UInt16(kVK_Escape), let hotkey = Hotkey(event: event) {
                preferences.hotkey = hotkey
                stop()
            } else if event.keyCode == UInt16(kVK_Escape) {
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences
    let onPermission: () -> Void
    let onQuit: () -> Void
    let onHelp: () -> Void
    let onTranslate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("设置").font(.title2.bold())
            HStack {
                Button("输入文字翻译", action: onTranslate)
                Button("使用帮助", action: onHelp)
            }
            HotkeyRecorder(preferences: preferences)
            Divider()
            Toggle("在菜单栏显示图标", isOn: $preferences.showMenuBarIcon)
                .toggleStyle(.switch)
            Text("隐藏图标后，应用仍在后台运行，选中文字按 \(preferences.hotkey.display) 即可翻译。设置会在下次启动时保留。")
                .foregroundStyle(.secondary)
            Toggle("在 Dock 栏显示图标", isOn: $preferences.showDockIcon)
                .toggleStyle(.switch)
            Text("关闭后 Dock 与程序切换器中不再显示啾译，应用仍在后台运行；可从翻译窗口右上角的齿轮重新打开设置。")
                .foregroundStyle(.secondary)
            if preferences.showDockIcon {
                Text("点击 Dock 图标可直接打开翻译窗口。")
                    .foregroundStyle(.secondary)
            }
            Divider()
            Toggle("登录时自动启动", isOn: Binding(
                get: { preferences.launchAtLoginRequested },
                set: { preferences.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.switch)
            Text(preferences.loginStatusText)
                .foregroundStyle(.secondary)
            if let error = preferences.loginError {
                Text(error).foregroundStyle(.red).font(.callout)
            }
            Button("打开系统登录项…") {
                SMAppService.openSystemSettingsLoginItems()
            }
            Divider()
            HStack {
                Button("授权辅助功能…", action: onPermission)
                Spacer()
                Button("退出应用", action: onQuit)
            }
            Text("啾译 v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版") · 中英文互译")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { preferences.refreshLoginStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            preferences.refreshLoginStatus()
        }
    }
}
