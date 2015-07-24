/*
 * =====================================================================================
 *
 *       Filename:  post-process-kwslist.cc
 *
 *    Description:  
 *
 *        Version:  1.0
 *        Created:  2014年12月23日 17时06分51秒
 *       Revision:  none
 *       Compiler:  gcc
 *
 *         Author:  Zhipeng Chen 
 *   Organization:  
 *
 * =====================================================================================
 */
//#define _DEBUG

#include <stdlib.h>
#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include <errno.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <sys/time.h>
#include <ctime>
#include <unistd.h>
//#include<netinet/in.h>
#include <sys/un.h>
#define UNIX_DOMAIN "/tmp/unix_domains/kws_demo.json"
#define MAXLINE 1024
#define MAXDATASIZE 32*1024*1024
using namespace std;

class ScopeLogger {
public:
  ScopeLogger(const string & id)
#ifdef _DEBUG
    : _id(id)
#endif
  {
#ifdef _DEBUG
    cerr << "### Enter scope " << _id << " ###" << endl;
    gettimeofday(&tpstart, NULL);
#endif
  }
  ~ScopeLogger()
  {
#ifdef _DEBUG
    gettimeofday(&tpend, NULL);
    cerr << "### Leave scope " << _id << " (" << (tpend.tv_sec - tpstart.tv_sec + (double)(tpend.tv_usec - tpstart.tv_usec) / 1000000) << ") ###" << endl;
#endif
  }
  void checkPoint(const string & name)
  {
#ifdef _DEBUG
    struct timeval tmp;
    gettimeofday(&tmp, NULL);
    cerr << "### In scope " << _id << ": checkpoint " << name << " (" << (tmp.tv_sec - tpstart.tv_sec + (double)(tmp.tv_usec - tpstart.tv_usec) / 1000000) << ") ###" << endl;
#endif
  }
private:
#ifdef _DEBUG
  string _id;
  struct timeval tpstart;
  struct timeval tpend;
#endif
};

bool send_all(int socket, const char *buffer, size_t length)
{
  cerr << "Sending data: " << length << " Bytes\n";
  // send length first
  char len[16];
  sprintf(len, "%016ld", (long)length);
  if (send(socket, len, 16, 0) != 16) {
    printf("error when sending the length of data: %s %s(errno: %d)\n", len, strerror(errno), errno);
    return false;
  }
  const char *ptr = buffer;
  while (length > 0)
  {
    int i = send(socket, ptr, length, 0);
    if (i < 1) {
      printf("%s(errno: %d)\n", strerror(errno), errno);
      return false;
    }
    ptr += i;
    length -= i;
  }
  return true;
}

struct Hit {
  unsigned int kwid; //0
  unsigned int utt_id;
  string utter; //1
  string file;
  //string url;
  //unsigned short chnl; //2
  double start; //3
  double utt_start;
  double dur; //4
  double score; // 5
  bool decision; // 6
  double score_raw; //7
};

struct Info {
  string kwlist_filename;
  string language;
  string system_id;
};

vector<string> id2url;
vector<int> id2date;
vector<string> id2program;
vector<string> id2subtitle;
vector<string> id2hyp;

// Function for sorting
bool KwslistOutputSort(const Hit & a, const Hit & b) {
  /* 
  if (a.kwid != b.kwid) {
    return (a.kwid < b.kwid); // for number
    //return (strcmp(a.kwid.c_str(), b.kwid.c_str()) < 0); // for string
  } else */
  if (a.score != b.score) {
    return (a.score > b.score);
  } else {
    return (a.utt_id < b.utt_id);
  }
}

