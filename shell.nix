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
    flamegraph
  ] ++ (lib.optionals pkgs.stdenv.isLinux ([
    linuxKernel.packages.linux_6_6.perf
  ]));
}
