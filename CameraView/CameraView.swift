//
//  CameraView.swift
//
//  Created by Hovik Melikyan on 12/12/2022.
//

import SwiftUI


struct CameraView: View {

	let title: String
	@Binding var result: UIImage?

	@State private var viewfinderImage: Image?
	@State private var capturedImage: UIImage?
	@State private var showingImagePicker = false
	private var hasCapturedImage: Bool { capturedImage != nil }

	private let camera: Camera

	@Environment(\.presentationMode) var presentationMode


	init(title: String, forSelfie: Bool, result: Binding<UIImage?>) {
		self.title = title
		self._result = result
		self.camera = Camera(forSelfie: forSelfie)
	}


	var body: some View {
		GeometryReader { geometry in
			ViewfinderView(viewfinderImage: $viewfinderImage, capturedImage: $capturedImage)
				.overlay(
					Color.black
						.opacity(0.75)
						.frame(height: 96 + geometry.safeAreaInsets.bottom),
					alignment: .top)
				.overlay(
					topBar()
						.padding(.top, geometry.safeAreaInsets.top),
					alignment: .top)
				.overlay(
					buttonsView(height: 144 + geometry.safeAreaInsets.bottom),
					alignment: .bottom)
				.ignoresSafeArea()
		}
		.onAppear {
			Task {
				await camera.start()
				Task {
					await handleCameraPreviews()
				}
				Task {
					await handleCameraPhotos()
				}
			}
		}
		.statusBar(hidden: true)
	}


	private func handleCameraPreviews() async {
		// This is the video stream, just map it to the viewfinder
		let imageStream = camera.previewStream.map { Image(uiImage: $0) }
		for await image in imageStream {
			Task { @MainActor in
				viewfinderImage = image
			}
		}
	}

	func handleCameraPhotos() async {
		// A much slower stream of photos captured
		let unpackedPhotoStream = camera.photoStream
			.compactMap { $0 }

		for await image in unpackedPhotoStream {
			Task { @MainActor in
				camera.stop()
				capturedImage = image
			}
		}
	}


	private func buttonsView(height: Double) -> some View {
		ZStack {
			Color.black.opacity(0.75)
			capturingButtons().isHidden(hasCapturedImage)
			confirmationButtons().isHidden(!hasCapturedImage)
		}
		.frame(height: height)
	}


	private func capturingButtons() -> some View {
		HStack(spacing: 60) {
			Spacer()

			Button {
				showingImagePicker.toggle()
			} label: {
				Image(systemName: "ellipsis")
			}

			Button {
				camera.takePhoto()
			} label: {
				Image(systemName: "circle.inset.filled")
					.font(.system(size: 70, weight: .thin))
			}

			Button {
				camera.switchCaptureDevice()
			} label: {
				Image(systemName: "arrow.triangle.2.circlepath")
			}

			Spacer()
		}
		.foregroundColor(.white)
		.font(.system(size: 36, weight: .regular))
		.sheet(isPresented: $showingImagePicker) {
			ImagePicker(image: $capturedImage)
		}
	}


	private func confirmationButtons() -> some View {
		HStack(spacing: 24) {
			Capsule()
				.fill(Color.gray)
				.overlay(Button {
					capturedImage = nil
					Task {
						await camera.start()
					}
				} label: {
					Text("RETAKE")
						.foregroundColor(.white)
				})
				.frame(width: 132, height: 50)
			Capsule()
				.fill(Color.accentColor)
				.overlay(Button {
					guard let capturedImage else { return }
					result = capturedImage
					presentationMode.wrappedValue.dismiss()
				} label: {
					Text("DONE")
						.foregroundColor(.black)
				})
				.frame(width: 132, height: 50)
		}
		.padding()
	}


	private func topBar() -> some View {
		ZStack(alignment: .leading) {
			Button {
				presentationMode.wrappedValue.dismiss()
			} label: {
				Image(systemName: "xmark")
					.font(.system(size: 24, weight: .regular))
			}
			Text(title)
				.frame(maxWidth: .infinity)
		}
		.foregroundColor(.white)
		.padding()
	}


	private struct ViewfinderView: View {
		@Binding var viewfinderImage: Image?
		@Binding var capturedImage: UIImage?

		var body: some View {
			GeometryReader { geometry in
				ZStack {
					Color.black
					viewfinderImage?
						.resizable()
						.scaledToFill()
						.frame(width: geometry.size.width, height: geometry.size.height)
					capturedImage.map({ Image(uiImage: $0) })?
						.resizable()
						.scaledToFill()
						.frame(width: geometry.size.width, height: geometry.size.height)
				}
			}
		}
	}
}


private extension CIImage {
	var image: Image? {
		let ciContext = CIContext()
		guard let cgImage = ciContext.createCGImage(self, from: self.extent) else { return nil }
		return Image(decorative: cgImage, scale: 1, orientation: .up)
	}
}


private extension View {

	@ViewBuilder func isHidden(_ hidden: Bool, remove: Bool = false) -> some View {
		if hidden {
			if !remove {
				self.hidden()
			}
		} else {
			self
		}
	}
}


struct CameraView_Previews: PreviewProvider {
	static var previews: some View {
		CameraView(title: "Take a photo of yourself", forSelfie: true, result: .init(get: {
			nil
		}, set: { image in

		}))
	}
}
