
import collections
from enum import Enum
import glob
import os
import pkg_resources
import tempfile

import av
import h5py
from nptdms import TdmsFile
import numpy as np
import pandas as pd
import six
import tifffile

from nwb import nwb_file
from nwb import nwb_utils

from . import metadata


class Modes(Enum):
    """Scanning modes supported by the AOL microscope."""
    pointing = 1
    patch = 2
    miniscan = 2
    volume = 3


class NwbFile():
    """Silver Lab wrapper for the NWB data format.data

    Designed to be used as a context manager, i.e. do something like:
    >>> with NwbFile(output_file_path) as nwb:
    ...     nwb.import_labview_folder(folder_path)

    However, there is also an explicit close() method, and this will be called
    when the object is deleted.

    Once a file has been opened, two main access mechanisms are provided:
    - nwb.nwb_file - the NWB API interface to the file
    - nwb.hdf_file - the h5py interface to the file

    You can also access nodes within the file using dictionary-style access, e.g.
    `nwb['/path/to/node']`.
    """

    SILVERLAB_NWB_VERSION = '0.1'

    def __init__(self, nwb_path, mode='r', verbose=True):
        """Create an interface to an NWB file.

        :param nwb_path: the NWB file to access
        :param mode: mode of file access. As for the NWB API, must be one of:
            'r'  - Readonly, file must exist
            'r+' - Read/write, file must exist
            'w'  - Create file, replacing if exists
            'w-' - Create file, fail if exists
            'a'  - Read/write if exists, create otherwise
        :param verbose: if True, print status information as processing happens
        """
        self.verbose = verbose
        self.nwb_file = None
        self.nwb_path = nwb_path
        assert mode in {'r', 'r+', 'w', 'w-', 'a'}
        self.nwb_open_mode = mode
        if mode in {'r', 'r+'} or (mode == 'a' and os.path.isfile(nwb_path)):
            self.open_nwb_file()

    def import_labview_folder(self, folder_path):
        """Import all data from a Labview export folder into this NWB file.

        This calls three helper methods to do most of the work, to support unit tests
        of just parts of the import code.

        This will automatically import video data only if the video folder is adjacent to
        the main labview folder, with the same name but having ' VidRec' appended. If you
        use a different layout you will need to call read_video_data() separately.

        :param folder_path: the folder to import
        """
        assert os.path.isdir(folder_path)
        folder_name = os.path.basename(folder_path)
        session_id = folder_name.split(' ')[0]  # Drop the ' FunctAcq' part
        self.log('Importing Labview session', session_id, 'from', folder_path)
        speed_data, expt_start_time = self.create_nwb_file(folder_path, session_id)
        self.add_core_metadata()
        self.import_labview_data(folder_path, folder_name, speed_data, expt_start_time)
        self.log('All data imported')

    @property
    def hdf_file(self):
        """Access the h5py interface to this NWB file."""
        assert self.nwb_file is not None
        return self.nwb_file.file_pointer

    def __getitem__(self, name):
        """Provide access to nodes within this file just like h5py does.

        :param name: full path (within the file) of the HDF5 node to access
        """
        return self.hdf_file[name]

    def open_nwb_file(self):
        """Open an existing NWB file for reading and optionally modification.

        TODO: If allowing modification then the copy_append setting defaults to True and
        we can't modify it via nwb_file.open - we'd need to call the underlying routines
        directly if we want to avoid copying the original file! However, this copying
        behaviour does guard against data corruption, so might well be desirable.
        """
        self.log("Opening file {}", self.nwb_path)
        self.nwb_file = nwb_file.open(
            self.nwb_path, mode=self.nwb_open_mode, core_spec='-',
            verbosity='all' if self.verbose else 'none')

    def create_nwb_file(self, folder_path, session_id):
        """Create a new NWB file and add general lab/session metadata.

        :param folder_path: the Labview folder to import
        :param session_id: the unique session ID for this experiment
        :returns: (speed_data, expt_start_time) for passing to import_labview_data
        """
        def rel(file_name):
            """Return the path of a file name relative to the Labview folder."""
            return os.path.join(folder_path, file_name)
        # Check we're allowed to create a new file
        if not (self.nwb_open_mode == 'w' or (self.nwb_open_mode in {'a', 'w-'} and
                                              not os.path.isfile(self.nwb_path))):
            raise ValueError('Not allowed to create/overwrite {} in mode {}'.format(
                self.nwb_path, self.nwb_open_mode))
        # Figure out the metadata required when creating a new NWB file
        self.read_user_config()
        header_fields = self.parse_experiment_header_ini(rel('Experiment Header.ini'))
        speed_data, expt_start_time = self.read_speed_data(rel('Speed_Data/Speed data 001.txt'))
        # Create the NWB file
        extensions = ["e-labview.py", "e-pixeltimes.py"]
        for i, ext in enumerate(extensions):
            extensions[i] = pkg_resources.resource_filename(__name__, ext)
        nwb_settings = {
            'file_name': self.nwb_path,
            'mode': self.nwb_open_mode,
            'start_time': expt_start_time.isoformat(),
            'identifier': nwb_utils.create_identifier(session_id),
            'description': self.session_description,
            'extensions': extensions
        }
        self.nwb_file = nwb_file.open(**nwb_settings)
        self.add_general_info('session_id', session_id)
        self.add_labview_header(header_fields)
        # For potential future backwards compatibility, store the 'version' of this API
        # that created the file.
        self.nwb_file.set_custom_dataset('/silverlab_api_version', self.SILVERLAB_NWB_VERSION)
        return speed_data, expt_start_time

    def add_core_metadata(self):
        """Add core metadata from the YAML config file to the NWB file.

        This fills in many of the fields in /general.
        """
        self.add_general_info('experimenter', self.user['name'])  # TODO: Add ORCID etc.
        self.add_general_info('experiment_description', self.experiment['description'])
        self.add_general_info('institution', 'University College London')
        self.add_general_info('lab', 'Silver Lab (http://silverlab.org)')
        self.add_devices_info()
        for field in ['data_collection', 'pharmacology', 'protocol', 'slices', 'stimulus',
                      'subject', 'surgery', 'virus', 'related_publications', 'notes']:
            if field in self.experiment:
                value = self.experiment[field]
                if isinstance(value, collections.Mapping):
                    for subfield in value:
                        self.nwb_file.set_dataset(
                            subfield, value[subfield], path='/general/' + field)
                else:
                    self.add_general_info(field, value)

    def import_labview_data(self, folder_path, folder_name, speed_data, expt_start_time):
        """Import the bulk of the Labview data to NWB.

        :param folder_path: the Labview folder to import
        :param folder_name: the name of the Labview folder
        :param speed_data: mouse speed data
        :param expt_start_time: when the experiment started
        """
        def rel(file_name):
            """Return the path of a file name relative to the Labview folder."""
            return os.path.join(folder_path, file_name)
        self.add_speed_data(speed_data, expt_start_time)
        self.determine_trial_times()
        self.add_stimulus()
        self.read_cycle_relative_times(rel('Single cycle relative times.txt'))
        self.read_zplane(rel('Zplane_Pockels_Values.dat'))
        self.read_zstack(rel('Zstack Images'))
        self.add_rois(rel('ROI.dat'))
        self.read_functional_data(rel('Functional imaging TDMS data files'))
        video_folder = os.path.join(os.path.dirname(folder_path), folder_name + ' VidRec')
        if os.path.isdir(video_folder):
            self.read_video_data(video_folder)

    def __enter__(self):
        """Return this object itself as a context manager."""
        return self

    def __exit__(self, type, value, traceback):
        """Close the NWB file when the context is exited."""
        self.close()

    def __del__(self):
        """Close the NWB file when this object is destroyed."""
        self.close()

    def close(self):
        """Close our NWB file."""
        if self.nwb_file:
            self.nwb_file.close()
        self.nwb_file = None

    def log(self, msg_template, *args, **kwargs):
        """Log status information if in verbose mode.

        :param msg_template: message to log, optionally with {} placeholders
        :param args: positional arguments to pass to msg_template.format
        :param kwargs: keyword arguments to pass to msg_template.format
        """
        if self.verbose:
            import time
            timestamp = time.strftime('%H:%M:%S ')
            print(timestamp + msg_template.format(*args, **kwargs))

    def read_user_config(self):
        """Read the user configuration YAML files.

        We first read the default configuration supplied with this package.
        Then we look in the user_config_dir (as defined by appdirs) for any
        machine- & user-specific configuration settings, which override the
        defaults.
        """
        if os.path.isfile(metadata.user_conf_path):
            self.log('Reading user metadata from {}', metadata.user_conf_path)
        self.user_metadata = metadata.read_user_config()
        return self.user_metadata

    def add_general_info(self, label, value):
        general = self.nwb_file.get_node('/general')
        general.set_dataset(label, value)

    def add_devices_info(self):
        """Populate /general/devices with information about the rig.

        The names and descriptions of devices are taken from the metadata config file.
        """
        general = self.nwb_file.get_node('/general')
        devices = general.make_group('devices')
        for device_name, desc in self.user_metadata['devices'].items():
            if not device_name.endswith('Cam'):
                devices.set_dataset(id='<device_X>', name=device_name, value=desc)

    def parse_experiment_header_ini(self, filename):
        """Read the LabView .ini file and store fields for later processing.

        The information will be stored in self.labview_header as a nested dict
        for easy access of key fields later. Those fields that are numbers will be
        stored as floating point values; everything else will be strings. Values given
        in double quotes will have the quotes removed.

        This method also uses the header info to set self.mode, which stores the
        type of imaging being performed, and figure out which user's metadata to load.

        :param filename: path to the Labview header
        :returns: the raw Labview fields as a list of lists of strings
        """
        self.log('Parsing Labview header {}', filename)
        ini = open(filename, 'r')
        fields = []
        section = ''
        self.labview_header = header = {}
        for line in ini:
            line = line.strip()
            if len(line) > 0:
                if line.startswith('['):
                    section = line[1:-1]
                    header[section] = {}
                elif '=' in line:
                    words = line.split('=')
                    key, value = words[0].strip(), words[1].strip()
                    fields.append([section, key, value])
                    try:
                        value = float(value)
                    except ValueError:
                        pass
                    if isinstance(value, str) and value[0] == value[-1] == '"':
                        value = value[1:-1]
                    header[section][key] = value
        # Use the header to determine what kind of imaging is being performed.
        if header['GLOBAL PARAMETERS']['number of poi'] > 0:
            self.mode = Modes.pointing
        elif header['GLOBAL PARAMETERS']['number of miniscans'] > 0:
            self.mode = Modes.miniscan
        else:
            raise ValueError('Unsupported imaging type: numbers of poi and miniscans are zero.')
        # Use the user specified in the header to select default session etc. metadata
        user = header['LOGIN']['User']
        if user not in self.user_metadata['sessions']:
            if 'last_session' in self.user_metadata:
                self.log("Labview user '{}' not found in metadata;"
                         " using last session by '{}' instead.",
                         user, self.user_metadata['last_session'])
                user = self.user_metadata['last_session']
            else:
                raise ValueError("No session information found for user '{}' - please edit the"
                                 " metadata.yaml file to include their details.".format(user))
        if user not in self.user_metadata['people']:
            raise ValueError("No information found for user '{}' - please edit the metadata.yaml"
                             " file to include their details.".format(user))
        self.user = self.user_metadata['people'][user]
        expt = self.user_metadata['sessions'][user]['experiment']
        if expt not in self.user_metadata['experiments']:
            raise ValueError("Experiment '{}' not found in metadata.yaml.".format(expt))
        self.experiment = self.user_metadata['experiments'][expt]
        self.session_description = self.user_metadata['sessions'][user]['description']
        return fields

    def add_labview_header(self, fields):
        """Add the Labview header fields verbatim to the NWB file.

        We use a fixed length ASCII string array, null-padded to the length of the longest
        string, at /general/labview_header. This is defined by one of our NWB extensions.
        It is likely to be the most portable representation for this kind of data.

        :param fields: the raw Labview headers as a list of 3-element lists of strings
        """
        general = self.nwb_file.get_node('/general')
        general.set_dataset("labview_header", fields)

    def add_time_series_data(self, label, data, times, ts_attrs={}, data_attrs={},
                             kind='TimeSeries'):
        """Create a basic acquisition timeseries and add to the NWB file.

        :param label: Name of the group within /acquisition/timeseries.
        :param data: The data array.
        :param times: The timestamps array.
        :param ts_attrs: Any attributes for the timeseries group itself.
        :param data_attrs: Any attributes for the data array.
        :param kind: What type of timeseries to create, e.g. TwoPhotonSeries.
        :returns: The new timeseries group.
        """
        nts = self.nwb_file.make_group(
            "<{}>".format(kind), label,
            path="/acquisition/timeseries",
            attrs=ts_attrs)
        nts.set_dataset("data", data, attrs=data_attrs)
        nts.set_dataset("timestamps", times)
        return nts

    def read_speed_data(self, file_name):
        """Read acquired speed data from the raw data file.

        The columns in the file are:
         - Date as MM/DD/YYYY
         - Time at HH:MM:SS.UUUUUU
         - Microseconds since start of trial
         - Speed in rpm (1 rpm = 50 cm/s), always negative!
         - Unsure; seems to be unused

        The date & time columns give the global experiment time. The third column is used
        to identify where trials begin & end. It will reset both at the end of one trial,
        then again at the start of the next, giving a short period of 'junk' data inbetween.

        :param file_name: path to the file
        :returns: (speed_data, initial_time), where speed_data is the file contents as a
        Pandas data table, and initial_time is the experiment start time, which sets the
        session_start_time for the NWB file.
        """
        self.log('Loading speed data from {}', file_name)
        assert os.path.isfile(file_name)
        speed_data = pd.read_table(file_name, header=None, usecols=[0, 1, 2, 3], index_col=0,
                                   names=('Date', 'Time', 'Trial time', 'Speed'),
                                   dtype={'Trial time': int, 'Speed': float},
                                   parse_dates=[[0, 1]],  # Combine first two cols
                                   dayfirst=True, infer_datetime_format=True,
                                   memory_map=True)
        initial_offset = pd.Timedelta(microseconds=speed_data['Trial time'][0])
        initial_time = speed_data.index[0] - initial_offset
        return speed_data, initial_time

    def add_speed_data(self, speed_data, initial_time):
        """Add acquired speed data the the NWB file.

        Creates the /acquisition/timeseries/speed_data and
        /acquisition/timeseries/trial_times groups.

        :param speed_data: raw speed data loaded from file by read_speed_data(), as a
        Pandas data table
        :param initial_time: experiment start time, from read_speed_data()
        """
        rel_times = (speed_data.index - initial_time).total_seconds().values
        ts_attrs = {'source': '/general/devices/mouse_wheel_device',
                    'description': 'Raw mouse speed data.',
                    'comments': 'Speed is in rpm, with conversion factor to cm/s specified.'}
        speed_attrs = {'unit': 'cm/s', 'conversion': 50.0 / 60.0, 'resolution': 0.001 * 50 / 60}
        time_attrs = {'unit': 'second', 'conversion': 1e6, 'resolution': 1e-6}
        self.add_time_series_data('speed_data', speed_data['Speed'].values, rel_times,
                                  ts_attrs=ts_attrs, data_attrs=speed_attrs)
        ts_attrs['description'] = 'Per-trial times for mouse speed data.'
        self.add_time_series_data('trial_times', speed_data['Trial time'].values, rel_times,
                                  ts_attrs=ts_attrs, data_attrs=time_attrs)

    def get_data(self, timeseries, dataset='data'):
        """Get the data for a timeseries as a numpy array.

        :param timeseries: either an h5gate.Group or path to the timeseries
        :param dataset: alternative name for the dataset if not 'data'
        """
        if isinstance(timeseries, nwb_file.g.Group):
            timeseries = timeseries.full_path
        data_path = timeseries + '/' + dataset
        return self[data_path].value

    def get_times(self, timeseries):
        """Get the timestamps for a timeseries as a numpy array.

        Will handle both the case where there is a 'timestamps' dataset, and the case where
        these must be determined from 'starting_time' and rate.

        :param timeseries: either an h5gate.Group or path to the timeseries
        """
        if isinstance(timeseries, str):
            timeseries = self.nwb_file.get_node(timeseries)
        ts = self[timeseries.full_path]
        if 'timestamps' in ts:
            t = ts['timestamps'].value
        else:
            n = ts['num_samples'].value
            t0 = ts['starting_time'].value
            rate = ts['starting_time'].attrs['rate']
            t = t0 + np.arange(n) / rate
        return t

    def determine_trial_times(self):
        """Use the acquired speed data to determine the start & end times for each trial.

        Each trial will be defined as an epoch within the NWB file, and the relevant portions
        of the speed data linked to these.  The epochs will be named 'trial_001' etc.

        Trials are identified by the resets in the 'trial_times' timeseries.  This stores
        the relative times for each speed reading within a single trial.  Hence when it
        resets (i.e. one entry is less than the one before) this marks the end of a trial.
        There is a short interval between trials which still has speed data recorded, so it's
        the second reset which marks the start of the next trial.
        """
        self.log('Calculating trial times from speed data')
        trial_times_ts = self.nwb_file.get_node('/acquisition/timeseries/trial_times')
        speed_data_ts = self.nwb_file.get_node('/acquisition/timeseries/speed_data')
        trial_times = self.get_data(trial_times_ts)
        # Prepend -1 so we pick up the first trial start
        # Append -1 in case there isn't a reset recorded at the end of the last trial
        deltas = np.ediff1d(trial_times, to_begin=-1, to_end=-1)
        # Find resets and pair these up to mark start & end points
        reset_idxs = (deltas < 0).nonzero()[0].copy()
        assert reset_idxs.ndim == 1
        num_trials = reset_idxs.size // 2   # Drop the extra reset added at the end if
        reset_idxs.resize((num_trials, 2))  # it's not needed
        reset_idxs[:, 1] -= 1  # Select end of previous segment, not start of next
        # Index the timestamps to find the actual start & end times of each trial. The start
        # time is calculated using the offset value in the first reading within the trial.
        rel_times = self.get_times(trial_times_ts)
        epoch_times = rel_times[reset_idxs]
        epoch_times[:, 0] -= trial_times[reset_idxs[:, 0]] * 1e-6
        # Create the epochs in the NWB file
        # Note that we cannot use nwb_utils.add_epoch_ts since it would add the last previous
        # junk speed reading to the start of the next trial, since they have exactly the same
        # timestamp. Since we already know the start index and count of relevant entries in
        # the timeseries, however, it's easy to set up the references directly.
        expected_counts = np.diff(reset_idxs) + 1
        for i, (start_time, stop_time) in enumerate(epoch_times):
            trial = 'trial_{:04d}'.format(i + 1)
            epoch = nwb_utils.create_epoch(self.nwb_file, trial, start_time, stop_time)
            ts_ref_in_epoch = epoch.make_group('<timeseries_X>', 'speed_data')
            ts_ref_in_epoch.set_dataset('idx_start', int(reset_idxs[i, 0]))
            ts_ref_in_epoch.set_dataset('count', int(expected_counts[i]))
            ts_ref_in_epoch.make_group('timeseries', speed_data_ts)

    def add_stimulus(self):
        '''Add information about the stimulus presented.

        This is taken from the metadata.yaml at present, since Labview does not record this
        information.

        This adds a TimeSeries group to /stimulus/presentation containing the timings of air
        puffs. At present the stimulus is always presented at the same time within each trial,
        so the only argument is the delay from the start of the trial until the puff. The 'data'
        for this time series is simply the text 'puff' at each occasion.
        '''
        for stim in self.experiment['stimulus_details']:
            ts = self.nwb_file.make_group(
                '<TimeSeries>', stim['name'], path='/stimulus/presentation',
                attrs={'source': stim['source'],
                       'description': stim['description'],
                       'comments': stim['comments']})
            trials = self['/epochs']
            puffs = ['puff'] * len(trials)
            ts.set_dataset('data', puffs, attrs={'unit': 'n/a', 'conversion': float('nan'),
                                                 'resolution': float('nan')})
            times = np.zeros((len(puffs),), dtype=np.float64)
            for i, trial in enumerate(trials.values()):
                times[i] = trial['start_time'].value + stim['trial_time_offset']
            ts.set_dataset('timestamps', times)

    def read_cycle_relative_times(self, file_path):
        """Read the 'Single cycle relative times.txt' file and store the values in memory.

        Note that while the file has times in microseconds, we convert to seconds for consistency
        with other timestamps in NWB.
        """
        assert os.path.isfile(file_path)
        self.cycle_relative_times = pd.read_table(file_path, names=('RelativeTime', 'CycleTime'),
                                                  dtype=np.float64) / 1e6

    def read_functional_data(self, folder_path):
        """Import functional data from Labview TDMS files.

        The folder contains files named like like "NNN.tdms", where NNN gives the trial number.
        These files are thus per-trial, but a TimeSeries needs to contain all trials. We link to
        portions corresponding to single trials from epochs.

        Each file contains data for 2 channels in the group 'Functional Imaging Data', where
        'Channel 0 Data' is Red and 'Channel 1 Data' is Green. Each channel contains data for all
        pixels in all ROIs for all time within that trial, as a single 1d array. Within this array,
        we have data first for all pixels in the first ROI at time 0, then the second ROI at time
        0, and so on through all ROIs, before moving to data from the next cycle. For 2d ROIs, it
        scans first over the X dimension then over Y.

        While it might seem that this data is well suited to become RoiResponseSeries within
        /processing/Acquired_ROIs/Fluoresence, that time series type assumes a single value per
        ROI per time, which doesn't support storing raw data from multi-pixel ROIs. Instead,
        the data will be stored within /acquisition/timeseries, in TwoPhotonSeries named like
        ROI_NNN_Green, where NNN is the global (not per-imaging-plane) ROI number.

        We define the ROIs within their imaging planes first, storing zeros for the data, then
        read each TDMS file to fill in real recordings. The channel data will have its dimensions
        permuted to match the NWB (t, z, y, x) arrangement, and be stored in the appropriate
        segment of the timeseries. At present all ROIs are 2d (or less, but can be represented as
        such with length 1 dimensions), however this structure allows for extension to 3d in the
        future.

        The single cycle time (self.cycle_relative_times['CycleTime'][0]) gives you the difference
        in acquisition time between successive lines in a file. Time starts at the beginning of
        the trial (epoch in NWB speak). This is the time to record in the timestamps field. Note
        that even though these are evenly spaced we can't use starting_time and rate, since this
        would not account for time between trials.
        """
        self.log('Loading functional data from {}', folder_path)
        assert os.path.isdir(folder_path)
        # Figure out timestamps, measured in seconds
        epoch_names = self['/epochs'].keys()
        trials = [int(s[6:]) for s in epoch_names]
        cycles_per_trial = int(self.labview_header['GLOBAL PARAMETERS']['number of cycles'])
        num_times = cycles_per_trial * len(epoch_names)
        cycle_time = self.cycle_relative_times['CycleTime'][0]
        single_trial_times = np.arange(cycles_per_trial) * cycle_time
        times = np.zeros((num_times,), dtype=float)
        for i, epoch_name in enumerate(epoch_names):
            trial_start = self['/epochs/' + epoch_name + '/start_time']
            times[i * cycles_per_trial:
                  (i + 1) * cycles_per_trial] = single_trial_times + trial_start
        opto = self.nwb_file.make_group('optophysiology', abort=False)
        opto.set_custom_dataset('cycle_time', cycle_time)
        # Prepare attributes for timeseries groups and datasets (common to all instances)
        data_attrs = {'unit': 'intensity', 'conversion': 1.0, 'resolution': float('NaN')}
        ts_desc_template = 'Fluorescence data acquired from the {channel} channel in {roi_name}.'
        ts_attrs = {'source': '/general/devices/AOL_microscope',
                    'comments': 'The AOL microscope can acquire just the pixels comprising defined'
                                ' ROIs. This timeseries records those pixels over time for a'
                                ' single ROI & channel.'}
        gains = {'Red': self.labview_header['GLOBAL PARAMETERS']['pmt 1'],
                 'Green': self.labview_header['GLOBAL PARAMETERS']['pmt 2']}
        # Iterate over ROIs, which are nested inside each imaging plane section
        all_rois = {}
        seg_iface = self['/processing/Acquired_ROIs/ImageSegmentation']
        for plane_name, plane in seg_iface.items():
            self.log('  Defining ROIs for plane {}', plane_name)
            # Note that we can't read plane['roi_list'] to determine roi_names as the API only
            # creates it when we close the file.
            roi_names = [n for n in plane.keys() if n.startswith('ROI_')]
            for roi_name in roi_names:
                roi_num = int(roi_name[4:])
                roi = plane[roi_name]
                all_rois[roi_num] = {}
                for ch, channel in {'A': 'Red', 'B': 'Green'}.items():
                    # Set zero data for now; we'll read the real data later
                    # TODO: The TDMS uses 64 bit floats; we may not really need that precision!
                    # The exported data seems to be rounded to unsigned ints. Issue #15.
                    roi_dimensions = roi['dimension'].value
                    data_shape = np.concatenate((roi_dimensions, [num_times]))[::-1]
                    data = np.zeros(data_shape, dtype=np.float64)
                    # Create the timeseries object and fill in standard metadata
                    ts_name = 'ROI_{:03d}_{}'.format(roi_num, channel)
                    ts_attrs['description'] = ts_desc_template.format(channel=channel.lower(),
                                                                      roi_name=roi_name)
                    ts = self.add_time_series_data(ts_name, data=data, times=times,
                                                   kind='TwoPhotonSeries',
                                                   ts_attrs=ts_attrs, data_attrs=data_attrs)
                    all_rois[roi_num][channel] = self[ts.full_path + '/data']
                    ts.set_dataset('dimension', roi_dimensions)
                    ts.set_dataset('format', 'raw')
                    ts.set_dataset('bits_per_pixel', 64)
                    pixel_size_in_m = (self.labview_header['GLOBAL PARAMETERS']['field of view'] /
                                       1e6 /
                                       int(self.labview_header['GLOBAL PARAMETERS']['frame size']))
                    ts.set_dataset('field_of_view', roi_dimensions * pixel_size_in_m)
                    ts.set_dataset('imaging_plane', plane_name)
                    ts.set_custom_dataset('roi_name', roi_name)
                    ts.set_dataset('pmt_gain', gains[channel])
                    ts.set_dataset('scan_line_rate', 1 / cycle_time)
                    ts.set_custom_dataset('channel', channel)
                    # Save the time offset(s) for this ROI, as a link
                    ts.set_dataset('pixel_time_offsets', 'link:' + roi['pixel_time_offsets'].name)
                    # Link to these data within the epochs
                    for trial, epoch_name in enumerate(epoch_names):
                        epoch = self.nwb_file.get_node('/epochs/' + epoch_name)
                        series_ref_in_epoch = epoch.make_group('<timeseries_X>', ts_name)
                        series_ref_in_epoch.set_dataset('idx_start', trial * cycles_per_trial)
                        series_ref_in_epoch.set_dataset('count', cycles_per_trial)
                        series_ref_in_epoch.make_group('timeseries', ts)
        # Iterate over trials, reading data from the TDMS file for each
        num_rois = len(all_rois)
        for trial_index, trial in enumerate(trials):
            self.log('  Reading TDMS {}', trial_index + 1)
            file_path = os.path.join(folder_path, '{:03d}.tdms'.format(trial_index + 1))
            tdms_file = TdmsFile(file_path,
                                 memmap_dir=tempfile.gettempdir())
            time_segment = slice(trial_index * cycles_per_trial,
                                 (trial_index + 1) * cycles_per_trial)
            for ch, channel in {'0': 'Red', '1': 'Green'}.items():
                # Reshape the TDMS data into an nd array
                # TODO: Consider precision: the round() here is to match the exported data...
                ch_data = np.round(tdms_file.channel_data('Functional Imaging Data',
                                                          'Channel {} Data'.format(ch)))
                ch_data_shape = np.concatenate((roi_dimensions, [num_rois, cycles_per_trial]))[::-1]
                ch_data = ch_data.reshape(ch_data_shape)
                # Copy each ROI's data into the NWB
                for roi_num, roi_channels in all_rois.items():
                    roi_channels[channel][time_segment, ...] = ch_data[:, roi_num - 1, ...]

    def add_imaging_plane(self, name, manifold, description,
                          green=True, red=True):
        """Add a new imaging plane definition to /general/optophysiology.

        :param name: A name for the NWB group representing this imaging plane.
        :param manifold: 3d array giving the x,y,z coordinates in microns for each pixel
            in the plane. If the plane is really a line, this can be an Nx1x3 array.
        :param description: Brief text description of the plane, e.g. "Reference Z stack",
            "Pointing mode acquisition sequence".
        :param green: Whether to include the green channel.
        :param red: Whether to include the red channel.
        :returns: The NWB group defining the imaging plane.
        """
        opto = self.nwb_file.make_group('optophysiology', abort=False)
        plane_defn = opto.make_group('<imaging_plane_X>', name=name)
        plane_defn.set_dataset('description', description)
        plane_defn.set_dataset('device', 'AOL_microscope')
        opto_metadata = self.experiment['optophysiology']
        plane_defn.set_dataset('excitation_lambda', opto_metadata['excitation_lambda'])
        plane_defn.set_dataset('indicator', opto_metadata['calcium_indicator'])
        plane_defn.set_dataset('location', opto_metadata['location'])
        cycle_time = self.cycle_relative_times['CycleTime'][0]  # seconds
        cycle_rate = 1 / cycle_time  # Hz
        plane_defn.set_dataset(
            'imaging_rate', '{:.16f}Hz (cycle time = {:.16f} microseconds)'.format(
                cycle_rate, cycle_time * 1e6))
        plane_defn.set_dataset('manifold', manifold,
                               attrs={'unit': 'metre', 'conversion': 1e6})
        plane_defn.set_dataset('reference_frame', 'TODO: In lab book (partly?)')
        if green:
            green_channel = plane_defn.make_group('<channel_X>', name='green')
            green_channel.set_dataset('description',
                                      'Green channel, typically used for active signal.')
            green_channel.set_dataset('emission_lambda', opto_metadata['emission_lambda']['green'])
        if red:
            red_channel = plane_defn.make_group('<channel_X>', name='red')
            red_channel.set_dataset('description', 'Red channel, typically used for reference.')
            red_channel.set_dataset('emission_lambda', opto_metadata['emission_lambda']['red'])
        return plane_defn

    def read_zplane(self, zplane_path):
        """Determine coordinates of reference image stack from Zplane_Pockels_Values.dat.

        This also uses information from the LabView .ini file to define image planes etc
        in /general/optophysiology.

        The .dat file has 4 columns: Z offset from focal plane (micrometres), normalised Z,
        'Pockels' i.e. laser power in %, and z offset for drive motors. We save this raw
        array as the extension dataset /general/optophysiology/zplane_pockels.

        Also sets up self.zplanes as a map from Z coordinate (in microns) to imaging plane name.
        """
        self.log('Loading imaging plane information from {}', zplane_path)
        assert os.path.isfile(zplane_path)
        zplane_data = pd.read_table(
            zplane_path, skiprows=2, skip_blank_lines=True,
            names=('z', 'z_norm', 'laser_power', 'z_motor'), header=0,
            index_col=False)
        num_pixels = int(self.labview_header['GLOBAL PARAMETERS']['frame size'])
        plane_width_in_microns = self.labview_header['GLOBAL PARAMETERS']['field of view']
        manifold = np.zeros((num_pixels, num_pixels, 3))
        x = np.linspace(0, plane_width_in_microns, num_pixels)
        y = np.linspace(0, plane_width_in_microns, num_pixels)
        xv, yv = np.meshgrid(x, y)
        manifold[:, :, 0] = xv
        manifold[:, :, 1] = yv
        self.zplanes = {}
        for plane in zplane_data.itertuples():
            manifold[:, :, 2] = plane.z
            name = 'Zstack{:04d}'.format(plane.Index + 1)
            self.zplanes[plane.z] = name
            self.add_imaging_plane(
                name=name,
                description='Reference Z stack',
                manifold=manifold)
        self.nwb_file.set_custom_dataset(
            '/general/optophysiology/zplane_pockels',
            zplane_data.values,
            attrs={'columns': zplane_data.columns.tolist()})
        self.nwb_file.set_custom_dataset(
            '/general/optophysiology/frame_size', [num_pixels, num_pixels])

    def read_zstack(self, zstack_folder):
        """Add the reference Z stack images into /acquisition.

        The folder holds one .tif file per imaging plane per channel, with the planes ordered
        as in the Zplane_Pockels_Values.dat file (see read_zplane) and hence the order matches
        the ZstackNNNN planes added there. The file names are like GreenChannel_0001.tif.

        We create a single-image TwoPhotonSeries for each plane for each channel in
        /acquisition/timeseries/Zstack_<channel>_<plane>.

        Also fills in self.zstack as a mapping from [plane_name][channel_name] to node path.
        """
        self.log('Loading reference Z stack from {}', zstack_folder)
        assert os.path.isdir(zstack_folder)
        opto = self['/general/optophysiology']
        gains = {'Red': self.labview_header['GLOBAL PARAMETERS']['pmt 1'],
                 'Green': self.labview_header['GLOBAL PARAMETERS']['pmt 2']}
        cycle_time = self.cycle_relative_times['CycleTime'][0]  # seconds
        cycle_rate = 1 / cycle_time  # Hz
        self.zstack = {}
        for plane_name in (n for n in opto.keys() if n.startswith('Zstack')):
            # plane_defn = opto[plane_name]
            self.zstack[plane_name] = {}
            for channel in ('Green', 'Red'):
                plane_index = plane_name[6:]
                group_name = 'Zstack_{}_{}'.format(channel, plane_index)
                file_path = os.path.join(zstack_folder,
                                         channel + 'Channel_' + plane_index + '.tif')
                if not os.path.isfile(file_path):
                    print('Expected Zstack file "{}" missing; skipping.'.format(file_path))
                    continue
                img = tifffile.imread(file_path)
                # Save img to NWB
                ts_attrs = {'description': 'Initial reference Z stack plane',
                            'comments': 'Contains single slice from {} channel'.format(
                                channel.lower()),
                            'source': '/general/devices/AOL_microscope'}
                data_attrs = {'unit': 'intensity', 'conversion': 1.0,
                              'resolution': float('NaN')}
                ts = self.add_time_series_data(group_name, data=img, times=np.array([0.0]),
                                               kind='TwoPhotonSeries',
                                               ts_attrs=ts_attrs, data_attrs=data_attrs)
                self.zstack[plane_name][channel] = ts.full_path
                num_pixels = int(self.labview_header['GLOBAL PARAMETERS']['frame size'])
                width_in_metres = self.labview_header['GLOBAL PARAMETERS']['field of view'] / 1e6
                ts.set_dataset('dimension', [num_pixels, num_pixels])
                ts.set_dataset('format', 'tiff')
                ts.set_dataset('bits_per_pixel', 16)
                ts.set_dataset('field_of_view', [width_in_metres, width_in_metres])
                ts.set_dataset('imaging_plane', plane_name)
                ts.set_dataset('pmt_gain', gains[channel])
                ts.set_dataset('scan_line_rate', cycle_rate)
                ts.set_custom_dataset('channel', channel)

    def add_rois(self, roi_path):
        """Add the locations of ROIs as an ImageSegmentation module.

        We read a ROI.dat file to determine ROI locations. This has many tab-separated columns:
            ROI index; ROI ID; ROI Time (ns); Pixels in ROI;
            X start; Y start; Z start; X stop; Y stop; Z stop;
            Angle (deg); Composite ID; Number of lines; Frame Size; Zoom;
            Laser Power (%); ROI group ID.

        Each ROI must lie within one of the Z planes in the reference Z stack. We therefore can
        represent it as a rectangle (size 1x1 for pointing mode) within that plane. The relevant
        slice slice from the Z stack is used as the reference image. We group the ROIs by Z
        coordinate, since each imaging plane should only be listed once in the ImageSegmentation
        module; within a given plane, the original relative ordering of ROIs is maintained.

        TODO: Consider adding an array dataset of object references to the ROI definitions - see
        http://docs.h5py.org/en/latest/refs.html for details of how to do this. Would enable quick
        access to all ROIs (in the defined order) without having to iterate over imaging planes
        then sort. It's less of an issue with the timeseries ROI data, since that's in groups
        organised by ROI number and channel name, so we can iterate there. Issue #16.
        """
        self.log('Loading ROI locations from {}', roi_path)
        assert os.path.isfile(roi_path)
        roi_data = pd.read_table(
            roi_path, header=0, index_col=False, dtype=np.float16, memory_map=True)
        original_names = roi_data.columns.tolist()
        roi_data.rename(
            columns={'ROI index': 'roi_index', 'Pixels in ROI': 'num_pixels',
                     'X start': 'x_start', 'Y start': 'y_start', 'Z start': 'z_start',
                     'X stop': 'x_stop', 'Y stop': 'y_stop', 'Z stop': 'z_stop',
                     'Laser Power (%)': 'laser_power'},
            inplace=True)
        module = self.nwb_file.make_group(
            '<Module>', 'Acquired_ROIs',
            attrs={'description': 'ROI locations and acquired fluorescence readings made directly'
                                  ' by the AOL microscope.'})
        module.set_custom_dataset('roi_spec', roi_data.values)
        module.get_node('roi_spec').set_attr('columns', original_names, custom=True)
        # Now we've stored the raw data (which needed to be single dtype) convert some cols to int
        roi_data = roi_data.astype(
            {'x_start': np.uint16, 'x_stop': np.uint16, 'y_start': np.uint16, 'y_stop': np.uint16,
             'num_pixels': int})
        seg_iface = module.make_group('ImageSegmentation',
                                      attrs={'source': '/general/devices/AOL_microscope'})
        # Define the properties of the imaging plane itself, if not a Z plane
        opto = self.nwb_file.make_group('optophysiology', abort=False)
        opto.set_custom_dataset('imaging_mode', self.mode.name)
        if self.mode is Modes.pointing:
            # Sanity check that each ROI is a single pixel
            assert np.all(roi_data.num_pixels == 1)
        # Figure out which plane each ROI is in
        assert (roi_data['z_start'] == roi_data['z_stop']).all()  # Planes are flat in Z
        grouped = roi_data.groupby('z_start', sort=False)
        # Iterate over planes and define ROIs
        for plane_name, roi_group in grouped:
            plane_name = self.zplanes[plane_name]
            plane = seg_iface.make_group('<image_plane>', name=plane_name)
            plane.set_dataset('description', opto.get_node(plane_name + '/description'))
            plane.set_dataset('imaging_plane_name', plane_name)
            ref_imgs = plane.make_group('reference_images')
            # Add a link to the Zstack image acquired for this plane as a reference image.
            ref_imgs.make_group('<image_name>', name='Zstack_image',
                                link='link:' + self.zstack[plane_name]['Red'])
            for row in roi_group.itertuples():
                roi_name = 'ROI_{:03d}'.format(int(row.roi_index))
                # The ROI mask only gives x & y coordinates - z is defined by the imaging plane.
                # The coordinates are also relative to the imaging plane, not absolute. However, our
                # plane coordinates run from 0 to frame_size, so that's easy to compute.
                pixels = np.zeros((row.num_pixels, 2), dtype=np.uint16)
                weights = np.ones((pixels.shape[0],), dtype=float)
                ref_width = ref_height = int(
                    self.labview_header['GLOBAL PARAMETERS']['frame size'])
                # Pixels are located contiguously from start to stop coordinates.
                num_x_pixels = row.x_stop - row.x_start
                num_y_pixels = row.y_stop - row.y_start
                if self.mode is Modes.pointing:
                    assert row.num_pixels == 1, 'Unexpectedly large ROI in pointing mode'
                    num_x_pixels = num_y_pixels = 1
                assert row.num_pixels == num_x_pixels * num_y_pixels, (
                    'ROI is not rectangular: {} != {} * {}'.format(
                        row.num_pixels, num_x_pixels, num_y_pixels))
                dimensions = np.array([num_x_pixels, num_y_pixels], dtype=np.int32)
                for i in range(row.num_pixels):
                    pixels[i, 0] = row.x_start + (i % num_x_pixels)
                    pixels[i, 1] = row.y_start + (i // num_x_pixels)
                nwb_utils.add_roi_mask_pixels(
                    seg_iface, plane_name, name=roi_name, desc=roi_name,
                    pixel_list=pixels, weights=weights, width=ref_width, height=ref_height)
                # Record the time offset(s) for this ROI
                roi = plane.get_node(roi_name)
                time_offsets = self.cycle_relative_times['RelativeTime']
                if self.mode is Modes.pointing:
                    roi.set_dataset('pixel_time_offsets', [time_offsets[row.Index]])
                else:
                    # The relative time field records the start time for each row, not each pixel.
                    # We need to compute pixel times by adding on dwell time per pixel.
                    num_miniscans = self.labview_header['GLOBAL PARAMETERS']['number of miniscans']
                    assert len(time_offsets) == num_miniscans
                    assert num_y_pixels == num_miniscans / len(roi_data)
                    dwell_time = self.labview_header['GLOBAL PARAMETERS']['dwelltime (us)'] / 1e6
                    row_increments = np.arange(num_x_pixels) * dwell_time
                    start_index = row.Index * num_y_pixels
                    row_offsets = time_offsets[start_index:start_index + num_y_pixels].values
                    # Numpy's broadcasting lets us turn the 1d arrays into a 2d combined value
                    pixel_offsets = row_offsets[:, np.newaxis] + row_increments
                    roi.set_dataset('pixel_time_offsets', pixel_offsets)
                # Record the ROI dimensions for ease of lookup when adding functional data
                roi.set_custom_dataset('dimension', dimensions)

    def read_video_data(self, folder_path):
        """Link to video data stored in the given folder.

        :param folder_path: folder containing videos of the experiment.

        Multiple video angles are supported. This method looks for files named like
        '<Base>Cam-relative times.txt' in the folder, each of which contains timing data for a
        single video timeseries. These files contain two tab-separated columns, the first being
        frame numbers, and the second time offsets from the start of the experiment in
        milliseconds.

        The video data itself is stored in .avi files, potentially more than one per camera,
        named like '<Base>Cam-<N>.avi', where the file number <N> starts at 1.

        This method adds an ImageSeries in /acquisition/timeseries for each camera, linking to
        the existing .avi files with relative paths. The timeseries are named '<Base>Cam'.
        """
        self.log('Loading video data from {}', folder_path)
        assert os.path.isdir(folder_path)
        nwb_dir = os.path.dirname(os.path.realpath(self.nwb_file.file_name))
        timing_suffix = '-relative times.txt'
        timing_files = glob.glob(os.path.join(folder_path, '*' + timing_suffix))
        for timing_file_path in timing_files:
            cam_name = os.path.basename(timing_file_path)[:-len(timing_suffix)]
            self.log('Camera: {}', cam_name)
            frame_rel_times = pd.read_table(timing_file_path, names=('Frame', 'RelTime'))
            frame_rel_times['RelTime'] *= 1e-3  # Convert to seconds
            # Determine properties of each .avi file
            avi_files = glob.glob(os.path.join(folder_path, cam_name + '-*.avi'))
            num_frames = np.zeros((len(avi_files),), dtype=np.int64)
            video_file_paths = [''] * len(avi_files)
            for avi_file in avi_files:
                file_name = os.path.basename(avi_file)
                self.log('Video: {}', file_name)
                index = int(file_name[len(cam_name) + 1:-4]) - 1
                avi_file = os.path.realpath(avi_file)
                try:
                    video_file_paths[index] = os.path.relpath(avi_file, nwb_dir)
                except ValueError:
                    # Particularly on Windows, it's sometimes impossible to construct
                    # a relative path, so fall back to absolute
                    video_file_paths[index] = avi_file
                container = av.open(avi_file)
                vid = container.streams.video[0]
                num_frames[index] = vid.frames
                if index == 0:
                    vid_rate = vid.rate
                    vid_dimensions = [vid.width, vid.height]
                    bits_per_pixel = vid.format.components[0].bits
                del container, vid
            starting_frames = np.roll(np.cumsum(num_frames), 1)
            starting_frames[0] = 0
            # Add camera to list of devices
            self.nwb_file.set_dataset(
                '<device_X>', name=cam_name, path='/general/devices',
                value=self.user_metadata['devices'][cam_name])
            # Create timeseries
            ts = self.nwb_file.make_group(
                '<ImageSeries>', cam_name, path='/acquisition/timeseries',
                attrs={'source': '/general/devices/' + cam_name,
                       'description': 'Video recording of mouse behaviour.',
                       'comments': 'Frame rate {} s'.format(vid_rate)})
            ts.set_dataset('format', 'external')
            ts.set_dataset('external_file', video_file_paths,
                           attrs={'starting_frame': starting_frames})
            ts.set_dataset('dimension', vid_dimensions)
            ts.set_dataset('bits_per_pixel', bits_per_pixel)
            ts.set_dataset('timestamps', frame_rel_times['RelTime'].values)
