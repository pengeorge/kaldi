/*
 * =====================================================================================
 *
 *       Filename:  mem-util.cc
 *
 *    Description:  
 *
 *        Version:  1.0
 *        Created:  2014年10月07日 15时53分44秒
 *       Revision:  none
 *       Compiler:  gcc
 *
 *         Author:  YOUR NAME (), 
 *   Organization:  
 *
 * =====================================================================================
 */
#include <sstream>
#include <fstream>
#include <stdlib.h>
#include <sys/sysinfo.h>
#include "chenzp-util/mem-util.h"

void process_mem_usage(double& vm_usage, double& resident_set, pid_t pid)
{
  std::string file;
  if (!pid) {
    file = "/proc/self/stat";
  } else {
    std::ostringstream os;
    os << "/proc/" << pid << "/stat";
    file = os.str();
  }
  vm_usage     = 0.0;
  resident_set = 0.0;
  unsigned long vsize;
  long rss;
  {
    std::string ignore;
    std::ifstream ifs(file.c_str(), std::ios_base::in);
    ifs >> ignore >> ignore >> ignore >> ignore >> ignore >> ignore >> ignore >> ignore >> ignore >> ignore
      >> ignore >> ignore >> ignore >> ignore >> ignore >> ignore >> ignore >> ignore >> ignore >> ignore
      >> ignore >> ignore >> vsize >> rss;
  }

  long page_size_kb = sysconf(_SC_PAGE_SIZE) / 1024; // in case x86-64 is configured to use 2MB pages
  vm_usage = vsize / 1024.0;
  resident_set = rss * page_size_kb;
}

void get_raminfo(unsigned long &totalram, unsigned long &freeram, unsigned long &bufferram) { // in Byte
  struct sysinfo si;
  sysinfo(&si);
  totalram = si.totalram;
  freeram = si.freeram;
  bufferram = si.bufferram;
}

unsigned long get_availableRam(unsigned long &total, unsigned long &free, unsigned long &buffer, unsigned long &cache) { // in KB
  {
    std::string ignore;
    std::ifstream ifs("/proc/meminfo", std::ios_base::in);
    ifs >> ignore >> total >> ignore >> ignore >> free >> ignore >> ignore >> buffer >> ignore >> ignore >> cache;
  }
  return free + buffer + cache;
}

