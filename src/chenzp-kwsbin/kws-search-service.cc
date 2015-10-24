// kwsbin/kws-search.cc

// Copyright 2012-2013  Johns Hopkins University (Authors: Guoguo Chen, Daniel Povey)

// See ../../COPYING for clarification regarding multiple authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
// THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
// WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
// MERCHANTABLITY OR NON-INFRINGEMENT.
// See the Apache 2 License for the specific language governing permissions and
// limitations under the License.


#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include "fstext/fstext-utils.h"
#include "fstext/kaldi-fst-io.h"
#include "kws/kaldi-kws.h"
#include<stdio.h>
#include<stdlib.h>
#include<string.h>
#include<errno.h>
#include<sys/types.h>
#include<sys/socket.h>
#include <sys/wait.h>
#include<sys/time.h>
#include<unistd.h>
#include<netinet/in.h>
#define MAXLINE 1024

namespace kaldi {

  typedef KwsLexicographicArc Arc;
  typedef Arc::Weight Weight;
  typedef Arc::StateId StateId;

  uint64 EncodeLabel(StateId ilabel,
      StateId olabel) {
    return (((int64)olabel)<<32)+((int64)ilabel);

  }

  StateId DecodeLabelUid(uint64 osymbol) {
    // We only need the utterance id
    return ((StateId)(osymbol>>32));
  }

  class VectorFstToKwsLexicographicFstMapper {
    public:
      typedef fst::StdArc FromArc;
      typedef FromArc::Weight FromWeight;
      typedef KwsLexicographicArc ToArc;
      typedef KwsLexicographicWeight ToWeight;

      VectorFstToKwsLexicographicFstMapper() {}

      ToArc operator()(const FromArc &arc) const {
        return ToArc(arc.ilabel, 
            arc.olabel,
            (arc.weight == FromWeight::Zero() ?
             ToWeight::Zero() :
             ToWeight(arc.weight.Value(),
               StdLStdWeight::One())),
            arc.nextstate);
      }

      fst::MapFinalAction FinalAction() const { return fst::MAP_NO_SUPERFINAL; }

      fst::MapSymbolsAction InputSymbolsAction() const { return fst::MAP_COPY_SYMBOLS; }

      fst::MapSymbolsAction OutputSymbolsAction() const { return fst::MAP_COPY_SYMBOLS;}

      uint64 Properties(uint64 props) const { return props; }
  };

}

