classdef (SharedTestFixtures=SharedFixtures()) ...
        TestImport < matlab.unittest.TestCase
    %TESTIMPORT Test importing Labview to NWB gives correct data

    properties
    end

    methods
        function path = data_path(testCase)
            path = getenv('SILVERLAB_DATA_DIR');
            testCase.assumeTrue(isdir(path));
        end
    end

    methods (Test)
        function testImportedHanaData(testCase)
            %TESTIMPORTEDHANADATA Check data matches Hana's original code

            data_path = testCase.data_path();
            nwb_path = fullfile(data_path, '161215_15_34_21.nwb');
            testCase.assumeEqual(exist(nwb_path, 'file'), 2);
            nwb = NwbFile(nwb_path);
            ref = load(fullfile(data_path, '161215_15_34_21.mat'));

            % Basic experiment parameters
            testCase.verifyEqual(nwb.num_trials, ref.Ntr);
            testCase.verifyEqual(nwb.num_rois, ref.Nroi);
            testCase.verifyEqual(nwb.num_cycles_per_trial, ref.Npt);
            testCase.verifyEqual(nwb.num_cycles_per_trial, ref.Ncycl);
            testCase.verifyEqual(nwb.cycle_time * 1e3, ref.Tcycl, ...
                'RelTol', 1e-6); % Our times are in seconds, original in ms

            % Coordinates for the imaging planes & ROIs
            zdata = double(nwb.get('/general/optophysiology/zplane_pockels'));
            zz_norm = zdata(:,2);
            testCase.verifyEqual(zz_norm, ref.zz_norm, 'RelTol', 1e-6);
            % TODO: Get these from the individual Zstack manifolds, rather
            % than our custom dataset?
            % To do this we'd need to:
            % - Get (x,y) locations of each ROI within its Z plane from
            % /processing/Acquired_ROIs/ImageSegmentation/ZstackNNN/ROI_NNN/pix_mask
            % - Use these to find the right part of /general/optophysiology/ZstackNNNN/manifold
            % (pick out entries (x, y, 1:3) for the (x,y,z) co-ords)
            % (need to check if x & y are 0-based or 1-based)
            roi_spec = double(nwb.get('/processing/Acquired_ROIs/roi_spec'));
            Z0 = interp1(zdata(:,1), zz_norm, roi_spec(:,7));
            testCase.verifyEqual(Z0, ref.Z0, 'RelTol', 1e-6);
            testCase.verifyEqual(roi_spec(:,5), round(ref.Xim));
            testCase.verifyEqual(roi_spec(:,6), round(ref.Yim));

            % Functional data
            [green_data, Troi, times] = nwb.get_roi_data('Green');
            testCase.verifyEqual(green_data, ref.allData_green, ...
                'RelTol', 1e-6);
            testCase.verifyEqual(Troi .* 1e3, ref.Troi, ...
                'RelTol', 1e-6); % Our times are in seconds, original in ms
            base_times = zeros(ref.Ntr, ref.Ncycl);
            for i=1:ref.Ntr
                base_times(i,:) = nwb.get_trial_data(i, 'ROI_001_Green', 'timestamps');
            end
            ref_times = repmat(Troi.', 20, 1) + permute(base_times, [1 3 2]);
            testCase.verifyEqual(times, ref_times);

            % Speed data
            Ttrial = nwb.num_cycles_per_trial * nwb.cycle_time; % in seconds
            T = linspace(0, Ttrial, Ttrial/0.001);
            spDall = zeros(ref.Ntr, size(T, 2));
            for i = 1:ref.Ntr
                spd_data = nwb.get_trial_data(i, 'speed_data');
                spd_times = nwb.get_trial_data(i, 'speed_data', 'timestamps');
                rel_times = spd_times - spd_times(1);
                spDall(i,:) = interp1(rel_times, spd_data, T);
            end
            spDall = -spDall;
            testCase.verifyEqual(spDall, ref.spDall, ...
                'RelTol', 1e-2, 'AbsTol', 1e-4);
        end

        function testImportHana(testCase)
            %TESTIMPORTHANA Check we can import some Hana data

            skip_imports = getenv('SILVERLAB_SKIP_IMPORTS');
            testCase.assumeFalse(strcmp(skip_imports, '1'));

            data_path = testCase.data_path();
            labview_path = fullfile(data_path, '161215_15_58_52 FunctAcq');
            testCase.assumeTrue(isdir(labview_path));

            temp_folder = testCase.getSharedTestFixtures(...
                'matlab.unittest.fixtures.TemporaryFolderFixture').Folder;
            nwb_path = fullfile(temp_folder, '161215_15_58_52.nwb');
            nwb = NwbFile(nwb_path, 'w');
            disp(['Importing ' labview_path '...']);
            nwb.import_labview(labview_path);
            nwb.file_obj.close();

            disp('Checking signature matches...');
            sig_path = 'data/161215_15_58_52.sig';
            match = py.silverlabnwb.nwb_util.compare_to_signature(...
                nwb_path, sig_path);
            testCase.verifyTrue(match);
        end
    end

end