bool KwslistTreeOutputSort(const Hit & a, const Hit & b) {
  if (id2date[a.utt_id] != id2date[b.utt_id]) {
    return (id2date[a.utt_id] > id2date[b.utt_id]);
  } else if (id2program[a.utt_id] != id2program[b.utt_id]) {
    return (strcmp(id2program[a.utt_id].c_str(), id2program[b.utt_id].c_str()) < 0); // for string
  } else if (id2subtitle[a.utt_id] != id2subtitle[b.utt_id]) {
    return (strcmp(id2subtitle[a.utt_id].c_str(), id2subtitle[b.utt_id].c_str()) < 0); // for string
  } else if (a.start != b.start) {
    return (a.start < b.start);
  } else if (a.score != b.score) {
    return (a.score > b.score);
  } else {
    return (a.utt_id < b.utt_id);
  }
}

double duptime;
string format_string;
bool KwslistDupSort(const Hit & a, const Hit & b) {
  if (a.utt_id != b.utt_id) {
    return (a.utt_id < b.utt_id);
  } else if (abs(a.start - b.start) >= duptime) {
    return (a.start < b.start);
  } else if (a.score != b.score) {
    return (a.score > b.score);
  } else {
    return (a.dur > b.dur);
  }
}

// Function for printing Kwslist.xml (fprintf version)
void PrintKwslist(const Info &info, const vector<Hit> &KWS, FILE *fout) {
  // Starting printing
  fprintf(fout, "<kwslist kwlist_filename=\"%s\" language=\"%s\" system_id=\"%s\">\n",
     info.kwlist_filename.c_str(), info.language.c_str(), info.system_id.c_str());
  unsigned int prev_kw = -1;
  for (vector<Hit>::const_iterator iter = KWS.begin(); iter != KWS.end(); ++iter) {
    if (prev_kw != iter->kwid) {
      if (prev_kw != -1) {
        fprintf(fout, "  </detected_kwlist>\n");
      }
      fprintf(fout, "  <detected_kwlist search_time=\"1\" kwid=\"%d\" oov_count=\"0\">\n", iter->kwid);
      prev_kw = iter->kwid;
    }
    fprintf(fout, "    <kw file=\"%s\" tbeg=\"%.2f\" dur=\"%.2f\" score=\"",
       iter->file.c_str(), iter->start, iter->dur);
    fprintf(fout, format_string.c_str(), iter->score);
    fprintf(fout, "\" decision=\"%s\"/>\n", (iter->decision?"YES":"NO"));
  }
  if (prev_kw != -1) {
    fprintf(fout, "  </detected_kwlist>\n");
  }
  fprintf(fout, "</kwslist>\n");
}

// Function for printing Kwslist.xml (sprintf version)
void PrintKwslist(const Info &info, const vector<Hit> &KWS, char *buff) {
  // Starting printing
  buff += sprintf(buff, "<kwslist kwlist_filename=\"%s\" language=\"%s\" system_id=\"%s\">\n",
     info.kwlist_filename.c_str(), info.language.c_str(), info.system_id.c_str());
  unsigned int prev_kw = -1;
  for (vector<Hit>::const_iterator iter = KWS.begin(); iter != KWS.end(); ++iter) {
    if (prev_kw != iter->kwid) {
      if (prev_kw != -1) {
        buff += sprintf(buff, "  </detected_kwlist>\n");
      }
      buff += sprintf(buff, "  <detected_kwlist search_time=\"1\" kwid=\"%d\" oov_count=\"0\">\n", iter->kwid);
      prev_kw = iter->kwid;
    }
    buff += sprintf(buff, "    <kw file=\"%s\" tbeg=\"%.2f\" dur=\"%.2f\" score=\"",
       iter->file.c_str(), iter->start, iter->dur);
    buff += sprintf(buff, format_string.c_str(), iter->score);
    buff += sprintf(buff, "\" decision=\"%s\"/>\n", (iter->decision?"YES":"NO"));
  }
  if (prev_kw != -1) {
    buff += sprintf(buff, "  </detected_kwlist>\n");
  }
  buff += sprintf(buff, "</kwslist>\n");
}

