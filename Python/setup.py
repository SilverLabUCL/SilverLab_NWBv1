from setuptools import setup, find_packages

import sys


# Check which Python version this is, and set extra deps accordingly
if sys.version_info[0] == 2:
    extra_deps = ['enum34']
else:
    extra_deps = []

setup(name='SilverLabNwb',
      version='0.1',
      description='Neuroscience data management and analysis in the Silver Lab',
      url='https://github.com/SilverLabUCL/SilverLab_NWBv1',
      author='Jonathan Cooper',
      author_email='j.p.cooper@ucl.ac.uk',
      classifiers=['Development Status :: 3 - Alpha',
                   'Programming Language :: Python',
                   'Programming Language :: Python :: 2',
                   'Programming Language :: Python :: 3',
                   'Operating System :: OS Independent',
                   'Intended Audience :: Science/Research',
                   'License :: Other/Proprietary License'],
      install_requires=['nwb', 'h5py', 'numpy', 'pandas>=0.20', 'tifffile',
                        'nptdms', 'av', 'appdirs', 'pyyaml', 'six'] + extra_deps,
      packages=find_packages(exclude=['*test']),
      package_data={
          # If any (sub-)package contains *.yaml files, include them:
          '': ['*.yaml']
      },
      entry_points={
          'console_scripts': [
              'labview2nwb = silverlabnwb.script:import_labview',
              'nwb_check_signature = silverlabnwb.script:check_signature',
              'subsample_nwb = silverlabnwb.subsample_nwb:run'
          ],
          'gui_scripts': [
              'nwb_metadata_editor = silverlabnwb.metadata_gui:run_editor'
          ]
      },
      zip_safe=False
      )
