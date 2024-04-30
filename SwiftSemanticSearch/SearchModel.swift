//
// Copyright (c) Ash Vardanian
//

import Accelerate
import Combine
import SwiftUI
import UForm
import USearch

class SearchModel: ObservableObject {
    @MainActor
    public enum StateFlag {
        case readyToShow
        case readyToSearch
    }
    
    @MainActor
    @Published
    public var state: Set<StateFlag> = []
    
    private var _loadEncodersAndIndexConcurrentlyTask: Task<Void, Error>? = nil
    private var allImageNames: [String] = []
    private var textEncoder: TextEncoder?
    private var imageEncoder: ImageEncoder?
    
    fileprivate var imageIndex: USearchIndex?
    
    private lazy var textEncoderActor = TextEncoderActor()
    private lazy var imageEncoderActor = ImageEncoderActor()
    private lazy var imageIndexActor = ImageIndexActor(searchModel: self)
    
    private var rows: UInt32 = 0
    private var columns: UInt32 = 0
    private var matrix: [Float] = []
    
    init() {
        allImageNames = loadImageNames()
        let persistedImageFilename = listFilesInImagesFolder()
        checkForMissingImages(imageNames: allImageNames, imageFiles: persistedImageFilename)
        loadMatrix()
        
        Task.detached(priority: .userInitiated) {
            await self.loadEncodersAndIndexConcurrently()
        }
    }
    
    func loadImageNames() -> [String] {
        if let filepath = Bundle.main.resourcePath?.appending("/images.names.txt") {
            do {
                let contents = try String(contentsOfFile: filepath)
                var names = contents.components(separatedBy: "\n")
                names = names.filter { !$0.isEmpty } // Removing any empty lines
                names = names.map { $0 + ".jpg" }
                print("Contains \(names.count) files in \(filepath)")
                return names
            } catch {
                print("Error reading the contents of the file: \(error)")
            }
        }
        return []
    }
    
    func listFilesInImagesFolder() -> [String] {
        if let imagesPath = Bundle.main.resourcePath?.appending("/images") {
            do {
                let fileManager = FileManager.default
                let imageFiles = try fileManager.contentsOfDirectory(atPath: imagesPath)
                print("Contains \(imageFiles.count) files in \(imagesPath)")
                return imageFiles
            } catch {
                print("Error while enumerating files in /images: \(error.localizedDescription)")
            }
        }
        return []
    }
    
    func checkForMissingImages(imageNames: [String], imageFiles: [String]) {
        // Ensure loadImageNames() and listFilesInImagesFolder() have been called
        guard !imageNames.isEmpty && !imageFiles.isEmpty else { return }
        
        // Convert imageNames to just the filenames (in case they have path components)
        let imageNamesSet = Set(imageNames.map { URL(fileURLWithPath: $0).lastPathComponent })
        
        // Convert imageFiles to a set
        let imageFilesSet = Set(imageFiles)
        
        // Find the difference
        let missingFiles = imageNamesSet.subtracting(imageFilesSet)
        if missingFiles.isEmpty {
            print("All files are present.")
        } else {
            print("Missing files: \(missingFiles)")
        }
    }
    
