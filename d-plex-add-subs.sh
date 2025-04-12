#!/bin/bash

# Check if directory, model, and language are passed as arguments
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Usage: $0 <directory> <model> <language_code>"
    exit 1
fi

# Directory to process, model to use, and language code
DIR="$1"
MODEL="$2"
LANGUAGE_CODE="$3"

# Map the 3-digit language code to a 2-digit code for stable-ts command
declare -A LANG_MAP
LANG_MAP=( ["eng"]="en" ["spa"]="es" ["fra"]="fr" ["deu"]="de" ["rus"]="ru" ["jpn"]="ja" ["kor"]="ko" ["gre"]="el")

# Check if the language code is valid
if [[ -z "${LANG_MAP[$LANGUAGE_CODE]}" ]]; then
    echo "Invalid language code: $LANGUAGE_CODE. Supported codes are: ${!LANG_MAP[@]}"
    exit 1
fi

# Activate stable-ts conda environment
source ~/opt/miniconda3/etc/profile.d/conda.sh
conda activate stable-ts-env

# Initialize an array to hold files to be processed
declare -a FILES_TO_PROCESS

# Find and process each .mp4 or .mkv file in the directory and its subdirectories
while IFS= read -r -d '' file; do
    # Extract file basename (without extension)
    BASENAME=$(basename "$file")
    FILENAME="${BASENAME%.*}"

    # Define the output subtitle file name in the same directory as the input file, including the model name
    SUBTITLE_OUTPUT="${file%.*}.${LANGUAGE_CODE}.stable-ts.${MODEL}.srt"

    # Check if the specific .srt file already exists
    if [ -e "${DIR}/${FILENAME}.${LANGUAGE_CODE}.stable-ts.${MODEL}.srt" ]; then
        echo "Skipping $file, subtitle file already exists."
        continue
    fi

    # Add the file to the list of files to process
    FILES_TO_PROCESS+=("$file")
done < <(find "$DIR" -type f \( -name "*.mp4" -o -name "*.mkv" \) -print0)

# Print the list of files to be processed
if [ ${#FILES_TO_PROCESS[@]} -eq 0 ]; then
    echo "No files to process."
    conda deactivate
    exit 0
fi

echo "The following files will be processed:"
for file in "${FILES_TO_PROCESS[@]}"; do
    echo "$file"
done

# Ask for user confirmation
read -p "Do you want to proceed with processing these files? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborting."
    conda deactivate
    exit 1
fi

# Process each file with stable-ts
for file in "${FILES_TO_PROCESS[@]}"; do
    # Define the output subtitle file name in the same directory as the input file, including the model name
    SUBTITLE_OUTPUT="${file%.*}.${LANGUAGE_CODE}.stable-ts.${MODEL}.srt"

    # Run stable-ts command
    echo "Processing $file ..."

    # Run stable-ts command with the 2-digit language code
    stable-ts "$file" \
        --output "$SUBTITLE_OUTPUT" \
        --model "$MODEL" \
        --device cuda \
        --verbose 1 \
        --language "${LANG_MAP[$LANGUAGE_CODE]}" \
        --word_level False
done

# Deactivate conda environment
conda deactivate

echo "All files processed."
