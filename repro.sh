#!/usr/bin/env bash
###############################################################################
# Copyright (C) 2026 Bull S. A. S. -  All rights reserved
# Bull, Rue Jean Jaures, B.P.68, 78340, Les Clayes-sous-Bois, France
# This is not Free or Open Source software.
# Please contact Bull S. A. S. for details about its license.
###############################################################################
# Author:      Antoine Morvan
# License:     Private
# Version:     0.0.1
# Maintainer:  Antoine Morvan
# EMail        antoine.morvan@bull.com
# Status:      beta
# Credits:     Antoine Morvan
# BugTracker:  
###############################################################################

set -e -u -o pipefail

REPRO_SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
echo "## -- [ectrans_aocc_repro] start"

COMPILER=AOCC # install 5.2.0
# COMPILER=GCC #system GCC

case "${@}" in
    "--clean")
        while IFS= read -r -d '' folder_to_clean ; do
            echo "rm folder ${folder_to_clean}"
            rm -rf "${folder_to_clean}"
        done <  <(find "${REPRO_SCRIPT_DIR}" -mindepth 1 -maxdepth 1 -type d -print0)
        rm -v "${REPRO_SCRIPT_DIR}"/setenv_*.sh
        exit 0
        ;;
esac

echo "## -- [ectrans_aocc_repro] >>> testing $COMPILER"

###############################################################################
## AOCC
###############################################################################

case $COMPILER in
    AOCC)
        AOCC_VERSION=5.2.0

        echo "## -- [ectrans_aocc_repro] AOCC"
        AOCC_DIR=aocc-compiler-${AOCC_VERSION}
        AOCC_ARCHIVE=${AOCC_DIR}.tar
        AOCC_URL_VERSION=$(echo "${AOCC_VERSION}" | rev | cut -d'.' -f2- | rev | sed 's/\./-/')
        AOCC_URL=https://download.amd.com/developer/eula/aocc/aocc-${AOCC_URL_VERSION}/${AOCC_ARCHIVE}

        [ ! -f "${REPRO_SCRIPT_DIR}/${AOCC_ARCHIVE}" ] && curl -L -o "${REPRO_SCRIPT_DIR}/${AOCC_ARCHIVE}" "${AOCC_URL}"
        [ ! -d "${REPRO_SCRIPT_DIR}/${AOCC_DIR}" ] && tar xf "${REPRO_SCRIPT_DIR}/${AOCC_ARCHIVE}" -C "${REPRO_SCRIPT_DIR}/"
        [ ! -f "${REPRO_SCRIPT_DIR}/setenv_AOCC.sh" ] && (
            cd "${REPRO_SCRIPT_DIR}/${AOCC_DIR}"
            ./install.sh
            cat >> "${REPRO_SCRIPT_DIR}/setenv_AOCC.sh" << "EOF"
export CC=clang
export CXX=clang++
export FC=flang
export FF=$FC
EOF
            rm "${REPRO_SCRIPT_DIR}"/aocc-compiler*_module
        )
        ;;
    GCC)
        # use system GCC ; tested with RHEL9 GCC 11.5
        cat > "${REPRO_SCRIPT_DIR}/setenv_GCC.sh" << "EOF"
export CC=gcc
export CXX=g++
export FC=gfortran
export FF=$FC
EOF
        ;;
    *) echo "Error: unsupported compiler $COMPILER"; exit 1 ;;
esac


###############################################################################
## MPI
###############################################################################

echo "## -- [ectrans_aocc_repro] Open MPI"
OPENMPI_VERSION="5.0.10"
OPENMPI_DIR=openmpi-${OPENMPI_VERSION}
OPENMPI_ARCHIVE=${OPENMPI_DIR}.tar.bz2
OPENMPI_URL=https://download.open-mpi.org/release/open-mpi/v${OPENMPI_VERSION%.*}/${OPENMPI_ARCHIVE}

[ ! -f "${REPRO_SCRIPT_DIR}/${OPENMPI_ARCHIVE}" ] && curl -L -o "${REPRO_SCRIPT_DIR}/${OPENMPI_ARCHIVE}" "${OPENMPI_URL}"
[ ! -d "${REPRO_SCRIPT_DIR}/${OPENMPI_DIR}" ] && tar xf "${REPRO_SCRIPT_DIR}/${OPENMPI_ARCHIVE}" -C "${REPRO_SCRIPT_DIR}/"

