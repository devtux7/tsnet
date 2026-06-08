# OrbStack Ubuntu Tailscale SSH Setup

This repository provides a one-command setup script for accessing an OrbStack Ubuntu VM over Tailscale.

The default setup uses Tailscale SSH. That means you do not need to copy SSH keys between devices and you do not need to set a Linux password for SSH. Tailscale handles authentication and authorization with your tailnet identity and policy.

The goal is to:

- Reach the VM from another trusted device in your tailnet.
- Avoid router or modem port forwarding.
- Avoid exposing port 22 to the public internet.
- Avoid manual SSH key copying for personal tailnet workflows.
- Use terminal SSH and the Tailscale VS Code extension.

## Overview

If the other device is connected to the same Tailscale network, also known as the same tailnet, it can SSH to the Ubuntu VM by using the VM's Tailscale IP address:

```bash
ssh user@100.x.y.z
```

With Tailscale SSH enabled, the SSH client still speaks the SSH protocol, but Tailscale handles the authentication step. Access is controlled by your tailnet's SSH policy, not by copied SSH public keys or Linux account passwords.

This is different from making OpenSSH accept empty passwords. Empty-password OpenSSH is not recommended. It removes the host-level authentication boundary and trusts every permitted network path too much. Tailscale SSH is the right passwordless path because it keeps identity and authorization in Tailscale.

## Architecture

```text
Other device
  -> Tailscale client
  -> Encrypted tailnet
  -> OrbStack Ubuntu VM Tailscale IP
  -> Tailscale SSH
  -> Linux shell as an allowed local user
```

This flow does not open `22/tcp` on your router. The script configures UFW inside the VM so SSH is allowed on the `tailscale0` interface and denied on other interfaces.

## One-Command Setup

Run this inside the Ubuntu VM:

```bash
curl -fsSL https://raw.githubusercontent.com/devtux7/tsnet/main/scripts/setup-tailscale-ssh.sh | bash
```

The `| bash` part executes the downloaded script. Without it, `curl` only prints the script content.

During setup, the script runs `tailscale up`. If the VM is not already authenticated, Tailscale prints a login URL and, when supported by the installed Tailscale version, a QR code. Open the URL or scan the QR code with a trusted phone, complete the Tailscale login, and the script will continue after the VM joins your tailnet.

To set a Tailscale device name:

```bash
curl -fsSL https://raw.githubusercontent.com/devtux7/tsnet/main/scripts/setup-tailscale-ssh.sh | TAILSCALE_HOSTNAME=orbstack-ubuntu bash
```

## Local Usage

From a local clone:

```bash
bash scripts/setup-tailscale-ssh.sh
```

The script may ask for `sudo`.

## What The Script Does

- Checks that it is running on Ubuntu.
- Installs `ca-certificates`, `curl`, `ufw`, and Tailscale.
- Runs `tailscale up` and lets Tailscale generate the browser login URL when needed.
- Enables Tailscale SSH by default.
- Restricts `22/tcp` to the `tailscale0` interface with UFW.
- Prints SSH connection details.

## Environment Variables

| Variable | Default | Description |
| --- | --- | --- |
| `SSH_ACCESS_MODE` | `tailscale` | `tailscale` enables Tailscale SSH only. `openssh` uses classic OpenSSH. `both` enables both. |
| `TAILSCALE_HOSTNAME` | Current hostname | Tailscale device name. |
| `TAILSCALE_LOGIN_QR` | `true` | Shows a QR code for the Tailscale login URL when the installed Tailscale CLI supports it. |
| `TAILSCALE_QR_FORMAT` | `small` | QR code format passed to `tailscale up --qr-format`. Use `small` or `large`. |
| `LOCKDOWN_SSH_TO_TAILSCALE` | `true` | Restricts SSH to the Tailscale interface with UFW. |
| `FORCE_LOCKDOWN` | `false` | Applies the firewall restriction even when the script is running from a non-Tailscale SSH session. |

Classic OpenSSH mode supports these additional variables:

| Variable | Default | Description |
| --- | --- | --- |
| `TARGET_USER` | User that invoked `sudo` | Linux user whose SSH keys should be configured. |
| `SSH_PUBLIC_KEY` | Empty | Public key to append to `authorized_keys`. |
| `GITHUB_USER` | Empty | Imports public keys from `https://github.com/USER.keys`. |
| `AUTHORIZED_KEYS_FILE` | Empty | Local authorized keys file to import. |
| `IMPORT_MAC_ED25519_KEY` | `true` | Imports `/mnt/mac/Users/$USER/.ssh/id_ed25519.pub` when present inside OrbStack. |
| `DISABLE_PASSWORD_AUTH` | `false` | Disables SSH password login when set to `true`. Add and test a key first. |
| `ENABLE_TAILSCALE_SSH` | `false` | Also enables Tailscale SSH when `SSH_ACCESS_MODE=openssh`. |

