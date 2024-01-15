{ pkgs
, stdenv
, flags ? ["-O2"]}:
let
in
stdenv.mkDerivation {
  name = "test cmake";
  src = ./.;

  buildInputs = with pkgs; [
    cmake
  ];

  installPhase = ''
    mkdir -p $out/bin
  '';
}
