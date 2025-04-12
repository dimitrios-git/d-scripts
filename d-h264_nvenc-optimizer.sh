#!/bin/bash

# Define log file location
log_file="encoding.log"

# Clear existing log file
: > "$log_file"

# Custom logging function
log() {
    echo "$@"
    echo "$@" >> "$log_file"
}

# Display help information
show_help() {
    echo "Usage: $0 [-d] [-h] <input_file_or_directory>"
    echo "Optimize video files for H.264 NVEnc encoding while maintaining quality (SSIM > 0.99)"
    echo
    echo "Options:"
    echo "  -d    Process a directory of video files"
    echo "  -h    Show this help message"
    echo
    echo "Single file mode:"
    echo "  Interactive mode with bitrate recommendations and quality checks"
    echo "  Preserves original audio/subtitle tracks and metadata"
    echo
    echo "Directory mode:"
    echo "  - Processes all supported files in alphabetical order"
    echo "  - Uses automatic bitrate calculations (80% of detected maxrate)"
    echo "  - Fixed minimum decrement step of 99kbps"
    echo
    echo "Supported formats: MKV, MP4, MOV (case insensitive)"
    exit 0
}

# Initialize variables
directory_mode=false
declare -a files_to_process
valid_exts=("mkv" "mp4" "mov")
default_min_decrement=99

# Parse command line options
while getopts ":dh" opt; do
    case $opt in
        d)  directory_mode=true ;;
        h)  show_help ;;
        \?) log "Invalid option: -$OPTARG" >&2; exit 1 ;;
        :)  log "Option -$OPTARG requires an argument." >&2; exit 1 ;;
    esac
done
shift $((OPTIND -1))

