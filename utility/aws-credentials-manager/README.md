# AWS Credentials Manager

A simple tool to manage multiple AWS credentials files and easily switch between them.

## Overview

This tool provides:
- **Centralized credentials management**: Store all your AWS credentials in `~/.aws/credentials-files/`
- **Easy switching**: Use `aws-switch <credentials-name>` to switch between credentials
- **Visual feedback**: See which credentials are active when you open a terminal
- **Symlink-based**: Uses a symlink at `~/.aws/credentials` that points to your active credentials file
- **Automatic backup**: Backs up existing static credentials files before converting to symlink management

## Installation

### Quick Install

Run the installation script from the `script` directory:

```bash
./install-aws-credentials-manager.sh
```

This will:
1. Create `~/.zsh_init` directory (if needed)
2. Copy `init-aws-credentials.sh` to `~/.zsh_init/`
3. Create `~/.aws/credentials-files` directory
4. Verify your shell configuration
5. Check for existing credentials files

### Manual Install

If you prefer to install manually:

1. Copy the init script:
   ```bash
   mkdir -p ~/.zsh_init
   cp init-aws-credentials.sh ~/.zsh_init/
   chmod +x ~/.zsh_init/init-aws-credentials.sh
   ```

2. Add to your `~/.zshrc` (if not already present):
   ```bash
   for file in $(find ~/.zsh_init/*.sh -type f); do source "$file"; done
   ```

3. Create the credentials directory:
   ```bash
   mkdir -p ~/.aws/credentials-files
   ```

## Setup

### If you have existing credentials

If you have an existing `~/.aws/credentials` file:

1. **Move it to credentials-files**:
   ```bash
   mv ~/.aws/credentials ~/.aws/credentials-files/default
   ```

2. **Create the symlink**:
   ```bash
   ln -sf ~/.aws/credentials-files/default ~/.aws/credentials
   ```

3. **Restart your terminal** or source your shell config:
   ```bash
   source ~/.zshrc
   ```

### If starting fresh

1. **Create your credentials files** in `~/.aws/credentials-files/`:
   ```bash
   # Example format for a credentials file
   cat > ~/.aws/credentials-files/production <<EOF
   [default]
   aws_access_key_id = YOUR_ACCESS_KEY_ID
   aws_secret_access_key = YOUR_SECRET_ACCESS_KEY
   EOF
   ```

2. **Set the initial active credentials**:
   ```bash
   ln -sf ~/.aws/credentials-files/production ~/.aws/credentials
   ```

3. **Restart your terminal** or source your shell config:
   ```bash
   source ~/.zshrc
   ```

## Usage

### View Available Credentials

Simply run the command without arguments:

```bash
aws-switch
```

Output:
```
Usage: aws-switch <credentials-name>

Available credentials:
    production
  * staging (active)
    development
```

### Switch Credentials

Switch to different AWS credentials:

```bash
aws-switch production
```

Output:
```
Switched to AWS credentials: production
```

### Startup Information

When you open a new terminal, you'll see:

```
🔑 AWS Credentials Manager
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Active credentials: staging

Available credentials:
  - production
  - staging
  - development

To switch credentials, use:
  aws-switch <credentials-name>

Example:
  aws-switch production
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## How It Works

1. The script sets `$AWS_SHARED_CREDENTIALS_FILE` to `~/.aws/credentials`
2. `~/.aws/credentials` is a symlink pointing to one of your credentials files
3. When you run `aws-switch`, it updates the symlink
4. AWS CLI automatically uses the new credentials

## File Structure

```
~/.aws/
├── credentials -> credentials-files/staging  # Symlink
├── credentials-files/
│   ├── production
│   ├── staging
│   └── development
└── config  # AWS config file (regions, output format, etc.)

~/.zsh_init/
└── init-aws-credentials.sh  # Loaded on shell startup
```

## AWS Credentials File Format

Each credentials file should follow the standard AWS credentials format:

```ini
[default]
aws_access_key_id = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

[profile-name]
aws_access_key_id = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

## Security Best Practices

1. **Secure file permissions**: Ensure credentials files are only readable by you:
   ```bash
   chmod 600 ~/.aws/credentials-files/*
   ```

2. **Never commit credentials**: Add credentials files to `.gitignore`:
   ```bash
   echo "credentials-files/" >> ~/.aws/.gitignore
   ```

3. **Use IAM roles when possible**: For EC2 instances and other AWS services, prefer IAM roles over credentials files

4. **Rotate credentials regularly**: Update your AWS access keys periodically

5. **Use different credentials per environment**: Keep production, staging, and development credentials separate

## Troubleshooting

### Function not found

If `aws-switch` is not available:
1. Verify the script is in `~/.zsh_init/`
2. Check that your `~/.zshrc` sources `.zsh_init` scripts
3. Restart your terminal or run: `source ~/.zshrc`

### Credentials not switching

If AWS CLI still uses old credentials:
1. Check that `~/.aws/credentials` points to the correct file:
   ```bash
   ls -la ~/.aws/credentials
   ```
2. Verify `$AWS_SHARED_CREDENTIALS_FILE` is set:
   ```bash
   echo $AWS_SHARED_CREDENTIALS_FILE
   ```
3. Test with AWS CLI:
   ```bash
   aws sts get-caller-identity
   ```

### No credentials showing up

If no credentials appear:
1. Ensure your credentials files are in `~/.aws/credentials-files/`
2. Check file permissions (should be readable)
3. Verify files contain valid AWS credentials format

### Static file warning

If you see "Active credentials: (static file - not managed)":
- Your `~/.aws/credentials` is a regular file, not a symlink
- Use `aws-switch` to convert it (it will automatically back up the existing file)
- Or manually move it: `mv ~/.aws/credentials ~/.aws/credentials-files/default`

## Adding Credentials on New Machines

To replicate this setup on another machine:

1. Clone the repository containing these scripts
2. Run `./install-aws-credentials-manager.sh`
3. Copy your AWS credentials files to `~/.aws/credentials-files/`
4. Set the initial active credentials
5. Restart your terminal

**Note**: Never commit actual credentials to git. Only commit the management scripts.

## Integration with AWS CLI

This credentials manager works seamlessly with:
- AWS CLI v1 and v2
- AWS SDKs (boto3, aws-sdk-js, etc.)
- Terraform
- Any tool that respects `AWS_SHARED_CREDENTIALS_FILE` or reads from `~/.aws/credentials`

## Uninstall

To remove the AWS credentials manager:

```bash
rm ~/.zsh_init/init-aws-credentials.sh
unset -f aws-switch
```

Then restart your terminal.

If you want to convert back to a static credentials file:

```bash
# Remove symlink and copy the file content
cp ~/.aws/credentials ~/.aws/credentials.static
rm ~/.aws/credentials
mv ~/.aws/credentials.static ~/.aws/credentials
```
