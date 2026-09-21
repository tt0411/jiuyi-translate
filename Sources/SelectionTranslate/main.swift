import AppKit
import ApplicationServices
import Carbon
import SwiftUI
import Translation

final class TranslationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

enum DockIconVisibility {
    static func activationPolicy(visible: Bool) -> NSApplication.ActivationPolicy {
        visible ? .regular : .accessory
    }

    static func selfCheck() {
        precondition(activationPolicy(visible: true) == .regular)
        precondition(activationPolicy(visible: false) == .accessory)
        AppPreferences.selfCheck()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var settingsWindow: NSWindow?
    private var translationPinned = false
    private let preferences = AppPreferences()
    private var selectionTask: Task<Void, Never>?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var translateMenuItem: NSMenuItem?

    func applicationWillFinishLaunching(_ notification: Notification) {
        applyDockVisibility(preferences.showDockIcon)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = MenuBarIcon.image()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "啾译"
        statusItem.button?.setAccessibilityLabel("啾译")
        let menu = NSMenu()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        menu.addItem(NSMenuItem(title: "啾译 v\(version) · 中英文互译", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        translateMenuItem = addItem("翻译选中文字  \(preferences.hotkey.display)", action: #selector(translateSelection), to: menu)
        addItem("输入文字翻译…", action: #selector(manualTranslation), to: menu)
        addItem("设置…", action: #selector(showSettings), to: menu)
        addItem("使用帮助…", action: #selector(openHelp), to: menu)
        menu.addItem(.separator())
        addItem("授权辅助功能…", action: #selector(requestAccessibility), to: menu)
        addItem("退出啾译", action: #selector(quit), to: menu)
        statusItem.menu = menu
        preferences.onVisibilityChange = { [weak self] visible in
            self?.statusItem.isVisible = visible
        }
        statusItem.isVisible = preferences.showMenuBarIcon
        preferences.onDockVisibilityChange = { [weak self] visible in
            self?.applyDockVisibility(visible)
        }
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        registerShortcut()
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            show(text: "", message: "选中文字后按 \(preferences.hotkey.display) 即可翻译。首次使用请从菜单栏授权辅助功能；也可以直接在这里输入或粘贴文字。首次翻译可能需要下载 Apple 语言包。")
            UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "啾译")
        let inputItem = NSMenuItem(title: "输入文字翻译…", action: #selector(manualTranslation), keyEquivalent: "n")
        inputItem.target = self
        appMenu.addItem(inputItem)
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出啾译", action: #selector(quit), keyEquivalent: "q")
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

    @discardableResult
    private func addItem(_ title: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
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
        preferences.onHotkeyChange = { [weak self] hotkey in
            self?.translateMenuItem?.title = "翻译选中文字  \(hotkey.display)"
            self?.bindHotkey()
        }
        bindHotkey()
        if handlerStatus != noErr {
            show(text: "", message: "快捷键注册失败，可能被其他软件占用。请使用菜单栏或右键服务进行翻译。")
        }
    }

    private func bindHotkey() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        let hotkey = preferences.hotkey
        let identifier = EventHotKeyID(signature: 0x5354524E, id: 1)
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.carbonModifiers, identifier, GetApplicationEventTarget(), 0, &hotKey)
        preferences.hotkeyError = status == noErr ? nil : "\(hotkey.display) 可能已被其他软件占用，请换一个组合键。"
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
        // Browsers drop block boundaries from AXSelectedText, so a long selection without a newline
        // is almost certainly several paragraphs glued together. Re-read it with ⌘C, which keeps them.
        if selected.count >= 200, !selected.contains(where: \.isNewline) {
            readSelectionByCopy(from: sourceApp, flattened: selected)
            return
        }
        show(text: selected, message: nil)
    }

    private func readSelectionByCopy(from sourceApp: NSRunningApplication?, flattened: String? = nil) {
        guard let sourceApp else {
            if let flattened { show(text: flattened, message: nil) } else { showSelectionUnavailable() }
            return
        }
        selectionTask = Task { @MainActor [weak self] in
            let result = await ClipboardSelectionReader.read(from: sourceApp)
            guard let self else { return }
            self.selectionTask = nil
            switch result {
            case .text(let text): self.show(text: text, message: nil)
            case .unavailable:
                if let flattened { self.show(text: flattened, message: nil) } else { self.showSelectionUnavailable() }
            case .cancelled:
                if let flattened { self.show(text: flattened, message: nil) }
            }
        }
    }

    private func showSelectionUnavailable() {
        show(text: "", message: "未读取到选中文字。请先在其他应用中选中文字再按 \(preferences.hotkey.display)。辅助功能和复制取词均未取得文字时，可手动复制后在这里粘贴。")
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
        if window != nil {
            presentTranslationWindow()
        } else {
            manualTranslation()
        }
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // An accessory app that becomes active reappears in the Dock. Keep it inactive so the
        // hidden-icon preference actually sticks while panels stay on screen.
        guard !preferences.showDockIcon else { return }
        NSApp.deactivate()
    }

    /// Shows or hides the Dock tile. Switching to `.accessory` while this app is active leaves a
    /// ghost Dock icon, so drop activation first; switching to `.regular` would steal focus, so give
    /// it back. Visible panels are restored because a policy change can order them out.
    private func applyDockVisibility(_ visible: Bool) {
        let policy = DockIconVisibility.activationPolicy(visible: visible)
        let previous = NSWorkspace.shared.frontmostApplication
        let visibleWindows = NSApp.windows.filter(\.isVisible)
        if policy == .accessory, NSApp.isActive {
            NSApp.deactivate()
        }
        NSApp.setActivationPolicy(policy)
        restoreFrontmost(previous)
        for window in visibleWindows {
            window.orderFrontRegardless()
        }
    }

    /// Shows a panel without making 啾译 the active app. That would highlight (or, when the Dock
    /// icon is hidden, resurrect) the Dock tile; the source app should stay frontmost.
    private func presentNonActivating(_ panel: NSWindow, makeKey: Bool = true) {
        let previous = NSWorkspace.shared.frontmostApplication
        panel.orderFrontRegardless()
        if makeKey {
            panel.makeKey()
        }
        restoreFrontmost(previous)
    }

    private func restoreFrontmost(_ previous: NSRunningApplication?) {
        guard NSApp.isActive else { return }
        if let previous, previous != NSRunningApplication.current {
            previous.activate()
        } else {
            NSApp.deactivate()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            // A plain window can never join another app's full-screen space; only a non-activating
            // floating panel can, which is why the translation panel already shows up there.
            let settings = TranslationPanel(contentRect: NSRect(x: 0, y: 0, width: 448, height: 300), styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
            settings.title = "啾译设置"
            settings.isReleasedWhenClosed = false
            settings.isFloatingPanel = true
            settings.hidesOnDeactivate = false
            settings.level = .floating
            settings.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            settings.contentViewController = NSHostingController(rootView: SettingsView(preferences: preferences, onPermission: { [weak self] in
                self?.requestAccessibility()
            }, onQuit: { [weak self] in
                self?.quit()
            }, onHelp: { [weak self] in
                self?.openHelp()
            }, onTranslate: { [weak self] in
                self?.manualTranslation()
            }))
            settingsWindow = settings
        }
        guard let settings = settingsWindow else { return }
        // NSApp.activate would pull the user back to the app's own desktop space, so order the panel
        // in front where they already are instead.
        settings.setFrameOrigin(settingsOrigin(for: settings.frame.size))
        presentNonActivating(settings)
    }

    private func settingsOrigin(for size: NSSize) -> NSPoint {
        let panel = window?.isVisible == true ? window : nil
        let screen = panel?.screen
            ?? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        let anchor = panel?.frame ?? screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: size.width, height: size.height)
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.midY - size.height / 2)
        if let visible = screen?.visibleFrame.insetBy(dx: 8, dy: 8) {
            origin.x = max(visible.minX, min(origin.x, visible.maxX - size.width))
            origin.y = max(visible.minY, min(origin.y, visible.maxY - size.height))
        }
        return origin
    }

    @objc private func requestAccessibility() {
        show(text: "", message: nil, permissionHelp: true)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func show(text: String, message: String?, permissionHelp: Bool = false) {
        if window == nil {
            window = makeTranslationPanel()
        }
        let screenHeight = (window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        // Keep the panel a floating card rather than a full-height window: the two text areas share
        // whatever 85% of the screen leaves after the measured chrome, and scroll beyond that.
        let maximumContentHeight = max(118, screenHeight * 0.85 - (permissionHelp ? 434 : 334))
        let hosting = NSHostingController(rootView: TranslationView(text: text, message: message, permissionHelp: permissionHelp, pinned: translationPinned, shortcut: preferences.hotkey.display, maximumContentHeight: maximumContentHeight, onPin: { [weak self] pinned in
            self?.translationPinned = pinned
            self?.applyPin(pinned)
        }, onClose: { [weak self] in
            self?.window?.orderOut(nil)
        }, onSettings: { [weak self] in
            self?.showSettings()
        }, onSizeChange: { [weak self] size in
            self?.resizeTranslationWindow(to: size)
        }).id(UUID()))
        hosting.sizingOptions = []
        window?.contentViewController = hosting
        presentTranslationWindow()
        if window?.isVisible != true {
            window?.contentViewController = nil
            window = makeTranslationPanel()
            window?.contentViewController = hosting
            presentTranslationWindow()
        }
    }

    private func makeTranslationPanel() -> TranslationPanel {
        let panel = TranslationPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 410), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "啾译"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.center()
        return panel
    }

    private func applyPin(_ pinned: Bool) {
        guard let panel = window as? NSPanel else { return }
        panel.isFloatingPanel = pinned
        // isFloatingPanel restores the NSPanel default of hiding on deactivate, so clear it afterwards.
        panel.hidesOnDeactivate = false
        panel.level = pinned ? .floating : .normal
        // moveToActiveSpace only follows this app's own activation, so a pinned panel stays
        // behind on the old space once another app's window takes over.
        panel.collectionBehavior = pinned
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.moveToActiveSpace, .fullScreenAuxiliary]
        if pinned {
            panel.orderFrontRegardless()
        }
    }

    private func presentTranslationWindow() {
        guard let window else { return }
        applyPin(translationPinned)
        presentNonActivating(window)
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

if CommandLine.arguments.contains("--self-check") {
    Hotkey.selfCheck()
    DockIconVisibility.selfCheck()
    print("hotkey self-check OK")
    exit(0)
}

let application = NSApplication.shared
let showDockIcon = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
application.setActivationPolicy(DockIconVisibility.activationPolicy(visible: showDockIcon))
let delegate = AppDelegate()
application.delegate = delegate
application.run()
