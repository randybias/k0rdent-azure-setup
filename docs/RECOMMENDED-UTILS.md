# Recommended Utilities

While not required for k0rdent Azure setup, these utilities can significantly enhance your development and operational experience.

## Search and Text Processing

### ripgrep (rg)
**Purpose**: Lightning-fast recursive search tool (better than grep)  
**Why use it**: Searches code intelligently, respects .gitignore, blazingly fast  
**Install**:
```bash
# macOS
brew install ripgrep

# Ubuntu/Debian
sudo apt install ripgrep

# From binary
curl -LO https://github.com/BurntSushi/ripgrep/releases/download/13.0.0/ripgrep_13.0.0_amd64.deb
sudo dpkg -i ripgrep_13.0.0_amd64.deb
```

**Example uses**:
```bash
# Find all references to a function
rg "check_prerequisites"

# Search only in shell scripts
rg -t sh "azure_cli"

# Show context around matches
rg -C 3 "error"
```

### fd
**Purpose**: Fast and user-friendly alternative to find  
**Why use it**: Simpler syntax than find, faster, colorized output  
**Install**:
```bash
# macOS
brew install fd

# Ubuntu/Debian
sudo apt install fd-find
```

**Example uses**:
```bash
# Find all shell scripts
fd -e sh

# Find files modified in last day
fd --changed-within 1d

# Find and execute
fd -e yaml -x yq eval '.' {}
```

## Monitoring and Visualization

### viddy
**Purpose**: Modern alternative to watch with better features  
**Why use it**: Colored diffs, precise intervals, better UI  
**Install**:
```bash
# macOS
brew install viddy

# Go install
go install github.com/sachaos/viddy@latest
```

**Example uses**:
```bash
# Monitor pod status with highlighting changes
viddy -d -n 2 kubectl get pods -A

# Watch VM creation progress
viddy -d az vm list -g $RG --query "[].{Name:name,State:provisioningState}"

# Monitor deployment events
viddy -d -n 1 kubectl get events --sort-by='.lastTimestamp'
```

### htop / btop
**Purpose**: Interactive process viewers  
**Why use it**: Better than top, shows resource usage beautifully  
**Install**:
```bash
# htop
brew install htop  # macOS
sudo apt install htop  # Ubuntu/Debian

# btop (even better, with network/disk graphs)
brew install btop  # macOS
sudo apt install btop  # Ubuntu 22.04+
```

## File Management and Navigation

### bat
**Purpose**: cat with syntax highlighting and Git integration  
**Why use it**: Makes reading code files much easier  
**Install**:
```bash
# macOS
brew install bat

# Ubuntu/Debian
sudo apt install bat
```

**Example uses**:
```bash
# View script with syntax highlighting
bat bin/deploy-k0rdent.sh

# Page through large files
bat --paging=always deployment-state.yaml

# Show git changes inline
bat --diff common-functions.sh
```

### exa / eza
**Purpose**: Modern replacement for ls  
**Why use it**: Better colors, git status, tree view, icons  
**Install**:
```bash
# eza (maintained fork of exa)
brew install eza  # macOS
sudo apt install eza  # Ubuntu 23.04+

# or via cargo
cargo install eza
```

**Example uses**:
```bash
# List with git status
eza -la --git

# Tree view with icons
eza -la --icons --tree --level=2

# Sort by modification time
eza -la --sort=modified
```

### fzf
**Purpose**: Fuzzy finder for command line  
**Why use it**: Quickly find files, commands, history  
**Install**:
```bash
# macOS
brew install fzf

# Ubuntu/Debian
sudo apt install fzf
```

**Example uses**:
```bash
# Find and edit files
vim $(fzf)

# Search command history (Ctrl+R replacement)
# Add to .bashrc: eval "$(fzf --bash)"

# Quick directory navigation
cd $(find . -type d | fzf)
```

## JSON/YAML Processing

### gron
**Purpose**: Make JSON greppable  
**Why use it**: Flattens JSON for easy searching and filtering  
**Install**:
```bash
# macOS
brew install gron

# Go install
go install github.com/tomnomnom/gron@latest
```

