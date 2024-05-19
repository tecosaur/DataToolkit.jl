module TiffImagesExt

using TiffImages
import DataToolkitCommon: _read_tiff, _write_tiff

_read_tiff(from::IO) =
    TiffImages.load(from)

_write_tiff(dest::IO, info::AbstractMatrix) =
    TiffImages.save(dest, info)

end
