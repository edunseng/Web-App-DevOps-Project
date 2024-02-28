# Function to generate a timestamp
function generate_timestamp() {
  date +%Y%m%d-%H%M%S
}

# Function to create a new plan filename with a timestamp
function create_new_plan_filename() {
  local timestamp=$(generate_timestamp)
  echo "$tfplan_prefix-${timestamp}-${TF_ENV^^}"
}

# Generates a timestamp, creates a new plan filename, and determines the final plan filename.
function generate_plan_filename() {
  local new_plan_filename=$(create_new_plan_filename)
  echo "${1:-$new_plan_filename}"
}


# Function to check connectivity to a goiven host
function check_connectivity() {
  local host=$1

  echo "Checking connectivity to $host..."
  if ping -c 4 "$host"; then
    echo "Successfully reached $host."
    return 0  # Success
  else
    echo "Failed to reach $host. Please check your network connection and try again."
    return 1  # Failure
  fi
}

# Checks for the existence of a Terraform plan file and returns 1 if not found.
function check_plan_file_exists() {
  if [ -f "$TF_PLANS_DIR/$1" ]; then
    return 0
  else
    echo "Error: Plan file not found at $TF_PLANS_DIR/$1"
    return 1
  fi
}


# Initializes Terraform configuration in the environment-specific directory.
function terraform_init() {
    echo "Initializing the Terraform project configuration for environment: $TF_ENV..."
    # Run terraform init within the correct directory
    if terraform init; then
        echo "Terraform initialization successful."
        return 0  # Initialization was successful
    else
        echo "An error occurred during Terraform init. Please check the output for details."
        return 1  # Return failure if initialization fails
    fi
}

# Creates a Terraform plan file within the designated plans directory.
# Function to create a Terraform plan file
function terraform_plan() {
  # Check connectivity before proceeding
  #if ! perform_operation_with_retry 'check_connectivity "management.azure.com"' 5; then 
  #  return 1  # Exit if unable to reach Azure
  #fi

  # Create a directory for plan files if it doesn't exist
  echo "Planning the Terraform project configuration..." 
  if [ ! -d "$TF_PLANS_DIR" ]; then
    mkdir -p "$TF_PLANS_DIR"
    chown "$(whoami)":"$(whoami)" "$TF_PLANS_DIR"  # Set ownership of the directory
  fi
  local plan_filename=$(generate_plan_filename)
  echo "New plan will be saved as '$TF_PLANS_DIR/$plan_filename'"

  # Run terraform plan only if init was successful
  if perform_operation_with_retry "terraform plan -out=$TF_PLANS_DIR/${plan_filename}" 2; then 
  #if terraform plan -out="$TF_PLANS_DIR/${plan_filename}"; then
    echo "Terraform plan was created successfully."
    export plan=$plan_filename
    terraform show $TF_PLANS_DIR/${plan}
    return 0  # Plan creation was successful
  else
    echo "Failed to create Terraform plan. Would you like to try a different DNS Server (8.8.8.8) for optimal DNS resolution? (y/n)"
    read -n 1 -r user_input
    if [[ $user_input =~ ^[Yy]$ ]]; then
        # User chose to set Google's public DNS server
        set_google_dns
        if ! terraform plan $plan; then
            echo "Changing to Google's public DNS did not resolve the issue, the plan could not be created."
            return 1  # Return failure if unable to create a plan
        else
            echo "Plan created successfully using Google's public DNS."
            return 0  # Plan creation was successful
        fi
    else
        echo "Not changing DNS settings. Exiting without creating a plan."
        return 1  # Return failure as user opted not to change DNS settings
    fi
  fi
}

set_google_dns() {
    # Define Google DNS servers
    local google_dns1="8.8.8.8"
    local google_dns2="8.8.4.4"

    # Check if we have sudo privileges
    if ! sudo -v; then
        echo "You must have sudo privileges to set DNS."
        return 1
    fi

    # Check if Google DNS servers are already set
    if grep -qE "$google_dns1|$google_dns2" /etc/resolv.conf; then
        echo "Google DNS servers are already set."
        return 0
    fi

    # Prevent automatic generation of resolv.conf (WSL-specific)
    if grep -q Microsoft /proc/version; then  # Check if we are in WSL
        if [ ! -f /etc/wsl.conf ]; then
            echo "[network]" | sudo tee /etc/wsl.conf > /dev/null
            echo "generateResolvConf = false" | sudo tee -a /etc/wsl.conf > /dev/null
        elif ! grep -q "generateResolvConf = false" /etc/wsl.conf; then
            echo "generateResolvConf = false" | sudo tee -a /etc/wsl.conf > /dev/null
        fi
        sudo rm -f /etc/resolv.conf  # Remove the symlink that WSL creates
    fi

    # Backup current resolv.conf
    sudo cp /etc/resolv.conf /etc/resolv.conf.backup

    # Write Google DNS entries to resolv.conf
    echo "nameserver $google_dns1" | sudo tee /etc/resolv.conf > /dev/null
    echo "nameserver $google_dns2" | sudo tee -a /etc/resolv.conf > /dev/null

    echo "Google DNS has been set successfully."
}