# Validate input parameter
if [ $# -eq 0 ]; then
    log "Error: No input specified"
    show_help
    exit 1
fi

input_path="$1"

# Directory processing function with sorted output
process_directory() {
    local dir="$1"
    declare -a found_files=()
    
    # Find and sort supported files (case-insensitive)
    while IFS= read -r -d $'\0' file; do
        found_files+=("$file")
    done < <(find "$dir" -type f -print0 2>/dev/null | \
             grep -z -iE "\.($(IFS=\|; echo "${valid_exts[*]}"))$" | \
             grep -z -vi "encoded_outputs" | \
             sort -z -f | \
             tr '\n' '\0' | \
             xargs -0n1 | \
             sort -V | \
             tr '\n' '\0')
   
    if [ ${#found_files[@]} -eq 0 ]; then
        log "No supported files found in directory"
        exit 1
    fi

    # Display files in numbered list
    log "Found ${#found_files[@]} supported files:"
    for i in "${!found_files[@]}"; do
        printf "[%3d] %s\n" "$((i+1))" "${found_files[$i]}"
    done

    # File selection interface
    while true; do
        read -p "Select files (numbers comma-separated, 'all', or 'abort'): " selection
        case $selection in
            all)
                files_to_process=("${found_files[@]}")
                return 0
                ;;
            abort)
                log "Processing aborted by user"
                exit 0
                ;;
            *)
                IFS=',' read -ra nums <<< "$selection"
                valid_selection=true
                declare -a unique_numbers=()
                
                # Validate input numbers
                for num in "${nums[@]}"; do
                    num=${num//[^0-9]/}
                    [ -z "$num" ] && continue
                    
                    if (( num < 1 || num > ${#found_files[@]} )); then
                        log "Invalid number: $num"
                        valid_selection=false
                        break
                    fi
                    unique_numbers+=("$num")
                done

                $valid_selection || continue
                
                # Remove duplicates
                mapfile -t unique_numbers < <(printf "%s\n" "${unique_numbers[@]}" | sort -nu)
                
                # Populate files to process
                for num in "${unique_numbers[@]}"; do
                    files_to_process+=("${found_files[$((num-1))]}")
                done
                
                [ ${#files_to_process[@]} -gt 0 ] && return 0
                log "No valid files selected"
                ;;
        esac
    done
}

# File processing function
process_file() {
    local input_file="$1"
    local start_bitrate="$2"
    local min_decrement="$3"
    local file_ext="${input_file##*.}"
    local output_dir="encoded_outputs"
    local created_files=()
    local attempted_bitrates=()  # Track attempted bitrates

    mkdir -p "$output_dir"

    # Determine original max bitrate (using ffprobe and fallback if necessary)
    local original_maxrate
    original_maxrate=$(ffprobe -v error -select_streams v:0 \
        -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 "$input_file")
    if [ -z "$original_maxrate" ] || [ "$original_maxrate" = "N/A" ]; then
        local duration filesize
        duration=$(ffprobe -v error -select_streams v:0 \
            -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 "$input_file")
        filesize=$(stat -c %s "$input_file")
        original_maxrate=$((filesize / duration / 1000))
    else
        original_maxrate=$((original_maxrate / 1000))
    fi

    # Compute recommended bitrate and use it as default if none was provided
    local recommended_bitrate
    recommended_bitrate=$(echo "scale=0; ($original_maxrate * 0.8 + 0.5) / 1" | bc)
    start_bitrate=${start_bitrate:-$recommended_bitrate}

    # Retrieve video framerate and compute GOP size
    local framerate framerate_rounded gop_size
    framerate=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$input_file")
    framerate=$(echo "scale=2; $framerate" | bc)
    framerate_rounded=$(echo "scale=0; ($framerate + 0.5) / 1" | bc)
    gop_size=$(echo "scale=0; $framerate_rounded / 2" | bc)
    (( gop_size < 1 )) && gop_size=1

    local best_bitrate=$start_bitrate
    local best_file=""   # Track the file with the best bitrate that passed quality check
    local prev_ssim=1.0
    local decrement_step=$min_decrement
    local last_failed_bitrate=0  # 0 means no failure recorded yet
    local previous_file=""

    log "Processing file: $input_file"
    log "Using start bitrate: ${start_bitrate}k, min decrement: ${min_decrement}k"

    while [ "$start_bitrate" -gt 0 ]; do
        # Check if current bitrate has already been attempted
        while [[ " ${attempted_bitrates[*]} " =~ " $start_bitrate " && "$start_bitrate" -gt 0 ]]; do
            log "Bitrate ${start_bitrate}k already attempted. Decrementing by ${min_decrement}k."
            start_bitrate=$((start_bitrate - min_decrement))
        done

        if [ "$start_bitrate" -le 0 ]; then
            log "No more bitrates to attempt."
            break
        fi

        attempted_bitrates+=("$start_bitrate")  # Record the attempt

        local maxrate bufsize output_file candidate_bitrate
        maxrate=$((start_bitrate * 2))
        bufsize=$maxrate
        output_file="${output_dir}/$(basename "$input_file" .${file_ext}) [h264_nvenc ${start_bitrate}k].${file_ext}"
        created_files+=("$output_file")

        log "Encoding with bitrate: ${start_bitrate}k..."
        # Add -y to overwrite without prompt
        ffmpeg -y -hwaccel cuda -i "$input_file" -map 0 -map_metadata 0 \
            -c:v h264_nvenc -pix_fmt yuv420p -bf 2 -g "$gop_size" -coder 1 \
            -movflags +faststart -preset slow -b:v "${start_bitrate}k" -maxrate "${maxrate}k" \
            -bufsize "${bufsize}k" -c:a copy -c:s copy "$output_file"

        # Calculate SSIM
        local ssim_value
        ssim_value=$(ffmpeg -i "$input_file" -i "$output_file" -filter_complex ssim -f null - 2>&1 | \
                     grep "All:" | sed -E 's/.*All:([0-9.]+).*/\1/')
        log "SSIM for ${start_bitrate}k: $ssim_value"

        # If quality is below threshold, record the failure and decide how to proceed
        if (( $(echo "$ssim_value < 0.99" | bc -l) )); then
            if [ "$last_failed_bitrate" -eq 0 ]; then
                last_failed_bitrate=$start_bitrate
            fi
            if [ "$decrement_step" -gt "$min_decrement" ]; then
                log "Quality deteriorated at ${start_bitrate}k with dynamic step ($decrement_step) > min_decrement."
                log "Reverting to last known good bitrate (${best_bitrate}k) and using fixed decrement."
                start_bitrate=$((best_bitrate - min_decrement))
                decrement_step=$min_decrement
                continue
            else
                log "Quality deteriorated at ${start_bitrate}k with fixed decrement. Stopping search."
                break
            fi
        fi

        # Update the best known bitrate and file (current bitrate passed quality check)
        best_bitrate=$start_bitrate
        best_file="$output_file"

        # Delete the previous intermediate file if it exists and is not the best file
        if [ -n "$previous_file" ] && [ -f "$previous_file" ] && [ "$previous_file" != "$best_file" ]; then
            log "Deleting intermediate file: $previous_file"
            rm "$previous_file"
        fi
        previous_file="$output_file"

        # Calculate dynamic decrement based on SSIM improvement
        local ssim_change ssim_target_diff decrement_factor candidate_dynamic_step
        ssim_change=$(echo "scale=6; $prev_ssim - $ssim_value" | bc)
        ssim_target_diff=$(echo "scale=6; $ssim_value - 0.99" | bc)

        if (( $(echo "$ssim_change == 0" | bc -l) )); then
            candidate_dynamic_step=$min_decrement
        else
            decrement_factor=$(echo "scale=6; $ssim_target_diff / $ssim_change" | bc)
            candidate_dynamic_step=$(echo "$decrement_factor * $min_decrement" | bc | awk '{printf "%d", $0}')
            local max_decrement=$((min_decrement * 10))
            if [ "$candidate_dynamic_step" -gt "$max_decrement" ]; then
                candidate_dynamic_step=$max_decrement
            fi
            if [ "$candidate_dynamic_step" -lt "$min_decrement" ]; then
                candidate_dynamic_step=$min_decrement
            fi
        fi

        candidate_bitrate=$((start_bitrate - candidate_dynamic_step))
        if [ "$last_failed_bitrate" -ne 0 ] && [ "$candidate_bitrate" -le "$last_failed_bitrate" ]; then
            log "Dynamic step would drop bitrate to ${candidate_bitrate}k, which is below the failed value (${last_failed_bitrate}k)."
            decrement_step=$min_decrement
        else
            decrement_step=$candidate_dynamic_step
        fi

        prev_ssim=$ssim_value
        start_bitrate=$((start_bitrate - decrement_step))
    done

    log "Best bitrate for $input_file: ${best_bitrate}k"

    # Final cleanup: delete all intermediate files except the best output
    for file in "${created_files[@]}"; do
        if [ "$file" != "$best_file" ] && [ -f "$file" ]; then
            log "Deleting intermediate file: $file"
            rm "$file"
        fi
    done
}

# Main execution logic
if $directory_mode; then
    # Directory processing mode
    [ ! -d "$input_path" ] && log "Error: Directory does not exist" && exit 1
    process_directory "$input_path"

    # Process selected files with default values
    for file in "${files_to_process[@]}"; do
        process_file "$file" "" "$default_min_decrement"
    done
else
    # Single file mode
    [ ! -f "$input_path" ] && log "Error: File does not exist" && exit 1
    file_ext="${input_path##*.}"
    
    # Validate extension
    if [[ ! " ${valid_exts[@]} " =~ " ${file_ext,,} " ]]; then
        log "Error: Unsupported file format. Only MKV, MP4, and MOV are allowed."
        exit 1
    fi

    # Original single file processing logic
    # [Keep original interactive input handling here]
    # Then call process_file with collected parameters
    # [Rest of original single file handling]
fi

log "All processing complete!"
