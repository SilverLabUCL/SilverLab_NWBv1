#!/usr/bin/env bash

mydir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Pointing mode

# Hana, 80 ROIs, 20 trials, 8772 cycles, some TDMS missing, video
labview2nwb --no-gui "$SILVERLAB_DATA_DIR/161215_15_34_21.nwb" "$SILVERLAB_DATA_DIR/161215_15_34_21 FunctAcq" 
nwb_check_signature "$SILVERLAB_DATA_DIR/161215_15_34_21.nwb" "$mydir/data/161215_15_34_21.sig"

# Hana, 80 ROIs, 20 trials, 8772 cycles
# Reading TDMS: 5m47.735s; 10:35:48 - 10:41:25 = 5m37
# Reading .dat: 1m45.357s; 10:50:35 - 10:52:10 = 1m35
labview2nwb --no-gui "$SILVERLAB_DATA_DIR/161215_15_58_52.nwb" "$SILVERLAB_DATA_DIR/161215_15_58_52 FunctAcq" 
nwb_check_signature "$SILVERLAB_DATA_DIR/161215_15_58_52.nwb" "$mydir/data/161215_15_58_52.sig"

# Fred, 120 ROIs, 18 trials, 2929 cycles
# Reading TDMS: 2m49.831s; 09:15:14 - 09:17:47 = 2m33
# Reading .dat: 1m20.015s; 09:12:13 - 09:13:17 = 1m05
labview2nwb --no-gui "$SILVERLAB_DATA_DIR/170317_10_11_01.nwb" "$SILVERLAB_DATA_DIR/170317_10_11_01 FunctAcq"
nwb_check_signature "$SILVERLAB_DATA_DIR/170317_10_11_01.nwb" "$mydir/data/170317_10_11_01.sig"

# Miniscans

# Fred, 4 ROIs, 96 miniscans, 6 trials, 2611 cycles
# Note: this first example seems to have some corrupt data in the TDMS (trial 4) - not enough data points
# It wasn't mentioned in Fred's email, so may not be a good sample to use.
labview2nwb --no-gui "$SILVERLAB_DATA_DIR/170209_11_26_03.nwb" "$SILVERLAB_DATA_DIR/170209_11_26_03 FunctAcq"
nwb_check_signature "$SILVERLAB_DATA_DIR/170209_11_26_03.nwb" "$mydir/data/170209_11_26_03.sig"

# Fred, 7 ROIs, 420 miniscans, 18 trials, 367 cycles
labview2nwb --no-gui "$SILVERLAB_DATA_DIR/170322_14_06_43.nwb" "$SILVERLAB_DATA_DIR/170322_14_06_43 FunctAcq"
nwb_check_signature "$SILVERLAB_DATA_DIR/170322_14_06_43.nwb" "$mydir/data/170322_14_06_43.sig"

exit 0

# To regenerate sigs use the commands below

python -m nwb.h5diffsig "$SILVERLAB_DATA_DIR/161215_15_34_21.nwb" -Na > "$mydir/data/161215_15_34_21.sig"
python -m nwb.h5diffsig "$SILVERLAB_DATA_DIR/161215_15_58_52.nwb" -Na > "$mydir/data/161215_15_58_52.sig"
python -m nwb.h5diffsig "$SILVERLAB_DATA_DIR/170317_10_11_01.nwb" -Na > "$mydir/data/170317_10_11_01.sig"
# python -m nwb.h5diffsig "$SILVERLAB_DATA_DIR/170209_11_26_03.nwb" -Na > "$mydir/data/170209_11_26_03.sig"
python -m nwb.h5diffsig "$SILVERLAB_DATA_DIR/170322_14_06_43.nwb" -Na > "$mydir/data/170322_14_06_43.sig"
