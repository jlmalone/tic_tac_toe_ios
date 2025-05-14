#!/bin/bash
# Use this script to update keys in your Info.plist from values in your .env file.
# Run this script from the root directory of your Xcode project.
# WARNING: This script will print the content of your .env file for debugging.
# Be careful with this output if it contains sensitive information.

# --- Configuration ---
# This path now matches what your Xcode Build Settings show.
PLIST_FILE="./tic-tac-toe-ios-ethereum-Info.plist"
ENV_FILE="./.env"

KEYS_TO_ADD=(
  "LOCAL_RPC_URL:String"
  "SEPOLIA_RPC_URL:String"
  "PRIVATE_KEY_HARDHAT_0:String"
  "PRIVATE_KEY_HARDHAT_1:String"
  "PRIVATE_KEY_PLAYER1:String"
  "PRIVATE_KEY_PLAYER2:String"
  "HARDHAT_CHAIN_ID:String"
  "SEPOLIA_CHAIN_ID:String"
)

# --- Helper Functions ---
getValueFromEnv() {
  local key_to_find="$1"
  local env_file_path="$2"
  local line_found
  local value_after_equals
  local trimmed_value

  echo "    [DEBUG getValueFromEnv] Searching for key: '$key_to_find' in file: '$env_file_path'" >&2
  
  line_found=$(grep -m 1 "^${key_to_find}[[:space:]]*=" "$env_file_path")

  if [ -z "$line_found" ]; then
    echo "    [DEBUG getValueFromEnv] Key '$key_to_find' NOT found by grep in '$env_file_path'" >&2
    return 1 
  fi

  echo "    [DEBUG getValueFromEnv] Matched line for '$key_to_find': '$line_found'" >&2
  
  value_after_equals=$(echo "$line_found" | sed 's/^[^=]*=//')
  echo "    [DEBUG getValueFromEnv] Value after '=' for '$key_to_find': '$value_after_equals'" >&2

  trimmed_value=$(echo "$value_after_equals" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
  echo "    [DEBUG getValueFromEnv] Final trimmed value for '$key_to_find': '$trimmed_value'" >&2
  
  echo "$trimmed_value"
  return 0 
}

# --- Main Script Logic ---
echo "--- Script Start: Updating $PLIST_FILE from $ENV_FILE ---"
echo ""

if ! command -v /usr/libexec/PlistBuddy &> /dev/null; then
    echo "Error: PlistBuddy command not found."
    exit 1
fi
echo "[Sanity Check] PlistBuddy found."

if [ ! -f "$PLIST_FILE" ]; then
  echo "Error: Info.plist file not found at '$PLIST_FILE'."
  exit 1
fi
if [ ! -w "$PLIST_FILE" ]; then
  echo "Error: Info.plist file at '$PLIST_FILE' is not writable. Check permissions."
  exit 1
fi
echo "[Sanity Check] Target Info.plist found and is writable: $PLIST_FILE"

if [ ! -f "$ENV_FILE" ]; then
  echo "Error: .env file not found at $ENV_FILE."
  exit 1
fi
if [ ! -r "$ENV_FILE" ]; then
  echo "Error: .env file at $ENV_FILE is not readable."
  exit 1
fi
echo "[Sanity Check] .env file found and is readable: $ENV_FILE"
echo ""

echo "--- Content of $ENV_FILE (for debugging) ---"
cat "$ENV_FILE"
echo "--- End of $ENV_FILE content ---"
echo ""

echo "--- Processing keys ---"
success_count=0
warning_count=0

for entry in "${KEYS_TO_ADD[@]}"; do
  IFS=':' read -r key type <<< "$entry"
  echo "[Processing] Key: '$key', Expected Type: '$type'"

  value=$(getValueFromEnv "$key" "$ENV_FILE")
  get_value_status=$?

  if [ $get_value_status -ne 0 ] || [ -z "$value" ]; then
    echo "  [Warning] Value for key '$key' not found or is empty in $ENV_FILE. Skipping."
    warning_count=$((warning_count + 1))
    echo "" 
    continue
  fi

  echo "  [Action] Ensuring key '$key' in $PLIST_FILE has value '$value'"

  # 1. Try to Delete the key. This will succeed if it exists, fail silently if not (hence '|| true').
  /usr/libexec/PlistBuddy -c "Delete :$key" "$PLIST_FILE" > /dev/null 2>&1 || true
  
  # 2. Add the key with the new value.
  add_output=$(/usr/libexec/PlistBuddy -c "Add :$key $type \"$value\"" "$PLIST_FILE" 2>&1)
  add_status=$?
  
  if [ $add_status -ne 0 ]; then
      echo "    [Error] PlistBuddy 'Add' command failed for key '$key' with value '$value': $add_output"
  else
      echo "    [Success] Key '$key' ensured with value '$value'."
      success_count=$((success_count + 1))
  fi
  echo "" 
done

echo "--- Script Finish ---"
echo "Summary: $success_count key(s) processed successfully."
if [ $warning_count -gt 0 ]; then
  echo "$warning_count key(s) had warnings (value not found or empty in .env)."
fi
echo "You can verify the changes in Xcode under your target's Info tab -> Custom iOS Target Properties, or by viewing the raw $PLIST_FILE content."
echo "Remember to be cautious with private keys in bundled files for production."
echo ""
echo "--- Final content of $PLIST_FILE (for verification) ---"
cat "$PLIST_FILE"
echo "--- End of $PLIST_FILE content ---"