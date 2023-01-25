//
//  ContentView.swift
//
//  Created by Hovik Melikyan on 07/12/2022.
//

import UIKit
import SwiftUI

struct MainView: View {
	@State private var showingCameraView = false
	@State private var uiImage: UIImage?

    var body: some View {
		VStack {
			ZStack {
				Color.gray
				uiImage.map({ Image(uiImage: $0) })?
					.resizable()
					.scaledToFill()
			}
			.frame(width: 128, height: 128)
			.cornerRadius(8)

			Button {
				showingCameraView.toggle()
			} label: {
				HStack {
					Image(systemName: "camera")
						.imageScale(.large)
						.foregroundColor(.accentColor)
					Text("Take a picture")
				}
			}
			.padding()
			.fullScreenCover(isPresented: $showingCameraView) {
				CameraView(title: "Take a photo of yourself", forSelfie: true, result: $uiImage)
			}
		}
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
