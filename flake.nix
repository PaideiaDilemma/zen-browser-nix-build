{
  description = "Zen Browser Nix Build";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default-linux";

    zen-browser-src = {
      url = "github:zen-browser/desktop";
      flake = false;
    };

    zen-l10n = {
      url = "github:zen-browser/l10n-packs";
      flake = false;
    };

    firefox-src = {
      # For stable
      url = "https://archive.mozilla.org/pub/firefox/releases/141.0/source/firefox-141.0.source.tar.xz";
      #url = "https://archive.mozilla.org/pub/firefox/candidates/141.0-candidates/build1/source/firefox-141.0.source.tar.xz";
      flake = false;
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    systems,
    ...
  }: let
    inherit (nixpkgs) lib;
    eachSystem = lib.genAttrs (import systems);
    pkgsFor = eachSystem (system:
      import nixpkgs {
        localSystem = system;
        overlays = [self.overlays.zen-browser-packages];
      });
  in {
    overlays = import ./overlays.nix {inherit self lib inputs;};

    packages = eachSystem (system: {
      default = self.packages.${system}.zen-browser;
      zen-browser = pkgsFor.${system}.zen-browser;
      zen-browser-unwrapped = pkgsFor.${system}.zen-browser-unwrapped;
    });

    devShells = eachSystem (system: {
      default =
        pkgsFor.${system}.mkShell.override {
          inherit (self.packages.${system}.default) stdenv;
        } {
          name = "zen-browser-shell";
          hardeningDisable = ["fortify"];
          inputsFrom = [pkgsFor.${system}.zen-browser-unwrapped];
          packages = [pkgsFor.${system}.clang-tools];
        };
    });
  };
}
