import AppKit
import ApplicationServices
import Carbon
import SwiftUI
import Translation

final class TranslationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var settingsWindow: NSWindow?
    private let preferences = AppPreferences()
    private var selectionTask: Task<Void, Never>?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "划词翻译")
        let menu = NSMenu()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        menu.addItem(NSMenuItem(title: "划词翻译 v\(version) · 中英文互译", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        addItem("翻译选中文字  ⌥D", action: #selector(translateSelection), to: menu)
        addItem("输入文字翻译…", action: #selector(manualTranslation), to: menu)
        addItem("设置…", action: #selector(showSettings), to: menu)
        addItem("使用帮助…", action: #selector(openHelp), to: menu)
        menu.addItem(.separator())
        addItem("授权辅助功能…", action: #selector(requestAccessibility), to: menu)
        addItem("退出划词翻译", action: #selector(quit), to: menu)
        statusItem.menu = menu
        preferences.onVisibilityChange = { [weak self] visible in
            self?.statusItem.isVisible = visible
        }
        statusItem.isVisible = preferences.showMenuBarIcon
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        registerShortcut()
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            show(text: "", message: "选中文字后按 ⌥D 即可翻译。首次使用请从菜单栏授权辅助功能；也可以直接在这里输入或粘贴文字。首次翻译可能需要下载 Apple 语言包。")
            UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "划词翻译")
        let inputItem = NSMenuItem(title: "输入文字翻译…", action: #selector(manualTranslation), keyEquivalent: "n")
        inputItem.target = self
        appMenu.addItem(inputItem)
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出划词翻译", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        // Nil targets route editing commands to the focused text view.
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }

    private func addItem(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    private func registerShortcut() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == 0x5354524E, identifier.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            delegate.translateSelection()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        let identifier = EventHotKeyID(signature: 0x5354524E, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(optionKey), identifier, GetApplicationEventTarget(), 0, &hotKey)
        if handlerStatus != noErr || status != noErr {
            show(text: "", message: "快捷键注册失败，可能被其他软件占用。请使用菜单栏或右键服务进行翻译。")
        }
    }

    @objc private func translateSelection() {
        guard AXIsProcessTrusted() else {
            show(text: "", message: nil, permissionHelp: true)
            return
        }
        guard selectionTask == nil else { return }
        let sourceApp = NSWorkspace.shared.frontmostApplication
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.3)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            readSelectionByCopy(from: sourceApp)
            return
        }
        let focused = unsafeBitCast(focusedValue, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(focused, 0.3)
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, kAXSubroleAttribute as CFString, &subrole)
        guard subrole as? String != kAXSecureTextFieldSubrole as String else {
            showSelectionUnavailable()
            return
        }
        var selectedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &selectedValue) == .success,
              let selected = selectedValue as? String,
              !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            readSelectionByCopy(from: sourceApp)
            return
        }
        show(text: selected, message: nil)
    }

    private func readSelectionByCopy(from sourceApp: NSRunningApplication?) {
        guard let sourceApp else {
            showSelectionUnavailable()
            return
        }
        selectionTask = Task { @MainActor [weak self] in
            let result = await ClipboardSelectionReader.read(from: sourceApp)
            guard let self else { return }
            self.selectionTask = nil
            switch result {
            case .text(let text): self.show(text: text, message: nil)
            case .unavailable: self.showSelectionUnavailable()
            case .cancelled: break
            }
        }
    }

    private func showSelectionUnavailable() {
        show(text: "", message: "未读取到选中文字。请先在其他应用中选中文字再按 ⌥D。辅助功能和复制取词均未取得文字时，可手动复制后在这里粘贴。")
    }

    @objc func translateService(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "没有可翻译的文字。"
            return
        }
        show(text: text, message: nil)
    }

    @objc private func manualTranslation() { show(text: "", message: nil) }

    @objc private func openHelp() {
        guard let url = Bundle.main.url(forResource: "Help", withExtension: "html") else { return }
        NSWorkspace.shared.open(url)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 448, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            settings.title = "划词翻译设置"
            settings.isReleasedWhenClosed = false
            settings.level = .floating
            settings.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            settings.contentViewController = NSHostingController(rootView: SettingsView(preferences: preferences, onPermission: { [weak self] in
                self?.requestAccessibility()
            }, onQuit: { [weak self] in
                self?.quit()
            }, onHelp: { [weak self] in
                self?.openHelp()
            }, onTranslate: { [weak self] in
                self?.manualTranslation()
            }))
            settings.center()
            settingsWindow = settings
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func requestAccessibility() {
        show(text: "", message: nil, permissionHelp: true)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func show(text: String, message: String?, permissionHelp: Bool = false) {
        if window == nil {
            let panel = TranslationPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 410), styleMask: [.borderless], backing: .buffered, defer: false)
            panel.title = "划词翻译"
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.center()
            window = panel
        }
        window?.level = .floating
        let screenHeight = (window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        let maximumResultHeight = max(40, screenHeight - (permissionHelp ? 540 : 440))
        let hosting = NSHostingController(rootView: TranslationView(text: text, message: message, permissionHelp: permissionHelp, maximumResultHeight: maximumResultHeight, onPin: { [weak self] pinned in
            self?.window?.level = pinned ? .floating : .normal
        }, onClose: { [weak self] in
            self?.window?.orderOut(nil)
        }, onSettings: { [weak self] in
            self?.showSettings()
        }, onSizeChange: { [weak self] size in
            self?.resizeTranslationWindow(to: size)
        }).id(UUID()))
        hosting.sizingOptions = []
        window?.contentViewController = hosting
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func resizeTranslationWindow(to size: CGSize) {
        guard let window, size.width > 0, size.height > 0 else { return }
        var frame = window.frame
        let top = frame.maxY
        frame.size = NSSize(width: ceil(size.width), height: ceil(size.height))
        frame.origin.y = top - frame.height
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame.insetBy(dx: 8, dy: 8) {
            frame.origin.y = max(visible.minY, min(frame.origin.y, visible.maxY - frame.height))
            frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
        }
        if window.frame != frame { window.setFrame(frame, display: true) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        selectionTask?.cancel()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
