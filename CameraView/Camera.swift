//
//  Camera.swift
//
//  Created by Hovik Melikyan on 12/12/2022.
//
//  Based on Apple's sample app, modified:
//  https://developer.apple.com/tutorials/sample-apps/capturingphotos-captureandsave
//

@preconcurrency import AVFoundation
import CoreImage.CIImage
import UIKit.UIImage


@MainActor
final class Camera: NSObject {
	private let captureSession = AVCaptureSession()
	private var isCaptureSessionConfigured = false
	private var deviceInput: AVCaptureDeviceInput?
	private var photoOutput: AVCapturePhotoOutput?
	private var videoOutput: AVCaptureVideoDataOutput?

	private var allCaptureDevices: [AVCaptureDevice] {
		AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInWideAngleCamera, .builtInDualWideCamera], mediaType: .video, position: .unspecified).devices
	}

	private var frontCaptureDevices: [AVCaptureDevice] {
		allCaptureDevices
			.filter { $0.position == .front }
	}

	private var backCaptureDevices: [AVCaptureDevice] {
		allCaptureDevices
			.filter { $0.position == .back }
	}

	private var captureDevices: [AVCaptureDevice] {
		var devices = [AVCaptureDevice]()
#if os(macOS) || (os(iOS) && targetEnvironment(macCatalyst))
		devices += allCaptureDevices
#else
		if let backDevice = backCaptureDevices.first {
			devices += [backDevice]
		}
		if let frontDevice = frontCaptureDevices.first {
			devices += [frontDevice]
		}
#endif
		return devices
	}

	private var availableCaptureDevices: [AVCaptureDevice] {
		captureDevices
			.filter( { $0.isConnected } )
			.filter( { !$0.isSuspended } )
	}

	private var captureDevice: AVCaptureDevice? {
		didSet {
			guard let captureDevice = captureDevice else { return }
			updateSessionForCaptureDevice(captureDevice)
		}
	}

	var isRunning: Bool {
		captureSession.isRunning
	}

	var isUsingFrontCaptureDevice: Bool {
		guard let captureDevice = captureDevice else { return false }
		return frontCaptureDevices.contains(captureDevice)
	}

	var isUsingBackCaptureDevice: Bool {
		guard let captureDevice = captureDevice else { return false }
		return backCaptureDevices.contains(captureDevice)
	}

	private var addToPhotoStream: ((UIImage) -> Void)?

	private var addToPreviewStream: ((UIImage) -> Void)?

	var isPreviewPaused = false

	lazy var previewStream: AsyncStream<UIImage> = {
		AsyncStream { continuation in
			addToPreviewStream = { uiImage in
				if !self.isPreviewPaused {
					continuation.yield(uiImage)
				}
			}
		}
	}()

	lazy var photoStream: AsyncStream<UIImage> = {
		AsyncStream { continuation in
			addToPhotoStream = { photo in
				continuation.yield(photo)
			}
		}
	}()

	init(forSelfie: Bool) {
		super.init()

		let device = availableCaptureDevices.first {
			$0.position == (forSelfie ? .front : .back)
		}
		captureDevice = device ?? AVCaptureDevice.default(for: .video)

		UIDevice.current.beginGeneratingDeviceOrientationNotifications()
		NotificationCenter.default.addObserver(self, selector: #selector(updateForDeviceOrientation), name: UIDevice.orientationDidChangeNotification, object: nil)
	}

	private func configureCaptureSession(completionHandler: (_ success: Bool) -> Void) {

		var success = false

		self.captureSession.beginConfiguration()

		defer {
			self.captureSession.commitConfiguration()
			completionHandler(success)
		}

		guard
			let captureDevice = captureDevice,
			let deviceInput = try? AVCaptureDeviceInput(device: captureDevice)
		else {
			print("ERROR: Failed to obtain video input.")
			return
		}

		let photoOutput = AVCapturePhotoOutput()

		captureSession.sessionPreset = AVCaptureSession.Preset.photo

		let videoOutput = AVCaptureVideoDataOutput()
		videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "VideoDataOutputQueue"))

		guard captureSession.canAddInput(deviceInput) else {
			print("ERROR: Unable to add device input to capture session.")
			return
		}
		guard captureSession.canAddOutput(photoOutput) else {
			print("ERROR: Unable to add photo output to capture session.")
			return
		}
		guard captureSession.canAddOutput(videoOutput) else {
			print("ERROR: Unable to add video output to capture session.")
			return
		}

		captureSession.addInput(deviceInput)
		captureSession.addOutput(photoOutput)
		captureSession.addOutput(videoOutput)

		self.deviceInput = deviceInput
		self.photoOutput = photoOutput
		self.videoOutput = videoOutput

		//        photoOutput.isHighResolutionCaptureEnabled = true
		photoOutput.maxPhotoQualityPrioritization = .quality

		updateVideoOutputConnection()

		isCaptureSessionConfigured = true

		success = true
	}

	private func checkAuthorization() async -> Bool {
		switch AVCaptureDevice.authorizationStatus(for: .video) {
			case .authorized:
				return true
			case .notDetermined:
				let status = await AVCaptureDevice.requestAccess(for: .video)
				return status
			case .denied:
				return false
			case .restricted:
				return false
			@unknown default:
				return false
		}
	}

	private func deviceInputFor(device: AVCaptureDevice?) -> AVCaptureDeviceInput? {
		guard let validDevice = device else { return nil }
		do {
			return try AVCaptureDeviceInput(device: validDevice)
		} catch let error {
			print("ERROR: Error getting capture device input: \(error.localizedDescription)")
			return nil
		}
	}

	private func updateSessionForCaptureDevice(_ captureDevice: AVCaptureDevice) {
		guard isCaptureSessionConfigured else { return }

		captureSession.beginConfiguration()
		defer { captureSession.commitConfiguration() }

		for input in captureSession.inputs {
			if let deviceInput = input as? AVCaptureDeviceInput {
				captureSession.removeInput(deviceInput)
			}
		}

		if let deviceInput = deviceInputFor(device: captureDevice) {
			if !captureSession.inputs.contains(deviceInput), captureSession.canAddInput(deviceInput) {
				captureSession.addInput(deviceInput)
			}
		}

		updateVideoOutputConnection()
	}

	private func updateVideoOutputConnection() {
		if let videoOutput = videoOutput, let videoOutputConnection = videoOutput.connection(with: .video) {
			if videoOutputConnection.isVideoMirroringSupported {
				videoOutputConnection.isVideoMirrored = isUsingFrontCaptureDevice
			}
		}
	}

	func start() async {
		let authorized = await checkAuthorization()
		guard authorized else {
			print("ERROR: Camera access was not authorized.")
			return
		}

		if isCaptureSessionConfigured {
			if !captureSession.isRunning {
				Task.detached {
					await self.captureSession.startRunning()
				}
			}
			return
		}

		configureCaptureSession { success in
			guard success else { return }
			Task.detached {
				await self.captureSession.startRunning()
			}
		}
	}

	func stop() {
		guard isCaptureSessionConfigured else { return }

		if captureSession.isRunning {
			captureSession.stopRunning()
		}
	}

	func switchCaptureDevice() {
		if let captureDevice = captureDevice, let index = availableCaptureDevices.firstIndex(of: captureDevice) {
			let nextIndex = (index + 1) % availableCaptureDevices.count
			self.captureDevice = availableCaptureDevices[nextIndex]
		} else {
			self.captureDevice = AVCaptureDevice.default(for: .video)
		}
	}

	private var deviceOrientation: UIDeviceOrientation {
		var orientation = UIDevice.current.orientation
		if orientation == UIDeviceOrientation.unknown {
			orientation = UIScreen.main.orientation
		}
		return orientation
	}

	@objc
	func updateForDeviceOrientation() {
		//TODO: Figure out if we need this for anything.
	}

	private func videoOrientationFor(_ deviceOrientation: UIDeviceOrientation) -> AVCaptureVideoOrientation? {
		switch deviceOrientation {
			case .portrait: return AVCaptureVideoOrientation.portrait
			case .portraitUpsideDown: return AVCaptureVideoOrientation.portraitUpsideDown
			case .landscapeLeft: return AVCaptureVideoOrientation.landscapeRight
			case .landscapeRight: return AVCaptureVideoOrientation.landscapeLeft
			default: return nil
		}
	}

	func takePhoto() {
		guard let photoOutput = self.photoOutput else { return }

		var photoSettings = AVCapturePhotoSettings()

		if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
			photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
		}

		let isFlashAvailable = self.deviceInput?.device.isFlashAvailable ?? false
		photoSettings.flashMode = isFlashAvailable ? .auto : .off
