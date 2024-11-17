import Cocoa
import AVFoundation
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, CameraManagerDelegate, NSWindowDelegate {
    private var cameraManager: CameraManager!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Initialize camera manager first
        cameraManager = CameraManager()
        
        // Show settings window on launch
        showSettings()
    }
    
    private func updateCurrentPresetSettings(_ update: (inout BackgroundSettings) -> Void) {
        if var settings = cameraManager.currentSettings {
            update(&settings)
            cameraManager.updateSettings(settings)
        }
    }
    
    @objc private func brightnessChanged(_ sender: NSSlider) {
        updateCurrentPresetSettings { settings in
            settings.brightness = sender.doubleValue
        }
    }
    
    @objc private func contrastChanged(_ sender: NSSlider) {
        updateCurrentPresetSettings { settings in
            settings.contrast = sender.doubleValue
        }
    }
    
    @objc private func saturationChanged(_ sender: NSSlider) {
        updateCurrentPresetSettings { settings in
            settings.saturation = sender.doubleValue
        }
    }
    
    @objc private func warmthChanged(_ sender: NSSlider) {
        updateCurrentPresetSettings { settings in
            settings.warmth = sender.doubleValue
        }
    }
    
    @objc private func sharpnessChanged(_ sender: NSSlider) {
        updateCurrentPresetSettings { settings in
            settings.sharpness = sender.doubleValue
        }
    }
    
    @objc private func touchUpChanged(_ sender: NSSlider) {
        updateCurrentPresetSettings { settings in
            settings.skinSmoothingAmount = sender.doubleValue
        }
    }
    
    @objc private func resetAppearance() {
        // Create default settings
        let defaultSettings = BackgroundSettings()
        
        // Update the camera with default settings
        cameraManager.updateSettings(defaultSettings)
        
        // Reset all sliders in the menu to their default values
    }
    
    private func updateSliders(with settings: BackgroundSettings) {
        print("Updating sliders with settings: \(settings)")
        
        DispatchQueue.main.async {
        }
    }
    
    private func addSlider(to menu: NSMenu, title: String, minValue: Double, maxValue: Double, defaultValue: Double, action: Selector) -> NSMenuItem {
        let sliderItem = NSMenuItem()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        
        let label = NSTextField(frame: NSRect(x: 10, y: 20, width: 180, height: 17))
        label.stringValue = title
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.textColor = .labelColor
        container.addSubview(label)
        
        let slider = NSSlider(frame: NSRect(x: 10, y: 0, width: 180, height: 20))
        slider.minValue = minValue
        slider.maxValue = maxValue
        slider.doubleValue = defaultValue
        slider.target = self
        slider.action = action
        container.addSubview(slider)
        
        sliderItem.view = container
        sliderItem.title = title
        return sliderItem
    }
    
    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "VirtualCam Settings"
            window.center()
            window.setFrameAutosaveName("SettingsWindow")
            
            let contentView = SettingsWindow(cameraManager: cameraManager)
            let hostingView = NSHostingView(rootView: contentView)
            window.contentView = hostingView
            window.delegate = self
            
            settingsWindow = window
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow == settingsWindow {
            NSApplication.shared.terminate(nil)
        }
    }
    
    func cameraManager(_ manager: CameraManager, didReceiveError error: Error) {
        let alert = NSAlert()
        alert.messageText = "Camera Error"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
    
    func cameraManagerDidUpdateState(_ manager: CameraManager) {
    }
    
    func cameraManager(_ manager: CameraManager, didChangePreset preset: Preset) {
    }
}
