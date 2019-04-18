#!/bin/bash -ef 

# This script facilitates the resampling of data (scalar and labels/parcellations) between
# FreeSurfer (native or fsaverage) and fs_LR HCP space

# assumes the following
# HCP pipelines are installed somewhere 
# HCPPIPEDIR environmental variable is set to point to HCP pipelines
# "wb_shortcuts-master" has been placed in HCPPIPEDIR
# FreeSurfer is installed and sourced correctly

# Preliminary release
# TODO: add fs_LR to FreeSurfer resampling

v="spherical_surface_swapper.sh: version 0.4; Author(s): stobyne; Date: 04.17.19";

usage() { 
  echo "Usage: $(basename $0)

	REQUIRED
	-i <input>		: specify surface input overlay or label to resample
	-o <output>		: specify surface output filename stem to create (no suffix/filetype)
	-f <filetype>		: specify I/O type (valid values: scalar, annotation)

	-h <hemi>		: speficy hemisphere (valid values: L, R)

	-s <start_space>	: specify starting space (valid values: fsaverage[4,5,6], native, fs_LR, fs_LR_native)
	-t <targ_space>		: specify target space (valid values same as -s)

	IF -s OR -t IS SET TO NATIVE, MUST SPECIFY
	-d <directory>		: specify FreeSurfer SUBJECTS_DIR (will also take environmental variable)
	-r <recon ID>		: specify FreeSurfer recon subject ID

	OPTIONAL
	-a <atlas_dir>		: directory containing spheres used in resampling (def: HCPPIPEDIR/global/templates/standard_mesh_atlases/)
	-m <targ_mesh_size>	: fs_LR mesh size (target only, valid values: 32 [def], 59, 164)
	-n 			: no cleanup; turn off cleanup

	-h		: HELP!

	EXAMPLE
	To map an imaginary LH native space sig.mgz for cc53 to fs_LR 32k mesh:
	spherical_surface_swapper.sh -i sig.mgz -o sig -f scalar -h L -s native -t fs_LR -r cc53" >&2
 }

#===============
#parse arguments
#===============

# if no arguments, print usage
if [[ "$#" -lt 1 ]]; then
	usage;
	exit 1
fi

# parse short options
OPTIND=1
while getopts "ni:o:f:h:s:t:d:r:a:m:" opt; do
    case "$opt" in
       i) infile="$OPTARG" ;;
       o) outfile="$OPTARG" ;;
       f) type="$OPTARG" ;;
	   h) hemi="$OPTARG" ;;
       s) inspace="$OPTARG" ;;
       t) outspace="$OPTARG" ;;
       d) SUBJECTS_DIR="$OPTARG" ;;
	   r) reconid="$OPTARG" ;;
       a) ATLASDIR="$OPTARG" ;;
       m) meshsize="$OPTARG" ;;
	   n) cleanup=0;;
       \?) echo "Invalid option: ${OPTARG}"
           usage 
           exit 1
           ;;
	   :) echo "Option -$OPTARG requires an argument."
		  usage
	      exit 1
   esac
done

#================
# check arguments and assign defaults
#================

# check required variables
if [[ -z ${infile+x} ]] || [[ -z ${outfile+x} ]] || [[ -z ${type+x} ]] || [[ -z ${inspace+x} ]] || [[ -z ${outspace+x} ]] || [[ -z ${hemi+x} ]]; then
	echo "ERROR: Must specify all of -i (input ), -o (output), -f (file type), -s (starting space) and -t (target space)."
    usage;
	exit 1
fi

# check allowable input types
if [[ $type != "scalar" ]] && [[ $type != "annotation" ]]; then
	echo "ERROR: Filetype must be set to either scalar or annotation."
	usage;
	exit 1
fi

# check hemisphere correctly set
if [[ $hemi != "L" ]] && [[ $hemi != R ]]; then
	echo "ERROR: Hemisphere must be set to either L or R."
	usage;
	exit 1
fi

# check allowable input/output types
if [[ $inspace != "fsaverage" ]] && [[ $inspace != "fsaverage6" ]] && [[ $inspace != "fsaverage5" ]] && [[ $inspace != "fsaverage4" ]] && [[ $inspace != "native" ]] && [[ $inspace != "fs_LR" ]] && [[ $inspace != "fs_LR_native" ]]; then
	echo "ERROR: Starting space must bet set to either fsaverage, fsaverage6, fsaverage5, fsaverage4, native, fs_LR or fs_LR_native."
	usage;
	exit 1
fi

