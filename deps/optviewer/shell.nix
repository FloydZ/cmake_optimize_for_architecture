# shell.nix
{ pkgs ? import <nixpkgs> {} }:

let
  myPython = pkgs.python311;
  pythonPackages = pkgs.python311Packages;
  pythonWithPkgs = myPython.withPackages (pythonPkgs: with pythonPkgs; [
    ipython
    pip
    setuptools
    virtualenv
    wheel
    black
    prophet
  ]);

  extraBuildInputs = with pkgs; [
    pythonPackages.pyaml
    clang
  ];
in
import ./python-shell.nix { 
    extraBuildInputs=extraBuildInputs; 
    # extraLibPackages=extraLibPackages; 
    myPython=myPython;
    pythonWithPkgs=pythonWithPkgs;
  }

