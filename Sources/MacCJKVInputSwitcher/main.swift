import Foundation
import AppKit
import Carbon.HIToolbox

private let signature = OSType(0x4D495357) // MISW
private let hotKeyKey = "hotKey"

struct HotKey: Codable, Equatable {
    var keyCode: Int
    var modifiers: UInt32

    static let `default` = HotKey(
        keyCode: Int(kVK_Space),
        modifiers: UInt32(controlKey | optionKey | shiftKey)
    )

    var displayName: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    static func keyName(for keyCode: Int) -> String {
        let names: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab",
            kVK_Delete: "Delete", kVK_Escape: "Esc", kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
        ]
        if let name = names[keyCode] { return name }
        return "Key \(keyCode)"
    }
}

final class HotKeyStore {
    static let shared = HotKeyStore()
    private let defaults = UserDefaults.standard

    var hotKey: HotKey {
        get {
            guard let data = defaults.data(forKey: hotKeyKey),
                  let value = try? JSONDecoder().decode(HotKey.self, from: data) else { return .default }
            return value
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { defaults.set(data, forKey: hotKeyKey) }
        }
    }
}

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

final class InputSourceSwitcher {
    let inputSources: [String]
    var currentIndex: Int
    private var rebindWindow: NSWindow?
    private var previousApplication: NSRunningApplication?
    private var transitionInProgress = false

    init() {
        let sources = loadInputSources()
        inputSources = sources
        currentIndex = currentInputSourceID().flatMap { sources.firstIndex(of: $0) } ?? -1
    }

    func selectNextInputSource() {
        guard !inputSources.isEmpty, !transitionInProgress else { return }
        if let current = currentInputSourceID(), let index = inputSources.firstIndex(of: current) { currentIndex = index }
        let nextIndex = (currentIndex + 1) % inputSources.count
        let nextSource = inputSources[nextIndex]
        currentIndex = nextIndex

        let needsWorkaround = isCJKV(nextSource)
        transitionInProgress = needsWorkaround
        if needsWorkaround { rebindInputContext() }

        func attempt(_ remaining: Int) {
            self.selectInputSource(nextSource)
            if currentInputSourceID() != nextSource && remaining > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) { attempt(remaining - 1) }
                return
            }
            self.rebindWindow?.orderOut(nil)
            self.previousApplication?.activate(options: [])
            self.previousApplication = nil
            self.transitionInProgress = false
        }
        if needsWorkaround {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) { attempt(2) }
        } else { attempt(0) }
    }

    private func selectInputSource(_ id: String) {
        let properties = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let unmanaged = TISCreateInputSourceList(properties, false),
              let sources = unmanaged.takeRetainedValue() as? [TISInputSource],
              let source = sources.first else { return }
        let status = TISSelectInputSource(source)
        if status != noErr { fputs("TISSelectInputSource failed: \(status)\n", stderr) }
    }

    private func rebindInputContext() {
        previousApplication = NSWorkspace.shared.frontmostApplication
        if rebindWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.alphaValue = 0.01
            window.level = .floating
            rebindWindow = window
        }
        rebindWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class HotKeyManager {
    private(set) var hotKey: HotKey
    private var eventHotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onTriggered: (() -> Void)?
    var onChanged: ((HotKey) -> Void)?

    init() {
        hotKey = HotKeyStore.shared.hotKey
        installHandler()
        register()
    }

    deinit { unregister() }

    func update(_ newValue: HotKey) {
        unregister()
        hotKey = newValue
        HotKeyStore.shared.hotKey = newValue
        register()
        onChanged?(newValue)
    }

    private func installHandler() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == signature, id.id == 1 else { return noErr }
            hotKeyManager?.onTriggered?()
            return noErr
        }, 1, &eventSpec, nil, &handler)
        if status != noErr { fputs("InstallEventHandler failed: \(status)\n", stderr) }
    }

    private func register() {
        let id = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(UInt32(hotKey.keyCode), hotKey.modifiers, id, GetApplicationEventTarget(), 0, &eventHotKey)
        if status != noErr { fputs("RegisterEventHotKey failed: \(status)\n", stderr) }
    }

    private func unregister() {
        if let eventHotKey { UnregisterEventHotKey(eventHotKey); self.eventHotKey = nil }
    }
}

private var hotKeyManager: HotKeyManager?

final class SettingsWindowController: NSWindowController {
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let recordButton = NSButton(title: "단축키 변경", target: nil, action: nil)
    private var monitor: Any?
    private var isRecording = false

