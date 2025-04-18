#!/bin/bash
set -e

# --- Prevent Infinite Loop ---
if [[ "$QUARTO_DOCKER_RENDER_ACTIVE" == "true" ]]; then
  echo "[Project Pre-Render] Already inside Docker. Allowing render."
  exit 0
fi

echo "[Project Pre-Render] Script started."
echo "[Project Pre-Render] Input files variable: '$QUARTO_PROJECT_INPUT_FILES'"

# --- Get the first input file from the list ---
read -r -a input_files <<< "$QUARTO_PROJECT_INPUT_FILES"
if [[ ${#input_files[@]} -eq 0 ]]; then
  echo "[Project Pre-Render] No input files specified. Skipping Docker check."
  exit 0
fi
TARGET_INPUT_FILE="${input_files[0]}"
echo "[Project Pre-Render] Processing target file: '$TARGET_INPUT_FILE'"

# --- Check if target file exists ---
TARGET_INPUT_FILE_ABS="$QUARTO_PROJECT_DIR/$TARGET_INPUT_FILE"
if [[ ! -f "$TARGET_INPUT_FILE_ABS" ]]; then
  echo "[Project Pre-Render] Warning: Target input file not found ('$TARGET_INPUT_FILE_ABS'). Skipping Docker check."
  exit 0
fi

# --- YAML Parsing (Requires yq on host) ---
if ! command -v yq &> /dev/null || ! command -v sed &> /dev/null; then
    echo "[Project Pre-Render] Error: 'yq' or 'sed' command not found." >&2
    exit 1
fi

echo "[Debug] Absolute path: '$TARGET_INPUT_FILE_ABS'"
echo "[Debug] Extracting front matter using sed..."

# Extract YAML front matter using sed (lines between first and second ---, excluding the --- lines)
# Handle potential errors during extraction
FRONT_MATTER=$(sed -n '/^---$/,/^---$/p' "$TARGET_INPUT_FILE_ABS" | sed '1d;$d')
if [[ -z "$FRONT_MATTER" ]]; then
    echo "[Project Pre-Render] Warning: Could not extract YAML front matter from '$TARGET_INPUT_FILE_ABS'. Skipping Docker check."
    exit 0 # Proceed with host render if no front matter found
fi
# echo "[Debug] Extracted Front Matter:" "$FRONT_MATTER" # Optional debug

echo "[Debug] Checking for docker block in extracted front matter..."

# Pipe ONLY the front matter into yq. Check exit status.
# No need for select(document_index == 0) now.
echo "$FRONT_MATTER" | yq -e '.docker | length > 0' > /dev/null # Redirect output, check exit code only
YQ_CHECK_EXIT_CODE=$?
echo "[Debug] yq check exit code: $YQ_CHECK_EXIT_CODE"

# Check only the exit code now
if [[ $YQ_CHECK_EXIT_CODE -ne 0 ]]; then
  # Exit code is non-zero, meaning .docker likely doesn't exist or is empty/null in front matter
  echo "[Project Pre-Render] No 'docker:' config found in YAML front matter. Proceeding with host render/freeze."
  exit 0 # Let host handle it
else
   # Exit code is 0, meaning .docker exists and is not empty/null
   echo "[Debug] Docker config block found in front matter."
fi

# --- Docker Configuration Extraction (Pipe front matter to yq) ---
echo "[Debug] Extracting docker image from front matter..."
# Use -e -r and pipe the extracted FRONT_MATTER
DOCKER_IMAGE=$(echo "$FRONT_MATTER" | yq -e -r '.docker.image // ""')
if [[ $? -ne 0 || -z "$DOCKER_IMAGE" ]]; then
    echo "[Project Pre-Render] Error: Failed to extract 'docker.image' from front matter." >&2
    exit 1
fi

echo "[Debug] Extracting docker options from front matter..."
# Use -r and pipe the extracted FRONT_MATTER
DOCKER_OPTIONS_RAW=$(echo "$FRONT_MATTER" | yq -r '.docker.options // [] | .[]' 2>/dev/null) || true
DOCKER_OPTIONS=()
while IFS= read -r line; do
    if [[ -n "$line" ]]; then
        DOCKER_OPTIONS+=("$line")
    fi
done <<< "$DOCKER_OPTIONS_RAW"


# --- Docker Execution ---
PROJECT_DIR_ABS="$QUARTO_PROJECT_DIR"
QMD_FILE_RELATIVE="$TARGET_INPUT_FILE"
CONTAINER_PROJECT_PATH="/project"

echo "[Project Pre-Render] Docker config processed. Running in container (project freeze setting applies)..."
echo "  Image: $DOCKER_IMAGE"
echo "  Options: ${DOCKER_OPTIONS[@]}"

export QUARTO_DOCKER_RENDER_ACTIVE="true"

# Run quarto render normally - project settings will handle freeze
docker run --rm -it \
  -v "$PROJECT_DIR_ABS":"$CONTAINER_PROJECT_PATH" \
  -w "$CONTAINER_PROJECT_PATH" \
  --user "$(id -u):$(id -g)" \
  -e QUARTO_DOCKER_RENDER_ACTIVE \
  "${DOCKER_OPTIONS[@]}" \
  "$DOCKER_IMAGE" \
  quarto render "$QMD_FILE_RELATIVE" $QUARTO_PROJECT_RENDER_ARGS

DOCKER_EXIT_CODE=$?
echo "[Project Pre-Render] Docker execution finished (Exit Code: $DOCKER_EXIT_CODE)."

exit $DOCKER_EXIT_CODE
