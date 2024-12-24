(import ./test.nix) {
  name = "crowdsec-engine-patterns";
  nodes = {
    # `self` here is set by using specialArgs in `test.nix`
    machine = {
      self,
      pkgs,
      ...
    }: {
      imports = [self.nixosModules.crowdsec];
      services.crowdsec = {
        enable = true;
        patterns = [ (pkgs.writeTextDir "aws" "# not the default aws pattern") ];
      };
    };
  };
  testScript = {nodes, ...}: ''
    output = machine.succeed("cat ${nodes.machine.config.services.crowdsec.settings.config_paths.pattern_dir}/ssh")
    assert "sshd grok pattern" in output

    output = machine.succeed("cat ${nodes.machine.config.services.crowdsec.settings.config_paths.pattern_dir}/aws")
    assert "not the default aws pattern" in output, output
  '';
}