[ ! -f "${REPRO_SCRIPT_DIR}/openmpi_prefix_${COMPILER}/lib/libmpi.so" ] && (
    cd "${REPRO_SCRIPT_DIR}/${OPENMPI_DIR}"

    # AOCC setenv still not supporting set -u
    set +u
    source "${REPRO_SCRIPT_DIR}/setenv_${COMPILER}.sh"
    set -u
    echo ${CC}-${FC}

    case $COMPILER in
        AOCC) export LDFLAGS="${LDFLAGS:-} -Wl,--allow-shlib-undefined" ;;
    esac

    ROCM_CONF_ARG=("--without-rocm")
    NVHPC_CUDA_CONF_ARG=("--without-cuda")
    LIBEVENT_CONF_ARG=("--with-libevent=internal")
    HWLOC_CONF_ARG=("--with-hwloc=internal")
    HCOLL_CONF_ARG=("--without-hcoll")
    LUSTRE_CONF_ARG=("--without-lustre")
    PMIX_CONF_ARG=("--with-pmix=internal")
    KNEM_CONF_ARG=("--without-knem")
    XPMEM_CONF_ARG=("--without-xpmem")
    GPFS_CONF_ARG=("--without-gpfs")
    UCX_UCC_FLAGS=()
    FORTRAN_MODIFIER=("--enable-mpi-fortran")
    OPENMPI_EXTRA_CONFIGURE_FLAGS=()

    mkdir -p "${REPRO_SCRIPT_DIR}/${OPENMPI_DIR}/build_${COMPILER}"
    cd "${REPRO_SCRIPT_DIR}/${OPENMPI_DIR}/build_${COMPILER}"

    "${REPRO_SCRIPT_DIR}/${OPENMPI_DIR}/configure" \
        --prefix="${REPRO_SCRIPT_DIR}/openmpi_prefix_${COMPILER}" \
        --libdir="${REPRO_SCRIPT_DIR}/openmpi_prefix_${COMPILER}/lib" \
        --enable-shared \
        "${FORTRAN_MODIFIER[@]}" \
        --enable-wrapper-rpath=no \
        --enable-wrapper-runpath=no \
        --disable-mpi1-compatibility \
        --enable-prte-prefix-by-default \
        --with-libnl=no \
        --with-portals4=no \
        "${UCX_UCC_FLAGS[@]}" \
        "${HCOLL_CONF_ARG[@]}" \
        "${HWLOC_CONF_ARG[@]}" \
        "${XPMEM_CONF_ARG[@]}" \
        "${KNEM_CONF_ARG[@]}" \
        "${PMIX_CONF_ARG[@]}" \
        "${LIBEVENT_CONF_ARG[@]}" \
        "${NVHPC_CUDA_CONF_ARG[@]}" \
        "${ROCM_CONF_ARG[@]}" \
        "${LUSTRE_CONF_ARG[@]}" \
        "${GPFS_CONF_ARG[@]}" \
        --with-cma \
        "${OPENMPI_EXTRA_CONFIGURE_FLAGS[@]}"

    make -j 32
    mkdir -p "${REPRO_SCRIPT_DIR}/openmpi_prefix_${COMPILER}"
    make install
)
cat > "${REPRO_SCRIPT_DIR}/setenv_openmpi_${COMPILER}.sh" << EOF
export OPAL_PREFIX="${REPRO_SCRIPT_DIR}/openmpi_prefix_${COMPILER}"

export MPI_ROOT="${REPRO_SCRIPT_DIR}/openmpi_prefix_${COMPILER}"
export MPI_HOME="${REPRO_SCRIPT_DIR}/openmpi_prefix_${COMPILER}"
export MPI_DIR="${REPRO_SCRIPT_DIR}/openmpi_prefix_${COMPILER}"

export MPI_HOME="${REPRO_SCRIPT_DIR}/openmpi_prefix_${COMPILER}"
export MPI_ROOT="${REPRO_SCRIPT_DIR}/openmpi_prefix_${COMPILER}"
export MPI_BIN="${REPRO_SCRIPT_DIR}/openmpi_prefix_${COMPILER}/bin"
export MPI_LIB="${REPRO_SCRIPT_DIR}/openmpi_prefix_${COMPILER}/lib"
export MPI_INC="${REPRO_SCRIPT_DIR}/openmpi_prefix_${COMPILER}/include"

