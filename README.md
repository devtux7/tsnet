# OrbStack Ubuntu Tailscale SSH & Exit Node Setup

This repository provides a one-command setup script for accessing an OrbStack Ubuntu VM over Tailscale SSH, configuring it as a high-performance **Tailscale Exit Node (VPN)**, and applying critical network throughput/latency optimizations.

The default setup uses Tailscale SSH and configures the VM as a high-performance exit node.

The goal is to:

- Reach the VM from another trusted device in your tailnet.
- Use the VM as a secure VPN/Exit Node for all internet traffic.
- Apply Linux sysctl optimizations (including BBR congestion control) to eliminate network bottlenecks.
- Avoid router or modem port forwarding.
- Avoid exposing port 22 to the public internet.

## Overview

If the other device is connected to the same Tailscale network (tailnet), it can SSH to the Ubuntu VM by using the VM's Tailscale IP address:

```bash
ssh user@100.x.y.z
```

With Tailscale SSH enabled, the SSH client still speaks the SSH protocol, but Tailscale handles the authentication step. Access is controlled by your tailnet's SSH policy.

## Architecture

```text
Other device
  -> Tailscale client
  -> Encrypted tailnet (VPN traffic routed via Exit Node VM)
  -> OrbStack Ubuntu VM Tailscale IP
  -> Tailscale SSH / IP Forwarding / BBR & Socket Buffer Optimizations
  -> Linux shell / WAN Internet
```

## Modular Structure

Following the modular design pattern, the project is divided into dedicated scripts under the `scripts/modules/` directory:

- **[setup-tailscale-ssh.sh](file:///Users/serkan/Developer/Tailscale/tailSSH/scripts/setup-tailscale-ssh.sh)**: Main orchestrator script. Supports both local running and remote running (`curl | bash`) by automatically loading submodules.
- **[utils.sh](file:///Users/serkan/Developer/Tailscale/tailSSH/scripts/modules/utils.sh)**: General helper utilities (OS detection, package installer wrapper, root privilege checks).
- **[sysctl.sh](file:///Users/serkan/Developer/Tailscale/tailSSH/scripts/modules/sysctl.sh)**: Configures IP forwarding (`net.ipv4.ip_forward=1`) and optimizes network buffers, BBR congestion control, TCP window scaling, and interface queue backlogs to avoid bottlenecks.
- **[firewall.sh](file:///Users/serkan/Developer/Tailscale/tailSSH/scripts/modules/firewall.sh)**: Restricts SSH port 22 to the `tailscale0` interface and configures UFW's default forward policy to `ACCEPT` so routed VPN traffic flows correctly. Also preserves OrbStack macOS host local connectivity.
- **[tailscale.sh](file:///Users/serkan/Developer/Tailscale/tailscale.sh)**: Installs Tailscale, registers the device with custom settings (SSH, exit node advertisement, login QR code), and displays setup summaries.

## One-Command Setup

Run this inside the Ubuntu VM:

```bash
curl -fsSL https://raw.githubusercontent.com/devtux7/tsnet/main/scripts/setup-tailscale-ssh.sh | bash
```

To configure with specific settings (e.g. customized hostname):

```bash
curl -fsSL https://raw.githubusercontent.com/devtux7/tsnet/main/scripts/setup-tailscale-ssh.sh | TAILSCALE_HOSTNAME=my-vpn-node bash
```

## Environment Variables

You can customize the script's behavior using the following environment variables:

| Variable | Default | Description |
| --- | --- | --- |
| `TAILSCALE_EXIT_NODE` | `true` | When `true`, advertises the machine as an exit node and enables IP forwarding. |
| `TAILSCALE_OPTIMIZE` | `true` | Applies sysctl network configurations for high-speed VPN/routing traffic (BBR, queue sizes, buffers). |
| `TAILSCALE_HOSTNAME` | Current hostname | Tailscale device name. |
| `TAILSCALE_LOGIN_QR` | `true` | Shows a QR code for the Tailscale login URL when the installed Tailscale CLI supports it. |
| `TAILSCALE_QR_FORMAT` | `small` | QR code format passed to `tailscale up --qr-format`. Use `small` or `large`. |
| `LOCKDOWN_SSH_TO_TAILSCALE` | `true` | Restricts SSH to the Tailscale interface with UFW. |
| `ALLOW_ORBSTACK_HOST_SSH` | `true` | Keeps local SSH from the macOS OrbStack host/bridge network working. |
| `ORBSTACK_SSH_ALLOW_CIDRS` | `198.19.0.0/16` | Space-separated CIDRs allowed for local OrbStack host/bridge SSH. |
| `FORCE_LOCKDOWN` | `false` | Applies the firewall restriction even when the script is running from a non-Tailscale SSH session. |

## Network Optimizations Details

To avoid bandwidth bottlenecks during high VPN usage, the script automatically applies these sysctl configurations:
- **BBR Congestion Control**: Replaces traditional TCP Reno/Cubic with Google's BBR to decrease latency and increase throughput.
- **Socket Buffers**: Increases `rmem_max`/`wmem_max` to `16MB` to handle high-bandwidth latency product paths.
- **Interface Queue Backlog**: Increases queue depth to `10000` to prevent drops on fast interfaces.
- **TCP Window Scaling**: Enabled to utilize larger window sizes.

## Exit Node Activation (Crucial Step)

After running the script, you **must approve** the exit node in your Tailscale Admin Console:

1. Open the [Tailscale Admin Console](https://login.tailscale.com/admin/machines).
2. Find your device, click the **three dots** icon next to it, and select **Edit route settings**.
3. Enable **Use as exit node**.

## References

- Tailscale SSH: https://tailscale.com/docs/features/tailscale-ssh
- Tailscale Exit Nodes: https://tailscale.com/kb/1103/exit-nodes
- Tailscale VS Code extension: https://tailscale.com/docs/integrations/vscode-extension
- Tailscale QR code setup: https://tailscale.com/docs/features/access-control/device-management/how-to/set-up-qr-code
