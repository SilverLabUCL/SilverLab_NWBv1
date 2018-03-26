classdef (SharedTestFixtures=SharedFixtures()) ...
    TestLabviewHeader < matlab.unittest.TestCase
    %TESTLABVIEWHEADER Tests of the LabviewHeader class.
    
    properties
    end
    
    methods (Test)
        function testLoadingSampleHeader(testCase)
            %TESTLOADINGSAMPLEHEADER Check a full-featured sample.
            
            header = LabviewHeader('data/sample_header.ini', 'LOGIN');
            testCase.checkHeaderContents(header);
        end
        
        function testDefaultConstructor(testCase)
            %TESTDEFAULTCONSTRUCTOR Check can construct and load separately.
            
            header = LabviewHeader();
            testCase.verifyEmpty(header.path);
            testCase.verifyEmpty(header.defaultSection);
            testCase.verifyEmpty(header.sections());
            testCase.verifyFalse(header.hasSection('blah'));
            testCase.verifyFalse(header.hasItem('item'));
            
            header.defaultSection = 'LOGIN';
            header.load('data/sample_header.ini');
            testCase.checkHeaderContents(header);
        end
    end
    
    methods
        function checkHeaderContents(testCase, header)
            %CHECKHEADERCONTENTS Check the contents of the sample .ini.
            
            testCase.verifyMatches(header.path, '.*sample_header\.ini');
            testCase.verifyEqual(header.defaultSection, 'LOGIN');

            testCase.verifyEqual(header.sections(), ...
                {'', 'GLOBAL PARAMETERS', 'LOGIN', ...
                 'MOVEMENT CORRECTION','STATISTICS'});
            testCase.verifyTrue(header.hasSection('LOGIN'));

            testCase.verifyTrue(header.hasItem('GLOBAL PARAMETERS', 'pockels'));
            testCase.verifyTrue(header.hasItem('User'));
            testCase.verifyEqual(header.item('User'), 'Angus');
            testCase.verifyEqual(header.item('', 'Orphan item'), 'Poor me!');

            testCase.verifyEqual(header.itemNames(), {'User'});
            testCase.verifyEqual(header.itemNames('MOVEMENT CORRECTION'), ...
                {'MovCor Enabled?', 'Reference Size'});

            header.defaultSection = 'GLOBAL PARAMETERS';
            testCase.verifyEqual(header.item('# averaged frames'), 16.0);
            testCase.verifyEqual(header.item('laser power (%)'), 60.0);
            testCase.verifyEqual(header.item('pockels'), -1);

            testCase.verifyEqual(header.item('STATISTICS', 'Z-stack duration (sec)'), ...
                56.67, 'AbsTol', 0.01);
            testCase.verifyEqual(header.item('STATISTICS', 'Z-stack duration (sec)'), ...
                56.674242, 'AbsTol', 0.000001);
            testCase.verifyEqual(header.item('MOVEMENT CORRECTION', 'Reference Size'), ...
                '15 x 18 pixels');
            
            testCase.verifyError(@() header.item('blah'), 'LabviewHeader:item:missing');
            testCase.verifyError(@() header.item('LOGIN', 'oops'), 'LabviewHeader:item:missing');
        end
    end
    
end

