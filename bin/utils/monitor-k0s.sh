#!/bin/bash
export KUBECONFIG=""

# Function to find the kubeconfig file with project suffix
find_kubeconfig() {
    local k0sctl_dir="./k0sctl-config"
    local project_suffix_file=".project-suffix"
    
    # Check if k0sctl-config directory exists
    if [[ ! -d "$k0sctl_dir" ]]; then
        echo "Waiting for k0sctl-config directory to appear..."
        return 1
    fi
    
    # Check if .project-suffix file exists
    if [[ ! -f "$project_suffix_file" ]]; then
        echo "Waiting for .project-suffix file to appear..."
        return 1
    fi
    
    # Read the project suffix
    local suffix=$(cat "$project_suffix_file" 2>/dev/null | tr -d '\n\r')
    if [[ -z "$suffix" ]]; then
        echo "Project suffix file is empty, waiting..."
        return 1
    fi
    
    # Look for kubeconfig file with the suffix (suffix-kubeconfig format)
    local kubeconfig_file="$k0sctl_dir/k0rdent-$suffix-kubeconfig"
    
    if [[ -f "$kubeconfig_file" ]]; then
        export KUBECONFIG="$kubeconfig_file"
        echo "Found kubeconfig: $kubeconfig_file"
        return 0
    else
        echo "Waiting for kubeconfig file: $kubeconfig_file"
        return 1
    fi
}

# Function to run viddy with kubectl
run_viddy() {
    echo "Starting viddy to monitor pods..."
    viddy "kubectl get pods -A -o wide"
}

# Main monitoring loop
main() {
    echo "Starting k0s monitoring script..."
    echo "Monitoring for k0sctl-config directory and kubeconfig file..."
    
    while true; do
        if [[ $? -eq 0 ]]; then
            # Found the kubeconfig file, run viddy
            find_kubeconfig
            run_viddy
            
            # If viddy exits (user presses q or Ctrl+C), restart the monitoring
            echo "viddy exited, restarting monitoring..."
            sleep 2
        else
            # Sleep for a bit before checking again
            sleep 5
        fi
    done
}

# Handle Ctrl+C gracefully
trap 'echo -e "\nExiting monitoring script..."; exit 0' SIGINT SIGTERM

# Start the main function
main
