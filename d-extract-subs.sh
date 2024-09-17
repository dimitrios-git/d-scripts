#!/bin/bash

# Check if the file path is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <file.mkv>"
    exit 1
fi

input_file="$1"

# Fetch subtitle track information using mediainfo
echo "Fetching subtitle track information..."
mediainfo_output=$(mediainfo -f "$input_file")

# Initialize associative arrays
declare -A subtitle_id_map
declare -A subtitle_language_map

# Initialize variables
record_id=""
subtitle_id=""
language_found=0

# Parse the mediainfo output
while IFS= read -r line; do
    if [[ "$line" =~ ^Text\ #([0-9]+) ]]; then
        record_id="${BASH_REMATCH[1]}"
        echo "Found Text stream, setting record_id to $record_id"  # Debugging line
    elif [[ "$line" =~ ^StreamOrder ]]; then
        if [ -n "$record_id" ]; then
            subtitle_id=$(echo "$line" | awk -F': ' '{print $2}')
            echo "Found StreamOrder, setting subtitle_id to $subtitle_id"  # Debugging line
            subtitle_id_map["$record_id"]="$subtitle_id"
        fi
    elif [[ "$line" =~ ^Language.*[a-zA-Z]{3} ]]; then
        if [ -n "$record_id" ]; then
            language=$(echo "$line" | awk -F': ' '{print $2}' | awk '{print tolower($0)}')
            if [ ${#language} -eq 3 ]; then
                subtitle_language_map["$record_id"]="$language"
                language_found=1
                echo "Found Language, setting subtitle_language to $language"  # Debugging line
            fi
        fi
    fi
done <<< "$mediainfo_output"

# Display the collected subtitle information
echo "Collected subtitle information:"
for record_id in "${!subtitle_id_map[@]}"; do
    subtitle_id="${subtitle_id_map[$record_id]}"
    subtitle_language="${subtitle_language_map[$record_id]}"
    echo "$record_id -> $subtitle_id -> $subtitle_language"
done

# Check if any subtitle information was found
if [ ${#subtitle_id_map[@]} -eq 0 ]; then
    echo "Error: No subtitle streams found."
    exit 1
fi

# Iterate over the stored subtitle information and extract subtitles
for record_id in "${!subtitle_id_map[@]}"; do
    subtitle_id="${subtitle_id_map[$record_id]}"
    subtitle_language="${subtitle_language_map[$record_id]}"
    if [ -n "$subtitle_id" ] && [ -n "$subtitle_language" ]; then
        echo "Extracting subtitle for record_id $record_id..."
        output_file="${input_file%.*}.$subtitle_language.srt"
        mkvextract tracks "$input_file" "$subtitle_id:$output_file"
        echo "Subtitle extraction complete: $output_file"
    else
        echo "Error: Incomplete subtitle information for record_id $record_id."
    fi
done

