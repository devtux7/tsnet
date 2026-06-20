# OrbStack Ubuntu Setup Script

This repository provides a modular, interactive setup script (`ubuntu.sh`) for installing packages, configuring network settings, and setting up VPN connections like **Tailscale SSH & Exit Nodes**.

## Features

- **Interactive Menu**: Choose what software or configurations to apply.
- **Tailscale SSH & Exit Node**: Reach your VM securely, use it as a high-speed VPN/Exit Node, and authenticate with Tailscale SSH.
- **Network Buffers & BBR Tuning**: Fine-tune TCP buffer sizes and TCP congestion control (BBR) to prevent network bottlenecks.
- **Firewall Integration**: Automatically restricts SSH to Tailscale interfaces while keeping local OrbStack host connectivity working.

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

The project is structured with modularity in mind under the `modules/` directory:

- **[ubuntu.sh](file:///Users/serkan/Developer/Tailscale/tailSSH/ubuntu.sh)**: Main orchestrator script. Displays the interactive menu, handles arguments, and sources modules. Supports both local running and remote running (`curl | bash`).
- **[modules/utils.sh](file:///Users/serkan/Developer/Tailscale/tailSSH/modules/utils.sh)**: General helper utilities (OS detection, package installer wrapper, root privilege checks).
- **[modules/sysctl.sh](file:///Users/serkan/Developer/Tailscale/tailSSH/modules/sysctl.sh)**: Configures IP forwarding (`net.ipv4.ip_forward=1`) and applies TCP buffers, Google BBR congestion control, TCP window scaling, and interface queue backlogs to avoid bottlenecks.
- **[modules/firewall.sh](file:///Users/serkan/Developer/Tailscale/tailSSH/modules/firewall.sh)**: Restricts SSH port 22 to the `tailscale0` interface and configures UFW's default forward policy to `ACCEPT`. Also preserves OrbStack macOS host local connectivity.
- **[modules/tailscale.sh](file:///Users/serkan/Developer/Tailscale/tailSSH/modules/tailscale.sh)**: Installs Tailscale, registers the device with custom settings (SSH, exit node advertisement, login QR code), and displays setup summaries.
- **[modules/wireguard.sh](file:///Users/serkan/Developer/Tailscale/tailSSH/modules/wireguard.sh)**: Placeholder for future Wireguard VPN configurations.

## One-Command Setup

Run this inside the Ubuntu VM:

```bash
curl -fsSL https://raw.githubusercontent.com/devtux7/tsnet/main/ubuntu.sh | bash
```

To bypass raw GitHub CDN caches instantly (useful after commits):

```bash
curl -fsSL "https://raw.githubusercontent.com/devtux7/tsnet/main/ubuntu.sh?$(date +%s)" | bash
```

## Interactive Choices

Upon running the script, you will be prompted with a choice:
1) **Install Tailscale (SSH & Exit Node)**: Fully installs and configures Tailscale, activates SSH and Exit Node parameters, and runs firewall lockdown.
2) **Install Wireguard (Placeholder)**: Planned for future Wireguard VPN setups.
3) **Exit**: Safely exits the installer.

## Environment Variables

When choosing **Tailscale** (Option 1), you can customize behavior using the following environment variables:

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

After running the Tailscale installation flow, you **must approve** the exit node in your Tailscale Admin Console:

1. Open the [Tailscale Admin Console](https://login.tailscale.com/admin/machines).
2. Find your device, click the **three dots** icon next to it, and select **Edit route settings**.
3. Enable **Use as exit node**.

## References

- Tailscale SSH: https://tailscale.com/docs/features/tailscale-ssh
- Tailscale Exit Nodes: https://tailscale.com/kb/1103/exit-nodes
- Tailscale VS Code extension: https://tailscale.com/docs/integrations/vscode-extension
- Tailscale QR code setup: https://tailscale.com/docs/features/access-control/device-management/how-to/set-up-qr-code
