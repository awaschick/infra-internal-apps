#!/usr/bin/env zsh

# AWS credentials directory
AWS_DIR="$HOME/.aws"
AWS_CREDENTIALS_FILES_DIR="$AWS_DIR/credentials-files"
AWS_CREDENTIALS_ACTIVE="$AWS_DIR/credentials"

# Create directories if they don't exist
mkdir -p "${AWS_CREDENTIALS_FILES_DIR}"

# Set AWS_SHARED_CREDENTIALS_FILE to the active credentials file
if [[ -L "${AWS_CREDENTIALS_ACTIVE}" ]] || [[ -f "${AWS_CREDENTIALS_ACTIVE}" ]]; then
  export AWS_SHARED_CREDENTIALS_FILE="${AWS_CREDENTIALS_ACTIVE}"
fi

# Function to switch AWS credentials
aws-switch() {
  local creds_name="$1"
  
  if [[ -z "$creds_name" ]]; then
    echo "Usage: aws-switch <credentials-name>"
    echo ""
    echo "Available credentials:"
    for creds_file in "${AWS_CREDENTIALS_FILES_DIR}"/*(.N); do
      local basename="${creds_file:t}"
      if [[ -L "${AWS_CREDENTIALS_ACTIVE}" ]] && [[ "$(readlink "${AWS_CREDENTIALS_ACTIVE}")" == "$creds_file" ]]; then
        echo "  * $basename (active)"
      elif [[ ! -L "${AWS_CREDENTIALS_ACTIVE}" ]] && [[ -f "${AWS_CREDENTIALS_ACTIVE}" ]]; then
        # If credentials is a regular file, show it as "static file"
        echo "    $basename"
      else
        echo "    $basename"
      fi
    done
    
    # Check if credentials is a static file rather than a symlink
    if [[ -f "${AWS_CREDENTIALS_ACTIVE}" ]] && [[ ! -L "${AWS_CREDENTIALS_ACTIVE}" ]]; then
      echo ""
      echo "Note: ~/.aws/credentials is currently a static file, not a symlink."
      echo "      Switching will convert it to a symlink."
    fi
    
    return 1
  fi
  
  local target_creds="${AWS_CREDENTIALS_FILES_DIR}/${creds_name}"
  
  if [[ ! -f "$target_creds" ]]; then
    echo "Error: Credentials '${creds_name}' not found in ${AWS_CREDENTIALS_FILES_DIR}"
    return 1
  fi
  
  # Backup existing credentials file if it's not a symlink
  if [[ -f "${AWS_CREDENTIALS_ACTIVE}" ]] && [[ ! -L "${AWS_CREDENTIALS_ACTIVE}" ]]; then
    local backup="${AWS_CREDENTIALS_ACTIVE}.backup.$(date +%Y%m%d_%H%M%S)"
    mv "${AWS_CREDENTIALS_ACTIVE}" "$backup"
    echo "Backed up existing credentials to: $backup"
  fi
  
  ln -sf "$target_creds" "${AWS_CREDENTIALS_ACTIVE}"
  export AWS_SHARED_CREDENTIALS_FILE="${AWS_CREDENTIALS_ACTIVE}"
  echo "Switched to AWS credentials: ${creds_name}"
}

# Scan available credentials and display info
echo ""
echo "🔑 AWS Credentials Manager"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ -L "${AWS_CREDENTIALS_ACTIVE}" ]]; then
  local active_creds="$(readlink "${AWS_CREDENTIALS_ACTIVE}")"
  local active_name="${active_creds:t}"
  echo "Active credentials: ${active_name}"
elif [[ -f "${AWS_CREDENTIALS_ACTIVE}" ]]; then
  echo "Active credentials: (static file - not managed)"
else
  echo "No active credentials set"
fi

echo ""
echo "Available credentials:"
local has_creds=false
for creds_file in "${AWS_CREDENTIALS_FILES_DIR}"/*(.N); do
  has_creds=true
  echo "  - ${creds_file:t}"
done

if [[ "$has_creds" == "false" ]]; then
  echo "  (none found in ${AWS_CREDENTIALS_FILES_DIR})"
fi

echo ""
echo "To switch credentials, use:"
echo "  aws-switch <credentials-name>"
echo ""
echo "Example:"
for creds_file in "${AWS_CREDENTIALS_FILES_DIR}"/*(.N); do
  echo "  aws-switch ${creds_file:t}"
  break
done
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
