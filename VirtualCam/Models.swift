import Foundation
import CoreImage

// MARK: - Settings
struct BackgroundSettings: Codable, Equatable {
    var skinSmoothingAmount: Double = 0.0
    var brightness: Double = 0.0
    var contrast: Double = 1.0
    var saturation: Double = 1.0
    var warmth: Double = 0.0
    var sharpness: Double = 0.0
    var backgroundPreset: BackgroundPreset = .none
    var customBackgroundImage: CIImage? = nil
    var included1BackgroundImage: CIImage? = nil
    var included2BackgroundImage: CIImage? = nil
    var included3BackgroundImage: CIImage? = nil
    var mirrorVideo: Bool = true
    
    static var `default`: BackgroundSettings {
        return BackgroundSettings()
    }
    
    init(backgroundPreset: BackgroundPreset = .none) {
        self.backgroundPreset = backgroundPreset
    }
    
    enum CodingKeys: String, CodingKey {
        case skinSmoothingAmount, brightness, contrast, saturation, warmth, sharpness, backgroundPreset, mirrorVideo
        // Note: CIImage properties are not coded since CIImage is not Codable
    }
    
    static func == (lhs: BackgroundSettings, rhs: BackgroundSettings) -> Bool {
        return lhs.skinSmoothingAmount == rhs.skinSmoothingAmount &&
               lhs.brightness == rhs.brightness &&
               lhs.contrast == rhs.contrast &&
               lhs.saturation == rhs.saturation &&
               lhs.warmth == rhs.warmth &&
               lhs.sharpness == rhs.sharpness &&
               lhs.backgroundPreset == rhs.backgroundPreset &&
               lhs.mirrorVideo == rhs.mirrorVideo
        // Note: We don't compare CIImage properties since CIImage doesn't conform to Equatable
    }
}

// MARK: - Background Types
enum BackgroundPreset: String, Codable {
    case none
    case lightBlur
    case blur
    case custom
    case included1
    case included2
    case included3
    
    var name: String {
        switch self {
        case .none:
            return "None"
        case .lightBlur:
            return "Light Blur"
        case .blur:
            return "Strong Blur"
        case .custom:
            return "Custom"
        case .included1:
            return "Background 1"
        case .included2:
            return "Background 2"
        case .included3:
            return "Background 3"
        }
    }
    
    var iconSystemName: String {
        switch self {
        case .none:
            return "camera.filters"
        case .lightBlur:
            return "camera.filters.wheel"
        case .blur:
            return "circle.circle.fill"
        case .custom:
            return "photo.fill"
        case .included1, .included2, .included3:
            return "photo.fill"
        }
    }
}

// MARK: - Preset
struct Preset: Codable, Equatable {
    let name: String
    let type: BackgroundPreset
    var settings: BackgroundSettings
    var imagePath: String?
    
    init(name: String, type: BackgroundPreset, settings: BackgroundSettings, imagePath: String? = nil) {
        self.name = name
        self.type = type
        self.settings = settings
        self.imagePath = imagePath
    }
    
    static func == (lhs: Preset, rhs: Preset) -> Bool {
        return lhs.name == rhs.name &&
               lhs.type == rhs.type &&
               lhs.settings == rhs.settings &&
               lhs.imagePath == rhs.imagePath
    }
}
