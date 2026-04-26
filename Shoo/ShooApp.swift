import SwiftUI
import ApplicationServices
import Combine
import Foundation

// MARK: - Enums

enum ActionType: String, CaseIterable {
    case close = "Close Window"
    case quit = "Quit App"
}

enum TrafficLightButton {
    case close
    case minimize
}

enum WindowAction {
    case close
    case minimize
    case quit
}

// MARK: - App Entry

@main
struct ShooApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    @AppStorage("defaultClickAction") private var defaultClickAction: ActionType = .close

    var body: some Scene {
        MenuBarExtra("Shoo", systemImage: appState.isEnabled ? "eye" : "eye.slash") {
            Button(appState.isEnabled ? "Disable Shoo" : "Enable Shoo") {
                appState.isEnabled.toggle()
            }
            
            Divider()
            
            Picker("Default Red Button Action", selection: $defaultClickAction) {
                ForEach(ActionType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(MenuPickerStyle())
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        OnboardingManager.shared.checkPermissionOnLaunch()
    }
}

// MARK: - Private API

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: inout CGWindowID) -> AXError

// MARK: - Window Info

class WindowInfo: ObservableObject, Identifiable {
    let id: CGWindowID
    let pid: pid_t
    @Published var bounds: CGRect
    let title: String
    
    @Published var isHoveringWindow: Bool = false
    @Published var hoveredButton: TrafficLightButton? = nil

    init(id: CGWindowID, pid: pid_t, bounds: CGRect, title: String) {
        self.id = id
        self.pid = pid
        self.bounds = bounds
        self.title = title
    }
}

// MARK: - App State

class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
                hideAllOverlays()
            }
        }
    }

    private var timer: Timer?
    private var overlayControllers: [CGWindowID: OverlayWindowController] = [:]
    private var cachedAXWindows: [CGWindowID: AXUIElement] = [:]

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventTapRetryCount = 0
    private let maxRetries = 10
    private var isHandlingPermissionLoss = false

    private var globalClickMonitor: Any?
    private var globalMoveMonitor: Any?
    
    // UI Constants
    let buttonSize: CGFloat = 14
    let buttonPadding: CGFloat = 8
    let buttonSpacing: CGFloat = 8

    func requestPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        print("[Shoo] Accessibility trusted: \(trusted)")
    }

    func startMonitoring() {
        print("[Shoo] Starting monitoring...")
        refreshAXCache()
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.tick()
        }
        attemptEventTapSetup()
    }

    func stopMonitoring() {
        print("[Shoo] Stopping monitoring...")
        timer?.invalidate()
        timer = nil
        removeEventTap()
        removeGlobalMonitors()
        cachedAXWindows.removeAll()
    }

    private func tick() {
        // If accessibility was revoked externally, stop immediately
        if !AXIsProcessTrusted() {
            handlePermissionLoss()
            return
        }
        let isMC = isMissionControlActive()
        if !isMC {
            refreshAXCache()
            hideAllOverlays()
        } else {
            updateOverlays()
        }
    }

    private func isMissionControlActive() -> Bool {
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return false }

        for info in windowInfoList {
            if let owner = info[kCGWindowOwnerName as String] as? String, owner == "Dock",
               let layer = info[kCGWindowLayer as String] as? Int, layer == 18 {
                return true
            }
        }
        return false
    }

    private func refreshAXCache() {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        for app in apps {
            let pid = app.processIdentifier
            if pid == ProcessInfo.processInfo.processIdentifier { continue }

            let appElement = AXUIElementCreateApplication(pid)
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
               let axWindows = value as? [AXUIElement] {
                for axWindow in axWindows {
                    var winId: CGWindowID = 0
                    if _AXUIElementGetWindow(axWindow, &winId) == .success && winId != 0 {
                        cachedAXWindows[winId] = axWindow
                    }
                }
            }
        }
    }

    private func updateOverlays() {
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return }

        var currentWindows = Set<CGWindowID>()
        let myPid = ProcessInfo.processInfo.processIdentifier
        let dockPid = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == "com.apple.dock" })?.processIdentifier ?? 0

        for info in windowInfoList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let ownerPid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any] else {
                continue
            }

            if ownerPid == myPid || ownerPid == dockPid { continue }

            let rect = CGRect(
                x: boundsDict["X"] as? CGFloat ?? 0,
                y: boundsDict["Y"] as? CGFloat ?? 0,
                width: boundsDict["Width"] as? CGFloat ?? 0,
                height: boundsDict["Height"] as? CGFloat ?? 0
            )

            if rect.width < 50 || rect.height < 50 { continue }
            currentWindows.insert(windowID)

            if let controller = overlayControllers[windowID] {
                controller.windowInfo.bounds = rect
                controller.update(bounds: rect)
            } else {
                let title = info[kCGWindowName as String] as? String ?? ""
                let wInfo = WindowInfo(id: windowID, pid: ownerPid, bounds: rect, title: title)
                let controller = OverlayWindowController(windowInfo: wInfo, appState: self)
                overlayControllers[windowID] = controller
                controller.update(bounds: rect)
            }
        }

        let staleIDs = overlayControllers.keys.filter { !currentWindows.contains($0) }
        for id in staleIDs {
            overlayControllers[id]?.close()
            overlayControllers.removeValue(forKey: id)
        }
    }

    func hideAllOverlays() {
        guard !overlayControllers.isEmpty else { return }
        for controller in overlayControllers.values {
            controller.close()
        }
        overlayControllers.removeAll()
    }

    // MARK: - Event Tap

    private func attemptEventTapSetup() {
        eventTapRetryCount = 0
        tryCreateEventTap()
    }

    private func tryCreateEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.mouseMoved.rawValue)
            | (1 << CGEventType.keyDown.rawValue)

        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let appState = Unmanaged<AppState>.fromOpaque(refcon).takeUnretainedValue()
                return appState.handleCGEvent(event: event, type: type)
            },
            userInfo: observer
        )

        if eventTap == nil {
            eventTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: eventMask,
                callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                    guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                    let appState = Unmanaged<AppState>.fromOpaque(refcon).takeUnretainedValue()
                    return appState.handleCGEvent(event: event, type: type)
                },
                userInfo: observer
            )
        }

        if let tap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            if let source = runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        } else {
            eventTapRetryCount += 1
            if eventTapRetryCount <= maxRetries {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.tryCreateEventTap()
                }
            } else {
                setupGlobalMonitors()
            }
        }
    }

    private func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
    }

    private func handleCGEvent(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout {
            // Only re-enable if we still have accessibility permissions.
            // Without this check, revoking permissions causes a tight
            // disable → re-enable → disable loop that freezes the system.
            if AXIsProcessTrusted(), let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                // Permissions were revoked — handle gracefully
                handlePermissionLoss()
            }
            return Unmanaged.passRetained(event)
        }
        if type == .tapDisabledByUserInput {
            // The system disabled our event tap (usually due to permission revocation).
            // We MUST NOT modify the event tap or run loop source from inside this
            // callback — doing so deadlocks the main thread. Instead, schedule
            // cleanup on the next run loop iteration.
            handlePermissionLoss()
            return Unmanaged.passRetained(event)
        }
        guard !overlayControllers.isEmpty else { return Unmanaged.passRetained(event) }

        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let isCmdDown = event.flags.contains(.maskCommand)
            if isCmdDown {
                let hoveredWindow = overlayControllers.values.first(where: { $0.windowInfo.isHoveringWindow })?.windowInfo
                if let target = hoveredWindow {
                    if keyCode == 12 { // Cmd + Q
                        DispatchQueue.main.async { self.performAction(.quit, on: target) }
                        return nil
                    } else if keyCode == 13 { // Cmd + W
                        DispatchQueue.main.async { self.performAction(.close, on: target) }
                        return nil
                    } else if keyCode == 46 { // Cmd + M
                        DispatchQueue.main.async { self.performAction(.minimize, on: target) }
                        return nil
                    }
                }
            }
            return Unmanaged.passRetained(event)
        }

        let loc = event.location

        if type == .mouseMoved {
            updateHoverState(at: loc)
            return Unmanaged.passRetained(event)
        }

        if type == .leftMouseDown {
            if let hitResult = findHitTarget(at: loc) {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if hitResult.button == .minimize {
                        self.performAction(.minimize, on: hitResult.window)
                    } else if hitResult.button == .close {
                        let defaultAction = UserDefaults.standard.string(forKey: "defaultClickAction") ?? ActionType.close.rawValue
                        self.performAction(defaultAction == ActionType.quit.rawValue ? .quit : .close, on: hitResult.window)
                    }
                }
                return nil
            }
        }

        return Unmanaged.passRetained(event)
    }

    /// Safely handles permission revocation without deadlocking.
    /// This can be called from inside the event tap callback, so all
    /// actual cleanup is deferred to the next run loop iteration.
    private func handlePermissionLoss() {
        guard !isHandlingPermissionLoss else { return }
        isHandlingPermissionLoss = true
        
        // Schedule cleanup on the NEXT run loop iteration.
        // This is critical: we cannot modify the event tap or its run loop
        // source while we are inside the event tap callback, or we deadlock.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Double-check: maybe permissions were restored in the meantime
            if AXIsProcessTrusted() {
                // Re-enable the tap if permissions came back
                if let tap = self.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                self.isHandlingPermissionLoss = false
                return
            }
            
            // Permissions truly revoked — stop everything gracefully
            self.isEnabled = false
            self.isHandlingPermissionLoss = false
            OnboardingManager.shared.show()
        }
    }

    private func setupGlobalMonitors() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            if let loc = CGEvent(source: nil)?.location, let target = self?.findHitTarget(at: loc) {
                if target.button == .minimize {
                    self?.performAction(.minimize, on: target.window)
                } else if target.button == .close {
                    let defaultAction = UserDefaults.standard.string(forKey: "defaultClickAction") ?? ActionType.close.rawValue
                    self?.performAction(defaultAction == ActionType.quit.rawValue ? .quit : .close, on: target.window)
                }
            }
        }
        globalMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            if let loc = CGEvent(source: nil)?.location { self?.updateHoverState(at: loc) }
        }
    }

    private func removeGlobalMonitors() {
        if let m = globalClickMonitor { NSEvent.removeMonitor(m); globalClickMonitor = nil }
        if let m = globalMoveMonitor { NSEvent.removeMonitor(m); globalMoveMonitor = nil }
    }

    // MARK: - Hit Testing & Hover State

    private func updateHoverState(at point: CGPoint) {
        for controller in overlayControllers.values {
            let info = controller.windowInfo
            let isWinHovered = info.bounds.contains(point)
            
            let closeRect = CGRect(x: info.bounds.origin.x + buttonPadding, y: info.bounds.origin.y + buttonPadding, width: buttonSize, height: buttonSize)
            let minRect = CGRect(x: info.bounds.origin.x + buttonPadding + buttonSize + buttonSpacing, y: info.bounds.origin.y + buttonPadding, width: buttonSize, height: buttonSize)
            
            var hoveredBtn: TrafficLightButton? = nil
            if closeRect.contains(point) { hoveredBtn = .close }
            else if minRect.contains(point) { hoveredBtn = .minimize }
            
            if info.isHoveringWindow != isWinHovered || info.hoveredButton != hoveredBtn {
                DispatchQueue.main.async {
                    info.isHoveringWindow = isWinHovered
                    info.hoveredButton = hoveredBtn
                }
            }
        }
    }

    private func findHitTarget(at point: CGPoint) -> (window: WindowInfo, button: TrafficLightButton)? {
        for controller in overlayControllers.values {
            let info = controller.windowInfo
            let closeRect = CGRect(x: info.bounds.origin.x + buttonPadding, y: info.bounds.origin.y + buttonPadding, width: buttonSize, height: buttonSize)
            let minRect = CGRect(x: info.bounds.origin.x + buttonPadding + buttonSize + buttonSpacing, y: info.bounds.origin.y + buttonPadding, width: buttonSize, height: buttonSize)
            
            if closeRect.contains(point) { return (info, .close) }
            if minRect.contains(point) { return (info, .minimize) }
        }
        return nil
    }

    // MARK: - Actions

    private func performAction(_ action: WindowAction, on windowInfo: WindowInfo) {
        print("[Shoo] Performing action \(action) on window \(windowInfo.id) (pid \(windowInfo.pid))")
        
        switch action {
        case .quit:
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == windowInfo.pid }) {
                app.terminate()
                print("[Shoo] ✅ Terminated app \(windowInfo.pid)")
                removeOverlay(for: windowInfo.id)
            } else {
                print("[Shoo] ❌ Could not find NSRunningApplication for pid \(windowInfo.pid)")
            }
            
        case .minimize:
            if let axWindow = getAXWindow(for: windowInfo) {
                let err = AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, true as CFTypeRef)
                if err == .success {
                    print("[Shoo] ✅ Minimized window \(windowInfo.id)")
                    removeOverlay(for: windowInfo.id)
                } else {
                    print("[Shoo] ❌ Failed to minimize: \(err.rawValue)")
                }
            }
            
        case .close:
            if let axWindow = getAXWindow(for: windowInfo) {
                var closeBtnValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(axWindow, kAXCloseButtonAttribute as CFString, &closeBtnValue) == .success {
                    let closeBtn = closeBtnValue as! AXUIElement
                    let err = AXUIElementPerformAction(closeBtn, kAXPressAction as CFString)
                    if err == .success {
                        print("[Shoo] ✅ Closed window \(windowInfo.id)")
                        removeOverlay(for: windowInfo.id)
                    } else {
                        print("[Shoo] ❌ Failed to press close button: \(err.rawValue)")
                    }
                }
            }
        }
    }
    
    private func getAXWindow(for windowInfo: WindowInfo) -> AXUIElement? {
        if let cached = cachedAXWindows[windowInfo.id] { return cached }
        let appElement = AXUIElementCreateApplication(windowInfo.pid)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
           let windows = value as? [AXUIElement] {
            for axWindow in windows {
                var winId: CGWindowID = 0
                if _AXUIElementGetWindow(axWindow, &winId) == .success && winId == windowInfo.id {
                    return axWindow
                }
            }
        }
        return nil
    }
    
    private func removeOverlay(for id: CGWindowID) {
        overlayControllers[id]?.close()
        overlayControllers.removeValue(forKey: id)
        cachedAXWindows.removeValue(forKey: id)
    }
}

