# Dev Box setup walkthrough

This guide uses the only available deployment path: uploading a user customization file while creating a Dev Box. The existing pool selects the Windows 11 base image; no original pool YAML or project catalog administration is required for the happy path.

## Prerequisites

- A Microsoft Dev Center, project, network connection, and Dev Box pool backed by Windows 11.
- Dev Box User rights to create a Dev Box.
- User customizations enabled for the project.
- Administrator permission to run system tasks, or a project catalog that preapproves the required elevated PowerShell task.
- Outbound HTTPS from the Dev Box to WinGet, GitHub (or the chosen artifact host), Microsoft package repositories, Ubuntu repositories, and the VS Code Marketplace.
- A local copy of `imagedefinition.yaml` from `https://github.com/taumhanlon/devbox-customization`.

## 1. Create or select a Dev Box project and pool

1. Sign in to the Azure portal and open **Microsoft Dev Center**.
2. Create or select a Dev Center, then create or select a project for the Azure Support team.
3. Confirm the project has a network connection with internet or approved package-repository access.
4. Create a Dev Box definition using Windows 11 Enterprise 24H2, or an approved organizational Windows 11 image.
5. Create a pool that references the definition and network connection. Confirm the pool status is healthy.
6. Assign the support engineers the **DevCenter Dev Box User** role scoped to the project.

If a pool already exists, verify its image includes Microsoft App Installer/WinGet and supports nested virtualization required by WSL 2.

## 2. Add the customization file

1. Download the repository or save its raw `imagedefinition.yaml` file locally.
2. Review the YAML and scripts before use. The configured script source is `https://raw.githubusercontent.com/taumhanlon/devbox-customization/main`.
3. Sign in to the Microsoft developer portal at `https://devportal.microsoft.com`.
4. Select **New** > **New dev box**, enter a name, and select the existing project and Windows 11 pool.
5. Select **Apply customizations** and then **Continue**.
6. Select **Upload a customization file(s)** > **Add customizations from file**, and choose `imagedefinition.yaml`.

## 3. Import the image definition

There is no separate image-definition import in this access model. The filename is retained because it is part of the project contract, but the file is an uploadable customization and intentionally omits `image`.

1. Select **Validate** after adding the file.
2. Confirm the portal recognizes `azure-support-hpc-workstation` and the `~/powershell` task.
3. If validation rejects the system task, stop: an uploaded file cannot grant itself elevation. Ask the Dev Center administrator to preapprove an elevated custom task, apply the same bootstrap as a team customization, or provide a base image with WSL enabled.
4. If organizational policy requires a repository selection instead of local upload, Microsoft currently requires that repository customization file to be named `workload.yaml`. Publish a copy of this YAML under that name and provide the repository URL in the portal.

## 4. Run provisioning

1. Browse to the Microsoft developer portal at `https://devportal.microsoft.com`.
2. Select **New** > **New dev box**.
3. Enter a name and select the prepared project and pool.
4. Confirm the uploaded customization is listed and validated.
5. Submit the request and monitor the creation and customization operations.
6. Connect after the Dev Box reaches **Running** and customization reports success.

The system task creates `C:\DevBoxSetup`, downloads all scripts, and runs the Windows, WSL, extension, and validation stages. Logs persist in `C:\DevBoxSetup\Logs`.

## 5. Validate installations

Open an elevated PowerShell prompt and run:

```powershell
& 'C:\DevBoxSetup\scripts\post-install-validation.ps1'
```

Expected checks are `PASS` for PowerShell 7, Azure CLI, Terraform, Bicep, kubectl, VS Code, WSL, and Ubuntu. Confirm the requested version commands directly when collecting evidence:

```powershell
az version
terraform version
az bicep version
kubectl version --client
```

Validate Ubuntu and HPC/network commands:

```powershell
wsl -d Ubuntu-24.04 -- bash -lc 'az version'
wsl -d Ubuntu-24.04 -- bash -lc 'mpirun --version'
wsl -d Ubuntu-24.04 -- bash -lc 'command -v nslookup dig ping traceroute ssh scp tcpdump'
```

Open VS Code and confirm the Azure CLI, Bicep, Kubernetes, Terraform, YAML, Python, Copilot, Copilot Chat, and PowerShell extensions are enabled. Copilot requires the engineer to sign in with an entitled GitHub account.

## 6. Troubleshoot failures

1. Open the Dev Box customization details in the developer portal and identify the failed task and exit code.
2. On the Dev Box, sort `C:\DevBoxSetup\Logs` by modified time and inspect the corresponding transcript.
3. Test access to the script URL and package sources through the enterprise proxy. Do not disable TLS validation to work around proxy errors.
4. Run `winget source update` and `winget search <tool>` when a package ID or source fails.
5. Run `wsl --status` and `wsl --list --verbose`. If feature enablement requires a reboot, restart once and rerun:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
& 'C:\DevBoxSetup\scripts\bootstrap-windows.ps1'
```

6. If Ubuntu exists under another name, pass it explicitly:

```powershell
& 'C:\DevBoxSetup\scripts\bootstrap-windows.ps1' -UbuntuDistribution 'Ubuntu'
& 'C:\DevBoxSetup\scripts\post-install-validation.ps1' -UbuntuDistribution 'Ubuntu'
```

7. If only Linux setup failed, rerun it without reinstalling Windows packages:

```powershell
wsl -d Ubuntu-24.04 --user root -- bash /mnt/c/DevBoxSetup/scripts/bootstrap-wsl.sh
```

8. If only extensions failed, rerun `C:\DevBoxSetup\scripts\install-vscode-extensions.ps1` and inspect its transcript.
9. Rerun validation. Preserve the failed customization operation, transcript, WinGet output, `wsl --status`, and network/proxy evidence when escalating.

Because setup is designed to be rerunnable, successful package operations are retained and current packages are reused or upgraded. Test repository and package changes in a nonproduction pool before broad rollout.
