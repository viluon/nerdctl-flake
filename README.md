> [!WARNING]
> Created by GitHub Copilot CLI, Claude Opus 4.8.

# nerdctl-flake

A clean Nix flake that builds [`nerdctl`](https://github.com/containerd/nerdctl)
with **eStargz** and **zstd:chunked** support, and exposes a NixOS module that
wires up everything needed to *create* and *lazily consume* these OCI images.

nixpkgs only packages the `nerdctl` binary — it ships neither a NixOS module nor
the [`stargz-snapshotter`](https://github.com/containerd/stargz-snapshotter)
(which is required for lazy pulling). This flake fills both gaps.

## What you get

- `packages.nerdctl` — nerdctl built from source, wrapped with `buildkit`,
  `cni-plugins`, and the `zstd` / `pigz` helpers used when converting images to
  eStargz or zstd:chunked.
- `packages.stargz-snapshotter` — the `containerd-stargz-grpc` daemon and helper
  binaries (`ctr-remote`, `stargz-store`, `stargz-fuse-manager`), packaged here
  because they are absent from nixpkgs.
- `nixosModules.default` — a `services.nerdctl` module that enables containerd,
  registers the stargz proxy snapshotter, and runs `containerd-stargz-grpc`.
- `checks.integration` — a NixOS VM test covering the full
  produce → push → lazy-pull → run cycle for **both** formats.

## Usage

Add the flake as an input and import the module:

```nix
{
  inputs.nerdctl-flake.url = "github:youruser/nerdctl-flake";

  outputs = { nixpkgs, nerdctl-flake, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nerdctl-flake.nixosModules.default
        { services.nerdctl.enable = true; }
      ];
    };
  };
}
```

### Create an eStargz or zstd:chunked image

```console
# eStargz (gzip-based)
$ nerdctl image convert --oci --estargz example.com/foo:orig example.com/foo:esgz

# zstd:chunked (zstd-based)
$ nerdctl image convert --oci --zstdchunked example.com/foo:orig example.com/foo:zstd

$ nerdctl push example.com/foo:esgz
```

`--estargz` and `--zstdchunked` are mutually exclusive: they are the gzip and
zstd variants of the same lazy-pulling scheme.

### Lazily consume an image

```console
$ nerdctl pull --snapshotter=stargz example.com/foo:esgz
$ nerdctl run  --snapshotter=stargz example.com/foo:esgz
```

With `services.nerdctl.setContainerdSnapshotter = true` (the default), containerd
also selects the stargz snapshotter automatically when unpacking.

## Development

```console
$ nix develop        # nerdctl, stargz-snapshotter, containerd, buildkit, cni
$ nix fmt            # format with treefmt (nixpkgs-fmt)
$ nix flake check    # build packages, check formatting, run the VM test
```

## Module options

| Option | Default | Description |
| --- | --- | --- |
| `services.nerdctl.enable` | `false` | Enable nerdctl + containerd + stargz-snapshotter. |
| `services.nerdctl.package` | this flake's `nerdctl` | The nerdctl package to install. |
| `services.nerdctl.snapshotter.package` | this flake's `stargz-snapshotter` | The snapshotter package. |
| `services.nerdctl.snapshotter.settings` | `{ }` | Extra `containerd-stargz-grpc` config (TOML). |
| `services.nerdctl.setContainerdSnapshotter` | `true` | Prefer the stargz snapshotter when containerd unpacks images. |
