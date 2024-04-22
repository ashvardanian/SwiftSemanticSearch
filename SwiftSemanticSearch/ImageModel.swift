//
// Copyright (c) Ash Vardanian
//

import Accelerate
import Combine
import Hub
import SwiftUI
import UForm

@globalActor
final public actor UFormActor: GlobalActor {
    static public var shared = UFormActor()
}

class ImageModel: ObservableObject {
    @MainActor
    @Published var imageNames: [String] = []
    var allImageNames: [String] = []
    @MainActor
    @Published var textModel: TextEncoder?
    
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
    
    @UFormActor
    func filteredAndSortedImages(
        query: String
    ) async throws -> [String] {
        print("Wants to filter images by \(query)")
        guard let textModel = await textModel, !query.isEmpty, let matrix = matrix else {
            return allImageNames
        }
        
        do {
            // Get the embedding for the query.
            let queryEmbedding = try textModel.forward(with: query).asFloats()
            
            // Calculate the cosine similarity of each image's embedding to the query's embedding.
            let similarityScores = await matrix.enumerated().concurrentMap { (index, imageEmbedding) -> (String, Float) in
                let imageName = allImageNames[index]
                return (imageName, vDSP.cosineSimilarity(lhs: queryEmbedding, rhs: imageEmbedding))
            }
            
            // Sort the images by descending similarity scores.
            return similarityScores
                .sorted { $0.1 > $1.1 }
                .map { $0.0 }
            
        } catch {
            print("Error processing embeddings: \(error)")
            return allImageNames
        }
    }
    
    func loadMatrix() {
        
        guard let filePath = Bundle.main.resourcePath?.appending("/images.uform-vl-english-small.fbin") else {
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
    func loadTextModel() async {
        do {
            let api = HubApi(hfToken: "")
            textModel = try await TextEncoder(
                modelName: "unum-cloud/uform3-image-text-english-small",
                hubApi: api
            )
        } catch {
            print("Error initializing TextEncoder: \(error)")
        }
    }
}

// MARK: - Internal

extension Sequence {
    public func concurrentMap<T: Sendable>(
        priority: TaskPriority? = nil,
        @_implicitSelfCapture _ transform: @Sendable @escaping (Element) async throws -> T
    ) async rethrows -> [T] {
        try await withThrowingTaskGroup(of: (Int, T).self) { group in
            enumerated().forEach { element in
                group.addTask(priority: priority) {
                    let result = try await transform(element.1)
                    
                    return (element.0, result)
                }
            }
            
            let initialCapacity = underestimatedCount
            
            var result = ContiguousArray<(Int, T)>()
            
            result.reserveCapacity(initialCapacity)
            
            for _ in 0..<initialCapacity {
                try await result.append(group.next()!)
            }
            
            while let element = try await group.next() {
                result.append(element)
            }
            
            try await group.waitForAll()
            
            return result.sorted(by: { $0.0 < $1.0 }).map({ $0.1 })
        }
    }
}

extension vDSP {
    @inlinable
    public static func cosineSimilarity<U: AccelerateBuffer>(
        lhs: U,
        rhs: U
    ) -> Double where U.Element == Double {
        let dotProduct = vDSP.dot(lhs, rhs)
        
        let lhsMagnitude = vDSP.sumOfSquares(lhs).squareRoot()
        let rhsMagnitude = vDSP.sumOfSquares(rhs).squareRoot()
        
        return dotProduct / (lhsMagnitude * rhsMagnitude)
    }
    
    @inlinable
    public static func cosineSimilarity<U: AccelerateBuffer>(
        lhs: U,
        rhs: U
    ) -> Float where U.Element == Float {
        let dotProduct = vDSP.dot(lhs, rhs)
        
        let lhsMagnitude = vDSP.sumOfSquares(lhs).squareRoot()
        let rhsMagnitude = vDSP.sumOfSquares(rhs).squareRoot()
        
        return dotProduct / (lhsMagnitude * rhsMagnitude)
    }
}
