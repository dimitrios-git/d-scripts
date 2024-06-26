#!/bin/bash

# Wait for kwallet
kwallet-query -l kdewallet > /dev/null

# Import SSH keys from the user's home directory
for KEY in $(ls $HOME/.ssh/id_* | grep -v \.pub); do
  ssh-add -q ${KEY} </dev/null
done

# Define a custom list of SSH keys
SSH_KEYS_LIST=(
	"/mnt/devel/dimitrios/deploywell/ansible/ansible_ssh_key"
	# Add more keys here
)

# Import SSH keys from the custom list
for KEY in ${SSH_KEYS_LIST[@]}; do
  if [ -f ${KEY} ]; then
    ssh-add -q ${KEY} </dev/null
  fi
done


