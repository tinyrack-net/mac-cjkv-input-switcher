import Foundation
import AppKit
import Carbon.HIToolbox

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

private func isCJKV(_ id: String) -> Bool {
    let properties = [kTISPropertyInputSourceID as String: id] as CFDictionary
    guard let list = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource],
          let source = list.first,
          let pointer = TISGetInputSourceProperty(source, "InputModeID" as CFString) else { return false }
    return (Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String).isEmpty == false
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

registerHotKey(kVK_Space, id: 1, ref: &koreanHotKey)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.run()