// MARK: - Overlay Window Controller

class OverlayWindowController {
    let window: NSPanel
    let windowInfo: WindowInfo
    private weak var appState: AppState?

    init(windowInfo: WindowInfo, appState: AppState) {
        self.windowInfo = windowInfo
        self.appState = appState
        self.window = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        self.window.isOpaque = false
        self.window.backgroundColor = .clear
        self.window.level = .screenSaver
        self.window.ignoresMouseEvents = true
        self.window.hasShadow = false
        self.window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let view = TrafficLightGroupView(windowInfo: windowInfo)
        self.window.contentView = NSHostingView(rootView: view)
    }

    func update(bounds: CGRect) {
        guard let screen = NSScreen.screens.first, let appState = appState else { return }
        let screenHeight = screen.frame.height

        let totalWidth = (appState.buttonSize * 2) + appState.buttonSpacing
        let flippedY = screenHeight - bounds.origin.y - appState.buttonSize - appState.buttonPadding
        let x = bounds.origin.x + appState.buttonPadding

        let rect = NSRect(x: x, y: flippedY, width: totalWidth, height: appState.buttonSize)

        if self.window.frame != rect {
            self.window.setFrame(rect, display: true)
        }

        if !self.window.isVisible {
            self.window.orderFront(nil)
        }
    }

