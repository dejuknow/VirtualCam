import Foundation

struct CameraSource: Identifiable, Codable, Equatable {
    let id: String  // Unique device ID
    let name: String
    var priority: Int
    
    static func == (lhs: CameraSource, rhs: CameraSource) -> Bool {
        return lhs.id == rhs.id
    }
}

class CameraSourcePreferences {
    static let shared = CameraSourcePreferences()
    private let userDefaults = UserDefaults.standard
    private let sourcesKey = "CameraSourcePreferences"
    
    var sources: [CameraSource] {
        get {
            guard let data = userDefaults.data(forKey: sourcesKey),
                  let sources = try? JSONDecoder().decode([CameraSource].self, from: data) else {
                return []
            }
            return sources.sorted { $0.priority < $1.priority }
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                userDefaults.set(data, forKey: sourcesKey)
            }
        }
    }
    
    func updatePriorities(_ sources: [CameraSource]) {
        var updatedSources = sources
        for (index, var source) in sources.enumerated() {
            source.priority = index
            updatedSources[index] = source
        }
        self.sources = updatedSources
    }
}
