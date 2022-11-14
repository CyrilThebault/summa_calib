#!/bin/bash
# Make a job list to run summa in parallel across requested cores.
# An example: ./5_make_summa_run_list.sh '../control_active.txt' 5

# -----------------------------------------------------------------------------------------
# ----------------------------- User specified input --------------------------------------
# -----------------------------------------------------------------------------------------
control_file=$1  # path of the active control file
nSubset=$2       # number of GRU subsets to split summa run

# -----------------------------------------------------------------------------------------
# ------------------------------------ Functions ------------------------------------------
# -----------------------------------------------------------------------------------------
# Function to extract a given setting from the controlFile.
read_from_control () {
    control_file=$1
    setting=$2
    
    line=$(grep -m 1 "^${setting}" $control_file)
    info=$(echo ${line##*|}) # remove the part that ends at "|"
    info=$(echo ${info%%#*}) # remove the part starting at '#'; does nothing if no '#' is present
    echo $info
}

# Function to extract a given setting from the summa or mizuRoute configuration file.
read_from_summa_route_config () {
    input_file=$1
    setting=$2
    
    line=$(grep -m 1 "^${setting}" $input_file) 
    info=$(echo ${line%%!*}) # remove the part starting at '!'
    info="$( cut -d ' ' -f 2- <<< "$info" )" # get string after the first space
    info="${info%\'}" # remove the suffix '. Do nothing if no '.
    info="${info#\'}" # remove the prefix '. Do nothing if no '.
    echo $info
}

# -----------------------------------------------------------------------------------------
# -------------------------- Read settings from control_file ------------------------------
# -----------------------------------------------------------------------------------------

# Read calibration path from controlFile.
calib_path="$(read_from_control $control_file "calib_path")"

# Read hydrologic model path from controlFile.
model_path="$(read_from_control $control_file "model_path")"
if [ "$model_path" = "default" ]; then model_path="${calib_path}/model"; fi

# Read summa setting and summa_filemanager paths.
summa_settings_relpath="$(read_from_control $control_file "summa_settings_relpath")"
summa_settings_path=$model_path/$summa_settings_relpath
summa_filemanager="$(read_from_control $control_file "summa_filemanager")"
summa_filemanager=$summa_settings_path/$summa_filemanager

# Read summa and mizuRoute executable paths.
summaExe="$(read_from_control $control_file "summa_exe_path")"
routeExe="$(read_from_control $control_file "route_exe_path")"

# Read the total numebr of GRUs (used to calculate countGRU).
summa_attributeFile="$(read_from_summa_route_config $summa_filemanager "attributeFile")"
summa_attributeFile=$summa_settings_path/$summa_attributeFile
nGRU=$( ncks -Cm -v gruId -m $summa_attributeFile | grep 'gru = '| cut -d' ' -f 7 )

# -----------------------------------------------------------------------------------------
# -------------------------------------- Execute ------------------------------------------
# -----------------------------------------------------------------------------------------
# Copy summaExe to local to save summa_run_list.txt size
cp $summaExe summa.exe
chmod 744 summa.exe

# Create summa_run_list.txt
jobList=./summa_run_list.txt  
rm -f $jobList # Remove existing file

# Calculate a trial countGRU value. May need an adjustment based on startGRU and endGRU
countGRU_try=$(( ( $nGRU / $nSubset ) + ( $nGRU % $nSubset > 0 ) )) 

# Loop to write each GRU subset per line
iSubset=0
while [ $iSubset -lt $nSubset ]; do

    # Set gru bounds per subset; 
    startGRU=$(( iSubset*countGRU_try + 1 ))
    endGRU=$(( startGRU+countGRU_try-1))
    
    # Adjust countGRU to cap at max of nGRU
    if [ $endGRU -gt $nGRU ]; then 
        countGRU=$(( nGRU-startGRU+1 ))
    else 
        countGRU=$countGRU_try
    fi     
    
    # Write a subset per line to jobList
    echo $iSubset ./summa.exe -g $startGRU $countGRU -r never -m $summa_filemanager >> $jobList
      
    iSubset=$(( iSubset + 1 ))
done

