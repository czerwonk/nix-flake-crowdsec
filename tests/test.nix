test: {
  pkgs,
  self,
}: let
  inherit (pkgs) lib;
  nixos-lib = import (pkgs.path + "/nixos/lib") {};
in
  (nixos-lib.runTest {
    hostPkgs = pkgs;
    defaults.documentation.enable = lib.mkDefault false;
    # This makes `self` available in the NixOS configuration of the virtual machines.
    # This is useful for referencing modules or packages from the flake itself
    # as well as importing from other flakes.
    node.specialArgs = {inherit self;};
    imports = [test];
  })
  .config
  .result
