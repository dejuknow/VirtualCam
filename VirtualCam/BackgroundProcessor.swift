import Foundation
import CoreImage
import Vision
import AppKit

class BackgroundProcessor {
    private var personSegmentationRequest: VNGeneratePersonSegmentationRequest?
    private(set) var currentSettings: BackgroundSettings?
    private(set) var currentPreset: Preset?
    private var cachedBackgroundImage: CIImage?
    private var lastFrameSize: CGRect?
    
    init() {
        setupVisionRequest()
        // Set default preset
        currentSettings = BackgroundSettings()
    }
    
    private func setupVisionRequest() {
        personSegmentationRequest = VNGeneratePersonSegmentationRequest()
        personSegmentationRequest?.qualityLevel = .balanced
        personSegmentationRequest?.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }
    
    func setPreset(_ preset: Preset) {
        currentPreset = preset
        
        // Create new settings with the preset type
        var settings = preset.settings
        settings.backgroundPreset = preset.type
        currentSettings = settings
        
        // Load custom background image if provided
        if preset.type == .custom, let imagePath = preset.imagePath {
            if let image = CIImage(contentsOf: URL(fileURLWithPath: imagePath)) {
                currentSettings?.customBackgroundImage = image
            } else {
                print("Failed to load custom background image from: \(imagePath)")
            }
        }
        
        // Clear cached background when preset changes
        cachedBackgroundImage = nil
        lastFrameSize = nil
    }
    
    func updateSettings(_ settings: BackgroundSettings) {
        currentSettings = settings
    }
    
    func processVideoFrame(_ frame: CIImage, with settings: BackgroundSettings) -> CIImage {
        let originalExtent = frame.extent
        
        // First apply any background effects
        var result = applyBackgroundEffect(to: frame, with: settings)
        
        // Then apply video adjustments
        result = applyVideoAdjustments(to: result, with: settings)
        
        // Ensure final output maintains original size
        return result.cropped(to: originalExtent)
    }
    
    private func applyBackgroundEffect(to image: CIImage, with settings: BackgroundSettings) -> CIImage {
        let originalExtent = image.extent
        
        switch settings.backgroundPreset {
        case .none:
            return image
            
        case .lightBlur, .blur:
            if let personMask = createPersonMask(from: image) {
                // Create a blurred version of the entire image
                let blurAmount: Double = settings.backgroundPreset == .lightBlur ? 10.0 : 20.0
                let blurredBackground = image.applyingGaussianBlur(sigma: blurAmount)
                                           .cropped(to: originalExtent)
                
                // Blend the original person with the blurred background
                if let blendFilter = CIFilter(name: "CIBlendWithMask") {
                    blendFilter.setValue(image, forKey: kCIInputImageKey)            // Original image (for person)
                    blendFilter.setValue(blurredBackground, forKey: kCIInputBackgroundImageKey)  // Blurred image (for background)
                    blendFilter.setValue(personMask, forKey: kCIInputMaskImageKey)   // Person mask
                    
                    return blendFilter.outputImage?.cropped(to: originalExtent) ?? image
                }
            }
            return image
            
        case .custom, .included1, .included2, .included3:
            let backgroundImage: CIImage?
            
            switch settings.backgroundPreset {
            case .custom:
                backgroundImage = settings.customBackgroundImage
            case .included1:
                backgroundImage = settings.included1BackgroundImage
            case .included2:
                backgroundImage = settings.included2BackgroundImage
            case .included3:
                backgroundImage = settings.included3BackgroundImage
            default:
                backgroundImage = nil
            }
            
            if let customImage = backgroundImage,
               let personMask = createPersonMask(from: image) {
                // Scale and position the custom background image to fill the frame
                let scaledBackground = scaleAndCenterFill(image: customImage, toExtent: originalExtent)
                
                // Blend the original person with the custom background
                if let blendFilter = CIFilter(name: "CIBlendWithMask") {
                    blendFilter.setValue(image, forKey: kCIInputImageKey)            // Original image (for person)
                    blendFilter.setValue(scaledBackground, forKey: kCIInputBackgroundImageKey)  // Custom background
                    blendFilter.setValue(personMask, forKey: kCIInputMaskImageKey)   // Person mask
                    
                    return blendFilter.outputImage?.cropped(to: originalExtent) ?? image
                }
            }
            return image
        }
    }
    
