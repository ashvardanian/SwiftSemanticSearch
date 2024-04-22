//
//  ContentView.swift
//  SwiftSemanticSearch
//
//  Created by Ash Vardanian on 4/13/24.
//

import SwiftUIX

struct ContentView: View {
    @EnvironmentObject var imageModel: ImageModel
    @State private var searchText: String = ""
    @State var filteredData: [String] = []
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    @State var searchTask: Task<Void, Error>? 

    var body: some View {
        NavigationView {
            VStack {
                TextField("Search", text: $searchText)
                    .padding()
                    .border(Color(UIColor.separator))

                searchResultsView
            }
            .navigationBarTitle("UForm + USearch 4 Swift", displayMode: .inline)
        }
    }
    
    private var searchResultsView: some View {
        ScrollView {
            if imageModel.textModel == nil {
                ProgressView()
                    .progressViewStyle(.circular)
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(filteredData, id: \.self) { imageName in
                        if let imagePath = Bundle.main.path(forResource: imageName, ofType: nil, inDirectory: "images") {
                            Image(uiImage: UIImage(contentsOfFile: imagePath) ?? UIImage())
                                .resizable()
                                .scaledToFit()
                                .frame(width: 100, height: 100)
                                .onTapGesture {
                                    print("\(imageName) was tapped")
                                }
                        }
                    }
                }
                .padding()
            }
        }
        .withChangePublisher(for: searchText) { publisher in
            publisher
                .receive(on: DispatchQueue.main)
                .handleEvents(receiveOutput: { _ in
                    self.filteredData = []
                })
                .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
                .sink { (text: String) in
                    searchTask?.cancel()
                    searchTask = Task.detached(priority: .userInitiated) {
                        let result = try await imageModel.filteredAndSortedImages(query: text)
                        
                        try Task.checkCancellation()
                        
                        await MainActor.run {
                            self.filteredData = result
                        }
                    }
                }
        }
    }
}

#Preview {
    ContentView()
}
