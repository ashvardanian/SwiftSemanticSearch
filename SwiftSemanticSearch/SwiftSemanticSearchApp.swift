//
//  SwiftSemanticSearchApp.swift
//  SwiftSemanticSearch
//
//  Created by Ash Vardanian on 4/13/24.
//

import Accelerate
import SwiftUI
import USearch
import UForm
import Hub

@main
struct SwiftSemanticSearchApp: App {
    @StateObject var imageModel = ImageModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(imageModel)
                .task {
                    await imageModel.loadTextModel()
                }
        }
    }
}

