{
  description = "dev shell for blog.ihaterelity.space";

  inputs = {
    nixpkgs.url   = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      forEachSystem = lib.genAttrs lib.systems.flakeExposed;
    in
    {
      devShells = forEachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system}.pkgs;
        in
        {
          default = pkgs.mkShell {
            name = "I hate reality shhhheeeeklkllll";
            packages = [
              pkgs.zola
            ];
          };
        }
      );
    };
}
