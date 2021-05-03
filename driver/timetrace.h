//===-- driver/timetrace.h --------------------------------------*- C++ -*-===//
//
//                         LDC – the LLVM D compiler
//
// This file is distributed under the BSD-style LDC license. See the LICENSE
// file for details.
//
//===----------------------------------------------------------------------===//
//
// Compilation time tracing, --ftime-trace.
// Main implementation is in D, this C++ source is for interfacing.
//
//===----------------------------------------------------------------------===//

#pragma once

#include <functional>

// Forward declarations to functions implemented in D
void initializeTimeTrace(unsigned timeGranularity, unsigned memoryGranularity,
                         const char *processName);
void deinitializeTimeTrace();
void writeTimeTraceProfile(const char *filename_cstr);
void timeTraceProfilerBegin(const char *name_ptr, const char *detail_ptr);
void timeTraceProfilerEnd();
bool timeTraceProfilerEnabled();


/// RAII helper class to call the begin and end functions of the time trace
/// profiler.  When the object is constructed, it begins the section; and when
/// it is destroyed, it stops it.
/// The strings pointed to are copied (pointers are not stored).
struct TimeTraceScope {
  TimeTraceScope() = delete;
  TimeTraceScope(const TimeTraceScope &) = delete;
  TimeTraceScope &operator=(const TimeTraceScope &) = delete;
  TimeTraceScope(TimeTraceScope &&) = delete;
  TimeTraceScope &operator=(TimeTraceScope &&) = delete;

  TimeTraceScope(const char *name) {
    if (timeTraceProfilerEnabled())
      timeTraceProfilerBegin(name, "");
  }
  TimeTraceScope(const char *name, const char *detail) {
    if (timeTraceProfilerEnabled())
      timeTraceProfilerBegin(name, detail);
  }
  TimeTraceScope(const char *name, std::function<std::string()> detail) {
    if (timeTraceProfilerEnabled())
      timeTraceProfilerBegin(name, detail().c_str());
  }
  TimeTraceScope(std::function<std::string()> name, std::function<std::string()> detail) {
    if (timeTraceProfilerEnabled())
      timeTraceProfilerBegin(name().c_str(), detail().c_str());
  }

  ~TimeTraceScope() {
    if (timeTraceProfilerEnabled())
      timeTraceProfilerEnd();
  }
};
