#!/bin/bash

# Get the base movies path from the argument
base_path="$1"

# Initialize arrays for categorizing movies
no_plex_versions=()
with_plex_versions=()

# List all directories inside the base path (movies directories)
for movie_dir in "$base_path"/*/; do
    movie_name=$(basename "$movie_dir")
    
    # Check if the "Plex Versions" directory exists inside the movie directory
    if [ -d "$movie_dir/Plex Versions" ]; then
        with_plex_versions+=("$movie_name")
    else
        no_plex_versions+=("$movie_name")
    fi
done

# Print common path
echo "Common Path: $base_path"
echo ""

# Print movies without Plex Versions
echo "Movies without Plex Versions:"
for movie in "${no_plex_versions[@]}"; do
    echo "$movie"
done

echo ""

# Print movies with Plex Versions
echo "Movies with Plex Versions:"
for movie in "${with_plex_versions[@]}"; do
    echo "$movie"
done

