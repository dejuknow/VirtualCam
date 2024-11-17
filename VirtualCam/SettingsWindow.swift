import SwiftUI
import AVFoundation

struct SidebarLabel: View {
    let title: String
    let systemImage: String
    let color: Color
    
    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .font(.system(size: 16))
                .frame(width: 24, height: 24)
        }
    }
}

struct SettingsWindow: View {
    @StateObject private var viewModel: SettingsViewModel
    @State private var selectedSection = "General"
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private let sections = ["General", "Background", "Enhancement", "Presets"]
    
    init(cameraManager: CameraManager) {
        _viewModel = StateObject(wrappedValue: SettingsViewModel(cameraManager: cameraManager))
    }
    
    var body: some View {
        NavigationSplitView(sidebar: {
            // Sidebar
            List(sections, id: \.self, selection: $selectedSection) { section in
                NavigationLink(value: section) {
                    sidebarItem(for: section)
                }
            }
            .navigationTitle("Settings")
            .listStyle(.sidebar)
        }, detail: {
            // Content area with vertical layout
            VStack(spacing: 0) {
                // Top: Camera preview
                CameraPreviewView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, minHeight: 540, maxHeight: 540)
                    .background(Color(.windowBackgroundColor))
                
                Divider()
                
                // Bottom: Settings content
                ScrollView {
                    switch selectedSection {
                    case "General":
                        GeneralSettingsView(cameraManager: viewModel.cameraManager)
                    case "Background":
                        BackgroundSettingsView(settings: $viewModel.settings,
                                             preset: $viewModel.selectedPreset,
                                             showingError: $showingError,
                                             errorMessage: $errorMessage)
                    case "Enhancement":
                        EnhancementSettingsView(settings: $viewModel.settings)
                    case "Presets":
                        PresetsView(selectedPreset: $viewModel.selectedPreset)
                    default:
                        GeneralSettingsView(cameraManager: viewModel.cameraManager)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        })
        .frame(minWidth: 800, minHeight: 800)
        .onChange(of: viewModel.settings) { oldValue, newValue in
            viewModel.updateSettings()
        }
        .onChange(of: viewModel.selectedPreset) { oldValue, newValue in
            viewModel.updateSettings()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func sidebarItem(for section: String) -> some View {
        switch section {
        case "General":
            return SidebarLabel(title: section, systemImage: "gearshape.fill", color: .blue)
        case "Background":
            return SidebarLabel(title: section, systemImage: "photo.fill", color: .purple)
        case "Enhancement":
            return SidebarLabel(title: section, systemImage: "wand.and.stars", color: .orange)
        case "Presets":
            return SidebarLabel(title: section, systemImage: "slider.horizontal.3", color: .green)
        default:
            return SidebarLabel(title: section, systemImage: "gearshape.fill", color: .blue)
        }
    }
}

struct BackgroundGalleryItem: View {
    let preset: BackgroundPreset
    let isSelected: Bool
    let image: NSImage?
    
    var body: some View {
        VStack {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.windowBackgroundColor))
                    .frame(width: 100, height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 2)
                    )
                
                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 96, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: preset.iconSystemName)
                        .font(.system(size: 24))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
            }
            
            Text(preset.name)
                .font(.caption)
                .foregroundColor(isSelected ? .primary : .secondary)
        }
    }
}

struct BackgroundSettingsView: View {
    @Binding var settings: BackgroundSettings
    @Binding var preset: Preset
    @Binding var showingError: Bool
    @Binding var errorMessage: String
    @State private var isShowingImagePicker = false
    @State private var customImage: NSImage?
    @State private var includedImages: [BackgroundPreset: NSImage] = [:]
    
    private let presets: [BackgroundPreset] = [
        .none, .lightBlur, .blur, .custom,
        .included1, .included2, .included3
    ]
    
