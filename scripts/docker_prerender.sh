#!/bin/bash
set -e

# --- Prevent Infinite Loop ---
if [[ "$QUARTO_DOCKER_RENDER_ACTIVE" == "true" ]]; then
  exit 0
fi

# --- Get Environment Variables ---
input_files_str=${QUARTO_PROJECT_INPUT_FILES:-""}
project_dir=${QUARTO_PROJECT_DIR:-"."}
project_render_args=${QUARTO_PROJECT_RENDER_ARGS:-""}

# --- Get the first input file ---
read -r -a input_files <<< "$input_files_str"
if [[ ${#input_files[@]} -eq 0 ]]; then
  exit 0
fi
TARGET_INPUT_FILE="${input_files[0]}"
TARGET_INPUT_FILE_ABS="$project_dir/$TARGET_INPUT_FILE"

# --- Check if target file exists ---
if [[ ! -f "$TARGET_INPUT_FILE_ABS" ]]; then
  echo "[Project Pre-Render] Warning: Target input file not found ('$TARGET_INPUT_FILE_ABS'). Skipping Docker check."
  exit 0
fi

# --- Check Dependencies ---
if ! command -v docker &> /dev/null || ! command -v sed &> /dev/null; then
    echo "[Project Pre-Render] Error: 'docker' or 'sed' command not found. Please check prerequisites." >&2
    exit 1
fi

# --- Call TypeScript Parser using 'quarto run' ---
echo "[Debug] Calling TypeScript YAML parser using 'quarto run'..."
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
TS_PARSER_SCRIPT="$SCRIPT_DIR/parse_yaml.ts"

# Run the TS script using 'quarto run', capture output
# Note: 'quarto run' might handle permissions implicitly, so --allow-read might not be needed here.
# Capture stdout, redirect stderr to stdout to catch potential errors from 'quarto run' itself
PARSER_OUTPUT=$(quarto run "$TS_PARSER_SCRIPT" "$TARGET_INPUT_FILE_ABS" 2>&1)
PARSER_EXIT_CODE=$?

if [[ $PARSER_EXIT_CODE -ne 0 ]]; then
    echo "[Project Pre-Render] Error: TypeScript YAML parser ('quarto run') failed." >&2
    echo "Parser Output:" >&2
    echo "$PARSER_OUTPUT" >&2
    exit 1
fi
# echo "[Debug] Parser Output:" "$PARSER_OUTPUT" # Optional debug

# --- Parse Output from TypeScript Script ---
DOCKER_IMAGE=""
declare -a DOCKER_OPTIONS=()

while IFS= read -r line; do
    # Ignore potential Deno download/compile messages if any appear on stdout
    if [[ "$line" =~ ^(Download|Compile|Check) ]]; then
        continue
    fi
    # Parse our specific output format
    if [[ "$line" =~ ^IMAGE=(.*) ]]; then
        DOCKER_IMAGE="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^OPTION=(.*) ]]; then
        DOCKER_OPTIONS+=("${BASH_REMATCH[1]}")
    fi
done <<< "$PARSER_OUTPUT"

# --- Validation after Parsing ---
if [[ -z "$DOCKER_IMAGE" ]]; then
  echo "[Project Pre-Render] No 'docker.image' found by parser. Proceeding with host render."
  exit 0 # No image means don't use Docker
fi

echo "[Debug] Bash Parsing Result - Image: $DOCKER_IMAGE"
echo "[Debug] Bash Parsing Result - Options: (${DOCKER_OPTIONS[*]})"


# --- Docker Execution ---
PROJECT_DIR_ABS="$project_dir"
QMD_FILE_RELATIVE="$TARGET_INPUT_FILE"
CONTAINER_PROJECT_PATH="/project"

echo "[Project Pre-Render] Docker config processed. Running in container (project execution setting applies)..."
echo "  Image: $DOCKER_IMAGE"
# echo "  Options: ${DOCKER_OPTIONS[@]}" # Optional debug

export QUARTO_DOCKER_RENDER_ACTIVE="true"

USER_ID=$(id -u)
GROUP_ID=$(id -g)

docker_cmd_parts=(
  docker run --rm -it
  -v "${PROJECT_DIR_ABS}:${CONTAINER_PROJECT_PATH}"
  -w "${CONTAINER_PROJECT_PATH}"
  --user "${USER_ID}:${GROUP_ID}"
  -e QUARTO_DOCKER_RENDER_ACTIVE="true"
)
for opt in "${DOCKER_OPTIONS[@]}"; do
  docker_cmd_parts+=("$(printf '%q' "$opt")")
done
docker_cmd_parts+=(
  "$DOCKER_IMAGE"
  quarto render "$QMD_FILE_RELATIVE" $project_render_args
)

"${docker_cmd_parts[@]}"

DOCKER_EXIT_CODE=$?
echo "[Project Pre-Render] Docker execution finished (Exit Code: $DOCKER_EXIT_CODE)."

exit $DOCKER_EXIT_CODE
