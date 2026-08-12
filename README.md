# Azure Support / HPC Dev Box Customization

This project configures a Windows 11 Microsoft Dev Box as a repeatable workstation for Microsoft CSS Azure infrastructure and HPC support. It installs Windows troubleshooting and deployment tools, enables an Ubuntu WSL 2 environment, adds Linux networking and MPI tooling, installs a shared VS Code extension set, and verifies the result.

## Architecture overview

Provisioning is split into four idempotent layers:

1. You upload `imagedefinition.yaml` as the customization file while creating the Dev Box. Its built-in PowerShell system task downloads scripts from this public repository to `C:\DevBoxSetup\scripts` and starts the Windows bootstrap.
2. `bootstrap-windows.ps1` installs or upgrades Windows software with WinGet, enables WSL 2, installs Ubuntu 24.04, and invokes the remaining scripts.
3. `bootstrap-wsl.sh` installs Ubuntu support, networking, build, and OpenMPI packages and configures Azure CLI and shell aliases.
4. `install-vscode-extensions.ps1` uses a machine-wide `VSCODE_EXTENSIONS` directory. `post-install-validation.ps1` reports a final pass/fail result.

Every PowerShell script uses strict mode, terminating errors, and transcripts under `C:\DevBoxSetup\Logs`. The Linux script writes its transcript to the same Windows directory through `/mnt/c`.

## Folder structure

```text
devbox-customization/
|-- README.md
|-- imagedefinition.yaml
|-- prompt.txt
|-- scripts/
|   |-- bootstrap-windows.ps1
|   |-- bootstrap-wsl.sh
|   |-- install-vscode-extensions.ps1
|   `-- post-install-validation.ps1
`-- docs/
    `-- setup-walkthrough.md
```

## Installed Windows software

The bootstrap requests the newest release available for each WinGet package ID at provisioning time: PowerShell 7, Azure CLI, Terraform, kubectl, Helm, Git, VS Code, Windows Terminal, Azure Storage Explorer, Notepad++, WinMerge, Python, jq, and yq. Bicep is installed and upgraded through `az bicep`, which keeps it aligned with Azure CLI behavior.

## Azure HPC support tooling

| Tool or package | Why it is useful |
| --- | --- |
| Azure CLI and Bicep | Reproduce ARM control-plane operations, inspect resources, and test declarative deployments. |
| Terraform | Reproduce infrastructure deployments and inspect provider/state behavior. |
| kubectl and Helm | Diagnose AKS workloads, services, storage classes, charts, and cluster configuration. |
| Azure Storage Explorer, jq, and yq | Inspect storage data and filter JSON/YAML evidence from APIs and configuration. |
| Git, VS Code, Python, CMake, GCC/G++, and Make | Review automation, build reproducers, and test customer scripts or native HPC workloads. |
| OpenMPI (`openmpi-bin`, `libopenmpi-dev`) | Compile and run MPI reproductions and validate rank launch and communication behavior. |
| `nslookup` and `dig` (`dnsutils`) | Compare resolver behavior, records, TTLs, and authoritative DNS responses. |
| `ping` (`iputils-ping`) | Check basic reachability, packet loss, latency, and MTU symptoms where ICMP is allowed. |
| `traceroute` | Identify route changes and the network hop where reachability degrades. |
| `ssh` and `scp` (`openssh-client`) | Access Linux, CycleCloud, and Slurm nodes and transfer logs or reproducers. |
| `tcpdump` | Capture packet-level evidence for DNS, TCP, MPI, storage, and cluster networking cases. |
| `net-tools` | Provides familiar tools such as `netstat` and `ifconfig` for older support procedures. |
| `curl` and `wget` | Test endpoints, proxies, TLS, metadata services, and artifact downloads. |
| `zip` and `unzip` | Package logs and handle support bundles or deployment artifacts. |

For CycleCloud and Slurm cases, these tools cover node access, scheduler-log collection, DNS and route checks, packet capture, MPI validation, and API/resource inspection. CycleCloud and Slurm themselves are workload services rather than workstation prerequisites, so this project does not install a scheduler daemon on the support workstation.

## Installation flow

1. Download `imagedefinition.yaml` from `https://github.com/taumhanlon/devbox-customization`.
2. In the Microsoft developer portal, create a Dev Box from the existing Windows 11 pool and select **Apply customizations**.
3. Select **Upload a customization file(s)**, add `imagedefinition.yaml`, and select **Validate**.
4. Create the Dev Box after validation succeeds. The YAML downloads this repository's scripts from `https://raw.githubusercontent.com/taumhanlon/devbox-customization/main`.
5. If Windows reports a pending restart while enabling WSL, restart once and rerun `C:\DevBoxSetup\scripts\bootstrap-windows.ps1` from an elevated PowerShell session.
6. Review `C:\DevBoxSetup\Logs` and run the validation script again if needed.

