FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install all kernel build dependencies in a single layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Compilers & linker (clang-14 for better compatibility with older kernels)
    clang-14 \
    lld-14 \
    llvm-14 \
    # Host and cross-compilers (needed by some Kbuild scripts even with LLVM=1)
    gcc \
    g++ \
    gcc-aarch64-linux-gnu \
    # Core build tools
    make \
    bc \
    bison \
    flex \
    # Libraries
    libssl-dev \
    libelf-dev \
    # Kernel-specific tools
    kmod \
    dwarves \
    device-tree-compiler \
    # Utilities (openssl needed for module signing keys)
    openssl \
    python3 \
    cpio \
    lz4 \
    gzip \
    xz-utils \
    zstd \
    git \
    # Needed by some kernel scripts
    perl \
    && rm -rf /var/lib/apt/lists/*

# Create version-neutral symlinks so LLVM=1 finds unversioned tool names.
# The kernel Makefile with LLVM=1 looks for: clang, ld.lld, llvm-ar, etc.
RUN ln -sf /usr/bin/clang-14 /usr/bin/clang && \
    ln -sf /usr/bin/clang++-14 /usr/bin/clang++ && \
    ln -sf /usr/bin/clang-cpp-14 /usr/bin/clang-cpp && \
    ln -sf /usr/bin/ld.lld-14 /usr/bin/ld.lld && \
    ln -sf /usr/bin/llvm-ar-14 /usr/bin/llvm-ar && \
    ln -sf /usr/bin/llvm-nm-14 /usr/bin/llvm-nm && \
    ln -sf /usr/bin/llvm-objcopy-14 /usr/bin/llvm-objcopy && \
    ln -sf /usr/bin/llvm-objdump-14 /usr/bin/llvm-objdump && \
    ln -sf /usr/bin/llvm-readelf-14 /usr/bin/llvm-readelf && \
    ln -sf /usr/bin/llvm-strip-14 /usr/bin/llvm-strip && \
    ln -sf /usr/bin/llvm-size-14 /usr/bin/llvm-size && \
    ln -sf /usr/bin/llvm-strings-14 /usr/bin/llvm-strings && \
    ln -sf /usr/bin/llvm-readobj-14 /usr/bin/llvm-readobj && \
    ln -sf /usr/bin/llvm-config-14 /usr/bin/llvm-config

# Verify critical tools exist
RUN clang --version && ld.lld --version && aarch64-linux-gnu-gcc --version && make --version

ENV ARCH=arm64
ENV CROSS_COMPILE=aarch64-linux-gnu-
ENV CLANG_TRIPLE=aarch64-linux-gnu-
ENV LLVM=1
ENV LLVM_IAS=1

WORKDIR /src
