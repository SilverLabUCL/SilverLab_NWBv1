function resize_videos(nwb, width)
%RESIZE_VIDEOS Create resized versions of videos referenced in an NWB file
%
% Synopsis: resize_videos(nwb, width)
%
% Arguments:
%   nwb: the NWB file to read to determine what videos to resize
%   width: the desired width for each video; defaults to
%     DisplayVideos.DEFAULT_VIDEO_WIDTH
%
% The scaling of each video will be maintained. Resized videos will be
% written to files in the same folders as the originals, with names like
% 'base-width300.mp4' when the original is called 'base.avi'.

if nargin < 2
    width = DisplayVideos.DEFAULT_VIDEO_WIDTH;
end

video_paths = nwb.video_paths;
num_videos = length(video_paths);

for i=1:num_videos
    num_files = length(video_paths{i});
    for j=1:num_files
        video_path = video_paths{i}{j};
        output_path = DisplayVideos.resized_path(video_path, width);
        disp(['Resizing ' video_path ' to ' output_path '...']);

        reader = vision.VideoFileReader(video_path, ...
            'VideoOutputDataType', 'uint8');
        writer = vision.VideoFileWriter(output_path, ...
            'FrameRate', reader.info.VideoFrameRate, ...
            'FileFormat', 'MJ2000');
%             'FileFormat', 'MPEG4', 'Quality', 90);

        scale = reader.info.VideoSize(1) / width;
        height = round(reader.info.VideoSize(2) / scale);

        while ~reader.isDone()
            frame = reader.step();
            frame = imresize(frame, [width height]);
            writer.step(frame);
        end

        writer.release();
        reader.release();
    end
end

end
