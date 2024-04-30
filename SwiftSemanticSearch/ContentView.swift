//
// Copyright (c) Ash Vardanian
//

import Media // For camera - https://github.com/vmanot/Media
import SwiftUIX // For debounce - https://github.com/vmanot/SwiftUIX

enum SearchMode: String, CaseIterable, Codable, Hashable, Sendable {
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
            VStack(spacing: 0) {
                contentForCurrentMode
                    .clipped()
                searchResultsView
                    .clipped()
            }
            .navigationBarTitle("Unum ❤️ Apple", displayMode: .inline)
            .toolbar {
                searchModeToolbar
            }
            .onAppear {
                showAll()
            }
        }
        .navigationViewStyle(.stack)
    }
    
    @ViewBuilder
    private var contentForCurrentMode: some View {
        switch searchMode {
            case .text:
                textFieldView
            case .videoStream, .image:
                MediaInputView(
                    searchMode: searchMode,
                    onImageCapture: { image in
                        showSimilar(toImage: image)
                    },
                    searchImage: searchImage,
                    onImageTap: {
                        showAll()
                        
                        searchMode = .text
                    }
                )
        }
    }
    
    private var textFieldView: some View {
        TextField("Search with UForm & USearch", text: $searchText)
            .padding()
            .multilineTextAlignment(.center)
            .alignmentGuide(HorizontalAlignment.center)
    }

    private var searchModeToolbar: some ToolbarContent {
        Group {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: toggleSearchMode) {
                    Image(systemName: iconForCurrentMode)
                }
            }
            
            ToolbarItem(placement: .navigationBarLeading) {
                progressIndicator
            }
        }
    }
    
    @ViewBuilder
    private var progressIndicator: some View {
        if !searchModel.state.isSuperset(of: [.readyToSearch, .readyToShow]) {
            ProgressView().progressViewStyle(.circular)
        }
    }
    
    private var iconForCurrentMode: String {
        switch searchMode {
            case .text: return "camera"
            case .videoStream: return "photo"
            case .image: return "text.bubble"
        }
    }
    
    private var searchResultsView: some View {
        GeometryReader(alignment: .center) { geometry in
            SearchResultsView(geometry: geometry, data: filteredData, onTap: { image in
                showSimilar(toImage: image)
                searchMode = .image
            })
        }
        .withChangePublisher(for: searchText) { publisher in
            publisher
                .receive(on: DispatchQueue.main)
                .handleEvents(receiveOutput: { _ in
                    self.filteredData = []
                })
                .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
                .sink { searchText in
                    withAnimation(.default) {
                        showSimilar(toText: searchText)
                    }
                }
        }
    }
}

extension ContentView {
    private func toggleSearchMode() {
        switch searchMode {
            case .text:
                searchMode = .videoStream
            case .videoStream, .image:
                searchMode = .text
        }
        showAll()
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
    
    @MainActor
    private func showSimilar(toImage image: UIImage) {
        guard let cgImage = image.cgImage else {
            // Handle the error: no CGImage found
            print("No CGImage available in the UIImage")
            return
        }
        
        searchTask?.cancel()
        searchImage = image
        searchTask = Task.detached(priority: .high) {
            let result = try await searchModel.filter(withImage: cgImage)
            
            try Task.checkCancellation()
            
            await MainActor.run {
                self.filteredData = result
            }
        }
    }
}

extension ContentView {
    fileprivate struct MediaInputView: View {
        let searchMode: SearchMode
        let onImageCapture: (AppKitOrUIKitImage) -> Void
        let searchImage: AppKitOrUIKitImage?
        let onImageTap: () -> Void
        
        @State private var autoCapture: Bool = true
        
        var body: some View {
            GeometryReader(alignment: .center) { geo in
                let size = min(geo.size.width, geo.size.height)
                switch searchMode {
                    case .videoStream:
                        makeCameraView(size: size)
                    case .image:
                        makeImageView(size: size)
                    default:
                        EmptyView()
                }
            }
        }
        
        private func makeCameraView(size: CGFloat) -> some View {
            CameraViewReader { (camera: CameraViewProxy) in
                CameraView(camera: .back, mirrored: false)
                    .aspectRatio(1.0, contentMode: .fill)
                    .processingFrameRate(.fps1)
                    .frame(width: .greedy, height: size)
                    .onReceive(camera._outputImageBufferPublisher?.receiveOnMainQueue()) { cvImage in
                        Task { @MainActor in
                            guard autoCapture, let image = cvImage._cgImage else {
                                return
                            }

                            self.onImageCapture(AppKitOrUIKitImage(cgImage: image))
                        }
                    }
            }
        }
        
        @ViewBuilder
        private func makeImageView(size: CGFloat) -> some View {
            if let searchImage {
                Image(image: searchImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .background(Color.almostClear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onImageTap()
                    }
            }
        }
        
        @ViewBuilder
        private func makeCaptureButton(
            camera: CameraViewProxy
        ) -> some View {
            Button {
                Task { @MainActor in
                    do {
                        autoCapture = false
                        
                        let image: AppKitOrUIKitImage = try await camera.capturePhoto()
                        
                        onImageCapture(image)
                    } catch {
                        runtimeIssue(error)
                    }
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
    }
    
    fileprivate struct SearchResultsView: View {
        let geometry: GeometryProxy
        let data: [String]
        let onTap: (AppKitOrUIKitImage) -> Void
        
        var body: some View {
            let imageOptimalWidth = 250.0
            let minColumns = 3
            
            // Dynamically calculate the number of columns based on the available width,
            // so that the images are displayed in a grid layout without any empty space
            let numberOfColumns = Int(max(minColumns, Int(geometry.size.width / imageOptimalWidth)))
            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: numberOfColumns)
            let width = geometry.size.width / CGFloat(numberOfColumns)
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(data, id: \.self) { imageName in
                        if let imagePath = Bundle.main.path(forResource: imageName, ofType: nil, inDirectory: "images"),
                           let image = UIImage(contentsOfFile: imagePath) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: width, height: width)
                                .onTapGesture {
                                    onTap(image)
                                }
                        }
                    }
                    
                }
                
            }
        }
    }
}

#Preview {
    ContentView()
}

