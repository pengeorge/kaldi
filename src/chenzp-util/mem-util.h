/*
 * =====================================================================================
 *
 *       Filename:  mem-util.h
 *
 *    Description:  
 *
 *        Version:  1.0
 *        Created:  2014年10月07日 16时03分50秒
 *       Revision:  none
 *       Compiler:  gcc
 *
 *         Author:  YOUR NAME (), 
 *   Organization:  
 *
 * =====================================================================================
 */
#include <sys/types.h>
void process_mem_usage(double& vm_usage, double& resident_set, pid_t pid = 0);
void get_raminfo(unsigned long &totalram, unsigned long &freeram, unsigned long &bufferram); // in Byte
unsigned long get_availableRam(unsigned long &total, unsigned long &free, unsigned long &buffer, unsigned long &cache); // in KB