## Recommended Setup

1. Run the script inside the Ubuntu VM:

```bash
curl -fsSL https://raw.githubusercontent.com/devtux7/tsnet/main/scripts/setup-tailscale-ssh.sh | bash
```

2. Open the Tailscale login URL, or scan the printed QR code, when prompted.

3. Note the Tailscale IP address printed at the end.

4. From another device connected to the same tailnet, test SSH:

```bash
ssh user@100.x.y.z
```

If your tailnet uses the default Tailscale SSH policy, you can usually connect to your own devices as a non-root user. If you customized your tailnet policy, make sure it includes an SSH rule that allows your source device or user to connect to this VM as the target Linux username.

## VS Code

The recommended path is the Tailscale extension for Visual Studio Code.

On the other device:

1. Install Tailscale and sign in to the same tailnet.
2. Install VS Code.
3. Install the Tailscale extension.
4. Open the Tailscale machine explorer.
5. Select the VM and attach VS Code to it, or start a terminal session.

If your local username is different from the Linux username on the VM, add a local SSH config entry with the remote username:

```sshconfig
Host orbstack-ubuntu.example.ts.net
  User user
```

You can get the MagicDNS name from Tailscale. You can also use the Tailscale IP address directly with normal terminal SSH.

## Classic OpenSSH Mode

If you want the older OpenSSH behavior with SSH keys or password authentication, run:

```bash
curl -fsSL https://raw.githubusercontent.com/devtux7/tsnet/main/scripts/setup-tailscale-ssh.sh | SSH_ACCESS_MODE=openssh bash
```

To enable both Tailscale SSH and OpenSSH:

```bash
curl -fsSL https://raw.githubusercontent.com/devtux7/tsnet/main/scripts/setup-tailscale-ssh.sh | SSH_ACCESS_MODE=both bash
```

OpenSSH mode is useful when a tool specifically needs the host OpenSSH server. For normal terminal access and Tailscale's VS Code workflow, prefer the default Tailscale SSH mode.

## Security Notes

- Do not enable empty-password OpenSSH. Use Tailscale SSH for passwordless access.
- Tailscale SSH access depends on your tailnet SSH policy.
- The script applies UFW rules that allow `22/tcp` on `tailscale0` and deny `22/tcp` elsewhere.
- Use Tailscale ACLs and SSH rules to limit which users and devices can access the VM.
- If OrbStack has `Expose ports to LAN` enabled, services listening on `0.0.0.0` may be visible from the LAN. This script applies a UFW restriction for SSH.

## Checks

Inside the Ubuntu VM:

```bash
tailscale status
tailscale ip -4
tailscale debug prefs
sudo ufw status verbose
```

From another device:

```bash
tailscale status
ssh -v user@100.x.y.z
```

## Troubleshooting

SSH asks for a password:

- Re-run the script to ensure Tailscale SSH is enabled.
- Check that the target VM is online in `tailscale status`.
- Check your tailnet SSH policy. Tailscale SSH must be allowed for the source user/device and target Linux username.
- Use the Tailscale VS Code extension if your goal is VS Code access.

SSH timeout:

- Is the other device signed in to Tailscale?
- Is the VM online in `tailscale status`?
- Does `sudo ufw status verbose` show the `tailscale0` allow rule?
- Do your Tailscale ACLs allow `22/tcp` access?

Wrong username:

- Use the Linux username that exists inside the VM.
- If using MagicDNS with VS Code, add a local SSH config entry that sets `User`.

## References

- Tailscale SSH: https://tailscale.com/docs/features/tailscale-ssh
- Tailscale VS Code extension: https://tailscale.com/docs/integrations/vscode-extension
- Tailscale `up` command: https://tailscale.com/kb/1241/tailscale-up
- Tailscale QR code setup: https://tailscale.com/docs/features/access-control/device-management/how-to/set-up-qr-code
- Tailscale Linux install: https://tailscale.com/docs/install/linux
- OrbStack SSH access: https://docs.orbstack.dev/machines/ssh
- OrbStack Linux networking: https://docs.orbstack.dev/machines/network
