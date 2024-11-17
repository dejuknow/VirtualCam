import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var cameraManager: CameraManager
    @State private var settings: BackgroundSettings
    
    init(cameraManager: CameraManager) {
        self.cameraManager = cameraManager
        _settings = State(initialValue: cameraManager.backgroundProcessor.currentSettings ?? BackgroundSettings())
    }
    
    var body: some View {
        Form {
            GroupBox(label: Text("Camera Settings")) {
                VStack(alignment: .leading, spacing: 12) {
                    CameraSourceSettingsView(cameraManager: cameraManager)
                    
                    Divider()
                    
                    Toggle(isOn: Binding(
                        get: { settings.mirrorVideo },
                        set: { newValue in
                            settings.mirrorVideo = newValue
                            cameraManager.backgroundProcessor.updateSettings(settings)
                        }
                    )) {
                        Text("Mirror my video")
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Skin Smoothing")
                            .font(.body)
                        Slider(
                            value: Binding(
                                get: { settings.skinSmoothingAmount },
                                set: { newValue in
                                    settings.skinSmoothingAmount = newValue
                                    cameraManager.backgroundProcessor.updateSettings(settings)
                                }
                            ),
                            in: 0...1
                        ) {
                            Text("Skin Smoothing")
                        }
                    }
                }
            }
        }
        .padding()
    }
}
