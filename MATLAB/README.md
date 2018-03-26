# Matlab API for NWB use in the Silver Lab

Quick usage example:

``` matlab
nwb = NwbFile('Data/161215_15_34_21.nwb');
gui = DisplayVideos(nwb);
```

For examples of using the API from Matlab analysis scripts, see
https://github.com/SilverLabUCL/Data-Analysis-Hana/blob/hdf5-experiment/RunUsingNwb.m


## Automated Matlab testing

Tests are stored in the [tests](./tests) folder.
New tests are written as classes named like `TestSomething` within this folder.
It's probably easiest to start by copying the structure of an existing test.

Tests may be run locally,
and are also run automatically when pushing to the `master` branch or creating/updating pull requests.

### Local test running

Within Matlab, change to the `MATLAB/tests` folder (or add it to your path) then run
```
TestRunner()
```

### Automated tests

Results are displayed at http://jenkins.rc.ucl.ac.uk/ - ask Jonathan Cooper to give your GitHub account permissions to see this.
Tests of the master branch are at http://jenkins.rc.ucl.ac.uk/job/SilverLab-main/ and for pull requests under http://jenkins.rc.ucl.ac.uk/job/SilverLab-pull-request/.

You can also see results of specific builds linked from the pull requests / [commits](https://github.com/SilverLabUCL/SilverLab_NWBv1/commits/master) themselves.
Click on 'Console output' to see the actual test output (scrolling past a lot of test environment setup output!).
