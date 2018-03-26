'''
Command-line entrypoints for the Silver Lab pipeline.
'''

import argparse

from .nwb_file import NwbFile
from .metadata_gui import run_editor


def import_labview():
    """Command line script to import a Labview folder to NWB format."""
    parser = argparse.ArgumentParser(description='Import Labview to NWB.')
    parser.add_argument('nwb_path',
                        help='path to the NWB file to write')
    parser.add_argument('labview_path',
                        help='path to the Labview folder to import')
    parser.add_argument('--no-gui', dest='gui', action='store_false',
                        help="don't show a GUI to edit metadata; just reuse the last session")
    parser.add_argument('--check-sig', action='store_true',
                        help="check the generated NWB file against an existing signature."
                        " This expects a .sig file to be present next to the .nwb file.")
    args = parser.parse_args()

    if args.gui:
        run_editor()

    with NwbFile(args.nwb_path, mode='w') as nwb:
        nwb.import_labview_folder(args.labview_path)

    if args.check_sig:
        import os
        sig_path = os.path.splitext(args.nwb_path)[0] + '.sig'
        if os.path.exists(sig_path):
            from .nwb_util import compare_to_signature
            print('Comparing against signature file {}'.format(sig_path))
            compare_to_signature(args.nwb_path, sig_path)
        else:
            parser.error('No signature file {} found'.format(sig_path))


def check_signature():
    """Command line script to check an NWB file against a pre-computed signature."""
    parser = argparse.ArgumentParser(description='Check an NWB file against a signature')
    parser.add_argument('nwb_path',
                        help='path to the NWB file to check')
    parser.add_argument('sig_path',
                        help='path to the signature to check against')
    args = parser.parse_args()
    from .nwb_util import compare_to_signature
    compare_to_signature(args.nwb_path, args.sig_path)
