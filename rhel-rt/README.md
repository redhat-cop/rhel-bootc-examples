# rhel-rt — real-time RHEL 10.2 bootc image

`kernel-rt` plus the stock tuned `realtime` profile on `registry.redhat.io/rhel10/rhel-bootc:10.2`,
with the profile's kernel arguments baked into the image so tuned has nothing left to append.

Real-time tuning and image mode each have a documented way to set kernel arguments, and on RHEL 10.2
the two disagree. This example shows how to reconcile them.

**Scoped to RHEL 10.2.** See "Open questions" for why 10.3 is not claimed.

---

## The problem this prevents

RHEL's real-time guide configures the `realtime` profile by letting tuned set kernel arguments through
`rpm-ostree kargs`. The image-mode guide says kernel arguments belong in `/usr/lib/bootc/kargs.d/`. On
RHEL 10.2 (tuned 2.27) these collide silently:

1. tuned 2.27 has no bootc-aware bootloader path. When the profile wants kernel arguments, it stages them
   via `rpm-ostree kargs` — a **local deployment** that diverges from the image.
2. On the next boot the kernel sees both the image's arguments and tuned's, and takes the **last**
   `isolcpus`. Nothing reports the duplicate.

This happened to us: an image carried `isolcpus=managed_irq,domain,2-3` while the profile (whose
`isolate_managed_irq` had been dropped) wanted `isolcpus=2-3`. The result was a duplicate `isolcpus` and
an unintended core layout, with no error anywhere.

The fix is to bake the profile's kernel arguments into `/usr/lib/bootc/kargs.d/` at image build time.
tuned 2.27 computes *profile kargs minus what's already on the command line* and appends only the
remainder (`plugin_bootloader.py`, `_rpm_ostree_update()`): if the baked file covers **all** of them,
tuned logs "kernel arguments already set" and touches nothing.

**The critical rule: the kargs.d file must be complete or absent.** A file that covers only *some* of the
profile's arguments makes tuned append exactly the missing ones — producing the duplicate-`isolcpus`
symptom this recipe exists to prevent. An incomplete file is **worse than no file at all**: no file gives
a clean (if local-deployment) tuned path; a partial file gives a silent duplicate.

## What's in the image

Each piece below is marked as either the supported way to do its job, or a workaround — with the RHEL
doc or tuned/bootc source that decides it.

