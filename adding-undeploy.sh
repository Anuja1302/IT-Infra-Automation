#!/bin/bash

# Path to the lock file
lock_file="/tmp/$(basename "$0").lock"

# Check if the lock file exists
if [ -e "$lock_file" ]; then
    echo "Another instance of this script is already running. Exiting."
    log_message "ERROR" "Script is already running by another user or instance."
    exit 1
fi

# Create necessary directories for logs
log_dir="/tps/logs/prd/ppap001/pci_swing"
mkdir -p "$log_dir"
log_file="$log_dir/$(date +"%Y-%m-%d_%H-%M-%S")_PCI_swing.log"



# Function to log messages
log_message() {
  local log_time
  log_time=$(date +"%d-%m-%Y %H:%M:%S")
  local log_type=$1
  local log_message=$2
  echo "$log_time -- $log_type - $log_message" | tee -a "$log_file"
}

# Create a lock file with the current process ID
echo $$ > "$lock_file"
log_message "INFO" "Lock file created at $lock_file with PID $$"

# Function to clean up lock file on exit
cleanup() {
    rm -f "$lock_file"
}
# Ensure lock file is removed on script exit (normal or due to interruption)
trap cleanup EXIT

# Source the environment variables
source /tps/envvars




# Define input and output files
input_file="output.txt"
filtered_output_file="filtered_output.txt"
filtered_output_file1="filtered_output1.txt"
grllbpcip1_file="grllbpcip1_partitions.txt"
nhqlbpcip1_file="nhqlbpcip1_partitions.txt"
final_grllbpcip1_file="final_grllbpcip1_partitions.txt"
final_nhqlbpcip1_file="final_nhqlbpcip1_partitions.txt"
semi_final1_file="Semi_final1.txt"
final_output_file="final_output.txt"
extracted_dir="extracted_files"


# Create necessary directories and files
mkdir -p "$extracted_dir"
> "$final_output_file"

# Log that directories and files have been created
log_message "INFO" "Created directories and files."


# Define SSH parameters
username="jbosegs"
main_partition="prdab63"

# Function to SSH into servers from a specified file and run the hostname command
run_hostname_command() {
    local server_file="$1"

    # Check if the file exists
    if [[ -f "$server_file" ]]; then
        log_message "INFO" "Processing servers from $server_file"
        
        # Read the file into an array
        mapfile -t servers < "$server_file"
        
        # Loop through each server in the array
        for server in "${servers[@]}"; do
            # Skip empty lines
            [[ -z "$server" ]] && continue
            
            log_message "INFO" "Connecting to $server and running hostname command"
            
            # Run SSH command to get the hostname
            ssh -o StrictHostKeyChecking=no "$server" 'hostname' 2>/dev/null
            
            if [[ $? -eq 0 ]]; then
                log_message "SUCCESS" "Successfully retrieved hostname from $server"
            else
                log_message "ERROR" "Failed to retrieve hostname from $server"
            fi
        done
    else
        log_message "WARN" "File $server_file does not exist"
    fi
}


# Function to perform an SSH operation
ssh_execute() {
  local user=$1     # SSH username
  local server=$2   # Server hostname or IP
  local command=$3  # Command to execute

  if [[ -z "$user" || -z "$server" || -z "$command" ]]; then
    echo "Usage: ssh_execute <user> <server> <command>"
    return 1
  fi

  # Execute the command over SSH
  ssh "${user}@${server}" "$command"
}