//		photoSettings.isHighResolutionPhotoEnabled = true
		if let previewPhotoPixelFormatType = photoSettings.availablePreviewPhotoPixelFormatTypes.first {
			photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: previewPhotoPixelFormatType]
		}
		photoSettings.photoQualityPrioritization = .balanced

		if let photoOutputVideoConnection = photoOutput.connection(with: .video) {
			if photoOutputVideoConnection.isVideoOrientationSupported,
			   let videoOrientation = self.videoOrientationFor(self.deviceOrientation) {
				photoOutputVideoConnection.videoOrientation = videoOrientation
			}
		}

		photoOutput.capturePhoto(with: photoSettings, delegate: self)
	}
}

extension Camera: AVCapturePhotoCaptureDelegate {

	nonisolated
	func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {

		if let error {
			print("ERROR: Error capturing photo: \(error.localizedDescription)")
			return
		}

		guard let cgImage = photo.cgImageRepresentation(),
			  let metadataOrientation = photo.metadata[String(kCGImagePropertyOrientation)] as? UInt32,
			  let cgImageOrientation = CGImagePropertyOrientation(rawValue: metadataOrientation) else { return }

		let uiImage = UIImage(cgImage: cgImage, scale: 1, orientation: UIImage.Orientation(cgImageOrientation))

		Task { @MainActor in
			addToPhotoStream?(uiImage)
		}
	}
}


