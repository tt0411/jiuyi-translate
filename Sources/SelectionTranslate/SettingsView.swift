import AppKit
import ServiceManagement
import SwiftUI

final class AppPreferences: ObservableObject {
    private let defaults: UserDefaults
    var onVisibilityChange: ((Bool) -> Void)?
    @Published private(set) var loginStatus = SMAppService.mainApp.status
    @Published private(set) var loginError: String?

    var launchAtLoginRequested: Bool {
        loginStatus == .enabled || loginStatus == .requiresApproval
    }

    var loginStatusText: String {
        switch loginStatus {
        case .enabled:
            return "已启用：登录 Mac 后自动在后台运行，⌥D 可直接翻译。"
        case .requiresApproval:
            return "等待系统批准：请打开系统登录项，允许“划词翻译”自动启动。"
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["showMenuBarIcon": true])
        showMenuBarIcon = defaults.bool(forKey: "showMenuBarIcon")
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
            Toggle("在菜单栏显示图标", isOn: $preferences.showMenuBarIcon)
                .toggleStyle(.switch)
            Text("隐藏图标后，应用仍在后台运行，选中文字按 ⌥D 即可翻译。设置会在下次启动时保留。")
                .foregroundStyle(.secondary)
            Text("可从翻译窗口右上角的齿轮打开设置；也可以再次双击应用打开设置，恢复菜单栏图标。")
                .foregroundStyle(.secondary)
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
            Text("划词翻译 v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版") · 中英文互译")
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
