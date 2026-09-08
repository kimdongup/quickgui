# Local SPICE acceptance probe

This opt-in probe boots a disposable 16 MiB image containing a tiny BIOS keyboard
program. It receives a framebuffer over SPICE, disconnects, reconnects, sends K
through the SPICE inputs channel, and checks both a new frame and the guest's
memory flag. It then opens the real `spicy` client and checks its main, display,
inputs and cursor channels through QMP. It does not install an OS or attach any
existing guest disk, network interface or shared directory.

Requirements: an x86_64 QEMU with SPICE, matching firmware, NASM, a C compiler,
pkg-config, spice-client-glib and gdk-pixbuf. macOS uses HVF; Linux uses TCG. The
checked host is an Intel Mac; this is not Apple Silicon guest validation.

From the repository root:

```sh
spice_probe_dir=$(mktemp -d /tmp/quickgui-spice-probe.XXXXXX)
cc -Wall -Werror tool/spice/capture.c -o "$spice_probe_dir/capture" \
  $(pkg-config --cflags --libs spice-client-glib-2.0 gdk-pixbuf-2.0)
python3 tool/spice/smoke.py \
  --qemu /Users/mac/quickemu/validation/spice-backend/bin/qemu-system-x86_64 \
  --capture "$spice_probe_dir/capture" \
  --viewer /usr/local/bin/spicy --firmware /usr/local/share/qemu
```

Substitute the executable/firmware paths for the host. The probe prints its
temporary evidence directory and leaves logs/PNGs there. It stops its own viewer
and VM on completion or failure. `--keep-running` leaves them available for a
Quickgui inspection until a `finish` file is created in that directory.

GStreamer may take minutes to build its first registry. Run
`gst-inspect-1.0 --version` to complete normal initialization first. `--registry`
accepts a separately prepared cache for diagnostics. `--display-only` skips plugin
discovery only in the probe's child processes; it is not the normal app default
and does not validate multimedia codecs. Neither the server build nor this probe
proves installed-guest SSH, clipboard, file transfer, audio or USB redirection.
