#!/bin/bash

# Exit on errors
set -e

# Main function
main() {
    # Constants
    ct_ostype="alpine"
    ct_id=$(get_container_id)
    ct_template=$(get_container_template "$ct_ostype")
    ct_storage="local-zfs"
    ct_disk_size="8G"
    ct_memory="2048"
    ct_cores="2"
    ct_bridge="vmbr0"
    ct_ip="dhcp"
    ct_hostname="samba"
    ct_arch="amd64"

    echo "### ------  LXC Container Setup ------ ###"
    echo "        Container ID (ct_id): $ct_id"
    echo "      Hostname (ct_hostname): $ct_hostname"
    echo "         OS Type (ct_ostype): $ct_ostype"
    echo "      Template (ct_template): $ct_template"
    echo "        Storage (ct_storage): $ct_storage"
    echo "    Disk Size (ct_disk_size): $ct_disk_size"
    echo "          Memory (ct_memory): $ct_memory"
    echo "        CPU Cores (ct_cores): $ct_cores"
    echo "  Network Bridge (ct_bridge): $ct_bridge"
    echo "          Network IP (ct_ip): $ct_ip"
    echo "      Architecture (ct_arch): $ct_arch"

    # Create the container
    create_container

    # Configure bind mounts for host users
    #configure_mounts "$ct_id"

    # Start the container
    start_container 

    # Output container status
    echo "### ------  LXC Container Setup Complete ------ ###"
    pct status "$ct_id"
}

get_container_template() {
    local ostype="${1:-$ct_ostype}"
    if [[ -z "$ostype" ]]; then
        echo "Error: No ostype provided. Usage: get_container_template --ostype <ostype>"
        return 1
    fi

    # Update the template catalog
	if ! pveam update > /dev/null 2>&1; then
		echo "Error: Unable to update template catalog. Ensure you can connect to: http://download.proxmox.com"
		return 2
	fi
	
    # Find the latest matching template
    local template
    template=$(pveam available -section system | awk -v os="$ostype" '$2 ~ os {latest=$2} END {print latest}')

    if [[ -z "$template" ]]; then
        echo "Error: No template found for OS '$ostype'. Ensure templates are available in the system section."
        return 3
    fi

    # Download the latest matching template
	output=$(pveam download local "$template" 2>&1)
	case "$output" in
		*"no need to download"*)
			echo "$template";;
		*"downloading"*)
			echo "$template";;
		*)
			echo "Error: Failed to download template '$template'. Ensure you can connect to: http://download.proxmox.com"
			return 4;;
	esac
}

get_container_id() {
    local existing_ids
    existing_ids=$(pct list | awk 'NR>1 {print $1}' | sort -n)
    local next_id=100
    while echo "$existing_ids" | grep -q "^$next_id$"; do
        ((next_id++))
    done
    echo "$next_id"
}

create_container() {
	local id="${1:-$ct_id}"
	local ostemplate="${2:-local:vztmpl/$ct_template}"
	local storage="${3:-$ct_storage}"
	local disk_size="${4:-${ct_disk_size%G}}"
	local memory="${5:-$ct_memory}"
	local cores="${6:-$ct_cores}"
	local bridge="${7:-$ct_bridge}"
	local ip="${8:-$ct_ip}"
	local hostname="${9:-$ct_hostname}"
	local arch="${10:-$ct_arch}"

    echo "### ------ Creating lxc container $hostname ($id) ------ ###"
    if pct create \
        "$id" "$ostemplate" \
        --rootfs "$storage:$disk_size" \
        --hostname "$hostname" \
        --memory "$memory" \
        --cores "$cores" \
        --net0 "name=eth0,bridge=$bridge,ip=$ip" \
        --features "nesting=0,keyctl=1" \
        --unprivileged 0; then
        echo "lxc container $hostname ($id) created successfully"
    else
        echo "Error: Failed to create container $id" >&2
        exit 1
    fi
}

configure_mounts() {
    local id="$1"
    echo -e "### ------ Configuring bind mounts for container $id ------ ###"

    # Ensure destination files exist in the container
    pct exec "$id" -- touch /etc/passwd /etc/shadow /etc/group

    # Set bind mounts
    if pct set "$id" \
        -mp0 /etc/passwd,mp=/etc/passwd,ro=1 \
        -mp1 /etc/shadow,mp=/etc/shadow,ro=1 \
        -mp2 /etc/group,mp=/etc/group,ro=1; then
        echo "Bind mounts configured for container $id"
    else
        echo "Error: Failed to configure bind mounts for container $id" >&2
        exit 1
    fi
}

start_container() {
    local id="${1:-$ct_id}"
    echo -e "### ------ Starting container $id ------ ###"
    if pct start "$id"; then
        echo "Container $id started successfully"
    else
        echo "Error: Failed to start container $id" >&2
        exit 1
    fi
}

# Run the script
main
