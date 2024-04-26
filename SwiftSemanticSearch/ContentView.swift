//
//  ContentView.swift
//  SwiftSemanticSearch
//
//  Created by Ash Vardanian on 4/13/24.
//

import SwiftUIX

struct ContentView: View {
    @EnvironmentObject var searchModel: SearchModel
    @State private var searchText: String = ""
    @State var filteredData: [String] = []
    @State var searchTask: Task<Void, Error>?
    
    var body: some View {
        NavigationView {
            VStack {
                TextField("Search with UForm & USearch", text: $searchText)
                    .padding()
                    .multilineTextAlignment(.center)
                    .alignmentGuide(HorizontalAlignment.center)
                
                searchResultsView
            }
            .navigationBarTitle("Unum ❤️ Apple", displayMode: .inline)
            .onAppear {
                runInitialFilter()
            }
        }
    }
    
    private var searchResultsView: some View {
        GeometryReader { geometry in
            let imageOptimalWidth = 250.0
            let minColumns = 3
            
            // Dynamically calculate the number of columns based on the available width,
            // so that the images are displayed in a grid layout without any empty space
            let numberOfColumns = Int(max(minColumns, Int(geometry.size.width / imageOptimalWidth)))
            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: numberOfColumns)
            let width = geometry.size.width / CGFloat(numberOfColumns)
            ScrollView {
                if searchModel.textEncoder == nil {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    LazyVGrid(columns: columns, spacing: 0) {
                        ForEach(filteredData, id: \.self) { imageName in
                            if let imagePath = Bundle.main.path(forResource: imageName, ofType: nil, inDirectory: "images") {
                                Image(uiImage: UIImage(contentsOfFile: imagePath) ?? UIImage())
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: width, height: width)
                                    .onTapGesture {
                                        print("\(imageName) was tapped")
                                    }
                            }
                        }
                    }
                }
                
            }
        }
        .withChangePublisher(for: searchText) { publisher in
            publisher
                .receive(on: DispatchQueue.main)
                .handleEvents(receiveOutput: { _ in
                    // self.filteredData = []
                })
                .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
                .sink { (text: String) in
                    searchTask?.cancel()
                    searchTask = Task.detached(priority: .userInitiated) {
                        let result = try await searchModel.filteredAndSortedImages(query: text)
                        try Task.checkCancellation()
                        await MainActor.run {
                            self.filteredData = result
                        }
                    }
                }
        }
    }
    private func runInitialFilter() {
        searchTask?.cancel()
        searchTask = Task {
            let result = try await searchModel.filteredAndSortedImages(query: searchText)
            try Task.checkCancellation()
            self.filteredData = result
        }
    }
    
}

#Preview {
    ContentView()
}
