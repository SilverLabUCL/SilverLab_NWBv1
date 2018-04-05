# Silver Lab analysis pipeline

Data -> NWB 1.0.x -> Analysis

This is not yet 'production software', but there are working tools for converting Labview data to NWB and viewing/processing this in Matlab.

## Quick installation

An installation script is provided, but it requires some software to be installed on your machine first:
1. The [git](https://git-scm.com/) version control system
2. The [Anaconda](https://conda.io/docs/) Python distribution

In both cases the command-line tools are needed.
Software Carpentry provide some [installation instructions](https://swcarpentry.github.io/workshop-template/#setup) for Windows, Mac OS and Linux.
Follow the sections for "The Bash Shell", "Git" and "Python".

You can then open a bash shell, download this software to your machine, and run our installer script.
For instance:
``` sh
cd $HOME
git clone https://github.com/SilverLabUCL/SilverLab_NWBv1
cd SilverLab_NWBv1
./install.sh
```

The tools should now be ready to use from both Python and Matlab.
For more details on each component, see:
- [our Python library for working with NWB files](Python/README.md)
- [Matlab wrappers for this with a graphical interface](MATLAB/README.md)

### Installation notes & variations

1. You can install the software in any folder; `$HOME` was just used above as an example that exists on all systems.
2. Rather than installing the full Anaconda suite, you can install the cut-down 'Miniconda' version;
   see the [Miniconda quick install instructions](https://conda.io/docs/install/quick.html) for details.
   It doesn't matter whether you choose Python 2 or Python 3, but we do recommend using the 64-bit version.
3. When the Anaconda/Miniconda installer asks if you want to have conda added to your path,
   or be made the default Python version, say yes so that the conda tools can be found by our installation script.
   (The script will try to guess if you don't, but this isn't as reliable.)
4. It's worth while learning how to use git to version control your own analysis scripts.
   Look out for the next [Software Carpentry workshop](http://www.ucl.ac.uk/isd/services/research-it/training)
   being run by Research IT Services.
5. You may also want to install a graphical interface to git such as [Git Kraken](https://www.gitkraken.com/).


## Links

Neurodata Without Borders: http://nwb.org/

Python & MATLAB APIs: https://github.com/NeurodataWithoutBorders/api-python

HDFView: https://support.hdfgroup.org/products/java/hdfview, to view hdf5 files:

![HDFview](/HDFView.png)



# Other tools for data analysis

## Whisker Tracking – Janelia

https://openwiki.janelia.org/wiki/display/MyersLab/Whisker+Tracking+Downloads

Clack NG, O'Connor DH, Huber D, Petreanu L, Hires A., Peron, S., Svoboda, K., and Myers, E.W. (2012) 
Automated Tracking of Whiskers in Videos of Head Fixed Rodents.
PLoS Comput Biol 8(7):e1002591. doi:10.1371/journal.pcbi.1002591

## Locomotion Videography – Hausser Lab

Synaptic representation of locomotion in single cerebellar granule cells
https://elifesciences.org/content/4/e07290/supp-material1
https://elifesciences.org/content/4/e07290/article-data


## July 2016 Nature Communications Paper

Accurate spike estimation from noisy calcium signals for ultrafast three-dimensional imaging of large neuronal populations in vivo
http://www.nature.com/articles/ncomms12190


## Losonczy Lab

http://www.losonczylab.org/software

We strive to share our software with the scientific community. The most recent versions of our software are made available on this page.

#### SIMA (Documentation, Downloads, Example Dataset, GitHub)
The SIMA package is an open source Python package for analysis of fluorescence imaging data. We use this software for motion correction, segmentation, and extraction of fluorescence signals from 2-photon calcium imaging experiments.

#### ROI Buddy (Documentation, Downloads)
ROI Buddy is a graphical user interface for editing ROIs. It is designed to be used in conjunction with the SIMA package. See the documentation for installation details.

**References:**
Kaifosh P, Zaremba J, Danielson N, and Losonczy A. SIMA: Python software for analysis of dynamic fluorescence imaging data. Frontiers in Neuroinformatics. 2014 Aug 27; 8:77. doi: 10.3389/fninf.2014.00077.
Kaifosh P, Lovett-Barron M, Turi GF, Reardon TR, Losonczy A. Septo-hippocampal GABAergic signaling across multiple modalities in awake mice. Nat Neurosci. 2013 Sep;16(9):1182-4. doi: 10.1038/nn.3482.


## VAA3D
https://www.janelia.org/open-science/vaa3d

## Schultz Lab
http://www.schultzlab.org/software/index.html

## Svoboda Lab
Janelia Automatic Animal Behavior Annotator (JAABA®)
https://www.janelia.org/open-science/jaaba%C2%AE

## Yuste Lab
Lots of software and cluster analysis
http://www.columbia.edu/cu/biology/faculty/yuste/methods.html

## Hausser Lab
http://michael-hausser.squarespace.com/software/

http://www.treestoolbox.org/

