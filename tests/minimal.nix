(import ./test.nix) {
  name = "crowdsec-engine-minimal";
  nodes = {
    # `self` here is set by using specialArgs in `test.nix`
    node1 = {
      self,
      pkgs,
      ...
    }: {
      imports = [self.nixosModules.crowdsec];
      services.crowdsec = {
        enable = true;
      };
    };
  };
  testScript = ''
    start_all()

    node1.wait_for_unit("crowdsec")
    node1.wait_for_open_port(8080)

    output = node1.wait_until_succeeds("cscli lapi status")
    assert "You can successfully interact with Local API" in output
  '';
}
