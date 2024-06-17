#!/bin/bash
#
# d-scripts / d-plex-convert
#
# A script to convert video files to WebM or MP4 format using FFmpeg. The script analyzes the input video files and determines the optimal settings for the
# output format based on the resolution, frame rate, video codec, and other factors.

# Enable debugging and trace output
# set -x

# Function to check for the presence of required dependencies
#
# The script requires bc for floating-point arithmetic, bc is usually installed by default on most systems, however, WSL (Windows Subsystem for Linux) may
# require manual installation of bc.
#
# The script uses ffmpeg for video conversion and ffprobe which is part of the ffmpeg package for video analysis. mediainfo is used when ffprobe is unable to
# provide the required information.
#
# The script will offer to install the missing applications on Ubuntu if they are not found. For other systems, the user will be prompted to install the
# missing applications manually.
check_required_apps() {
	local missing_apps=()
	for app in bc ffmpeg mediainfo vainfo; do
		if ! command -v "$app" &> /dev/null; then
			missing_apps+=("$app")
			fi
		done
		
		if [ ${#missing_apps[@]} -gt 0 ]; then
			echo "Missing required applications: ${missing_apps[*]}"
			if [[ "$OSTYPE" == "linux-gnu"* ]] && grep -qi ubuntu /etc/os-release; then
				read -r -p "Would you like to install them now? [Y/n] " response
				if [[ $response =~ ^[Yy]?$ ]]; then
					sudo apt update && sudo apt install -y "${missing_apps[@]}"
				else
					echo "Please install the missing applications and rerun the script."
					exit 1
				fi
			else
				echo "Please install the missing applications and rerun the script."
				exit 1
			fi
		fi
}

# Check for required dependencies
check_required_apps

# Function to print script usage
print_usage() {
	echo "Usage: $0 <directory> <file_extension> <container_format> <audio_streams_count> <languages> <subtitles> <hardware_acceleration> [-y]"
	echo "<container_format> can be 'webm' or 'mp4'."
	echo "<subtitles> can be 'enabled' or 'disabled'."
	echo "<hardware_acceleration> can be 'none', 'vaapi', 'cuda', 'qsv', 'amf'."
	echo "Use '-y' to automatically confirm all prompts. This will overwrite existing files without confirmation!"
	echo "Example: $0 . mkv webm 1 eng disabled -y"
}

# Function to check if the correct number of arguments are provided
check_number_of_arguments() {
	if [ $# -lt 7 ] || [ $# -gt 8 ]; then
		echo "Error: Incorrect number of arguments."
		print_usage
		exit 1
	fi
}

# Check if the correct number of arguments are provided
check_number_of_arguments "$@"

# Function to validate the input arguments
validate_arguments() {
	directory="$1"
	if [ ! -d "$directory" ]; then
		echo "Error: Directory '$directory' not found."
		exit 1
	fi

	file_extension="$2"
	if [[ ! "$file_extension" =~ ^(mkv|mp4|avi|mov|flv|wmv|webm|ts)$ ]]; then
		echo "Error: Invalid file extension. Supported extensions: mkv, mp4, avi, mov, flv, wmv, webm, ts."
		exit 1
	fi

	container_format="$3"
	if [[ ! "$container_format" =~ ^(webm|mp4)$ ]]; then
		echo "Error: Invalid container format. Supported formats: webm, mp4."
		exit 1
	fi

	audio_streams_count="$4"
	if ! [[ "$audio_streams_count" =~ ^[0-9]+$ ]]; then
		echo "Error: Invalid audio streams count. Please provide a positive integer."
		exit 1
	fi

	languages="$5"
	if [[ ! "$languages" =~ ^[a-zA-Z,]+$ ]]; then
		echo "Error: Invalid language format. Please provide a comma-separated list of languages."
		exit 1
	fi

	subtitles="$6"
	if [[ ! "$subtitles" =~ ^(enabled|disabled)$ ]]; then
		echo "Error: Invalid subtitle option. Please use 'enabled' or 'disabled'."
		exit 1
	fi

	hardware_acceleration="$7"
	if [[ ! "$hardware_acceleration" =~ ^(none|vaapi|cuda|qsv|amf)$ ]]; then
		echo "Error: Invalid hardware acceleration option. Please use 'none', 'vaapi', 'cuda', 'qsv', or 'amf'."
		exit 1
	fi

	if [[ "$hardware_acceleration" == "none" ]]; then
		echo "Hardware acceleration is disabled by user." > /dev/null
	elif [[ "$hardware_acceleration" == "vaapi" ]]; then
		if [[ "$container_format" != "mp4" ]]; then
			echo "VAAPI hardware acceleration is only supported for MP4 container format."
			exit 1
		elif ! vainfo &> /dev/null; then
			echo "Error: VAAPI device not found. Please ensure that the device is available."
			exit 1
			fi
			echo "Hardware acceleration is set to VAAPI." > /dev/null
		elif [[ "$hardware_acceleration" == "cuda" ]]; then
			echo "Hardware acceleration is set to CUDA."
			echo "CUDA is not supported at the moment."
			exit 1
		elif [[ "$hardware_acceleration" == "qsv" ]]; then
			echo "Hardware acceleration is set to QSV."
			echo "QSV is not supported at the moment."
			exit 1
		elif [[ "$hardware_acceleration" == "amf" ]]; then
			echo "Hardware acceleration is set to AMF."
			echo "AMF is not supported at the moment."
	fi

	auto_confirm="n"
	if [ $# -eq 8 ] && [ "$8" == "-y" ]; then
		auto_confirm="y"
	fi
}
validate_arguments "$@"

# Function to get terminal width
get_terminal_width() {
	stty size | cut -d ' ' -f2
}

# Function to draw the progress bar with time information
draw_progress_bar() {
	local current_time=$1  # Current progress time in milliseconds
	local duration=$2  # Total duration in milliseconds
	local start_time=$3  # Start time of the process

	local now
	now=$(date +%s)
	local elapsed_time=$((now - start_time))
	local progress
	progress=$(echo "scale=2; $current_time * 100 / $duration" | bc | xargs printf "%.2f")
	local width
	width=$(get_terminal_width)
	local padding=49 # Padding for time information and brackets
	local bar_width=$((width - padding)) # Adjust width for time information and brackets
	local completed
	completed=$(echo "$progress * $bar_width / 100" | bc | xargs printf "%.0f")

	printf "\r["  # Move the cursor to the beginning of the line
	for ((i=0; i<completed; i++)); do printf "="; done
	for ((i=completed; i<bar_width; i++)); do printf " "; done

	# Avoid division by zero
	local progress_nonzero
	progress_nonzero=$(echo "$progress + 0.0001" | bc | xargs printf "%.4f")
	local estimated_time
	estimated_time=$(echo "$elapsed_time * 100 / $progress_nonzero" | bc | xargs printf "%.0f")
	local remaining_time=$((estimated_time - elapsed_time))

	# Print the progress bar and time information
	printf "] %.2f%% | %02dh:%02dm:%02ds elapsed, %02dh:%02dm:%02ds left" "$progress" $((elapsed_time/3600)) $((elapsed_time%3600/60)) $((elapsed_time%60)) $((remaining_time/3600)) $((remaining_time%3600/60)) $((remaining_time%60))
}

# Handler for terminal resize
handle_resize() {
	if [ -n "$current_time" ] && [ -n "$duration" ]; then
		draw_progress_bar "$current_time" "$duration" "$start_time"
	fi
}

# Trap SIGWINCH signal
trap 'handle_resize' SIGWINCH

# Global variable to store FFmpeg PID
ffmpeg_pid=0

# Cleanup function to remove the progress file and kill FFmpeg
cleanup() {
	echo -e "\nInterrupted. Cleaning up..."

	# Check if FFmpeg process is running and kill it
	if [ $ffmpeg_pid -ne 0 ]; then
		kill $ffmpeg_pid 2>/dev/null
	fi

	# Remove progress file
	if [ -f "$progress_file" ]; then
		rm -f "$progress_file"
	fi

	# Remove the output file
	remove_output_file

	echo "Cleanup done. Exiting."
	exit 1  # Exit with an error status
}

remove_output_file() {
	if [ -f "$output_file" ]; then
		if [ ! -s "$output_file" ]; then
			echo "Removing empty output file: $output_file"
			rm -f "$output_file"
		else
			echo "Not removing non-empty output file: $(du -h "$output_file" | cut -f1)"
		fi
	else
			echo "Output file not found: $output_file"
	fi
}

# Trap SIGINT signal (Ctrl+C)
trap 'cleanup' SIGINT

# Function to determine the closest matching resolution and frame rate
get_bitrate_recommended() {
	local height=$1
	local frame_rate=$2
	
	# Define an associative array for resolution and bitrate cap
	declare -A resolution_bitrate_recommended=(
		[4320]="160000 240000"
		[2160]="45000 68000"
		[1440]="16000 24000"
		[1080]="8000 12000"
		[720]="5000 7500"
		[480]="2500 4000"
		[360]="1000 1500"
	)
	
	# Determine the closest resolution height from the table
	local closest_height=4320  # Start with the highest resolution
	for res in "${!resolution_bitrate_recommended[@]}"; do
		if [ "$height" -le "$res" ] && [ $((res - height)) -lt $((closest_height - height)) ]; then
			closest_height=$res
		fi
	done

	# Determine if the frame rate is higher than 30 fps (30.9 fps threshold)
	local rate_index=0  # Index 0 for <=30, Index 1 for >3
	if (( $(echo "$frame_rate > 30.9" | bc -l) )); then
		rate_index=1
	fi
	
	# Extract the bitrate cap based on the closest resolution and frame rate index
	read -r -a caps <<< "${resolution_bitrate_recommended[$closest_height]}"
	local bitrate_recommended=${caps[$rate_index]}
	
	echo "$bitrate_recommended"
}

# Estimate the closest QP value based on the bitrate cap
get_qp_from_video_bitrate() {
	local input_file_sampling="$1"
	local target_bitrate="$2"
	local closest_qp=21  # Start from a common value
	local step=1  # Initial step for adjusting QP
	local last_diff=999999999  # Start with a large number for comparison
	local direction  # This will store the direction of QP change
	declare -a qp_register=()  # Register to store the QP values tested
	local sample_parts=0  # Number of sample parts generated
	local cummulative_bitrate=0  # Cumulative bitrate for all sample parts
	local sample_length
	
	for ((i=0; i<10; i++)); do
		local sample_file=".$(basename -s .$file_extension "$input_file_sampling")_sample_qp${closest_qp}"
		local duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$input_file_sampling" | awk '{print int($1)}')

		# Determine the sample length based on the duration
		if [ $duration -gt 180 ]; then
			sample_length=180
		else
			# If the duration is less than 180 seconds, sample half of the video to the closest integer
			sample_length=$(printf "%.0f" $(echo "$duration / 2" | bc -l)) #TODO: Use this method to return the closest integer for other cases in this function.
		fi

		# Populate the QP register with the current QP value
		qp_register+=("$closest_qp")

		# Start a loop for until the end of the video file duration
		for ((j=0; j<duration; j+=$(echo "$sample_length * 2 " | bc -l))); do
			# Generate a sample part with the current QP value
			local ffmpeg_cmd="ffmpeg -vaapi_device /dev/dri/renderD128 -ss '$j' -i '$input_file_sampling' -t '$sample_length' -vf 'format=nv12,hwupload' -c:v 'h264_vaapi' -qp '$closest_qp' -an '${sample_file}_part${j}.mp4'"
			eval "$ffmpeg_cmd" > /dev/null 2>&1
			wait $!

			# Proceed only if the sample file was generated correctly
			if [ -f "${sample_file}_part${j}.mp4" ] && [ -s "${sample_file}_part${j}.mp4" ]; then
				local current_bitrate=$(mediainfo --Output="Video;%BitRate%" "${sample_file}_part${j}.mp4" | awk '{print $1/1000}')

				# Create an array to store the bitrate values
				declare -a bitrates=()
				bitrates+=("$current_bitrate")

				# Increment the sample parts counter
				local sample_parts=$(echo "$sample_parts + 1" | bc -l)

				# Cleanup the sample part file after each iteration if it exists
				if [ -f "${sample_file}_part${j}.mp4" ]; then
					rm -f "${sample_file}_part${j}.mp4"
				fi
			else
				sample_parts=$(echo "$sample_parts - 1" | bc -l)
			fi

			# Calculate the sample average bitrate but check if the sample parts are more than 0
			if [ $sample_parts -lt 1 ]; then
				echo "Error: No sample parts generated for QP: $closest_qp." >> /dev/stderr
				#TODO: Add a fallback mechanism to handle this case by evaluating the output of this function. This function should return integer numbers from
				#18 to 28. Any other output should be considered an error.
			fi
		done

		# Calculate the median bitrate for the sample parts
		local median_bitrate=$(echo "${bitrates[@]}" | tr ' ' '\n' | sort -n | awk '{a[NR]=$1}END{print (NR%2==1)?a[(NR+1)/2]:(a[NR/2]+a[NR/2+1])/2}')

		# Calculate the difference between the target bitrate and the average bitrate
		local diff=$(echo "$target_bitrate - $median_bitrate" | bc -l)
		diff=${diff#-}  # Absolute value of the difference

		# Determine the direction of the change based on whether the bitrate is greater than the target
		if [[ $(echo "$median_bitrate > $target_bitrate" | bc -l) -eq 1 ]]; then
			direction=1  # Need to decrease bitrate, increase QP
		else
			direction=-1   # Need to increase bitrate, decrease QP
		fi

		# Update closest_qp
		closest_qp=$((closest_qp + direction * step))

		# If the QP exists in the register, set QP to the value with the smallest difference
		if [[ " ${qp_register[@]} " =~ " ${closest_qp} " ]]; then
			if [ $(echo "$diff > $last_diff" | bc -l) -eq 1 ]; then
				echo $closest_qp
				exit 0
			else
				echo $(($closest_qp - direction * step))
				exit 0
			fi
		fi

		# Check if the qp value is within the acceptable range (18-28) and if the limit has been reached. Set the QP to the closest value and exit.
		if [ $closest_qp -lt 18 ]; then
			echo 18
			exit 0
		elif [ $closest_qp -gt 28 ]; then
			echo 28
			exit 0
		fi

		# Update the last difference
		last_diff=$diff
		
	done

	# Chcek if closest_qp is populated
	if [ -z "$closest_qp" ]; then
		echo "Error: Unable to determine the closest QP value." >> /dev/stderr
	fi
	
	echo $closest_qp
}

# Function to generate the filename for the output file
generate_output_filename() {
	local input_file="$1"
	local filename
	filename=$(basename -- "$input_file")
	local filename_without_extension="${filename%.*}"
	local output_file
	
	# Determine the output file based on the container format
	if [[ "$container_format" == "webm" ]]; then
		output_file="${directory}/${filename_without_extension}.webm"
	elif [[ "$container_format" == "mp4" ]]; then
		output_file="${directory}/${filename_without_extension}.mp4"
	fi

	# Check if the output file is the same as the input file and add a suffix if needed
	if [ "$output_file" == "$input_file" ]; then
		output_file="${directory}/${filename_without_extension}_converted.${container_format}"
	fi

	echo "$output_file"
}

# Function to get the input file framerate using ffprobe
get_frame_rate_using_ffprobe() {
	local input_file="$1"
	local frame_rate_raw
	frame_rate_raw=$(ffprobe -v error -of csv=p=0 -select_streams v:0 -show_entries stream=r_frame_rate "$input_file")
	local frame_rate
	frame_rate=$(echo "$frame_rate_raw" | awk -F'/' '{ if ($2 > 0) print $1 / $2; else print 0; }')
	
	echo "$frame_rate"
}

# Function to get the input file framerate using mediainfo
get_frame_rate_using_mediainfo() {
	local input_file="$1"
	local frame_rate
	frame_rate=$(mediainfo --Inform="Video;%FrameRate%" "$input_file")
	
	echo "$frame_rate"
}

# Function to determine the GOP size based on the frame rate. Closed GOP. GOP of half the frame rate
get_gop_size() {
	local frame_rate="$1"
	local gop_size
	gop_size=$(echo "scale=0; $frame_rate / 2" | bc | xargs printf "%.0f")
	
	echo "$gop_size"
}

# Function to get the resolution height of the video
get_resolution_height() {
	local input_file="$1"
	local height
	height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$input_file")
	
	echo "$height"
}

# Function to get the video codec using mediainfo
get_video_codec() {
	local input_file="$1"
	local video_codec
	video_codec=$(mediainfo --Inform="Video;%Format%" "$input_file")
	
	echo "$video_codec"
}

# Function to get the video bitrate using mediainfo
get_video_bitrate() {
	local input_file="$1"
	local video_bitrate
	video_bitrate=$(mediainfo --Inform="Video;%BitRate%" "$input_file")
	
	echo "$video_bitrate"
}

# Function to get the video bitrate using mediainfo in an alternate way
get_video_bitrate_alternate() {
	local input_file="$1"
	local video_bitrate
	video_bitrate=$(mediainfo -f "$input_file" | grep -oP 'bitrate=\K\d+')
	
	echo "$video_bitrate"
}

# Function to get the overall bitrate using mediainfo
get_overall_bitrate() {
	local input_file="$1"
	local overall_bitrate
	overall_bitrate=$(mediainfo --Inform="General;%BitRate%" "$input_file")
	
	echo "$overall_bitrate"
}

# Function to modify the video bitrate based on the video codec and container format
modify_video_bitrate() {
	local video_bitrate="$1"
	local video_codec="$2"
	local container_format="$3"
	
	if [[ "$container_format" == "webm" ]]; then
		if [[ "$video_codec" =~ HEVC|hevc ]]; then
			video_bitrate=$(echo "$video_bitrate * 1.1" | bc | xargs printf "%.0f")
		elif [[ "$video_codec" =~ AVC|h264 ]]; then
			video_bitrate=$(echo "$video_bitrate * 0.8" | bc | xargs printf "%.0f")
		elif [[ "$video_codec" =~ VP9|vp9 ]]; then
			video_bitrate=$(echo "$video_bitrate * 1" | bc | xargs printf "%.0f")  # No change needed, but included for clarity
		fi
	elif [[ "$container_format" == "mp4" ]]; then
		if [[ "$video_codec" =~ HEVC|hevc ]]; then
			video_bitrate=$(echo "$video_bitrate * 1.3" | bc | xargs printf "%.0f")
		elif [[ "$video_codec" =~ VP9|vp9 ]]; then
			video_bitrate=$(echo "$video_bitrate * 1.2" | bc | xargs printf "%.0f")
		elif [[ "$video_codec" =~ AVC|h264 ]]; then
			video_bitrate=$(echo "$video_bitrate * 1" | bc | xargs printf "%.0f")  # No change needed, but included for clarity
		fi
	else
		echo "Unsupported container format: $container_format. Exiting..."
		exit 1
	fi
	
	echo "$video_bitrate"
}

# Function to check modified bitrate against recommended bitrate and return the final bitrate
check_bitrate_against_recommended() {
	local video_bitrate="$1"
	local bitrate_recommended="$2"
	
	# after determining the modified bitrate, check against recommended bitrate
	bitrate_recommended=$(get_bitrate_recommended "$height" "$frame_rate")
	if [[ "$video_bitrate" -gt "$bitrate_recommended" ]]; then
		if [ "$auto_confirm" == "y" ]; then
			video_bitrate=$bitrate_recommended
		else
			while true; do
				read -r -p "Enter a new bitrate or type 'skip' to skip this file (input: $video_bitrate_input target: $video_bitrate | recommended: $bitrate_recommended): " user_input
				if [[ "$user_input" =~ ^[ss]kip$ ]]; then
					echo "Skipping file: $input_file"
					continue 2 # skip to the next file in the outer loop
				elif [[ "$user_input" =~ ^[0-9]+$ ]] && (( user_input > 0 )); then
					video_bitrate=$user_input
					break # break out of the while loop; valid input provided
				else
					echo "Invalid input. please enter a positive bitrate value or type 'skip' to skip."
				fi
			done
		fi
	fi

	echo "$video_bitrate"
}

# Process each video file
process_files() {
	# Find and iterate over files here
	local input_files=()
	while IFS= read -r -d '' file; do
		input_files+=("$file")
	# find by extension, but exclude files that end with the suffix _converted.$file_extension to avoid re-converting files
	done < <(find "$directory" -type f -name "*.$file_extension" ! -name "*_converted.$file_extension" -print0)
	
	if [ ${#input_files[@]} -eq 0 ]; then
		echo "Error: No '$file_extension' files found in directory '$directory'."
		exit 1
	fi
	
	for input_file in "${input_files[@]}"; do
		# Determine the output file name
		output_file=$(generate_output_filename "$input_file")
		echo "Input file: $input_file"
		echo "Output file: $output_file"
		
		# Attempt to get frame rate using ffprobe
		local frame_rate
		frame_rate=$(get_frame_rate_using_ffprobe "$input_file")
		
		# Check if frame rate is within an acceptable range
		if (( $(echo "$frame_rate <= 0 || $frame_rate > 60.9" | bc -l) )); then
			echo "Warning: Frame rate from ffprobe is out of bounds: $frame_rate. Attempting to get frame rate using mediainfo..."
			
			# Attempt to get frame rate using mediainfo
			local frame_rate_media_info
			frame_rate_media_info=$(get_frame_rate_using_mediainfo "$input_file")
			
			# Validate frame rate from mediainfo
			if (( $(echo "$frame_rate_media_info > 0 && $frame_rate_media_info <= 60.9" | bc -l) )); then
				frame_rate=$frame_rate_media_info
				echo "Frame rate from mediainfo seems valid: $frame_rate"
			else
				echo "Warning: Unable to obtain a valid frame rate for $input_file. Frame rate from mediainfo: $frame_rate_media_info"
				
				if [ "$auto_confirm" == "y" ]; then
					echo "Auto-confirm is enabled. Skipping file: $input_file"
					continue # Skip this file due to -y flag
				else
					# Prompt user to enter a valid frame rate
					read -r -p "Please enter a valid frame rate for this file or press Enter to skip: " user_frame_rate
					if [[ -n "$user_frame_rate" ]] && (( $(echo "$user_frame_rate > 0 && $user_frame_rate <= 60.9" | bc -l) )); then
						frame_rate=$user_frame_rate
						echo "Using user-provided frame rate: $frame_rate"
					else
						echo "Invalid or no frame rate entered. Skipping file: $input_file"
						continue # Skip this file due to invalid user input or no input
					fi
				fi
			fi
		fi

		# Determine the GOP size based on the frame rate. Closed GOP. GOP of half the frame rate
		local gop_size
		gop_size=$(get_gop_size "$frame_rate")

		# Determine the resolution of the video
		local height
		height=$(get_resolution_height "$input_file")

		# Determine the video codec
		local video_codec
		video_codec=$(get_video_codec "$input_file")

		# Determine the input video bitrate
		local video_bitrate_input
		video_bitrate_input=$(get_video_bitrate "$input_file")

		if [ -z "$video_bitrate_input" ]; then
			video_bitrate_input=$(get_video_bitrate_alternate "$input_file")
		else
			video_bitrate_input=$(echo "$video_bitrate_input / 1000" | bc | xargs printf "%.0f")
		fi

		# Determine the recommended bitrate based on the resolution and frame rate
		local bitrate_recommended
		bitrate_recommended=$(get_bitrate_recommended "$height" "$frame_rate")

		if [ -z "$video_bitrate_input" ]; then
			if [ "$auto_confirm" == "y" ]; then
				echo "Auto-confirm is enabled but bitrate information is not available. Using the recommended bitrate: $bitrate_recommended kbps."
				video_bitrate_input=$bitrate_recommended
			else
				overall_bitrate_input=$(get_overall_bitrate "$input_file")
				read -r -p "Unable to determine the source bitrate. Please enter the desired bitrate in kbps (input: ${height}p${frame_rate}) or type 'skip' to skip this file: " user_input
				video_bitrate_input=$(echo "$user_input" | bc | xargs printf "%.0f")
				fi
		fi

		# Determine the modified bitrate based on the video codec and container format
		local video_bitrate
		video_bitrate=$(modify_video_bitrate "$video_bitrate_input" "$video_codec" "$container_format")

		# after determining the modified bitrate, check against recommended bitrate
		video_bitrate=$(check_bitrate_against_recommended "$video_bitrate" "$bitrate_recommended")

		if [[ "$container_format" == "webm" ]]; then
			# Set ffmpeg_cmd for VP9 and WebM
			ffmpeg_cmd="ffmpeg -i '$input_file' -map 0 -map -0:a -map -0:d? -c:v libvpx-vp9 -b:v ${video_bitrate}k -maxrate $((video_bitrate*2))k -bufsize $((video_bitrate*4))k -speed 1 -tile-columns 6 -frame-parallel 1 -auto-alt-ref 1 -lag-in-frames 25 -metadata title='$(basename -s .$file_extension "$input_file")'"
			audio_codec="libopus" # TODO: libopus fails with some audio codecs, libvorbis is a good alternative. Think of a way to handle this automatically.
		elif [[ "$container_format" == "mp4" ]]; then
			if [[ "$hardware_acceleration" == "none" ]]; then
				ffmpeg_cmd="ffmpeg -i '$input_file' -map 0 -map -0:a -map -0:d? -c:v libx264 -profile:v high -level:v 4.2 -bf 2 -g $gop_size -coder 1 -movflags +faststart -b:v ${video_bitrate}k -maxrate $((video_bitrate*2))k -bufsize $((video_bitrate*4))k -pix_fmt yuv420p -preset veryslow -metadata title='$(basename -s .$file_extension "$input_file")'"
			elif [[ "$hardware_acceleration" == "vaapi" ]]; then
				# Determine the QP value based on the bitrate cap
				local qp_value
				echo "Calculating QP value based on the target bitrate: $video_bitrate kbps. Generating samples in the background. This may take several minutes..."
				qp_value=$(get_qp_from_video_bitrate "$input_file" "$video_bitrate")
				ffmpeg_cmd="ffmpeg -vaapi_device /dev/dri/renderD128 -i '$input_file' -map 0 -map -0:a -map -0:d? -vf 'format=nv12,hwupload' -c:v h264_vaapi -bf 2 -g $gop_size -coder 1 -movflags +faststart -qp '$qp_value' -metadata title='$(basename -s .$file_extension "$input_file")'"
			elif [[ "$hardware_acceleration" == "cuda" ]]; then
				echo "CUDA is not supported at the moment."
				exit 1
			elif [[ "$hardware_acceleration" == "qsv" ]]; then
				echo "QSV is not supported at the moment."
				exit 1
			elif [[ "$hardware_acceleration" == "amf" ]]; then
				echo "AMF is not supported at the moment."
				exit 1
			fi
			audio_codec="aac"
		else
			echo "Unsupported container format: $container_format. Exiting..."
			exit 1
		fi

		# Add audio and subtitle options to ffmpeg_cmd
		local IFS=' '
		read -r -a languages_array <<< "$languages"
		if [ "$audio_streams_count" -gt 0 ] && [ ${#languages_array[@]} -gt 0 ]; then
			for (( i=0; i<audio_streams_count; i++ )); do
				local language_index=$((i % ${#languages_array[@]}))
				local language="${languages_array[$language_index]}"
				ffmpeg_cmd+=" -map 0:a:$i -metadata:s:a:$i language=$language -c:a:$i $audio_codec"
			done
		fi

		if [ "$subtitles" == "enabled" ]; then
			ffmpeg_cmd+=" -c:s copy"
		elif [ "$subtitles" == "disabled" ]; then
			ffmpeg_cmd+=" -sn"
		else
			echo "Invalid subtitle option. Please use 'enabled' or 'disabled'. Exiting..."
			exit 1
		fi

		ffmpeg_cmd+=" '$output_file'"
		
		# Get the duration of the input file and validate it
		local duration
		duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$input_file")
		if [ -z "$duration" ] || (( $(echo "$duration <= 0" | bc -l) )); then
			echo "Error: Unable to determine the duration of the input file. Skipping file: $input_file"
			continue
		fi

		# Concatenate progress file path
		progress_file="${output_file}.log"
		# Add -progress option to ffmpeg_cmd
		ffmpeg_cmd+=" -progress '$progress_file'"
		
		# Handle user confirmation and execution
		execute_ffmpeg=0  # Flag to determine if FFmpeg should be executed
		if [ "$auto_confirm" == "y" ]; then
			execute_ffmpeg=1
		else
			while true; do
				echo "Ready to execute: $ffmpeg_cmd"
				read -r -p "Proceed? (y)es, (n)o, (q)uit: " choice
				case "$choice" in
					[Yy]* )
						execute_ffmpeg=1
						break;;
					[Nn]* )
						echo "Skipping file: $input_file"
						continue 2;;  # Continue to the next iteration of the outer loop (skip current file)echo "Conversion canceled by user."
					[Qq]* )
						echo "Conversion canceled by user."
						exit 1;;
					* )
						echo "Please answer yes, no, or quit.";;
				esac
			done
		fi

		# Execute FFmpeg command if confirmed
		if [ "$execute_ffmpeg" -eq 1 ]; then

			# Check if the output file already exists
			# If it does, prompt the user to overwrite or skip
			# If auto-confirm is enabled, overwrite the file
			# If the user chooses to skip, continue to the next file
			if [ -f "$output_file" ]; then
				if [ "$auto_confirm" == "y" ]; then
					echo "Auto-confirm is enabled. Overwriting existing file."
					rm -f "$output_file"
				else
					# Calculate the size of the output file in KiB, MiB, and GiB
					local output_file_size_kib
					output_file_size_kib=$(du -k "$output_file" | cut -f1)
					local output_file_size_mib
					output_file_size_mib=$(echo "scale=2; $output_file_size_kib / 1024" | bc)
					local output_file_size_gib
					output_file_size_gib=$(echo "scale=2; $output_file_size_mib / 1024" | bc)
					while true; do
						read -r -p "${output_file} already exists ($output_file_size_kib KiB, $output_file_size_mib MiB, $output_file_size_gib GiB). Overwrite? [Y/n] " choice
						case "$choice" in
							[Yy]* )
								echo "Overwriting existing file."
								rm -f "$output_file"
								break;;
							[Nn]* )
								echo "Skipping file: $input_file"
								continue 2;;  # Continue to the next iteration of the outer loop (skip current file)
							* )
								echo "Please answer yes or no.";;
						esac
					done
				fi
			fi

			# Create a conversion log file
			local log_file="${directory}/._conversion.log"

			# Append input and output file information to the log file
			echo "Input file: $input_file" >> "$log_file"
			echo "Output file: $output_file" >> "$log_file"

			# Append ffmpeg_cmd to the log file
			echo "Conversion command: $ffmpeg_cmd" >> "$log_file"

			# Start ffmpeg and redirect tts output to the log file
			eval "$ffmpeg_cmd > /dev/null 2>&1 &"
			ffmpeg_pid=$!

			# Capture the start time for the progress bar
			start_time=$(date +%s)

			# Calculate duration in nanoseconds for the progress bar
			duration=$(echo "$duration * 1000000" | bc | xargs printf "%.0f")

			echo "Starting encoding..."
			while kill -0 $ffmpeg_pid 2>/dev/null; do
				if [ -f "$progress_file" ]; then
					# Extract progress information
					current_time=$(grep -a -oP '^out_time_ms=\K\d+' "$progress_file" | tail -1)

					# Check if the current time is not empty and greater than zero
					if [[ -n "$current_time" ]] && (( current_time > 0 )); then
						draw_progress_bar "$current_time" "$duration" "$start_time"
					fi
				fi
				sleep 1
			done

			# Check the exit status of FFmpeg
			wait $ffmpeg_pid
			ffmpeg_exit_status=$?

			if [ $ffmpeg_exit_status -eq 0 ]; then
				echo -e "\nEncoding completed successfully: $output_file"
				# Print the output file bitrate in kbps
				local video_bitrate_output
				video_bitrate_output=$(mediainfo --Inform="Video;%BitRate%" "$output_file" | awk '{print $1/1000}') # Convert to kbps
				echo "Input file codec and bitrate:  $video_codec at $video_bitrate_input kbps" | tee -a "$log_file"
				echo "Output file codec and bitrate: $(get_video_codec "$output_file") at $video_bitrate_output kbps" | tee -a "$log_file"
				# Compare the input and output file bitrates and return a percentage difference
				local bitrate_difference
				bitrate_difference=$(echo "scale=2; ($video_bitrate_output - $video_bitrate_input) * 100 / $video_bitrate_input" | bc)
				echo "Bitrate difference: $bitrate_difference%" | tee -a "$log_file"
				echo "" | tee -a "$log_file"
			else
				echo -e "\nError: FFmpeg exited with status $ffmpeg_exit_status." | tee -a "$log_file"
				echo "" | tee -a "$log_file"	
				# Remove output file
				remove_output_file
			fi

			echo  # Print a newline after completion
			# Clean up the progress file
			rm -f "$progress_file"
			
		fi
		
	done
}
process_files

