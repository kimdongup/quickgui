# Upstream submission queue

Upstream base: `74949e086154f3f2d555f9268778545c78ff2b51`. First submission: [Draft PR #325](https://github.com/quickemu-project/quickgui/pull/325), head `448e7e4922ec804578908f41ef07778deacf4dd2`, on `pr/upstream-desktop-compatibility`. It contains one commit and 40 files. The existing dependent topic branches remain preserved.

These topics share dependent commits. Submit the build foundation first, then rebuild each remaining topic against the accepted upstream base. Do not submit the personal branch as one large upstream PR. If upstream uses squash/rebase merge, compare the remaining tree/patches before replaying commits.

| Order | Fork branch | Proposed title | Dependency |
| --- | --- | --- | --- |
| A | `pr/upstream-desktop-compatibility` | `build!: update Flutter desktop compatibility` — [Draft #325](https://github.com/quickemu-project/quickgui/pull/325) | upstream base |
| B | `pr/recoverable-startup` | `fix: recover startup and preserve the selected workspace` | A |
| C | `pr/download-lifecycle` | `fix: track download failures and terminate cancelled commands` | B runner/workspace |
| D | `pr/vm-actions` | `fix: serialize VM actions and verify backend state` | B/C services |
| E | `pr/selection-usability` | `fix: make selections searchable and preserve download inputs` | B/C selection/download contracts |
| QA | `pr/functional-regressions` | `fix: handle corrupt VM files and verify desktop lifecycle regressions` | D/E; fold relevant follow-up fixes into the owning topic before submission |

## A — build foundation

The configured Flutter SDK and desktop dependencies/native project settings were out of sync. Use Flutter 3.47.2 / Dart 3.13 and compatible locks, retain CocoaPods fallback, and run analysis/tests plus Linux/macOS builds. Use a separate Nix input for Flutter so compiler updates do not force an unrelated QEMU runtime update. The submitted workflow targets main for push/PR events and supports workflow_dispatch; private branch patterns are excluded.

The new SDK emits a binary asset manifest, so the original JSON icon loader fails. A real bundled-asset regression test reproduced that failure before switching to `AssetManifest.loadFromAssetBundle` and awaiting icon loading during startup. The resolved Darwin file picker checks filesystem entitlements before opening dialogs, so the two plist changes from `c59d53b` are included in this first PR. The macOS deployment target is now 12.0; the compatibility change is explicit in the title/body.

Local submitted-tree validation: enforced lockfile, formatting, analysis, both tests, macOS Release build (47.2 MB), deep signature verification and signed file-picker entitlement passed. Runner/App.framework contain x86_64 and arm64 slices. The bundle is ad-hoc signed, not notarized. Submitted-head [fork CI](https://github.com/kimdongup/quickgui/actions/runs/34558437055) and the remaining acceptance scope are tracked in [the first PR record](UPSTREAM_DESKTOP_PR.ko.md). Installed-guest GUI acceptance and release-format packaging/publishing are not complete on this branch.

`pr/desktop-build` / `1970416` remains an implementation reference. Its dependent topics must be rebuilt against the accepted result of #325, including the manifest and entitlement corrections. Related open work: #303 for startup/manifest handling, #322 for the packaging dependency replaced by fastforge, and #317 for other flake.lock updates. The related PRs were rechecked on 2026-09-10; no foreign branch was merged or automatically closed.

## B — recoverable startup and workspace

A missing saved directory or a startup discovery failure could prevent the app from starting. Build on the binary asset manifest fix in #325, separate package metadata from executable discovery, show retry/folder recovery, and keep the user's saved path until a valid replacement is selected. Commands receive an explicit working directory and preserve PATH precedence.

Validation: executable permissions/PATH ordering, unavailable saved folders, preferences, icons and legacy/current quoted CSV fixtures. Related idea: [#303](https://github.com/quickemu-project/quickgui/pull/303) by **s-b-repo**; the manifest and lifecycle implementation is rewritten around the shared services.

## C — download lifecycle

A command that printed 100% and exited nonzero could appear successful, and unconsumed output could block the process. Drain stdout/stderr concurrently, keep bounded diagnostics, use exit status for the result, and cancel the owned process tree when a download is cancelled. Preserve existing files during write-access probing and confirm closing an active download.

Validation: nonzero exit after 100%, missing executable, large simultaneous output, split progress, cancellation before start and a child holding output pipes open, spaced/Unicode arguments. Only owned disposable commands were used for termination tests.

## D — VM actions

VM controls could target the wrong state-file directory, split filenames containing spaces, or allow deletion while startup was pending. Use absolute config paths and argument lists, inspect literal disk paths without sourcing Bash, serialize operations per VM and recheck state/config before commands. Resolve storage paths before deletion to protect shared disk symlinks, directory aliases and nested VM directories referenced by other configurations in the workspace. Requery the resulting state and surface backend failures. SSH discovery has bounded connect/read timeouts.

Validation: invalid/unrelated PIDs, custom disk directories, concurrent actions, changed config, safe SSH arguments and split/silent SSH fixtures. Public Quickemu 4.9.9 starts/stops/deletes a disposable BIOS VM on Linux x86_64 and macOS x86_64. Full installed guest/SSH/SPICE GUI acceptance is still pending; do not mark that PR checklist item complete.

Follow-up `ab1ff85` on `pr/shared-vm-storage` is also integrated into `pr/functional-regressions` and `integration/stabilization`. The old code invoked the mock deletion backend for aliased/shared storage; the fix rejects it before invocation. Three regression tests cover aliases, nested directories, shared disk symlinks and successful deletion of independent storage. Analysis and all 26 common tests pass locally; [Linux/macOS/Nix CI](https://github.com/kimdongup/quickgui/actions/runs/34259444705) and [real Linux backend CI](https://github.com/kimdongup/quickgui/actions/runs/34259444702) pass on that SHA. Fold this follow-up into topic D before submission; it introduces no personal installation profile or UI layout change.

Follow-up `ae57d7d` on `pr/spice-unix` adds Quickemu's default local SPICE endpoint. Previously, a running VM with only `unix,<path>` in its ports file had no enabled viewer button. Resolve relative paths, verify an actual socket, preserve literal path characters, and recheck the PID/config/state before connecting. Keep TCP support and the existing Manager layout. Four regression tests cover socket discovery, path characters, stale state/endpoints, TCP and the viewer button. All 30 common tests, [Linux/macOS/Nix CI](https://github.com/kimdongup/quickgui/actions/runs/34262907080) and [real Linux backend CI](https://github.com/kimdongup/quickgui/actions/runs/34262907061) pass. This is the current integration/QA head; fold it into topic D before submission. An isolated Intel Mac QEMU/SPICE build also passed framebuffer, keyboard and reconnect checks on a disposable probe VM. Those personal host recipes do not belong in the common app patch, and installed-guest acceptance remains pending.

## E — selection usability

Long OS/version/option lists could not be reliably scrolled. Share a single ListView/Scrollbar/controller implementation, reset scroll on filtering, dispose focus/scroll resources, show retry/empty states, and capture download inputs before asynchronous workspace validation.

Validation: scrolling to the last entry, filtering to an empty list, retry after catalog failure, minimum desktop window and repeated navigation. Inspired by [#224](https://github.com/quickemu-project/quickgui/pull/224) by **peterax**, with additional lifecycle and error handling.

## M1-discovered common follow-ups

The PATH fix on `pr/macos-homebrew-path` (`dc51dd0`) and the file-picker entitlement fix on `pr/macos-file-picker-entitlements` (`c59d53b`) each branch from `ae57d7d`. Their [PATH CI](https://github.com/kimdongup/quickgui/actions/runs/34506027934) and [file-picker CI](https://github.com/kimdongup/quickgui/actions/runs/34506028056) pass analysis/tests and Linux/Nix/macOS builds; the fork-only PPA exclusion is skipped as expected.

These original branches are independent follow-ups against the common integration base. Against upstream `74949e0`, they include 14 commits and 62/63 files respectively. Fold PATH precedence into topic B after its Toolchain service lands. The two entitlement changes have now been extracted into #325 because its updated file picker requires them; they no longer need a separate PR. Recheck each final submitted diff and validate its exact base. ARM VM services, drivers, installation media and personal validation documents remain in the personal branch.

## Personal follow-up ideas

- [#275](https://github.com/quickemu-project/quickgui/pull/275), **ivoheck**: tag newly installed VMs. The fork uses the exact config in successful Quickget output, validates it and distinguishes an existing config; it does not select a folder by modification time.
- [#266](https://github.com/quickemu-project/quickgui/pull/266), **meepak**: config editor. The fork adds loading/saving states, conflict checks, same-filesystem replacement and the shared VM operation lock.

All four referenced PRs were open and unmerged when checked on 2026-09-08. Ideas were adapted; no whole foreign branch was merged. Existing project licensing and author attribution remain intact.

For every actual submission, replace general validation text with the submitted head SHA, passing run URLs and remaining host limitations from [STATUS.ko.md](STATUS.ko.md). Record the resulting PR URL and upstream merge SHA here as review progresses.
