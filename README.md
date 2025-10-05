I gave the zen browser a try because it was recommended to me, so I made this package, because I didn't like it's build relying on a weird javascript tool.
But after using it a bit I couldn't get any use out of it's features.
None of them felt like they legitimized a whole different browser version.

Unofficial build for the zen browser.

I am using this myself until zen lands in nixpkgs.
The `postPatch` phase in `default.nix` shows how to patches
the firefox source without [surfer](https://github.com/zen-browser/surfer) and could be interesting for anyone wanting to build zen without it.