bool send_all(int socket, const char *buffer, size_t length)
{
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

int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    using namespace fst;
    typedef kaldi::int32 int32;
    typedef kaldi::uint32 uint32;
    typedef kaldi::uint64 uint64;
    typedef KwsLexicographicArc Arc;
    typedef Arc::Weight Weight;
    typedef Arc::StateId StateId;

    const char *usage =
        "Search the keywords over the index. This program can be executed parallely, either\n"
        "on the index side or the keywords side; we use a script to combine the final search\n"
        "results. Note that the index archive has a only key \"global\".\n"
        "The output file is in the format:\n"
        "kw utterance_id beg_frame end_frame negated_log_probs\n"
        " e.g.: KW1 1 23 67 0.6074219\n"
        "\n"
        "Usage: kws-search [options] index-dir index-id\n"
        " e.g.: kws-search /path/to/indices 1\n";

    ParseOptions po(usage);

    int32 n_best = -1;
    int32 keyword_nbest = -1;
    double negative_tolerance = -0.1;
    double keyword_beam = -1;
    
    po.Register("nbest", &n_best, "Return the best n hypotheses.");
    po.Register("keyword-nbest", &keyword_nbest,
                "Pick the best n keywords if the FST contains multiple keywords.");
    po.Register("negative-tolerance", &negative_tolerance, 
                "The program will print a warning if we get negative score smaller "
                "than this tolerance.");
    po.Register("keyword-beam", &keyword_beam,
                "Prune the FST with the given beam if the FST contains multiple keywords.");

    if (n_best < 0 && n_best != -1) {
      KALDI_ERR << "Bad number for nbest";
      exit (1);
    }
    if (keyword_nbest < 0 && keyword_nbest != -1) {
      KALDI_ERR << "Bad number for keyword-nbest";
      exit (1);
    }
    if (keyword_beam < 0 && keyword_beam != -1) {
      KALDI_ERR << "Bad number for keyword-beam";
      exit (1);
    }

    po.Read(argc, argv);

    if (po.NumArgs() < 2 || po.NumArgs() > 2) {
      po.PrintUsage();
      exit(1);
    }

    //std::string utter_id_path = po.GetArg(1);
    std::string index_path = po.GetArg(1);
    int index_id = atoi(po.GetArg(2).c_str());
    int port = 6000 + index_id;

    std::ostringstream index_rspecifier;
    index_rspecifier << "ark:gzip -cdf " << index_path << "/index." << index_id << ".gz|";
    printf("Index: %s\n", index_rspecifier.str().c_str());
    RandomAccessTableReader< VectorFstTplHolder<KwsLexicographicArc> > index_reader(index_rspecifier.str());

    // Index has key "global"
    KwsLexicographicFst index = index_reader.Value("global");
    
    // First we have to remove the disambiguation symbols. But rather than
    // removing them totally, we actually move them from input side to output
    // side, making the output symbol a "combined" symbol of the disambiguation
    // symbols and the utterance id's.
    // Note that in Dogan and Murat's original paper, they simply remove the
    // disambiguation symbol on the input symbol side, which will not allow us
    // to do epsilon removal after composition with the keyword FST. They have
    // to traverse the resulting FST.
    int32 label_count = 1;
    unordered_map<uint64, uint32> label_encoder;
    unordered_map<uint32, uint64> label_decoder;
    for (StateIterator<KwsLexicographicFst> siter(index); !siter.Done(); siter.Next()) {
      StateId state_id = siter.Value();
      for (MutableArcIterator<KwsLexicographicFst> 
           aiter(&index, state_id); !aiter.Done(); aiter.Next()) {
        Arc arc = aiter.Value();
        // Skip the non-final arcs
        if (index.Final(arc.nextstate) == Weight::Zero())
          continue;
        // Encode the input and output label of the final arc, and this is the
        // new output label for this arc; set the input label to <epsilon>
        uint64 osymbol = EncodeLabel(arc.ilabel, arc.olabel);
        arc.ilabel = 0;
        if (label_encoder.find(osymbol) == label_encoder.end()) {
          arc.olabel = label_count;
          label_encoder[osymbol] = label_count;
          label_decoder[label_count] = osymbol;
          label_count++;
        } else { 
          arc.olabel = label_encoder[osymbol];
        }
        aiter.SetValue(arc);
      }
    }
    ArcSort(&index, fst::ILabelCompare<KwsLexicographicArc>());
    
    // Creating socket...
    int    listenfd, connfd;
    struct sockaddr_in     servaddr;
    char    buff[MAXLINE];
    int     n;

    if( (listenfd = socket(AF_INET, SOCK_STREAM, 0)) == -1 ){
      printf("create socket error: %s(errno: %d)\n",strerror(errno),errno);
      exit(0);
    }

    memset(&servaddr, 0, sizeof(servaddr));
    servaddr.sin_family = AF_INET;
    servaddr.sin_addr.s_addr = htonl(INADDR_ANY);
    servaddr.sin_port = htons(port);

    if( ::bind(listenfd, (struct sockaddr*)&servaddr, sizeof(servaddr)) == -1){
      printf("bind socket error: %s(errno: %d)\n",strerror(errno),errno);
      exit(0);
    }

    if( listen(listenfd, 10) == -1){
      printf("listen socket error: %s(errno: %d)\n",strerror(errno),errno);
      exit(0);
    }
    printf("Service started, port %d\n", port);
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
        n = recv(connfd, buff, MAXLINE, 0);
        buff[n] = '\0';
        printf("Receiving keyword: %s\n", buff);
        struct timeval tpstart, tpend;
        gettimeofday(&tpstart, NULL);
        int32 n_done = 0;
        int32 n_fail = 0;
        std::ostringstream keyword_rspecifier;
        keyword_rspecifier << "ark:" << buff << ".fsts";
        printf("Keyword: %s\n", keyword_rspecifier.str().c_str());
        SequentialTableReader<VectorFstHolder> keyword_reader(keyword_rspecifier.str());
        std::ostringstream osres;
        /*
        std::ostringstream result_wspecifier;
        result_wspecifier << "ark,t:|int2sym.pl -f 2 " << utter_id_path;//<< " > " << buff << "/result." << index_id;
        printf("Result: %s\n", result_wspecifier.str().c_str());
        TableWriter< BasicVectorHolder<double> > result_writer(result_wspecifier.str()); */
        for (; !keyword_reader.Done(); keyword_reader.Next()) {
          std::string key = keyword_reader.Key();
          VectorFst<StdArc> keyword = keyword_reader.Value();
          keyword_reader.FreeCurrent();

          // Process the case where we have confusion for keywords
          if (keyword_beam != -1) {
            Prune(&keyword, keyword_beam);
          }
          if (keyword_nbest != -1) {
            VectorFst<StdArc> tmp;
            ShortestPath(keyword, &tmp, keyword_nbest, true, true);
            keyword = tmp;
          }

          KwsLexicographicFst keyword_fst;
          KwsLexicographicFst result_fst;
          Map(keyword, &keyword_fst, VectorFstToKwsLexicographicFstMapper());
          Compose(keyword_fst, index, &result_fst);
          Project(&result_fst, PROJECT_OUTPUT);
          Minimize(&result_fst);
          ShortestPath(result_fst, &result_fst, n_best);
          RmEpsilon(&result_fst);

          // No result found
          if (result_fst.Start() == kNoStateId)
            continue;

          // Got something here
          double score;
          int32 tbeg, tend, uid;
          for (ArcIterator<KwsLexicographicFst> 
               aiter(result_fst, result_fst.Start()); !aiter.Done(); aiter.Next()) {
            const Arc &arc = aiter.Value();

            // We're expecting a two-state FST
            if (result_fst.Final(arc.nextstate) != Weight::One()) {
              KALDI_WARN << "The resulting FST does not have the expected structure for key " << key;
              n_fail++;
              continue;
            }

            uint64 osymbol = label_decoder[arc.olabel];
            uid = (int32)DecodeLabelUid(osymbol);
            tbeg = arc.weight.Value2().Value1().Value();
            tend = arc.weight.Value2().Value2().Value();
            score = arc.weight.Value1().Value();

            if (score < 0) {
              if (score < negative_tolerance) {
                KALDI_WARN << "Score out of expected range: " << score;
              }
              score = 0.0;
            }
            /* 
            vector<double> result;
            result.push_back(uid);
            result.push_back(tbeg);
            result.push_back(tend);
            result.push_back(score);
            result_writer.Write(key, result); */
            osres << key << " " << uid << " " << tbeg << " " << tend << " " << score << std::endl;
          }

          n_done++;
        }
        //result_writer.Flush();
        /*
        if (send(connfd, "o", 1, 0) < 0) {
          printf("WARNING: send status msg failed: %s(errno: %d)\n", strerror(errno), errno);
        } */
        if (!send_all(connfd, osres.str().c_str(), osres.str().length())) {
          printf("WARNING: send data failed\n");
        }
        KALDI_LOG << "Done " << n_done << " keywords";
        gettimeofday(&tpend, NULL);
        printf("Time elapsed: %f\n", tpend.tv_sec - tpstart.tv_sec + (double)(tpend.tv_usec - tpstart.tv_usec) / 1000000);
        leave = true;
      } else {
        //int status;
        //waitpid(pid, &status, 0);
      }
      close(connfd);
    }
    //close(listenfd);

  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