**Example uses**:
```bash
# Make JSON searchable
az vm list | gron | rg "publicIps"

# Extract specific values
kubectl get nodes -o json | gron | rg "status.addresses"
```

### yq (already required)
**Enhanced usage tips**:
```bash
# In-place edit YAML files
yq eval '.kof.enabled = true' -i config/k0rdent.yaml

# Merge YAML files
yq eval-all '. as $item ireduce ({}; . * $item)' file1.yaml file2.yaml

# Convert between formats
yq -o json deployment-state.yaml | jq '.'
```

## Network and Connectivity

### mtr
**Purpose**: Combined traceroute and ping  
**Why use it**: Better network diagnostics than ping alone  
**Install**:
```bash
# macOS
brew install mtr

# Ubuntu/Debian
sudo apt install mtr
```

**Example uses**:
```bash
# Interactive mode
mtr azure.microsoft.com

# Report mode
mtr --report --report-cycles 100 8.8.8.8
```

### httpie
**Purpose**: User-friendly HTTP client  
**Why use it**: Much easier than curl for API testing  
**Install**:
```bash
# macOS
brew install httpie

# Ubuntu/Debian
sudo apt install httpie
```

**Example uses**:
```bash
# Test API endpoints
http GET api.example.com/status

# POST with JSON
http POST api.example.com/data name=test value=123
```

## Development Tools

### direnv
**Purpose**: Automatic environment variable loading  
**Why use it**: Project-specific env vars, automatic KUBECONFIG switching  
**Install**:
```bash
# macOS
brew install direnv

# Ubuntu/Debian
sudo apt install direnv

# Add to .bashrc
eval "$(direnv hook bash)"
```

**Example uses**:
```bash
# Create .envrc in project
echo 'export KUBECONFIG=$PWD/k0sctl-config/kubeconfig' > .envrc
direnv allow

# Automatic environment switching
cd /path/to/project  # Env vars loaded automatically
```

### shellcheck (highly recommended)
**Purpose**: Shell script static analysis  
**Why use it**: Catches common shell scripting errors  
**Install**:
```bash
# macOS
brew install shellcheck

# Ubuntu/Debian
sudo apt install shellcheck
```

**Example uses**:
```bash
# Check single script
shellcheck bin/deploy-k0rdent.sh

# Check all scripts
fd -e sh -x shellcheck {}
```

## Kubernetes Tools

### k9s
**Purpose**: Terminal UI for Kubernetes  
**Why use it**: Much easier than kubectl for exploration  
**Install**:
```bash
# macOS
brew install k9s

# Linux
curl -sS https://webinstall.dev/k9s | bash
```

### stern
**Purpose**: Multi-pod log tailing  
**Why use it**: Better than kubectl logs for multiple pods  
**Install**:
```bash
# macOS
brew install stern

# Linux
curl -Lo stern https://github.com/stern/stern/releases/latest/download/stern_linux_amd64
chmod +x stern && sudo mv stern /usr/local/bin/
```

**Example uses**:
```bash
# Tail all pods in namespace
stern -n kof .

# Tail by label
stern -l app=kof-mothership

# With timestamps
stern --timestamps -n kcm-system .
```

### kubectx / kubens
**Purpose**: Fast context and namespace switching  
**Why use it**: Much faster than kubectl config commands  
**Install**:
```bash
# macOS
brew install kubectx

# Ubuntu/Debian
sudo apt install kubectx
```

## Git Enhancements

### delta
**Purpose**: Better git diffs  
**Why use it**: Syntax highlighting, side-by-side diffs  
**Install**:
```bash
# macOS
brew install git-delta

# Ubuntu/Debian
curl -LO https://github.com/dandavison/delta/releases/download/0.16.5/git-delta_0.16.5_amd64.deb
sudo dpkg -i git-delta_0.16.5_amd64.deb

# Configure git to use delta
git config --global core.pager delta
```

