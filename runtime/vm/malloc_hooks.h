// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#ifndef RUNTIME_VM_MALLOC_HOOKS_H_
#define RUNTIME_VM_MALLOC_HOOKS_H_

#include "vm/globals.h"

namespace dart {

class MallocHooks {
 public:
  static void InitOnce();
  static void TearDown();
  static void ResetStats();

  static intptr_t allocation_count();
  static intptr_t heap_allocated_memory_in_bytes();

 private:
  DISALLOW_ALLOCATION();
  DISALLOW_IMPLICIT_CONSTRUCTORS(MallocHooks);
};

}  // namespace dart

#endif  // RUNTIME_VM_MALLOC_HOOKS_H_
