#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include <iostream>
#include <fstream>
#include "util/text-utils.h"
using namespace std;
using namespace kaldi;

class NgramLM {
  public:
  void ReadARPA(string filename) {
    cprob.clear();
    bow.clear();
    ifstream ifile(filename.c_str());
    string line;
    bool is_header_readed = false;
    n = 0;
    int k = -1;
    while (getline(ifile, line)) {
      if (!is_header_readed) {
        if (line.compare("\\data\\") == 0) {
          continue;
        } else if (line.compare(0, 5, "ngram") == 0) {
          n++;
          continue;
        } else if (line.empty()) {
          if (n > 0) {
            is_header_readed = true;
          }
          continue;
        }
      } else {
        if (line[0] == '\\') {
          if (line.compare("\\end\\") == 0) {
            break;
          } else if (line.find("-grams:", 0) != -1) {
            k++;
            map<string, double> tmp;
            cprob.push_back(tmp);
            bow.push_back(tmp);
          }
          continue;
        } else if (line.empty()) {
          continue;
        } else { // Read items
          double cond_prob, backoff_weight;
          string item;
          vector<string> col;
          SplitStringToVector(line, "\t", false, &col);
          item = col[1];
          ConvertStringToReal(col[0], &cond_prob);
          cprob[k].insert(pair<string, double>(item, cond_prob));
          if (col.size() >= 3) {
            ConvertStringToReal(col[2], &backoff_weight);
            bow[k].insert(pair<string, double>(item, backoff_weight));
          }
        }
      }
    }
    ifile.close();
  }
  int n;
  vector< map<string, double> > cprob;
  vector< map<string, double> > bow;
};

NgramLM lm;
map<pair<string, string>, double> s; // best score (lowest perplexity)
map<pair<string, string>, double> p; // conditional prob: directly read cprob or calculate via backoff
map<pair<string, string>, int> best_seg; // the best 1st segment

double getp(string h, string w) { // h: w1 w2  (delim: space)
  pair<string, string> key(h, w);
  if (p.find(key) == p.end()) {
    //vector<string> hwords;
    //SplitStringToVector(h, " ", true, &hwords);
    //int h_num = hwords.size();
    int h_num;
    if (h.empty()) {
      h_num = 0;
    } else {
      h_num = count(h.begin(), h.end(), ' ') + 1;
    }
    string key_in_lm = (h_num==0 ? w : (h + " " + w));
    if (lm.cprob[h_num].find(key_in_lm) != lm.cprob[h_num].end()) {
      p.insert(pair<pair<string, string>, double>(key, lm.cprob[h_num][key_in_lm]));
      //KALDI_LOG << "p(" << key.second << " | " << key.first << ") = " << p[key] << " (no backoff)";
    } else if (h_num == 0) {
      //KALDI_LOG << "No P(" << w << " | " << h << ")";
      p.insert(pair<pair<string, string>, double>(key, -99999));
    } else {
      string hh;
      if (h_num == 1) {
        hh = "";
      } else {
        hh = h.substr(h.find(' ')+1); // remove 1st (farthest) history word
      }
      double this_p = getp(hh, w);
      if (lm.bow[h_num-1].find(h) != lm.bow[h_num-1].end()) {
        this_p += lm.bow[h_num-1][h];
      }
      p.insert(pair<pair<string, string>, double>(key, this_p));
      //KALDI_LOG << "p(" << key.second << " | " << key.first << ") = " << p[key] << " (backoff)";
    }
  }
  return p[key];
}

