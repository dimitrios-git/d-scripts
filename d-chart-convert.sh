#!/bin/bash

# Function to check image dimensions
function check_dimensions() {
  local width=$(identify -format "%w" "$1")
  local height=$(identify -format "%h" "$1")
  if [[ $width -ne 1835 || $height -ne 1099 ]]; then
    echo "Error: Image dimensions are not 1835x1099. Please resize before running the script."
    exit 1
  fi
}

# Get the image filename from the first argument
image_file="$1"

# Check if an image file is provided
if [[ -z "$image_file" ]]; then
  echo "Error: Please provide an image file as an argument."
  exit 1
fi

# Check if cwebp is installed
if ! which cwebp >/dev/null 2>&1; then
  echo "Error: cwebp command not found. Please install webp package."
  exit 1
fi

# Check if ImageMagick is installed
if ! which convert >/dev/null 2>&1; then
  echo "Error: ImageMagick's convert command not found. Please install ImageMagick."
  exit 1
fi

# Check image dimensions
check_dimensions "$image_file"

# Extract filename without extension
filename="${image_file%.*}"
extension="${image_file##*.}"

# Crop the image
cropped_image="${filename}_cropped.${extension}"
convert "$image_file" -crop 1813x1035+11+28 "$cropped_image"

# Convert to webp with good compression
cwebp -q 80 "$cropped_image" -o "${filename}.webp"
if [[ $? -ne 0 ]]; then
  echo "Error: Conversion to webp failed."
  exit 1
fi

echo "Image successfully prepared for upload: ${filename}.webp"

