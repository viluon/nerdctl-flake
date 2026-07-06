{ self }:
{ pkgs, ... }:

let
  # A tiny self-contained OCI image built entirely offline with nix, so the VM
  # test needs no network to obtain a base image. It just prints a marker.
  marker = "hello-from-estargz-zstdchunked";
  testImage = pkgs.dockerTools.buildImage {
    name = "local/testimg";
    tag = "orig";
    copyToRoot = pkgs.buildEnv {
      name = "testimg-root";
      paths = [
        pkgs.bashInteractive
        pkgs.coreutils
      ];
      pathsToLink = [ "/bin" ];
    };
    config.Cmd = [
      "/bin/echo"
      marker
    ];
  };

  # Minimal registry config for a plain-HTTP local registry on :5000.
  registryConfig = pkgs.writeText "registry-config.yml" (builtins.toJSON {
    version = "0.1";
    storage.filesystem.rootdirectory = "/var/lib/registry";
    storage.delete.enabled = true;
    http.addr = ":5000";
  });
in
pkgs.testers.nixosTest {
  name = "nerdctl-estargz-zstdchunked";

  nodes.machine =
    { ... }:
    {
      imports = [ self.nixosModules.default ];
      services.nerdctl.enable = true;

      # Local, plain-HTTP registry so we can push/pull the converted image
      # without any external network access.
      systemd.services.registry = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.distribution}/bin/registry serve ${registryConfig}";
          StateDirectory = "registry";
          Restart = "always";
        };
      };

      virtualisation.memorySize = 3072;
      virtualisation.diskSize = 6144;
    };

  testScript = ''
    ref = "localhost:5000/testimg"

    machine.start()
    machine.wait_for_unit("containerd.service")
    machine.wait_for_unit("containerd-stargz-grpc.service")
    machine.wait_for_unit("registry.service")
    machine.wait_for_open_port(5000)

    machine.wait_until_succeeds("nerdctl info 2>&1 | grep -i stargz")

    # Import the offline-built base image into containerd. We use ctr rather than
    # `nerdctl load` because nerdctl's loader goes through containerd's transfer
    # service, which rejects tar imports with "no unpack platforms defined".
    machine.succeed(
        "ctr -n default images import --platform linux/${pkgs.go.GOARCH} ${testImage}"
    )

    # eStargz (gzip) and zstd:chunked (zstd) are the two mutually-exclusive
    # lazy-pulling formats. Exercise both end to end: produce -> push -> lazy
    # pull -> run.
    for tag, convert_flag in [
        ("estargz", "--estargz"),
        ("zstdchunked", "--zstdchunked"),
    ]:
        image = ref + ":" + tag

        machine.succeed(
            "nerdctl image convert --oci " + convert_flag + " local/testimg:orig " + image
        )
        machine.succeed("nerdctl push --insecure-registry " + image)

        # Drop the converted image locally so the next pull must be lazy.
        machine.succeed("nerdctl rmi -f " + image)

        machine.succeed(
            "nerdctl pull --snapshotter=stargz --insecure-registry " + image
        )

        # Run a detached container so the lazy FUSE mount stays observable, then
        # confirm both that the image works and that it was mounted lazily by the
        # stargz snapshotter (rather than fully unpacked).
        name = "c-" + tag
        machine.succeed(
            "nerdctl run -d --name " + name + " --snapshotter=stargz "
            + "--insecure-registry " + image + " sleep 60"
        )
        machine.wait_until_succeeds(
            "mount | grep -E 'stargz|fuse.rawBridge'", timeout=30
        )
        out = machine.succeed(
            "nerdctl exec " + name + " echo ${marker}"
        )
        assert "${marker}" in out, f"unexpected output for {tag}: {out!r}"
        machine.succeed("nerdctl rm -f " + name)
  '';
}