    func close() {
        self.window.close()
    }
}

// MARK: - UI Views

struct TrafficLightGroupView: View {
    @ObservedObject var windowInfo: WindowInfo

    var body: some View {
        HStack(spacing: 8) {
            TrafficLightButtonView(
                type: .close,
                isHovered: windowInfo.hoveredButton == .close,
                showSymbols: windowInfo.hoveredButton != nil
            )
            TrafficLightButtonView(
                type: .minimize,
                isHovered: windowInfo.hoveredButton == .minimize,
                showSymbols: windowInfo.hoveredButton != nil
            )
        }
        .opacity(windowInfo.isHoveringWindow ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: windowInfo.isHoveringWindow)
    }
}

struct TrafficLightButtonView: View {
    let type: TrafficLightButton
    let isHovered: Bool
    let showSymbols: Bool
    
    var color: Color {
        switch type {
        case .close: return isHovered ? Color(red: 1.0, green: 0.37, blue: 0.34) : Color(red: 1.0, green: 0.37, blue: 0.36)
        case .minimize: return isHovered ? Color(red: 1.0, green: 0.74, blue: 0.18) : Color(red: 1.0, green: 0.74, blue: 0.27)
        }
    }
    
    var symbol: String {
        switch type {
        case .close: return "xmark"
        case .minimize: return "minus"
        }
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 14, height: 14)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
                )

            if showSymbols {
                Image(systemName: symbol)
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundColor(Color.black.opacity(0.6))
            }
        }
    }
}
import SwiftUI
import ApplicationServices