if [[ $outspace != "fsaverage" ]] && [[ $outspace != "fsaverage6" ]] && [[ $outspace != "fsaverage5" ]] && [[ $outspace != "fsaverage4" ]] && [[ $outspace != "native" ]] && [[ $outspace != "fs_LR" ]] && [[ $outspace != "fs_LR_native" ]]; then
	echo "ERROR: Starting space must bet set to either fsaverage, fsaverage6, fsaverage5, fsaverage4, native, fs_LR or fs_LR_native."
	usage;
	exit 1
fi

# if input is an fsaverage mesh, set fsaverage mesh size
case $inspace in
	fsaverage) fsavmesh=164 ;;
	fsaverage6) fsavmesh=41 ;;
	fsaverage5) fsavmesh=10 ;;
	fsaverage4)	fsavmesh=3 ;;
esac

# mesh size
[[ -z ${meshsize+x} ]] && meshsize=32;	# vertex density for fs_LR mesh

if [[ $meshsize -ne "32" ]] && [[ $meshsize -ne "59" ]] && [[ $meshsize -ne "164" ]]; then
	echo "ERROR: fs_LR mesh size must be set to either 32, 59 or 164."
	usage;
	exit 1
fi

# input/output native space
if [[ $inspace == "native" ]] && [[ $outspace == "native" ]]; then
	if [[ -z ${SUBJECTS_DIR+x} ]]; then
		echo "ERROR: If starting space or output space are set to native, SUBJECTS_DIR must exist or be must be set with -d."
		usage;
		exit 1
	fi
fi

# ATLASDIR directory
[[ -z ${ATLASDIR+x} ]] && ATLASDIR=${HCPPIPEDIR}/global/templates/standard_mesh_atlases/; 	# directory containing spheres

if [[ ! -d $ATLASDIR ]]; then
	echo "ERROR: Could not find ATLASDIR: ${ATLASDIR}."
	exit 1
fi

# check FreeSurfer directories
if [[ ! -d $SUBJECTS_DIR ]]; then
	echo "ERROR: Could not find SUBJECTS_DIR: ${SUBJECTS_DIR}."
	exit 1
fi

if [[ ! -d $SUBJECTS_DIR/$reconid ]]; then
	echo "ERROR: Could not find $reconid in ${SUBJECTS_DIR}."
	exit 1
fi

[[ -z ${cleanup+x} ]] && cleanup=1;	# cleanup on by default

############################
# begin resampling use cases
############################

tempdir="temp.`date +%N`"
mkdir $tempdir

			echo ""
echo "Input: $infile"
echo "Input space: $inspace $type"
echo "Output: $outfile"
echo "Output space: $outspace $type"

