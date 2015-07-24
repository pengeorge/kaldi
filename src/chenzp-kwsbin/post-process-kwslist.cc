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
#include <stdlib.h>
#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include <fstream>
#include <map>
using namespace std;

class ScopeLogger {
public:
  ScopeLogger(const string & id)
//    : _id(id)
  {
//    cerr << "### Enter scope " << _id << " ###" << endl;
  }
  ~ScopeLogger()
  {
//    cerr << "### Leave scope " << _id << " ###" << endl;
  }
  void checkPoint(const string & name)
  {
//    cerr << "### In scope " << _id << ": checkpoint " << name << " ###" << endl;
  }
private:
//  string _id;
};

struct Hit {
  string kwid; //0
  string utter; //1
  unsigned short chnl; //2
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
    //return (atoi(a.kwid.c_str()) < atoi(b.kwid.c_str())); // for number
    return (strcmp(a.kwid.c_str(), b.kwid.c_str()) < 0);
  } else if (a.score != b.score) {
    return (a.score > b.score);
  } else {
    return (strcmp(a.utter.c_str(), b.utter.c_str()) < 0);
  }
}

double duptime;
string format_string;
bool KwslistDupSort(const Hit & a, const Hit & b) {
  if (a.kwid != b.kwid) {
    return (strcmp(a.kwid.c_str(), b.kwid.c_str()) < 0);
  } else if (a.utter != b.utter) {
    return (strcmp(a.utter.c_str(), b.utter.c_str()) < 0);
  } else if (a.chnl != b.chnl) {
    return (a.chnl < b.chnl);
  } else if (abs(a.start - b.start) >= duptime) {
    return (a.start < b.start);
  } else if (a.score != b.score) {
    return (a.score > b.score);
  } else {
    return (a.dur > b.dur);
  }
}

// Function for printing Kwslist.xml (printf version)
void PrintKwslist(const Info &info, const vector<Hit> &KWS, FILE *fout) {
  // Starting printing
  fprintf(fout, "<kwslist kwlist_filename=\"%s\" language=\"%s\" system_id=\"%s\">\n",
     info.kwlist_filename.c_str(), info.language.c_str(), info.system_id.c_str());
  string prev_kw = "";
  for (vector<Hit>::const_iterator iter = KWS.begin(); iter != KWS.end(); ++iter) {
    if (prev_kw != iter->kwid) {
      if (!prev_kw.empty()) {
        fprintf(fout, "  </detected_kwlist>\n");
      }
      fprintf(fout, "  <detected_kwlist search_time=\"1\" kwid=\"%s\" oov_count=\"0\">\n", iter->kwid.c_str());
      prev_kw = iter->kwid;
    }
    fprintf(fout, "    <kw file=\"%s\" channel=\"%d\" tbeg=\"%.2f\" dur=\"%.2f\" score=\"",
       iter->utter.c_str(), iter->chnl, iter->start, iter->dur);
    fprintf(fout, format_string.c_str(), iter->score);
    fprintf(fout, "\" decision=\"%s\"/>\n", (iter->decision?"YES":"NO"));
  }
  if (!prev_kw.empty()) {
    fprintf(fout, "  </detected_kwlist>\n");
  }
  fprintf(fout, "</kwslist>\n");
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
    ScopeLogger scopeMain("main");
    using namespace kaldi;
    const char *usage = "Post process kwslist (normalization...) -- Experiment version\n";

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

    string filein = po.GetArg(1);
    string fileout = po.GetArg(2);
    
    istream *source;
    ifstream fin;
    if (filein == "-") {
      source = &cin;
    } else {
      fin.open(filein.c_str());
      if (!fin) {
        KALDI_ERR << "Fail to open input file " << filein;
        exit (1);
      }
      source = &fin;
    }
    // Get symbol table and start time
    unordered_map<string, double> tbeg;
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
        tbeg[col[0]] = atof(col[2].c_str());
      }
    }
    if (fseg.is_open()) {
      fseg.close();
    }
    // Get utterance mapper
    unordered_map<string, string> utter_mapper;
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
        utter_mapper[col[0]] = col[1];
      }
    }
    if (futt.is_open()) {
      futt.close();
    }
    // Processing
    vector<Hit> raw_KWS;
    for (string line; getline(*source, line); ) {
      istringstream split(line);
      vector<string> col;
      for (string each; getline(split, each, ' '); col.push_back(each));
      if (col.size() != 5) {
        KALDI_ERR << "Bad number of columns in raw results \"" << line << "\"";
        exit (1);
      }
      Hit h;
      h.kwid = col[0];
      h.utter = col[1];
      h.start = atof(col[2].c_str()) * flen;
      h.dur = atof(col[3].c_str()) * flen - h.start;
      h.score = exp(-atof(col[4].c_str()));
      if (!segment.empty()) {
        h.start += tbeg[h.utter];
      }
      if (!map_utter.empty()) {
        h.utter = utter_mapper[h.utter];
      }
      h.chnl = 1;
      if (h.utter[h.utter.length()-2] == '-' &&
          (h.utter[h.utter.length()-1] == 'A' || h.utter[h.utter.length()-1] == 'B') ) {
        h.chnl = (char)h.utter[h.utter.length()-1] - 'A' + 1;
      }
      raw_KWS.push_back(h);
    }
    if (filein != "-" && fin.is_open()) {
      fin.close();
    }
    scopeMain.checkPoint("processing finished");

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
            (prev.chnl == curr.chnl) &&
            (prev.utter == curr.utter) &&
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
                << prev.kwid << " " << prev.utter << " " << prev.chnl << " "
                << prev.start << endl;
              prev.score = 1.0;
            }
          }
          continue;
        } else {
          KWS.push_back(curr);
        }
      }
    }
    scopeMain.checkPoint("Ntrue");
    map<string, double> Ntrue;
    for (vector<Hit>::const_iterator iter = KWS.begin(); iter != KWS.end(); ++iter) {
      if (Ntrue.find(iter->kwid) == Ntrue.end()) {
        Ntrue[iter->kwid] = 0.0;
      }
      Ntrue[iter->kwid] += iter->score;
    }

    // Scale the Ntrue
    scopeMain.checkPoint("threshold");
    map<string, double> threshold;
    for (map<string,double>::iterator iter = Ntrue.begin(); iter != Ntrue.end(); ++iter) {
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
    
    scopeMain.checkPoint("normalization");
    Info info;
    info.kwlist_filename = kwlist_filename;
    info.language = language;
    info.system_id = system_id;
    map<string, int> YES_count;
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
    scopeMain.checkPoint("output");
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
    scopeMain.checkPoint("print");
    /* // Stream output version
    string kwslist = PrintKwslist(info, *pKWS);
    if (fileout == "-") {
      printf("%s", kwslist.c_str());
    } else {
      ofstream fout(fileout.c_str());
      if (!fout) {
        KALDI_ERR << "Fail to open output file " << fileout;
        exit (1);
      }
      fout << kwslist;
      fout.close();
    }*/
    if (fileout == "-") {
      PrintKwslist(info, *pKWS, stdout);
    } else {
      FILE *fout = fopen(fileout.c_str(), "w");
      PrintKwslist(info, *pKWS, fout);
      fclose(fout);
    }
    return 0;
}
