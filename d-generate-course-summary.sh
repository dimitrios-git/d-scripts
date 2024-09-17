#!/bin/bash

# Check if the argument is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <directory_path>"
    exit 1
fi

# Define the directory path from the argument
directory_path="$1"

# Check if the provided path is a directory
if [ ! -d "$directory_path" ]; then
    echo "Error: $directory_path is not a valid directory."
    exit 1
fi

# Define the log file
log_file="course_summary.md"

# Clear the log file if it already exists
> "$log_file"

# Initialize total duration in seconds for all directories
declare -A dir_durations

# Get the main heading (top-level directory name)
main_heading=$(basename "$directory_path")

# Function to convert seconds to conversational format
seconds_to_conversational() {
    local seconds=$1
    local hours=$(( seconds / 3600 ))
    local minutes=$(( (seconds % 3600) / 60 ))

    if [ "$seconds" -gt 0 ] && [ "$minutes" -eq 0 ]; then
        echo "less than a minute"
    elif [ "$hours" -gt 0 ] && [ "$minutes" -gt 0 ]; then
        echo "$hours hour$([ $hours -gt 1 ] && echo "s") and $minutes minute$([ $minutes -gt 1 ] && echo "s")"
    elif [ "$hours" -gt 0 ]; then
        echo "$hours hour$([ $hours -gt 1 ] && echo "s")"
    else
        echo "$minutes minute$([ $minutes -gt 1 ] && echo "s")"
    fi
}

# Function to process each directory
process_directory() {
    local dir="$1"

    echo "Processing directory: $dir"

    # Initialize duration for the current directory
    local total_duration=0

    # Find all mp4 files in the directory and subdirectories
    while IFS= read -r file; do
        echo "Processing file: $file"
        
        # Get file duration in seconds using ffprobe
        duration=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=nk=1:nw=1 "$file" 2>/dev/null)
        
        if [ $? -ne 0 ]; then
            echo "Error: Unable to get duration for $file" >> "$log_file"
            continue
        fi
        
        # Convert duration to integer and accumulate
        duration=${duration%.*}
        if [[ ! "$duration" =~ ^[0-9]+$ ]]; then
            echo "Error: Invalid duration value '$duration' for $file" >> "$log_file"
            continue
        fi
        total_duration=$(( total_duration + duration ))
    done < <(find "$dir" -type f -name "*.mp4")

    # Record the duration for this directory
    if [ "$total_duration" -gt 0 ]; then
        dir_durations["$dir"]=$total_duration
    fi

    # Recursively process subdirectories
    for sub_dir in "$dir"/*/; do
        [ -d "$sub_dir" ] && process_directory "$sub_dir"
    done
}

# Start processing from the top-level directory
echo "Starting directory processing..."
process_directory "$directory_path"
echo "Directory processing complete."

# Function to print directory durations as Markdown table
print_dir_durations() {
    local dir="$1"
    local indent="$2"

    # Print the duration for the current directory if available
    if [ -n "${dir_durations[$dir]}" ]; then
        local duration_conversational=$(seconds_to_conversational "${dir_durations[$dir]}")
        echo "| $(basename "$dir") | $duration_conversational |" >> "$log_file"
    fi

    # Process subdirectories
    for sub_dir in "$dir"/*/; do
        [ -d "$sub_dir" ] && print_dir_durations "$sub_dir" "$indent"
    done
}

# Write the main heading and table headers
echo "# $main_heading" > "$log_file"
echo "" >> "$log_file"
echo "| Course | Duration |" >> "$log_file"
echo "|--------|----------|" >> "$log_file"

# Start printing the summary
echo "Generating summary..."
print_dir_durations "$directory_path" ""
echo "Summary generation complete."

echo "Summary complete. Log file created: $log_file"