    var body: some View {
        Form {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: [GridItem(.fixed(100))], spacing: 16) {
                        ForEach(presets, id: \.self) { preset in
                            BackgroundGalleryItem(
                                preset: preset,
                                isSelected: settings.backgroundPreset == preset,
                                image: getImageForPreset(preset)
                            )
                            .onTapGesture {
                                settings.backgroundPreset = preset
                                if preset == .custom && settings.customBackgroundImage == nil {
                                    isShowingImagePicker = true
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 100)
            } header: {
                Text("Background")
            }
            
            if settings.backgroundPreset == .custom {
                Section {
                    Button("Choose Different Image...") {
                        isShowingImagePicker = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isShowingImagePicker,
                     allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                if let image = CIImage(contentsOf: url) {
                    settings.customBackgroundImage = image
                    settings.backgroundPreset = .custom
                    
                    // Update preview thumbnail
                    if let nsImage = NSImage(contentsOf: url) {
                        customImage = nsImage
                    }
                    
                    // Create a new preset with the updated image path
                    let updatedPreset = Preset(
                        name: preset.name,
                        type: .custom,
                        settings: settings,
                        imagePath: url.path
                    )
                    preset = updatedPreset
                } else {
                    errorMessage = "Failed to load the selected image"
                    showingError = true
                }
            case .failure(let error):
                errorMessage = "Error selecting image: \(error.localizedDescription)"
                showingError = true
            }
        }
        .onAppear {
            // Load custom image preview if available
            if let path = preset.imagePath,
               let nsImage = NSImage(contentsOf: URL(fileURLWithPath: path)) {
                customImage = nsImage
            }
            
            // TODO: Load included background images when paths are provided
            // This will be updated when background paths are provided
        }
    }
    
    private func getImageForPreset(_ preset: BackgroundPreset) -> NSImage? {
        switch preset {
        case .custom:
            return customImage
        case .included1, .included2, .included3:
            return includedImages[preset]
        default:
            return nil
        }
    }
}

struct EnhancementSettingsView: View {
    @Binding var settings: BackgroundSettings
    
    var body: some View {
        Form {
            Section("Image Adjustments") {
                VStack(alignment: .leading) {
                    Text("Brightness")
                    Slider(value: $settings.brightness, in: -1...1) {
                        Text("Brightness")
                    }
                    
                    Text("Contrast")
                    Slider(value: $settings.contrast, in: 0...2) {
                        Text("Contrast")
                    }
                    
                    Text("Saturation")
                    Slider(value: $settings.saturation, in: 0...2) {
                        Text("Saturation")
                    }
                    
                    Text("Warmth")
                    Slider(value: $settings.warmth, in: -1...1) {
                        Text("Warmth")
                    }
                    
                    Text("Sharpness")
                    Slider(value: $settings.sharpness, in: 0...1) {
                        Text("Sharpness")
                    }
                }
            }
            
            Section {
                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
                        resetToDefaults()
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
            }
        }
    }
    
    private func resetToDefaults() {
        settings.skinSmoothingAmount = 0.0
        settings.brightness = 0.0
        settings.contrast = 1.0
        settings.saturation = 1.0
        settings.warmth = 0.0
    }
}

struct PresetsView: View {
    @Binding var selectedPreset: Preset
    
    var body: some View {
        List {
            Text("Presets coming soon...")
        }
    }
}

struct CameraPreviewView: NSViewRepresentable {
    @ObservedObject var viewModel: SettingsViewModel
    
    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }
    
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        
        // Create a fixed aspect ratio view (16:9)
        let aspectRatio: CGFloat = 16.0 / 9.0
        let previewView = NSView()
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.wantsLayer = true
        container.addSubview(previewView)
        
        // Center the preview view in the container
        NSLayoutConstraint.activate([
            previewView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            previewView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            previewView.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor),
            previewView.heightAnchor.constraint(lessThanOrEqualTo: container.heightAnchor),
            previewView.widthAnchor.constraint(equalTo: previewView.heightAnchor, multiplier: aspectRatio)
        ])
        
        // Add width or height constraint based on container's aspect ratio
        let containerObserver = ContainerObserver(container: container, previewView: previewView, aspectRatio: aspectRatio)
        context.coordinator.containerObserver = containerObserver
        
        // Start the camera if it's not already running
        if !viewModel.cameraManager.isRunning {
            viewModel.cameraManager.startCamera()
        }
        
        // Add the preview layer
        if let previewLayer = viewModel.cameraManager.getPreviewLayer() {
            previewLayer.frame = previewView.bounds
            previewLayer.videoGravity = .resizeAspectFill
            previewView.layer?.addSublayer(previewLayer)
        }
        
        return container
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Only update frame if the preview layer exists
        if let previewLayer = viewModel.cameraManager.getPreviewLayer(),
           let previewView = nsView.subviews.first {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = previewView.bounds
            CATransaction.commit()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var containerObserver: ContainerObserver?
        
        deinit {
            containerObserver = nil
        }
    }
    
    class ContainerObserver {
        private var container: NSView
        private var previewView: NSView
        private var aspectRatio: CGFloat
        private var widthConstraint: NSLayoutConstraint?
        private var heightConstraint: NSLayoutConstraint?
        
        init(container: NSView, previewView: NSView, aspectRatio: CGFloat) {
            self.container = container
            self.previewView = previewView
            self.aspectRatio = aspectRatio
            
            updateConstraints()
            
            // Observe container size changes
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(containerSizeDidChange),
                name: NSView.frameDidChangeNotification,
                object: container
            )
        }
        
        @objc private func containerSizeDidChange() {
            updateConstraints()
        }
        
        private func updateConstraints() {
            // Remove existing constraints
            widthConstraint?.isActive = false
            heightConstraint?.isActive = false
            
            // Calculate new constraints based on container size
            let containerAspectRatio = container.bounds.width / container.bounds.height
            
            if containerAspectRatio > aspectRatio {
                // Container is wider than 16:9, constrain height
                heightConstraint = previewView.heightAnchor.constraint(equalTo: container.heightAnchor)
                heightConstraint?.isActive = true
            } else {
                // Container is taller than 16:9, constrain width
                widthConstraint = previewView.widthAnchor.constraint(equalTo: container.widthAnchor)
                widthConstraint?.isActive = true
            }
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
