//
// Copyright (c) Ash Vardanian
//

import Accelerate
import Combine
import SwiftUI

import UForm
import USearch

@globalActor
final public actor SearchActor: GlobalActor {
    static public var shared = SearchActor()
}

class SearchModel: ObservableObject {

    @Published var allImageNames: [String] = []
    @Published var statusMessage = ""

    @MainActor
    @Published var textEncoder: TextEncoder?
    @MainActor
    @Published var imageEncoder: ImageEncoder?
    @MainActor
    @Published var imageIndex: USearchIndex?

    var rows: UInt32 = 0
    var columns: UInt32 = 0
    var matrix: [[Float]]?
    
    init() {
        allImageNames = loadImageNames()
        let persistedImageFilename = listFilesInImagesFolder()
        checkForMissingImages(imageNames: allImageNames, imageFiles: persistedImageFilename)
        loadMatrix()
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
    
    @SearchActor
    func filteredAndSortedImages(
        query: String
    ) async throws -> [String] {
        
        if query.isEmpty {
            return allImageNames
        }
        
        print("Wants to filter images by \(query)")
        guard let textEncoder = await textEncoder, let imageIndex = await imageIndex else {
            return []
        }
        
        do {
            // Get the embedding for the query.
            let queryEmbedding = try textEncoder.forward(with: query).asFloats()
            let results = imageIndex.search(vector: queryEmbedding, count: 100)
            
            // Calculate the cosine similarity of each image's embedding to the query's embedding.
            let similarityScores = zip(results.0, results.1).map { (key: USearchKey, similarity: Float32) in
                let imageName = allImageNames[Int(key)]
                return (imageName, similarity)
            }
            
            // Sort the images by descending similarity scores.
            return similarityScores
                .sorted { $0.1 > $1.1 }
                .map { $0.0 }
            
        } catch {
            print("Error processing embeddings: \(error)")
            return []
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
                
                // Now that we know the size of the matrix, allocate it
                matrix = Array(repeating: Array(repeating: 0, count: Int(columns)), count: Int(rows))
                
                // Extract matrix data
                let floatPointer = bytes.baseAddress!.advanced(by: offset).assumingMemoryBound(to: Float.self)
                for row in 0..<Int(rows) {
                    for col in 0..<Int(columns) {
                        matrix![row][col] = floatPointer[row * Int(columns) + col]
                    }
                }
                print("Loaded a \(rows) x \(columns) matrix")
            }
        } catch {
            print("Error loading matrix file: \(error)")
        }
    }
    
    @MainActor
    func loadTextEncoder() async {
        do {
            textEncoder = try await TextEncoder(modelName: "unum-cloud/uform3-image-text-english-small")
        } catch {
            print("Error initializing TextEncoder: \(error)")
        }
    }

    @MainActor
    func loadImageEncoder() async {
        do {
            statusMessage = "Loading image encoder..."
            imageEncoder = try await ImageEncoder(modelName: "unum-cloud/uform3-image-text-english-small")
        } catch {
            print("Error initializing ImageEncoder: \(error)")
        }
        statusMessage = ""
    }
    
    @MainActor
    func indexImages() async {
        do {
            imageIndex = USearchIndex.make(metric: .cos, dimensions: columns, connectivity: 0, quantization: .F16)
            let _ = imageIndex!.reserve(rows)
            for row in 0..<Int(rows) {
                let _ = imageIndex!.add(key: UInt64(row), vector: matrix![row])
            }
        } catch {
            print("Error initializing USearchIndex: \(error)")
        }
    }
    
    @MainActor
    func loadEncodersAndIndex() async {
        async let loadText: () = loadTextEncoder()
        async let loadImage: () = loadImageEncoder()
        async let index: () = indexImages()

        // Await all tasks here, they run concurrently
        _ = await (loadText, loadImage, index)
    }
}
