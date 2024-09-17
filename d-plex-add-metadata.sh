#!/bin/bash

# Check for the correct number of arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <path_to_videos> <audio_language>"
    exit 1
fi

# Assign arguments to variables
VIDEO_PATH="$1"
AUDIO_LANGUAGE="$2"

# Check if the specified path exists
if [ ! -d "$VIDEO_PATH" ]; then
    echo "Error: Directory $VIDEO_PATH does not exist."
    exit 1
fi

# Function to process each video file
process_file() {
    local file="$1"
    local filename=$(basename "$file")
    local extension="${filename##*.}"
    local title="${filename%.*}"
    local temp_file="${file}.tmp.${extension}"
    local log_file="${file}.log"

    echo "Processing $file..."

    # Add metadata and audio language using ffmpeg
    ffmpeg -i "$file" \
        -map 0:v -map 0:a \
        -c:v copy -c:a copy \
        -metadata title="$title" \
        -metadata:s:a:0 language="$AUDIO_LANGUAGE" \
        "$temp_file" 2>"$log_file"

    # Check if ffmpeg succeeded
    if [ $? -eq 0 ]; then
        # Replace the original file with the temp file
        mv "$temp_file" "$file"
        echo "Updated $file with title '$title' and audio language '$AUDIO_LANGUAGE'."
        rm -f "$log_file"  # Remove log file if processing was successful
    else
        echo "Error processing $file. Check $log_file for details."
        rm -f "$temp_file"
    fi
}

# Process all mkv and mp4 files in the specified directory
for file in "$VIDEO_PATH"/*.{mkv,mp4}; do
    # Skip non-existent files (in case there are no matches)
    [ -e "$file" ] || continue
    process_file "$file"
done

