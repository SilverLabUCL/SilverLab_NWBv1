function result = tuple2mat(tuple, converter)
%TUPLE2MAT Convert a Python tuple to a Matlab array
%
% Synopsis: result = tuple2mat(tuple, converter)
%
% Arguments:
%   tuple: the Python tuple to convert
%   converter: optional function handle for converting items in the tuple;
%              defaults to @double

if nargin < 2
    converter = @double;
end

result = cellfun(converter, cell(tuple));

end

