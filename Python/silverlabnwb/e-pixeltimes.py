# NWB extension to store per-pixel time offsets for TwoPhotonSeries and RoiResponseSeries.
# Created at the Silver Lab, UCL, UK.

{"fs": {"pixeltimes": {

"info": {
    "name": "Per-pixel time offsets extension",
    "version": "1.0.0",
    "date": "Feb 22, 2017",
    "author": "Jonathan Cooper",
    "contact": "j.p.cooper@ucl.ac.uk",
    "description": ("NWB extension to store per-pixel time offsets for AOL-acquired data."
                    " Due to the properties of the AOL microscope, each pixel in a 2d image,"
                    " or in an ROI, is acquired at a slightly different time. A single "
                    " timestamp per ROI or image plane is therefore misleading."
                    " This extension adds a pixel_time_offsets dataset to RoiResponseSeries"
                    " and TwoPhotonSeries recording the offset from the frame timestamp for"
                    " each pixel.")
},

"schema": {
    "<RoiResponseSeries>/": {
        "description": "Extension to add a roi_time_offsets dataset.",
        "roi_time_offsets?": {
            "description": ("The offset from the frame timestamp at which each ROI was acquired."
                            " Note that the offset is not time-varying, i.e. it is the same for"
                            " each frame. These offsets are given in the same units as for the"
                            " timestamps array, i.e. seconds."),
            "data_type": "float64!",
            "dimensions": ["num_ROIs"]
        }
    },
    "<TwoPhotonSeries>/": {
        "description": "Extension to add a pixel_time_offsets dataset.",
        "pixel_time_offsets?": {
            "description": ("The offset from the frame timestamp at which each pixel was acquired."
                            " Note that the offset is not time-varying, i.e. it is the same for"
                            " each frame. These offsets are given in the same units as for the"
                            " timestamps array, i.e. seconds."),
            "link": {"target_type": "pixel_time_offsets", "allow_subclasses": False},
            "data_type": "float64!"
        }
    },
    "<roi_name>/*": {
        "pixel_time_offsets": {
            "description": ("The offset from the frame timestamp at which each pixel in this ROI"
                            " was acquired."
                            " Note that the offset is not time-varying, i.e. it is the same for"
                            " each frame. These offsets are given in the same units as for the"
                            " timestamps array, i.e. seconds."),
            "data_type": "float64!",
            "dimensions": [["y"], ["y", "x"]]
        }
    }
}
}}}