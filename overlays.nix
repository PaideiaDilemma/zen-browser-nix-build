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
  ver = "latest";
in {
  default = lib.composeManyExtensions (with self.overlays; [
    zen-browser-packages
  ]);

  zen-browser-packages = lib.composeManyExtensions [
    (final: _prev: let
      date = mkDate (self.lastModifiedDate or "19700101");
      version = "${ver}+date=${date}_${self.shortRev or "dirty"}";
    in {
      zen-browser = final.callPackage (import ./default.nix {
        name = "zen-browser";
        firefox-src = inputs.firefox-src;
        zen-src = inputs.zen-browser-src;
        zen-l10n = inputs.zen-l10n;
        zen-version = ver;
        branch = "main";
        llvmBuildPackages = final.llvmPackages_20;
        ltoSupport = false;
        inherit version;
      }) {};
    })
  ];
}
