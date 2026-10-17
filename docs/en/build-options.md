[Documentation index](README.md) · [Project home](../../README_english.md)

# Build Options

Choose the target, desktop, display backend, and optional features on the GitHub Actions `Run workflow` page. Desktop images are intended for ARM64 Droidspaces containers.

## Distribution and desktop support

| Target | Base image | Desktop profiles | Anland Wayland |
| --- | --- | --- | --- |
| `Debian-13` | Debian 13 (trixie) | `none`, `KDE`, `KDE mobile`, `GNOME`, `Anland Next`, `Niri`, `Hyprland`, `Mango`, `Denial` | Yes |
| `Ubuntu-24` | Ubuntu 24.04 | `none`, `KDE` | No |
| `Ubuntu-25` | Ubuntu 25.10 | `none`, `KDE` | No |
| `Ubuntu-26` | Ubuntu 26.04 | `none`, `KDE`, `KDE mobile`, `GNOME`, `Anland Next`, `Niri`, `Hyprland`, `Mango`, `Denial` | Yes |
| `Fedora-43` | Fedora 43 | `none`, `KDE`, `KDE mobile`, `GNOME`, `Anland Next`, `Niri`, `Hyprland`, `Mango`, `Denial` | Yes |
| `Fedora-44` | Fedora 44 | `none`, `KDE`, `KDE mobile`, `GNOME`, `Anland Next`, `Niri`, `Hyprland`, `Mango`, `Denial` | Yes |
| `Arch` | Arch Linux ARM | `none`, `KDE`, `KDE mobile`, `GNOME`, `Anland Next`, `Niri`, `Hyprland`, `Mango`, `Denial` | Yes (KDE uses Anland Wayland only) |

`all` filters targets according to desktop/backend support. `all-wayland` builds Debian 13, Ubuntu 26, Fedora 43/44, and Arch for KDE/KDE Mobile, GNOME, Niri, Hyprland, Mango, and Denial. Arch KDE, GNOME, KDE Mobile, Anland Next, Niri, Hyprland, Mango, and Denial force `anland-wayland`.

| Desktop | Description |
| --- | --- |
| `none` | Command-line environment for SSH, development, or a custom desktop. |
| `KDE` | KDE Plasma; Arch supports Anland Wayland only, while other supported targets may use X11 or Anland Wayland. |
| `KDE mobile` | Touch-first Plasma Mobile; requires Anland Wayland. |
| `GNOME` | A full Anland Wayland desktop on Debian 13, Ubuntu 26, Fedora 43/44, and Arch Linux ARM, with a terminal, file manager, settings, system monitor, keyring, portal, and common document/media apps. |
| `Anland Next` | An Anland session with rootless Xwayland and mini-wm, without a full desktop; Wayland only. |
| `Niri`, `Hyprland`, `Mango`, `Denial` | Anland Wayland compositors on Debian 13, Ubuntu 26, Fedora 43/44, and Arch Linux ARM. They include a basic terminal, XDG portal, audio, and fonts, without a full desktop application set. |

## Workflow inputs