void extractInfoFromFile(const string &file, string &url, int &date, string &program, string &subtitle) {
  istringstream is(file);
  string t, str;
  getline(is, t, '_');
  getline(is, t, '_');
  getline(is, t, '_');
  getline(is, str, '_');
  istringstream is2(str);
  getline(is2, t, '-');
  date = atoi(t.c_str());
  getline(is2, program, '-');
  getline(is2, subtitle, '-');
  ostringstream os;
  os << "http:\\/\\/msiipl.no-ip.org:8878/video/" << program << "\\/" << (date/100) << "\\/" << date << "_" << subtitle << ".mp4";
  url = os.str();
  if (program == "XINWEN30FEN") {
    program = "新闻30分";
  } else if (program == "XINWENLIANBO") {
    program = "新闻联播";
  } else if (program == "GUOJISHIXUN") {
    program = "国际时讯";
  }
}

// Function for printing kwslist.json (sprintf version)
void PrintKwslistJson(const vector<Hit> &KWS, char *buff, int offset = 0, int limit = -1) {
  // Starting printing
  buff += sprintf(buff, "\"kwslist\":[");
  int curr = -1;
  int count = 0;
  for (vector<Hit>::const_iterator iter = KWS.begin(); iter != KWS.end(); ++iter) {
    curr++;
    if (curr < offset) {
      continue;
    }
    if (limit >= 0 && count >= limit) {
      break;
    }
    buff += sprintf(buff, "{\"url\":\"%s\",\"tbeg\":%.2f,\"sbeg\":%.2f,\"dur\":%.2f,\"score\":",
       id2url[iter->utt_id].c_str(), iter->start, iter->utt_start, iter->dur);
    buff += sprintf(buff, format_string.c_str(), iter->score);
    buff += sprintf(buff, ",\"hyp\":\"%s\"},", id2hyp[iter->utt_id].c_str());
    count++;
  }
  if (count > 0) buff--; // remove last ","
  buff += sprintf(buff, "],\"total\":%ld", KWS.size());
}

void PrintKwslistJsonTree(const vector<Hit> &KWS, char *buff, int offset = 0, int limit = -1) {
  // Starting printing
  buff += sprintf(buff, "\"kwslist\":[");
  bool first_video = true;
  bool first_item = true;
  int curr = -1;
  int count = 0;
  vector<Hit>::const_iterator piter = KWS.end();
  for (vector<Hit>::const_iterator iter = KWS.begin(); iter != KWS.end(); ++iter) {
    curr++;
    if (curr < offset) {
      piter = iter;
      continue;
    }
    if (limit >= 0 && count >= limit) {
      break;
    }
    if (piter == KWS.end() || id2url[piter->utt_id] != id2url[iter->utt_id] || first_video) { // new video
      int _continue = 0;
      if (!first_video) {
        buff += sprintf(buff, "]},");
      } else {
        if (piter !=  KWS.end() && id2url[piter->utt_id] == id2url[iter->utt_id]) {
          _continue = 1;
        }
        first_video = false;
      }
      int y,m,d;
      y = id2date[iter->utt_id]/10000;
      m = (id2date[iter->utt_id] % 10000) / 100;
      d = id2date[iter->utt_id] % 100;
      buff += sprintf(buff, "{\"video_name\":\"《%s》%04d年%02d月%02d日-%s\",\"url\":\"%s\",\"continue\":%d,\"hits\":["
         , id2program[iter->utt_id].c_str(), y, m, d, id2subtitle[iter->utt_id].c_str()
         , id2url[iter->utt_id].c_str(), _continue);
      first_item = true;
    }
    if (!first_item) {
      buff += sprintf(buff, ",");
    } else {
      first_item = false;
    }
    buff += sprintf(buff, "{\"tbeg\":%.2f,\"sbeg\":%.2f,\"dur\":%.2f,\"score\":", iter->start, iter->utt_start, iter->dur);
    buff += sprintf(buff, format_string.c_str(), iter->score);
    buff += sprintf(buff, ",\"hyp\":\"%s\"}", id2hyp[iter->utt_id].c_str());
    count++;
    piter = iter;
  }
  if (!first_video) {
    buff += sprintf(buff, "]}");
  }
  //if (count > 0) buff--; // remove last ","
  buff += sprintf(buff, "],\"total\":%ld", KWS.size());
}
/*
// Function for printing Kwslist.xml (stream version)
string PrintKwslist(const Info &info, const vector<Hit> &KWS) {
  ostringstream kwslist;
  // Starting printing
  kwslist << "<kwslist kwlist_filename=\"" << info.kwlist_filename << "\" language=\""
    << info.language << "\" system_id=\"" << info.system_id << "\">\n";
  string prev_kw = "";
  for (vector<Hit>::iterator iter = KWS.begin(); iter != KWS.end(); ++iter) {
    if (prev_kw != iter->kwid) {
      if (!prev_kw.empty()) {
        kwslist << "  </detected_kwlist>\n";
      }
      kwslist << "  <detected_kwlist search_time=\"1\" kwid=\"" << iter->kwid << "\" oov_count=\"0\">\n";
      prev_kw = iter->kwid;
    }
    kwslist << "    <kw file=\"" << iter->utter << "\" channel=\"" << iter->chnl
      << "\" tbeg=\"" << iter->start << "\" dur=\"" << iter->dur << "\" score=\""
      << iter->score << "\" decision=\"" << (iter->decision?"YES":"NO") << "\"/>\n";
  }
  if (!prev_kw.empty()) {
    kwslist << "  </detected_kwlist>\n";
  }
  kwslist << "</kwslist>\n";
  return kwslist.str();
}
*/

