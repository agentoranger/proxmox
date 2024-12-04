#!/bin/bash

# Exit on errors
set -e

# Main function
main() {
	# Constants
	ct_ostype="alpine"													# Operating System: alpine | archlinux | centos | debian | devuan | fedora | gentoo | nixos | opensuse | ubuntu | unmanaged
	ct_vmid=$(get_container_id)											# Container ID:		Integer to define the container id (100 - 999999999)
	ct_template=$(get_container_template "$ct_ostype")					# Template:			String to define the LXC Template based on ct_ostype
	ct_storage="local-zfs"												# Disk Location:	String to define the proxmox storage
	ct_disk_size="8G"													# Disk size:		Integer in K, M, G, T (default = M)    
	ct_memory=$(awk '/MemTotal/ {print int($2 / 4096)}' /proc/meminfo)	# Memory size:		Integer in MB (default = 512)
	ct_cores=$(($(nproc) / 2))											# CPU Cores:		Integer (1 - 8192) (default = all) 
	ct_hostname="nasbeta"												# Hostname:			String to define the hostname
	ct_bridge="vmbr0"													# Network Bridge:	String to define the proxmox connection
	ct_hwaddr="52:54:10:01:01:64"										# MAC Address:      String to define the mac address (52:54:00:00:00:00)
	ct_ip4="10.1.1.100/24"												# IPv4 Address:		10.1.1.150/24 | dhcp
	ct_gw4="10.1.1.1"													# IPv4 Gateway:		10.1.1.1
	ct_ip6="dhcp"														# IPv6 Address:		2001:db8::100/64 | dhcp | slaac
	#ct_gw6="dhcp"														# IPv6 Gateway:		2001:db8::1
	ct_firewall="0"														# Firewall:			0=Disabled | 1=Enabled
	ct_onboot="1"														# Start On-Boot:	0=Disabled | 1=Enabled	
	ct_swap="0"															# Swap size:		0=Disabled | Integer in MB
	ct_console="0"														# Console Device:	0=Disabled | 1=Enabled
	ct_cmode="shell"													# Console Mode:		console | shell | tty
	ct_tty="0"															# ttys available:	Integer (0 - 6) (default = 2)
	ct_unprivileged="0"													# Unprivileged:		0=Disabled | 1=Enabled
	ct_description="nas.orange.guru"									# Description:		String to define the description
	ct_ssh_keys="KEY"													# Public SSH keys:  One key per line, OpenSSH format

	# Create the container
	create_container

	# Configure bind mounts for host users
	#configure_mounts "$ct_vmid"

	# Start the container
	start_container 

	# Output container status
	pct status "$ct_vmid"
}

