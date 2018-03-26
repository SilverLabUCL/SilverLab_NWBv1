classdef (SharedTestFixtures=SharedFixtures()) ...
        TestNumpy2mat < matlab.unittest.TestCase
    %TESTNUMPY2MAT Test the data conversion utilities
    
    properties
    end
    
    methods (Test)
        function testTuple(testCase)
            %TESTTUPLE Check we can convert tuples
            
            actual = tuple2mat(py.tuple([1, 2]));
            testCase.verifyEqual(actual, [1 2]);
            testCase.verifyClass(actual, 'double');
            
            actual = tuple2mat(py.tuple([1, 2]), @int64);
            testCase.verifyEqual(actual, int64([1 2]));
            testCase.verifyClass(actual, 'int64');
        end
        
        function testScalars(testCase)
            %TESTSCALARS Check we can convert scalar values
            
            actual = numpy2mat(py.numpy.float64(1.0));
            testCase.verifyEqual(actual, 1.0);
            testCase.verifyClass(actual, 'double');
            
            actual = numpy2mat(py.numpy.int32(2));
            testCase.verifyEqual(actual, 2);
            testCase.verifyClass(actual, 'double');
        end
        
        function test1d(testCase)
            %TEST1D Check conversion of 1d arrays
            
            actual = numpy2mat(py.numpy.arange(5));
            testCase.verifyEqual(actual, 0:4);
            testCase.verifyClass(actual, 'double');
            
            actual = numpy2mat(py.numpy.arange(5, ...
                pyargs('dtype', 'int8')));
            testCase.verifyEqual(actual, 0:4);
            testCase.verifyClass(actual, 'double');
        end
        
        function test2d(testCase)
            %TEST2D Check conversion of 2d arrays
            
            actual = numpy2mat(py.numpy.arange(6).reshape(...
                py.int(2), py.int(3)));
            testCase.verifyEqual(actual, [0 1 2; 3 4 5]);
            testCase.verifyClass(actual, 'double');
            
            actual = numpy2mat(py.numpy.arange(6, ...
                pyargs('dtype', 'float32')).reshape(...
                py.int(2), py.int(3)));
            testCase.verifyEqual(actual, [0 1 2; 3 4 5]);
            testCase.verifyClass(actual, 'double');
        end
        
        function test3d(testCase)
            %TEST3D Check conversion of 3d arrays
            
            actual = numpy2mat(py.numpy.arange(24).reshape(...
                py.int(2), py.int(3), py.int(4)));
            expected = zeros(2,3,4);
            expected(1, :, :) = [0 1 2 3; 4 5 6 7; 8 9 10 11];
            expected(2, :, :) = expected(1, :, :) + 12;
            testCase.verifyEqual(actual, expected);
            testCase.verifyClass(actual, 'double');
            
            actual = numpy2mat(py.numpy.arange(24, ...
                pyargs('dtype', 'uint16')).reshape(...
                py.int(2), py.int(3), py.int(4)));
            testCase.verifyEqual(actual, expected);
            testCase.verifyClass(actual, 'double');
        end
    end
end

