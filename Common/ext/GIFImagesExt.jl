module GIFImagesExt

using GIFImages
import DataToolkitCommon: _read_gif, _write_gif

_read_gif(fromfile::String) =
    GIFImages.gif_decode(fromfile)

_write_gif(destfile::String, info::Matrix) =
    GIFImages.gif_encode(destfile, info)

end
