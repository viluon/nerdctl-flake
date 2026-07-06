{ lib
, buildGoModule
, src
, version
, makeWrapper
, installShellFiles
, buildkit
, cni-plugins
, zstd
, pigz
, writableTmpDirAsHomeHook
, extraPackages ? [ ]
,
}:

# Built from the upstream GitHub source (pinned flake input). Beyond the nixpkgs
# package this wires in zstd + pigz so nerdctl can *create* eStargz/zstd:chunked
# images. Lazy pulling (consuming) is handled by stargz-snapshotter.
buildGoModule {
  pname = "nerdctl";
  inherit version src;

  vendorHash = "sha256-BmlcW3svWyK55rduTiPOZbIN9bLc+v9yvzlDwrZPniA=";

  nativeBuildInputs = [
    makeWrapper
    installShellFiles
    writableTmpDirAsHomeHook
  ];

  ldflags =
    let
      t = "github.com/containerd/nerdctl/v${lib.versions.major version}/pkg/version";
    in
    [
      "-s"
      "-w"
      "-X ${t}.Version=v${version}"
      "-X ${t}.Revision=<unknown>"
    ];

  # tigron is an extra test-only Go application in a separate module.
  excludedPackages = [ "mod/tigron" ];

  # Most tests need a live containerd socket.
  doCheck = false;

  postInstall = ''
    wrapProgram $out/bin/nerdctl \
      --prefix PATH : "${lib.makeBinPath ([ buildkit zstd pigz ] ++ extraPackages)}" \
      --prefix CNI_PATH : "${cni-plugins}/bin"

    installShellCompletion --cmd nerdctl \
      --bash <($out/bin/nerdctl completion bash) \
      --fish <($out/bin/nerdctl completion fish) \
      --zsh <($out/bin/nerdctl completion zsh)
  '';

  meta = {
    description = "Docker-compatible CLI for containerd, with eStargz and zstd:chunked support";
    homepage = "https://github.com/containerd/nerdctl/";
    changelog = "https://github.com/containerd/nerdctl/releases/tag/v${version}";
    license = lib.licenses.asl20;
    mainProgram = "nerdctl";
    platforms = lib.platforms.linux;
  };
}
