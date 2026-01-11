# Troubleshooting Guide

This guide covers common issues and their solutions when using the system-lifecycle scripts.

## Table of Contents

- [APT Issues](#apt-issues)
- [Snap Issues](#snap-issues)
- [GNOME Extension Issues](#gnome-extension-issues)
- [Ubuntu Pro Issues](#ubuntu-pro-issues)
- [WSL-Specific Issues](#wsl-specific-issues)
- [Permission Issues](#permission-issues)
- [Network Issues](#network-issues)

---

## APT Issues

### APT Lock Error

**Symptoms:**
```
E: Could not get lock /var/lib/dpkg/lock-frontend
E: Unable to acquire the dpkg frontend lock
```

**Causes:**
- Another package manager is running (Software Center, unattended-upgrades)
- Previous apt operation was interrupted

**Solutions:**

1. Wait for the other process to finish:
   ```bash
   # Check what's holding the lock
   sudo lsof /var/lib/dpkg/lock-frontend
   ```

2. If no process is running, remove stale locks:
   ```bash
   sudo rm /var/lib/dpkg/lock-frontend
   sudo rm /var/lib/dpkg/lock
   sudo rm /var/cache/apt/archives/lock
   sudo dpkg --configure -a
   ```

3. Stop unattended-upgrades temporarily:
   ```bash
   sudo systemctl stop unattended-upgrades
   # Run your update, then restart
   sudo systemctl start unattended-upgrades
   ```

### Package Dependency Issues

**Symptoms:**
```
The following packages have unmet dependencies
```

**Solutions:**

1. Try fixing broken packages:
   ```bash
   sudo apt --fix-broken install
   ```

2. Update package lists and retry:
   ```bash
   sudo apt update
   sudo apt upgrade
   ```

3. Check for held packages:
   ```bash
   sudo apt-mark showhold
   # Remove hold if needed
   sudo apt-mark unhold <package>
   ```

### GPG Key Errors

**Symptoms:**
```
NO_PUBKEY <key_id>
The following signatures couldn't be verified
```

**Solutions:**

1. Re-add the GPG key:
   ```bash
   # For Microsoft packages
   curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/microsoft.gpg
   ```

2. Check keyring file permissions:
   ```bash
   ls -la /usr/share/keyrings/
   # Should be readable by all (644)
   ```

---

## Snap Issues

### Snap Refresh Failures

**Symptoms:**
```
error: cannot refresh "package": snap "package" has running apps
```

**Solutions:**

1. Close applications using the snap:
   ```bash
   # Find running snap apps
   snap list --all | grep -E "disabled|running"
   ```

2. Force refresh (use with caution):
   ```bash
   sudo snap refresh --ignore-running
   ```

### Snap Connection Issues

**Symptoms:**
```
error: cannot communicate with server
snap has no updates available
```

**Solutions:**

1. Check snap daemon status:
   ```bash
   sudo systemctl status snapd
   sudo systemctl restart snapd
   ```

2. Check network connectivity to snap store:
   ```bash
   curl -I https://api.snapcraft.io/
   ```

---

## GNOME Extension Issues

### Extensions Not Loading

**Symptoms:**
- Extension installed but not visible
- Extension shows as "Error" in Extensions app

**Solutions:**

1. Restart GNOME Shell:
   - Press `Alt+F2`, type `r`, press Enter
   - Or log out and log back in

2. Check extension compatibility:
   ```bash
   # Get GNOME Shell version
   gnome-shell --version

   # List installed extensions
   gnome-extensions list --enabled
   ```

3. View extension errors:
   ```bash
   journalctl -f -o cat /usr/bin/gnome-shell
   ```

### dconf Configuration Not Applied

**Symptoms:**
- Settings revert after reboot
- Configuration changes don't take effect

**Solutions:**

1. Ensure dconf is installed:
   ```bash
   sudo apt install dconf-cli
   ```

2. Manually load configuration:
   ```bash
   dconf load /org/gnome/shell/extensions/<extension>/ < config.dconf
   ```

3. Check for syntax errors in dconf file:
   ```bash
   dconf dump /org/gnome/shell/extensions/<extension>/
   ```

---

## Ubuntu Pro Issues

### Token Attachment Failures

**Symptoms:**
```
Failed to attach to Ubuntu Pro
Invalid token
```

**Solutions:**

1. Verify token validity at [ubuntu.com/pro](https://ubuntu.com/pro)

2. Check if already attached:
   ```bash
   pro status
   ```

3. Detach and re-attach:
   ```bash
   sudo pro detach
   sudo pro attach <token>
   ```

### USG Service Not Available

**Symptoms:**
```
Service usg is not available
```

**Solutions:**

1. Check Ubuntu Pro status:
   ```bash
   pro status --all
   ```

2. Ensure system is attached to Ubuntu Pro first

3. Enable USG service:
   ```bash
   sudo pro enable usg
   ```

---

## WSL-Specific Issues

### CIS Hardening Skipped

**Behavior:** CIS hardening is automatically skipped in WSL environments.

**Reason:** CIS benchmarks are designed for bare-metal or full VM installations. Many controls are not applicable in WSL's virtualized environment.

**Solution:** This is expected behavior. If you need CIS compliance, test on a full Ubuntu installation.

### Firmware Updates Skipped

**Behavior:** Firmware updates are skipped in WSL.

**Reason:** WSL doesn't have direct hardware access; firmware is managed by the Windows host.

### systemd Services Not Working

**Symptoms:**
```
System has not been booted with systemd
Failed to connect to bus
```

**Solutions:**

1. Enable systemd in WSL (WSL 2 only):
   Create/edit `/etc/wsl.conf`:
   ```ini
   [boot]
   systemd=true
   ```

2. Restart WSL:
   ```powershell
   wsl --shutdown
   ```

---

## Permission Issues

### Script Must Be Run as Root

**Symptoms:**
```
This script must be run as root (use sudo)
```

**Solution:**
```bash
sudo ./script.sh
```

### Log Directory Permission Denied

**Symptoms:**
```
mkdir: cannot create directory '/var/log/system-lifecycle'
```

**Solutions:**

1. Create directory with sudo:
   ```bash
   sudo mkdir -p /var/log/system-lifecycle
   sudo chown root:adm /var/log/system-lifecycle
   sudo chmod 775 /var/log/system-lifecycle
   ```

2. Or run the script with sudo (recommended)

---

## Network Issues

### Internet Connectivity Check Failed

**Symptoms:**
```
No internet connectivity - required for package installation
```

**Solutions:**

1. Check basic connectivity:
   ```bash
   ping -c 3 8.8.8.8
   ping -c 3 google.com
   ```

2. Check DNS resolution:
   ```bash
   nslookup google.com
   ```

3. Check proxy settings (if behind corporate proxy):
   ```bash
   echo $http_proxy
   echo $https_proxy
   ```

### Download Timeouts

**Symptoms:**
```
curl: (28) Connection timed out
Failed to download
```

**Solutions:**

1. Retry the operation (may be temporary)

2. Check if URL is accessible:
   ```bash
   curl -I <url>
   ```

3. Try using a different mirror or wait for server availability

---

## General Debugging

### Enable Verbose Logging

Most scripts support these options:
- Remove `--quiet` flag for more output
- Check log files in `/var/log/system-lifecycle/`

### View Recent Logs

```bash
# List log files
ls -lt /var/log/system-lifecycle/

# View latest log
cat /var/log/system-lifecycle/$(ls -t /var/log/system-lifecycle/ | head -1)

# Follow logs in real-time
tail -f /var/log/system-lifecycle/*.log
```

### Run in Dry-Run Mode

Test what would happen without making changes:
```bash
sudo ./install-workstation.sh --dry-run
sudo ./update-system.sh --dry-run
```

---

## Getting Help

If you encounter issues not covered here:

1. Check the log files in `/var/log/system-lifecycle/`
2. Run with `--dry-run` to see what operations would be performed
3. Check the [GitHub Issues](https://github.com/your-repo/system-lifecycle/issues)
4. Create a new issue with:
   - Ubuntu version (`lsb_release -a`)
   - Script version (`./script.sh --version`)
   - Full error message
   - Relevant log output
