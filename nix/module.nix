{ self }:
{ config
, lib
, pkgs
, ...
}:

let
  cfg = config.services.nerdctl;

  socketPath = "/run/containerd-stargz-grpc/containerd-stargz-grpc.sock";

  snapshotterFormat = pkgs.formats.toml { };
  snapshotterConfig = snapshotterFormat.generate "stargz-config.toml" cfg.snapshotter.settings;
in
{
  options.services.nerdctl = {
    enable = lib.mkEnableOption ''
      nerdctl with containerd and the stargz-snapshotter, enabling creation and
      lazy consumption of eStargz and zstd:chunked OCI images'';

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.nerdctl;
      defaultText = lib.literalExpression "nerdctl-flake.packages.\${system}.nerdctl";
      description = "The nerdctl package to install (with eStargz/zstd:chunked helpers).";
    };

    snapshotter.package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.stargz-snapshotter;
      defaultText = lib.literalExpression "nerdctl-flake.packages.\${system}.stargz-snapshotter";
      description = "The stargz-snapshotter package providing containerd-stargz-grpc.";
    };

    snapshotter.settings = lib.mkOption {
      type = snapshotterFormat.type;
      default = { };
      example = lib.literalExpression ''
        {
          no_prometheus = true;
        }
      '';
      description = ''
        Configuration for containerd-stargz-grpc, rendered to
        /etc/containerd-stargz-grpc/config.toml. The defaults already support
        both eStargz and zstd:chunked, so this can usually stay empty.
      '';
    };

    setContainerdSnapshotter = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Configure containerd's image unpacking to prefer the stargz snapshotter,
        so lazy pulling works without passing --snapshotter=stargz on every call.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
      cfg.snapshotter.package
      pkgs.cni-plugins
    ];

    virtualisation.containerd.enable = true;

    virtualisation.containerd.settings = {
      # containerd 2.x needs config schema v3 for the transfer-service
      # unpack_config below to take effect.
      version = lib.mkForce 3;

      proxy_plugins.stargz = {
        type = "snapshot";
        address = socketPath;
      };
    }
    // lib.optionalAttrs cfg.setContainerdSnapshotter {
      plugins."io.containerd.transfer.v1.local".unpack_config = [
        {
          # containerd rejects a bare "linux"; the platform must be arch-qualified.
          platform = "linux/${pkgs.go.GOARCH}";
          snapshotter = "stargz";
        }
      ];
    };

    boot.kernelModules = [ "fuse" ];

    systemd.services.containerd-stargz-grpc = {
      description = "stargz-snapshotter (containerd-stargz-grpc) - lazy image pulling";
      documentation = [ "https://github.com/containerd/stargz-snapshotter" ];
      wantedBy = [ "multi-user.target" ];
      before = [ "containerd.service" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [ pkgs.fuse3 ];
      serviceConfig = {
        Type = "notify";
        ExecStart = "${cfg.snapshotter.package}/bin/containerd-stargz-grpc "
          + "--address ${socketPath} "
          + "--config ${snapshotterConfig}";
        Restart = "always";
        RestartSec = "1";
        RuntimeDirectory = "containerd-stargz-grpc";
        StateDirectory = "containerd-stargz-grpc";
        KillMode = "mixed";
        Delegate = "yes";
        OOMScoreAdjust = "-999";
      };
    };
  };
}
