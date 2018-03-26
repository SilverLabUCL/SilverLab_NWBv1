function result = numpy2mat( nparray )
%NUMPY2MAT Convert a numpy.ndarray to a Matlab array
% 
% Synopsis: result = numpy2mat(nparray)
%
% Arguments:
%   nparray: a numpy n-dimensional array coming from Matlab's Python
%            interface. Can be a numpy scalar too.
%
% Returns:
%   a standard Matlab array containing the same data, in the natural
%   layout for Matlab. The array data type will always be double.
%
% Based on https://uk.mathworks.com/matlabcentral/answers/157347-convert-python-numpy-array-to-double

shape = tuple2mat(nparray.shape);
if numel(shape) <= 1
    % This is a simple operation
    result = double(py.array.array('d', py.numpy.nditer(nparray)));
elseif length(shape) == 2
    % order='F' is used to get data in column-major order (as in Fortran
    % 'F' and Matlab)
    iter = py.numpy.nditer(nparray, pyargs('order', 'F'));
    arr = double(py.array.array('d', iter));
    result = reshape(arr, shape);
else
    % For multidimensional arrays more manipulation is required
    % First recover in python order (C contiguous order)
    iter = py.numpy.nditer(nparray, pyargs('order', 'C'));
    result = double(py.array.array('d', iter));
    % Switch the order of the dimensions (as Python views this in the
    % opposite order to Matlab) and reshape to the corresponding C-like
    % array
    result = reshape(result, fliplr(shape));
    % Now transpose rows and columns of the 2D sub-arrays to arrive at the
    % correct Matlab structuring
    result = permute(result, length(shape):-1:1);
end

end

