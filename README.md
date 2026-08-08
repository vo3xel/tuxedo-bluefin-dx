# tuxedo-bluefin-dx

[Bluefin DX](https://projectbluefin.io/) with **TUXEDO drivers** and **TUXEDO Control Center**
baked into the image. Built for the TUXEDO InfinityBook Pro 14 Gen9 (AMD), but should work on
any TUXEDO/Clevo device supported by `tuxedo-drivers`.

Based on the [ublue-os/image-template](https://github.com/ublue-os/image-template).

## What's inside

- **Base:** `ghcr.io/ublue-os/bluefin-dx:stable`
- **Kernel modules:** the official `tuxedo-drivers` dkms package (tuxedo_keyboard, tuxedo_io,
  fan/EC control, …) compiled at image build time against the exact image kernel — dkms is only
  a build tool here, nothing rebuilds at runtime, the modules ship in the image
- **TUXEDO Control Center** (`tccd` + `tccd-sleep` enabled) from the
  [official TUXEDO Fedora repo](https://rpm.tuxedocomputers.com/), installed to a real
  (immutable) `/opt` so it survives bootc deployments
- Nightly rebuilds via GitHub Actions pick up base image, driver, and TCC updates automatically

## Install

On an existing Fedora Atomic / Universal Blue installation:

```bash
sudo bootc switch ghcr.io/vo3xel/tuxedo-bluefin-dx:latest
```

Then reboot. To go back:

```bash
sudo bootc switch ghcr.io/ublue-os/bluefin-dx:stable
```

An anaconda ISO / qcow2 can be built with the **Build disk images** workflow
(Actions → Build disk images → Run workflow) or locally with `just build-iso`.

## ⚠️ Secure Boot

The TUXEDO kernel modules built into this image are **not signed**. With Secure Boot enabled
the kernel will refuse to load them. Options:

1. Disable Secure Boot in firmware (TUXEDO ships many devices this way), or
2. Module signing with your own MOK — not implemented yet (contributions welcome)

Everything else in the image works fine with Secure Boot on; only the tuxedo_* modules
(keyboard backlight, fan control, TCC hardware access) would be unavailable.

## CI setup (once, for forks)

1. **Enable workflows** in the Actions tab.
2. **Image signing (recommended):** install [cosign](https://docs.sigstore.dev/cosign/system_config/installation/), then

   ```bash
   COSIGN_PASSWORD="" cosign generate-key-pair
   ```

   - Add the content of `cosign.key` as a repository **Actions secret** named `SIGNING_SECRET`
     (Settings → Secrets and variables → Actions → New repository secret)
   - Commit `cosign.pub` to the repo root
   - Never commit `cosign.key` (it is in `.gitignore`)

   Until the secret exists, the build still succeeds — the signing step just warns and skips.

## Repo layout

| Path | Purpose |
| --- | --- |
| `Containerfile` | Base image selection + immutable `/opt` + runs `build.sh` |
| `build_files/build.sh` | Driver build (akmods), TCC install, service enablement |
| `system_files/` | Files copied verbatim into `/` (TUXEDO yum repo definition) |
| `.github/workflows/build.yml` | Build, rechunk, push to GHCR, sign — on push, PR, and nightly |
| `.github/workflows/build-disk.yml` | ISO/qcow2 disk images via bootc-image-builder |
| `disk_config/` | Disk/ISO build configuration |
| `tuxedo-bluefin-dx.env` | Image name/org/description used by the Justfile and CI |

## Verifying the drivers after boot

```bash
lsmod | grep tuxedo          # modules loaded
systemctl status tccd        # TCC daemon running
tuxedo-control-center        # GUI
```
