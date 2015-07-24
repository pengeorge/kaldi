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
#define _DEBUG

#include <stdlib.h>
#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include<errno.h>
#include<sys/types.h>
#include<sys/socket.h>
#include <sys/wait.h>
#include<sys/time.h>
#include<unistd.h>
#include<netinet/in.h>
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
  //unsigned short chnl; //2
  double start; //3
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

// Function for sorting
bool KwslistOutputSort(const Hit & a, const Hit & b) {
  if (a.kwid != b.kwid) {
    return (a.kwid < b.kwid); // for number
    //return (strcmp(a.kwid.c_str(), b.kwid.c_str()) < 0); // for string
  } else if (a.score != b.score) {
    return (a.score > b.score);
  } else {
    return (a.utt_id < b.utt_id);
  }
}

double duptime;
string format_string;
bool KwslistDupSort(const Hit & a, const Hit & b) {
  if (a.kwid != b.kwid) {
    return (a.kwid < b.kwid);
  } else if (a.utt_id != b.utt_id) {
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
    const char *usage = "Post process kwslist (normalization...) -- Service version\nUsage: post-process-kwslist-service <index-num> <port> <output-filename>\n";

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
    ifstream futt;
    if (!map_utter.empty()) {
      futt.open(map_utter.c_str());
      if (!futt.is_open()) {
        KALDI_ERR << "Fail to open utterance table " << map_utter;
        exit (1);
      }
    }

    if (po.NumArgs() < 3 || po.NumArgs() > 3) {
      po.PrintUsage();
      exit(1);
    }

    int index_num = atoi(po.GetArg(1).c_str());
    int port = atoi(po.GetArg(2).c_str());
    string fileout = po.GetArg(3);
    
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
        id2file[utter2id[col[0]]] = col[1];
      }
    }
    if (futt.is_open()) {
      futt.close();
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
    struct sockaddr_in     servaddr;
    char    tgtDir[MAXLINE];
    int     n;

    if( (listenfd = socket(AF_INET, SOCK_STREAM, 0)) == -1 ){
      printf("create socket error: %s(errno: %d)\n",strerror(errno),errno);
      exit(0);
    }

    memset(&servaddr, 0, sizeof(servaddr));
    servaddr.sin_family = AF_INET;
    servaddr.sin_addr.s_addr = htonl(INADDR_ANY);
    servaddr.sin_port = htons(port);

    if( bind(listenfd, (struct sockaddr*)&servaddr, sizeof(servaddr)) == -1){
      printf("bind socket error: %s(errno: %d)\n",strerror(errno),errno);
      exit(0);
    }

    if( listen(listenfd, 10) == -1){
      printf("listen socket error: %s(errno: %d)\n",strerror(errno),errno);
      exit(0);
    }
    printf("Post-processor service started, port %d\n", port);
    // Start serving...
    bool leave = false;
    while(!leave){
      if( (connfd = accept(listenfd, (struct sockaddr*)NULL, NULL)) == -1){
        printf("accept socket error: %s(errno: %d)",strerror(errno),errno);
        continue;
      }
      pid_t pid = fork();
      if (pid < 0) {
        KALDI_ERR << "[E] Error in folk";
        continue;
      }
      if (pid == 0) {
        ScopeLogger scopeWork("work");
        n = recv(connfd, tgtDir, MAXLINE, 0);
        tgtDir[n] = '\0';
        printf("Receiving result directory: %s\n", tgtDir);
        struct timeval tpstart, tpend;
        gettimeofday(&tpstart, NULL);

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
            h.dur = n_dur * flen - h.start;
            h.score = exp(-h.score);
            if (!segment.empty()) {
              h.start += id2tbeg[h.utt_id];
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
          sort(raw_KWS.begin(), raw_KWS.end(), KwslistDupSort);
          vector<Hit>::iterator itRaw = raw_KWS.begin();
          KWS.push_back(*itRaw);
          for (itRaw++; itRaw != raw_KWS.end(); ++itRaw) {
            Hit &prev = *KWS.end();
            Hit &curr = *itRaw;
            if ((abs(prev.start - curr.start) < duptime) &&
                (prev.utt_id == curr.utt_id) &&
                (prev.kwid == curr.kwid)) {
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
        // TODO should be only one Ntrue and one threshold
        scopeWork.checkPoint("Ntrue");
        map<unsigned int, double> Ntrue;
        for (vector<Hit>::const_iterator iter = KWS.begin(); iter != KWS.end(); ++iter) {
          if (Ntrue.find(iter->kwid) == Ntrue.end()) {
            Ntrue[iter->kwid] = 0.0;
          }
          Ntrue[iter->kwid] += iter->score;
        }

        // Scale the Ntrue
        scopeWork.checkPoint("threshold");
        map<unsigned int, double> threshold;
        for (map<unsigned int,double>::iterator iter = Ntrue.begin(); iter != Ntrue.end(); ++iter) {
          Ntrue[iter->first] *= Ntrue_scale;
          threshold[iter->first] = iter->second / (duration/beta + (beta-1) * iter->second / beta);
        }

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
        map<unsigned int, int> YES_count;
        double logThr = log(0.5);
        for (vector<Hit>::iterator iter = KWS.begin(); iter != KWS.end(); ++iter) {
          double thres = threshold[iter->kwid];
          if (iter->score > thres) {
            iter->decision = true;
            if (YES_count.find(iter->kwid) != YES_count.end()) {
              YES_count[iter->kwid]++;
            } else {
              YES_count[iter->kwid] = 1;
            }
          } else {
            iter->decision = false;
            if (YES_count.find(iter->kwid) == YES_count.end()) {
              YES_count[iter->kwid] = 0;
            }
          }
          /*if (verbose > 0) {

          }*/
          if (normalize.find("kaldi") != string::npos) {
            double numerator = (1 - thres) * iter->score;
            double denominator = (1 - thres) * iter->score + (1 - iter->score) * thres;
            if (denominator != 0) {
              //char new_score[64];
              //sprintf(new_score, format_string.c_str(), numerator / denominator);
              iter->score = numerator / denominator;
            } // if denominator == 0, score will not be changed.
          } else if (normalize == "KST") {
            iter->score = pow(iter->score, logThr/log(thres));
          } 
          // TODO do something about STO and QL
        }
        // Output sorting
        scopeWork.checkPoint("output");
        sort(KWS.begin(), KWS.end(), KwslistOutputSort);
        if (all_YES) {
          ScopeLogger scopeOutputYes("output all_YES");
          for (vector<Hit>::iterator iter = KWS.begin(); iter != KWS.end(); ++iter) {
            iter->decision = true;
          }
        } else {
          ScopeLogger scopeOutputNo("output !all_YES");
          // Process the YES-cutoff. Note that you don't need this for the normal cases where
          // hits and false alarms are balanced
          if (YES_cutoff != -1) {
            int count = 1;
            for (int i = 1; i < KWS.size(); i++) {
              if (KWS[i].kwid != KWS[i-1].kwid) {
                count = 1;
                continue;
              }
              if (YES_count[KWS[i].kwid] > YES_cutoff * 2) {
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
        PrintKwslist(info, *pKWS, buff);
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
        leave = true;
      } else {
        // Parent process
      }
      close(connfd);
    }
    return 0;
}
