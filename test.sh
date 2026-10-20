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

# 64 bit ARM targets, configured as an aarch64 Linux build. Without an aarch64
# compiler this only checks the names (the -mcpu flag is then not added). Set
# ARM_CC/ARM_CXX to an aarch64 cross compiler to also check the -mcpu flags.
arm_archs=( "generic" "none"
    "cortex-a34" "cortex-a35" "cortex-a53" "cortex-a57" "cortex-a72" "cortex-a73"
    "cortex-a55" "cortex-a65" "cortex-a65ae" "cortex-a75" "cortex-a76" "cortex-a76ae" "cortex-a77"
    "cortex-a78" "cortex-a78ae" "cortex-a78c" "cortex-x1" "cortex-x1c"
    "cortex-a510" "cortex-a710" "cortex-a715" "cortex-x2" "cortex-x3"
    "cortex-a320" "cortex-a520" "cortex-a520ae" "cortex-a720" "cortex-a720ae" "cortex-a725" "cortex-x4" "cortex-x925"
    "c1-nano" "c1-pro" "c1-premium" "c1-ultra" "cortex-a72+nocrypto"
    "apple-a7" "apple-a8" "apple-a9" "apple-a10" "apple-a11" "apple-a12" "apple-a13"
    "apple-a14" "apple-a15" "apple-a16" "apple-a17" "apple-a18" "apple-a19"
    "apple-m1" "apple-m2" "apple-m3" "apple-m4" "apple-m5"
    "apple-s4" "apple-s5" "apple-s6" "apple-s7" "apple-s8" "apple-s9" "apple-s10" )

arm_compiler=()
if [ -n "${ARM_CC:-}" ]; then
    arm_compiler=( -DCMAKE_C_COMPILER="${ARM_CC}" -DCMAKE_CXX_COMPILER="${ARM_CXX:-${ARM_CC}}"
                   -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY )
fi

# CUDA detection: must not break the configuration, even without GPU or nvcc
echo "cuda"
rm -rf ./build
mkdir ./build
cd ./build
cmake .. -DCUDA_DETECT=ON
cd ..

for arch in "${arm_archs[@]}"
do
    echo "${arch}"
    rm -rf ./build
    mkdir ./build
    cd ./build
    cmake .. -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64 "${arm_compiler[@]}" -DTARGET_ARCHITECTURE="${arch}"
    cd ..
done
