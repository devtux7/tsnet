# OrbStack Ubuntu Tailscale SSH Setup

This repository provides a one-command setup script for accessing an OrbStack Ubuntu VM over Tailscale with terminal SSH and VS Code Remote - SSH.

The goal is to:

- Reach the VM from another device or network.
- Avoid router or modem port forwarding.
- Avoid exposing port 22 to the public internet.
- Work on files and projects inside the VM with VS Code Remote - SSH.

## Overview

If the other device is connected to the same Tailscale network, also known as the same tailnet, it can SSH to the Ubuntu VM by using the VM's Tailscale IP address:

```bash
ssh user@100.x.y.z
```

The most compatible setup for VS Code Remote - SSH is OpenSSH server inside the Ubuntu VM. Tailscale removes the need for public port forwarding, but VS Code Remote - SSH still expects an SSH server running on the remote machine.

OrbStack's built-in SSH endpoint is excellent for local `ssh orb` usage, but OrbStack documents it as accepting only `localhost` connections. For direct access from another device, install and run an SSH server inside the Linux machine.

## Architecture

```text
Other device
  -> Tailscale client
  -> Encrypted tailnet
  -> OrbStack Ubuntu VM Tailscale IP
  -> OpenSSH server
  -> Terminal or VS Code Remote - SSH
```

This flow does not open `22/tcp` on your router. The script configures UFW inside the VM so SSH is allowed on the `tailscale0` interface and denied on other interfaces.

## One-Command Setup

Once this repository is available on GitHub, run this inside the Ubuntu VM:

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/orbstack-ubuntu-tailscale-ssh/main/scripts/setup-tailscale-ssh.sh | bash
```

During setup, the script runs `tailscale up`. If the VM is not already authenticated, Tailscale prints a login URL. Open that URL in your browser, complete the Tailscale login, and the script will continue after the VM joins your tailnet.

To set a Tailscale device name:

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/orbstack-ubuntu-tailscale-ssh/main/scripts/setup-tailscale-ssh.sh | TAILSCALE_HOSTNAME=orbstack-ubuntu bash
```

## Local Usage

From a local clone:

```bash
bash scripts/setup-tailscale-ssh.sh
```

The script may ask for `sudo`.

## What The Script Does

- Checks that it is running on Ubuntu.
- Installs `ca-certificates`, `curl`, `openssh-server`, and `ufw`.
- Installs Tailscale using the official Linux install script.
- Runs `tailscale up` and lets Tailscale generate the browser login URL when needed.
- Enables the OpenSSH service.
- Writes a small SSH hardening config snippet.
- Optionally disables SSH password login.
- Optionally adds public keys to `~/.ssh/authorized_keys`.
- Restricts `22/tcp` to the `tailscale0` interface with UFW.
- Prints SSH and VS Code Remote - SSH connection details.

## Environment Variables

| Variable | Default | Description |
| --- | --- | --- |
| `TAILSCALE_HOSTNAME` | Current hostname | Tailscale device name. |
| `TARGET_USER` | User that invoked `sudo` | Linux user whose SSH keys should be configured. |
| `SSH_PUBLIC_KEY` | Empty | Public key to append to `authorized_keys`. |
| `GITHUB_USER` | Empty | Imports public keys from `https://github.com/USER.keys`. |
| `AUTHORIZED_KEYS_FILE` | Empty | Local authorized keys file to import. |
| `IMPORT_MAC_ED25519_KEY` | `true` | Imports `/mnt/mac/Users/$USER/.ssh/id_ed25519.pub` when present inside OrbStack. |
| `DISABLE_PASSWORD_AUTH` | `false` | Disables SSH password login when set to `true`. Add and test a key first. |
| `LOCKDOWN_SSH_TO_TAILSCALE` | `true` | Restricts SSH to the Tailscale interface with UFW. |
| `FORCE_LOCKDOWN` | `false` | Applies the firewall restriction even when the script is running from a non-Tailscale SSH session. |
| `ENABLE_TAILSCALE_SSH` | `false` | Also enables Tailscale SSH. This is not required for VS Code Remote - SSH. |

