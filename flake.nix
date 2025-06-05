{
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-25.05;
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }: let

    version = self.rev or "dirty";

    overlay = final: prev: {
      testrun = final.callPackage ./package.nix {
        inherit version;
        epkgs = final.emacsPackagesFor final.emacs;
      };
    };

    emacs-without-native-comp-overlay = final: prev: {
      emacs = prev.emacs.override { withNativeCompilation = false; };
    };

    empty-overlay = final: prev: {};

    # https://github.com/NixOS/nixpkgs/issues/395169
    overlay-map = {
      "x86_64-darwin"  = emacs-without-native-comp-overlay;
      "aarch64-darwin" = emacs-without-native-comp-overlay;
      "x86_64-linux"   = empty-overlay;
      "aarch64-linux"  = empty-overlay;
    };

    out = system: let
      pkgs = import nixpkgs { inherit system; overlays = [overlay-map.${system}]; };
    in {
      packages.default = (self.overlays.default pkgs pkgs).testrun;
    };

  in flake-utils.lib.eachDefaultSystem out // {
    overlays.default = overlay;
  };
}
