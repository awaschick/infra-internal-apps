# This file must be called with a `source` command in `start_complete.sh` or other
# script that defines project directory and other operational constants.
# Launching this directly will not work!

account_name=$(set_local_config "aws" "account-name")
access_key=$(set_local_config "aws" "aws-access-key")
secret_key=$(set_local_config "aws" "aws-secret")

credentials_path="${HOME}/.aws/credentials-files"
mkdir -p "${credentials_path}"
credentials_filename="${account_name}"

cat <<EOF > "${credentials_path}/${credentials_filename}"
[default]
aws_access_key_id = $access_key
aws_secret_access_key = $secret_key
EOF

echo
echo -e "${text_bold}${text_underline}LOCAL AWS CREDENTIALS SETUP${text_normal}"
echo
echo -e "Successfully updated credentials for AWS account ${text_bold}${account_name}${text_normal}, saved as \n  ${text_bold}${credentials_path}/${credentials_filename}${text_normal}"
echo
echo -e "If you install the ${text_underline}AWS Credentials Manager${text_normal} found in the ${text_bold}utility${text_normal} directory of this repo, you can quickly activate and deactivate multiple AWS credentials. If already installed, run ${text_bold}aws-switch ${account_name}${text_normal} to activate it now."
