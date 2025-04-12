#!/bin/bash

# Configuration flags
interactive=0

# Function to check if the file has a valid extension
is_valid_extension() {
    local file="$1"
    local ext="${file##*.}"
    [[ "$ext" =~ ^(mp4|MP4|mov|MOV|mkv|MKV)$ ]]
}

# Function to check the file extension and exit if invalid
check_extension() {
    local file="$1"
    if ! is_valid_extension "$file"; then
        echo "Error: Only .MP4, .MOV or .MKV files are supported."
        exit 1
    fi
}

# Function to extract video resolution and frame rate
get_video_info() {
    local input_file="$1"

    # Ensure ffprobe is available
    if ! command -v ffprobe &> /dev/null; then
        echo "Error: ffprobe is not installed. Please install ffmpeg tools."
        exit 1
    fi

    # Extract resolution and frame rate using ffprobe
    resolution=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=width,height \
        -of csv=p=0 "$input_file" | head -1)
    
    frame_rate=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=r_frame_rate \
        -of csv=p=0 "$input_file" | awk -F'/' '{printf "%.0f", $1/$2}')

    echo "Video Resolution: ${resolution//,/x}"
    echo "Frame Rate: ${frame_rate} fps"
}

print_help() {
    echo "Usage: $0 [-h] [-i] -b BITRATE (-d DIRECTORY | INPUT_FILE)"
    echo "Convert video files using NVIDIA NVENC H.264 encoding."
    echo
    echo "Options:"
    echo "  -h            Display this help message and show bitrate recommendations."
    echo "  -i            Interactive mode: show ffmpeg command and confirm before running"
    echo "  -d DIRECTORY  Process video files in the specified directory"
    echo "  -b BITRATE    Target video bitrate (e.g., 8M for 8 Mbps). Required."
    exit 0
}

# Function to construct and execute ffmpeg command
run_ffmpeg_conversion() {
    local input_file="$1"
    local target_bitrate="$2"

    # Calculate GOP value (half of the frame rate)
    local gop=$((frame_rate / 2))

    # Construct ffmpeg command
    ffmpeg_cmd=(
        ffmpeg -hwaccel cuda -i "$input_file" \
        -c:v h264_nvenc -pix_fmt yuv420p -bf 2 -g "$gop" -coder 1 \
        -movflags +faststart -preset slow \
        -b:v "$target_bitrate" -maxrate "$((2 * ${target_bitrate%M}))M" \
        -bufsize "$((2 * ${target_bitrate%M}))M" \
        -c:a copy -c:s copy \
        "${input_file%.*}_nvenc.${input_file##*.}"
    )

    if [[ $interactive -eq 1 ]]; then
        echo -e "\nConstructed ffmpeg command:\n${ffmpeg_cmd[*]}"
        read -p "Is this command okay to run? (y/n): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Conversion aborted."
            return 1
        fi
    fi

    "${ffmpeg_cmd[@]}"
    echo "Conversion completed."
}

# Main script execution
show_help=0
directory=""
bitrate=""

# Parse command-line options
while getopts "hid:b:" opt; do
    case $opt in
        h) show_help=1;;
        i) interactive=1;;
        d) directory="$OPTARG";;
        b) bitrate="$OPTARG";;
        *) echo "Invalid option: -$OPTARG" >&2; exit 1;;
    esac
done
shift $((OPTIND -1))

# Show help if requested
if [[ $show_help -eq 1 ]]; then
    print_help
fi

# Validate required bitrate
if [[ -z "$bitrate" ]]; then
    echo "Error: -b bitrate is required." >&2
    exit 1
fi

# Validate bitrate format
if [[ ! "$bitrate" =~ ^[0-9]+M$ ]]; then
    echo "Invalid bitrate format. Please use the format <number>M (e.g., 8M)." >&2
    exit 1
fi

# Handle directory or single file processing
if [[ -n "$directory" ]]; then
    # Directory processing
    if [[ $# -ne 0 ]]; then
        echo "Error: No arguments allowed when using -d option." >&2
        exit 1
    fi

    if [[ ! -d "$directory" ]]; then
        echo "Error: Directory '$directory' does not exist." >&2
        exit 1
    fi

    # Collect and sort valid files
    files=()
    while IFS= read -r -d $'\0' file; do
        if is_valid_extension "$file"; then
            files+=("$file")
        fi
    done < <(find "$directory" -maxdepth 1 -type f -print0)

    # Sort files alphabetically case-insensitive
    readarray -t sorted_files < <(printf "%s\n" "${files[@]}" | sort -f)
    files=("${sorted_files[@]}")

    if [[ ${#files[@]} -eq 0 ]]; then
        echo "No supported video files found in directory '$directory'."
        exit 0
    fi

    # Display files
    echo "Found ${#files[@]} supported video files:"
    for i in "${!files[@]}"; do
        printf "%2d) %s\n" "$((i+1))" "${files[i]}"
    done

    # Get user selection
    while true; do
        read -p $'\nEnter file numbers (comma-separated), "all", or "abort": ' selection
        case "$selection" in
            [Aa]ll)
                selected_files=("${files[@]}")
                break
                ;;
            [Aa]bort)
                echo "Processing aborted."
                exit 0
                ;;
            *)
                IFS=',' read -ra nums <<< "$selection"
                selected_files=()
                valid=true
                for num in "${nums[@]}"; do
                    num=${num//[[:space:]]/}
                    if [[ ! "$num" =~ ^[0-9]+$ ]]; then
                        echo "Invalid number: $num"
                        valid=false
                        break
                    fi
                    index=$((num - 1))
                    if [[ $index -lt 0 || $index -ge ${#files[@]} ]]; then
                        echo "Number out of range: $num"
                        valid=false
                        break
                    fi
                    selected_files+=("${files[index]}")
                done
                $valid && break
                ;;
        esac
    done

    # Process selected files
    for file in "${selected_files[@]}"; do
        echo -e "\nProcessing file: $file"
        get_video_info "$file"
        run_ffmpeg_conversion "$file" "$bitrate"
    done
else
    # Single file processing
    if [[ $# -ne 1 ]]; then
        echo "Error: No input file specified." >&2
        exit 1
    fi
    input_file="$1"
    check_extension "$input_file"
    get_video_info "$input_file"
    run_ffmpeg_conversion "$input_file" "$bitrate"
fi
