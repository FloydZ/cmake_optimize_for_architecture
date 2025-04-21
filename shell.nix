with import <nixpkgs> {};
{ pkgs ? import <nixpkgs> {} }:

stdenv.mkDerivation {
  name = "cmake`";
  src = ./.;

  buildInputs = [ 
    cmake
	gnumake 
    clang

    # additional features
    bloaty
  ] ++ (lib.optionals pkgs.stdenv.isLinux ([
  ]));
}
