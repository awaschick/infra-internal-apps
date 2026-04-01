# Kubernetes Configuration Manager

A simple tool to manage multiple kubectl configurations and easily switch between them.

## Overview

This tool provides:
- **Centralized config management**: Store all your kubectl configs in `~/.kube/config-files/`
- **Easy switching**: Use `kubeconfig-switch <config-name>` to switch between clusters
- **Visual feedback**: See which config is active when you open a terminal
- **Symlink-based**: Uses a symlink at `~/.kube/config.active` that points to your active config

## Installation

### Quick Install

Run the installation script from the `script` directory:

```bash
./install-kubeconfig-manager.sh
```

This will:
1. Create `~/.zsh_init` directory (if needed)
2. Copy `init-kubeconfigs.sh` to `~/.zsh_init/`
3. Create `~/.kube/config-files` directory
4. Verify your shell configuration

### Manual Install

If you prefer to install manually:

1. Copy the init script:
   ```bash
   mkdir -p ~/.zsh_init
   cp init-kubeconfigs.sh ~/.zsh_init/
   chmod +x ~/.zsh_init/init-kubeconfigs.sh
   ```

2. Add to your `~/.zshrc` (if not already present):
   ```bash
   for file in $(find ~/.zsh_init/*.sh -type f); do source "$file"; done
   ```

3. Create the config directory:
   ```bash
   mkdir -p ~/.kube/config-files
   ```

## Setup

1. **Place your kubectl config files** in `~/.kube/config-files/`:
   ```bash
   cp my-cluster-config.yaml ~/.kube/config-files/
   ```

2. **Set the initial active config**:
   ```bash
   ln -sf ~/.kube/config-files/my-cluster-config.yaml ~/.kube/config.active
   ```

3. **Restart your terminal** or source your shell config:
   ```bash
   source ~/.zshrc
   ```

## Usage

### View Available Configs

Simply run the command without arguments:

```bash
kubeconfig-switch
```

Output:
```
Usage: kubeconfig-switch <config-name>

Available configurations:
    production
  * staging (active)
    development
```

### Switch Configs

Switch to a different cluster:

```bash
kubeconfig-switch production
```

Output:
```
Switched to kubectl config: production
```

### Startup Information

When you open a new terminal, you'll see:

```
📦 Kubernetes Configuration Manager
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Active config: staging

Available configs:
  - production
  - staging
  - development

To switch configurations, use:
  kubeconfig-switch <config-name>

Example:
  kubeconfig-switch production
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## How It Works

1. The script sets `$KUBECONFIG` to `~/.kube/config.active`
2. `config.active` is a symlink pointing to one of your config files
3. When you run `kubeconfig-switch`, it updates the symlink
4. kubectl automatically uses the new config

## File Structure

```
~/.kube/
├── config.active -> config-files/staging.yaml  # Symlink
└── config-files/
    ├── production.yaml
    ├── staging.yaml
    └── development.yaml

~/.zsh_init/
└── init-kubeconfigs.sh  # Loaded on shell startup
```

## Troubleshooting

### Function not found

If `kubeconfig-switch` is not available:
1. Verify the script is in `~/.zsh_init/`
2. Check that your `~/.zshrc` sources `.zsh_init` scripts
3. Restart your terminal or run: `source ~/.zshrc`

### Config not switching

If kubectl still uses the old config:
1. Check that `~/.kube/config.active` points to the correct file:
   ```bash
   ls -la ~/.kube/config.active
   ```
2. Verify `$KUBECONFIG` is set:
   ```bash
   echo $KUBECONFIG
   ```

### No configs showing up

If no configs appear:
1. Ensure your config files are in `~/.kube/config-files/`
2. Ensure files have `.yaml` or `.yml` extension
3. Check file permissions (should be readable)

## Adding Configs on New Machines

To replicate this setup on another machine:

1. Clone the repository containing these scripts
2. Run `./install-kubeconfig-manager.sh`
3. Copy your kubectl config files to `~/.kube/config-files/`
4. Set the initial active config
5. Restart your terminal

## Uninstall

To remove the kubectl config manager:

```bash
rm ~/.zsh_init/init-kubeconfigs.sh
unset -f kubeconfig-switch
```

Then restart your terminal.