    private func scaleAndCenterFill(image: CIImage, toExtent targetExtent: CGRect) -> CIImage {
        let imageAspect = image.extent.width / image.extent.height
        let targetAspect = targetExtent.width / targetExtent.height
        
        let scale: CGFloat
        if imageAspect > targetAspect {
            // Image is wider than target: scale to match height
            scale = targetExtent.height / image.extent.height
        } else {
            // Image is taller than target: scale to match width
            scale = targetExtent.width / image.extent.width
        }
        
        // Scale the image
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        // Center the image
        let xOffset = (targetExtent.width - scaledImage.extent.width) / 2
        let yOffset = (targetExtent.height - scaledImage.extent.height) / 2
        
        // Translate to center and crop
        return scaledImage
            .transformed(by: CGAffineTransform(translationX: xOffset + targetExtent.minX, 
                                             y: yOffset + targetExtent.minY))
            .cropped(to: targetExtent)
    }
    
    private func applyVideoAdjustments(to image: CIImage, with settings: BackgroundSettings) -> CIImage {
        var result = image
        let originalExtent = image.extent
        
        // Only get person mask if we're using a background effect
        let shouldMaskAdjustments = settings.backgroundPreset != .none
        let personMask = shouldMaskAdjustments ? createPersonMask(from: image) : nil
        
        // Apply mirroring if enabled (after mask creation but before effects)
        if settings.mirrorVideo {
            result = result.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
            result = result.transformed(by: CGAffineTransform(translationX: originalExtent.width, y: 0))
            
            // Also mirror the mask if we have one
            if let mask = personMask {
                let mirroredMask = mask.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
                                    .transformed(by: CGAffineTransform(translationX: originalExtent.width, y: 0))
                return applyEffects(to: result, withMask: mirroredMask, settings: settings)
            }
        }
        
        return applyEffects(to: result, withMask: personMask, settings: settings)
    }
    