case "$inspace" in 
	fsaverage*)	
		### fsaverage[4,5,6] to fs_LR group

		if [[ $type == "scalar" ]]; then
			# for scalar overlay
			echo ""
			echo "Converting input $inspace scalar overlay to GIFTI format..."
			echo ""
			mri_convert $infile $tempdir/temp.gii

			echo ""
			echo "Resampling to specified fs_LR surface..."
			echo ""
			wb_command -metric-resample $tempdir/temp.gii \
				$ATLASDIR/resample_fsaverage/fsaverage_std_sphere.$hemi.${fsavmesh}k_fsavg_${hemi}.surf.gii \
				$ATLASDIR/resample_fsaverage/fs_LR-deformed_to-fsaverage.$hemi.sphere.${meshsize}k_fs_LR.surf.gii \
				ADAP_BARY_AREA \
				$outfile.func.gii \
				-area-metrics $ATLASDIR/resample_fsaverage/fsaverage.$hemi.midthickness_va_avg.${fsavmesh}k_fsavg_${hemi}.shape.gii $ATLASDIR/resample_fsaverage/fs_LR.$hemi.midthickness_va_avg.${meshsize}k_fs_LR.shape.gii

		elif [[ $type == "annotation" ]]; then
			# for annotation
			echo ""
			echo "Converting input $inspace annotation to GIFTI format..."
			echo ""
			mris_convert --annot $infile $SUBJECTS_DIR/fsaverage/surf/lh.white $tempdir/temp.gii

			echo ""
			echo "Resampling to specified fs_LR surface..."
			echo ""
			wb_command -label-resample $tempdir/temp.gii \
	 			$ATLASDIR/resample_fsaverage/fsaverage_std_sphere.$hemi.${fsavmesh}k_fsavg_${hemi}.surf.gii \
	 			$ATLASDIR/resample_fsaverage/fs_LR-deformed_to-fsaverage.$hemi.sphere.${meshsize}k_fs_LR.surf.gii \
				ADAP_BARY_AREA \
				$outfile.label.gii \
				-area-metrics $ATLASDIR/resample_fsaverage/fsaverage.$hemi.midthickness_va_avg.${fsavmesh}k_fsavg_${hemi}.shape.gii $ATLASDIR/resample_fsaverage/fs_LR.$hemi.midthickness_va_avg.${meshsize}k_fs_LR.shape.gii
		fi
		;;

	native)
		### native to fs_LR group

		# set FreeSurfer style hemi reference
		if [[ $hemi == "L" ]]; then
			lchemi="lh";
		else
			lchemi="rh";
		fi

		if [[ $type == "scalar" ]]; then
			# for scalar overlay	
			echo ""
			echo "Converting input $inspace scalar overlay to GIFTI format..."
			echo ""
			mri_convert $infile $tempdir/temp.gii

			echo ""
			echo "Calculating native-to-fs_LR spherical registration..."
			echo ""
			$HCPPIPEDIR/wb_shortcuts-master/wb_shortcuts -freesurfer-resample-prep $SUBJECTS_DIR/$reconid/surf/$lchemi.white \
				$SUBJECTS_DIR/$reconid/surf/$lchemi.pial \
				$SUBJECTS_DIR/$reconid/surf/$lchemi.sphere.reg \
				$ATLASDIR/resample_fsaverage/fs_LR-deformed_to-fsaverage.$hemi.sphere.${meshsize}k_fs_LR.surf.gii \
				$tempdir/$lchemi.midthickness.surf.gii \
				$tempdir/$lchemi.midthickness.$hemi.${meshsize}k_fs_LR.surf.gii \
				$tempdir/$lchemi.sphere.reg.surf.gii
		
			echo ""
			echo "Resampling to specified fs_LR surface..."
			echo ""
			wb_command -metric-resample $tempdir/temp.gii \
			$tempdir/$lchemi.sphere.reg.surf.gii \
			$ATLASDIR/resample_fsaverage/fs_LR-deformed_to-fsaverage.$hemi.sphere.${meshsize}k_fs_LR.surf.gii \
			ADAP_BARY_AREA $outfile.func.nii -area-surfs \
			$tempdir/$lchemi.midthickness.surf.gii \
			$tempdir/$lchemi.midthickness.$hemi.${meshsize}k_fs_LR.surf.gii

		elif [[ $type == "annotation" ]]; then
			# for annotation
			echo ""
			echo "Converting input $inspace annotation to GIFTI format..."
			echo ""
			mris_convert --annot $infile $SUBJECTS_DIR/$reconid/surf/$lchemi.white $tempdir/temp.gii

			echo ""
			echo "Calculating native-to-fs_LR spherical registration..."
			echo ""
			$HCPPIPEDIR/wb_shortcuts-master/wb_shortcuts -freesurfer-resample-prep $SUBJECTS_DIR/$reconid/surf/$lchemi.white \
				$SUBJECTS_DIR/$reconid/surf/$lchemi.pial \
				$SUBJECTS_DIR/$reconid/surf/$lchemi.sphere.reg \
				$ATLASDIR/resample_fsaverage/fs_LR-deformed_to-fsaverage.$hemi.sphere.${meshsize}k_fs_LR.surf.gii \
				$tempdir/$lchemi.midthickness.surf.gii \
				$tempdir/$lchemi.midthickness.$hemi.${meshsize}k_fs_LR.surf.gii \
				$tempdir/$lchemi.sphere.reg.surf.gii

			echo ""
			echo "Resampling to specified fs_LR surface..."
			echo ""
			wb_command -label-resample $tempdir/temp.gii \
				$tempdir/$lchemi.sphere.reg.surf.gii \
				$ATLASDIR/resample_fsaverage/fs_LR-deformed_to-fsaverage.$hemi.sphere.${meshsize}k_fs_LR.surf.gii \
				ADAP_BARY_AREA \
				$outfile.label.gii \
				-area-surfs $tempdir/$lchemi.midthickness.surf.gii $tempdir/$lchemi.midthickness.L.32k_fs_LR.surf.gii
		fi
		;;
	
	fs_LR)
		### fs_LR group to fsaverage
		echo ""
		echo "fs_LR group average to fsaverage resampling not yet implemented. Sorry!"
		;;


	fs_LR_native)
		### fs_LR_native to fsaverage
		echo ""
		echo "fs_LR native to fsaverage resampling not yet implemented. Sorry!"
esac

if [[ $cleanup -eq 1 ]]; then
	echo ""
	echo "Cleaning up..."
	rm -r $tempdir
else
	echo ""
	echo "Skipping cleanup..."
fi

echo ""
echo "Spherical surface swapping wizardry complete!"

#exit 0;