export PATH="${REPRO_SCRIPT_DIR}/openmpi_prefix_${COMPILER}/bin\${PATH:+:\${PATH}}"
export LD_LIBRARY_PATH="${REPRO_SCRIPT_DIR}/openmpi_prefix_${COMPILER}/lib\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
export LIBRARY_PATH="${REPRO_SCRIPT_DIR}/openmpi_prefix_${COMPILER}/lib\${LIBRARY_PATH:+:\${LIBRARY_PATH}}"
export CPATH="${REPRO_SCRIPT_DIR}/openmpi_prefix_${COMPILER}/include\${CPATH:+:\${CPATH}}"

export PKG_CONFIG_PATH="${REPRO_SCRIPT_DIR}/openmpi_prefix_${COMPILER}/lib/pkgconfig\${PKG_CONFIG_PATH:+:\${PKG_CONFIG_PATH}}"
export CMAKE_PREFIX_PATH="${REPRO_SCRIPT_DIR}/openmpi_prefix_${COMPILER}\${CMAKE_PREFIX_PATH:+:\${CMAKE_PREFIX_PATH}}"

export MPICC=mpicc
export MPICXX=mpicxx
export MPIFC=mpifort
export MPI_C_COMPILER=mpicc
export MPI_CXX_COMPILER=mpicxx
export MPI_Fortran_COMPILER=mpifort

export OMPI_CC="\${CC}"
export OMPI_CXX="\${CXX}"
export OMPI_FC="\${FC}"
export OMPI_F90="\${FC}"
export OMPI_F77="\${FC}"
EOF

###############################################################################
## OpenBLAS
###############################################################################

echo "## -- [ectrans_aocc_repro] OpenBLAS"
OPENBLAS_VERSION="0.3.33"
OPENBLAS_DIR=OpenBLAS-${OPENBLAS_VERSION}
OPENBLAS_ARCHIVE=${OPENBLAS_DIR}.tar.gz
OPENBLAS_URL=https://github.com/OpenMathLib/OpenBLAS/releases/download/v${OPENBLAS_VERSION}/${OPENBLAS_ARCHIVE}

[ ! -f "${REPRO_SCRIPT_DIR}/${OPENBLAS_ARCHIVE}" ] && curl -L -o "${REPRO_SCRIPT_DIR}/${OPENBLAS_ARCHIVE}" "${OPENBLAS_URL}"
[ ! -d "${REPRO_SCRIPT_DIR}/${OPENBLAS_DIR}" ] && tar xf "${REPRO_SCRIPT_DIR}/${OPENBLAS_ARCHIVE}" -C "${REPRO_SCRIPT_DIR}/"

[ ! -f "${REPRO_SCRIPT_DIR}/openblas_prefix_${COMPILER}/lib/libopenblas.so" ] && (
    # AOCC setenv still not supporting set -u
    set +u
    source "${REPRO_SCRIPT_DIR}/setenv_${COMPILER}.sh"
    set -u
    echo ${CC}-${FC}

    OPENBLAS_ARCH_SPEC=("-DTARGET_CORE=ZEN")
    OPENBLAS_THREADING_SPEC=("-DUSE_THREAD=ON" "-DUSE_OPENMP=ON")

    mkdir "${REPRO_SCRIPT_DIR}/${OPENBLAS_DIR}/build_${COMPILER}"
    cd "${REPRO_SCRIPT_DIR}/${OPENBLAS_DIR}/build_${COMPILER}"
    cmake \
        -Wno-dev \
        -G 'Unix Makefiles' \
        -DCMAKE_INSTALL_LIBDIR="lib" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${REPRO_SCRIPT_DIR}/openblas_prefix_${COMPILER}" \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_STATIC_LIBS=ON \
        -DBUILD_BENCHMARKS=ON \
        -DBUILD_TESTING=OFF \
        -DNUM_THREADS="512" \
        -DDYNAMIC_ARCH=OFF \
        "${OPENBLAS_ARCH_SPEC[@]}" \
        "${OPENBLAS_THREADING_SPEC[@]}" \
        "${REPRO_SCRIPT_DIR}/${OPENBLAS_DIR}"
    
    make -j 32
    make install
)
cat > "${REPRO_SCRIPT_DIR}/setenv_openblas_${COMPILER}.sh" << EOF
export LD_LIBRARY_PATH="${REPRO_SCRIPT_DIR}/openblas_prefix_${COMPILER}/lib\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
export LIBRARY_PATH="${REPRO_SCRIPT_DIR}/openblas_prefix_${COMPILER}/lib\${LIBRARY_PATH:+:\${LIBRARY_PATH}}"
export CPATH="${REPRO_SCRIPT_DIR}/openblas_prefix_${COMPILER}/include\${CPATH:+:\${CPATH}}"

