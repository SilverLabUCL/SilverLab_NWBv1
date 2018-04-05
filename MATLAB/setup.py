# A little Python script to set the Matlab paths correctly for using NWB

import argparse
import os
import re
import sys


def munge_path(path):
    """Convert `path` to a native system path so Matlab understands it."""
    if sys.platform.startswith('win32'):
        if re.match(r'/\s/.*', path):
            path = os.path.realpath('{}:{}'.format(path[1], path[2:]))
    elif sys.platform.startswith('cygwin'):
        if re.match(r'/cygdrive/\s/.*', path):
            path = os.path.realpath('{}:{}'.format(path[10], path[11:]))
    return path


def setup_matlab(silverlab_path, nwb_api_path):
    silverlab_path = munge_path(silverlab_path)
    nwb_api_path = munge_path(os.path.join(nwb_api_path, 'matlab_bridge', 'matlab_bridge_api'))
    print('Setting up Matlab with paths:')
    print('  NWB API folder: {}'.format(nwb_api_path))
    print('  Our Matlab folder: {}'.format(silverlab_path))
    matlab_commands = [
        "pyversion '{}';".format(sys.executable),
        "addpath('{}');".format(nwb_api_path),
        "addpath(genpath('{}'));".format(silverlab_path),
        "success = savepath();",
        "if success == 1; error('Failed to save Matlab path - set manually'); else quit; end;"
    ]
    os.system('matlab -nosplash -nodesktop -r "{}"'.format(' '.join(matlab_commands)))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Setup Matlab for NWB use.')
    parser.add_argument('nwb_api_path',
                        help='path to the NWB API sources')
    args = parser.parse_args()
    our_matlab_path = os.path.join(os.path.dirname(__file__), 'source')
    setup_matlab(our_matlab_path, args.nwb_api_path)
