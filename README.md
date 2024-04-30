#  Swift Semantic Search 🍏

![Preview](https://github.com/ashvardanian/ashvardanian/blob/master/repositories/SwiftSemanticSearch.jpg?raw=true#center)

This Swift demo app shows you how to build real-time native AI-powered apps for Apple devices using Unum's Swift libraries.
Under the hood, it uses [UForm](https://github.com/unum-cloud/uform) to understand and "embed" multimodal data, like images, multilingual texts, and 🔜 videos.
Once the embeddings are computed, it uses [USearch](https://github.com/unum-cloud/usearch) to provide real-time search over the semantic space.
That same engine also enables geo-spatial search over the coordinates of the images, and has been to shown to easily scale even to 100M+ entries on an iPhone 🍏

<table>
  <tr>
    <td>
      <img src="https://github.com/ashvardanian/ashvardanian/blob/master/demos/SwiftSemanticSearch-Dog.gif?raw=true" alt="SwiftSemanticSearch demo Dog">
    </td>
    <td>
      <img src="https://github.com/ashvardanian/ashvardanian/blob/master/demos/SwiftSemanticSearch-Flowers.gif?raw=true" alt="SwiftSemanticSearch demo with Flowers">
    </td>
  </tr>
</table>

The demo app is capable of text-to-image and image-to-image search, can uses `vmanot/Media` to fetch the camera feed, embedding and searching frames on the fly.
To test the demo:

```bash
# Clone the repo
git clone https://github.com/ashvardanian/SwiftSemanticSearch.git

# Change directory & decompress the images dataset.zip, which brings:
#   - `images.names.txt` with newline-separated image names
#   - `images.uform3-image-text-english-small.fbin` - precomputed embeddings
#   - `images.uform3-image-text-english-small.usearch` - precomputed index
#   - `images` - directory with images
cd SwiftSemanticSearch
unzip dataset.zip
```

After that, fire up the Xcode project and run the app on your iPhone 🍏 or iPad 🍏
