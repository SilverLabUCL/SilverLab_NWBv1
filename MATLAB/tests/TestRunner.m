function result = TestRunner(do_coverage)
%TESTRUNNER Run the Silver Lab Analysis Pipeline tests.
%
% Pass true as an argument to generate a coverage report.

if nargin < 1
    do_coverage = false;
end

import matlab.unittest.TestRunner;
import matlab.unittest.TestSuite;
import matlab.unittest.plugins.CodeCoveragePlugin

[tests_folder, ~, ~] = fileparts(mfilename('fullpath'));
source_folder = fullfile(tests_folder, '..', 'source');

suite_folder = TestSuite.fromFolder(tests_folder);
runner = TestRunner.withTextOutput;

if do_coverage
    % We have to setup our path fixture here, rather than per test, for the
    % coverage plugin to work!
    % https://uk.mathworks.com/matlabcentral/fileexchange/33972-coverage-report-generator
    % may be a better option for the future...
    fixtures = SharedFixtures();
    fixtures{1}.setup();
    c = onCleanup(@() fixtures{1}.teardown());
    runner.PrebuiltFixtures = fixtures{1};
    % At present this will only show coverage of the test code (if path changed), not source...
    runner.addPlugin(CodeCoveragePlugin.forFolder(source_folder));
    result = runner.run(suite_folder);
else
    result = runner.run(suite_folder);
end

end