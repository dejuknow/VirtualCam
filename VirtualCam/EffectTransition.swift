import Foundation
import CoreImage

class EffectTransition {
    private var startSettings: BackgroundSettings
    private var endSettings: BackgroundSettings
    private var progress: Double = 0.0
    private var duration: TimeInterval
    private var startTime: Date?
    
    init(from startSettings: BackgroundSettings, to endSettings: BackgroundSettings, duration: TimeInterval = 0.3) {
        self.startSettings = startSettings
        self.endSettings = endSettings
        self.duration = duration
    }
    
    func start() {
        startTime = Date()
    }
    
    func getCurrentSettings() -> BackgroundSettings {
        guard let startTime = startTime else { return endSettings }
        
        let elapsed = Date().timeIntervalSince(startTime)
        progress = min(1.0, elapsed / duration)
        
        if progress >= 1.0 {
            return endSettings
        }
        
        // Interpolate between settings
        var currentSettings = BackgroundSettings()
        currentSettings = interpolateSettings(startSettings, endSettings, progress: Float(progress))
        
        // For background preset, we don't interpolate - we switch at the midpoint
        if progress < 0.5 {
            currentSettings.backgroundPreset = startSettings.backgroundPreset
            currentSettings.customBackgroundImage = startSettings.customBackgroundImage
        } else {
            currentSettings.backgroundPreset = endSettings.backgroundPreset
            currentSettings.customBackgroundImage = endSettings.customBackgroundImage
        }
        
        return currentSettings
    }
    
    private func interpolateSettings(_ settings1: BackgroundSettings, _ settings2: BackgroundSettings, progress: Float) -> BackgroundSettings {
        var result = BackgroundSettings()
        result.brightness = lerp(settings1.brightness, settings2.brightness, progress: Double(progress))
        result.contrast = lerp(settings1.contrast, settings2.contrast, progress: Double(progress))
        result.saturation = lerp(settings1.saturation, settings2.saturation, progress: Double(progress))
        result.warmth = lerp(settings1.warmth, settings2.warmth, progress: Double(progress))
        result.sharpness = lerp(settings1.sharpness, settings2.sharpness, progress: Double(progress))
        result.skinSmoothingAmount = lerp(settings1.skinSmoothingAmount, settings2.skinSmoothingAmount, progress: Double(progress))
        return result
    }
    
    private func lerp(_ start: Double, _ end: Double, progress: Double) -> Double {
        return start + (end - start) * progress
    }
    
    var isComplete: Bool {
        guard let startTime = startTime else { return false }
        return Date().timeIntervalSince(startTime) >= duration
    }
}
