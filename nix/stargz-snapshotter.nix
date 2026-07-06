{ lib
, buildGoModule
, src
, version
, fuse3
, makeWrapper
,
}:

# Not packaged in nixpkgs. The buildable commands live in the ./cmd sub-module.
buildGoModule {
  pname = "stargz-snapshotter";
  inherit version src;

  modRoot = "cmd";

  vendorHash = "sha256-aHQsU6u7yXGdKI8exesqVZc51UP3jh8Q7bM67cKsbgk=";

  subPackages = [
    "containerd-stargz-grpc"
    "ctr-remote"
    "stargz-store"
    "stargz-fuse-manager"
  ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/containerd/stargz-snapshotter/version.Version=v${version}"
  ];

  nativeBuildInputs = [ makeWrapper ];

  # Daemons shell out to fusermount3 at runtime.
  postInstall = ''
    for b in containerd-stargz-grpc stargz-store stargz-fuse-manager; do
      wrapProgram $out/bin/$b \
        --prefix PATH : "${lib.makeBinPath [ fuse3 ]}"
    done
  '';

  # Integration tests need root, containerd and network access.
  doCheck = false;

  meta = {
    description = "Fast container image distribution plugin with lazy pulling (eStargz, zstd:chunked)";
    homepage = "https://github.com/containerd/stargz-snapshotter";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    mainProgram = "containerd-stargz-grpc";
  };
}