get_container_template() {
	local ostype="${1:-$ct_ostype}"
	if [[ -z "$ostype" ]]; then
		echo "Error: No ostype provided. Usage: get_container_template <ostype>"
		return 1
	fi

	# Update lxc template catalog
	if ! pveam update > /dev/null 2>&1; then
		echo "Error: Failed to update template catalog."
		return 2
	fi
	
	# Find latest matching template
	local template
	template=$(pveam available -section system | awk -v os="$ostype" '$2 ~ os {latest=$2} END {print latest}')

	if [[ -z "$template" ]]; then
		echo "Error: No template found for OS '$ostype'."
		return 3
	fi

	# Download latest matching template
	output=$(pveam download local "$template" 2>&1)
	case "$output" in
		*"no need to download"*)
			echo "$template";;
		*"downloading"*)
			echo "$template";;
		*)
			echo "Error: Failed to download template '$template'."
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
	local vmid="${1:-$ct_vmid}"
	local ostemplate="${2:-local:vztmpl/$ct_template}"
	local storage="${3:-$ct_storage}"
	local disk_size="${4:-${ct_disk_size%G}}"
	local memory="${5:-$ct_memory}"
	local cores="${6:-$ct_cores}"
	local hostname="${7:-$ct_hostname}"
	local onboot="${8:-$ct_onboot}"
	local swap="${9:-$ct_swap}"
	local console="${10:-$ct_console}"
	local cmode="${11:-$ct_cmode}"
	local tty="${12:-$ct_tty}"
    local unprivileged="${13:-$ct_unprivileged}"
	local bridge="${14:-$ct_bridge}"
	local description="${14:-$ct_description}"
	local hwaddr="${15:-$ct_hwaddr}"
	local ip4="${16:-$ct_ip4}"
	local gw4="${17:-$ct_gw4}"
	local ip6="${18:-$ct_ip6}"
	local gw6="${19:-$ct_gw6}"
	local firewall="${20:-$ct_firewall}"
	
	local net0="name=eth0,bridge=$bridge,firewall=$firewall"
		[ -n "$hwaddr" ] && net0+=",hwaddr=$hwaddr"
		[ -n "$ip4" ]    && net0+=",ip=$ip4"
		[ -n "$gw4" ]    && net0+=",gw=$gw4"
		[ -n "$ip6" ]    && net0+=",ip6=$ip6"
		[ -n "$gw6" ]    && net0+=",gw6=$gw6"

	echo "### ------  LXC Container Configuration ------ ###"
	echo ""
	echo "       Container ID: $ct_vmid"
	echo "           Hostname: $ct_hostname"
	echo "   Operating System: $ct_ostype"
	echo "           Template: $ct_template"
	echo "          CPU Cores: $ct_cores"
	echo "             Memory: $ct_memory"
	echo "            Storage: $ct_storage"
	echo "          Disk Size: $ct_disk_size"
	echo "     Network Bridge: $ct_bridge"
	echo "        MAC Address: $ct_hwaddr"
	echo "  IP Address (IPv4): $ct_ip4"
	echo "  IP Address (IPv6): $ct_ip6"
	echo ""
	echo "### ------ Creating LXC Container: $hostname ($vmid) ------ ###"
	
	if pct create "$vmid" "$ostemplate" \
		--rootfs "$storage:$disk_size,acl=0,quota=0,replicate=0" \
		--memory "$memory" \
		--cores "$cores" \
		--hostname "$hostname" \
		--onboot "$onboot" \
		--swap "$swap" \
		--console "$console" \
		--cmode "$cmode" \
		--tty "$tty" \
		--unprivileged "$unprivileged" \
		--tty "$tty" \
		--description "$description" \
		--net0 "$net0" \
		--unprivileged "$unprivileged" \
		--features "nesting=0,keyctl=1" ; then
		echo "[INFO] - LXC Container $hostname ($vmid) created successfully"
	else
		echo "[ERROR] - Failed to create container $hostname ($vmid)" >&2
		exit 1
	fi
}

configure_mounts() {
	local vmid="${1:-$ct_vmid}"
	echo "### ------ Configuring bind mounts: $hostname ($vmid) ------ ###"

	## Ensure destination files exist in the container
	#pct exec "$vmid" -- touch /etc/passwd /etc/shadow /etc/group

	# Set bind mounts
	if pct set "$vmid" \
		-mp0 /etc/passwd,mp=/etc/passwd,ro=1 \
		-mp1 /etc/shadow,mp=/etc/shadow,ro=1 \
		-mp2 /etc/group,mp=/etc/group,ro=1; then
		echo "[INFO] - Bind mounts configured for container $vmid"
	else
		echo "[ERROR] - Failed to configure bind mounts for container $vmid" >&2
		exit 1
	fi
}

start_container() {
	local vmid="${1:-$ct_vmid}"
	echo -e "### ------ Starting LXC Container: $hostname ($vmid) ------ ###"
	if pct start "$vmid"; then
		echo "[INFO] - Container $vmid started successfully"
	else
		echo "[ERROR] - Failed to start container $vmid" >&2
		exit 1
	fi
}

# Run the script
main
