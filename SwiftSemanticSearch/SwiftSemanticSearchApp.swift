//
//  SwiftSemanticSearchApp.swift
//  SwiftSemanticSearch
//
//  Created by Ash Vardanian on 4/13/24.
//

import Accelerate
import SwiftUI

@main
struct SwiftSemanticSearchApp: App {
    @StateObject var searchModel = SearchModel()
    
    var body: some Scene {
        WindowGroup {

            ContentView()
                .environmentObject(searchModel)
                .task {
                    await searchModel.loadEncodersAndIndex()
                }
        }
    }
}