### tig
**Purpose**: Text-mode interface for git  
**Why use it**: Browse commits, diffs, logs interactively  
**Install**:
```bash
# macOS
brew install tig

# Ubuntu/Debian
sudo apt install tig
```

## Performance Analysis

### hyperfine
**Purpose**: Command-line benchmarking tool  
**Why use it**: Compare performance of different commands  
**Install**:
```bash
# macOS
brew install hyperfine

# Ubuntu/Debian
wget https://github.com/sharkdp/hyperfine/releases/download/v1.18.0/hyperfine_1.18.0_amd64.deb
sudo dpkg -i hyperfine_1.18.0_amd64.deb
```

**Example uses**:
```bash
# Compare grep vs ripgrep
hyperfine 'grep -r "pattern" .' 'rg "pattern"'

# Benchmark script performance
hyperfine --warmup 3 './bin/prepare-deployment.sh status'
```

## Azure-Specific Tools

### Azure CLI Interactive Mode
**Purpose**: Interactive Azure CLI with autocomplete  
**Why use it**: Easier Azure resource exploration  
**Usage**:
```bash
# Enter interactive mode
az interactive

# Auto-completion and syntax highlighting
# Built-in help and examples
```

### azcopy
**Purpose**: High-performance Azure storage transfers  
**Why use it**: Much faster than az storage commands  
**Install**:
```bash
# Download from Microsoft
curl -Lo azcopy.tar.gz https://aka.ms/downloadazcopy-v10-linux
tar -xf azcopy.tar.gz
sudo mv azcopy_linux_amd64_*/azcopy /usr/local/bin/
```

## Terminal Multiplexers

### tmux
**Purpose**: Terminal multiplexer  
**Why use it**: Multiple sessions, survives disconnects  
**Install**:
```bash
# macOS
brew install tmux

# Ubuntu/Debian
sudo apt install tmux
```

**k0rdent-specific .tmux.conf**:
```bash
# Split panes for monitoring
bind-key M split-window -h "viddy kubectl get pods -A"
bind-key V split-window -v "viddy az vm list -g \$RG --output table"
bind-key L split-window -h "stern -n kcm-system ."
```

## Recommended Shell Configuration

### Starship Prompt
**Purpose**: Fast, customizable shell prompt  
**Why use it**: Shows git status, kubectl context, Azure subscription  
**Install**:
```bash
# macOS/Linux
curl -sS https://starship.rs/install.sh | sh

# Add to .bashrc
eval "$(starship init bash)"
```

### Example .bashrc additions for k0rdent
```bash
# Aliases for common k0rdent operations
alias k='kubectl'
alias kga='kubectl get all -A'
alias kgp='kubectl get pods -A'
alias wgs='sudo wg show'
alias azls='az vm list -g $RG --output table'

# Quick kubeconfig switching
kc() {
    export KUBECONFIG=$PWD/k0sctl-config/$1-kubeconfig
    echo "KUBECONFIG set to: $KUBECONFIG"
}

# Monitor deployment
monitor-deploy() {
    tmux new-session -d -s deploy
    tmux send-keys -t deploy "viddy kubectl get pods -A" C-m
    tmux split-window -t deploy -h
    tmux send-keys -t deploy "viddy az vm list -g $RG --output table" C-m
    tmux split-window -t deploy -v
    tmux send-keys -t deploy "tail -f deployment-events.yaml" C-m
    tmux attach -t deploy
}
```

## Putting It All Together

Example workflow using recommended tools:

```bash
# Find scripts that handle state
rg -t sh "update_state" | bat

# Monitor deployment progress
viddy -d az vm list -g $RG --output table

# Explore Kubernetes resources
k9s

# Search for configuration values
fd -e yaml | xargs rg "kof:" | bat

# Quick file navigation
cd $(fd -t d | fzf)

# Compare script performance
hyperfine './deploy-k0rdent.sh check' 'bash bin/check-prerequisites.sh'

# View logs from multiple pods
stern -n kof . --tail 50

# Interactive git history
tig

# Check shell scripts for issues
fd -e sh -x shellcheck {}
```

These tools will make your k0rdent development and operations significantly more efficient and enjoyable!