extension Camera: AVCaptureVideoDataOutputSampleBufferDelegate {

	nonisolated
	func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
		guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
		let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
		guard let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return }
		let uiImage = UIImage(cgImage: cgImage)

		Task { @MainActor in
			if connection.isVideoOrientationSupported,
			   let videoOrientation = videoOrientationFor(deviceOrientation) {
				connection.videoOrientation = videoOrientation
			}

			addToPreviewStream?(uiImage)
		}
	}
}


private extension UIScreen {

	var orientation: UIDeviceOrientation {
		let point = coordinateSpace.convert(CGPoint.zero, to: fixedCoordinateSpace)
		if point == CGPoint.zero {
			return .portrait
		} else if point.x != 0 && point.y != 0 {
			return .portraitUpsideDown
		} else if point.x == 0 && point.y != 0 {
			return .landscapeRight //.landscapeLeft
		} else if point.x != 0 && point.y == 0 {
			return .landscapeLeft //.landscapeRight
		} else {
			return .unknown
		}
	}
}


private extension UIImage.Orientation {

	init(_ cgImageOrientation: CGImagePropertyOrientation) {
		switch cgImageOrientation {
			case .up: self = .up
			case .upMirrored: self = .upMirrored
			case .down: self = .down
			case .downMirrored: self = .downMirrored
			case .left: self = .left
			case .leftMirrored: self = .leftMirrored
			case .right: self = .right
			case .rightMirrored: self = .rightMirrored
		}
	}
}