int main(int argc, char *argv[]) {
    using namespace kaldi;
    const char *usage = "Post process kwslist (normalization...) -- Service version\nUsage: post-process-kwslist-service <index-num> <output-filename>\n";

    ParseOptions po(usage);

    string segment = "";
    double flen = 0.01;
    double beta = 999.9;
    double duration = 999.9;
    string language = "cantonese";
    string ecf_filename = "";
    int index_size = 0;
    string system_id = "";
    string normalize = "kaldi2";
    string utter_id = "";
    string map_utter = "";
    string utter_one_best = "";
    double Ntrue_scale = 1.0;
    int digits = 0;
    string kwlist_filename = "";
    //int verbose = 0;
    duptime = 0.5;
    bool remove_dup = false;
    bool remove_NO = false;
    int YES_cutoff = -1;
    bool all_YES = false;
    int cutoff_thres = 0;
    bool tree_output = false;

    po.Register("segments", &segment, "Segments file from Kaldi                    (string,  default = "")");
    po.Register("flen", &flen, "Frame length                                (float,   default = 0.01)");
    po.Register("beta", &beta, "Beta value when computing ATWV              (float,   default = 999.9)");
    po.Register("duration", &duration, "Duration of all audio, you must set this    (float,   default = 999.9)");
    po.Register("language", &language, "Language type                               (string,  default = \"cantonese\")");
    po.Register("ecf_filename", &ecf_filename, "ECF file name                               (string,  default = "")");
    po.Register("index_size", &index_size, "Size of index                               (float,   default = 0)");
    po.Register("system_id", &system_id, "System ID                                   (string,  default = "")");
    po.Register("normalize", &normalize, "Normalization method (kaldi/KST/skip)       (string,  default = kaldi2)");
    po.Register("utter_id", &utter_id, "Map utterance to id                         (string,  default = "")");
    po.Register("map_utter", &map_utter, "Map utterance for evaluation                (string,  default = "")");
    po.Register("utter_one_best", &utter_one_best, "1-best result of utterance                (string,  default = "")");
    po.Register("Ntrue_scale", &Ntrue_scale, "Keyword independent scale factor for Ntrue  (float,   default = 1.0)");
    po.Register("digits", &digits, "How many digits should the score use        (int,     default = \"infinite\")");
    po.Register("kwlist_filename", &kwlist_filename, "Kwlist.xml file name                        (string,  default = "")");
    //po.Register("verbose", &verbose, "Verbose level (higher --> more kws section) (integer, default 0)");
    po.Register("duptime", &duptime, "Tolerance for duplicates                    (float,   default = 0.5)");
    po.Register("remove_dup", &remove_dup, "Remove duplicates                           (boolean, default = false)");
    po.Register("remove_NO", &remove_NO, "Remove the \"NO\" decision instances          (boolean, default = false)");
    po.Register("YES_cutoff", &YES_cutoff, "Only keep \"YES-cutoff\" yeses for each kw  (int,     default = -1)");
    po.Register("all_YES", &all_YES, "set hard decisions to YES                   (boolean, default = false)");
    po.Register("cutoff_thres", &cutoff_thres, "remove items whose score <= this value      (float, default = 0)");
    po.Register("tree_output", &tree_output, "output results in a tree structrue      (boolean, default = false)");

    po.Read(argc, argv);
    ifstream fseg;
    if (!segment.empty()) {
      fseg.open(segment.c_str());
      if (!fseg) {
        KALDI_ERR << "Fail to open segment file " << segment << endl;
        exit (1);
      }
    }
    ifstream futtid;
    if (!utter_id.empty()) {
      futtid.open(utter_id.c_str());
      if (!futtid.is_open()) {
        KALDI_ERR << "Fail to open utterance-to-id table " << utter_id;
        exit (1);
      }
    }
    ifstream ftxt;
    if (!utter_one_best.empty()) {
      ftxt.open(utter_one_best.c_str());
      if (!ftxt.is_open()) {
        KALDI_ERR << "Fail to open utterance table " << utter_one_best;
        exit (1);
      }
    }
    ifstream futt;
    if (!map_utter.empty()) {
      futt.open(map_utter.c_str());
      if (!futt.is_open()) {
        KALDI_ERR << "Fail to open utterance table " << map_utter;
        exit (1);
      }
    }

    if (po.NumArgs() < 2 || po.NumArgs() > 2) {
      po.PrintUsage();
      exit(1);
    }

    int index_num = atoi(po.GetArg(1).c_str());
    string fileout = po.GetArg(2);
    
    // Get utterance id
    vector<string> id2utter;
    map<string,unsigned int> utter2id;
    if (!utter_id.empty()) {
      ScopeLogger scopeUtterMapper("utter_id");
      vector<string> lines;
      id2utter.push_back("");
      unsigned int id = 0;
      for (string line; getline(futtid, line); ) {
        istringstream split(line);
        vector<string> col;
        for (string each; getline(split, each, ' '); col.push_back(each));
        if (col.size() != 2) {
          KALDI_ERR << "Bad number of columns in " << utter_id << " \"" << line << "\"\n";
          exit (1);
        }
        id2utter.push_back(col[0]);
        utter2id[col[0]] = ++id;
      }
    }
    if (futtid.is_open()) {
      futtid.close();
    }
    
    // Get utterance mapper
    //unordered_map<string, string> utter_mapper;
    vector<string> id2file(id2utter.size(), "");
    id2url.resize(id2utter.size(), "");
    id2date.resize(id2utter.size(), 0);
    id2program.resize(id2utter.size(), "");
    id2subtitle.resize(id2utter.size(), "");
    if (!map_utter.empty()) {
      ScopeLogger scopeUtterMapper("utter_mapper");
      vector<string> lines;
      for (string line; getline(futt, line); ) {
        istringstream split(line);
        vector<string> col;
        for (string each; getline(split, each, ' '); col.push_back(each));
        if (col.size() != 2) {
          KALDI_ERR << "Bad number of columns in " << map_utter << " \"" << line << "\"\n";
          exit (1);
        }
        //utter_mapper[col[0]] = col[1];
        unsigned int id = utter2id[col[0]];
        id2file[id] = col[1];
        //id2url[id] = file2url(col[1]);
        extractInfoFromFile(col[1], id2url[id], id2date[id], id2program[id], id2subtitle[id]);
      }
    }
    if (futt.is_open()) {
      futt.close();
    }

    // Get utterance 1-best
    id2hyp.resize(id2utter.size(), "");
    if (!utter_one_best.empty()) {
      ScopeLogger scopeUtterMapper("utter_one_best");
      vector<string> lines;
      for (string line; getline(ftxt, line); ) {
        istringstream split(line);
        vector<string> col;
        for (string each; getline(split, each, '\t'); col.push_back(each));
        if (col.size() != 2) {
          KALDI_ERR << "Bad number of columns in " << utter_one_best << " \"" << line << "\"\n";
          exit (1);
        }
        unsigned int id = utter2id[col[0]];
        id2hyp[id] = col[1];
        //regex_replace(col[1], reg, string(""));
      }
    }
    if (ftxt.is_open()) {
      ftxt.close();
    }
    

    // Get symbol table and start time
    //unordered_map<string, double> tbeg;
    vector<double> id2tbeg(id2utter.size(), 0.0);
    if (!segment.empty()) {
      ScopeLogger scopeTbeg("tbeg");
      vector<string> lines;
      for (string line; getline(fseg, line); ) {
        istringstream split(line);
        vector<string> col;
        for (string each; getline(split, each, ' '); col.push_back(each));
        if (col.size() != 4) {
          KALDI_ERR << "Bad number of columns in " << segment << " \"" << line << "\"\n";
          exit (1);
        }
        //tbeg[col[0]] = atof(col[2].c_str());
        id2tbeg[utter2id[col[0]]] = atof(col[2].c_str());
      }
    }
    utter2id.clear();
    if (fseg.is_open()) {
      fseg.close();
    }

    // Creating socket...
    int    listenfd, connfd;
    struct sockaddr_un     servaddr;
    char    buff[MAXLINE], *tgtDir;
    int     n;

    if( (listenfd = socket(AF_UNIX, SOCK_STREAM, 0)) == -1 ){
      printf("create socket error: %s(errno: %d)\n",strerror(errno),errno);
      exit(0);
    }

    memset(&servaddr, 0, sizeof(servaddr));
    servaddr.sun_family = AF_UNIX;
    strncpy(servaddr.sun_path, UNIX_DOMAIN, sizeof(servaddr.sun_path)-1);
    unlink(UNIX_DOMAIN); 
    //servaddr.sin_addr.s_addr = htonl(INADDR_ANY);
    //servaddr.sin_port = htons(port);

    if( bind(listenfd, (struct sockaddr*)&servaddr, sizeof(servaddr)) == -1){
      printf("bind socket error: %s(errno: %d)\n",strerror(errno),errno);
      close(listenfd);
      unlink(UNIX_DOMAIN);
      exit(1);
    }

    if( listen(listenfd, 10) == -1){
      printf("listen socket error: %s(errno: %d)\n",strerror(errno),errno);
      exit(1);
    }
    printf("Post-processor service started\n");
    // Start serving...
    bool leave = false;
    while(!leave){
      if( (connfd = accept(listenfd, (struct sockaddr*)NULL, NULL)) == -1){
        printf("accept socket error: %s(errno: %d)",strerror(errno),errno);
        continue;
      }
#ifdef _NO_FORK
      pid_t pid = 0;
#else
      pid_t pid = fork();
#endif
      if (pid < 0) {
        KALDI_ERR << "[E] Error in folk";
        continue;
      }
      if (pid == 0) {
        ScopeLogger scopeWork("work");
        n = recv(connfd, buff, MAXLINE, 0);
        struct timeval tpstart, tpend;
        gettimeofday(&tpstart, NULL);
        buff[n] = '\0';
        int offset, limit;
        char ip[16];
        offset = atoi(buff);
        limit = atoi(buff + 16);
        strcpy(ip, buff + 32);
        tgtDir = buff + 48;
        time_t lt = time(NULL);
        printf("--------------------------------------------------\n[%s] %s--------------------------------------------------\n",
            ip, ctime(&lt));
        char tmp[MAXLINE];
        sprintf(tmp, "%s.txt", tgtDir);
        FILE *fquery = fopen(tmp, "r");
        if (fquery) {
          int id;
          fscanf(fquery, "%d\t%s", &id, tmp);
          printf("Keyword=%s\t", tmp);
          fclose(fquery);
        }
        printf("Offset=%d\tLimit=%d\n", offset, limit);
        printf("%s\n", tgtDir);


        // Processing
        vector<Hit> raw_KWS;
        char filenameroot[MAXLINE];
        sprintf(filenameroot, "%s/result.", tgtDir);
        char *fid = filenameroot + strlen(filenameroot);
        for (int f = 1; f <= index_num; f++) {
          sprintf(fid, "%d", f);
          FILE *fin = fopen(filenameroot, "r");
          if (!fin) {
            KALDI_ERR << "[WARNING] Fail to open result file: " << filenameroot;
            continue;
          }
          char line[MAXLINE];
          for (; fgets(line, MAXLINE, fin); ) {
            Hit h;
            int n_start, n_dur;
            if (5 != sscanf(line, "%u %u %u %u %lf", &(h.kwid), &(h.utt_id), &n_start, &n_dur, &(h.score))) {
              KALDI_ERR << "Bad number of columns in raw results \"" << line << "\"";
              exit (1);
            }
            h.utter = id2utter[h.utt_id];
            h.start = n_start * flen;
            h.utt_start = 0;
            h.dur = n_dur * flen - h.start;
            h.score = exp(-h.score);
            if (!segment.empty()) {
              h.utt_start = id2tbeg[h.utt_id];
              h.start += h.utt_start;
            }
            if (!map_utter.empty()) {
              h.file = id2file[h.utt_id];
            } else {
              h.file = h.utter;
            }
            raw_KWS.push_back(h);
          }
          fclose(fin);
        }
        scopeWork.checkPoint("reading finished");

        // Removing duplicates
        vector<Hit> KWS;
        if (remove_dup) {
          ScopeLogger scopeRemoveDup("remove_dup");
          if (!raw_KWS.empty()) {
            sort(raw_KWS.begin(), raw_KWS.end(), KwslistDupSort);
            vector<Hit>::iterator itRaw = raw_KWS.begin();
            KWS.push_back(*itRaw);
            for (itRaw++; itRaw != raw_KWS.end(); ++itRaw) {
              Hit &prev = *KWS.end();
              Hit &curr = *itRaw;
              if ((abs(prev.start - curr.start) < duptime) &&
                  (prev.utt_id == curr.utt_id) ) {
                if (normalize[normalize.length()-1] == '2') {
                  if (curr.score_raw > prev.score_raw) {
                    prev.score_raw = curr.score_raw;
                    prev.start = curr.start;
                    prev.dur = curr.dur;
                  }
                  prev.score += curr.score;
                  if (prev.score > 1.0) {
                    cerr << "[WARN] score exceeds 1.0 to " << prev.score << " for "
                     << prev.kwid << " " << prev.utter << " " << prev.start << endl;
                    prev.score = 1.0;
                  }
                }
                continue;
              } else {
                KWS.push_back(curr);
              }
            }
          }
        }
        // TODO should be only one Ntrue and one threshold
        scopeWork.checkPoint("Ntrue");
        double Ntrue = 0.0;
        for (vector<Hit>::const_iterator iter = KWS.begin(); iter != KWS.end(); ++iter) {
          Ntrue += iter->score;
        }

        // Scale the Ntrue
        scopeWork.checkPoint("threshold");
        double threshold;
        Ntrue *= Ntrue_scale;
        threshold = Ntrue / (duration/beta + (beta-1) * Ntrue / beta);

        if (digits <= 0) {
          format_string = "%g";
        } else {
          ostringstream os;
          os << "%." << digits << "f";
          format_string = os.str();
        }

        string outdir = fileout.substr(0, fileout.find_last_of("/"));
        // TODO something about STO
        // TODO something about QL
        
        scopeWork.checkPoint("normalization");
        Info info;
        info.kwlist_filename = kwlist_filename;
        info.language = language;
        info.system_id = system_id;
        int YES_count = 0;
        double logThr = log(0.5);
        for (vector<Hit>::iterator iter = KWS.begin(); iter != KWS.end(); ++iter) {
          if (iter->score > threshold) {
            iter->decision = true;
            YES_count++;
          } else {
            iter->decision = false;
          }
          /*if (verbose > 0) {

          }*/
          if (normalize.find("kaldi") != string::npos) {
            double numerator = (1 - threshold) * iter->score;
            double denominator = (1 - threshold) * iter->score + (1 - iter->score) * threshold;
            if (denominator != 0) {
              //char new_score[64];
              //sprintf(new_score, format_string.c_str(), numerator / denominator);
              iter->score = numerator / denominator;
            } // if denominator == 0, score will not be changed.
          } else if (normalize == "KST") {
            iter->score = pow(iter->score, logThr/log(threshold));
          } 
          // TODO do something about STO and QL
        }
        // Output sorting
        if (!tree_output) {
          sort(KWS.begin(), KWS.end(), KwslistOutputSort);
        } else {
          sort(KWS.begin(), KWS.end(), KwslistTreeOutputSort);
        }
        if (all_YES) {
          ScopeLogger scopeOutputYes("all_YES");
          for (vector<Hit>::iterator iter = KWS.begin(); iter != KWS.end(); ++iter) {
            iter->decision = true;
          }
        } else {
          // Process the YES-cutoff. Note that you don't need this for the normal cases where
          // hits and false alarms are balanced
          if (YES_cutoff != -1) {
            ScopeLogger scopeOutputNo("YES_cutoff");
            int count = 1;
            for (int i = 1; i < KWS.size(); i++) {
              if (YES_count > YES_cutoff * 2) {
                KWS[i].decision = false;
                KWS[i].score = 0;
                continue;
              }
              if ((count == YES_cutoff) && KWS[i].decision) {
                KWS[i].decision = false;
                KWS[i].score = 0;
                continue;
              }
              if (KWS[i].decision) {
                count++;
              }
            }
          }
        }
        vector<Hit> *pKWS = &KWS;
        // Process the remove-NO decision and the cutoff for low score items
        vector<Hit> out_KWS;
        if (remove_NO || cutoff_thres >= 0) {
          ScopeLogger scopeNoCutoff("remove_NO || cutoff_thres");
          for (vector<Hit>::iterator iter = KWS.begin(); iter != KWS.end(); ++iter) {
            if ((!remove_NO || iter->decision)
                && (cutoff_thres < 0 || iter->score > cutoff_thres)) {
              out_KWS.push_back(*iter);
            }
          }
          pKWS = &out_KWS;
        }
        // Printing
        scopeWork.checkPoint("print");
        char *buff = new char[MAXDATASIZE];
        //PrintKwslist(info, *pKWS, buff);
        if (!tree_output) {
          PrintKwslistJson(*pKWS, buff, offset, limit);
        } else {
          PrintKwslistJsonTree(*pKWS, buff, offset, limit);
        }
#ifdef _DEBUG
        printf("%s\n", buff);
#endif
        scopeWork.checkPoint("send");
        if (!send_all(connfd, buff, strlen(buff))) {
          perror("WARNING: send data failed\n");
        }
        /* 
        if (fileout != "-") {
          char outfile[MAXLINE];
          sprintf(outfile, "%s/%s", tgtDir, fileout.c_str());
          FILE *fout = fopen(outfile, "w");
          fprintf(fout, "%s", buff);
          fclose(fout);
        } */
        gettimeofday(&tpend, NULL);
        printf("Time elapsed: %f\n", tpend.tv_sec - tpstart.tv_sec + (double)(tpend.tv_usec - tpstart.tv_usec) / 1000000);
#ifndef _NO_FORK
        leave = true;
#endif
      } else {
        // Parent process
      }
      close(connfd);
    }
    return 0;
}