enum OnboardingState {
    case welcome
    case waiting
    case done
}

class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()
    
    @Published var state: OnboardingState = .welcome
    private var timer: Timer?
    private var window: NSWindow?
    
    func checkPermissionOnLaunch() {
        if !AXIsProcessTrusted() {
            show()
        } else {
            // Automatically enable if trusted on launch
            AppState.shared.isEnabled = true
        }
    }
    
    func show() {
        if AXIsProcessTrusted() {
            state = .done
        } else {
            state = .welcome
        }
        
        if window == nil {
            let view = OnboardingView().environmentObject(self)
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 350),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window?.isReleasedWhenClosed = false
            window?.titlebarAppearsTransparent = true
            window?.titleVisibility = .hidden
            window?.isMovableByWindowBackground = true
            window?.contentView = NSHostingView(rootView: view)
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func closeWindow() {
        window?.close()
        window = nil
        timer?.invalidate()
    }
    
    func openSettings() {
        // First try the specific Accessibility pane
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        
        state = .waiting
        startPolling()
    }
    
    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            if AXIsProcessTrusted() {
                self?.timer?.invalidate()
                self?.timer = nil
                DispatchQueue.main.async {
                    self?.state = .done
                    AppState.shared.isEnabled = true
                }
            }
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject var manager: OnboardingManager
    
    var body: some View {
        VStack {
            switch manager.state {
            case .welcome:
                WelcomeView()
            case .waiting:
                WaitingView()
            case .done:
                DoneView()
            }
        }
        .frame(width: 450, height: 350)
    }
}

