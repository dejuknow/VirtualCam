import SwiftUI
import AVKit

struct CameraSourceSettingsView: View {
    @ObservedObject var cameraManager: CameraManager
    @State private var sources: [CameraSource]
    @State private var availableSources: [AVCaptureDevice]
    @State private var draggedItem: CameraSource?
    
    init(cameraManager: CameraManager) {
        self.cameraManager = cameraManager
        self._sources = State(initialValue: CameraSourcePreferences.shared.sources)
        
        let savedSources = CameraSourcePreferences.shared.sources
        let deviceTypes: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            deviceTypes = [.builtInWideAngleCamera, .external]
        } else {
            deviceTypes = [.builtInWideAngleCamera, .externalUnknown]
        }
        
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        ).devices
        
        // Initialize with saved priorities or create new entries
        var newSources: [CameraSource] = []
        for (index, device) in devices.enumerated() {
            if let existing = savedSources.first(where: { $0.id == device.uniqueID }) {
                newSources.append(existing)
            } else {
                newSources.append(CameraSource(
                    id: device.uniqueID,
                    name: device.localizedName,
                    priority: index
                ))
            }
        }
        
        _sources = State(initialValue: newSources.sorted { $0.priority < $1.priority })
        _availableSources = State(initialValue: devices)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Camera Sources")
                .font(.headline)
            
            Text("Drag to reorder camera priority")
                .font(.caption)
                .foregroundColor(.secondary)
            
            List {
                ForEach(sources) { source in
                    HStack {
                        Image(systemName: "video.fill")
                            .foregroundColor(statusColor(for: source))
                        
                        VStack(alignment: .leading) {
                            Text(source.name)
                            Text(statusText(for: source))
                                .font(.caption)
                                .foregroundColor(statusColor(for: source))
                        }
                        
                        Spacer()
                        
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(.gray)
                            .help("Drag to reorder")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let status = cameraManager.deviceStatuses[source.id],
                           status == .available {
                            cameraManager.switchToCamera(withID: source.id)
                        }
                    }
                    .onDrag {
                        self.draggedItem = source
                        return NSItemProvider(object: source.id as NSString)
                    }
                    .onDrop(of: [.text], delegate: CameraSourceDropDelegate(item: source, items: $sources, draggedItem: $draggedItem))
                }
            }
            .listStyle(PlainListStyle())
            .frame(minHeight: 100)
        }
        .padding()
        .onReceive(cameraManager.objectWillChange) { _ in
            // Update sources when camera manager changes
            sources = CameraSourcePreferences.shared.sources.sorted { $0.priority < $1.priority }
        }
    }
    
    private func statusColor(for source: CameraSource) -> Color {
        guard let status = cameraManager.deviceStatuses[source.id] else {
            return .gray
        }
        
        switch status {
        case .active:
            return .blue
        case .available:
            return .gray
        case .inUseByAnotherApp:
            return .orange
        case .unavailable, .disconnected:
            return .red
        }
    }
    
    private func statusText(for source: CameraSource) -> String {
        guard let status = cameraManager.deviceStatuses[source.id] else {
            return "Unknown"
        }
        
        switch status {
        case .active:
            return "Active"
        case .available:
            return "Available"
        case .inUseByAnotherApp:
            return "In Use"
        case .unavailable:
            return "Unavailable"
        case .disconnected:
            return "Disconnected"
        }
    }
}

struct CameraSourceDropDelegate: DropDelegate {
    let item: CameraSource
    @Binding var items: [CameraSource]
    @Binding var draggedItem: CameraSource?
    
    func dropEntered(info: DropInfo) {
        guard let draggedItem = self.draggedItem else { return }
        guard draggedItem != item else { return }
        
        if let from = items.firstIndex(of: draggedItem),
           let to = items.firstIndex(of: item) {
            if items[to] != draggedItem {
                withAnimation {
                    items.move(fromOffsets: IndexSet(integer: from),
                             toOffset: to > from ? to + 1 : to)
                }
            }
        }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        // Update priorities after drop
        for (index, source) in items.enumerated() {
            var updatedSource = source
            updatedSource.priority = index
            if let sourceIndex = items.firstIndex(of: source) {
                items[sourceIndex] = updatedSource
            }
        }
        
        // Save to preferences
        CameraSourcePreferences.shared.sources = items
        
        draggedItem = nil
        return true
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}
