import Foundation

class PresetManager {
    static let shared = PresetManager()
    private let userDefaultsKey = "SavedPresets"
    private(set) var presets: [Preset]
    
    private init() {
        let defaultPresets = [
            Preset(name: "No Effect", type: .none, settings: BackgroundSettings()),
            Preset(name: "Slight Blur", type: .blur, settings: {
                var settings = BackgroundSettings()
                settings.skinSmoothingAmount = 0.3
                return settings
            }()),
            Preset(name: "Strong Blur", type: .blur, settings: {
                var settings = BackgroundSettings()
                settings.skinSmoothingAmount = 0.3
                settings.brightness = 0.1
                settings.contrast = 1.1
                settings.saturation = 1.1
                return settings
            }())
        ]
        
        if let savedPresets = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([Preset].self, from: savedPresets) {
            presets = decoded
        } else {
            presets = defaultPresets
            savePresets()
        }
    }
    
    func addPreset(_ preset: Preset) {
        presets.append(preset)
        savePresets()
    }
    
    func updatePreset(at index: Int, with preset: Preset) {
        guard index < presets.count else { return }
        presets[index] = preset
        savePresets()
    }
    
    func removePreset(at index: Int) {
        guard index < presets.count else { return }
        presets.remove(at: index)
        savePresets()
    }
    
    private func savePresets() {
        if let encoded = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
}
