# Swift Semantic Search 🍏

![Preview](https://github.com/ashvardanian/ashvardanian/blob/master/repositories/SwiftSemanticSearch.jpg?raw=true#center)

This Swift demo app shows you how to build real-time native AI-powered apps for Apple devices using Unum's Swift libraries and quantized models.
Under the hood, it uses [UForm](https://github.com/unum-cloud/uform) to understand and "embed" multimodal data, like multilingual texts and images, processing them on the fly from a camera feed.
Once the vector embeddings are computed, it uses [USearch](https://github.com/unum-cloud/usearch) to provide a real-time search over the semantic space.
That same engine also enables geo-spatial search over the coordinates of the images and has been shown to scale even to 100M+ entries on an 🍏 iPhone easily.

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

The demo app is capable of text-to-image and image-to-image search and uses `vmanot/Media` libra to fetch the camera feed, embedding, and searching frames on the fly.
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

After that, fire up the Xcode project and run the app on your fruity device!

---

Links:

- [Preprocessing datasets](https://github.com/ashvardanian/SwiftSemanticSearch/blob/main/images.ipynb)
- [USearch Swift docs](https://unum-cloud.github.io/usearch/swift)
- [Form Swift docs](https://unum-cloud.github.io/uform/swift)

