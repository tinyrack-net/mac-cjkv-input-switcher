import Foundation
import AppKit
import Carbon.HIToolbox
import ApplicationServices

private let signature = OSType(0x4D495357) // MISW

// Common non-CJKV keyboard layouts, tried in order before falling back to the
// first non-CJKV source in the enabled list.  The workaround below needs a
// plain layout to step through, so ABC/U.S. is the natural candidate.
private let preferredNonCJKVInputSources = [
    "com.apple.keylayout.ABC",
    "com.apple.keylayout.US"
]

// The "Select the previous input source" symbolic hotkey (id 60) and the
// hotkey this program registers itself.  They must not overlap, otherwise the
// synthesized key event would re-enter our own handler.
private let selectPreviousInputSourceHotKeyID = 60
private let ownHotKey = (keyCode: CGKeyCode(kVK_Space), modifiers: controlKey | optionKey | shiftKey)

private func log(_ message: String) {
    fputs("\(message)\n", stderr)
}

// Posting the input source shortcut needs Accessibility permission.  The value
// AXIsProcessTrusted() reports is not always accurate for a job started by
// launchd, so it only decides whether to ask for the permission: whether the
// shortcut really works is judged by the result of the switch itself.
private var accessibilityPromptRequested = false

private func requestAccessibilityPermissionIfNeeded() {
    if AXIsProcessTrusted() { return }
    guard !accessibilityPromptRequested else { return }
    accessibilityPromptRequested = true
    log("Accessibility permission is not granted for this process.")
    log("Grant it in System Settings > Privacy & Security > Accessibility, then restart this tool.")
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
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
    stringProperty(source, kTISPropertyInputSourceID)
}

private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}

private func inputSource(withID id: String) -> TISInputSource? {
    let properties = [kTISPropertyInputSourceID as String: id] as CFDictionary
    let list = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource]
    return list?.first
}

private func inputSourceLanguages(_ source: TISInputSource) -> [String] {
    guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return [] }
    let languages = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as NSArray
    return languages.compactMap { $0 as? String }
}

// CJKV detection has to survive two shapes of the same input source: some
// macOS versions expose InputModeID, and the Korean/Japanese sources on recent
// versions expose nothing but their language.  Both signals are used, with the
// language list matching the approach Kawa uses.
private func isCJKV(_ id: String) -> Bool {
    guard let source = inputSource(withID: id) else { return false }
    if let mode = stringProperty(source, "InputModeID" as CFString), !mode.isEmpty { return true }
    return inputSourceLanguages(source).contains { language in
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

// A non-CJKV source that the workaround can step through on the way to the
// target.  Without one the macOS bug cannot be worked around, so the old
// forced-rebind path is used instead.
private var nonCJKVInputSourceID: String? {
    for preferred in preferredNonCJKVInputSources where inputSources.contains(preferred) {
        return preferred
    }
    return inputSources.first { !isCJKV($0) }
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

// MARK: - "Select the previous input source" shortcut

// Reads the shortcut the user actually configured in System Settings >
// Keyboard > Keyboard Shortcuts > Input Sources instead of assuming the
// factory default (Control-Space), which is frequently rebound.
private func selectPreviousInputSourceShortcut() -> (keyCode: CGKeyCode, flags: CGEventFlags)? {
    guard let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
          let hotKeys = domain["AppleSymbolicHotKeys"] as? [String: Any],
          let entry = hotKeys[String(selectPreviousInputSourceHotKeyID)] as? [String: Any],
          (entry["enabled"] as? NSNumber)?.boolValue == true,
          let value = entry["value"] as? [String: Any],
          let parameters = value["parameters"] as? [NSNumber],
          parameters.count >= 3 else { return nil }
    return (CGKeyCode(parameters[1].intValue), CGEventFlags(rawValue: parameters[2].uint64Value))
}

private func postSelectPreviousInputSourceShortcut() {
    guard let shortcut = selectPreviousInputSourceShortcut() else { return }
    let source = CGEventSource(stateID: .hidSystemState)
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false) else {
        log("Could not create the input source switch key event")
        return
    }
    down.flags = shortcut.flags
    up.flags = shortcut.flags
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}

// A synthesized event must never look like this program's own hotkey, or the
// key press would come straight back into selectNextInputSource().
private func isOwnHotKey(_ shortcut: (keyCode: CGKeyCode, flags: CGEventFlags)) -> Bool {
    guard shortcut.keyCode == ownHotKey.keyCode else { return false }
    let required = CGEventFlags(rawValue: UInt64(ownHotKey.modifiers))
    return shortcut.flags.intersection(required) == required
}

// MARK: - Input source transition

// Selecting a CJKV source can update the menu-bar state without rebinding the
// focused application's input context, so the menu bar and the text that is
// actually typed disagree.  Two mechanisms are available:
//
// 1. The Kawa/Karabiner workaround: point the input source state at the target,
//    step to a non-CJKV source, then let macOS itself return to the target by
//    posting the "Select the previous input source" shortcut.  The final switch
//    goes through the normal event path, so the focused app does rebind.
// 2. Forcing the rebind with a short-lived key window, then retrying the direct
//    switch.  Kept as a fallback for when no shortcut/non-CJKV source exists.
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

private func finishTransition() {
    rebindWindow?.orderOut(nil)
    previousApplication?.activate(options: [])
    previousApplication = nil
    transitionInProgress = false
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

    transitionInProgress = true
    if isCJKV(nextSource) {
        selectCJKVInputSource(nextSource)
    } else {
        selectInputSource(nextSource)
        finishTransition()
    }
}

private func selectCJKVInputSource(_ target: String) {
    requestAccessibilityPermissionIfNeeded()
    guard workaroundFailures < workaroundFailureLimit else {
        forceSelectInputSource(target)
        return
    }
    guard let intermediate = nonCJKVInputSourceID,
          let shortcut = selectPreviousInputSourceShortcut(),
          !isOwnHotKey(shortcut) else {
        log("Workaround unavailable; forcing an input context rebind for \(target)")
        forceSelectInputSource(target)
        return
    }
    performWorkaroundSelection(target, intermediate: intermediate, attemptsRemaining: 1)
}

// Consecutive failures stop the attempt so a machine without the permission
// does not pay the extra delay on every switch.
private let workaroundFailureLimit = 3
private var workaroundFailures = 0

// TISSelectInputSource sometimes fails to switch CJKV input sources; only the
// menu bar changes.  Selecting the target first makes macOS record it as the
// previous source, and the shortcut then returns to it through the reliable
// native switch.
private func performWorkaroundSelection(_ target: String, intermediate: String, attemptsRemaining: Int) {
    selectInputSource(target)
    selectInputSource(intermediate)
    postSelectPreviousInputSourceShortcut()
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) {
        if currentInputSourceID() == target {
            log("Switched to \(target) through the input source shortcut workaround")
            workaroundFailures = 0
            finishTransition()
            return
        }
        if attemptsRemaining > 0 {
            performWorkaroundSelection(target, intermediate: intermediate, attemptsRemaining: attemptsRemaining - 1)
            return
        }
        workaroundFailures += 1
        log("Workaround did not reach \(target) (input source shortcut \(AXIsProcessTrusted() ? "allowed" : "blocked"), failure \(workaroundFailures)/\(workaroundFailureLimit)); rebinding the input context")
        if workaroundFailures >= workaroundFailureLimit {
            log("Stopping the input source shortcut workaround for this session")
        }
        forceSelectInputSource(target)
    }
}

private func forceSelectInputSource(_ target: String, rebindDelay: Int = 150, attemptsRemaining: Int = 2) {
    rebindInputContext()
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(rebindDelay)) {
        selectInputSource(target)
        if currentInputSourceID() == target || attemptsRemaining == 0 {
            finishTransition()
            return
        }
        forceSelectInputSource(target, rebindDelay: rebindDelay, attemptsRemaining: attemptsRemaining - 1)
    }
}