struct WelcomeView: View {
    @EnvironmentObject var manager: OnboardingManager
    
    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .frame(width: 64, height: 64)
            
            Text("Accessibility Access Required")
                .font(.system(size: 24, weight: .bold))
            
            Text("Shoo requires Accessibility permissions to interact with window controls in Mission Control.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "1.circle.fill").foregroundColor(.secondary)
                    Text("Click **Open System Settings** below.")
                }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "2.circle.fill").foregroundColor(.secondary)
                    Text("Turn on the switch next to **Shoo**.")
                }
            }
            .padding(.vertical, 16)
            
            Spacer()
            
            HStack {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Open System Settings") {
                    manager.openSettings()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
    }
}

struct WaitingView: View {
    @EnvironmentObject var manager: OnboardingManager
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.2)
                .padding(.bottom, 8)
            
            Text("Waiting for Permission")
                .font(.system(size: 24, weight: .bold))
            
            Text("Please enable the switch for Shoo in System Settings.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
            
            Spacer()
            
            HStack {
                Button("Check Manually") {
                    manager.startPolling()
                }
                
                Spacer()
                
                Button("Open System Settings") {
                    manager.openSettings()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
    }
}

struct DoneView: View {
    @EnvironmentObject var manager: OnboardingManager
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .frame(width: 64, height: 64)
                .foregroundColor(.green)
            
            Text("You're All Set!")
                .font(.system(size: 24, weight: .bold))
            
            Text("Shoo now has the required permissions and is ready to use.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
            
            Spacer()
            
            Button("Get Started") {
                manager.closeWindow()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(32)
    }
}
