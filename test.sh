#!/usr/bin/env bash
set -e
#
archs=( "none" "generic" "core" "merom" "penryn" "nehalem" "westmere" "sandy-bridge" "ivy-bridge" "tremont" "goldmontplus" "airmont" "saltwell" "bonnwell" "haswell" "broadwell" "haswell-server" "broadwell-server" "skylake" "skylake-server" "silvermont" "goldmont" "knl" "atom" "emerald-rapids-server" "sapphire-rapids-server" "raptorlake" "alderlake" "lakefield" "rocketlake" "tigerlake" "icelake" "kabylake" "cannonlake" "nehalem-server" "westmere-server" "sandybridge-server" "ivybridge-server" "cascadelake-server" "cooperlake-server" "icelake-server" "granite-rapids-server" "granite-rapids-d-server" "diamond-rapids-server" "knm" "gracemont" "sierraforest" "grandridge" "clearwaterforest" "cometlake" "meteorlake" "arrowlake" "arrowlake-s" "lunarlake" "pantherlake" "wildcatlake" "novalake" "k8" "k8-sse3" "barcelona" "istanbul" "magny-cours" "bulldozer" "interlagos" "piledriver" "steamroller" "excavator" "jaguar" "puma" "zen" "zenplus" "zen2" "zen3" "zen4" "zen5" "zen6" "zen_china" "c86-4g-m7" "lujiazui" "yongfeng" "shijidadao" )

for arch in "${archs[@]}"
do
    echo "${arch}"
    rm -rf ./build
    mkdir ./build
    cd ./build
    cmake .. -DTARGET_ARCHITECTURE="${arch}"
    cd ..
done
