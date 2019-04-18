# Spherical Surface Swapper
Wrapper code to streamline moving data between surface formats

**REQUIRED**  
   -i <input>		: specify surface input overlay or label to resample  
   -o <output>		: specify surface output filename stem to create (no suffix/filetype)  
   -f <filetype>		: specify I/O type (valid values: scalar, annotation)  
  
   -h <hemi>		: speficy hemisphere (valid values: L, R)  
  
   -s <start_space>	: specify starting space (valid values: fsaverage[4,5,6], native, fs_LR, fs_LR_native)  
   -t <targ_space>		: specify target space (valid values same as -s)    
  
   IF -s OR -t IS SET TO NATIVE, MUST SPECIFY  
   -d <directory>		: specify FreeSurfer SUBJECTS_DIR (will also take environmental variable)  
   -r <recon ID>		: specify FreeSurfer recon subject ID  

**OPTIONAL**  
  -a <atlas_dir>		: directory containing spheres used in resampling (def: HCPPIPEDIR/global/templates/standard_mesh_atlases/)  
  -m <targ_mesh_size>	: fs_LR mesh size (target only, valid values: 32 [def], 59, 164)  
  -n 			: no cleanup; turn off cleanup  
  -h		: HELP!  

**EXAMPLE**  
To map an imaginary LH native space sig.mgz for cc53 to fs_LR 32k mesh:  
spherical_surface_swapper.sh -i sig.mgz -o sig -f scalar -h L -s native -t fs_LR -r cc53
