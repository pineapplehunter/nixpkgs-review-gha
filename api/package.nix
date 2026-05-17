{
  crane,
  lib,
  pkgs,
  versionCheckHook,
  cacert,
}:

let
  craneLib = crane.mkLib pkgs;

  commonArgs = {
    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        ./Cargo.lock
        ./Cargo.toml
        ./src
        ./templates
      ];
    };

    cargoArtifacts = craneLib.buildDepsOnly commonArgs;
  };
in

craneLib.buildPackage (
  commonArgs
  // {
    nativeCheckInputs = [ cacert ];

    nativeInstallCheckInputs = [ versionCheckHook ];
    versionCheckProgramArg = "--version";
    doInstallCheck = true;

    passthru.clippy = craneLib.cargoClippy (
      commonArgs // { cargoClippyExtraArgs = "--all-targets -- --deny warnings"; }
    );

    meta = {
      description = "HTTP API server for nixpkgs-review-gha";
      homepage = "https://github.com/Defelo/nixpkgs-review-gha";
      license = lib.licenses.mit;
      mainProgram = "nrgha-api";
      maintainers = with lib.maintainers; [ defelo ];
    };
  }
)
