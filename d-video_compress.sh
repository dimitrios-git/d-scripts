#!/bin/bash

# Function to check the file extension
check_extension() {
    local file="$1"
    local ext="${file##*.}"
    if [[ ! "$ext" =~ ^(mp4|MP4|mov|MOV|mkv|MKV)$ ]]; then
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

# Function to print recommended bitrate table
print_bitrate_table() {
    echo -e "\nRecommended Bitrate Settings:\n"
    printf "%-12s %-35s %-30s\n" "Type" "Standard Frame Rate (24, 25, 30)" "High Frame Rate (48, 50, 60)"
    printf "%-12s %-35s %-30s\n" "8K" "80 - 160 Mbps | HDR: 100 - 200 Mbps" "120 - 240 Mbps | HDR: 150 - 300 Mbps"
    printf "%-12s %-35s %-30s\n" "2160p (4K)" "35 - 45 Mbps | HDR: 44 - 56 Mbps" "53 - 68 Mbps | HDR: 66 - 85 Mbps"
    printf "%-12s %-35s %-30s\n" "1440p (2K)" "16 Mbps | HDR: 20 Mbps" "24 Mbps | HDR: 30 Mbps"
    printf "%-12s %-35s %-30s\n" "1080p" "8 Mbps | HDR: 10 Mbps" "12 Mbps | HDR: 15 Mbps"
    printf "%-12s %-35s %-30s\n" "720p" "5 Mbps | HDR: 6.5 Mbps" "7.5 Mbps | HDR: 9.5 Mbps"
    printf "%-12s %-35s %-30s\n" "480p" "2.5 Mbps" "4 Mbps"
    printf "%-12s %-35s %-30s\n" "360p" "1 Mbps" "1.5 Mbps"
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
        -map 0 -map_metadata 0 \
        -r 24000/1001 \
        -c:v h264_nvenc -pix_fmt yuv420p -bf 2 -g "$gop" -coder 1 \
        -movflags +faststart -preset slow \
        -b:v "$target_bitrate" -maxrate "$((2 * ${target_bitrate%M}))M" \
        -bufsize "$((2 * ${target_bitrate%M}))M" \
        -c:a copy -c:s copy \
        "${input_file%.*}_nvenc.${input_file##*.}"
    )

    echo -e "\nConstructed ffmpeg command:\n${ffmpeg_cmd[*]}"

    read -p "Is this command okay to run? (y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        "${ffmpeg_cmd[@]}"
        echo "Conversion completed."
    else
        echo "Conversion aborted."
    fi
}

# Main script execution
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <input_video>"
    exit 1
fi

input_video="$1"
check_extension "$input_video"
get_video_info "$input_video"

# Display bitrate table and get target bitrate
print_bitrate_table
echo
echo "Enter the target video bitrate (e.g., 8M for 8 Mbps): "
read target_bitrate

if [[ ! "$target_bitrate" =~ ^[0-9]+M$ ]]; then
    echo "Invalid bitrate format. Please use the format <number>M (e.g., 8M)."
    exit 1
fi

run_ffmpeg_conversion "$input_video" "$target_bitrate"