double score(string h, string atoms) {
  pair<string, string> key(h, atoms);
  if (s.find(key) == s.end()) {
    if (atoms.empty()) {  // 0 atom
      s.insert(pair<pair<string, string>, double>(key, 0.0));
    } else {
      int pos = atoms.find(' ');
      if (pos == string::npos) {  // 1 atom
        s.insert(pair<pair<string, string>, double>(key, getp(h, atoms)));
        best_seg.insert(pair<pair<string, string>, int>(key, 0));
      } else { // >1 atoms
        string hh;  // sub history
        int h_num;
        if (h.empty()) {
          h_num = 0;
        } else {
          h_num = count(h.begin(), h.end(), ' ') + 1;
        }
        if (h_num < lm.n - 1) { // not enough history words
          hh = h;
        } else if (h_num <= 1) { // h_num == lm.n - 1,   h_num = 0 or 1, lm.n == 1 or 2
          hh = "";
        } else {  // 2 <= h_num == lm.n - 1
          //int h_pos = h.find(' ');
          //KALDI_ASSERT(h_pos != string::npos);
          hh = h.substr(h.find(' ') + 1);
        }
        if (!hh.empty()) {
          hh += " ";
        }
        string next_word = atoms.substr(0, pos);
        atoms = atoms.substr(pos+1);
        double max_score = getp(h, next_word) + score((lm.n==1 ? "" : (hh + next_word)), atoms);
        int local_best_seg = 0;
        int curr_seg = 0;
        pos = atoms.find(' ');
        while (pos != string::npos) {
          next_word += "." + atoms.substr(0, pos);
          atoms = atoms.substr(pos+1);
          curr_seg++;
          double local_score = getp(h, next_word);
          if (local_score > max_score) {
            local_score += score((lm.n==1 ? "" : (hh + next_word)), atoms);
            if (local_score > max_score) {
              max_score = local_score;
              local_best_seg = curr_seg;
            }
          }
          pos = atoms.find(' ');
        }
        // the last atom
        next_word += "." + atoms;
        curr_seg++;
        double local_score = getp(h, next_word); // + 0.0
        if (local_score > max_score) {
          max_score = local_score;
          local_best_seg = curr_seg;
        }
        s.insert(pair<pair<string, string>, double>(key, max_score));
        best_seg.insert(pair<pair<string, string>, int>(key, local_best_seg));
      }
    }
    //KALDI_LOG << "score(" << key.first << ", " << key.second << ") = " << s[key];
    //KALDI_LOG << "best_seg(" << key.first << ", " << key.second << ") = " << best_seg[key];
  }
  return s[key];
}


int main(int argc, char *argv[]) {
  const char *usage =
    "Generate word-to-subword lexicon by a language model\n"
    "Usage: generate-w2s-lexicon <input-lexicon> <LM-file> <output-w2s-lexicon>\n";
  ParseOptions po(usage);
  bool romanized = false;
  po.Register("romanized", &romanized, "Whether the input lexicon is romanized.");
  po.Read(argc, argv);
  if (po.NumArgs() != 3) {
    po.PrintUsage();
    exit(1);
  }

  string in_lex_filename = po.GetArg(1),
         lm_filename = po.GetArg(2),
         out_w2s_filename = po.GetArg(3);

  lm.ReadARPA(lm_filename);

  ifstream lexfile(in_lex_filename.c_str());
  ofstream ofile(out_w2s_filename.c_str());
  string line;
  int spos = 1;
  if (romanized) {
    spos++;
  }
  while (getline(lexfile, line)) {
    vector<string> col;
    SplitStringToVector(line, "\t", true, &col);
    ofile << col[0];
    for (unsigned i = spos; i < col.size(); i++) {
      string pron = col[i];
      vector<string> atoms;
      SplitStringToVector(pron, ".#", true, &atoms);
      for (unsigned k = 0; k < atoms.size(); k++) {
        Trim(&atoms[k]);
        replace(atoms[k].begin(), atoms[k].end(), ' ', '-');
      }
      string str_atoms;
      JoinVectorToString(atoms, " ", true, &str_atoms);
      double max_score = score("", str_atoms);
      //KALDI_LOG << "Score of " << str_atoms << ": " << max_score;
      string subword_seq = "";
      string h = "";
      int cnt = 0;
      while (!str_atoms.empty()) {
        int num = best_seg[make_pair(h, str_atoms)];
        //KALDI_LOG << str_atoms << ",  seg num: " << num;
        int pos = -1;
        for (int k = 0; k < num; k++) {
          pos = str_atoms.find(' ', pos+1);
          KALDI_ASSERT(pos != string::npos);
        }
        pos = str_atoms.find(' ', pos+1);
        if (pos == string::npos) { // to the end
          pos = str_atoms.length();
        }
        string subword = str_atoms.substr(0, pos);
        replace(subword.begin(), subword.end(), ' ', '.');
        if (pos == str_atoms.length()) {
          str_atoms = "";
        } else {
          str_atoms = str_atoms.substr(pos+1);
        }
        if (cnt == 0) {
          subword_seq += subword;
          if (lm.n > 1) {
            h = subword;
          }
        } else {
          subword_seq += " " + subword;
          if (lm.n > 1) {
            if (cnt >= lm.n - 1) {
              if (lm.n > 2) {
                h = h.substr(h.find(' ') + 1);
                h += " " + subword;
              } else {
                h = subword;
              }
            } else {
              h += " " + subword;
            } 
          }
        }
        cnt++;
      }
      ofile << "\t" << subword_seq;
      cout << col[0] << "\t" << subword_seq << "\t" << max_score << "\n";
    }
    ofile << "\n";
  }
  lexfile.close();
  ofile.close();
}