See [docs/setup-walkthrough.md](docs/setup-walkthrough.md) for the complete portal procedure.

## Assumptions and schema alternatives

Despite its required filename, `imagedefinition.yaml` is now a user customization file, not the original pool image definition. It intentionally has no `image` property because the existing Dev Box pool selects the Windows 11 base image. It uses the documented customization schema (`$schema: "1.0"`, `name`, and task sections).

The solution needs a `tasks` system task because enabling WSL and installing machine-wide software require elevation. Microsoft Dev Box permits a user customization to run a system task only when the user is an administrator or the project catalog explicitly preapproves the task. Standard users cannot elevate a built-in PowerShell task through an uploaded file. If portal validation rejects `~/powershell`, this requirement cannot be solved solely by changing user YAML; ask the Dev Center administrator to approve a custom catalog task, apply a team customization, or include WSL and the tools in the base image.

Additional assumptions:

- User customizations are enabled on the Dev Box project and the attached catalog exposes the built-in `~/powershell` task.
- The Dev Box has outbound HTTPS access to GitHub, Microsoft package repositories, WinGet, Ubuntu repositories, and the VS Code Marketplace.
- The base image contains Microsoft App Installer/WinGet and supports WSL 2 virtualization.
- The public `main` branch is acceptable as the script source. For controlled production rollout, pin `$repositoryRawUrl` to a reviewed commit or release tag.

For a nonadministrative fallback, move only user-scoped installs into `userTasks`. That fallback cannot enable Windows features or guarantee machine-wide installations.

## Validation

Run from an elevated PowerShell prompt:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
& 'C:\DevBoxSetup\scripts\post-install-validation.ps1'
```

The script verifies PowerShell 7, Azure CLI (`az version`), Terraform (`terraform version`), Bicep (`az bicep version`), kubectl (`kubectl version --client`), VS Code, WSL, and Ubuntu. It prints a table and exits with code `1` if any required component fails.

Optional Linux checks:

```powershell
wsl -d Ubuntu-24.04 -- bash -lc 'az version && mpirun --version && command -v dig tcpdump ssh'
```

## Troubleshooting

- **Customization validation rejects the system task:** the user is not an administrator or `~/powershell` is not approved. A Dev Center administrator must provide an elevated catalog task, team customization, or suitable base image.
- **Customization cannot download scripts:** verify proxy policy and TLS access to `raw.githubusercontent.com/taumhanlon/devbox-customization`. Prefer a reviewed commit URL or internal artifact source for enterprise deployment.
- **WinGet is unavailable:** update Microsoft App Installer in the base image or choose a supported Windows 11 Dev Box image that includes WinGet.
- **A package ID is unavailable:** run `winget search <name>` and update the ID in `bootstrap-windows.ps1`. Sources and regional availability can differ.
- **WSL asks for a restart:** restart the Dev Box, open elevated PowerShell, and rerun the Windows bootstrap. Existing package installs are reused or upgraded.
- **Ubuntu name differs:** run `wsl --list --verbose`, then pass `-UbuntuDistribution <name>` to both Windows scripts.
- **VS Code extensions are missing:** confirm the machine environment variable `VSCODE_EXTENSIONS` points to `C:\DevBoxSetup\VSCodeExtensions`, then rerun the extension script.
- **Linux aliases are missing for an existing user:** run the WSL bootstrap as that user with `sudo`; aliases also live in `/etc/profile.d/azure-support-aliases.sh`.
- **Provisioning fails:** inspect the newest transcript in `C:\DevBoxSetup\Logs`, then review the Dev Box customization operation in the developer portal for its task exit code.

## Updating tool versions

WinGet installs by stable package ID without pinning, and rerunning the bootstrap upgrades to the newest package available from the configured source. To update manually:

```powershell
winget source update
winget upgrade --all --silent --accept-package-agreements --accept-source-agreements
az bicep upgrade
wsl -d Ubuntu-24.04 --user root -- apt-get update
wsl -d Ubuntu-24.04 --user root -- apt-get upgrade -y
& 'C:\DevBoxSetup\scripts\install-vscode-extensions.ps1'
```

Review package IDs periodically with `winget show --id <package-id> --exact`. Update the Python package ID when the organization adopts a new feature release, test the change in a nonproduction pool, and pin versions in a custom task or image when case reproducibility requires deterministic tooling.
