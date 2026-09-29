import Foundation
import AppKit
import Carbon.HIToolbox
import ServiceManagement

private let signature = OSType(0x4D495357) // MISW

private func loadInputSources() -> [String] {
    let properties: [String: Any] = [
        kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any,
        kTISPropertyInputSourceIsSelectCapable as String: true
    ]
    let list = TISCreateInputSourceList(properties as CFDictionary, false)?
        .takeRetainedValue() as? [TISInputSource] ?? []
    return list.compactMap(inputSourceID)
}

private func inputSourceID(_ source: TISInputSource) -> String? {
    guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}

// Some macOS versions expose InputModeID on CJKV input sources and some do not:
// the Korean source on recent versions only reports its language, so both
// signals are used.  The language list matches the check Kawa uses.
private func isCJKV(_ id: String) -> Bool {
    let properties = [kTISPropertyInputSourceID as String: id] as CFDictionary
    guard let list = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource],
          let source = list.first else { return false }
    if let pointer = TISGetInputSourceProperty(source, "InputModeID" as CFString) {
        let mode = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
        if !mode.isEmpty { return true }
    }
    guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return false }
    let languages = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as NSArray
    return languages.compactMap { $0 as? String }.contains { language in
        language == "ko" || language == "ja" || language == "vi" || language.hasPrefix("zh")
    }
}

private func currentInputSourceID() -> String? {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
    return inputSourceID(source)
}

private let inputSources = loadInputSources()
private var currentIndex = currentInputSourceID().flatMap { inputSources.firstIndex(of: $0) } ?? -1

if inputSources.isEmpty {
    fputs("No enabled keyboard input sources found.\n", stderr)
    exit(1)
}

private func selectInputSource(_ id: String) {
    let properties = [kTISPropertyInputSourceID as String: id] as CFDictionary
    guard let unmanaged = TISCreateInputSourceList(properties, false),
          let sources = unmanaged.takeRetainedValue() as? [TISInputSource],
          let source = sources.first else {
        fputs("Input source not found: \(id)\n", stderr)
        return
    }
    let status = TISSelectInputSource(source)
    if status != noErr { fputs("TISSelectInputSource failed: \(status)\n", stderr) }
}

// Selecting a CJKV source can update the menu-bar state without rebinding the
// focused application's input context.  A short-lived key window forces that
// rebinding; the delay also gives the IME time to finish the transition.
private var rebindWindow: NSWindow?
private var previousApplication: NSRunningApplication?
private var transitionInProgress = false

private func rebindInputContext() {
    previousApplication = NSWorkspace.shared.frontmostApplication
    if rebindWindow == nil {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0.01
        window.level = .floating
        rebindWindow = window
    }
    rebindWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}

private func selectNextInputSource() {
    guard !transitionInProgress else { return }
    // Re-read the current source so external changes do not desynchronise the
    // process-local index.
    if let current = currentInputSourceID(), let index = inputSources.firstIndex(of: current) {
        currentIndex = index
    }
    let nextIndex = (currentIndex + 1) % inputSources.count
    let nextSource = inputSources[nextIndex]
    currentIndex = nextIndex

    let needsWorkaround = isCJKV(nextSource)
    transitionInProgress = needsWorkaround
    if needsWorkaround { rebindInputContext() }

    func attempt(_ remaining: Int) {
        selectInputSource(nextSource)
        if currentInputSourceID() != nextSource && remaining > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) { attempt(remaining - 1) }
            return
        }
        rebindWindow?.orderOut(nil)
        previousApplication?.activate(options: [])
        previousApplication = nil
        transitionInProgress = false
    }
    if needsWorkaround {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) { attempt(2) }
    } else {
        attempt(0)
    }
}

private func registerHotKey(_ keyCode: Int, id: UInt32, ref: inout EventHotKeyRef?) {
    let hotKeyID = EventHotKeyID(signature: signature, id: id)
    let status = RegisterEventHotKey(
        UInt32(keyCode), UInt32(controlKey | optionKey | shiftKey), hotKeyID,
        GetApplicationEventTarget(), 0, &ref)
    if status != noErr { fputs("RegisterEventHotKey failed: \(status)\n", stderr); exit(1) }
}

final class SettingsController: NSObject {
    private var window: NSWindow?
    func show() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 150))
        let title = NSTextField(labelWithString: "Mac CJKV Input Switcher 설정")
        title.font = .boldSystemFont(ofSize: 15)
        let button = NSButton(checkboxWithTitle: "로그인 시 자동으로 시작", target: self, action: #selector(autoStartChanged(_:)))
        button.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let help = NSTextField(wrappingLabelWithString: "앱을 /Applications에 설치한 뒤 활성화하면 Mac에 로그인할 때 메뉴 막대 앱이 자동으로 실행됩니다.")
        help.textColor = .secondaryLabelColor
        help.font = .systemFont(ofSize: 12)
        let stack = NSStackView(views: [title, button, help])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14; stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24)])
        let window = NSWindow(contentRect: content.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "설정"; window.contentView = content; window.isReleasedWhenClosed = false; window.center(); self.window = window
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func autoStartChanged(_ sender: NSButton) {
        do { if sender.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { sender.state = SMAppService.mainApp.status == .enabled ? .on : .off; let alert = NSAlert(); alert.messageText = "자동 시작 설정을 변경할 수 없습니다"; alert.informativeText = error.localizedDescription; alert.runModal() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsController()
    private var statusItem: NSStatusItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength); statusItem.button?.title = "⌨︎"
        let menu = NSMenu(); let settingsItem = NSMenuItem(title: "설정…", action: #selector(showSettings), keyEquivalent: ","); settingsItem.target = self; menu.addItem(settingsItem); menu.addItem(.separator()); let quitItem = NSMenuItem(title: "종료", action: #selector(quit), keyEquivalent: "q"); quitItem.target = self; menu.addItem(quitItem); statusItem.menu = menu
    }
    @objc private func showSettings() { settings.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}

var koreanHotKey: EventHotKeyRef?
var handler: EventHandlerRef?
var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
    var id = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
    guard status == noErr else { return status }
    if id.id == 1 { selectNextInputSource() }
    return noErr
}, 1, &eventSpec, nil, &handler)
if handlerStatus != noErr { fputs("InstallEventHandler failed: \(handlerStatus)\n", stderr); exit(1) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
registerHotKey(kVK_Space, id: 1, ref: &koreanHotKey)
app.run()