private func registerHotKey(_ keyCode: Int, id: UInt32, ref: inout EventHotKeyRef?) {
    let hotKeyID = EventHotKeyID(signature: signature, id: id)
    let status = RegisterEventHotKey(
        UInt32(keyCode), UInt32(controlKey | optionKey | shiftKey), hotKeyID,
        GetApplicationEventTarget(), 0, &ref)
    if status != noErr { fputs("RegisterEventHotKey failed: \(status)\n", stderr); exit(1) }
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

private func logConfiguration() {
    log("Input sources:")
    for id in inputSources {
        log("  \(id)\(isCJKV(id) ? " (CJKV)" : "")")
    }
    log("Current input source: \(currentInputSourceID() ?? "unknown")")
    log("Workaround intermediate source: \(nonCJKVInputSourceID ?? "none")")
    if let shortcut = selectPreviousInputSourceShortcut() {
        log("Previous input source shortcut: keyCode \(shortcut.keyCode), flags \(shortcut.flags.rawValue)")
    } else {
        log("Previous input source shortcut: not enabled")
    }
    log("Accessibility permission: \(AXIsProcessTrusted() ? "granted" : "not granted")")
}

// `--diagnose` prints what the workaround would use on this machine without
// registering the hotkey or switching anything, which is handy when the tool
// runs somewhere that is only reachable through screen sharing.
if CommandLine.arguments.contains("--diagnose") {
    logConfiguration()
    exit(0)
}

registerHotKey(kVK_Space, id: 1, ref: &koreanHotKey)
logConfiguration()

// Lets a remote session switch the input source without a keyboard, which is
// useful when only an SSH connection is available:
//   kill -USR1 $(pgrep MacCJKVInputSwitcher)
signal(SIGUSR1, SIG_IGN)
let signalSource = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
signalSource.setEventHandler { selectNextInputSource() }
signalSource.resume()

// Reports the permission this process actually has, which is the value that
// decides whether the switch shortcut can be posted:
//   kill -USR2 $(pgrep MacCJKVInputSwitcher)
signal(SIGUSR2, SIG_IGN)
let stateSignalSource = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
stateSignalSource.setEventHandler {
    log("Accessibility permission: \(AXIsProcessTrusted() ? "granted" : "not granted")")
    log("Current input source: \(currentInputSourceID() ?? "unknown")")
}
stateSignalSource.resume()

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.run()
