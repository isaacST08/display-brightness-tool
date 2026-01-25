{
  description = "CLI tool to control the brightness of desktop monitors";

  inputs = {
    nixpkgs.url = "github:Nixos/nixpkgs/nixos-25.11";
    zig2nix.url = "github:Cloudef/zig2nix";
  };

  outputs = {zig2nix, ...}: let
    flake-utils = zig2nix.inputs.flake-utils;
  in (flake-utils.lib.eachDefaultSystem (system: let
    # Zig flake helper
    # Check the flake.nix in zig2nix project for more options:
    # <https://github.com/Cloudef/zig2nix/blob/master/flake.nix>
    env = zig2nix.outputs.zig-env.${system} {
      zig = zig2nix.outputs.packages.${system}.zig-0_15_2;
    };
  in
    with builtins;
    with env.pkgs.lib; rec {
      packages.default = env.package rec {
        src = cleanSource ./.;

        # Packages required for compiling
        nativeBuildInputs = with env.pkgs; [ddcutil];

        # Packages required for linking
        buildInputs = with env.pkgs; [ddcutil];

        # Prefer nix friendly settings.
        zigPreferMusl = false;

        # Executables required for runtime
        # These packages will be added to the PATH
        zigWrapperBins = with env.pkgs; [ddcutil];

        # Libraries required for runtime
        # These packages will be added to the LD_LIBRARY_PATH
        zigWrapperLibs = with env.pkgs; [ddcutil];

        postInstall = ''
          mkdir -p "$out/share/bash-completion/completions"
          cp "${src}/shell_completions/display-brightness-tool.bash" "$out/share/bash-completion/completions/"
        '';
      };

      # nix run .
      apps.default = env.app [] "zig build run -- \"$@\"";

      # nix run .#build
      apps.build = env.app [] "zig build \"$@\"";

      # nix run .#test
      apps.test = env.app [] "zig build test -- \"$@\"";

      # nix run .#docs
      apps.docs = env.app [] "zig build docs -- \"$@\"";

      # nix run .#zig2nix
      apps.zig2nix = env.app [] "zig2nix \"$@\"";

      # nix develop
      devShells.default = env.mkShell {
        # Packages required for compiling, linking and running
        # Libraries added here will be automatically added to the LD_LIBRARY_PATH and PKG_CONFIG_PATH
        nativeBuildInputs =
          []
          ++ packages.default.nativeBuildInputs
          ++ packages.default.buildInputs
          ++ packages.default.zigWrapperBins
          ++ packages.default.zigWrapperLibs;
      };
    }));
}