export PKG_CONFIG_PATH="${REPRO_SCRIPT_DIR}/openblas_prefix_${COMPILER}/lib/pkgconfig\${PKG_CONFIG_PATH:+:\${PKG_CONFIG_PATH}}"
export CMAKE_PREFIX_PATH="${REPRO_SCRIPT_DIR}/openblas_prefix_${COMPILER}\${CMAKE_PREFIX_PATH:+:\${CMAKE_PREFIX_PATH}}"
EOF

###############################################################################
## FFTW
###############################################################################

echo "## -- [ectrans_aocc_repro] FFTW"
FFTW_VERSION=3.3.10
FFTW_DIR=fftw-${FFTW_VERSION}
FFTW_ARCHIVE=${FFTW_DIR}.tar.gz
FFTW_URL=https://www.fftw.org/${FFTW_ARCHIVE}

[ ! -f "${REPRO_SCRIPT_DIR}/${FFTW_ARCHIVE}" ] && curl -L -o "${REPRO_SCRIPT_DIR}/${FFTW_ARCHIVE}" "${FFTW_URL}"
[ ! -d "${REPRO_SCRIPT_DIR}/${FFTW_DIR}" ] && tar xf "${REPRO_SCRIPT_DIR}/${FFTW_ARCHIVE}" -C "${REPRO_SCRIPT_DIR}/"

[ ! -f "${REPRO_SCRIPT_DIR}/fftw_prefix_${COMPILER}/lib/libfftw3.so" ] && (
    # AOCC setenv still not supporting set -u
    set +u
    source "${REPRO_SCRIPT_DIR}/setenv_${COMPILER}.sh"
    set -u
    echo ${CC}-${FC}

    FFTW_ARCH_FLAGS=()
    FFTW_ARCH_FLAGS+=("--enable-sse2")
    FFTW_ARCH_FLAGS+=("--enable-avx")
    FFTW_ARCH_FLAGS+=("--enable-avx2")
    FFTW_ARCH_FLAGS+=("--enable-avx512")
    FFTW_ARCH_FLAGS+=("--enable-fma")
    FFTW_ARCH_FLAGS+=("--enable-avx-128-fma")

    FFTW_DEFAULT_FLAGS=(
        --prefix="${REPRO_SCRIPT_DIR}/fftw_prefix_${COMPILER}" \
        --libdir="${REPRO_SCRIPT_DIR}/fftw_prefix_${COMPILER}/lib" \
        --disable-doc \
        --enable-shared \
        --enable-threads \
        --disable-static \
        --enable-openmp \
    )

    mkdir -p "${REPRO_SCRIPT_DIR}/${FFTW_DIR}/build_single_${COMPILER}"
    cd "${REPRO_SCRIPT_DIR}/${FFTW_DIR}/build_single_${COMPILER}"
    "${REPRO_SCRIPT_DIR}/${FFTW_DIR}/configure" \
        "${FFTW_DEFAULT_FLAGS[@]}" \
        "${FFTW_ARCH_FLAGS[@]}" \
        --enable-single
    make -j 32
    make install

    mkdir -p "${REPRO_SCRIPT_DIR}/${FFTW_DIR}/build_double_${COMPILER}"
    cd "${REPRO_SCRIPT_DIR}/${FFTW_DIR}/build_double_${COMPILER}"
    "${REPRO_SCRIPT_DIR}/${FFTW_DIR}/configure" \
        "${FFTW_DEFAULT_FLAGS[@]}" \
        "${FFTW_ARCH_FLAGS[@]}"
    make -j 32
    make install
)
cat > "${REPRO_SCRIPT_DIR}/setenv_fftw_${COMPILER}.sh" << EOF
export LD_LIBRARY_PATH="${REPRO_SCRIPT_DIR}/fftw_prefix_${COMPILER}/lib\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
export LIBRARY_PATH="${REPRO_SCRIPT_DIR}/fftw_prefix_${COMPILER}/lib\${LIBRARY_PATH:+:\${LIBRARY_PATH}}"
export CPATH="${REPRO_SCRIPT_DIR}/fftw_prefix_${COMPILER}/include\${CPATH:+:\${CPATH}}"

