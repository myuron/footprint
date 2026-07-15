{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    agent-skills.url = "github:Kyure-A/agent-skills-nix";
    anthropic-skills = {
      url = "github:anthropics/skills";
      flake = false;
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      treefmt-nix,
      agent-skills,
      anthropic-skills,
      rust-overlay,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };
        agentLib = agent-skills.lib.agent-skills;
        sources = {
          anthropic = {
            path = anthropic-skills;
            subdir = "skills";
          };
        };
        catalog = agentLib.discoverCatalog sources;
        allowlist = agentLib.allowlistFor {
          inherit catalog sources;
          enable = [
            "doc-coauthoring"
            "skill-creator"
          ];
        };
        selection = agentLib.selectSkills {
          inherit catalog allowlist sources;
          skills = { };
        };
        bundle = agentLib.mkBundle { inherit pkgs selection; };
        localTargets = {
          claude = agentLib.defaultLocalTargets.claude // {
            enable = true;
          };
        };
      in
      {
        formatter = treefmt-nix.lib.mkWrapper pkgs {
          projectRootFile = "flake.nix";
          programs = {
            nixfmt.enable = true;
            rustfmt.enable = true;
            prettier.enable = true;
          };
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            pkgs.rust-bin.stable.latest.default
            gh
            ripgrep
            fd
            jq
          ];
        };

        packages.default = pkgs.callPackage ./nix/rust.nix { };

        apps = {
          lint = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "lint" ''
                cargo clippy
              ''
            );
          };

          test = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "test" ''
                cargo test
              ''
            );
          };

          skills = {
            type = "app";
            program = "${
              agentLib.mkLocalInstallScript {
                inherit pkgs bundle;
                targets = localTargets;
              }
            }/bin/skills-install-local";
          };
        };
      }
    );
}