| Input | Values / default | Description |
| --- | --- | --- |
| `build_target` | Distribution, `all`, `all-wayland`; default `Debian-13` | Select build targets. |
| `custom_username` | 1–32 letters, digits, `_`, or `-`, starting with a letter or `_`; default `Gold` | Normal RootFS user. |
| `desktop` | `none`, `KDE`, `KDE mobile`, `GNOME`, `Anland Next`, `Niri`, `Hyprland`, `Mango`, `Denial`; default `KDE` | Select desktop or command-line mode. |
| `desktop_autostart` | `true` / `false`; default `true` | Installs the desktop startup service; must be disabled for `none`. |
| `display_backend` | `x11` / `anland-wayland` | Defaults to Wayland in the Chinese workflow and X11 in the English workflow; Arch KDE and some profiles force Wayland. |
| `PulseAudio` | `socket` / `tcp` / `none`; default `socket` | X11 audio forwarding; Anland sets this to `none`. |
| `enable_zh_tz` | `true` / `false` | Installs Chinese locale and Shanghai timezone; defaults differ by workflow. |
| `enable_mesa` | `true` / `false`; default `true` | Adds Snapdragon GPU/Mesa support. |
| `enable_8gen2_wayland` | `true` / `false`; default `false` | Sets the Turnip UBWC Wayland workaround for relevant devices. |
| `enable_o3_mali` | `true` / `false`; default `false` | Xring O3 / Arm Mali GPU support (mesa-manet PanVK/Zink). Debian 13 and Ubuntu 24/25/26 only; requires the `anland-wayland` display backend. |
| `o3_mesa_version` | `pinned` / `latest`; default `pinned` | manet version: `pinned` pins v1.0 (device-verified); `latest` fetches the newest [mesa-manet](https://github.com/DsoTsin/mesa-manet) release. |
| `o3_verify_sha256` | `true` / `false`; default `true` | Verify the manet package SHA256. `pinned` uses the built-in digest; `latest` reads the release `SHA256SUMS`. Disable only when debugging download issues. |
| `enable_sshd` | `true` / `false`; default `false` | Enable the sshd service and allow password login (Debian/Fedora do not enable sshd by default). |
| `ssh_public_key` | SSH public key string; default empty | Public key appended to the normal user's `authorized_keys` (comma-separated for multiple keys). Supplying a key enables sshd automatically. |
| `nosnap` | `true` / `false` | Ubuntu only: removes Snap and prevents APT from reinstalling it; defaults differ by workflow. |
| `enable_systemd257` | `true` / `false`; default `false` | Tries the systemd 257 package family for old Android kernels; only `none` and standard `KDE` are supported. |
| `enable_srf` | `true` / `false` | Installs Fcitx5; enabled by default in the Chinese workflow, disabled in English. |
| `enable_binfmt` | `true` / `false`; default `false` | Adds binfmt cross-architecture support; not recommended for Arch. |
| `enable_yj` | `true` / `false`; default `true` | Improves NAT and Android/Droidspaces hardware recognition. |
| `enable_kfgj` | `true` / `false`; default `false` | Installs development tools such as compilers, CMake, and Python. |
| `enable_zip` | `true` / `false`; default `true` | Installs common compression tools. |
| `enable_docker` | `true` / `false`; default `false` | Installs Docker packages in the RootFS. |
| `wayland_package_repository` | Public `owner/repository`; default `Goldzxcbug/droidspaces-package` | Selects the source for prebuilt Anland package Releases. |

For exact defaults, see `.github/workflows/build-rootfs-releases-en.yml` and `build-rootfs-releases.yml`. `enable_systemd257` is experimental and adds build time. Systems already at systemd 257 or older skip installation; details are in the [script guide](../../scripts/README_english.md).

## Generated Droidspaces recommendations

Native and QEMU builds generate `container.config` from the effective build options.
It is the first regular archive member, followed by the rootfs and then XZ compression.
Old root-level copies are removed; no additional Dockerfile `COPY` is needed.
Droidspaces versions with recommendation support prefill their installation wizard.

| Build option | Recommended setting |
| --- | --- |
| `anland-wayland` | `enable_anland=1`; Termux:X11 and PulseAudio off |
| `x11` | `enable_termux_x11=1`; Anland off |
| X11 with `socket` audio | `enable_pulseaudio=1`; other audio choices use `0` |
| KDE or KDE Mobile | `allow_userns=1` |
| Docker enabled | `net_mode=nat`; otherwise keep the app default |
| Snapdragon GPU support enabled | `enable_gpu_mode=1` |
| Anland Next | `bind_mounts=/data/local/tmp/awl:/run/anland` |
| `enable_zh_tz=true` (Chinese locale and Shanghai timezone) | `dns_servers=114.114.114.114` |

Keys follow the Droidspaces Anland branch. Mount paths live in the config and use
the existing Droidspaces bind-mount parser and runtime. Environment variables are
not passed through this recommendation file. On kernels without user namespaces,
the requested KDE setting stays checked but disabled; this does not add kernel support.

Run the mapping and archive checks with `python3 -m unittest discover -s tests -v`.

## Xring O3 / Mali GPU support (enable_o3_mali)

This option installs [mesa-manet](https://github.com/DsoTsin/mesa-manet) (PanVK/Zink), giving the Xring O3 SoC (Mali-G2-Ultra NX, kbase interface via `/dev/mali0`) Vulkan 1.4 and OpenGL (through Zink) acceleration inside the container. Verified on a Xiaomi Pad 9 Pro Max: `vulkaninfo` enumerates the Mali-G2-Ultra MC16, and Chrome's WebGL path renders through ANGLE(Vulkan) with real rasterization.

### Conflicts and limits

| Combination | Result |
| --- | --- |
| `enable_o3_mali` x `enable_mesa` (Qualcomm) | **Mutually exclusive**; the build fails. They write incompatible GPU environment variables (zink vs kgsl). |
| `enable_o3_mali` x `enable_8gen2_wayland` | **Mutually exclusive**; the build fails (the latter is Qualcomm Turnip-only). |
| `enable_o3_mali` x Fedora/Arch/`all`/`all-wayland` | **Unsupported**; the build fails. manet ships Debian/Ubuntu .deb packages only. |
| `enable_o3_mali` x `display_backend=x11` | **Unsupported**. `anland-wayland` is required (the Chrome wrapper and Wayland path are what was validated). |
| `enable_o3_mali` x `enable_binfmt` | Compatible. The installer disables non-manet ICDs to avoid clashing with the amd64 Mesa packages. |

### Known limits

- **No hardware video decode**: this Mali driver has no VA-API and the container has no V4L2 decode node, so browser video decodes in software (the O3's performance cores usually cope; play hard-decoded video on the Android side instead).
- **No GPU OpenCL**: a kernel DRM render node is required (the current kbase driver does not expose one). `RUSTICL_ENABLE=zink,llvmpipe` is preconfigured, so the OpenCL platform works on CPU (llvmpipe).
- A `CS_QUEUE_GROUP_CREATE ... ENOTTY` warning may appear on the first `vulkaninfo` run: the kbase ioctl numbers differ slightly from what manet expects, so it falls back gracefully; rendering is unaffected.

### Droidspaces container options required for this RootFS

| Droidspaces option | Requirement |
| --- | --- |
| **GPU Access** (`enable_gpu_mode`) | **Required**. The recommended config already writes `enable_gpu_mode=1`; verify it when importing manually. The Mali node `/dev/mali0` depends on it. |
| **Anland Display** (`enable_anland`) | **Required** (the recommended config writes `enable_anland=1` when the build used anland-wayland). |
| Configure Termux:X11 (`enable_termux_x11`) | Keep off. Conflicts with Anland. |
| Configure VirGL (`enable_virgl`) | Keep off. The native driver is used instead; VirGL would bypass the GPU. |
| Allow user namespaces (`allow_userns`) | Recommended for KDE (the recommended config enables it automatically for KDE desktops). |

### Version and verification sub-options

- `o3_mesa_version=pinned` (default): installs the fixed v1.0 (`manet-a2a7103fc7f.deb` with a built-in SHA256).
- `o3_mesa_version=latest`: fetches the newest mesa-manet release through the GitHub API.
- `o3_verify_sha256=false`: skips SHA256 verification (not recommended).

The rootfs keeps `/usr/local/sbin/install-manet-o3` as a runtime tool, so you can reinstall or upgrade inside the container (`install-manet-o3 -V latest`, `install-manet-o3 --uninstall`).

## SSH options (enable_sshd / ssh_public_key)

- `enable_sshd=true`: enables the sshd service and allows password login. The normal user password defaults to `1234` (see `custom_username`).
- `ssh_public_key`: fills in the key, enables sshd automatically and appends the key to the normal user's `~/.ssh/authorized_keys` (comma-separated for multiple keys).
- Configure a **port forward** (e.g. `22:22/tcp`) in the Droidspaces app container settings to SSH into the container from your LAN.