    init(hotKey: HotKey) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 180), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Mac CJKV Input Switcher 설정"
        window.center()
        super.init(window: window)
        recordButton.target = self
        recordButton.action = #selector(toggleRecording)
        shortcutLabel.stringValue = hotKey.displayName
        shortcutLabel.font = .monospacedSystemFont(ofSize: 20, weight: .medium)
        shortcutLabel.alignment = .center
        shortcutLabel.wantsLayer = true
        shortcutLabel.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        shortcutLabel.layer?.cornerRadius = 6

        let description = NSTextField(labelWithString: "전역 단축키")
        let hint = NSTextField(wrappingLabelWithString: "원하는 키 조합을 누르면 저장됩니다. 최소 한 개의 보조 키(⌃, ⌥, ⇧, ⌘)를 포함하세요.")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 12)

        let stack = NSStackView(views: [description, shortcutLabel, recordButton, hint])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22),
            shortcutLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            shortcutLabel.heightAnchor.constraint(equalToConstant: 34)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func windowDidLoad() {
        super.windowDidLoad()
        window?.delegate = self
    }

    @objc private func toggleRecording() {
        isRecording.toggle()
        recordButton.title = isRecording ? "키를 누르세요…" : "단축키 변경"
        if isRecording {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        installMonitorIfNeeded()
    }

    private func installMonitorIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else { return event }
            let flags = event.modifierFlags
            let modifiers = Self.carbonModifiers(from: flags)
            guard modifiers != 0 else { NSSound.beep(); return nil }
            let value = HotKey(keyCode: Int(event.keyCode), modifiers: modifiers)
            hotKeyManager?.update(value)
            self.shortcutLabel.stringValue = value.displayName
            self.isRecording = false
            self.recordButton.title = "단축키 변경"
            return nil
        }
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        isRecording = false
        recordButton.title = "단축키 변경"
    }
}


final class LoginItemManager {
    static let shared = LoginItemManager()
    private let label = "com.winetree.MacCJKVInputSwitcher"
    private let fileManager = FileManager.default

    private var launchAgentsDirectory: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    private var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(label).plist")
    }

    private var legacyBinaryURL: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/MacCJKVInputSwitcher")
    }

    func installIfNeeded() {
        let appPath = Bundle.main.bundlePath
        guard appPath.hasSuffix(".app") else { return }
        do {
            try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
            try migrateLegacyInstallation()
            try writePlist(appPath: appPath)
            _ = runLaunchctl(["bootout", "gui/\(getuid())", plistURL.path])
            _ = runLaunchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
        } catch {
            NSLog("Failed to install login item: \(error.localizedDescription)")
        }
    }

    func uninstall() {
        _ = runLaunchctl(["bootout", "gui/\(getuid())", plistURL.path])
        try? fileManager.removeItem(at: plistURL)
    }

    private func migrateLegacyInstallation() throws {
        guard fileManager.fileExists(atPath: plistURL.path),
              let data = try? Data(contentsOf: plistURL),
              let text = String(data: data, encoding: .utf8),
              text.contains("__INSTALL_PATH__") || text.contains(legacyBinaryURL.path) else { return }
        _ = runLaunchctl(["bootout", "gui/\(getuid())", plistURL.path])
        try? fileManager.removeItem(at: plistURL)
        try? fileManager.removeItem(at: legacyBinaryURL)
    }

    private func writePlist(appPath: String) throws {
        let logURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MacCJKVInputSwitcher.log")
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["\(appPath)/Contents/MacOS/MacCJKVInputSwitcher"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Interactive",
            "StandardOutPath": logURL.path,
            "StandardErrorPath": logURL.path
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
    }

    @discardableResult
    private func runLaunchctl(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsController: SettingsWindowController?
    private let switcher = InputSourceSwitcher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        LoginItemManager.shared.installIfNeeded()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "character.cursor.ibeam", accessibilityDescription: "입력기 전환")
            button.toolTip = "입력기 전환"
        }
        buildMenu()

        hotKeyManager = HotKeyManager()
        hotKeyManager?.onTriggered = { [weak self] in self?.switcher.selectNextInputSource() }
        hotKeyManager?.onChanged = { [weak self] _ in self?.buildMenu() }
    }

    private func buildMenu() {
        let menu = NSMenu()
        let hotKeyTitle = HotKeyStore.shared.hotKey.displayName
        let switchItem = NSMenuItem(title: "입력기 전환 (\(hotKeyTitle))", action: #selector(triggerSwitch), keyEquivalent: "")
        switchItem.target = self
        menu.addItem(switchItem)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "설정…", action: #selector(showSettings), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "종료", action: #selector(quit), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func triggerSwitch() { switcher.selectNextInputSource() }

    @objc private func showSettings() {
        if settingsController == nil { settingsController = SettingsWindowController(hotKey: HotKeyStore.shared.hotKey) }
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        LoginItemManager.shared.uninstall()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
