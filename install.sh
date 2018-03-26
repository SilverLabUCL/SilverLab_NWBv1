#!/usr/bin/env bash

# Installer script for the SilverLab AnalysisPipeline software + dependencies

# Are we running on Windows?
case "$(uname -s)" in
    MINGW*|CYGWIN*|Windows*) WINDOWS=1 ;;
    *) WINDOWS=0 ;;
esac


# Settings
conda_env_name=nwb
if [ $WINDOWS == 1 ]; then
    python_version=2.7
else
    # Python 3.5 is still crashing Matlab on Windows
    python_version=3.5
fi
nwb_api_folder=nwb_api_python
nwb_api_uri="https://github.com/SilverLabUCL/api-python"
our_folder="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Define helper functions
function error () {
    echo "Error: $1"
    exit 1
}

# Try to find required tools
echo 'Checking for presence of required tools...'
which git || error 'No git found'
conda=`which conda`
if [ ! $conda ]; then
    for name in anaconda2 anaconda3 miniconda2 miniconda3; do
        conda=$HOME/$name/bin/conda
        [ -x $conda ] && break
        # Try Windows style instead
        conda=$HOME/$name/Scripts/conda.exe
        [ -x $conda ] && break
    done
fi
[ -x $conda ] || error 'Unable to find conda'

conda_envs_dir="`$conda info | grep 'envs directories' |  awk -F' : ' '{print $2}'`"
conda_root="`$conda info --root`"
conda_bin_dir=`dirname $conda`

echo "Found conda install at $conda_root"

# Set up our conda environment
function setup_env () {
    echo 'Setting up conda environment...'
    [ -d "$conda_envs_dir/$conda_env_name" ] || $conda create --yes -n $conda_env_name python=$python_version
    source $conda_bin_dir/activate $conda_env_name
    $conda install --yes -n $conda_env_name numpy=1.13.0
    if [ $WINDOWS == 1 ]; then
        # Use h5py compiled to match Matlab's HDF5 version
        $conda install --yes -n $conda_env_name hdf5=1.8.12 h5py=2.7.0 -c jonc
    else
        $conda install --yes -n $conda_env_name h5py=2.7.0
    fi
    $conda install --yes -n $conda_env_name av=0.3.3 tifffile=0.12.1 -c conda-forge
}

# Install the NWB API
# Note that we can't just pip install direct from GitHub as we also need the Matlab bridge
function install_nwb () {
    echo 'Installing NeurodataWithoutBorders API...'
    cd "$our_folder"
    if [ -d "$nwb_api_folder" ]; then
        git -C "$nwb_api_folder" pull --ff-only
    else
        git clone "$nwb_api_uri" "$nwb_api_folder"
    fi
    cd "$nwb_api_folder"
    pip install -e .
}

# Install the analysis pipeline
function install_pipeline () {
    echo 'Installing Silver Lab analysis pipeline...'
    cd "$our_folder/Python"
    pip install -r "requirements/main.in"
    pip install -e .
}

# Set up Matlab to use the pipeline & NWB
function setup_matlab () {
    echo 'Setting up Matlab...'
    python "$our_folder/MATLAB/setup.py" "$our_folder/$nwb_api_folder"
}

# Run everything
setup_env
install_nwb
install_pipeline
# source $conda_bin_dir/activate $conda_env_name
setup_matlab

echo "To activate the conda environment, in order to convert Labview to NWB, run:"
echo "  On Linux, Mac OS, Windows with Git Bash:"
echo "source $conda_bin_dir/activate $conda_env_name"
echo "  On Windows with PowerShell:"
echo "$conda_bin_dir/activate.bat $conda_env_name"
