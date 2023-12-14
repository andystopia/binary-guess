# File Type from Sequential bytes


## Idea

I saw this idea couple weeks back, hopefully
I'm remembering it correctly.

Basically what you want to do is read in a file,
Construct a windowing iterator over two bytes
at a time, and then you use look up one byte
as the row of the image and you use the other byte
as a col. Add one to the value addresed by these to indexes.
in the image.

You should generate an image, and different file formats
should have different appearances, which you could train a
CNN on.

The image should be black to begin with.
The image should be normalized to [0, 1], and
then displayed by rendering

## Conclusion

I wrote a viewer, and considering even
I couldn't figure out a strong pattern that identifies
files, I'm not sure I could debug a CNN that's not training
correctly. So I'm shelving this project as a failed experiment, 
but it was interesting none-the-less.
