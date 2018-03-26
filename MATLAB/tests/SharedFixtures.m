function fixtures = SharedFixtures
    %SHAREDFIXTURES Shared fixtures for Silver Lab Analysis Pipeline tests.
    %
    % Sets up paths so source files are found.
    % Also defines a shared temporary folder.

    import matlab.unittest.fixtures.PathFixture;

    tests_folder = fileparts(mfilename('fullpath'));
    source_folder = fullfile(tests_folder, '..', 'source');

    fixtures = {...
        PathFixture(source_folder, 'IncludingSubfolders', true), ...
        matlab.unittest.fixtures.TemporaryFolderFixture};

end

