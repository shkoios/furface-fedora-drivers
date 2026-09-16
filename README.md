# Furface Linux Setup

Selective repair/setup script for **Fedora 44 KDE on an Intel Surface Laptop 4 (x86_64)**.
AMD Surface laptops, other Surface models, other Fedora releases, and Atomic/Kinoite are not supported. This is a community setup script, not an official Microsoft or Fedora installer.

## Run

Download the script, open Konsole in its folder, and run:

```bash
bash "furface linux setup.sh"
```

Choose **1** for everything, one menu number for a single fix, or several numbers such as **3 4** for GPU and microphone.

Command-line examples:

```bash
bash "furface linux setup.sh" --fix mic
bash "furface linux setup.sh" --fix gpu,mic
bash "furface linux setup.sh" --all
bash "furface linux setup.sh" --plan all
bash "furface linux setup.sh" --help
```

`--plan` only describes the selected steps; it does not check network availability or simulate package dependency resolution. Help and plan need no administrator privileges. Actual fixes need sudo and a local interactive terminal. Run from your normal desktop account. Face enrollment cannot be unattended.

## Fixes

| Name | Action |
|---|---|
| `repos` | Repairs the linux-surface repository and refreshes enabled repositories. Does not remove unrelated repositories or disable signature checks. |
| `gpu` | Installs Intel OpenCL and checks that Iris Xe is visible. Does not install DaVinci Resolve. |
| `mic` | Sets the built-in internal microphone to 20%. On the tested ALC274 hardware this removed the extra 30 dB boost. WirePlumber remembers the setting. Test speech and adjust if needed. |
| `touch` | Prepares the Surface repository, installs the Surface kernel and iptsd, sets the Surface kernel as default, and prepares Secure Boot enrollment. Retains Fedora kernels. |
| `face` | Installs Howdy from starfish's COPR, finds the infrared camera, configures it, offers enrollment, and tests face-only PAM authentication before adding Howdy to the KDE lock screen and Plasma Login Manager. Password fallback remains. |

Fixes run in the table's order regardless of argument order. Duplicate selections are removed. A failure stops the run; earlier changes are not automatically rolled back. Rerun the desired fix after addressing the error. Declining face enrollment skips login activation.

## Reboot and tests

Touch requires a reboot. If the blue MOK screen appears, choose **Enroll MOK → Continue → Yes**, enter **surface**, and reboot again. This is the linux-surface package's enrollment password, not your account password. `uname -r` should then contain `surface`.

Test touch after reboot, microphone speech in your calling app, and face unlock with **Meta+L**. The PAM test does not replace checking the actual login and lock screens. Howdy is a convenience feature, not equivalent to Windows Hello's security guarantees. Keep your password available.

The script never automatically reboots, disables SELinux, erases packages to solve dependencies, or installs Resolve itself.

## Repository choices

The script checks for the Fedora 44 Surface repository first. If unavailable, it uses the Fedora 43 Surface repository that installed successfully on the tested Fedora 44 laptop. This is a compatibility workaround, not a guarantee of future package compatibility. Dependency conflicts stop installation without `--allowerasing`.

GPU and mic use only Fedora's `fedora` and `updates` repositories; touch additionally uses linux-surface; face additionally uses starfish/howdy-beta. The separate repository-refresh option can still report errors from unrelated enabled repositories. Third-party package signing keys are accepted through DNF; package signature checking remains enabled.

## Backups and recovery

Every actual run creates a private `/var/backups/furface-linux-XXXXXXXX/` directory containing the original repository files, PAM files, existing Howdy configuration/models, and a log. Microphone runs also save the prior source settings. These backups contain personal data and **must not be uploaded to GitHub**.

For a boot problem, select your original Fedora kernel from GRUB. For a login problem, use your password and restore only the affected files from that run's backup. If `/etc/pam.d/plasmalogin` did not exist before the run, removing the newly created override restores the distribution's `/usr/lib/pam.d/plasmalogin` configuration. Do not replace the entire PAM directory blindly. Backups do not uninstall packages or revoke enrolled Secure Boot keys.

## Validation

The underlying fixes were exercised on one laptop. The selective version has Bash/embedded-Python syntax checks and automated CLI selection tests. A clean Fedora installation and other hardware have **not** been tested.

Run the non-mutating CLI tests with:

```bash
python3 tests/test_cli.py
```

## Upstream projects

- [linux-surface setup](https://github.com/linux-surface/linux-surface/wiki/Installation-and-Setup)
- [Intel compute runtime](https://github.com/intel/compute-runtime)
- [Howdy](https://github.com/boltgolt/howdy)
- [starfish Howdy COPR](https://copr.fedorainfracloud.org/coprs/starfish/howdy-beta/)
