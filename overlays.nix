{
  self,
  lib,
  inputs,
}: let
  mkDate = longDate: (lib.concatStringsSep "-" [
    (builtins.substring 0 4 longDate)
    (builtins.substring 4 2 longDate)
    (builtins.substring 6 2 longDate)
  ]);
  branch = "dev";
  ver = "latest";
in {
  default = lib.composeManyExtensions (with self.overlays; [
    zen-browser-packages
  ]);

  zen-browser-packages = lib.composeManyExtensions [
    (final: _prev: let
      date = mkDate (self.lastModifiedDate or "19700101");
      version = "${ver}-${branch}+date=${date}_${self.shortRev or "dirty"}";
    in {
      zen-browser-unwrapped = final.callPackage (import ./unwrapped.nix {
        name = "zen-browser";
        firefox-src = inputs.firefox-src;
        zen-src = inputs.zen-browser-src;
        zen-l10n = inputs.zen-l10n;
        zen-version = ver;
        llvmBuildPackages = final.llvmPackages_20;
        ltoSupport = false;
        inherit version;
      }) {};

      #zen-browser = final.zen-browser-unwrapped;
      zen-browser = (import ./default.nix {
        wrapFirefox = _prev.buildPackages.wrapFirefox;
        zen-browser-unwrapped = final.zen-browser-unwrapped;
      });
    })
  ];
}