export PKG_CONFIG_PATH="${REPRO_SCRIPT_DIR}/fftw_prefix_${COMPILER}/lib/pkgconfig\${PKG_CONFIG_PATH:+:\${PKG_CONFIG_PATH}}"
export CMAKE_PREFIX_PATH="${REPRO_SCRIPT_DIR}/fftw_prefix_${COMPILER}\${CMAKE_PREFIX_PATH:+:\${CMAKE_PREFIX_PATH}}"
EOF

###############################################################################
## ecbuild
###############################################################################

echo "## -- [ectrans_aocc_repro] ecBuild"
ECBUILD_VERSION=3.14.2
ECBUILD_DIR=ecbuild-${ECBUILD_VERSION}
ECBUILD_ARCHIVE=${ECBUILD_DIR}.tar.gz
ECBUILD_URL=https://github.com/ecmwf/ecbuild/archive/refs/tags/3.14.2.tar.gz

[ ! -f "${REPRO_SCRIPT_DIR}/${ECBUILD_ARCHIVE}" ] && curl -L -o "${REPRO_SCRIPT_DIR}/${ECBUILD_ARCHIVE}" "${ECBUILD_URL}"
[ ! -d "${REPRO_SCRIPT_DIR}/${ECBUILD_DIR}" ] && tar xf "${REPRO_SCRIPT_DIR}/${ECBUILD_ARCHIVE}" -C "${REPRO_SCRIPT_DIR}/"
cat > "${REPRO_SCRIPT_DIR}/setenv_ecbuild.sh" << EOF
export ecbuild_ROOT="${REPRO_SCRIPT_DIR}/${ECBUILD_DIR}"
export PATH="\${ecbuild_ROOT}/bin\${PATH:+:\${PATH}}"
EOF


###############################################################################
## FIAT
###############################################################################

echo "## -- [ectrans_aocc_repro] FIAT"
FIAT_VERSION=2.0.0
FIAT_DIR=fiat-${FIAT_VERSION}
FIAT_ARCHIVE=${FIAT_DIR}.tar.gz
FIAT_URL=https://github.com/ecmwf-ifs/fiat/archive/refs/tags/2.0.0.tar.gz

[ ! -f "${REPRO_SCRIPT_DIR}/${FIAT_ARCHIVE}" ] && curl -L -o "${REPRO_SCRIPT_DIR}/${FIAT_ARCHIVE}" "${FIAT_URL}"
[ ! -d "${REPRO_SCRIPT_DIR}/${FIAT_DIR}" ] && tar xf "${REPRO_SCRIPT_DIR}/${FIAT_ARCHIVE}" -C "${REPRO_SCRIPT_DIR}/"
[ ! -f "${REPRO_SCRIPT_DIR}/fiat_prefix_${COMPILER}/bin/fiat" ] && (
    # AOCC setenv still not supporting set -u
    set +u
    source "${REPRO_SCRIPT_DIR}/setenv_${COMPILER}.sh"
    set -u
    echo ${CC}-${FC}
    source "${REPRO_SCRIPT_DIR}/setenv_openmpi_${COMPILER}.sh"
    source "${REPRO_SCRIPT_DIR}/setenv_ecbuild.sh"

    mkdir -p "${REPRO_SCRIPT_DIR}/${FIAT_DIR}/build_${COMPILER}"
    cd "${REPRO_SCRIPT_DIR}/${FIAT_DIR}/build_${COMPILER}"

    ecbuild \
        -Wno-dev \
        -G 'Unix Makefiles' \
        -DCMAKE_INSTALL_LIBDIR="lib" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${REPRO_SCRIPT_DIR}/fiat_prefix_${COMPILER}" \
        "${REPRO_SCRIPT_DIR}/${FIAT_DIR}"
    make -j 32
    make install
)
cat > "${REPRO_SCRIPT_DIR}/setenv_fiat_${COMPILER}.sh" << EOF
export fiat_ROOT="${REPRO_SCRIPT_DIR}/fiat_prefix_${COMPILER}"
# export fiat_DIR="${REPRO_SCRIPT_DIR}/fiat_prefix_${COMPILER}"
export CMAKE_PREFIX_PATH="${REPRO_SCRIPT_DIR}/fiat_prefix_${COMPILER}\${CMAKE_PREFIX_PATH:+:\${CMAKE_PREFIX_PATH}}"
export PATH="\${fiat_ROOT}/bin\${PATH:+:\${PATH}}"
EOF

