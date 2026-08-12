# Dev Box setup walkthrough

This guide deploys the Azure Support / HPC customization as a team customization. Portal labels can vary as Dev Box features roll out; the equivalent Azure CLI or REST workflow is a valid alternative when a blade is not exposed in the tenant.

## Prerequisites

- A Microsoft Dev Center, project, network connection, and Dev Box pool backed by Windows 11.
- DevCenter Project Admin or Contributor rights to attach a catalog and configure the project/pool.
- Dev Box User rights to create a Dev Box.
- Project-level catalogs and team customizations enabled for the Dev Center and project.
- Outbound HTTPS from the Dev Box to WinGet, GitHub (or the chosen artifact host), Microsoft package repositories, Ubuntu repositories, and the VS Code Marketplace.
- A repository containing this project. Replace `CONTOSO` in `imagedefinition.yaml` before deployment.

## 1. Create or select a Dev Box project and pool

1. Sign in to the Azure portal and open **Microsoft Dev Center**.
2. Create or select a Dev Center, then create or select a project for the Azure Support team.
3. Confirm the project has a network connection with internet or approved package-repository access.
4. Create a Dev Box definition using Windows 11 Enterprise 24H2, or an approved organizational Windows 11 image.
5. Create a pool that references the definition and network connection. Confirm the pool status is healthy.
6. Assign the support engineers the **DevCenter Dev Box User** role scoped to the project.

If a pool already exists, verify its image includes Microsoft App Installer/WinGet and supports nested virtualization required by WSL 2.

## 2. Add the customization repository

1. Push this project to GitHub or Azure DevOps. Protect the default branch and review changes before promotion.
2. In `imagedefinition.yaml`, set `$repositoryRawUrl` to the raw-content base URL for that repository and branch.
3. In the Dev Center project, open **Catalogs** and choose **Add**.
4. Select the repository provider, supply the repository/branch/catalog path, and configure authentication without embedding credentials in YAML.
5. Enable automatic or manual catalog synchronization according to change-control policy.
6. Start a sync and wait for the catalog status to report success.

A private repository usually cannot be downloaded by `Invoke-WebRequest` without credentials. In that case, publish the scripts as an authenticated Azure DevOps universal package, use a secured Azure Storage artifact, or wrap the bootstrap in an approved custom catalog task that retrieves content with managed identity.

## 3. Import the image definition

The source project keeps `imagedefinition.yaml` at its requested root. Catalog layouts can require image definitions beneath a configured folder.

1. If the catalog root scans image definitions recursively, retain the file at the repository root.
2. If the catalog contract requires a conventional path, copy the file to `image-definitions/azure-support-hpc-workstation/imagedefinition.yaml` in the deployment repository.
3. Synchronize the catalog again.
4. Open the project image definitions/team customizations view and confirm `azure-support-hpc-workstation` is recognized.
5. Associate the image definition/team customization with the intended pool. If imaging is enabled, optionally build and publish a flattened image after the customization succeeds in a test pool.

The schema assumes `$schema: "1.0"`, `tasks` for LocalSystem work, and the built-in `~/powershell` task. If the tenant rejects that task, use an administrator-approved custom task or an Azure Compute Gallery image. If the pool controls the base image independently, adapt the task block into the tenant's user/team customization file and omit or replace the `image` field as required by its current schema.

## 4. Run provisioning

1. Browse to the Microsoft developer portal at `https://devportal.microsoft.com`.
2. Select **New** > **New dev box**.
3. Enter a name and select the prepared project and pool.
4. Select the team customization/image definition. Where user customization upload is enabled, choose **Apply customizations** and upload the tenant-approved YAML instead.
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
