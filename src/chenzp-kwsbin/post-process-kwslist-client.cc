/*
 * =====================================================================================
 *
 *       Filename:  client.cc
 *
 *    Description:  
 *
 *        Version:  1.0
 *        Created:  2014年12月24日 22时00分12秒
 *       Revision:  none
 *       Compiler:  gcc
 *
 *         Author:  Zhipeng Chen 
 *   Organization:  
 *
 * =====================================================================================
 */
#include<stdio.h>
#include<stdlib.h>
#include<string.h>
#include<errno.h>
#include<sys/types.h>
#include<sys/socket.h>
#include<unistd.h>
#include<sys/un.h>
#include<arpa/inet.h>
#include<netdb.h>

#define UNIX_DOMAIN "/tmp/unix_domains/kws_demo.json"
#define MAXDATASIZE 32*1024*1024  // 32MB

bool recv_all(int socket, char* buff) {
  char len[16];
  int len_of_len = recv(socket, len, 16, 0);
  if (len_of_len != 16) {
    fprintf(stderr, "error when receiving length of data: %d bytes received, expected %d\n", len_of_len, 16);
    return false;
  }
  int expLen = atoi(len);
  int bytes = 0;
  while (bytes < expLen) {
    int tmp = recv(socket, buff, MAXDATASIZE, 0);
    if (tmp < 0) {
      printf("%s(errno: %d)\n", strerror(errno), errno);
      return false;
    }
    buff += tmp;
    bytes += tmp;
  }
  buff[0] = '\0';
  return true;
}

int main(int argc, char** argv)
{
  int    sockfd;
  struct sockaddr_un    servaddr;

  if( argc != 5){
    fprintf(stderr, "usage: ./client <kw-path> <src-ip> <offset> <limit>\n");
    return 1;
  }
  char *strfsts = argv[1];
  char srcip[16];
  strcpy(srcip, argv[2]);
  int offset = atoi(argv[3]);
  int limit = atoi(argv[4]);
  fprintf(stderr, "%s %s %s %s %s\n", argv[0], argv[1], argv[2], argv[3], argv[4]);

  if( (sockfd = socket(PF_UNIX, SOCK_STREAM, 0)) < 0){
    fprintf(stderr, "create socket error: %s(errno: %d)\n", strerror(errno),errno);
    return 2;
  }
  servaddr.sun_family = AF_UNIX;
  strcpy(servaddr.sun_path, UNIX_DOMAIN);

  if( connect(sockfd, (struct sockaddr*)&servaddr, sizeof(servaddr)) < 0){
    fprintf(stderr, "connect error: %s(errno: %d)\n",strerror(errno),errno);
    return 3;
  }
  int pack_len = strlen(strfsts) + 48;
  char *pack = new char[pack_len+1];
  char strnum[16];
  sprintf(strnum, "%015d", offset);
  strcpy(pack, strnum);
  sprintf(strnum, "%015d", limit);
  strcpy(pack + 16, strnum);
  strcpy(pack + 32, srcip);
  strcpy(pack + 48, strfsts);
  if( send(sockfd, pack, pack_len, 0) < 0)
  {
    fprintf(stderr, "send msg error: %s(errno: %d)\n", strerror(errno), errno);
    return 4;
  }

  // Waiting for processing
  char *buff = new char[MAXDATASIZE];
  if(!recv_all(sockfd, buff)) {
    fprintf(stderr, "recv error: %s(errno: %d)\n", strerror(errno), errno);  
    close(sockfd);
    return 5;
  }
  /*
  if (buff[0] != 'o') { // if failed
    fprintf(stderr, "task failed\n");
  }*/
  printf("%s", buff);
  delete [] buff;
  close(sockfd);
  return 0;
}
