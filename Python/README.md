# Python API for NWB use in the Silver Lab

This Python package 'silverlabnwb' simplifies access to NWB data for typical Silver Lab experiments,
and converts data from Labview format into NWB.
It provides a few command-line utilities, as well as supporting access from other Python software.

## Installation

Our [installation script](../README.md) will install the SilverLabNwb package into a conda environment,
by default called `nwb`.
You need to activate this environment each time you want to use the package,
using one of the following commands depending on your system.
(These all assume Anaconda has been installed as the default Python;
if not you will need to provide the full path to its `activate` script.)

Linux, Mac OS, and Windows with git-bash:
``` sh
source activate nwb
```

Windows with PowerShell or the default `cmd` prompt:
``` sh
activate nwb
```

## Usage

Two main programs are provided: `labview2nwb` and `nwb_metadata_editor`.

`labview2nwb` imports Labview data to the NWB format.
You need to provide it the path to the NWB file to create,
and the path to the folder containing Labview data.
At present it assumes that video data is in a folder adjacent to the Labview data;
this will be made more flexible in the future.

For more details on usage run with the `-h` flag, i.e.
``` sh
labview2nwb -h
```

By default the import process will start by running a simple graphical editor,
allowing you to input metadata required or recommended by the NWB format,
but that is not available within the Labview data folder.

`nwb_metadata_editor` runs the metadata editor in standalone mode.
It is useful for setting up details of new researchers or new experiments,
that can then be used quickly when importing experiment data.

## Python library usage

The main class is `silverlabnwb.NwbFile` defined in `nwb_file.py`.
All its methods are documented with docstrings.

Quick examples:

``` python
from silverlabnwb import NwbFile

# Write a new file
with NwbFile(nwb_path, mode='w') as nwb:
    nwb.import_labview_folder(labview_path)

# Read an existing file
with NwbFile(nwb_path) as nwb:
    print('Opened NWB with ID {}'.format(nwb['/identifier']))
```

## Development

Installing the package with the `-e` flag to `pip` in the install script means it is installed in 'developer' mode,
so that changes you make to the package sources are immediately reflected in the installed package.

To run the automated tests, do:

``` sh
pip install -r requirements/test.txt  # First time only
pytest
```

There is also a utility script `nwb_check_signature` which checks an NWB file against a precomputed signature.
To generate a signature from an NWB file, use
``` sh
python -m nwb.h5diffsig /path/to/nwb_file.nwb -Na > /path/to/signature.sig
```
