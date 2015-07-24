/*
 * =====================================================================================
 *
 *       Filename:  client.cc
 *
 *    Description:  
 *
 *        Version:  1.0
 *        Created:  2014年12月21日 02时28分12秒
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
#include<netinet/in.h>
#include<arpa/inet.h>
#include<netdb.h>

#define MAXDATASIZE 10*1024*1024  // 10MB

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
  struct sockaddr_in    servaddr;
  char ip[32];

  if( argc != 4){
    fprintf(stderr, "usage: ./client <host> <port> <kw-path> \n%d\n", argc);
    return 1;
  }
  char *strhost = argv[1];
  int port = atoi(argv[2]);
  char *strfsts = argv[3];
  fprintf(stderr, "%s %s %s %s\n", argv[0], argv[1], argv[2], argv[3]);

  memset(&servaddr, 0, sizeof(servaddr));
  if( inet_pton(AF_INET, strhost, &servaddr.sin_addr) <= 0){
    //printf("inet_pton error for %s\n",argv[1]);
    struct hostent *hptr;
    if ((hptr = gethostbyname(strhost)) == NULL) {
      fprintf(stderr, "gethostbyname error for host: %s\n", strhost);
      return 1;
    }
    const char *strIP = inet_ntop(hptr->h_addrtype, *(hptr->h_addr_list), ip, sizeof(ip));
    if ( inet_pton(AF_INET, strIP, &servaddr.sin_addr) <= 0) {
      fprintf(stderr, "inet_pton error for %s\n", strIP);
      return 1;
    }
    servaddr.sin_family = hptr->h_addrtype;
    fprintf(stderr, "Server: %s (%s)\n", hptr->h_name, strIP);
  } else {
    servaddr.sin_family = AF_INET;
    fprintf(stderr, "Server: %s\n", strhost);
  }

  servaddr.sin_port = htons(port);

  if( (sockfd = socket(AF_INET, SOCK_STREAM, 0)) < 0){
    fprintf(stderr, "create socket error: %s(errno: %d)\n", strerror(errno),errno);
    return 1;
  }

  if( connect(sockfd, (struct sockaddr*)&servaddr, sizeof(servaddr)) < 0){
    fprintf(stderr, "connect error: %s(errno: %d)\n",strerror(errno),errno);
    return 1;
  }

  if( send(sockfd, strfsts, strlen(strfsts), 0) < 0)
  {
    fprintf(stderr, "send msg error: %s(errno: %d)\n", strerror(errno), errno);
    return 1;
  }

  // Waiting for processing
  char *buff = new char[MAXDATASIZE];
  if(!recv_all(sockfd, buff)) {
    fprintf(stderr, "recv error: %s(errno: %d)\n", strerror(errno), errno);  
    close(sockfd);
    return 2;
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
