classdef NwbFile < handle
    %NWBFILE Provides easy access to SilverLab NWB files.
    %
    % TODO: Documentation!

    properties (Access = public)
        % Path to this NWB file.
        path;
        % File handle for use in Matlab's HDF5 interface.
        file;
        % h5py interface to the file.
        h5py;
        % Our Python API object.
        file_obj;
    end

    % Properties calculated on the fly, rather than stored.
    % See the corresponding get.(property) methods for their definition.
    properties (Dependent)
        % How many trials are stored in the file.
        num_trials;
        % How many ROIs are stored in the file.
        num_rois;
        % How many times each point was imaged in a single trial.
        num_cycles_per_trial;
        % How long the microscope takes for a full cycle.
        cycle_time;
        % Names of timeseries containing video data.
        video_names;
        % Paths to the raw video files.
        video_paths;
    end

    methods
        function nwb = NwbFile(path, mode, verbose)
            %NWBFILE Open an NWB file for reading or writing.
            %
            % Synopsis: nwb = NwbFile(path, mode, verbose)
            %
            % Arguments:
            %   path: path to the NWB file
            %   mode: optional mode of file access. One of:
            %     'r'  - Readonly, file must exist
            %     'r+' - Read/write, file must exist (default)
            %     'w'  - Create file, replacing if exists
            %     'w-' - Create file, fail if exists
            %     'a'  - Read/write if exists, create otherwise
            %   verbose: whether to turn on logging output (default true)
            %
            % TODO: At present reading data is only possible in readonly
            % mode; the only operation supported when writing is importing
            % an entire Labview folder into a fresh file.

            if nargin < 1
                error('NwbFile:path:missing', 'No NWB file path supplied');
            end
            if nargin < 2
                mode = 'r';
            end
            if nargin < 3
                verbose = true;
            end

            % Stop Matlab crashing if the HDF5 libraries don't quite match!
            setenv('HDF5_DISABLE_VERSION_CHECK', '1');

            nwb.path = path;
            nwb.readonly = (mode == 'r');
            if nwb.readonly
                nwb.h5py = py.h5py.File(path, mode);
                nwb.file = H5F.open(path);
            else
                nwb.file_obj = py.silverlabnwb.NwbFile(path, mode, verbose);
            end
        end

        function n = get.num_trials(nwb)
            %NUM_TRIALS The number of trials stored in this file.
            n = double(py.len(nwb.h5py.get('/epochs')));
        end

        function n = get.num_rois(nwb)
            %NUM_ROIS The number of ROIs stored in this file.
            roi_spec = nwb.h5py.get('/processing/Acquired_ROIs/roi_spec');
            if roi_spec == py.None
                error('NwbFile:rois:missing', 'No ROIs defined in file.');
            else
                n = double(roi_spec.shape{1});
            end
        end

        function n = get.num_cycles_per_trial(nwb)
            %NUM_CYCLES_PER_TRIAL The number of microscope cycles/trial.
            %
            % That is, the number of times each point is imaged in each
            % trial. Currently looks at the first imaging timeseries in
            % the first trial, and assumes they're all the same.
            trials = py.list(nwb.h5py.get('/epochs').keys());
            trial1 = nwb.h5py.get(['/epochs/' char(trials{1})]);
            n = -1;
            for tsname = cell(py.list(trial1.keys()))
                ts = trial1.get(char(tsname{1}));
                if py.hasattr(ts, 'get') && ...
                        ts.get('timeseries/pixel_time_offsets') ~= py.None
                    n = double(py.int(ts.get('count').value));
                    break;
                end
            end
            if n == -1
                error('NwbFile:imaging:missing', ...
                      'No imaging timeseries defined in file.');
            end
        end

        function t = get.cycle_time(nwb)
            %CYCLE_TIME How long the microscope takes for a full cycle.
            t = double(nwb.get('/general/optophysiology/cycle_time'));
        end
        
        function names = get.video_names(nwb)
            %VIDEO_NAMES Names of timeseries containing video data.
            timeseries = cell(py.list(nwb.h5py.get(...
                '/acquisition/timeseries/').keys()));
            is_video = cellfun(@(name) name.endswith('Cam'), timeseries);
            names = timeseries(is_video);
            names = cellfun(@(n) char(py.str(n)), names, ...
                'UniformOutput', false);
        end

        function paths = get.video_paths(nwb)
            %VIDEO_PATHS Paths to raw video files.
            %
            % Returns a cell vector (length number of videos) where each
            % entry is a cell vector (length number of files) with the
            % absolute path to each video file for that video timeseries.

            [base_path, ~, ~] = fileparts(nwb.path);
            names = nwb.video_names;
            num_videos = length(names);
            paths = cell(1, num_videos);
            for i=1:num_videos
                rel_paths = nwb.get(['/acquisition/timeseries/' ...
                                     names{i} '/external_file']);
                num_files = size(rel_paths, 1);
                paths{i} = cell(1, num_files);
                for j=1:num_files
                    paths{i}{j} = fullfile(base_path, rel_paths(j, :));
                end
            end
        end

        function array = get(nwb, obj_path, varargin)
            %GET Retrieve a whole dataset from an NWB file.
            %
            % Synopsis: nwb.get(obj_path)
            %
            % Arguments:
            %   nwb: the NWB file object
            %   obj_path: path to the dataset within the file
            %   varargin: if given, obj_path is treated as a template and
            %             the full path constructed using sprintf
            %
            % Returns:
            %   the dataset as a Matlab array; either a numeric array
            %   for numeric data, or a cell array for text data

            if nargin > 2
                obj_path = sprintf(obj_path, varargin{:});
            end

            dataset_id = H5D.open(nwb.file, obj_path);
            array = H5D.read(dataset_id);
            % Matlab has the opposite dimension ordering by default
            array = permute(array, ndims(array):-1:1);
            H5D.close(dataset_id);
        end

        function data = get_trial_data(nwb, trial, ts_name, data_name)
            %GET_TRIAL_DATA Get the portion of a timeseries in a trial.
            %
            % Synopsis:
            %   nwb.get_trial_data(trial, ts_name)
            %
            % Arguments:
            %   trial: either a trial number or name of the group in the
            %          NWB file, e.g. trial_0001
            %   ts_name: name of the timeseries group within the selected
            %            trial, e.g. ROI_001_Green
            %   data_name: name of the dataset to read; defaults to data

            assert(nargin >= 3 && nargin <= 4);
            if nargin == 3
                data_name = 'data';
            end
            % Find the dataset in the file
            if isnumeric(trial)
                trial = sprintf('trial_%04d', trial);
            end
            base = ['/epochs/' trial '/' ts_name '/'];
            idx_start = nwb.get([base 'idx_start']);
            count = nwb.get([base 'count']);
            data_path = [base 'timeseries/' data_name];
            full_shape = tuple2mat(nwb.h5py.get(data_path).shape);
            dataset_id = H5D.open(nwb.file, data_path);

            % Read just the portion we care about
            ndim = length(full_shape);
            read_dims = zeros(size(full_shape));
            read_dims(1) = count;
            read_dims(2:end) = full_shape(2:end);
            mem_space_id = H5S.create_simple(ndim, read_dims, read_dims);
            file_space_id = H5D.get_space(dataset_id);
            offset = zeros(size(full_shape));
            offset(1) = idx_start;
            H5S.select_hyperslab(file_space_id, 'H5S_SELECT_SET', offset, [], [], read_dims);
            data = H5D.read(dataset_id, 'H5ML_DEFAULT', mem_space_id, file_space_id, 'H5P_DEFAULT');
            H5D.close(dataset_id);
        end

        function data = get_trials_data(nwb, ts_name, data_name, trials)
            %GET_TRIALS_DATA Get the portions of a timeseries in trials.
            %
            % Synopsis:
            %   nwb.get_trials_data(trial, ts_name, trials)
            %
            % Arguments:
            %   ts_name: name of the timeseries group within the selected
            %            trials, e.g. ROI_001_Green
            %   data_name: name of the dataset to read; defaults to data
            %   trials: optional array or cell array of trial identifiers,
            %           which are either numbers or names. Defaults to all
            %           trials.
            %
            % Returns: cell array of timeseries data.

            assert(nargin >= 2 && nargin <= 4);
            if nargin < 3
                data_name = 'data';
            end
            if nargin < 4
                trials = 1:nwb.num_trials;
            end

            data = cell(1, length(trials));
            i = 1;
            for trial = trials
                data{i} = nwb.get_trial_data(trial, ts_name, data_name);
                i = i + 1;
            end
        end

        function [data, t_offsets, times] = get_roi_data(nwb, channel)
            %GET_ROI_DATA Get functional data for all ROIs and trials.
            %
            % Synopsis: nwb.get_roi_data(channel)
            %
            % Arguments:
            %   nwb: the NWB file object
            %   channel: which channel to read ('Green' or 'Red')
            %
            % Returns:
            %   data: array of shape (num_trials, num_rois, num_times)
            %   t_offsets: (optional) time offsets at which each ROI was
            %              recorded
            %   times: (optional) array with timestamps for each point in
            %          data, of shape (num_trials, num_rois, num_times)

            n_trials = nwb.num_trials;
            n_rois = nwb.num_rois;
            n_times = nwb.num_cycles_per_trial;

            if nargout >= 2
                name_tpl = '/acquisition/timeseries/ROI_%03d_%s/pixel_time_offsets';
                first_t = nwb.get(name_tpl, 1, channel);
                t_offsets = zeros(n_rois, numel(first_t));
                t_offsets(1, :) = first_t;
                for j = 2:n_rois
                    t_offsets(j) = nwb.get(sprintf(name_tpl, j, channel));
                end
            end

            data = zeros(n_trials, n_rois, n_times);
            if nargout == 3
                times = zeros(n_trials, n_rois, n_times);
            end
            for i = 1:n_trials
                for j = 1:n_rois
                    roi_name = sprintf('ROI_%03d_%s', j, channel);
                    data(i,j,:) = nwb.get_trial_data(i, roi_name);
                    if nargout == 3
                        times(i,j,:) = nwb.get_trial_data(...
                            i, roi_name, 'timestamps') + t_offsets(j);
                    end
                end
            end
        end

        function import_labview(nwb, folder)
            %IMPORT_LABVIEW Import a Labview folder to NWB format.
            %
            % Synopsis: nwb.import_labview(folder)
            %
            % Arguments:
            %   nwb: the NWB file object
            %   folder: path to the folder to import

            assert(~nwb.readonly, 'Cannot import to a readonly file');
            %py.silverlabnwb.metadata_gui.run_editor();
            nwb.file_obj.import_labview_folder(folder);
        end
    end

    properties (Access = private)
        % Whether we are able to write to the file.
        readonly;
    end

end