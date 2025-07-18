/*
This package has been copied from the nixpkgs source repository.
All rights apply.

Copyright (c) 2003-2024 Eelco Dolstra and the Nixpkgs/NixOS contributors
Copyright (c) 2024 Christian Kampka

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  installShellFiles,
}:
buildGoModule rec {
  pname = "crowdsec";
  version = "1.6.8";

  src = fetchFromGitHub {
    owner = "crowdsecurity";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-/NTlj0kYCOMxShfoKdmouJTiookDjccUj5HFHLPn5HI=";
  };

  vendorHash = "sha256-7587ezh/9C69UzzQGq3DVGBzNEvTzho/zhRlG6g6tkk=";

  nativeBuildInputs = [installShellFiles];

  outputs = ["out" "patterns"];

  subPackages = [
    "cmd/crowdsec"
    "cmd/crowdsec-cli"
  ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/crowdsecurity/go-cs-lib/version.Version=v${version}"
    "-X github.com/crowdsecurity/go-cs-lib/version.BuildDate=1970-01-01_00:00:00"
    "-X github.com/crowdsecurity/go-cs-lib/version.Tag=${src.rev}"
    "-X github.com/crowdsecurity/crowdsec/pkg/cwversion.Codename=alphaga"
    "-X github.com/crowdsecurity/crowdsec/pkg/csconfig.defaultConfigDir=/etc/crowdsec"
    "-X github.com/crowdsecurity/crowdsec/pkg/csconfig.defaultDataDir=/var/lib/crowdsec/data"
  ];

  postBuild = "mv $GOPATH/bin/{crowdsec-cli,cscli}";

  postInstall = ''
    mkdir -p $out/share/crowdsec
    cp -r ./config $out/share/crowdsec/

    mkdir -p $patterns
    mv ./config/patterns/* $patterns

    installShellCompletion --cmd cscli \
      --bash <($out/bin/cscli completion bash) \
      --fish <($out/bin/cscli completion fish) \
      --zsh <($out/bin/cscli completion zsh)
  '';

  # It's important that the version is correctly set as it also determines feature capabilities
  checkPhase = ''
    $GOPATH/bin/cscli version 2>&1 | grep -q "version: v${version}"
  '';

  meta = with lib; {
    homepage = "https://crowdsec.net/";
    changelog = "https://github.com/crowdsecurity/crowdsec/releases/tag/v${version}";
    description = "CrowdSec is a free, open-source and collaborative IPS";
    longDescription = ''
      CrowdSec is a free, modern & collaborative behavior detection engine,
      coupled with a global IP reputation network. It stacks on fail2ban's
      philosophy but is IPV6 compatible and 60x faster (Go vs Python), uses Grok
      patterns to parse logs and YAML scenario to identify behaviors. CrowdSec
      is engineered for modern Cloud/Containers/VM based infrastructures (by
      decoupling detection and remediation). Once detected you can remedy
      threats with various bouncers (firewall block, nginx http 403, Captchas,
      etc.) while the aggressive IP can be sent to CrowdSec for curation before
      being shared among all users to further improve everyone's security.
    '';
    license = licenses.mit;
  };
}
