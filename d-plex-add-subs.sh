#!/bin/bash

# Check if the correct number of arguments is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path_to_video_file>"
    exit 1
fi

# Get the path to the video file
video_file="$1"

# Check if the provided file exists
if [ ! -f "$video_file" ]; then
    echo "Error: File '$video_file' not found."
    exit 1
fi

# Extract the filename and directory from the video file path
dir_name=$(dirname "$video_file")
base_name=$(basename "$video_file" | sed 's/\.[^.]*$//')

# Change directory to the location of the video file
cd "$dir_name" || { echo "Error: Failed to change directory to '$dir_name'."; exit 1; }

# List available audio streams
echo "Available audio streams:"
ffmpeg -i "$video_file" 2>&1 | grep -E "Stream #.*: Audio" | nl

# Get user input for stream selection
read -p "Enter the stream number to extract (e.g., 1, 2, etc.): " stream_num

# Validate user input
if [[ ! "$stream_num" =~ ^[0-9]+$ ]]; then
    echo "Invalid input. Please enter a valid number."
    exit 1
fi

# Extract audio using ffmpeg
wav_file="$base_name.wav"
ffmpeg -i "$video_file" -map 0:a:$((stream_num-1)) -q:a 0 "$wav_file" || { echo "Error: Failed to extract audio."; exit 1; }

# Run whisperx on the .wav file
whisperx "$wav_file" --model large-v3 --language en --align_model WAV2VEC2_ASR_LARGE_LV60K_960H --batch_size 4 --vad_onset 0.10 --vad_offset 0.05 --print_progress True || { echo "Error: WhisperX processing failed."; rm "$wav_file"; exit 1; }

# Rename the .srt file and remove other files
srt_file="$base_name.eng.whisperx.srt"
if [ -f "$base_name.srt" ]; then
    mv "$base_name.srt" "$srt_file"
fi

# Clean up: remove .wav file and other output files
rm "$wav_file"
rm "$base_name.json" "$base_name.txt" "$base_name.vtt" "$base_name.tsv" 2>/dev/null || true

echo "Processing complete. The .srt file is located at: $srt_file"

