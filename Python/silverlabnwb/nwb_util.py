"""Standalone utility methods for working with NWB files."""

import difflib
import os
import six
import sys

from nwb import h5diffsig

try:
    from contextlib import redirect_stdout
except ImportError:
    # Python 2 support
    from contextlib import contextmanager

    @contextmanager
    def redirect_stdout(new_target):
        old_target, sys.stdout = sys.stdout, new_target
        try:
            yield new_target
        finally:
            sys.stdout = old_target


def strip_ignorables(signature, ignore_external_file=False):
    """Strip ignorable text from the given NWB signature.

    The NWB signature algorithm can place items that trivially vary (like file paths,
    modification times) within <% ... %> tags. This method modifies the supplied list
    of strings to strip these out from individual entries.

    :param signature: the signature to strip
    :param ignore_external_file: if True, also strip external file paths
    """
    import re
    ignorable = re.compile(r'<%.*?%>')
    if ignore_external_file:
        ext_re = re.compile(r"( *\d+\. '/.+/external_file): dtype=")
    for i, line in enumerate(signature):
        signature[i] = ignorable.sub('<% ... %>', line)
        if ignore_external_file:
            m = ext_re.match(signature[i])
            if m:
                signature[i] = m.group(1) + ': value ignored'


def get_signature(nwb_path):
    """Get the signature for an NWB file as a string.

    :param nwb_path: path to the NWB file
    """
    assert os.path.exists(nwb_path), 'NWB file {} does not exist'.format(nwb_path)
    h5diffsig.filter_nwb = True
    h5diffsig.alpha_sort = True
    h5diffsig.single_file = True
    output_buffer = six.StringIO()
    with redirect_stdout(output_buffer):
        h5diffsig.diff_files(nwb_path, nwb_path)
    return output_buffer.getvalue().splitlines(True)


def compare_to_signature(nwb_path, sig_path, ignore_external_file=False):
    """Compare an NWB file to an existing signature.

    The NWB API has functionality to compute a 'signature' for an NWB file,
    and compare two files using this. Here we exploit the signature generation
    capabilities to compare a new NWB file against a pre-computed signature.

    :param nwb_path: path to the NWB file
    :param sig_path: path to file containing the signature
    :param ignore_external_file: whether to ignore external file paths when comparing
    """
    assert os.path.exists(sig_path), 'Signature file {} does not exist'.format(sig_path)
    expected_sig = open(sig_path, 'r').readlines()
    strip_ignorables(expected_sig, ignore_external_file=ignore_external_file)
    actual_sig = get_signature(nwb_path)
    strip_ignorables(actual_sig, ignore_external_file=ignore_external_file)
    match = expected_sig == actual_sig
    if match:
        print('Signature matches')
    else:
        diff = difflib.unified_diff(
            expected_sig, actual_sig,
            fromfile=sig_path, tofile=nwb_path)
        for line in diff:
            six.print_(line, end='')
    return match
