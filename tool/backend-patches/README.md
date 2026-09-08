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
