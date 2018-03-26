# NWB extension to store LabView header (.ini) information within the /general group.
# Created at the Silver Lab, UCL, UK.

{"fs": {"labview": {

"info": {
    "name": "LabView header storage extension",
    "version": "1.0.0",
    "date": "Feb 16, 2017",
    "author": "Jonathan Cooper",
    "contact": "j.p.cooper@ucl.ac.uk",
    "description": ("NWB extension to store raw metadata from LabView header (.ini) files."
        " While some of this information also maps to standard NWB fields,"
        " it is useful to retain the raw fields for provenance.")
},

"schema": {
    "labview_header": {
        "description": ("LabView header fields represented as a 3-column text array."
            " The columns represent 'Section', 'Field name' and 'Field value'."),
        "data_type": "text",
        # TODO: The actual type used by h5py/numpy can be 'object' because these are variable length strings,
        # so this gives a warning. But 'object isn't a valid type for the NWB API, and text is more appropriate anyway!
        "dimensions": ["total_num_fields", "cols"],
        "cols" : {  # definition of dimension "cols"
            "type": "structure",
            "components": [
                { "alias": "Section",     "unit": "N/A" },
                { "alias": "Field name",  "unit": "N/A" },
                { "alias": "Field value", "unit": "N/A" } ] }
    },
    "/general/": {
        "description": "Extension to core general to add labview_header.",
        "include": {  "labview_header": {}},
    },
}
}}}