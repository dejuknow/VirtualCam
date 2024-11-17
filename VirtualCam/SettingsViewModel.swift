import SwiftUI
import Combine

class SettingsViewModel: ObservableObject {
    @Published var settings: BackgroundSettings
    @Published var selectedPreset: Preset
    let cameraManager: CameraManager
    private var cancellables = Set<AnyCancellable>()
    
    init(cameraManager: CameraManager) {
        self.cameraManager = cameraManager
        self.settings = cameraManager.currentSettings ?? BackgroundSettings()
        self.selectedPreset = cameraManager.currentPreset
        
        // Update settings when they change in CameraManager
        NotificationCenter.default.publisher(for: .settingsChanged)
            .sink { [weak self] notification in
                if let settings = notification.object as? BackgroundSettings {
                    self?.settings = settings
                }
            }
            .store(in: &cancellables)
            
        // Update preset when it changes in CameraManager
        NotificationCenter.default.publisher(for: .presetChanged)
            .sink { [weak self] notification in
                if let preset = notification.object as? Preset {
                    self?.selectedPreset = preset
                }
            }
            .store(in: &cancellables)
    }
    
    func updateSettings() {
        cameraManager.updateSettings(settings)
    }
    
    func setPreset(_ preset: Preset) {
        cameraManager.setPreset(preset)
    }
}