## Recommended Setup

1. Make sure the device you will connect from has an SSH key:

```bash
ssh-keygen -t ed25519
```

2. Run the script inside the Ubuntu VM. To provide your public key directly:

```bash
TAILSCALE_HOSTNAME=orbstack-ubuntu \
SSH_PUBLIC_KEY='ssh-ed25519 AAAA... your-key' \
DISABLE_PASSWORD_AUTH=true \
bash scripts/setup-tailscale-ssh.sh
```

3. Open the Tailscale login URL printed by the script when prompted.

4. Note the Tailscale IP address printed at the end.

5. From another device connected to the same tailnet, test SSH:

```bash
ssh user@100.x.y.z
```

## VS Code Remote - SSH

On the other device:

1. Install Tailscale and sign in to the same tailnet.
2. Install VS Code.
3. Install the `Remote - SSH` extension.
4. Test plain SSH from a terminal first:

```bash
ssh user@100.x.y.z
```

5. Add an entry to your local `~/.ssh/config`:

```sshconfig
Host orbstack-ubuntu
  HostName 100.x.y.z
  User user
  Port 22
  IdentityFile ~/.ssh/id_ed25519
```

6. In VS Code, run `Remote-SSH: Connect to Host...` and select `orbstack-ubuntu`.

If MagicDNS is enabled, you can use the Tailscale device name as `HostName`.

## Tailscale SSH vs OpenSSH

Tailscale SSH can be a good option for terminal access, and Tailscale ACLs can manage who is allowed to connect. VS Code Remote - SSH, however, expects an SSH server on the remote host. This repository installs OpenSSH server for that compatibility path.

You can also enable Tailscale SSH with `ENABLE_TAILSCALE_SSH=true`, but treat OpenSSH over the Tailscale IP as the default route for VS Code.

## Security Notes

- Test key-based SSH before disabling password login.
- The script applies UFW rules that allow `22/tcp` on `tailscale0` and deny `22/tcp` elsewhere.
- Use Tailscale ACLs to limit which users and devices can access the VM.
- If OrbStack has `Expose ports to LAN` enabled, services listening on `0.0.0.0` may be visible from the LAN. This script applies a UFW restriction for SSH.

## Checks

Inside the Ubuntu VM:

```bash
tailscale status
tailscale ip -4
systemctl status ssh
sudo ufw status verbose
```

From another device:

```bash
tailscale status
ssh -v user@100.x.y.z
```

## Troubleshooting

SSH timeout:

- Is the other device signed in to Tailscale?
- Is the VM online in `tailscale status`?
- Does `sudo ufw status verbose` show the `tailscale0` allow rule?
- Do your Tailscale ACLs allow `22/tcp` access?

Permission denied:

- Are you using the correct Linux username?
- Is your public key in `~/.ssh/authorized_keys` on the VM?
- Are the permissions correct: `700` for `~/.ssh` and `600` for `authorized_keys`?

VS Code cannot connect:

- Test `ssh user@100.x.y.z` from a terminal first.
- Check `HostName`, `User`, and `IdentityFile` in your VS Code Remote - SSH config.
- Make sure the VM has enough memory for the VS Code remote server.

## References

- Tailscale Linux install: https://tailscale.com/docs/install/linux
- Tailscale SSH Linux VM guide: https://tailscale.com/docs/how-to/connect-ssh-linux-vm
- Tailscale SSH: https://tailscale.com/docs/features/tailscale-ssh
- OrbStack SSH access: https://docs.orbstack.dev/machines/ssh
- OrbStack Linux networking: https://docs.orbstack.dev/machines/network
- Ubuntu OpenSSH server: https://documentation.ubuntu.com/server/how-to/security/openssh-server/
- VS Code Remote - SSH: https://code.visualstudio.com/docs/remote/ssh