###############################################################################
## ecTrans
###############################################################################

echo "## -- [ectrans_aocc_repro] ecTrans"
ECTRANS_VERSION=1.8.0
ECTRANS_DIR=ectrans-${ECTRANS_VERSION}
ECTRANS_ARCHIVE=${ECTRANS_DIR}.tar.gz
ECTRANS_URL=https://github.com/ecmwf-ifs/ectrans/archive/refs/tags/1.8.0.tar.gz

[ ! -f "${REPRO_SCRIPT_DIR}/${ECTRANS_ARCHIVE}" ] && curl -L -o "${REPRO_SCRIPT_DIR}/${ECTRANS_ARCHIVE}" "${ECTRANS_URL}"
[ ! -d "${REPRO_SCRIPT_DIR}/${ECTRANS_DIR}" ] && tar xf "${REPRO_SCRIPT_DIR}/${ECTRANS_ARCHIVE}" -C "${REPRO_SCRIPT_DIR}/"

[ ! -x "${REPRO_SCRIPT_DIR}/${ECTRANS_DIR}/build_${COMPILER}/bin/ectrans-benchmark-cpu-sp" ] && (
    # AOCC setenv still not supporting set -u
    set +u
    source "${REPRO_SCRIPT_DIR}/setenv_${COMPILER}.sh"
    set -u
    echo ${CC}-${FC}
    source "${REPRO_SCRIPT_DIR}/setenv_openmpi_${COMPILER}.sh"
    source "${REPRO_SCRIPT_DIR}/setenv_openblas_${COMPILER}.sh"
    source "${REPRO_SCRIPT_DIR}/setenv_fftw_${COMPILER}.sh"
    source "${REPRO_SCRIPT_DIR}/setenv_ecbuild.sh"
    source "${REPRO_SCRIPT_DIR}/setenv_fiat_${COMPILER}.sh"

    mkdir -p "${REPRO_SCRIPT_DIR}/${ECTRANS_DIR}/build_${COMPILER}"
    cd "${REPRO_SCRIPT_DIR}/${ECTRANS_DIR}/build_${COMPILER}"
    ecbuild \
        -Wno-dev \
        -G 'Unix Makefiles' \
        -DCMAKE_INSTALL_LIBDIR="lib" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${REPRO_SCRIPT_DIR}/ectrans_prefix_${COMPILER}" \
        \
        -DENABLE_MPI=ON \
        -DENABLE_OMP=ON \
        -DENABLE_DOUBLE_PRECISION=OFF \
        -DENABLE_SINGLE_PRECISION=ON \
        \
        -DENABLE_CPU=ON \
        -DENABLE_TESTS=OFF \
        -DENABLE_TRANSI=OFF \
        -DENABLE_GPU=OFF \
        -DENABLE_ACC=OFF \
        -DENABLE_GPU_GRAPHS_GEMM=OFF \
        -DENABLE_GPU_GRAPHS_FFT=OFF \
        \
        --fresh \
        "${REPRO_SCRIPT_DIR}/${ECTRANS_DIR}"
    make -j 32
)

###############################################################################
## Failing test
###############################################################################

echo "## -- [ectrans_aocc_repro] Failing test"
(
    # AOCC setenv still not supporting set -u
    set +u
    source "${REPRO_SCRIPT_DIR}/setenv_${COMPILER}.sh"
    set -u
    echo $CC
    source "${REPRO_SCRIPT_DIR}/setenv_openmpi_${COMPILER}.sh"
    source "${REPRO_SCRIPT_DIR}/setenv_openblas_${COMPILER}.sh"
    source "${REPRO_SCRIPT_DIR}/setenv_fftw_${COMPILER}.sh"

    export OMP_NUM_THREADS=4
    mpiexec -n 4 -- "${REPRO_SCRIPT_DIR}/${ECTRANS_DIR}/build_${COMPILER}/bin/ectrans-benchmark-cpu-sp" --norms -n 2 -l 137 -t 319 --vordiv --uvders --scders --check 1000
)

echo "## -- [ectrans_aocc_repro] end"
exit 0
