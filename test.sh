#!/usr/bin/env bash
set -e
#
archs=( "none" "generic" "core" "merom" "penryn" "nehalem" "westmere" "sandy-bridge" "ivy-bridge" "tremont" "goldmontplus" "airmont" "saltwell" "bonnwell" "haswell" "broadwell" "haswell-server" "broadwell-server" "skylake" "skylake-server" "silvermont" "goldmont" "knl" "atom" "emerald-rapids-server" "sapphire-rapids-server" "raptorlake" "alderlake" "lakefield" "rocketlake" "tigerlake" "icelake" "kabylake" "cannonlake" "k8" "k8-sse3" "barcelona" "istanbul" "magny-cours" "bulldozer" "interlagos" "piledriver" "zen"  "zen2"  "zen3"  "zen4"  "zen5"  "zen6" )

for arch in "${archs[@]}"
do
    echo "${arch}"
    rm -rf ./build
    mkdir ./build
    cd ./build
    cmake .. -DTARGET_ARCHITECTURE="${arch}"
    cd ..
done
