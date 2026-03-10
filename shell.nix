with import <nixpkgs> {};
{ pkgs ? import <nixpkgs> {} }:
let 
  b = [
    cmake
	gnumake 
    clang

    # additional features
    bloaty                    # well for bloaty
    flamegraph                # well for flamegraphs
    #cudaPackages.cuda_nvcc    # for cuda sm tests
    #cudaPackages.cuda_cudart
    python3                 # for optviewer
    python3Packages.pyaml
    python3Packages.pygments
    python3Packages.virtualenv
  ];

  lib-path = lib.makeLibraryPath b;
in
stdenv.mkDerivation {
  name = "cmake`";
  src = ./.;
  
  buildInputs = b ++ (lib.optionals pkgs.stdenv.isLinux ([
    linuxKernel.packages.linux_6_6.perf
  ]));

  shellHook = ''
    # Allow the use of wheels.
    SOURCE_DATE_EPOCH=$(date +%s)
    # Augment the dynamic linker path
    export "LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${lib-path}"
    # Setup the virtual environment if it doesn't already exist.
    VENV=.venv
    if test ! -d $VENV; then
      virtualenv $VENV
    fi
    source ./$VENV/bin/activate
    export PYTHONPATH=$PYTHONPATH:`pwd`/$VENV/${python311.sitePackages}/
  '';
}