    func loadMatrix() {
        
        guard let filePath = Bundle.main.resourcePath?.appending("/images.uform3-image-text-english-small.fbin") else {
            print("Matrix file not found.")
            return
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                var offset = 0
                // Extract rows and columns from the beginning of the file
                let rowsPointer = bytes.baseAddress!.assumingMemoryBound(to: UInt32.self)
                rows = rowsPointer.pointee
                offset += MemoryLayout<UInt32>.size
                
                let columnsPointer = bytes.baseAddress!.advanced(by: offset).assumingMemoryBound(to: UInt32.self)
                columns = columnsPointer.pointee
                offset += MemoryLayout<UInt32>.size
                
                let rawMatrix = UnsafeBufferPointer<Float>(start: bytes.baseAddress!.advanced(by: offset).assumingMemoryBound(to: Float.self), count: rows * columns)
                
                // Now that we know the size of the matrix, allocate it
                matrix = Array(rawMatrix)
                
                print("Loaded a \(rows) x \(columns) matrix")
            }
        } catch {
            print("Error loading matrix file: \(error)")
        }
    }
    
    @MainActor
    func loadEncodersAndIndexConcurrently() async {
        do {
            _ = state.insert(.readyToShow)
            
            _loadEncodersAndIndexConcurrentlyTask = Task.detached(priority: .userInitiated) {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask(priority: .userInitiated) {
                        try await self.textEncoderActor.load()
                    }
                    
                    group.addTask(priority: .userInitiated) {
                        try await self.imageEncoderActor.load()
                    }
                    
                    group.addTask(priority: .userInitiated) {
                        try await self.imageIndexActor.index(
                            matrix: self.matrix,
                            rows: self.rows,
                            columns: self.columns
                        )
                    }
                    
                    try await group.waitForAll()
                }
            }
            
            try await _loadEncodersAndIndexConcurrentlyTask?.value
            
            self.textEncoder = await self.textEncoderActor.textEncoder
            self.imageEncoder = await self.imageEncoderActor.imageEncoder
            
            _ = state.insert(.readyToSearch)
        } catch {
            assertionFailure(String(describing: error))
        }
    }
    
    func filter(withText query: String) async throws -> [String] {
        
        if query.isEmpty {
            return allImageNames
        }
        
        print("Wants to filter images by \(query)")
        
        
        guard let textEncoder = textEncoder, let imageIndex = imageIndex else {
            return []
        }
        
        do {
            // Get the embedding for the query.
            let queryEmbedding = try textEncoder.encode(query).asFloats()
            let results = imageIndex.search(vector: queryEmbedding, count: 100)
            
            await Task.yield()
            
            try Task.checkCancellation()

            // Calculate the cosine similarity of each image's embedding to the query's embedding.
            let similarityScores = zip(results.0, results.1).map { (key: USearchKey, similarity: Float32) in
                let imageName = allImageNames[Int(key)]
                return (imageName, similarity)
            }
            
            await Task.yield()

            try Task.checkCancellation()
            
            // Sort the images by descending similarity scores.
            return similarityScores
                .sorted { $0.1 < $1.1 }
                .map { $0.0 }
            
        } catch {
            print("Error processing embeddings: \(error)")
            return []
        }
    }
}

extension SearchModel {
    @MainActor
    func filter(
        withImage query: CGImage
    ) async throws -> [String] {
        try await _loadEncodersAndIndexConcurrentlyTask?.value
        
        guard let imageEncoder = imageEncoder, let imageIndex = imageIndex else {
            return []
        }
        
        do {
            // Get the embedding for the query.
            let queryEmbedding = try imageEncoder.encode(query).asFloats()
            let results = imageIndex.search(vector: queryEmbedding, count: 100)
            
            // Calculate the cosine similarity of each image's embedding to the query's embedding.
            let similarityScores = zip(results.0, results.1).map { (key: USearchKey, similarity: Float32) in
                let imageName = allImageNames[Int(key)]
                return (imageName, similarity)
            }
            
            // Sort the images by descending similarity scores.
            return similarityScores
                .sorted { $0.1 < $1.1 }
                .map { $0.0 }
            
        } catch {
            print("Error processing embeddings: \(error)")
            return []
        }
    }
}

// MARK: - Auxiliary

// Define separate actors for encapsulating each resource, that can operate concurrently
actor TextEncoderActor {
    var textEncoder: TextEncoder?
    
    func load() async throws {
        self.textEncoder = try await TextEncoder(modelName: "unum-cloud/uform3-image-text-english-small")
    }
}

actor ImageEncoderActor {
    var imageEncoder: ImageEncoder?
    
    func load() async throws {
        self.imageEncoder = try await ImageEncoder(modelName: "unum-cloud/uform3-image-text-english-small")
    }
}

actor ImageIndexActor {
    private var searchModel: SearchModel
    
    init(searchModel: SearchModel) {
        self.searchModel = searchModel
    }
    
    @usableFromInline
    func index(
        matrix: [Float],
        rows: UInt32,
        columns: UInt32
    ) async throws {
        let indexPath = Bundle.main.resourcePath!.appending("/images.uform3-image-text-english-small.usearch")
        let indexURL = URL(fileURLWithPath: indexPath)
        
        let imageIndex = USearchIndex.make(
            metric: .cos,
            dimensions: columns,
            connectivity: 0,
            quantization: .F16
        )
        
        if FileManager.default.fileExists(at: indexURL) {
            imageIndex.load(path: indexPath)
        } else {
            let _ = imageIndex.reserve(rows)
            
            let columns = Int(columns)
            
            await (0..<Int(rows)).concurrentForEach { (row: Int) in
                let range: Range<Int> = Int(row * columns)..<Int((row + 1) * columns)
                let _ = imageIndex.add(key: UInt64(row), vector: matrix[range])
            }
            
            imageIndex.save(path: indexPath)
        }
        
        searchModel.imageIndex = imageIndex
    }
}

// MARK: - Helpers

extension Sequence {
    @_transparent
    @_specialize(where Self == Range<Int>, Element == Int)
    public func concurrentForEach(
        @_implicitSelfCapture _ operation: @escaping @Sendable (Element) async -> Void
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for element in self {
                group.addTask {
                    await operation(element)
                }
            }
            
            await group.waitForAll()
        }
    }
}
