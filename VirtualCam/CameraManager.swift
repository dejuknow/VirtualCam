import AVFoundation
import Cocoa
import CoreImage
import Combine

protocol CameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: CameraManager, didReceiveError error: Error)
    func cameraManagerDidUpdateState(_ manager: CameraManager)
    func cameraManager(_ manager: CameraManager, didChangePreset preset: Preset)
}

extension Notification.Name {
    static let settingsChanged = Notification.Name("settingsChanged")
    static let presetChanged = Notification.Name("presetChanged")
}

enum CameraError: Error {
    case noVideoDevicesAvailable
    case deviceInputError
    case sessionConfigurationError
    
    var localizedDescription: String {
        switch self {
        case .noVideoDevicesAvailable:
            return "No video capture devices are available"
        case .deviceInputError:
            return "Could not create video device input"
        case .sessionConfigurationError:
            return "Could not configure capture session"
        }
    }
}

enum CameraDeviceStatus {
    case available
    case unavailable
    case inUseByAnotherApp
    case active
    case disconnected
}

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, NSWindowDelegate {
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    @Published var isRunning = false
    @Published var activeDeviceID: String?
    @Published private(set) var deviceStatuses: [String: CameraDeviceStatus] = [:]
    
    weak var delegate: CameraManagerDelegate?
    private(set) var backgroundProcessor: BackgroundProcessor
    private var previewWindow: NSWindow?
    private var previewView: NSView?
    private let ciContext = CIContext()
    private let settingsKey = "com.deju.VirtualCam.settings"
    
    override init() {
        backgroundProcessor = BackgroundProcessor()
        super.init()
        
        // Start observing device connection status
        setupDeviceNotifications()
        
        setupPreviewWindow()
        loadSavedSettings()
        
        // Initial device status check and auto-start
        updateDeviceStatuses()
        startFirstAvailableCamera()
    }
    
    private func setupDeviceNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceWasConnected),
            name: AVCaptureDevice.wasConnectedNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceWasDisconnected),
            name: AVCaptureDevice.wasDisconnectedNotification,
            object: nil
        )
    }
    
    private func startFirstAvailableCamera() {
        // Get devices in priority order
        let preferences = CameraSourcePreferences.shared
        let savedSources = preferences.sources
        
        let deviceTypes: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            deviceTypes = [.builtInWideAngleCamera, .external]
        } else {
            deviceTypes = [.builtInWideAngleCamera, .externalUnknown]
        }
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )
        
        // First try to find a device from our saved preferences
        var selectedDevice: AVCaptureDevice?
        if !savedSources.isEmpty {
            for source in savedSources {
                if let device = discoverySession.devices.first(where: { $0.uniqueID == source.id }),
                   !device.isSuspended && !device.isInUseByAnotherApplication {
                    selectedDevice = device
                    break
                }
            }
        }
        
        // If no preferred device is available, take the first available device
        if selectedDevice == nil {
            selectedDevice = discoverySession.devices.first(where: { !$0.isSuspended && !$0.isInUseByAnotherApplication })
        }
        
        // If we found an available device, start it
        if let device = selectedDevice {
            // Save device in preferences if not already saved
            if !savedSources.contains(where: { $0.id == device.uniqueID }) {
                let newSource = CameraSource(
                    id: device.uniqueID,
                    name: device.localizedName,
                    priority: savedSources.count
                )
                preferences.sources = savedSources + [newSource]
            }
            
            // Set as active device and start it
            activeDeviceID = device.uniqueID
            startCamera()
        }
    }
    
    func startCamera() {
        // Ensure we're on the main thread for UI updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Store previous active device ID before stopping
            let previousActiveID = self.activeDeviceID
            
            // Stop any existing camera
            self.stopCamera()
            
            guard let deviceID = self.activeDeviceID,
                  let device = try? self.findDevice(withUniqueID: deviceID),
                  !device.isSuspended && !device.isInUseByAnotherApplication else {
                return
            }
            
            // Create new session
            let session = AVCaptureSession()
            session.sessionPreset = .high
            self.captureSession = session
            
            do {
                let videoInput = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(videoInput) {
                    session.addInput(videoInput)
                } else {
                    print("Cannot add video input")
                    return
                }
                
                // Configure video data output
                let dataOutput = AVCaptureVideoDataOutput()
                dataOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                ]
                
                let outputQueue = DispatchQueue(label: "videoDataOutputQueue", qos: .userInteractive)
                dataOutput.setSampleBufferDelegate(self, queue: outputQueue)
                dataOutput.alwaysDiscardsLateVideoFrames = true
                
                if session.canAddOutput(dataOutput) {
                    session.addOutput(dataOutput)
                } else {
                    print("Cannot add video output")
                    return
                }
                self.videoDataOutput = dataOutput
                
                // Start session on background thread
                DispatchQueue.global(qos: .userInteractive).async {
                    session.startRunning()
                    DispatchQueue.main.async {
                        if session.isRunning {
                            self.isRunning = true
                            
                            // Mark previous camera as available if it's different from current
                            if let previousID = previousActiveID, previousID != deviceID {
                                self.deviceStatuses[previousID] = .available
                            }
                            
                            // Mark current camera as active
                            self.deviceStatuses[deviceID] = .active
                            self.objectWillChange.send()
                        }
                    }
                }
            } catch {
                print("Error setting up camera: \(error.localizedDescription)")
            }
        }
    }
    
    private func findDevice(withUniqueID uniqueID: String) throws -> AVCaptureDevice? {
        let deviceTypes: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            deviceTypes = [.builtInWideAngleCamera, .external]
        } else {
            deviceTypes = [.builtInWideAngleCamera, .externalUnknown]
        }
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )
        
        return discoverySession.devices.first { $0.uniqueID == uniqueID }
    }
    
    private func setupPreviewWindow() {
        // Create preview view with 16:9 aspect ratio
        let width: CGFloat = 960
        let height: CGFloat = (width * 9) / 16
        previewView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        
        // Create window with the same aspect ratio
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Camera Preview"
        window.contentView = previewView
        window.delegate = self
        window.setFrameAutosaveName("PreviewWindow")
        
        // Center window on screen
        window.center()
        
        previewWindow = window
        
        // Create preview layer
        let previewLayer = AVCaptureVideoPreviewLayer()
        previewLayer.frame = previewView?.bounds ?? .zero
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        previewLayer.videoGravity = .resizeAspectFill
        previewView?.wantsLayer = true
        previewView?.layer?.addSublayer(previewLayer)
        
        self.previewLayer = previewLayer
    }
    
    private func loadSavedSettings() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let settings = try? JSONDecoder().decode(BackgroundSettings.self, from: data) {
            let preset = Preset(
                name: "Default",
                type: settings.backgroundPreset,
                settings: settings
            )
            setPreset(preset)
        } else {
            let defaultSettings = BackgroundSettings()
            let defaultPreset = Preset(
                name: "Default",
                type: .none,
                settings: defaultSettings
            )
            setPreset(defaultPreset)
        }
    }
    
    private func saveSettings() {
        if let settings = currentSettings {
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: settingsKey)
                
                // If we have a custom background, save its path
                if settings.backgroundPreset == .custom,
                   let preset = backgroundProcessor.currentPreset,
                   let imagePath = preset.imagePath {
                    UserDefaults.standard.set(imagePath, forKey: "\(settingsKey).customImagePath")
                } else {
                    // Clean up the image path if we're not using a custom background
                    UserDefaults.standard.removeObject(forKey: "\(settingsKey).customImagePath")
                }
                
                UserDefaults.standard.synchronize()
            }
        }
    }
    
    private func updateDeviceStatuses() {
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
        
        // Reset statuses
        deviceStatuses.removeAll()
        
        for device in devices {
            var status = CameraDeviceStatus.available
            
            // Check if device is suspended
            if device.isSuspended {
                status = .unavailable
            }
            
            // Check if device is in use by another app
            if device.isInUseByAnotherApplication {
                status = .inUseByAnotherApp
            }
            
            // Check if this is the active device
            if device.uniqueID == activeDeviceID && isRunning {
                status = .active
            }
            
            deviceStatuses[device.uniqueID] = status
        }
        
        objectWillChange.send()
    }
    
    @objc private func deviceWasConnected(_ notification: Notification) {
        guard let device = notification.object as? AVCaptureDevice else { return }
        
        // Update device status
        deviceStatuses[device.uniqueID] = .available
        
        // Add to preferences if not already present
        let preferences = CameraSourcePreferences.shared
        if !preferences.sources.contains(where: { $0.id == device.uniqueID }) {
            let newSource = CameraSource(
                id: device.uniqueID,
                name: device.localizedName,
                priority: preferences.sources.count
            )
            preferences.sources.append(newSource)
        }
        
        objectWillChange.send()
        
        // Notify delegate
        delegate?.cameraManagerDidUpdateState(self)
    }
    
    @objc private func deviceWasDisconnected(_ notification: Notification) {
        guard let device = notification.object as? AVCaptureDevice else { return }
        
        // Update device status
        deviceStatuses[device.uniqueID] = .disconnected
        
        // If this was the active device, try to switch to another one
        if device.uniqueID == activeDeviceID {
            stopCamera()
            startFirstAvailableCamera()
        }
        
        objectWillChange.send()
        
        // Notify delegate
        delegate?.cameraManagerDidUpdateState(self)
    }
    
    deinit {
        stopCamera()
    }
    
    var currentPreset: Preset {
        return backgroundProcessor.currentPreset ?? Preset(name: "None", type: .none, settings: BackgroundSettings())
    }
    
    var currentSettings: BackgroundSettings? {
        return backgroundProcessor.currentSettings
    }
    
    func stopCamera() {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            self.captureSession?.stopRunning()
            DispatchQueue.main.async {
                self.isRunning = false
                
                // Mark the stopped camera as available
                if let activeID = self.activeDeviceID {
                    self.deviceStatuses[activeID] = .available
                    self.objectWillChange.send()
                }
            }
        }
    }
    
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        if let existingLayer = previewLayer {
            return existingLayer
        }
        
        guard let session = captureSession else {
            return nil
        }
        
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer
        return layer
    }
    
    func setPreset(_ preset: Preset) {
        backgroundProcessor.setPreset(preset)
        // Notify observers of preset change
        NotificationCenter.default.post(name: .presetChanged, object: preset)
        saveSettings()
        delegate?.cameraManager(self, didChangePreset: preset)
    }
    
    func updateSettings(_ settings: BackgroundSettings) {
        backgroundProcessor.updateSettings(settings)
        // Notify observers of settings change
        NotificationCenter.default.post(name: .settingsChanged, object: settings)
        saveSettings()
    }
    
    func switchToCamera(withID deviceID: String) {
        guard let device = try? findDevice(withUniqueID: deviceID),
              !device.isSuspended && !device.isInUseByAnotherApplication,
              deviceStatuses[deviceID] == .available else {
            print("Cannot switch to camera: device not available")
            return
        }
        
        // Store previous active device ID
        let previousActiveID = activeDeviceID
        
        // Set new active device and start it
        activeDeviceID = deviceID
        startCamera()
        
        // Update status of previously active device to available
        if let previousID = previousActiveID {
            deviceStatuses[previousID] = .available
            objectWillChange.send()
        }
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let processedImage = backgroundProcessor.processFrame(imageBuffer)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update preview layer with processed image
            if let processedImage = processedImage,
               let cgImage = self.ciContext.createCGImage(processedImage, from: processedImage.extent) {
                let layer = CALayer()
                layer.frame = self.previewLayer?.bounds ?? .zero
                layer.contents = cgImage
                
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.previewLayer?.sublayers?.removeAll()
                self.previewLayer?.addSublayer(layer)
                CATransaction.commit()
            }
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Handle dropped frames if needed
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        stopCamera()
    }
    
    public func windowDidResize(_ notification: Notification) {
        updatePreviewLayerFrame()
    }
    
    private func updatePreviewLayerFrame() {
        guard let bounds = previewWindow?.contentView?.bounds else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        previewLayer?.sublayers?.forEach { $0.frame = bounds }
        CATransaction.commit()
    }
}
