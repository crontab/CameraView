//
//  ImagePicker.swift
//  all-health-v2 (iOS)
//
//  Created by Anton Vilimets on 9/6/22.
//

import Foundation
import PhotosUI
import UIKit
import SwiftUI

// TODO: there's probably a better way in SwiftUI, also this can't handle raw images properly

struct ImagePicker: UIViewControllerRepresentable {
	@Binding var image: UIImage?

	func makeUIViewController(context: Context) -> PHPickerViewController {
		var config = PHPickerConfiguration()
		config.filter = .images
		let picker = PHPickerViewController(configuration: config)
		picker.delegate = context.coordinator
		return picker
	}

	func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {

	}

	func makeCoordinator() -> Coordinator {
		Coordinator(self)
	}

	class Coordinator: NSObject, PHPickerViewControllerDelegate {
		let parent: ImagePicker

		init(_ parent: ImagePicker) {
			self.parent = parent
		}

		func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
			picker.dismiss(animated: true)

			guard let provider = results.first?.itemProvider else { return }

			if provider.canLoadObject(ofClass: UIImage.self) {
				provider.loadObject(ofClass: UIImage.self) { image, _ in
					self.parent.image = image as? UIImage
				}
			}
		}
	}
}
