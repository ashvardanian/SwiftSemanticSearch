//
//  ContentView.swift
//  SwiftSemanticSearch
//
//  Created by Ash Vardanian on 4/13/24.
//

import SwiftUI

import Media // For camera - https://github.com/vmanot/Media
import SwiftUIX // For debounce - https://github.com/vmanot/SwiftUIX

enum SearchMode {
    case text, videoStream, image
}

struct ContentView: View {
    @EnvironmentObject var searchModel: SearchModel
    @State private var searchText: String = ""
    @State private var searchImage: UIImage? = nil
    @State private var searchMode: SearchMode = .text

    /// The asynchronous function to be executed in the background
    @State private var searchTask: Task<Void, Error>?
    
    /// Paths (or names) of images matching the current search query
    @State private var filteredData: [String] = []

    var body: some View {
        NavigationView {
            VStack {
                contentForCurrentMode
                searchResultsView
            }
            .navigationBarTitle("Unum ❤️ Apple", displayMode: .inline)
            .toolbar {
                searchModeToolbar
            }
            .onAppear {
                showAll()
            }
        }
    }

    @ViewBuilder
    private var contentForCurrentMode: some View {
        switch searchMode {
        case .text:
            textFieldView
        case .videoStream, .image:
            squareContent
        }
    }
    
    private var textFieldView: some View {
        TextField("Search with UForm & USearch", text: $searchText)
            .padding()
            .multilineTextAlignment(.center)
            .alignmentGuide(HorizontalAlignment.center)
    }

    @ViewBuilder
    private var squareContent: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            switch searchMode {
            case .videoStream:
                cameraView(size: size)
            case .image:
                imageView(size: size)
            default:
                EmptyView()
            }
        }
    }

    private func cameraView(size: CGFloat) -> some View {
        CameraViewReader { (cameraProxy: CameraViewProxy) in
            CameraView(camera: .back, mirrored: false)
                .frame(width: size, height: size)
                .safeAreaInset(edge: .bottom) {
                    captureButton(camera: cameraProxy) { image in
                        showSimilar(toImage: image)
                    }
                }
        }
    }

    private func imageView(size: CGFloat) -> some View {
        Image(uiImage: searchImage!)
            .resizable()
            .frame(width: size, height: size, alignment: .center) // Set the frame size and center the image
            .scaledToFill() // This will ensure the image scales down to fit within the view without stretching
            .background(Color.clear) // Use a clear background, so it doesn't affect the image view
            .contentShape(Rectangle()) // Make sure the tap gesture is recognized in the whole square area
            .onTapGesture {
                showAll()
                searchMode = .text
            }
    }

    private var searchModeToolbar: some ToolbarContent {
        Group {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: toggleSearchMode) {
                    Image(systemName: iconForCurrentMode)
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                if !searchModel.readyToShow || !searchModel.readyToSearch {
                    ProgressView().progressViewStyle(.circular)
                }
            }
        }
    }


    private func toggleSearchMode() {
        switch searchMode {
        case .text:
            searchMode = .videoStream
        case .videoStream, .image:
            searchMode = .text
        }
        showAll()
    }

    private var iconForCurrentMode: String {
        switch searchMode {
        case .text: return "camera"
        case .videoStream: return "photo"
        case .image: return "text.bubble"
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
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(filteredData, id: \.self) { imageName in
                        if let imagePath = Bundle.main.path(forResource: imageName, ofType: nil, inDirectory: "images"),
                           let image = UIImage(contentsOfFile: imagePath) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: width, height: width)
                                .onTapGesture {
                                    showSimilar(toImage: image)
                                    searchMode = .image
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
                    self.filteredData = []
                })
                .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
                .sink { showSimilar(toText: $0) }
        }
    }
    
    @ViewBuilder
    private func captureButton(camera: CameraViewProxy, onCapture: @escaping (UIImage) -> Void) -> some View {
        Button {
            Task { @MainActor in
                let image: UIImage = try! await camera.capturePhoto()
                onCapture(image)
            }
        } label: {
            Label {
                Text("Capture Photo")
            } icon: {
                Image(systemName: .cameraFill)
            }
            .font(.title2)
            .controlSize(.large)
            .padding(.small)
        }
        .buttonStyle(.borderedProminent)
    }
    
    
    private func showAll() {
        showSimilar()
    }
    
    private func showSimilar(toText query: String = "") {
        searchTask?.cancel()
        searchText = query
        searchTask = Task {
            let result = try await searchModel.filter(withText: query)
            try Task.checkCancellation()
            self.filteredData = result
        }
    }
    
    private func showSimilar(toImage image: UIImage) {
        guard let cgImage = image.cgImage else {
            // Handle the error: no CGImage found
            print("No CGImage available in the UIImage")
            return
        }
        searchTask?.cancel()
        searchImage = image
        searchTask = Task.detached(priority: .userInitiated) {
            let result = try await searchModel.filter(withImage: cgImage)
            try Task.checkCancellation()
            await MainActor.run {
                self.filteredData = result
            }
        }
    }
}

#Preview {
    ContentView()
}
