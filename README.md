Unofficial build for the zen browser.

I am using this myself until zen lands in nixpkgs.
The `postPatch` phase in `default.nix` shows how to patches
the firefox source without [surfer](https://github.com/zen-browser/surfer) and could be interesting for anyone wanting to build zen without it.
