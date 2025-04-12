import os
import subprocess
import argparse
import json

# Constants
QUALITY_PROFILE = "1Mbps"
VIDEO_BITRATE = 1000
GOP_SIZE_FACTOR = 0.5  # GOP_SIZE is half the framerate
TARGET_HORIZONTAL_RES = 854
TARGET_VERTICAL_RES = 480

# Function to check if a file is a video
def is_video_file(filename):
    return any(filename.endswith(ext) for ext in ['.mp4', '.mkv', '.webm', '.avi'])

# Function to get video information using mediainfo
def get_video_info(input_file):
    try:
        result = subprocess.run(
            ['mediainfo', '--Output=JSON', input_file],
            capture_output=True,
            text=True,
            check=True
        )
        info = json.loads(result.stdout)
        video_track = next(track for track in info['media']['track'] if track['@type'] == 'Video')
        framerate = float(video_track.get('FrameRate', 0))
        bitrate = int(video_track.get('BitRate', 0)) / 1000  # Convert bitrate to kbps
        width = int(video_track.get('Width', 0))
        height = int(video_track.get('Height', 0))
        return framerate, bitrate, width, height
    except Exception as e:
        print(f"Error getting video info for {input_file}: {e}")
        return None, None, None, None

# Function to calculate the new resolution maintaining the aspect ratio
def calculate_new_resolution(width, height):
    # Try setting horizontal resolution to 854px first
    new_width = TARGET_HORIZONTAL_RES
    new_height = int(height * (TARGET_HORIZONTAL_RES / width))

    # If the calculated vertical resolution is greater than 480px
    if new_height > TARGET_VERTICAL_RES:
        # Adjust to the vertical resolution of 480px
        new_height = TARGET_VERTICAL_RES
        new_width = int(width * (TARGET_VERTICAL_RES / height))
    
    return new_width, new_height

# Function to create the "Custom Versions/1Mbps" folder if it doesn't exist
def ensure_custom_versions_folder(movie_folder_path):
    custom_versions_path = os.path.join(movie_folder_path, "Custom Versions")
    if not os.path.exists(custom_versions_path):
        os.makedirs(custom_versions_path)
    quality_profile_path = os.path.join(custom_versions_path, QUALITY_PROFILE)
    if not os.path.exists(quality_profile_path):
        os.makedirs(quality_profile_path)

# Function to process and convert video files
def process_videos(movie_folder_path):
    custom_versions_path = os.path.join(movie_folder_path, "Custom Versions", QUALITY_PROFILE)

    # Ensure the custom versions path exists
    if not os.path.exists(custom_versions_path):
        os.makedirs(custom_versions_path)

    for root, dirs, files in os.walk(movie_folder_path):
        if "Custom Versions" in root:
            continue
        for file in files:
            if is_video_file(file):
                input_file = os.path.join(root, file)
                output_file = os.path.join(custom_versions_path, file)
                
                # Skip if the file already exists in the target folder
                if os.path.exists(output_file):
                    continue

                # Get video information
                framerate, original_bitrate, width, height = get_video_info(input_file)

                # Skip if unable to get information or if bitrate is lower than 1Mbps
                if framerate is None or original_bitrate is None or original_bitrate < VIDEO_BITRATE:
                    print(f"Skipping {input_file}: bitrate is less than {VIDEO_BITRATE}kbps")
                    continue

                # Calculate GOP_SIZE
                gop_size = int(framerate * GOP_SIZE_FACTOR)

                # Calculate new resolution
                new_width, new_height = calculate_new_resolution(width, height)

                # Build the ffmpeg command
                ffmpeg_command = [
                    'ffmpeg', 
                    '-i', input_file, 
                    '-map', '0', 
                    '-map', '-0:a', 
                    '-map', '-0:d?', 
                    '-c:v', 'h264_nvenc', 
                    '-bf', '2', 
                    '-g', str(gop_size), 
                    '-coder', '1', 
                    '-movflags', '+faststart', 
                    '-b:v', f'{VIDEO_BITRATE}k', 
                    '-maxrate', f'{VIDEO_BITRATE*2}k', 
                    '-bufsize', f'{VIDEO_BITRATE*4}k', 
                    '-pix_fmt', 'yuv420p', 
                    '-preset', 'slow', 
                    '-metadata', f'title={os.path.splitext(file)[0]}', 
                    '-vf', f'scale={new_width}:{new_height}', 
                    output_file
                ]

                # Run the ffmpeg command
                subprocess.run(ffmpeg_command, check=True)

# Function to handle the argument parsing
def parse_arguments():
    parser = argparse.ArgumentParser(description="Process Plex movie library and create custom video versions.")
    parser.add_argument(
        "plex_library_path",
        type=str,
        help="The path to the Plex Movie Library"
    )
    return parser.parse_args()

# Main function
def main():
    args = parse_arguments()

    # Expand user directory if path contains '~'
    plex_library_path = os.path.expanduser(args.plex_library_path)

    # Ensure the provided path exists
    if not os.path.exists(plex_library_path):
        print("Error: The provided path does not exist.")
        return

    for movie_folder in os.listdir(plex_library_path):
        movie_folder_path = os.path.join(plex_library_path, movie_folder)

        if not os.path.isdir(movie_folder_path):
            continue

        # Ensure the "Custom Versions/1Mbps" folder exists
        ensure_custom_versions_folder(movie_folder_path)

        # Process and convert videos
        process_videos(movie_folder_path)

    print("Processing complete.")

if __name__ == "__main__":
    main()

