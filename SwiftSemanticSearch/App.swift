//
// Copyright (c) Ash Vardanian
//

import SwiftUI

@main
struct SwiftSemanticSearchApp: App {
    @StateObject var searchModel = SearchModel()
    
    var body: some Scene {
        WindowGroup {

            ContentView()
                .environmentObject(searchModel)
                .task {
                    Task.detached(priority: .userInitiated) {
                        await searchModel.loadEncodersAndIndexConcurrently()
                    }
                }
        }
    }
}

