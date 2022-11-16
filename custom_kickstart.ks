# Choosing mode (graphical|text|cmdline [--non-interactive])
text

# Use network installation
url --mirrorlist https://mirrors.fedoraproject.org/mirrorlist?repo=fedora-37&arch=x86_64

# Initial Setup Agent on first boot
firstboot --disabled

# System language
# lang en_US.UTF-8
# Keyboard layout
# keyboard --vckeymap=us --xlayouts="us"
# System timezone
# timezone Etc/UTC --utc

# Network information
network --bootproto=dhcp --device=link --onboot=on
network --hostname=fedora.local

# Root password
rootpw --lock
# User password
user --name=admin --groups=wheel --gecos=admin --password=P@ssw0rd

# Firewall configuration
firewall --enabled --ssh

# SELinux
selinux --enforcing

# Partitioning

## Clearing
ignoredisk --only-use=nvme0n1
zerombr
clearpart --all --initlabel --disklabel=gpt

## Partition layout
# autopart --nohome
autopart --type lvm --encrypted --passphrase P@ssw0rd --luks-version 2 

# Packages
%packages --retries=5 --timeout=20
@core
curl
git
zsh
neofetch
%end

# Services
services --enabled=sshd.service

# Reboot the system after installation.
reboot