    private func applyEffects(to image: CIImage, withMask mask: CIImage?, settings: BackgroundSettings) -> CIImage {
        var result = image
        let originalExtent = result.extent
        
        // Apply skin smoothing effect first (before other adjustments)
        if settings.skinSmoothingAmount > 0 {
            if let smoothed = applySkinSmoothing(to: result, intensity: settings.skinSmoothingAmount) {
                if let mask = mask {
                    result = blendWithMask(foreground: smoothed, background: result, mask: mask)
                } else {
                    result = smoothed
                }
            }
        }
        
        // Apply background effect if enabled
        if settings.backgroundPreset != .none, let mask = mask {
            switch settings.backgroundPreset {
            case .blur, .lightBlur:
                if let blurred = applyGaussianBlur(to: result, radius: settings.backgroundPreset == .blur ? 20.0 : 10.0) {
                    result = blendWithMask(foreground: result, background: blurred, mask: mask)
                }
            case .custom, .included1, .included2, .included3:
                let backgroundImage: CIImage?
                switch settings.backgroundPreset {
                case .custom:
                    backgroundImage = settings.customBackgroundImage
                case .included1:
                    backgroundImage = settings.included1BackgroundImage
                case .included2:
                    backgroundImage = settings.included2BackgroundImage
                case .included3:
                    backgroundImage = settings.included3BackgroundImage
                default:
                    backgroundImage = nil
                }
                
                if let background = backgroundImage {
                    let scaledBackground = scaleAndCenterFill(image: background, toExtent: originalExtent)
                    result = blendWithMask(foreground: result, background: scaledBackground, mask: mask)
                }
            case .none:
                break
            }
        }
        
        // Apply color adjustments
        if settings.brightness != 0 {
            result = result.applyingFilter("CIColorControls", parameters: ["inputBrightness": settings.brightness])
        }
        if settings.contrast != 1 {
            result = result.applyingFilter("CIColorControls", parameters: ["inputContrast": settings.contrast])
        }
        if settings.saturation != 1 {
            result = result.applyingFilter("CIColorControls", parameters: ["inputSaturation": settings.saturation])
        }
        if settings.warmth != 0 {
            result = result.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500 + settings.warmth * 1000, y: 0)])
        }
        if settings.sharpness != 0 {
            result = result.applyingFilter("CISharpenLuminance", parameters: ["inputSharpness": settings.sharpness])
        }
        
        return result
    }
    
    private func blendWithMask(foreground: CIImage, background: CIImage, mask: CIImage) -> CIImage {
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else { return foreground }
        
        blendFilter.setValue(foreground, forKey: kCIInputImageKey)
        blendFilter.setValue(background, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(mask, forKey: kCIInputMaskImageKey)
        
        return blendFilter.outputImage ?? foreground
    }
    
    private func applyGaussianBlur(to image: CIImage, radius: Double) -> CIImage? {
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        return filter.outputImage
    }
    
    private func applySkinSmoothing(to image: CIImage, intensity: Double) -> CIImage? {
        let originalExtent = image.extent
        
        // First pass: Strong blur for major imperfections
        guard let strongBlur = CIFilter(name: "CIGaussianBlur") else { return nil }
        strongBlur.setValue(image, forKey: kCIInputImageKey)
        strongBlur.setValue(intensity * 8.0, forKey: kCIInputRadiusKey)
        guard let stronglyBlurred = strongBlur.outputImage else { return nil }
        
        // Second pass: Subtle blur for texture
        guard let subtleBlur = CIFilter(name: "CIGaussianBlur") else { return nil }
        subtleBlur.setValue(image, forKey: kCIInputImageKey)
        subtleBlur.setValue(intensity * 2.0, forKey: kCIInputRadiusKey)
        guard let subtlyBlurred = subtleBlur.outputImage else { return nil }
        
        // Create compositing filter for edge preservation
        guard let compositeFilter = CIFilter(name: "CIBlendWithMask") else { return nil }
        
        // Create luminance difference mask
        let luminanceDifference = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722),
            "inputGVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722),
            "inputBVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722)
        ])
        
        // Create edge mask using difference between original and blurred
        let edgeMask = luminanceDifference.applyingFilter("CIColorControls", parameters: [
            "inputBrightness": -0.5,
            "inputContrast": 2.0
        ])
        
        // Apply high-pass filter using blend modes
        compositeFilter.setValue(stronglyBlurred, forKey: kCIInputImageKey)
        compositeFilter.setValue(subtlyBlurred, forKey: kCIInputBackgroundImageKey)
        compositeFilter.setValue(edgeMask, forKey: kCIInputMaskImageKey)
        
        guard let preservedImage = compositeFilter.outputImage else { return nil }
        
        // Create detail-based mask using luminance
        let detailMask = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722),
            "inputGVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722),
            "inputBVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722)
        ]).applyingFilter("CIColorControls", parameters: [
            "inputBrightness": -0.2,
            "inputContrast": 1.5
        ])
        
        // Final blend
        guard let finalBlend = CIFilter(name: "CIBlendWithMask") else { return nil }
        finalBlend.setValue(preservedImage, forKey: kCIInputImageKey)
        finalBlend.setValue(image, forKey: kCIInputBackgroundImageKey)
        finalBlend.setValue(detailMask, forKey: kCIInputMaskImageKey)
        
        return finalBlend.outputImage?.cropped(to: originalExtent)
    }
    
    private func createSkinToneMask(from image: CIImage) -> CIImage? {
        let originalExtent = image.extent
        
        // Convert to YCbCr color space
        let ycbcr = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.299, y: 0.587, z: 0.114),
            "inputGVector": CIVector(x: -0.169, y: -0.331, z: 0.500),
            "inputBVector": CIVector(x: 0.500, y: -0.419, z: -0.081),
            "inputBiasVector": CIVector(x: 0, y: 128/255, z: 128/255, w: 1)
        ])
        
        // Create skin tone mask using color ranges
        let skinMask = ycbcr.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 1, z: 1),  // Use Cb and Cr channels
            "inputGVector": CIVector(x: 0, y: 0, z: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0)
        ]).applyingFilter("CIColorControls", parameters: [
            "inputSaturation": 0,
            "inputContrast": 2.0
        ]).applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 70/255, z: 130/255, w: 0),
            "inputMaxComponents": CIVector(x: 1, y: 135/255, z: 180/255, w: 1)
        ])
        
        // Smooth the mask edges
        return skinMask.applyingFilter("CIGaussianBlur", parameters: [
            "inputRadius": 3.0
        ]).cropped(to: originalExtent)
    }
    
    private func combineMasks(_ mask1: CIImage, _ mask2: CIImage) -> CIImage? {
        guard let multiplyFilter = CIFilter(name: "CIMultiplyCompositing") else { return nil }
        multiplyFilter.setValue(mask1, forKey: kCIInputImageKey)
        multiplyFilter.setValue(mask2, forKey: kCIInputBackgroundImageKey)
        return multiplyFilter.outputImage?.cropped(to: mask1.extent)
    }
    
    private func createPersonMask(from image: CIImage) -> CIImage? {
        guard let request = personSegmentationRequest else { return nil }
        
        // Create handler and inherit QoS from calling thread
        let handler = VNImageRequestHandler(ciImage: image, orientation: .up, options: [:])
        
        // Perform request directly on current thread to maintain QoS
        try? handler.perform([request])
        
        guard let mask = request.results?.first?.pixelBuffer else { return nil }
        let maskImage = CIImage(cvPixelBuffer: mask)
        
        // Scale the mask to match the input image size
        let scaleX = image.extent.width / maskImage.extent.width
        let scaleY = image.extent.height / maskImage.extent.height
        
        return maskImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: image.extent)
    }
    
    private func enhanceSkinMask(_ mask: CIImage, intensity: Float) -> CIImage? {
        // Enhance the mask to be more aggressive on blemishes
        guard let colorControls = CIFilter(name: "CIColorControls") else { return nil }
        colorControls.setValue(mask, forKey: kCIInputImageKey)
        colorControls.setValue(1.0 + Double(intensity), forKey: kCIInputContrastKey) // Increase contrast with intensity
        colorControls.setValue(0.0, forKey: kCIInputSaturationKey)
        
        return colorControls.outputImage?.cropped(to: mask.extent)
    }
    
    private func adjustMaskIntensity(_ mask: CIImage, intensity: Float) -> CIImage? {
        guard let colorControls = CIFilter(name: "CIColorControls") else { return nil }
        colorControls.setValue(mask, forKey: kCIInputImageKey)
        colorControls.setValue(0.8 * Double(intensity), forKey: kCIInputBrightnessKey) // Reduce the mask strength
        return colorControls.outputImage?.cropped(to: mask.extent)
    }
    
    func crossFadeImages(_ image1: CIImage, _ image2: CIImage, progress: Float) -> CIImage {
        let transition = CIFilter(name: "CIDissolveTransition")!
        transition.setValue(image1, forKey: kCIInputImageKey)
        transition.setValue(image2, forKey: kCIInputTargetImageKey)
        transition.setValue(NSNumber(value: progress), forKey: kCIInputTimeKey)
        return transition.outputImage ?? image1
    }
    
    func processFrame(_ buffer: CVPixelBuffer) -> CIImage? {
        guard let currentSettings = currentSettings else { return nil }
        
        let ciImage = CIImage(cvPixelBuffer: buffer)
        return processVideoFrame(ciImage, with: currentSettings)
    }
}
