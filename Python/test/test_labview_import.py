
import os
import subprocess

import pytest

from silverlabnwb import NwbFile
from silverlabnwb.nwb_util import compare_to_signature


# Where to look for large raw data files
DATA_PATH = os.environ.get('SILVERLAB_DATA_DIR', '')
# Where reference data is kept
REF_PATH = os.path.join(os.path.dirname(__file__), 'data')


@pytest.mark.skipif(
    os.environ.get('SILVERLAB_GEN_REF', '0') == '0',
    reason="SILVERLAB_GEN_REF not set or set to 0")
def test_generate_signatures():
    """A 'test' to generate reference data for the tests below."""
    def generate(expt):
        cmd = [
            'python', '-m', 'nwb.h5diffsig',
            os.path.join(DATA_PATH, expt + '.nwb'),
            '-Na'
        ]
        output_path = os.path.join(REF_PATH, expt + '.sig')
        with open(output_path, 'wt') as output:
            subprocess.check_call(cmd, stdout=output)
    # Cut-down samples
    generate('sample_pointing_videos_161215_15_34_21')
    generate('sample_pointing_fred_170317_10_11_01')
    generate('sample_miniscan_fred_170322_14_06_43')
    # Full datasets
    generate('161215_15_58_52')
    generate('161215_15_34_21')
    generate('170317_10_11_01')
    generate('170322_14_06_43')


def do_import_test(tmpdir, expt, add_suffix=False):
    """Helper method for tests below."""
    nwb_path = os.path.join(str(tmpdir), expt + '.nwb')
    labview_path = os.path.join(DATA_PATH, expt + ' FunctAcq' if add_suffix else expt)
    sig_path = os.path.join(REF_PATH, expt + '.sig')

    with NwbFile(nwb_path, mode='w') as nwb:
        nwb.import_labview_folder(labview_path)
    assert compare_to_signature(nwb_path, sig_path, ignore_external_file=True)


@pytest.mark.skipif(
    not os.path.isdir(DATA_PATH),
    reason="raw data folder '{}' not present".format(DATA_PATH))
class TestSampleImports(object):

    def test_hana_video(self, tmpdir):
        do_import_test(tmpdir, 'sample_pointing_videos_161215_15_34_21')

    def test_fred_pointing(self, tmpdir):
        do_import_test(tmpdir, 'sample_pointing_fred_170317_10_11_01')

    def test_fred_miniscan(self, tmpdir):
        do_import_test(tmpdir, 'sample_miniscan_fred_170322_14_06_43')


@pytest.mark.skipif(
    not os.path.isdir(DATA_PATH),
    reason="raw data folder '{}' not present".format(DATA_PATH))
@pytest.mark.skipif(
    os.environ.get('SILVERLAB_SKIP_IMPORTS', '1') == '1',
    reason="SILVERLAB_SKIP_IMPORTS set to 1")
class TestFullImporting(object):

    def test_hana(self, tmpdir):
        """A sample dataset from Hana with no videos."""
        do_import_test(tmpdir, '161215_15_58_52', True)

    def test_hana_video(self, tmpdir):
        """A sample dataset from Hana with videos."""
        do_import_test(tmpdir, '161215_15_34_21', True)

    def test_fred_pointing(self, tmpdir):
        """A sample dataset from Fred with pointing mode data."""
        do_import_test(tmpdir, '170317_10_11_01', True)

    def test_fred_patch(self, tmpdir):
        """A sample dataset from Fred with miniscans."""
        do_import_test(tmpdir, '170322_14_06_43', True)
