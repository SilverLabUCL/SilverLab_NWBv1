classdef LabviewHeader < handle
    %LABVIEWHEADER Provides access to information from a LabView .ini file.
    %
    % Construct instances of this class passing the path to an
    % 'Experiment Header.ini' file, and then easily access any variable
    % defined within any section of the file by name.
    %
    % Example: given a .ini file looking like:
    %
    %   [LOGIN]
    %   User = "Angus"
    %   [GLOBAL PARAMETERS]
    %   number of poi = 150.000000
    %   # averaged frames = 16.000000
    %   laser power (%) = 60.000000
    %   pockels = -1.000000
    %   [MOVEMENT CORRECTION]
    %   MovCor Enabled? = TRUE
    %   Reference Size = "15 x 18 pixels"
    %   [STATISTICS]
    %   Z-stack duration (sec) = 56.674242
    %
    % Loading this with
    %
    %   header = LabviewHeader('file.ini', 'GLOBAL PARAMETERS');
    %
    % will let you do things like:
    %
    %   header.hasSection('GLOBAL PARAMETERS') -> true
    %   header.sections() -> {'GLOBAL PARAMETERS', 'LOGIN', ...
    %                         'MOVEMENT CORRECTION', 'STATISTICS'}
    %   header.hasItem('LOGIN', 'User') -> true
    %   header.item('LOGIN', 'User') -> 'Angus'
    %   header.item('# averaged frames') -> 16
    %   header.defaultSection = 'MOVEMENT CORRECTION';
    %   header.item('MovCor Enabled?') -> true
    
    methods
        function obj = LabviewHeader(ini_path, default_section)
            %LABVIEWHEADER Construct a new .ini file wrapper.
            %
            % Synopsis: obj = LabviewHeader(ini_path, default_section)
            %
            % Arguments:
            %   ini_path: optional path to .ini file to load
            %   default_section: optional default section in which to look up items
            %
            % If the path to the .ini file is not supplied, the load()
            % method must be called to read a file before its contents can
            % be accessed.
            
            obj.path = '';
            obj.info = containers.Map;
            if nargin > 0
                obj.load(ini_path);
            end
            if nargin > 1
                obj.defaultSection = default_section;
            else
                obj.defaultSection = '';
            end
        end
        
        function load(obj, ini_path)
            %LOAD Load information from the given .ini file.
            %
            % Synopsis: obj.load(ini_path)
            
            obj.path = ini_path;
            obj.info = containers.Map;

            current_section = ''; % Orphaned items go in an empty section
            f = fopen(ini_path, 'r');
            c = onCleanup(@() fclose(f)); % Ensure file gets closed
            while ~feof(f)
                s = strtrim(fgetl(f));
                if isempty(s) || s(1) == ';'
                    continue; % Skip blank lines & comments
                end;
                if ( s(1)=='[' ) && (s(end)==']' )
                    % Start of a section
                    current_section = s(2:end-1);
                    obj.info(current_section) = containers.Map;
                else
                    % Item definition
                    [name, value_text] = strtok(s, '=');
                    name = strtrim(name);
                    assert(length(value_text) > 1, 'Malformed .ini line "%s"', s);
                    if isempty(current_section) && ~obj.info.isKey('')
                        % We only create an empty section if necessary!
                        obj.info('') = containers.Map;
                    end
                    value = parseValue(value_text(2:end)); % Remove '=' from start
                    section = obj.info(current_section);
                    section(name) = value; %#ok<NASGU>
                end
            end
        end
        
        function present = hasSection(obj, section)
            %HASSECTION Check whether a section exists in the header.
            %
            % Synopsis: present = obj.hasSection(section)
            
            present = obj.info.isKey(section);
        end
        
        function sections = sections(obj)
            %SECTIONS Get a cell array listing the header's sections.
            %
            % Synopsis: sections = obj.sections()
            %
            % The return array contains the names of the sections in
            % alphabetical order.
            sections = obj.info.keys();
        end
        
        function present = hasItem(obj, section, name)
            %HASITEM Check whether the header contains a specific item.
            %
            % Synopsis: present = obj.hasItem(section, name)
            % Synopsis: present = obj.hasItem(name)
            %
            % Checks for existence of an item with the given name inside
            % the given section. If only one argument is given, the
            % defaultSection property is used for the section name.
            
            if nargin == 2
                name = section;
                section = obj.defaultSection;
            end
            present = obj.info.isKey(section) && obj.info(section).isKey(name);
        end
        
        function value = item(obj, section, name)
            %ITEM Get the value of a specific item within the header.
            %
            % Synopsis: value = obj.item(section, name)
            % Synopsis: value = obj.item(name)
            %
            % Returns the value of the item with given name inside the
            % given section, if present, and throws an error if the item is
            % not present. If only one argument is given, the
            % defaultSection property is used for the section name.
            
            if nargin == 2
                name = section;
                section = obj.defaultSection;
            end
            if obj.hasItem(section, name)
                sect = obj.info(section);
                value = sect(name);
            else
                error('LabviewHeader:item:missing', 'No item "%s" in header section "%s".', name, section);
            end
        end
        
        function names = itemNames(obj, section)
            %ITEMNAMES Lists the names of items within the given section.
            %
            % Synopsis: names = obj.itemNames(section)
            %
            % Names will be returned within a cell array in alphabetical
            % order. An assertion is tripped if the section does not exist.
            
            if nargin == 1
                section = obj.defaultSection;
            end
            assert(obj.hasSection(section), 'No section named "%s".', section);
            names = obj.info(section).keys();
        end
    end
    
    properties (Access = public)
        % Path to the .ini file wrapped by this object.
        path;
        % Default section to use for item lookup, if not specified in
        % methods.
        defaultSection;
    end
    
    properties (Access = private)
        % The actual header info, as a nested map.
        info;
    end
end

function value = parseValue(s)
    %PARSEVALUE Helper function to parse an item value.
    %
    % Will strip off leading/trailing whitespace and the =
    % character.
    %
    % "any text" -> char array "any text"
    % TRUE       -> true
    % FALSE      -> false
    % anything else is assumed to be a number
    
    s = strtrim(s);
    if ~isempty(s) && (s(1) == '"' || s(1) == '''')
        assert(s(1) == s(end), 'Mismatched string quotes in value: %s', s);
        value = s(2:end-1);
    elseif strcmp(s, 'TRUE')
        value = true;
    elseif strcmp(s, 'FALSE')
        value = false;
    else
        value = str2double(s);
    end
end
