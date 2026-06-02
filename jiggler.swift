import Cocoa
import CoreGraphics
import IOKit.ps
import IOKit.pwr_mgt

class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - State Management
    var isJiggling = false
    var timer: Timer?
    var batteryTimer: Timer?
    var assertionID: IOPMAssertionID = 0
    var hasAssertion = false
    
    // Status Bar Item
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    
    // Menu references for dynamic updates
    var toggleItem: NSMenuItem?
    var intervalMenu: NSMenu?
    var styleMenu: NSMenu?
    var smartMenu: NSMenu?
    var powerMenu: NSMenuItem?
    var launchItem: NSMenuItem?

    // UserDefaults Keys
    let kIntervalKey = "JigglerInterval"
    let kStyleKey = "JigglerStyle"
    let kIdleOnlyKey = "JigglerIdleOnly"
    let kIdleTimeoutKey = "JigglerIdleTimeout"
    let kBatteryGuardKey = "JigglerBatteryGuard"

    // MARK: - App Lifecycle
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Initialize UserDefaults Defaults
        UserDefaults.standard.register(defaults: [
            kIntervalKey: 30.0,
            kStyleKey: "subtle",
            kIdleOnlyKey: false,
            kIdleTimeoutKey: 60.0,
            kBatteryGuardKey: true
        ])
        
        setupStatusBar()
        setupNotificationObservers()
        
        // Start battery monitoring timer (runs every 60 seconds)
        batteryTimer = Timer.scheduledTimer(timeInterval: 60.0, target: self, selector: #selector(checkBatteryGuard), userInfo: nil, repeats: true)
        
        // Initial battery check
        checkBatteryGuard()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        releaseSleepAssertion()
        timer?.invalidate()
        batteryTimer?.invalidate()
    }

    // MARK: - Notification Observers (Sleep/Wake)
    private func setupNotificationObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc func systemWillSleep() {
        // Pause active timers and assertions during system sleep to be resource-friendly
        if isJiggling {
            stopJiggleTimer()
            releaseSleepAssertion()
        }
    }

    @objc func systemDidWake() {
        if isJiggling {
            startJiggleTimer()
            acquireSleepAssertionIfNeeded()
        }
    }

    // MARK: - Status Bar & Menu Setup
    private func setupStatusBar() {
        updateStatusBarButton()
        
        let menu = NSMenu()
        
        // 1. Main Toggle
        toggleItem = NSMenuItem(title: "Toggle Jiggler (OFF)", action: #selector(toggleJiggler), keyEquivalent: "t")
        menu.addItem(toggleItem!)
        menu.addItem(NSMenuItem.separator())
        
        // 2. Interval Submenu
        let intervalMenuItem = NSMenuItem(title: "Jiggle Interval", action: nil, keyEquivalent: "")
        let iMenu = NSMenu()
        let intervals: [(String, Double)] = [
            ("10 Seconds", 10.0),
            ("30 Seconds", 30.0),
            ("1 Minute", 60.0),
            ("5 Minutes", 300.0),
            ("10 Minutes", 600.0)
        ]
        for (title, duration) in intervals {
            let item = NSMenuItem(title: title, action: #selector(changeInterval(_:)), keyEquivalent: "")
            item.representedObject = duration
            iMenu.addItem(item)
        }
        intervalMenuItem.submenu = iMenu
        menu.addItem(intervalMenuItem)
        self.intervalMenu = iMenu
        
        // 3. Jiggle Style Submenu
        let styleMenuItem = NSMenuItem(title: "Jiggle Style", action: nil, keyEquivalent: "")
        let sMenu = NSMenu()
        let styles = [
            ("Subtle (1px Shift)", "subtle"),
            ("Random Drift (5px)", "random"),
            ("Prevent Sleep (No Move)", "nomove")
        ]
        for (title, value) in styles {
            let item = NSMenuItem(title: title, action: #selector(changeStyle(_:)), keyEquivalent: "")
            item.representedObject = value
            sMenu.addItem(item)
        }
        styleMenuItem.submenu = sMenu
        menu.addItem(styleMenuItem)
        self.styleMenu = sMenu
        
        // 4. Smart/Idle Mode Submenu
        let smartMenuItem = NSMenuItem(title: "Smart Activation", action: nil, keyEquivalent: "")
        let smMenu = NSMenu()
        
        let alwaysItem = NSMenuItem(title: "Always Active", action: #selector(setAlwaysActive), keyEquivalent: "")
        smMenu.addItem(alwaysItem)
        
        let idle60Item = NSMenuItem(title: "Only when Idle (1 min)", action: #selector(setIdleActivation(_:)), keyEquivalent: "")
        idle60Item.representedObject = 60.0
        smMenu.addItem(idle60Item)
        
        let idle300Item = NSMenuItem(title: "Only when Idle (5 mins)", action: #selector(setIdleActivation(_:)), keyEquivalent: "")
        idle300Item.representedObject = 300.0
        smMenu.addItem(idle300Item)
        
        smartMenuItem.submenu = smMenu
        menu.addItem(smartMenuItem)
        self.smartMenu = smMenu
        
        // 5. Battery/Power Submenu
        let powerMenuItem = NSMenuItem(title: "Battery Guard (Pause under 20%)", action: #selector(toggleBatteryGuard), keyEquivalent: "")
        menu.addItem(powerMenuItem)
        self.powerMenu = powerMenuItem
        
        // 6. Launch at Login
        launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        menu.addItem(launchItem!)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Jiggler", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
        
        updateMenuCheckmarks()
    }
    
    // MARK: - Menu Actions
    @objc func toggleJiggler() {
        isJiggling.toggle()
        
        if isJiggling {
            // Check battery level first before activating
            if shouldPauseForBattery() {
                isJiggling = false
                showNotification(title: "Jiggler Battery Guard", subtitle: "Battery is too low to run Jiggler.")
                return
            }
            
            updateStatusBarButton()
            toggleItem?.title = "Toggle Jiggler (ON)"
            startJiggleTimer()
            acquireSleepAssertionIfNeeded()
        } else {
            updateStatusBarButton()
            toggleItem?.title = "Toggle Jiggler (OFF)"
            stopJiggleTimer()
            releaseSleepAssertion()
        }
        updateMenuCheckmarks()
    }
    
    @objc func changeInterval(_ sender: NSMenuItem) {
        if let duration = sender.representedObject as? Double {
            UserDefaults.standard.set(duration, forKey: kIntervalKey)
            updateMenuCheckmarks()
            if isJiggling {
                stopJiggleTimer()
                startJiggleTimer()
            }
        }
    }
    
    @objc func changeStyle(_ sender: NSMenuItem) {
        if let style = sender.representedObject as? String {
            UserDefaults.standard.set(style, forKey: kStyleKey)
            updateMenuCheckmarks()
            if isJiggling {
                // If switching styles, re-evaluate assertion requirements
                if style == "nomove" {
                    acquireSleepAssertionIfNeeded()
                } else {
                    releaseSleepAssertion()
                }
            }
        }
    }
    
    @objc func setAlwaysActive() {
        UserDefaults.standard.set(false, forKey: kIdleOnlyKey)
        updateMenuCheckmarks()
    }
    
    @objc func setIdleActivation(_ sender: NSMenuItem) {
        if let timeout = sender.representedObject as? Double {
            UserDefaults.standard.set(true, forKey: kIdleOnlyKey)
            UserDefaults.standard.set(timeout, forKey: kIdleTimeoutKey)
            updateMenuCheckmarks()
        }
    }
    
    @objc func toggleBatteryGuard() {
        let current = UserDefaults.standard.bool(forKey: kBatteryGuardKey)
        UserDefaults.standard.set(!current, forKey: kBatteryGuardKey)
        updateMenuCheckmarks()
        checkBatteryGuard()
    }
    
    @objc func toggleLaunchAtLogin() {
        let current = isLaunchAtLoginEnabled()
        setLaunchAtLogin(enabled: !current)
        updateMenuCheckmarks()
    }
    
    // MARK: - Setup UI Checkmarks
    private func updateMenuCheckmarks() {
        let currentInterval = UserDefaults.standard.double(forKey: kIntervalKey)
        let currentStyle = UserDefaults.standard.string(forKey: kStyleKey) ?? "subtle"
        let isIdleOnly = UserDefaults.standard.bool(forKey: kIdleOnlyKey)
        let currentIdleTimeout = UserDefaults.standard.double(forKey: kIdleTimeoutKey)
        let isBatteryGuardEnabled = UserDefaults.standard.bool(forKey: kBatteryGuardKey)
        
        // 1. Intervals checkmarks
        if let iMenu = intervalMenu {
            for item in iMenu.items {
                if let duration = item.representedObject as? Double {
                    item.state = (duration == currentInterval) ? .on : .off
                }
            }
        }
        
        // 2. Style checkmarks
        if let sMenu = styleMenu {
            for item in sMenu.items {
                if let style = item.representedObject as? String {
                    item.state = (style == currentStyle) ? .on : .off
                }
            }
        }
        
        // 3. Smart Activation checkmarks
        if let smMenu = smartMenu {
            smMenu.items[0].state = !isIdleOnly ? .on : .off // Always Active
            smMenu.items[1].state = (isIdleOnly && currentIdleTimeout == 60.0) ? .on : .off
            smMenu.items[2].state = (isIdleOnly && currentIdleTimeout == 300.0) ? .on : .off
        }
        
        // 4. Battery state checkmark
        powerMenu?.state = isBatteryGuardEnabled ? .on : .off
        
        // 5. Launch at login checkmark
        launchItem?.state = isLaunchAtLoginEnabled() ? .on : .off
    }
    
    // MARK: - Timer Logic
    private func startJiggleTimer() {
        timer?.invalidate()
        let interval = UserDefaults.standard.double(forKey: kIntervalKey)
        timer = Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(jiggleCheckLoop), userInfo: nil, repeats: true)
    }
    
    private func stopJiggleTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - Power Sleep Assertions
    private func acquireSleepAssertionIfNeeded() {
        guard !hasAssertion else { return }
        let currentStyle = UserDefaults.standard.string(forKey: kStyleKey) ?? "subtle"
        
        // The "nomove" style disables sleeping purely via API assertions rather than mouse moves
        if currentStyle == "nomove" {
            let reason = "Jiggler No-Move Mode Active" as CFString
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &assertionID
            )
            if result == kIOReturnSuccess {
                hasAssertion = true
            }
        }
    }
    
    private func releaseSleepAssertion() {
        if hasAssertion {
            IOPMAssertionRelease(assertionID)
            hasAssertion = false
        }
    }
    
    // MARK: - Jiggle Core Loop
    @objc func jiggleCheckLoop() {
        guard isJiggling else { return }
        
        // 1. Smart Idle Check
        let isIdleOnly = UserDefaults.standard.bool(forKey: kIdleOnlyKey)
        if isIdleOnly {
            if let idleTime = getSystemIdleTime() {
                let requiredTimeout = UserDefaults.standard.double(forKey: kIdleTimeoutKey)
                if idleTime < requiredTimeout {
                    // System is not idle yet, skip jiggle
                    return
                }
            }
        }
        
        // 2. Perform style-dependent action
        let currentStyle = UserDefaults.standard.string(forKey: kStyleKey) ?? "subtle"
        
        if currentStyle == "nomove" {
            // Already handled via native Power Assertions
            return
        }
        
        // For subtle and random drift:
        guard let event = CGEvent(source: nil) else { return }
        let loc = event.location
        
        var deltaX: CGFloat = 1.0
        var deltaY: CGFloat = 0.0
        
        if currentStyle == "random" {
            deltaX = CGFloat(Int.random(in: -5...5))
            deltaY = CGFloat(Int.random(in: -5...5))
            // Ensure we actually moved somewhere
            if deltaX == 0 && deltaY == 0 {
                deltaX = 2.0
            }
        }
        
        let newLoc = CGPoint(x: loc.x + deltaX, y: loc.y + deltaY)
        
        // Dispatch mouse move
        if let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: newLoc, mouseButton: .left) {
            moveEvent.post(tap: .cghidEventTap)
        }
        
        // Snap back after 0.1 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let backEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: loc, mouseButton: .left) {
                backEvent.post(tap: .cghidEventTap)
            }
        }
    }
    
    // MARK: - Battery Safety Guard
    @objc func checkBatteryGuard() {
        if shouldPauseForBattery() {
            if isJiggling {
                // Pause it
                toggleJiggler()
                updateStatusBarButton()
                showNotification(title: "Jiggler Paused", subtitle: "Battery guard paused jiggling to save power (< 20%).")
            }
        }
    }
    
    private func shouldPauseForBattery() -> Bool {
        let isBatteryGuardEnabled = UserDefaults.standard.bool(forKey: kBatteryGuardKey)
        guard isBatteryGuardEnabled else { return false }
        
        if let status = getBatteryStatus() {
            if status.isDischarging && status.percentage <= 20 {
                return true
            }
        }
        return false
    }

    // MARK: - API Helpers
    private func getSystemIdleTime() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        if service == 0 { return nil }
        defer { IOObjectRelease(service) }
        
        var properties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
        if result != KERN_SUCCESS || properties == nil { return nil }
        
        let dict = properties!.takeRetainedValue() as NSDictionary
        if let idleTimeNanoseconds = dict["HIDIdleTime"] as? NSNumber {
            return idleTimeNanoseconds.doubleValue / 1_000_000_000.0
        }
        return nil
    }
    
    private func getBatteryStatus() -> (percentage: Int, isDischarging: Bool)? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }
        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        
        for source in sources {
            if let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
                let isPresent = description[kIOPSIsPresentKey] as? Bool ?? false
                if isPresent {
                    let capacity = description[kIOPSCurrentCapacityKey] as? Int ?? 0
                    let powerState = description[kIOPSPowerSourceStateKey] as? String ?? ""
                    let discharging = (powerState == kIOPSBatteryPowerValue)
                    return (capacity, discharging)
                }
            }
        }
        return nil
    }

    private func showNotification(title: String, subtitle: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.subtitle = subtitle
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }

    // MARK: - Custom Menu Bar Icon Helpers
    private func updateStatusBarButton() {
        guard let button = statusItem.button else { return }
        let shouldWarn = shouldPauseForBattery()
        
        if shouldWarn {
            button.image = getMenuIcon(active: false, warning: true)
            button.title = "⚠️"
            button.imagePosition = .imageLeft
        } else {
            button.image = getMenuIcon(active: isJiggling)
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    private func getMenuIcon(active: Bool, warning: Bool = false) -> NSImage? {
        let size = NSSize(width: 18, height: 18)
        let icon = NSImage(size: size)
        icon.isTemplate = true // Force macOS to render the icon in pure white on dark/blue wallpapers
        
        let drawBlock = {
            icon.lockFocus()
            
            // Clean outer circle matching the logo basis
            let circlePath = NSBezierPath(ovalIn: NSRect(x: 2.0, y: 2.0, width: 14.0, height: 14.0))
            circlePath.lineWidth = 1.5
            
            // Bold, mathematically symmetric NW-pointing pointer that fills the circle beautifully
            let pointerPath = NSBezierPath()
            pointerPath.move(to: NSPoint(x: 4.5, y: 13.5))        // Tip (pointing NW, perfectly symmetric)
            pointerPath.line(to: NSPoint(x: 13.5, y: 9.5))       // Right wing tip
            pointerPath.line(to: NSPoint(x: 10.0, y: 8.0))        // Inner indent
            pointerPath.line(to: NSPoint(x: 8.5, y: 4.5))        // Left wing tip
            pointerPath.close()
            
            // Draw using solid black as the template mask color
            if warning {
                // If warning, we can stroke circle thicker or just let normal template draw
                NSColor.black.set()
                circlePath.lineWidth = 2.0
                circlePath.stroke()
                pointerPath.fill()
            } else {
                NSColor.black.set()
                circlePath.stroke()
                pointerPath.fill()
                
                if active {
                    // Soft transparent fill inside the circle when running (translates to a gorgeous white glow on dark menubars!)
                    NSColor.black.withAlphaComponent(0.18).set()
                    circlePath.fill()
                }
            }
            
            icon.unlockFocus()
        }
        
        if let buttonAppearance = statusItem.button?.effectiveAppearance {
            buttonAppearance.performAsCurrentDrawingAppearance(drawBlock)
        } else {
            drawBlock()
        }
        
        return icon
    }

    // MARK: - Launch at Login Helper
    private func getExecutablePath() -> String {
        let path = CommandLine.arguments[0]
        if path.hasPrefix("/") {
            return path
        } else {
            let fm = FileManager.default
            let currentDir = fm.currentDirectoryPath
            return URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: currentDir)).path
        }
    }

    private func setLaunchAtLogin(enabled: Bool) {
        let fm = FileManager.default
        let folder = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        let plistURL = folder.appendingPathComponent("com.user.jiggler.plist")
        
        if enabled {
            let execPath = getExecutablePath()
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
            
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.user.jiggler</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(execPath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
            </dict>
            </plist>
            """
            try? plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
        } else {
            try? fm.removeItem(at: plistURL)
        }
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        let fm = FileManager.default
        let folder = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        let plistURL = folder.appendingPathComponent("com.user.jiggler.plist")
        return fm.fileExists(atPath: plistURL.path)
    }
}

// MARK: - Main Entry Point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
