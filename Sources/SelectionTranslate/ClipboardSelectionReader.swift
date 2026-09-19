import AppKit
import Carbon

struct ClipboardSnapshot {
    let changeCount: Int
    private let items: [NSPasteboardItem]

    init?(_ pasteboard: NSPasteboard) {
        let initialCount = pasteboard.changeCount
        var copies: [NSPasteboardItem] = []
        var totalBytes = 0
        for item in pasteboard.pasteboardItems ?? [] {
            let copy = NSPasteboardItem()
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                totalBytes += data.count
                // Skip the fallback when the clipboard cannot be safely backed up.
                guard totalBytes <= 8 * 1024 * 1024 else { return nil }
                guard copy.setData(data, forType: type) else { return nil }
            }
            copies.append(copy)
        }
        guard pasteboard.changeCount == initialCount else { return nil }
        changeCount = initialCount
        items = copies
    }

    @discardableResult
    func restore(to pasteboard: NSPasteboard, ifUnchangedSince count: Int) -> Bool {
        guard pasteboard.changeCount == count else { return false }
        pasteboard.clearContents()
        return items.isEmpty || pasteboard.writeObjects(items)
    }
}

enum ClipboardSelectionReader {
    enum Result {
        case text(String)
        case unavailable
        case cancelled
    }

    @MainActor
    static func read(from source: NSRunningApplication) async -> Result {
        guard source.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return .unavailable }
        let pasteboard = NSPasteboard.general
        // Do not send Command-C while Option from the translation shortcut is held.
        for _ in 0..<40 {
            guard source.isActive, !Task.isCancelled else { return .cancelled }
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection([.maskAlternate, .maskControl, .maskShift, .maskCommand]).isEmpty { break }
            do { try await Task.sleep(for: .milliseconds(25)) } catch { return .cancelled }
        }
        guard CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskAlternate, .maskControl, .maskShift, .maskCommand]).isEmpty else { return .cancelled }
        guard source.isActive, let snapshot = ClipboardSnapshot(pasteboard),
              let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false) else { return .unavailable }
        guard source.isActive, pasteboard.changeCount == snapshot.changeCount else { return .cancelled }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(source.processIdentifier)
        up.postToPid(source.processIdentifier)

        for _ in 0..<40 {
            do { try await Task.sleep(for: .milliseconds(25)) } catch { return .cancelled }
            let newCount = pasteboard.changeCount
            if newCount != snapshot.changeCount {
                // Never restore over a later copy or use the old clipboard as selected text.
                guard source.isActive, !Task.isCancelled else { return .cancelled }
                let selected = pasteboard.string(forType: .string)
                guard pasteboard.changeCount == newCount else { return .cancelled }
                snapshot.restore(to: pasteboard, ifUnchangedSince: newCount)
                guard let selected, !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .unavailable }
                return .text(selected)
            }
            guard source.isActive, !Task.isCancelled else { return .cancelled }
        }
        return .unavailable
    }
}
