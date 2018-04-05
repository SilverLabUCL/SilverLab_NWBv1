REM Installer script for the SilverLab AnalysisPipeline software + dependencies

REM Settings
SET conda_env_name=nwb
SET python_version=2.7
SET nwb_api_folder=nwb_api_python
SET nwb_api_uri="https://github.com/SilverLabUCL/api-python"
SET our_folder=%cd%

REM Set up our conda environment
echo "Setting up conda environment..."
conda env remove -q -y -n %conda_env_name%
conda create --yes -n %conda_env_name% python=%python_version%
conda install --yes -n %conda_env_name% numpy=1.13.0
conda install --yes -n %conda_env_name% hdf5=1.8.12 h5py=2.7.0 -c jonc
conda install --yes -n %conda_env_name% av=0.3.3 tifffile=0.12.1 -c conda-forge
call activate %conda_env_name%

REM Install the NWB API
REM Note that we can't just pip install direct from GitHub as we also need the Matlab bridge
echo "Installing NeurodataWithoutBorders API..."
IF EXIST %nwb_api_folder% (
    git -C %nwb_api_folder% pull --ff-only
) ELSE (
    git clone %nwb_api_uri% %nwb_api_folder%
)
cd %nwb_api_folder%
pip install -e .

REM Install the analysis pipeline
echo "Installing Silver Lab analysis pipeline..."
cd %our_folder%/Python
pip install -r "requirements/main.in"
pip install -e .

REM Set up Matlab to use the pipeline & NWB
echo "Setting up Matlab..."
FOR /F "delims=" %%i IN ('python -c "import sys; print(sys.executable)"') DO SET python=%%i
SET cmds=pyversion '%python%';
SET cmds=%cmds% addpath('%our_folder%/%nwb_api_folder%/matlab_bridge/matlab_bridge_api');
SET cmds=%cmds% addpath(genpath('%our_folder%/MATLAB/source'));
SET cmds=%cmds% success = savepath();
SET cmds=%cmds% if success == 1; error('Failed to save Matlab path - set manually'); end;
matlab -nosplash -nodesktop -r "%cmds% quit"

echo "To activate the conda environment, in order to convert Labview to NWB, run:"
echo "  On Linux, Mac OS, Windows with Git Bash:"
echo "source activate %conda_env_name%"
echo "  On Windows with PowerShell or Cmd:"
echo "activate.bat %conda_env_name%"
