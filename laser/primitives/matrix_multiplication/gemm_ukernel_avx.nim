# Laser
# Copyright (c) 2018 Mamy André-Ratsimbazafy
# Distributed under the Apache v2 License (license terms are at http://www.apache.org/licenses/LICENSE-2.0).
# This file may not be copied, modified, or distributed except according to those terms.

import
  ./gemm_ukernel_generator, ./gemm_tiling,
  ../../simd

template m256_muladd_unfused(a, b, c: m256): m256 =
  mm256_add_ps(mm256_mul_ps(a, b), c)

ukernel_generator(
      x86_AVX,
      typ = float32,
      vectype = m256,
      nb_scalars = 8,
      simd_setZero = mm256_setzero_ps,
      simd_broadcast_value = mm256_set1_ps,
      simd_load_aligned = mm256_load_ps,
      simd_load_unaligned = mm256_loadu_ps,
      simd_fma = m256_muladd_unfused,
      simd_store_unaligned = mm256_storeu_ps,
      simd_mul = mm256_mul_ps,
      simd_add = mm256_add_ps
    )
