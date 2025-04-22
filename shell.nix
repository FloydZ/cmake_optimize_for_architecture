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
    cudaPackages.cuda_nvcc
    cudaPackages.cuda_cudart
  ] ++ (lib.optionals pkgs.stdenv.isLinux ([
    linuxKernel.packages.linux_6_6.perf
  ]));
}
