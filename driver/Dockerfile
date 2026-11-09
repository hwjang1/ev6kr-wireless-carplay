# Build container for the USB Wi-Fi dongle driver (driver/build.sh). The toolchain (AOSP
# arm-eabi-4.7) and the kernel source (kernel.org 3.18.24) are fetched into a cache volume on
# the first run, not baked in here.
FROM ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends build-essential bc kmod perl python3 git curl \
        ca-certificates xz-utils \
    && rm -rf /var/lib/apt/lists/*
