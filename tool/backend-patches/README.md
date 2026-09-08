# Quickemu patches for guest validation

These are separate Quickemu changes, retained on the personal Quickgui branch for reproducible validation. They are not automatically applied to a system installation and are not part of the Quickgui upstream PR series.

`quickemu-4.9.9-macos-cpu.patch` fixes two reproduced Intel macOS detection failures: the caller's `Vendor` key is accepted, and feature checks include `machdep.cpu.leaf7_features` (where macOS reports AVX2), matching complete literal tokens. The patch does not fabricate CPU capabilities or bypass the feature checks.

Apply to a **copy** of the official Quickemu 4.9.9 script (Git blob `586a8cb04839f83aa7c5792791ae34907057d5d4`):

```sh
patch /path/to/validation/backend/quickemu < tool/backend-patches/quickemu-4.9.9-macos-cpu.patch
bash -n /path/to/validation/backend/quickemu
shellcheck /path/to/validation/backend/quickemu
QUICKGUI_PATCHED_QUICKEMU=/path/to/validation/backend/quickemu \
  QUICKGUI_BASH=/path/to/bash-4-or-newer \
  python3 -m unittest tool/test_macos_cpu_patch.py
```

On Intel macOS, select the patched copy through Quickgui's Advanced backend settings only for this validation. Use Cocoa/output-only audio. A successful backend launch proves neither guest installation nor SPICE support; see [the guest validation record](../../docs/maintenance/GUEST_VALIDATION.ko.md).

## Draft for a separate Quickemu PR

Title: `fix(quickemu): correct CPU detection on Intel macOS`

On an Intel Mac, `configure_cpu` requests `get_cpu_info 'Vendor'`, but the Darwin implementation only accepts `^Vendor ID`. In addition, the Darwin feature check reads only `machdep.cpu.features`, although AVX2 is reported in `machdep.cpu.leaf7_features`. As a result, launching a Sequoia guest on an i9-9880H reports an unknown CPU vendor and rejects the host for missing SSE4.2/AVX2 before QEMU starts.

Accept both vendor query keys and check exact feature tokens from both sysctl properties. Unsupported or unavailable features still fail the check. The Linux code path is unchanged.

Validation: Bash syntax and ShellCheck 0.11.0 pass; three regression tests cover vendor aliases, features from both properties, and missing/substring rejection. On macOS 15.7.9 with Quickemu 4.9.9 and QEMU 11.1.1, the guest now passes CPU checks and reaches the Sequoia recovery GUI with 8 GB RAM. Recovery Terminal opens and successfully prepares the new guest disk as GPT/APFS. Guest installation and SSH remain separate acceptance checks.

This draft has not been submitted. The reproduction patch targets the pinned 4.9.9 script; rebase and rerun these checks against the then-current Quickemu branch before submission.
