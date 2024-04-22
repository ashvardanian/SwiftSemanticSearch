//
//  ContentView.swift
//  SwiftSemanticSearch
//
//  Created by Ash Vardanian on 4/13/24.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var imageModel: ImageModel
    @State private var searchText = ""

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationView {
            VStack {
                TextField("Search", text: $searchText)
                    .padding()
                    .border(Color(UIColor.separator))

                ScrollView {
                    if imageModel.textModel == nil {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(imageModel.filteredAndSortedImages(query: searchText), id: \.self) { imageName in
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
            }
            .navigationBarTitle("UForm + USearch 4 Swift", displayMode: .inline)
        }
    }
}

#Preview {
    ContentView()
}
