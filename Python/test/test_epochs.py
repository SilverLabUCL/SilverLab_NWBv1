"""Testing that epochs are calculated and added correctly."""

import os

import h5py
import numpy as np
import yaml

from silverlabnwb import NwbFile


def compare_hdf5(nwb_path, expected_yaml_path):
    """Test utility method comparing a generated NWB file against expected contents.

    As a side-effect, checks that we can open files for reading with our API.
    """
    with open(expected_yaml_path, 'r') as f:
        expected = yaml.load(f)
    with NwbFile(nwb_path, mode='r') as nwb:
        compare_group(nwb.hdf_file, expected, '')


def compare_group(nwb_group, expected_group, path):
    """Check that an HDF5 group has the expected contents."""
    for key in expected_group:
        expected_value = expected_group[key]
        if key == '_attrs':
            # Check attributes of the node
            compare_attributes(nwb_group, expected_value, path)
        elif key == '_value':
            # nwb_group should actually be a dataset
            assert isinstance(nwb_group, h5py.Dataset)
            compare_dataset(nwb_group, expected_value, path)
        elif key == '_link':
            # This group should be a soft link to another
            link = nwb_group.get(nwb_group.name, getlink=True)
            assert isinstance(link, h5py.SoftLink)
            assert link.path == expected_value
        else:
            assert key in nwb_group
            if isinstance(expected_value, dict):
                compare_group(nwb_group[key], expected_value, path + '/' + key)
            else:
                compare_dataset(nwb_group[key], expected_value, path + '/' + key)


def compare_attributes(nwb_node, expected_attrs, path):
    """Check that an HDF5 node has the expected attributes."""
    for attr_name, attr_value in expected_attrs.items():
        assert attr_name in nwb_node.attrs
        compare_dataset(nwb_node.attrs[attr_name], attr_value, path + '/@' + attr_name)


def compare_dataset(nwb_dataset, expected_value, path):
    """Check that an HDF5 dataset has the expected contents.

    Note that this gets used for both 'normal' datasets and attribute values.
    In the former case we must access the numpy value with .value; in the latter
    nwb_dataset is already the numpy value.
    """
    if hasattr(nwb_dataset, 'value'):
        # Extract the actual data from the dataset
        nwb_dataset = nwb_dataset.value
    if isinstance(expected_value, str):
        if isinstance(nwb_dataset, np.bytes_):
            # Convert to string so we can compare naturally
            nwb_dataset = nwb_dataset.decode('UTF-8')
        assert nwb_dataset == expected_value, 'Mismatch at {}'.format(path)
    elif isinstance(expected_value, (int, float)):
        assert abs(nwb_dataset - expected_value) < 1e-6, 'Mismatch at {}'.format(path)
    elif isinstance(expected_value, list):
        expected_value = np.array(expected_value)
        assert nwb_dataset.shape == expected_value.shape, 'Mismatch at {}'.format(path)
        if expected_value.dtype.kind == 'U':
            expected_value = expected_value.astype('S')
        if nwb_dataset.dtype.kind in ['O', 'U']:
            nwb_dataset = nwb_dataset.astype('S')
        if expected_value.dtype.kind == 'S':
            np.testing.assert_array_equal(nwb_dataset, expected_value)
        else:
            np.testing.assert_allclose(nwb_dataset, expected_value, atol=1e-6)
    else:
        assert 0, 'Unexpected expected_value {!r}'.format(expected_value)


def test_epochs(tmpdir, capfd):
    data_path = os.path.join(os.path.dirname(__file__), 'data')
    import silverlabnwb
    silverlabnwb.metadata.set_conf_dir(data_path)
    fname = "test_epochs.nwb"
    with NwbFile(os.path.join(str(tmpdir), fname), mode='w') as nwb:
        speed_data, start_time = nwb.create_nwb_file(data_path, 'test_epochs')
        nwb.add_core_metadata()
        nwb.add_speed_data(speed_data, start_time)
        nwb.determine_trial_times()
    compare_hdf5(str(tmpdir.join(fname)), os.path.join(data_path, 'expected.yaml'))