# Function to generate the report
generate_report() {

    # Check for files starting with active- or passive-
    files=$(ls | grep -E '^(active|passive)_[^/]+\.txt$')

    if [[ -n $files ]]; then
        # If such files exist, remove them
        echo "Removing files starting with 'active-' or 'passive-'..."
        log_message "INFO" "Removing files starting with 'active-' or 'passive-'..."
        rm -f $files
        echo "Files removed."
        log_message "INFO" "Files removed."
    else
        # If no such files, continue
        echo "No 'active-' or 'passive-' files found. Good to go!"
        log_message "INFO" "No 'active-' or 'passive-' files found. Good to go!"

    fi

    log_message "INFO" "Generating the report."

    # Run the Expect script with the environment variable as an argument
    expect -f dont_touch.exp "$nsclpci" > "$input_file"
    # Read the content of $input_file
    if [[ -f "$input_file" ]]; then
        file_content=$(cat "$input_file")
    else
        file_content="Error: $input_file not found or empty."
    fi

    # Log the Expect script output
    log_message "INFO" "Ran the Expect script. Output: $file_content"

    # Check if input files exist
    if [[ ! -f "$input_file" ]]; then
        echo "Error: $input_file does not exist"
        log_message "ERROR" "$input_file does not exist"
        exit 1
    fi

    # Use sed to remove '-vip-' from the names
    sed 's/-vip-/-/g' "$input_file" > "$filtered_output_file"
    log_message "INFO" "Processed $input_file to remove '-vip-'."
    
    # Use awk to filter lines containing 'tcp', 'ssl', or 'http' and include port numbers
    awk '/tcp|ssl|http/ && /:[0-9]+/ {print}' "$filtered_output_file" > "$filtered_output_file1"
    log_message "INFO" "Filtered lines with 'tcp', 'ssl', or 'http' protocols."

    # Separate the partitions based on the initial character after 'prdab63'
    awk '/prdab63n-|prdab63npsv-/ {print}' "$filtered_output_file1" > "$nhqlbpcip1_file"
    awk '/prdab63g-|prdab63gpsv-/ {print}' "$filtered_output_file1" > "$grllbpcip1_file"
    log_message "INFO" "Separated partitions based on prefixes."

    # Extract only the partition names
    awk -F'[( ]' '{print $1}' "$nhqlbpcip1_file" | sed 's/^[0-9]*)//' > "$final_nhqlbpcip1_file"
    awk -F'[( ]' '{print $1}' "$grllbpcip1_file" | sed 's/^[0-9]*)//' > "$final_grllbpcip1_file"
    log_message "INFO" "Extracted partition names."

    # Run Expect script and check for existence of the output file
    expect -f Semi_final.exp "$nsclpci" > "$semi_final1_file" 

    # Read the content of $input_file
    if [[ -f "$semi_final1_file" ]]; then
        file_content2=$(cat "$semi_final1_file")
    else
        file_content2="Error: $semi_final1_file not found or empty."
    fi
    log_message "INFO" "Ran the second Expect script. Output: $file_content2"

    # Function to extract relevant block
    extract_info() {
        partition_name="$1"
        semi_final1_file="$2"
        output_file="$3"
        awk -v pname="$partition_name" '
            $0 ~ pname {found=1}
            found && /State:/ {
                print pname
                print
                getline; print
                getline; print
                exit
            }
        ' "$semi_final1_file" > "$output_file"
        log_message "INFO" "Extracting partition names."

        if [[ ! -s "$output_file" ]]; then
            echo "Warning: No match found for partition: $partition_name"
            log_message "WARN" "No match found for partition: $partition_name"
        else
            echo "Extracted details for partition: $partition_name"
            log_message "SUCCESS" "Extracted details for partition: $partition_name"
        fi
    }

    # Extract blocks based on partition names from both grllbpcip1 and nhqlbpcip1
    while read -r partition_name; do
        [[ -z "$partition_name" ]] && continue
        output_file="${extracted_dir}/${partition_name}.txt"
        extract_info "$partition_name" "$semi_final1_file" "$output_file"
        log_message "SUCCESS" "Extracted details of partition: $partition_name"
    done < "$final_nhqlbpcip1_file"
    log_message "SUCCESS" "Finished extracting partition details from nhqlbpcip1 file"

    while read -r partition_name; do
        [[ -z "$partition_name" ]] && continue
        output_file="${extracted_dir}/${partition_name}.txt"
        extract_info "$partition_name" "$semi_final1_file" "$output_file"
        log_message "SUCCESS" "Extracted details of partition: $partition_name"
    done < "$final_grllbpcip1_file"
    log_message "SUCCESS" "Finished extracting partition details from grllbpcip1 file"

    # Separate variables for prefix
    prefix_g="prdab63g"
    prefix_n="prdab63n"
    prefix_gpsv="prdab63gpsv"
    prefix_npsv="prdab63npsv"

    # Function to extract the state from the file
    extract_state_word1() {
        local file="$1"
        # Extract the state value from the line containing "state:"
        grep -i "state" "$file" | awk '{print $2}' | head -n 1
        log_message "INFO" "Extracted state from $file"
    }

    # Function to compare partition files based on protocol and port
    compare_partitions() {
        local prefix_g="$1"
        local prefix_n="$2"

        # Check if the extracted_dir variable is set and contains files
        if [[ -z "$extracted_dir" ]]; then
            log_message "ERROR" "extracted_dir is not set."
            return 1
        fi

        # Iterate over g-prefixed files
        for g_file in "${extracted_dir}/${prefix_g}"-*; do
            # Ensure the file matches the exact prefix (e.g., g or gpsv)
            if [[ ! "$g_file" =~ ${prefix_g}- ]]; then
                continue  # Skip if the file doesn't start with the exact prefix
            fi

            # Check if the file exists
            if [[ ! -f "$g_file" ]]; then
                log_message "WARN" "File $g_file does not exist."
                continue
            fi

            # Extract protocol and port from the g_file name (e.g., http-80 or ssl-443)
            protocol_port=$(echo "$g_file" | grep -oP '(http|ssl|tcp)-[0-9]+')
            log_message "INFO" "Extracted protocol and port from $g_file: $protocol_port"

            # Search for the corresponding n_file with the same protocol and port
            n_file="${extracted_dir}/${prefix_n}-${protocol_port}.txt"
            log_message "INFO" "Searching for corresponding n_file: $n_file"

            # Create a file for the specific protocol-port comparison
            comparison_file="${protocol_port}_comparison.txt"
            log_message "INFO" "Comparison file created: $comparison_file"

            if [[ -f "$n_file" ]]; then
                log_message "SUCCESS" "Comparing $g_file with $n_file"
                echo "Comparing $g_file with $n_file" >> "$final_output_file"
                echo "Comparing $g_file with $n_file" > "$comparison_file"

                # Extract states separately for g and n
                local state_g=$(extract_state_word1 "$g_file")
                local state_n=$(extract_state_word1 "$n_file")

                # Log state extraction
                log_message "INFO" "Extracted state for $g_file: $state_g"
                log_message "INFO" "Extracted state for $n_file: $state_n"

                # Print states
                echo "state: $g_file: $state_g" >> "$final_output_file"
                echo "state: $n_file: $state_n" >> "$final_output_file"
                echo "state: $g_file: $state_g"
                echo "state: $n_file: $state_n"
                echo "state: $g_file: $state_g" >> "$comparison_file"
                echo "state: $n_file: $state_n" >> "$comparison_file"

                # Separator
                echo "-----------------------------------------------" >> "$final_output_file"
                echo "-----------------------------------------------" >> "$comparison_file"
                echo "-----------------------------------------------"

                if [[ "$prefix_g" == "prdab63g" && "$prefix_n" == "prdab63n" ]]; then
                    # Logic for prdab63g vs prdab63n
                    if [[ "$state_g" == "ENABLED" && "$state_n" == "ENABLED" ]]; then
                        echo "Both LB sides are Active" >> "$final_output_file"
                        echo "Both LB sides are Active" >> "$comparison_file"
                        log_message "INFO" "Both LB sides are Active for $protocol_port"
                    elif [[ "$state_g" == "ENABLED" && "$state_n" == "DISABLED" ]]; then
                        echo "GRL LB side is Active" >> "$final_output_file"
                        echo "GRL LB side is Active" >> "$comparison_file"
                        log_message "INFO" "GRL LB side is Active for $protocol_port"
                    elif [[ "$state_g" == "DISABLED" && "$state_n" == "ENABLED" ]]; then
                        echo "NHQ LB side is Active" >> "$final_output_file"
                        echo "NHQ LB side is Active" >> "$comparison_file"
                        log_message "INFO" "NHQ LB side is Active for $protocol_port"
                    else
                        echo "Both sides are Passive" >> "$final_output_file"
                        echo "Both sides are passive" >> "$comparison_file"
                        log_message "INFO" "Both LB sides are Passive for $protocol_port"
                    fi
                elif [[ "$prefix_g" == "prdab63gpsv" && "$prefix_n" == "prdab63npsv" ]]; then
                    # Logic for prdab63gpsv vs prdab63npsv
                    if [[ "$state_g" == "ENABLED" && "$state_n" == "ENABLED" ]]; then
                        echo "Both LB Passive sides are Active" >> "$final_output_file"
                        echo "Both LB Passive sides are Active" >> "$comparison_file"
                        log_message "INFO" "Both LB Passive sides are Active for $protocol_port"
                    elif [[ "$state_g" == "ENABLED" && "$state_n" == "DISABLED" ]]; then
                        echo "NHQ passive side is Active" >> "$final_output_file"
                        echo "NHQ passive side is Active" >> "$comparison_file"
                        log_message "INFO" "NHQ Passive side is Active for $protocol_port"
                    elif [[ "$state_g" == "DISABLED" && "$state_n" == "ENABLED" ]]; then
                        echo "GRL LB Passive side is Active" >> "$final_output_file"
                        echo "GRL LB Passive side is Active" >> "$comparison_file"
                        log_message "INFO" "GRL LB Passive side is Active for $protocol_port"
                    else
                        echo "Both sides are Passive" >> "$final_output_file"
                        echo "Both sides are passive" >> "$comparison_file"
                        log_message "INFO" "Both Passive sides are Passive for $protocol_port"
                    fi
                fi

                # Final separator for this comparison
                echo "==================================================================================================================" >> "$final_output_file"
                echo "==================================================================================================================" >> "$comparison_file"
                log_message "INFO" "Finished comparison for $protocol_port"
            else
                # Log warning if no corresponding n_file is found
                log_message "WARN" "No matching file found for $g_file"
                echo "Warning: No matching file found for $g_file" >> "$final_output_file"
                echo "Warning: No matching file found for $g_file" >> "$comparison_file"
            fi
        done
    }

    # Compare partitions starting with prdab63g- with prdab63n-
    compare_partitions "$prefix_g" "$prefix_n"
    log_message "INFO" "comparing $prefix_g $prefix_n"

    # Compare partitions starting with prdab63gpsv- with prdab63npsv-
    compare_partitions "$prefix_gpsv" "$prefix_npsv"
    log_message "INFO" "comparing $prefix_gpsv $prefix_npsv"


    # Function to extract the state from the file
    extract_state_word() {
        local file="$1"
        grep -i "state" "$file" | awk '{print $2}' | head -n 1
    }

    # Initialize flags for the final check
    all_g_enabled=true
    all_n_enabled=true
    all_gpsv_enabled=true
    all_npsv_enabled=true

    # Variable to store the output of the loop
    output=""

    # Start of partition checks
    log_message "INFO" "Starting partition state checks..."

    # Loop through files with the 'prdab63g' prefix in the extracted directory
    for g_file in "${extracted_dir}/${prefix_g}"-*; do
        # Check if the file exists to avoid "no such file or directory" error
        if [[ -f "$g_file" ]]; then
            partition_g=$(basename "$g_file" .txt)  # Extract the partition name from the filename

            # Read the corresponding 'n' partition based on the g partition
            partition_n="${partition_g/prdab63g/prdab63n}"

            # Get states for prdab63g and prdab63n partitions
            state_g=$(extract_state_word "$g_file")
            state_n=$(extract_state_word "${extracted_dir}/${partition_n}.txt")

            # Now check the state of prdab63gpsv and prdab63npsv
            gpsv_partition="${partition_g/prdab63g/prdab63gpsv}"
            npsv_partition="${partition_n/prdab63n/prdab63npsv}"

            state_gpsv=$(extract_state_word "${extracted_dir}/${gpsv_partition}.txt")
            state_npsv=$(extract_state_word "${extracted_dir}/${npsv_partition}.txt")

            # Append output to the variable
            output+="Checking partition ${partition_g} and ${partition_n}...\n"
            
            # Log partition checking
            log_message "INFO" "Checking partition ${partition_g} and ${partition_n}. GRL state: $state_g, NHQ state: $state_n, GRL passive: $state_gpsv, NHQ passive: $state_npsv"

            # Apply your conditions
            if [[ "$state_n" == "ENABLED" && "$state_gpsv" == "ENABLED" ]]; then
                output+="NHQ side is active for partition ${partition_n}\n"
                log_message "INFO" "NHQ side active for partition ${partition_n}"
                output+="Checking GRL state...\n"
                if [[ "$state_g" == "DISABLED" && "$state_npsv" == "DISABLED" ]]; then
                    output+="GRL side is disabled for partition ${partition_g}\n"
                    output+="The active partition is prdab63n\n"
                    log_message "INFO" "GRL side is disabled for partition ${partition_g}, prdab63n is active"
                else
                    output+="Can't define the active side, GRL might be partially active.\n"
                    log_message "WARN" "Cannot define active side, GRL might be partially active for partition ${partition_g}"
                fi
            elif [[ "$state_g" == "ENABLED" && "$state_npsv" == "ENABLED" ]]; then
                output+="GRL side is active for partition ${partition_g}\n"
                log_message "INFO" "GRL side active for partition ${partition_g}"
                output+="Checking NHQ state...\n"
                if [[ "$state_n" == "DISABLED" && "$state_gpsv" == "DISABLED" ]]; then
                    output+="NHQ side is disabled for partition ${partition_n}\n"
                    output+="The active partition is prdab63g\n"
                    log_message "INFO" "NHQ side is disabled for partition ${partition_n}, prdab63g is active"
                else
                    output+="Can't define the active side, NHQ might be partially active.\n"
                    log_message "WARN" "Cannot define active side, NHQ might be partially active for partition ${partition_n}"
                fi
            else
                output+="Can't define the active side for partition ${partition_g} and ${partition_n}.\n"
                log_message "WARN" "Unable to define active side for partition ${partition_g} and ${partition_n}"
            fi

            # Update flags based on the current state
            if [[ "$state_g" != "ENABLED" ]]; then
                all_g_enabled=false
            fi
            if [[ "$state_n" != "ENABLED" ]]; then
                all_n_enabled=false
            fi
            if [[ "$state_gpsv" != "ENABLED" ]]; then
                all_gpsv_enabled=false
            fi
            if [[ "$state_npsv" != "ENABLED" ]]; then
                all_npsv_enabled=false
            fi
        else
            output+="Warning: $g_file not found!\n"
            log_message "ERROR" "File $g_file not found!"
        fi

    done

    # Output the result of the loop
    echo -e "$output"

    log_message "INFO" "Partition state checks completed"

    # Final status check logs
    log_message "DEBUG" "all_g_enabled: $all_g_enabled"
    log_message "DEBUG" "all_n_enabled: $all_n_enabled"
    log_message "DEBUG" "all_gpsv_enabled: $all_gpsv_enabled"
    log_message "DEBUG" "all_npsv_enabled: $all_npsv_enabled"

    # Final check for overall state
    if [[ "$all_n_enabled" == true && "$all_g_enabled" == false && "$all_gpsv_enabled" == true && "$all_npsv_enabled" == false ]]; then
        echo "********************************************"
        echo "--------------------------------------------"
        echo "|☺☺☺| prdab63n is active for all ports |☺☺☺|"
        echo "--------------------------------------------"
        echo "********************************************"
        log_message "INFO" "prdab63n is active for all ports"

        # Navigate to the required directory
        cd /tps/scripts/prod_moa/
        
        # Run the commands as specified
        ./make-server-list.sh -p prdab63n | tee /rhome/jbosegs/moa/testing_30082024/active_prdab63n.txt
        ./make-server-list.sh -p prdab63g | tee /rhome/jbosegs/moa/testing_30082024/passive_prdab63g.txt
        cd -

        log_message "INFO" "Server lists saved to active_prdab63n.txt and passive_prdab63g.txt"
        run_hostname_command /rhome/jbosegs/moa/testing_30082024/active_prdab63n.txt
        run_hostname_command /rhome/jbosegs/moa/testing_30082024/passive_prdab63g.txt
        log_message "INFO" "Hostname commands executed for servers in active and passive lists."

    elif [[ "$all_g_enabled" == true && "$all_n_enabled" == false && "$all_npsv_enabled" == true && "$all_gpsv_enabled" == false ]]; then
        echo "********************************************"
        echo "--------------------------------------------"
        echo "|☺☺☺| prdab63g is active for all ports |☺☺☺|"
        echo "--------------------------------------------"
        echo "********************************************"
        log_message "INFO" "prdab63g is active for all ports"
        # Navigate to the required directory
        cd /tps/scripts/prod_moa/
        
        # Run the commands as specified
        ./make-server-list.sh -p prdab63g  | tee /rhome/jbosegs/moa/testing_30082024/active_prdab63g.txt
        ./make-server-list.sh -p prdab63n  | tee /rhome/jbosegs/moa/testing_30082024/passive_prdab63n.txt
        cd -
        log_message "INFO" "Server lists saved to active_prdab63g.txt and passive_prdab63n.txt"
        
        run_hostname_command /rhome/jbosegs/moa/testing_30082024/active_prdab63g.txt
        run_hostname_command /rhome/jbosegs/moa/testing_30082024/passive_prdab63n.txt
        log_message "INFO" "Hostname commands executed for servers in active and passive lists."
        
    else
        echo "*******************************************************"
        echo "-------------------------------------------------------"
        echo "☹  | Can't define which side is fully active. |     ☹"
        echo "-------------------------------------------------------"
        echo "*******************************************************"
        log_message "ERROR" "Can't define which side is fully active"
    fi

    # Initialize files for saving active and passive port lists
    active_port_list="details_active.txt"
    passive_port_list="details_passive.txt"

    # Clear or create files
    > "$active_port_list"
    > "$passive_port_list"



    # Loop through files
    for g_file in "${extracted_dir}/${prefix_g}"-*; do
        if [[ -f "$g_file" ]]; then
            echo "Processing file: $g_file"

            # Partition names
            partition_g=$(basename "$g_file" .txt)
            partition_n="${partition_g/prdab63g/prdab63n}"
            echo "Partition G: $partition_g, Partition N: $partition_n"

            # Extract states
            state_g=$(extract_state_word "$g_file")
            state_n=$(extract_state_word "${extracted_dir}/${partition_n}.txt")
            echo "State G: $state_g, State N: $state_n"

            # GPSV and NPSV
            gpsv_partition="${partition_g/prdab63g/prdab63gpsv}"
            npsv_partition="${partition_n/prdab63n/prdab63npsv}"
            state_gpsv=$(extract_state_word "${extracted_dir}/${gpsv_partition}.txt")
            state_npsv=$(extract_state_word "${extracted_dir}/${npsv_partition}.txt")
            echo "GPSV Partition: $gpsv_partition, State: $state_gpsv"
            echo "NPSV Partition: $npsv_partition, State: $state_npsv"

            # Determine active and passive ports
            if [[ "$state_n" == "ENABLED" && "$state_g" == "DISABLED" ]]; then
                echo "$partition_n ($state_n)" >> "$active_port_list"
                echo "$partition_g ($state_g)" >> "$passive_port_list"
            elif [[ "$state_g" == "ENABLED" && "$state_n" == "DISABLED" ]]; then
                echo "$partition_g ($state_g)" >> "$active_port_list"
                echo "$partition_n ($state_n)" >> "$passive_port_list"
            else
                echo "WARN: Unable to categorize $partition_g and $partition_n" >> error.log
            fi

            # GPSV/NPSV categorization
            if [[ "$state_npsv" == "ENABLED" && "$state_gpsv" == "DISABLED" ]]; then
                echo "$npsv_partition ($state_npsv)" >> "$active_port_list"
                echo "$gpsv_partition ($state_gpsv)" >> "$passive_port_list"
            elif [[ "$state_gpsv" == "ENABLED" && "$state_npsv" == "DISABLED" ]]; then
                echo "$gpsv_partition ($state_gpsv)" >> "$active_port_list"
                echo "$npsv_partition ($state_npsv)" >> "$passive_port_list"
            else
                echo "WARN: Unable to categorize $gpsv_partition and $npsv_partition" >> error.log
            fi
        else
            echo "ERROR: File $g_file not found! Skipping."
        fi
    done

    active_output="extracted_active_ports.txt"
    passive_output="extracted_passive_ports.txt"

    # Check if active_ports.txt exists and process it
    if [[ -f "$active_port_list" ]]; then
        awk '{print $1}' "$active_port_list" > "$active_output"
    else
        echo "Error: $active_port_list not found."
    fi

    # Check if passive_ports.txt exists and process it
    if [[ -f "$passive_port_list" ]]; then
        awk '{print $1}' "$passive_port_list" > "$passive_output"
        echo "Extracted passive ports saved to $passive_output."
    else
        echo "Error: $passive_port_list not found."
    fi

}
# Function to perform the swing operation (add your specific logic here)
perform_the_swing() {

    generate_report

    # Define the base directory to check on each server
    base_dir="/opt/jbinstall/deployedapps"

    # Process files matching the pattern "active*.txt" and "passive*.txt"
    for file_type in "active" "passive"; do
        if compgen -G "${file_type}*.txt" > /dev/null; then
            for server_file in ${file_type}*.txt; do
                mapfile -t server_names < "$server_file"
                for server_name in "${server_names[@]}"; do

                    echo "Connecting to $server_name from $server_file"
                    log_message "INFO" "Connecting to $server_name from $server_file"

                    # Check hostname and fetch Java paths on the server
                    hostname_output=$(ssh "$server_name" "hostname" 2>/dev/null)
                    if [[ $? -eq 0 ]]; then
                        echo "$server_name: $hostname_output"

                        # Output file for Java processes on the server
                        java_output_file="${server_name}_java_processes.txt"

                        # Run command to get Java processes and save to the output file
                        ssh "$server_name" "ps -ef | grep java | grep '$server_name'" > "$java_output_file" 2>/dev/null

                        # Output files for extracted paths
                        extracted_java_files="${server_name}_path_usr_java64.txt"
                        extracted_jbinstall_files="${server_name}_path_opt_jbinstall.txt"

                        # Extract paths starting with /usr/java64/ and /opt/jbinstall/
                        grep -o '/usr/java64/openjdk/[^ /]*' "$java_output_file" > "$extracted_java_files"
                        grep -o '/opt/jbinstall/jboss-eap-[^ /]*' "$java_output_file" | sort -u > "$extracted_jbinstall_files"

                        # Display results
                        echo "The output of 'ps -ef | grep java | grep $server_name' has been saved to $java_output_file."

                        # Print extracted paths for /usr/java64/
                        if [[ -s "$extracted_java_files" ]]; then
                            echo "Extracted file names starting with /usr/java64/:"
                            cat "$extracted_java_files"
                        else
                            echo "No file names starting with /usr/java64/ found."
                        fi

                        # Print extracted paths for /opt/jbinstall/
                        if [[ -s "$extracted_jbinstall_files" ]]; then
                            echo "Extracted file names starting with /opt/jbinstall/:"
                            cat "$extracted_jbinstall_files"
                        else
                            echo "No file names starting with /opt/jbinstall/ found."
                        fi
                    else
                        echo "$server_name: Connection failed"
                    fi

                    echo "Connecting to $server_name from $server_file"
                    log_message "INFO" "Connecting to $server_name from $server_file"

                    # List files in the deployed apps directory on the server
                    ssh "$server_name" "
                        if [ -d '$base_dir/$server_name' ]; then
                            echo 'Listing files in $base_dir/$server_name on $server_name:'
                            ls '$base_dir/$server_name'
                        else
                            echo 'Directory $base_dir/$server_name does not exist on $server_name'
                        fi
                    "
                    # Check hostname
                    hostname_output=$(ssh "$server_name" "hostname" 2>/dev/null)
                    if [[ $? -eq 0 ]]; then
                        echo "$server_name: $hostname_output"

                        # Extracted paths
                        java_home_file="${server_name}_path_usr_java64.txt"
                        jboss_home_file="${server_name}_path_opt_jbinstall.txt"

                        # Validate if files exist and contain paths
                        if [[ -s "$java_home_file" && -s "$jboss_home_file" ]]; then
                            instance_java_home=$(head -n 1 "$java_home_file")
                            instance_jboss_home=$(head -n 1 "$jboss_home_file")

                            if [[ -n "$instance_java_home" && -n "$instance_jboss_home" ]]; then
                                
                                if [[ "$file_type" == "passive" ]]; then
                                    # Remove passive CLI file
                                    
                                    undeploy_command="
                                        rm -f /opt/jbinstall/deployedapps/$server_name/99-deploy-passive.cli
                                    "
                                    
                                    if ssh_execute "$username" "$server_name" "$undeploy_command"; then
                                        log_message "INFO" "Passive service CLI successfully removed on $server_name."
                                    else
                                        log_message "ERROR" "Failed to remove Passive service CLI on $server_name."
                                        true
                                    fi
                                    undeploy_command1="
                                        export JAVA_OPTS='-Djavax.net.ssl.trustStoreType=jks -Djavax.net.ssl.trustStore=/tps/security/truststores/prod/cacerts -Djavax.net.ssl.trustStorePassword=jbo4tps';
                                        export JAVA_HOME='$instance_java_home';
                                        ${instance_jboss_home}/bin/jboss-cli.sh --connect --controller=${server_name}.amfam.com:9999 --command='undeploy amfam-jbossha-passive-service.jar'
                                    "
                                    if ssh_execute "$username" "$server_name" "$undeploy_command1"; then
                                        log_message "INFO" "Passive service CLI successfully undeployed on $server_name."
                                    else
                                        log_message "ERROR" "Failed to undeploy Passive service CLI on $server_name."
                                        true
                                    fi
                                fi
                                if  [[ "$file_type" == "active" ]]; then                                
                                    # Remove active CLI file
                                    undeploy_command3="
                                        rm -f /opt/jbinstall/deployedapps/$server_name/99-deploy-active.cli
                                    "
                                    
                                    if ssh_execute "$username" "$server_name" "$undeploy_command3"; then
                                        log_message "INFO" "Active service CLI successfully removed on $server_name."
                                    else
                                        log_message "ERROR" "Failed to remove Active service CLI on $server_name."
                                        true
                                    fi
                                    undeploy_command4="
                                        export JAVA_OPTS='-Djavax.net.ssl.trustStoreType=jks -Djavax.net.ssl.trustStore=/tps/security/truststores/prod/cacerts -Djavax.net.ssl.trustStorePassword=jbo4tps' ;
                                        export JAVA_HOME='$instance_java_home'; 
                                        ${instance_jboss_home}/bin/jboss-cli.sh --connect --controller=${server_name}.amfam.com:9999 --command='undeploy amfam-jbossha-active-service.jar' 
                                    "
                                    if ssh_execute "$username" "$server_name" "$undeploy_command4"; then
                                        log_message "INFO" "Active service CLI successfully undeployed on $server_name."
                                    else
                                        log_message "ERROR" "Failed to undeploy Active service CLI on $server_name."
                                        true
                                    fi
                                fi
                            else
                                echo "Required paths not found in $java_home_file or $jboss_home_file"
                                log_message "ERROR" "Paths missing for $server_name"
                            fi
                        else
                            echo "Path files missing or empty for $server_name. Skipping..."
                            log_message "ERROR" "Path files missing or empty for $server_name"
                        fi
                    else
                        echo "$server_name: Connection failed"
                        log_message "ERROR" "Connection failed for $server_name"
                    fi

                done
            done
        fi
    done

    echo "Performing the swing operation..."
    log_message "INFO" "Performing the swing operation..."

    # Run Expect scripts and check for existence of the output file
    expect -f swing.exp "$nsclpci" > "swing.txt"
    # Read the content of $input_file
    if [[ -f "swing.txt" ]]; then
        file_content3=$(cat "swing.txt")
    else
        file_content3="Error: swing.txt not found or empty."
    fi

    # Extract the filename and assign the result to $active_name
    active_name=$(basename "$(ls active_pr*.txt)" | sed -E 's/active_(.*)\.txt/\1/')

    # Output the value of $active_name
    echo "$active_name"


    # Extract the filename and assign the result to $active_name
    passive_name=$(basename "$(ls passive_pr*.txt)" | sed -E 's/passive_(.*)\.txt/\1/')

    # Output the value of $active_name
    echo "$passive_name"

    # Log the Expect script output
    log_message "INFO" "Ran the Expect script. Output: $file_content3"

    # Process files matching the pattern "active*.txt" and "passive*.txt"
    for file_type in "active" "passive"; do
        if compgen -G "${file_type}*.txt" > /dev/null; then
            for server_file in ${file_type}*.txt; do
                mapfile -t server_names < "$server_file"
                for server_name in "${server_names[@]}"; do

                    echo "Connecting to $server_name from $server_file"
                    log_message "INFO" "Connecting to $server_name from $server_file"

                    # Check hostname and fetch Java paths on the server
                    hostname_output=$(ssh "$server_name" "hostname" 2>/dev/null)
                    if [[ $? -eq 0 ]]; then
                        echo "$server_name: $hostname_output"

                        # Output file for Java processes on the server
                        java_output_file="${server_name}_java_processes.txt"

                        # Run command to get Java processes and save to the output file
                        ssh "$server_name" "ps -ef | grep java | grep '$server_name'" > "$java_output_file" 2>/dev/null

                        # Output files for extracted paths
                        extracted_java_files="${server_name}_path_usr_java64.txt"
                        extracted_jbinstall_files="${server_name}_path_opt_jbinstall.txt"

                        # Extract paths starting with /usr/java64/ and /opt/jbinstall/
                        grep -o '/usr/java64/openjdk/[^ /]*' "$java_output_file" > "$extracted_java_files"
                        grep -o '/opt/jbinstall/jboss-eap-[^ /]*' "$java_output_file" | sort -u > "$extracted_jbinstall_files"

                        # Display results
                        echo "The output of 'ps -ef | grep java | grep $server_name' has been saved to $java_output_file."

                        # Print extracted paths for /usr/java64/
                        if [[ -s "$extracted_java_files" ]]; then
                            echo "Extracted file names starting with /usr/java64/:"
                            cat "$extracted_java_files"
                        else
                            echo "No file names starting with /usr/java64/ found."
                        fi

                        # Print extracted paths for /opt/jbinstall/
                        if [[ -s "$extracted_jbinstall_files" ]]; then
                            echo "Extracted file names starting with /opt/jbinstall/:"
                            cat "$extracted_jbinstall_files"
                        else
                            echo "No file names starting with /opt/jbinstall/ found."
                        fi
                    else
                        echo "$server_name: Connection failed"
                    fi

                    echo "Connecting to $server_name from $server_file"
                    log_message "INFO" "Connecting to $server_name from $server_file"

                    # List files in the deployed apps directory on the server
                    ssh "$server_name" "
                        if [ -d '$base_dir/$server_name' ]; then
                            echo 'Listing files in $base_dir/$server_name on $server_name:'
                            ls '$base_dir/$server_name'
                        else
                            echo 'Directory $base_dir/$server_name does not exist on $server_name'
                        fi
                    "
                    # Check hostname
                    hostname_output=$(ssh "$server_name" "hostname" 2>/dev/null)
                    if [[ $? -eq 0 ]]; then
                        echo "$server_name: $hostname_output"

                        # Extracted paths
                        java_home_file="${server_name}_path_usr_java64.txt"
                        jboss_home_file="${server_name}_path_opt_jbinstall.txt"

                        # Validate if files exist and contain paths
                        if [[ -s "$java_home_file" && -s "$jboss_home_file" ]]; then
                            instance_java_home=$(head -n 1 "$java_home_file")
                            instance_jboss_home=$(head -n 1 "$jboss_home_file")

                            if [[ -n "$instance_java_home" && -n "$instance_jboss_home" ]]; then
                                
                                if [[ "$file_type" == "passive" ]]; then

                                    passive_p="passive_symlink_target.txt"

                                    # Extract the second part of the filename and save it to $active_p
                                    basename "$(ls active_pr*.txt)" | sed -E 's/active_(.*)\.txt/\1/' > "$passive_p"

                                    # Read the value from $active_p
                                    passive_value=$(<"$passive_p")

                                    # Output the value for verification
                                    echo "$passive_value"

                                    log_message "INFO" "------------------------------------------------------"
                                    log_message "INFO" "Connecting to "$server_name" to deploy the Active service jar via CLI"

                                    # Deploying service jar active CLI
                                    deploy_command1="echo 'deploy /opt/jbinstall/deployedmodules/${server_name}/com/amfam/jbossha/ha_jars/amfam-jbossha-active-service.jar' > /opt/jbinstall/deployedapps/${server_name}/99-deploy-active.cli"
                                    if ssh_execute "$username" "$server_name" "$deploy_command1"; then
                                        log_message "INFO" "Active service CLI command successfully created on $server_name."
                                    else
                                        log_message "ERROR" "Failed to create Active service CLI command on $server_name."
                                        true
                                    fi
                                    
                                    deploy_command2="\
                                    export JAVA_OPTS='-Djavax.net.ssl.trustStoreType=jks -Djavax.net.ssl.trustStore=/tps/security/truststores/prod/cacerts -Djavax.net.ssl.trustStorePassword=jbo4tps'; \
                                    export JAVA_HOME=${instance_java_home}; \
                                    ${instance_jboss_home}/bin/jboss-cli.sh --connect --controller=${server_name}.amfam.com:9999 --file=/opt/jbinstall/deployedapps/${server_name}/99-deploy-active.cli"
                                    if ssh_execute "$username" "$server_name" "$deploy_command2"; then
                                        log_message "INFO" "Successfully deployed active service jar on $server_name."
                                    else
                                        log_message "ERROR" "Failed to deploy active service jar on $server_name."
                                        true
                                    fi

                                    
                                    command2="mkdir -p /opt/jbinstall/deployedapps/jbossHA/active/"
                                    ssh_execute "$username" "$server_name" "$command2"
                                    log_message "INFO" "exectuting command: $command2"
                                    command3="rm -rf /opt/jbinstall/deployedapps/jbossHA/active/$main_partition"
                                    ssh_execute "$username" "$server_name" "$command3"
                                    log_message "INFO" "exectuting command: $command3"

                                    command4="ln -f -s /opt/jbinstall/deployedapps/$passive_name /opt/jbinstall/deployedapps/jbossHA/active/$main_partition"
                                    ssh_execute "$username" "$server_name" "$command4"
                                    log_message "INFO" "exectuting command: $command4"

                                    log_message "removing the previous file /opt/jbinstall/deployedapps/"
                                    command5="cd /opt/jbinstall/deployedapps/jbossHA/passive && rm -rf prdab63"
                                    ssh_execute "$username" "$server_name" "$command5"
                                    log_message "INFO" "exectuting command: $command5"


                                    log_message "INFO" "exectuting script updateBatchInterface.sh"
                                    first_enabled_server=$(head -n 1 passive_pr*.txt | awk '{print substr($0, 1, 7)}')
                                    # Execute the command and capture the exit status
                                    if /home/jbosegs/moa/updateBatchInterface.sh -o a -p prdab63 -b "${first_enabled_server}" | tee -a "$log_file"; then
                                        log_message "INFO" "Command executed successfully: updateBatchInterface.sh -o a -p prdab63 -b ${first_enabled_server}"
                                    else
                                        log_message "ERROR" "Command failed: updateBatchInterface.sh -o a -p prdab63 -b ${first_enabled_server}"
                                    fi


                                fi
                                if [[ "$file_type" == "active" ]]; then
                                    active_p="active_symlink_target.txt"

                                    # Extract the second part of the filename and save it to $passive_p
                                    if ls passive_pr*.txt > /dev/null 2>&1; then
                                        basename "$(ls passive_pr*.txt)" | sed -E 's/passive_(.*)\.txt/\1/' > "$active_p"
                                        active_value=$(<"$active_p")
                                    else
                                        log_message "ERROR" "No passive_pr*.txt file found. Exiting."
                                        exit
                                    fi

                                    # Output the value for verification
                                    echo "$active_value"
                                    log_message "INFO" "------------------------------------------------------"
                                    log_message "INFO" "Connecting to $server_name to deploy the Passive service jar via CLI"

                                    # Deploying service jar passive CLI
                                    command1="echo 'deploy /opt/jbinstall/deployedmodules/${server_name}/com/amfam/jbossha/ha_jars/amfam-jbossha-passive-service.jar' > /opt/jbinstall/deployedapps/${server_name}/99-deploy-passive.cli"

                                    if ssh_execute "$username" "$server_name" "$command1"; then
                                        log_message "INFO" "Passive service CLI command successfully created on $server_name."
                                    else
                                        log_message "ERROR" "Failed to create Passive service CLI command on $server_name."
                                        true
                                    fi

                                    # Deploy passive service jar
                                    deploy_command="\
                                    export JAVA_OPTS='-Djavax.net.ssl.trustStoreType=jks -Djavax.net.ssl.trustStore=/tps/security/truststores/prod/cacerts -Djavax.net.ssl.trustStorePassword=jbo4tps'; \
                                    export JAVA_HOME=\"${instance_java_home}\"; \
                                    \"${instance_jboss_home}/bin/jboss-cli.sh\" --connect --controller=\"${server_name}.amfam.com:9999\" --file=\"/opt/jbinstall/deployedapps/${server_name}/99-deploy-passive.cli\" "
                                    if ssh_execute "$username" "$server_name" "$deploy_command"; then
                                        log_message "INFO" "Successfully deployed passive service jar on $server_name."
                                    else
                                        log_message "ERROR" "Failed to deploy passive service jar on $server_name."
                                        true
                                    fi

                                    # Steps for symlink creation
                                    log_message "INFO" "Creating the passive symlink of /opt/jbinstall/deployedapps/jbossHA/$active_value/"

                                    # Create directory for passive symlink
                                    command2="mkdir -p /opt/jbinstall/deployedapps/jbossHA/passive/"
                                    if ssh_execute "$username" "$server_name" "$command2"; then
                                        log_message "INFO" "Successfully executed command: $command2"
                                    else
                                        log_message "ERROR" "Failed to execute command: $command2"
                                        true
                                    fi

                                    # Remove previous passive files
                                    command3="rm -rf /opt/jbinstall/deployedapps/jbossHA/passive/$main_partition"
                                    if ssh_execute "$username" "$server_name" "$command3"; then
                                        log_message "INFO" "Successfully executed command: $command3"
                                    else
                                        log_message "ERROR" "Failed to execute command: $command3"
                                        true
                                    fi

                                    # Create symlink
                                    command4="ln -f -s /opt/jbinstall/deployedapps/$active_name /opt/jbinstall/deployedapps/jbossHA/passive/$main_partition"
                                    if ssh_execute "$username" "$server_name" "$command4"; then
                                        log_message "INFO" "Successfully executed command: $command4"
                                    else
                                        log_message "ERROR" "Failed to execute command: $command4"
                                        true
                                    fi

                                    log_message "removing the previous file /opt/jbinstall/deployedapps/"
                                    command5="cd /opt/jbinstall/deployedapps/jbossHA/active && rm -rf prdab63"
                                    ssh_execute "$username" "$server_name" "$command5"
                                    log_message "INFO" "exectuting command: $command5"


                                fi
                            else
                                echo "Required paths not found in $java_home_file or $jboss_home_file"
                                log_message "ERROR" "Paths missing for $server_name"
                            fi
                        else
                            echo "Path files missing or empty for $server_name. Skipping..."
                            log_message "ERROR" "Path files missing or empty for $server_name"
                        fi
                    else
                        echo "$server_name: Connection failed"
                        log_message "ERROR" "Connection failed for $server_name"
                    fi

                done
            done
        fi
        echo "*************************************************************************************"
        echo "Current active partiton is: $passive_name"
        echo "*************************************************************************************"
        log_message "INFO" "*************************************************************************************"
        log_message "SUCCESS" "Current active partiton is: $passive_name"
        log_message "INFO" "*************************************************************************************"
    done
}

# Main function to handle user input
main() {
    log_message "INFO" "Script started with argument: $1"

    case "$1" in
        generatereport)
            log_message "INFO" "User selected 'generatereport'."
            generate_report
            ;;
        perform_the_swing)
            log_message "INFO" "User selected 'perform_the_swing'."
            perform_the_swing
            ;;
        *)
            log_message "WARN" "Invalid option provided by user."
            # Display choice menu if no valid argument is provided
            echo "Please select an option from below:"
            echo "1) ./script_name.sh generatereport"
            echo "2) ./script_name.sh perform_the_swing"
            ;;
    esac

    log_message "INFO" "Script execution completed."
}

# Call the main function with the first argument passed to the script
main "$1"