| Piece | Supported, or workaround? |
|---|---|
| `dnf remove kernel…` / `dnf install kernel-rt…`, prune `/usr/lib/modules/*` without `vmlinuz`, empty `/boot` | The prune and `/boot` wipe are the layout `bootc container lint` enforces (single kernel, `/boot` present but empty). The swap mechanics themselves are **undocumented** — no RHEL doc covers replacing the kernel in a bootc Containerfile. Feedback welcome. |
| `/etc/tuned/realtime-variables.conf` | The documented way to parameterize the stock `realtime` profile (the profile's `[variables]` includes this file and asserts `isolated_cores` is set). |
| `/usr/lib/bootc/kargs.d/20-realtime.toml` | The workaround for tuned 2.27 described above. Verified against tuned source. |
| `recommend.d/00-realtime.conf` + `profile_mode=auto` (`select-declarative/`, default) | tuned's own image-native selection path, verified to select and apply `realtime` with no unit. Fresh installs only — bootc's `/etc` merge keeps a pre-existing machine-local `profile_mode`. |
| `realtime-profile.service` (oneshot, `select-unit/`, fallback) | Workaround for hosts that already carry tuned state, where the declarative path cannot engage. Puts tuned in manual mode. |
| `user@.service.d/10-rt-rtprio.conf` | Standard `systemd.exec(5)` `LimitRTPRIO` directive, so rootless apps/containers can use `SCHED_FIFO` (pair with Quadlet `Ulimit=rtprio=99:99`). |
| `realtime-tests`, `stress-ng` | Kept so the example is self-validating (see below). |

No users are created here. Compose this with the [cloud-init](../cloud-init) example, or provision
accounts the way your install path already does.

## Changing the configuration

`isolated_cores` is set in **two places that must agree**: `tune/etc/tuned/realtime-variables.conf` and
the `isolcpus=` entry in `tune/usr/lib/bootc/kargs.d/20-realtime.toml`. To change the isolated cores (or
any other profile variable), regenerate the kargs list rather than editing it by hand:

1. On a **package-mode** RHEL 10.2 test system with the same CPU vendor, apply your configuration:
   `tuned-adm profile realtime`.
2. Read `TUNED_BOOT_CMDLINE` from `/etc/tuned/bootcmdline`. On package mode tuned 2.27 writes the
   profile's full list there (`_grub2_update()`). **Do not do this on a bootc box:** there tuned writes
   only the arguments it had to *append* (`_rpm_ostree_update()`), which is empty or partial when a
   kargs.d file is already present.
3. Write that complete list into `20-realtime.toml`. All of it, or none of it.

`isolated_cores` must name CPUs that are online on the target. The profile asserts this and fails to
apply otherwise.

The shipped list, for reference, is what the stock `realtime` profile (which includes `network-latency`)
generates for `isolated_cores=2-3`, `isolate_managed_irq=Y`, on an **Intel** host:

```
skew_tick=1 tsc=reliable rcupdate.rcu_normal_after_boot=1 rcutree.nohz_full_patience_delay=1000
isolcpus=managed_irq,domain,2-3 intel_pstate=disable nosoftlockup
```

`intel_pstate=disable` comes from the profile's `disable_pstate` variable, which expands via a cpuinfo
check: an **AMD host needs `amd_pstate=disable`** instead. The kargs file is vendor- and
configuration-specific by nature — that is inherent to pre-baking it.

## Profile selection: two options

Why a baked `/etc/tuned/active_profile` doesn't work: the tuned RPM ships `active_profile` and
`profile_mode` as empty files, and tuned writes both when it first picks a profile. After that they
are local modifications, and bootc's three-way `/etc` merge keeps local modifications over whatever a
new image ships. An image copy can therefore only ever win on a fresh install.

**`select-declarative/` (default, verified):** tuned's image-native selection path.
`/usr/lib/tuned/recommend.d/00-realtime.conf` is a recommend section with no match options, so it
matches unconditionally, and it sorts before the package's `50-tuned.conf`. Alongside it,
`/etc/tuned/profile_mode` contains `auto`. Derived from tuned 2.27 source (`profile_recommender.py`,
`daemon.py` `_get_startup_profile`, `commands.py` `get_active_profile`) and then confirmed by running
the daemon against this image:

```
tuned.daemon.daemon: Running in automatic mode, checking what profile is recommended for your configuration.
tuned.daemon.daemon: Using 'realtime' profile
tuned.daemon.daemon: static tuning from profile 'realtime' applied
```

`active_profile` afterwards reads `realtime`, with no selection unit present. `tuned-adm recommend`
returns `realtime` independently. No runtime unit is involved, which is why this is the default.

**Limitation:** because of the `/etc` merge above, it takes effect only on a fresh install, or where
`profile_mode` was never written locally. A deployed system whose `profile_mode` already says `manual`
keeps `manual`, and that includes any box that previously ran `select-unit/`. **Exercise it with a
fresh `bootc install`, not by switching an existing box** — a `bootc switch` test is not merely risky
but inconclusive, since the old machine-local `/etc/tuned` state stays in force.

**`select-unit/` (fallback):** a oneshot unit that runs `tuned-adm profile realtime` after
`tuned.service` if it is not already active. It lives in `/usr`, so unlike the declarative path it
also covers existing deployments that `bootc switch`/`upgrade` onto this image. Side effect: it puts
tuned in manual mode. Use it where hosts already carry tuned state. To switch, in the Containerfile
replace:

```dockerfile
COPY select-declarative/ /
```

with:

```dockerfile
COPY select-unit/ /
RUN systemctl enable realtime-profile.service
```

Worth checking on a real boot either way: that `tuned-adm active` shows `realtime` with
`/etc/tuned/profile_mode` = `auto`, and that a later `tuned-adm profile X` switches to manual mode and
survives a reboot.

## Validating

The image includes `realtime-tests` and `stress-ng` so it can validate itself. On the installed system:

```sh
# as root: latency on the isolated cores while the housekeeping cores are loaded, 60s;
# check the reported max against your requirement
cyclictest -m -p95 -d0 -i1000 -a 2-3 -t 2 -D 60s &
stress-ng --cpu 2 --taskset 0,1 --cpu-load 90 --timeout 60s
wait; tuned-adm verify
```

Also verify the kargs landed as intended: `cat /proc/cmdline` should show exactly **one** `isolcpus`.

## Build

```sh
just build rhel-rt
```

The base image comes from `registry.redhat.io`, so log in first (`podman login registry.redhat.io`),
and the build runs `dnf` inside it, which needs the build host to be registered with a Red Hat
subscription: podman passes the host's entitlement certificates into the build.

**The subscription must also entitle RHEL for Real Time.** Real Time is a separate entitlement from
base RHEL; without it `rhel-10-for-x86_64-rt-rpms` is absent from the host's `redhat.repo` and the
build fails on `kernel-rt`. To check before building:

```sh
dnf repolist --all | grep rt-rpms
```

## Open questions

- **RHEL 10.3 / tuned 2.28:** tuned 2.28 gained bootc support (`bootc loader-entries
  set-options-for-source`) and no longer takes the `rpm-ostree` path. Whether a pre-baked `kargs.d` file
  and tuned's BLS write **deduplicate** identical arguments on 2.28 is unverified. Until tested, this
  example is scoped to RHEL 10.2 and the kargs.d file is "required on 10.2, unverified on 10.3".
- **Kernel swap mechanics** are not documented anywhere we could find; the `dnf remove`/`dnf install`
  pair is the obvious reading and produces a lint-clean image, but upstream confirmation would be good.
- **The declarative profile selection** (above) is verified for the selection decision but limited to
  fresh installs. Running the daemon against this image's `/etc/tuned` state logs `Running in automatic
  mode` then `Using 'realtime' profile`, applies it, and writes `active_profile=realtime`, with no unit
  present; `tuned-adm recommend` agrees. What that does not cover is real boot ordering and the
  bootloader plugin, which still want a boot on hardware.
- **Why `--releasever=10.2` is not cosmetic.** 10.3 content is not hypothetical: as of 2026-11-18 the
  rolling `/content/dist/rhel10/10/...` path already serves `kernel-rt-6.12.0-264.16.1.el10_3` and
  `tuned-2.28.0-1.el10`, confirmed by comparing `primary.xml` between the `10/` and `10.2/` paths. An
  unpinned build would today install a 10.3 kernel-rt onto the 10.2 base image whose own `kernel` has
  just been removed — a kernel/userspace mismatch, not just a scoping question. The same comparison
  shows `10.2/` caps at `tuned-2.27.0-2.el10_2` and `kernel-rt-6.12.0-211.74.1.el10_2`, which matches
  the base image's own removed kernel version.
- **`/etc` merge and `realtime-variables.conf`:** if an admin edits this file on a deployed system, the
  local copy wins over later image versions while `kargs.d` keeps tracking the image. The two can then
  drift apart, which is the incomplete-kargs failure mode. Treat this file as image-owned.

This example was prepared with assistance from AI tools. The tuned and bootc behaviour described above
was checked against upstream source rather than inferred — `plugin_bootloader.py`, `daemon.py`,
`profile_recommender.py`, `consts.py` in tuned 2.27, and `lints.rs` in bootc.
