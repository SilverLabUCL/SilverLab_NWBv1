classdef DisplayVideos < handle
%DISPLAYVIDEOS Show/control a GUI to play synced videos from an NWB file.
%
% This allows the parallel, time-synced display of multiple video
% streams, alongside other timeseries data displayed as static graphs.
% A vertical bar on the graphs indicates the current time point shown
% in the videos.

% Read-only properties
properties (GetAccess = public, SetAccess = private)
    % The NWB file object being displayed.
    nwb;
    % The main figure handle for the GUI window.
    fig;
    % Names of the videos to display.
    video_names;
    % Paths to the individual video files.
    video_paths;
    % Axes objects in which to display each video.
    video_axes;
    % Text uicontrols displaying the title of each video.
    video_titles;
    % Cell array with the starting_frame attribute for each video series.
    start_frames;
    % The current VideoReader instances for each video.
    videos;
    % The timeseries for each video.
    video_times;
    % The combined timeseries for all videos: sorted unique timestamps (s).
    joint_t;
    % Where in the joint timeseries each video has frames.
    video_frames;
    % Index of the last frame displayed, within the combined timeseries.
    last_frame;
    % Index of the last frame displayed for each video file.
    last_frames;
    % Structure containing UI controls.
    buttons;
    % Structure containing data labels.
    data_labels;
    % Axes for displaying per-ROI data, e.g. df/f
    roi_axes;
    % Axes for displaying single timeseries data, e.g. speed
    ts_axes;
    % Data being displayed on the ROI axes; (#trials, #rois, #times) array
    roi_data;
    % Times corresponding to roi_data.
    roi_times;
    % Data displayed on the timeseries axes; (#trials) cell array
    ts_data;
    % Times corresponding to ts_data.
    ts_times;
    % Handles for lines displaying the current time on data plots.
    data_time_lines;
    % Start times of each trial.
    trial_times;
end

% Properties calculated on the fly, rather than stored.
% See the corresponding get.(property) methods for their definition.
properties (Dependent)
    % The timestamp (in seconds) of the currently displayed frame.
    current_time;
    % Which trial corresponds to the current timestamp.
    current_trial;
    % Whether the videos are currently playing.
    playing;
end

% Class properties, defining how large various GUI elements are.
properties (Access = protected)
    % Height for buttons, text labels, and similar UI controls.
    BUTTON_HEIGHT = 20;
    % Default gap between elements.
    GAP = 10;
    % Desired height for data display.
    DATA_HEIGHT = 600;
    % Desired width for data display.
    DATA_WIDTH = 1200;
    % Instance property giving the overall dimensions of the video
    % displays.
    VIDEO_DIMS;
end

properties (Access = public, Constant)
    % Default width to display videos at
    DEFAULT_VIDEO_WIDTH = 300;
end

methods
    function gui = DisplayVideos(nwb, width)
        %DISPLAYVIDEOS Show a GUI to play synced videos from an NWB file.
        %
        % Synopsis: gui = DisplayVideos(nwb)
        %
        % Arguments:
        %   nwb: an NwbFile instance containing video data (inter alia)
        %   width: width to display videos at, in pixels (default DEFAULT_VIDEO_WIDTH)
        %
        % A GUI will be created with axes for each video defined within
        % the file.
        %
        % Returns:
        %   a handle for the GUI figure window

        gui.nwb = nwb;
        [~, nwb_name, ~] = fileparts(nwb.path);

        if nargin < 2
            width = gui.DEFAULT_VIDEO_WIDTH;
        end

        % Initialise some of our instance properties
        gui.video_names = nwb.video_names;
        gui.video_paths = nwb.video_paths;
        num_videos = length(gui.video_names);
        gui.videos = cell(1, num_videos);
        gui.last_frames = zeros(1, num_videos);
        gui.start_frames = cell(num_videos, 1);

        gui.find_resized_videos(width);
        gui.create_video_axes(width, nwb_name);
        gui.determine_times();
        gui.create_buttons();
        gui.create_data_axes();
        gui.plot_speed();
        gui.plot_dff();
        gui.step(); % Show first frames
    end
    
    function create_video_axes(gui, width, nwb_name)
        %CREATE_VIDEO_AXES Create the axes for displaying videos.

        num_videos = length(gui.video_names);
        % Figure out how much screen space we need for all videos etc.
        gui.VIDEO_DIMS = [width 0];
        bottom_positions = zeros(1, num_videos);
        dims = zeros(num_videos, 2);
        for i=1:num_videos
            dims(i, :) = gui.get_ts_item(gui.video_names{i}, 'dimension');
            scale = dims(i, 1) / width;
            dims(i, 1) = width;
            dims(i, 2) = round(dims(i, 2) / scale);
            bottom_positions(i) = gui.BUTTON_HEIGHT + gui.GAP + gui.VIDEO_DIMS(2);
            gui.VIDEO_DIMS(2) = gui.VIDEO_DIMS(2) + gui.GAP + dims(i, 2) + gui.BUTTON_HEIGHT;
        end

        fig_width = width + 2*gui.GAP + gui.DATA_WIDTH;
        fig_height = max(gui.VIDEO_DIMS(2), ...
                         gui.DATA_HEIGHT + gui.BUTTON_HEIGHT) ...
            + gui.BUTTON_HEIGHT + 2*gui.GAP;

        % Create the window
        gui.fig = figure('numbertitle', 'off', ...
                         'name', ['Videos from ' nwb_name], ...
                         'menubar', 'none', ...
                         'toolbar', 'none', ...
                         'resize', 'on', ...
                         'position', [10 10 fig_width fig_height], ...
                         'DeleteFcn', @gui.closing);

        % Create axes for each video, showing the initial frame
        gui.video_axes = cell(1, num_videos);
        gui.video_titles = cell(1, num_videos);
        for i=1:num_videos
            our_axes = axes(gui.fig, ...
                'Units', 'pixels', ...
                'Position', [gui.GAP/2, bottom_positions(i), ...
                             dims(i, 1), dims(i, 2)]);
            our_axes.XTick = [];
            our_axes.YTick = [];
            gui.video_axes{i} = our_axes;
            % Set video title using uicontrol. uicontrol is used so that text
            % can be positioned in the context of the figure, not the axis.
            gui.video_titles{i} = uicontrol('style', 'text', ...
                'String', gui.video_names{i}, ...
                'HorizontalAlignment', 'left', ...
                'Units', 'pixels', ...
                'Position', [gui.GAP * 2, ...
                             bottom_positions(i) + dims(i, 2), ...
                             150, gui.BUTTON_HEIGHT], ...
                'Parent', gui.fig, ...
                'BackgroundColor', gui.fig.Color);
        end
        drawnow;
    end

    function create_data_axes(gui)
        %CREATE_DATA_AXES Create axes for displaying functional/speed data.

        left = gui.VIDEO_DIMS(1) + gui.GAP + gui.BUTTON_HEIGHT;
        bottom = gui.BUTTON_HEIGHT + gui.GAP + gui.BUTTON_HEIGHT;
        width = min(gui.DATA_WIDTH, gui.fig.Position(3) - left);

        % Single timeseries data, e.g. speed
        gui.ts_axes = axes(gui.fig, 'Units', 'pixels', ...
            'XLimMode', 'manual', ...
            'ButtonDownFcn', @gui.cb_click, ...
            'OuterPosition', ...
            [left, bottom, width, gui.DATA_HEIGHT/5]);
        gui.tighten_axes(gui.ts_axes);

        % Per-ROI functional data
        gui.roi_axes = axes(gui.fig, 'Units', 'pixels', ...
            'XLimMode', 'manual', ...
            'YLimMode', 'manual', ...
            'ButtonDownFcn', @gui.cb_click, ...
            'OuterPosition', ...
            [left, bottom + gui.DATA_HEIGHT*0.2 + gui.GAP/2, ...
             width, gui.DATA_HEIGHT*0.8]);
        gui.tighten_axes(gui.roi_axes);

        % Structures to hold labels & time lines
        gui.data_labels = struct('roi_y', '', 'ts_x', '', 'ts_y', '');
        gui.data_time_lines = cell(2, 1);

        drawnow;
    end

    function plot_speed(gui)
        %PLOT_SPEED Convenience method to plot speed data from our NWB file
        %
        % Synopsis: gui.plot_speed()
        %
        % Note that we negate the speed data stored in NWB, to match the
        % experimentalists' convention for display.

        speed = gui.nwb.get_trials_data('speed_data');
        speed = cellfun(@(ts) -ts, speed, 'UniformOutput', false);
        speed_t = gui.nwb.get_trials_data('speed_data', 'timestamps');
        gui.plot_ts_data(speed, speed_t, 'Time (s)', 'Speed');
    end

    function plot_dff(gui)
        %PLOT_DFF Convenience method to compute & plot df/f.
        %
        % Synopsis: gui.plot_dff()
        %
        % TODO: Make choice of baseline flexible.

        disp('Calculating df/f...');
        [green, ~, dff_times] = gui.nwb.get_roi_data('Green');
        len = int32(size(green, 3) / 4);
        baseline = mean(green(:,:,1:len), 3);
        dff = (green - baseline) ./ baseline;
        gui.plot_roi_data(dff, dff_times, 'df/f for ROI #');
    end

    function plot_ts_data(gui, data, times, label_x, label_y)
        %PLOT_TS_DATA Plot timeseries data on the bottom axes.
        %
        % Synopsis: gui.plot_ts_data(data, times)
        %
        % Arguments:
        %   data: the data to plot, as a cell array (length #trials) of
        %         1d timeseries arrays
        %   times: cell array of timestamps corresponding to each point in
        %          data
        %   label_x: label for the x axis
        %   label_y: label for the y axis

        gui.ts_data = data;
        gui.ts_times = times;
        gui.data_labels.ts_x = label_x;
        gui.data_labels.ts_y = label_y;
        gui.update_ts_data_display();
    end

    function plot_roi_data(gui, data, times, label_y)
        %PLOT_ROI_DATA Plot some data on the top ROI axes.
        %
        % Synopsis: gui.plot_roi_data(data, times)
        %
        % Arguments:
        %   data: the data to plot, as a (#trials, #rois, #times) array
        %   times: array of timestamps corresponding to each point in data
        %   label_y: label for the y axis

        gui.roi_data = data;
        gui.roi_times = times;
        gui.data_labels.roi_y = label_y;
        gui.update_roi_data_display();
    end

    function update_ts_data_display(gui)
        %UPDATE_TS_DATA_DISPLAY Refresh the timeseries data axes.
        %   Internal helper method.

        trial = gui.current_trial;
        data = gui.ts_data{trial};
        times = gui.ts_times{trial} - gui.trial_times(trial);

        plot(gui.ts_axes, times, data, 'k-', ...
             'LineWidth', 1, 'HitTest', 'off');
        xlim(gui.ts_axes, [0, times(end)]);
        xlabel(gui.ts_axes, gui.data_labels.ts_x, ...
            'FontName', 'Helvetica', 'FontUnits', 'points', 'FontSize', 10);
        ylabel(gui.ts_axes, gui.data_labels.ts_y, ...
            'FontName', 'Helvetica', 'FontUnits', 'points', 'FontSize', 10);
        gui.ts_axes.ButtonDownFcn = @gui.cb_click;
        drawnow;
    end

    function update_roi_data_display(gui)
        %UPDATE_ROI_DATA_DISPLAY Refresh the ROI data axes.

        trial = gui.current_trial;
        trial_start = gui.trial_times(trial);
        data = gui.roi_data;
        times = gui.roi_times;
        n_roi = size(data, 2);

        cla(gui.roi_axes);
        hold(gui.roi_axes, 'on');
        alpha(gui.roi_axes, 0.5);

        for i = 1:n_roi
            plot(gui.roi_axes, ...
                 squeeze(times(trial,i,:) - trial_start), ...
                 squeeze(i + data(trial,i,:)), 'k-', ...
                 'HitTest', 'off');
        end;
        xlim(gui.roi_axes, [0, max(times(trial, :, end)) - trial_start]);
        ylim(gui.roi_axes, [0, n_roi]);
        ylabel(gui.roi_axes, gui.data_labels.roi_y, ...
            'FontName', 'Helvetica', 'FontUnits', 'points', 'FontSize', 10);
        gui.roi_axes.ButtonDownFcn = @gui.cb_click;
        drawnow;
    end

    function update_data_display(gui)
        %UPDATE_DATA_DISPLAY Replot data, e.g. due to trial changing.

        gui.update_roi_data_display();
        gui.update_ts_data_display();
    end

    function show_data_time(gui)
        %SHOW_DATA_TIME Indicate the current time on the data axes.

        t = gui.current_time - gui.trial_times(gui.current_trial);
        data_axes = [gui.ts_axes, gui.roi_axes];
        for i=1:2
            ax = data_axes(i);
            l = gui.data_time_lines{i};
            if isempty(l) || ~isgraphics(l)
                gui.data_time_lines{i} = line(ax, ...
                    [t t], ax.YLim, 'Color', 'r');
            else
                l.XData = [t t];
                l.YData = ax.YLim;
            end
        end
    end

    function tighten_axes(~, ax)
        %TIGHTEN_AXES Remove excess space around the central plot.
        %  Also sets font properties.

        ax.FontName = 'Helvetica';
        ax.FontUnits = 'points';
        ax.FontSize = 10;
        ax.FontWeight = 'normal';
        ax.FontAngle = 'normal';

        outerpos = ax.OuterPosition;
        ti = ax.TightInset;
        left = outerpos(1) + ti(1);
        bottom = outerpos(2) + ti(2);
        ax_width = outerpos(3) - ti(1) - ti(3);
        ax_height = outerpos(4) - ti(2) - ti(4);
        ax.Position = [left bottom ax_width ax_height];
    end

    function create_buttons(gui)
        %CREATE_BUTTONS Add UI controls to control play-back.

        gui.buttons = struct;
        left = gui.GAP / 2;
        bottom = gui.GAP / 2;
        % Restart button
        width = 40;
        gui.buttons.restart = uicontrol('Style', 'pushbutton', ...
            'String', 'Restart', ...
            'Position', [left bottom width gui.BUTTON_HEIGHT], ...
            'Interruptible', 'off', ...
            'Callback', @gui.cb_restart);
        left = left + width + gui.GAP;
        % Play button
        width = 40;
        gui.buttons.play = uicontrol('Style', 'pushbutton', ...
            'String', 'Play', ...
            'Position', [left bottom width gui.BUTTON_HEIGHT], ...
            'Callback', @gui.cb_play);
        left = left + width + gui.GAP;
        % Play mode menu
        width = 80;
        uicontrol('Style', 'text', 'String', 'Playback mode:', ...
            'Position', [left bottom width gui.BUTTON_HEIGHT], ...
            'HorizontalAlignment', 'right', ...
            'BackgroundColor', gui.fig.Color);
        left = left + width + 1;
        width = 150;
        gui.buttons.play_mode = uicontrol('Style', 'popupmenu', ...
            'Position', [left bottom width gui.BUTTON_HEIGHT], ...
            'String', {'Frame-by-frame', 'Fast'});
        left = left + width + gui.GAP;
        % Time slider
        width = 30;
        uicontrol('Style', 'text', 'String', 'Time:', ...
            'Position', [left bottom width gui.BUTTON_HEIGHT], ...
            'HorizontalAlignment', 'right', ...
            'BackgroundColor', gui.fig.Color);
        left = left + width + 1;
        width = 150;
        gui.buttons.time = uicontrol('Style', 'slider', ...
            'Position', [left bottom width gui.BUTTON_HEIGHT], ...
            'Min', gui.joint_t(1), 'Max', gui.joint_t(end), ...
            'Value', gui.current_time, ...
            'SliderStep', [0.001 0.05], ...
            'Interruptible', 'off', ...
            'Callback', @gui.cb_time);
        setappdata(gui.buttons.time, 'lastValue', gui.current_time);
        left = left + width + gui.GAP;
        % Trial dropdown menu
        width = 30;
        uicontrol('Style', 'text', 'String', 'Trial:', ...
            'Position', [left bottom width gui.BUTTON_HEIGHT], ...
            'HorizontalAlignment', 'right', ...
            'BackgroundColor', gui.fig.Color);
        left = left + width + 1;
        width = 100;
        gui.buttons.trial = uicontrol('Style', 'popupmenu', ...
            'Position', [left bottom width gui.BUTTON_HEIGHT], ...
            'String', arrayfun(@num2str, 1:gui.nwb.num_trials, 'UniformOutput', false), ...
            'Interruptible', 'off', ...
            'Callback', @gui.cb_trial);
        % Display controls now
        drawnow;
    end

    function cb_trial(gui, source, ~)
        % Callback function for the trial drop-down
        if source.Value ~= gui.current_trial
            trial_start = gui.trial_times(source.Value);
            t = find(gui.joint_t >= trial_start, 1);
            gui.display_frame(t);
        end
    end

    function cb_time(gui, source, ~)
        % Callback function for the time slider
        if source.Value == gui.current_time
            % We're playing, and display_frame has 'reset' time already
            source.Value = getappdata(source, 'lastValue');
        end
        gui.set_time(source.Value);
    end
    
    function cb_restart(gui, ~, ~)
        % Callback function for the restart button
        gui.display_frame(1);
    end
    
    function cb_play(gui, ~, ~)
        % Callback function for play/pause button
        if ~gui.playing
            gui.play();
        else
            gui.stop();
        end
    end
    
    function cb_click(gui, source, ~)
        % Callback function for mouse click within axes
        loc = source.CurrentPoint(1, 1);
        if loc >= 0 && loc <= source.Position(3)
            gui.set_time(loc + gui.trial_times(gui.current_trial));
        end
    end

    function playing = get.playing(gui)
        %PLAYING Determine whether the videos are currently playing
        playing = ~strcmp(gui.buttons.play.String, 'Play');
    end
    
    function was_playing = stop(gui)
        % Stop video playback
        was_playing = gui.playing;
        gui.buttons.play.String = 'Play';
        drawnow; % Let any playing callback complete and stop playback
    end

    function closing(gui, varargin)
        % Called when the user closes the main GUI window
        if (isstruct(gui.buttons) && isfield(gui.buttons, 'play') && ...
                isgraphics(gui.buttons.play))
            gui.stop();
        end
        gui.videos = {}; % Close video files
    end

    function determine_times(gui)
        %DETERMINE_TIMES Figure out timestamp information

        num_videos = length(gui.video_names);
        for i=1:num_videos
            % Open (first) video file
            gui.open_video(i, 1);
            gui.last_frames(i) = 0; % Nothing shown yet

            % Check for multi-file videos
            gui.start_frames{i} = gui.get_ts_attr(gui.video_names{i}, ...
                'external_file', 'starting_frame');
        end

        % Figure out merged timestamp information
        gui.video_times = cell(num_videos, 1);
        num_frames = cell(num_videos, 2);
        for i=1:num_videos
            gui.video_times{i} = gui.get_ts_item(gui.video_names{i}, 'timestamps');
            num_frames{i, 1} = numel(gui.video_times{i});
            if i == 1
                last = [0 0];
            else
                last = num_frames{i-1, 2};
            end
            num_frames{i, 2} = (last(end)+1):(last(end)+num_frames{i, 1});
        end
        [gui.joint_t, ~, idx_backward] = unique(horzcat(gui.video_times{:}));

        % Calculate where in joint_t each video has frames
        gui.video_frames = cell(num_videos, 1);
        for i=1:num_videos
            frames = NaN(size(gui.joint_t));
            frames(idx_backward(num_frames{i,2})) = 1:num_frames{i,1};
            gui.video_frames{i} = frames;
        end

        % No frames yet shown
        gui.last_frame = 0;
    end

    function find_resized_videos(gui, width)
        %FIND_RESIZED_VIDEOS Check for pre-resized videos.
        %
        % If the resize_videos() function has been used to generate
        % versions of our videos at the size we want, update our paths to
        % use those instead.
        %
        % Arguments:
        %   gui: the gui instance
        %   width: the width of video files to look for

        for i=1:length(gui.video_paths)
            for j=1:length(gui.video_paths{i})
                path = gui.video_paths{i}{j};
                sized_path = gui.resized_path(path, width);
                if exist(sized_path, 'file')
                    gui.video_paths{i}{j} = sized_path;
                end
            end
        end
    end

    function open_video(gui, video_index, file_index)
        %OPEN_VIDEO Internal function to open a video file for reading.
        %
        % Arguments:
        %   gui: the gui instance
        %   video_index: which video this is in our list
        %   file_index: which .avi file to open for this video
        
        path = gui.video_paths{video_index}{file_index};
        disp(['Opening ' path]);
        gui.videos{video_index} = VideoReader(path);
    end
    
    function set_time(gui, time)
        %SET_TIME Display the closest frame to the given time.
        %
        % Arguments:
        %   gui: the gui instance
        %   time: time in seconds to display; the latest frame not after
        %         this is selected

        t = find(gui.joint_t <= time, 1, 'last');
        gui.display_frame(t);
    end
    
    function current_time = get.current_time(gui)
        % The timestamp (in seconds) of the currently displayed frame.
        if gui.last_frame == 0
            current_time = gui.joint_t(1);
        else
            current_time = gui.joint_t(gui.last_frame);
        end
    end

    function trial = get.current_trial(gui)
        % Which trial corresponds to the current timestamp.

        if isempty(gui.trial_times)
            % Retrieve trial start times from the NWB file.
            n_trials = gui.nwb.num_trials;
            gui.trial_times = zeros(n_trials, 1);
            for i=1:n_trials
                gui.trial_times(i) = gui.nwb.get('/epochs/trial_%04d/start_time', i);
            end
        end
        trial = find(gui.trial_times <= gui.current_time, 1, 'last');
        if isempty(trial)
            trial = 1;
        end
    end

    function set_title(gui, i, colour)
        %SET_TITLE Update the title for video i.
        %
        % Displays the camera name and current time (in seconds relative
        % to trial start) in the given colour.
        trial = gui.current_trial;
        trial_start = gui.trial_times(trial);
        rel_time = gui.video_times{i}(gui.last_frames(i)) - trial_start;
        gui.video_titles{i}.String = [gui.video_names{i} ', t = ' ...
            num2str(rel_time) ' s'];
        gui.video_titles{i}.ForegroundColor = colour;
    end

    function display_frame(gui, t)
        %DISPLAY_FRAME Show a single frame for each video.
        %
        % Typically used to show the next frame.
        %
        % Arguments:
        %   gui: the gui instance
        %   t: index of the frame to display within the joint timeseries

        num_videos = length(gui.videos);
        title_cols = cell(1, num_videos);
        for i=1:num_videos
        our_t = gui.video_frames{i}(t); % Index to display within this video
        our_last_frame = gui.last_frames(i);
        if isnan(our_t)
            % If we're jumping, find the most recent frame to show
            if t ~= gui.last_frame + 1
                idx = find(~isnan(gui.video_frames{i}(1:t)), 1, 'last');
                our_t = gui.video_frames{i}(idx);
                gui.last_frames(i) = our_t;
            end
            % Show an indication that this is a stale frame
            title_cols{i} = 'red';
        else
            gui.last_frames(i) = our_t;
            title_cols{i} = 'black';
        end
        if ~isnan(our_t)
            % Figure out if we need to change video file
            last_file = gui.calculate_file_index(i, our_last_frame);
            curr_file = gui.calculate_file_index(i, our_t);
            if last_file ~= curr_file
                gui.open_video(i, curr_file);
            end
            % Read the requested frame
            video = gui.videos{i};
            if our_last_frame ~= our_t - 1
                % Random access read - need to compute desired "time"
                frame_offset = our_t - gui.start_frames{i}(curr_file) - 1;
                video.CurrentTime = double(frame_offset) / video.FrameRate;
            end
            if ~video.hasFrame()
                disp(['No next frame for ' num2str(i) ' at ' num2str(t)]);
                title_cols{i} = 'magenta';
                continue;
            end
            frame = video.readFrame(); % Next frame read
            % Show the frame
            our_axes = gui.video_axes{i};
            if ~isgraphics(our_axes) % Just in case!
                return;
            end
            frame = imresize(frame, our_axes.Position(3:4));
            image(our_axes, frame);
            our_axes.Visible = 'off';
        end
        end
        % Update which frame was just displayed
        last_trial = gui.current_trial;
        gui.last_frame = t;
        setappdata(gui.buttons.time, 'lastValue', gui.buttons.time.Value);
        gui.buttons.time.Value = gui.joint_t(t);
        % Update all video titles now so they get the correct trial offset
        for i=1:num_videos
            gui.set_title(i, title_cols{i});
        end
        if last_trial ~= gui.current_trial
            gui.buttons.trial.Value = gui.current_trial;
            gui.update_data_display();
        end
        gui.show_data_time();
        drawnow; % Allow other callbacks to be processed at this point
    end
    
    function file_index = calculate_file_index(gui, i, t)
        %FILE_INDEX Determine which .avi file contains the given time.
        %
        % Arguments:
        %   gui: the gui instance
        %   i: index of the video to query
        %   t: index of the frame to query
       
        is_after_start = gui.start_frames{i} < t;
        file_index = find(is_after_start, 1, 'last'); % Take the last index
    end
    
    function step(gui, count)
        %STEP Display the next frame for all videos.
        if nargin == 1
            count = 1;
        end
        gui.display_frame(gui.last_frame + count);
    end
    
    function play(gui, duration, duration_type)
        %PLAY Play a sequence of frames from all videos.
        %
        % By default will play until the end of the recordings, but a
        % duration may be given to play just for that long.
        %
        % Arguments:
        %   gui: the gui instance
        %   duration: how many seconds/frames to play
        %   duration_type: optional; either 'seconds' (default) or 'frames'

        gui.buttons.play.String = 'Pause';

        if nargin >= 2
            if nargin == 2
                duration_type = 'seconds';
            end
            if strcmp(duration_type, 'frames')
                end_frame = gui.last_frame + duration;
            else
                end_frame = find(...
                    gui.joint_t <= gui.current_time + duration, 1, 'last');
            end
        else
            end_frame = length(gui.joint_t);
        end
        if end_frame > length(gui.joint_t)
            end_frame = length(gui.joint_t);
        end

        % Figure out how many frames to skip for fast playback
        fast = gui.buttons.play_mode.Value == 2;
        if fast % Play ~10 frames / second
            frame_duration = max(diff(gui.joint_t(1:30)));
            skip_rate = floor(0.1 / frame_duration);
        else
            skip_rate = 1; % Play every frame
        end

        while isgraphics(gui.fig) && gui.last_frame < end_frame && gui.playing
            gui.step(skip_rate);
        end
    end

    function data = get_ts_item(gui, ts_name, item_name)
        %GET_TS_ITEM Get a dataset from an acquired timeseries.
        path = ['/acquisition/timeseries/' ts_name '/' item_name];
        data = gui.nwb.get(path);
    end

    function value = get_ts_attr(gui, ts_name, item_name, attr_name)
        %GET_TS_ATTR Get an attribute of a dataset within a timeseries.
        path = ['/acquisition/timeseries/' ts_name '/' item_name];
        value = numpy2mat(gui.nwb.h5py.get(path).attrs{attr_name});
    end

end % methods

methods (Static)
    function sized_path = resized_path(original_path, width)
        %RESIZED_PATH Determine the a resized version of the given path.
        %
        % Synopsis: DisplayVideos.resized_path(original_path, width)
        %
        % Arguments:
        %   original_path: the original (video) path to consider
        %   width: the desired video width
        %
        % Returns a path like 'folder/base-width300.avi' when the original
        % is called 'folder/base.mj2'.

        [base, name, ~] = fileparts(original_path);
        sized_path = [base filesep name '-width' num2str(width) '.mj2'];
    end
end

end % class
