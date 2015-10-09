function get_ive_types {
  nbest_set=$1
  lambda_set=$2
  type_set=
  for nbest in `echo "$nbest_set" | sed 's: \+:\n:g'`; do
    for lambda in `echo "$lambda_set" | sed 's: \+:\n:g'`; do
      ive_type=ive-$id-${model4cm}-${nbest}-${iv_phone_cutoff}-${lambda}
      if $use_total_weight; then 
        ive_type=${ive_type}-t
      fi
      if $self_prior; then 
        ive_type=${ive_type}-sp
      fi
      if $lm_in_expansion; then
        ive_type=${ive_type}-lm
        if [ ! -z $proxy_nbest0 ] && [ $proxy_nbest0 != '-1' ]; then
          ive_type=${ive_type}-${proxy_nbest0}
        fi
      fi
      type_set="$type_set $ive_type"
    done
  done
  echo "$type_set"
}

function get_beam {
  dcddir=$1
  line=`sed -n '3p' $(ls $dcddir/log/decode* | head -n 1)`
  beam=`echo "$line" | grep -Po '(?<=\-\-beam=)[\d\.]+'`
  if [ -z $beam ]; then
    echo "ERROR: cannot extract beam settings in $dcddir"
    exit 1;
  fi
  echo "$beam"
}

function get_lat_beam {
  dcddir=$1
  line=`sed -n '3p' $(ls $dcddir/log/decode* | head -n 1)`
  lat_beam=`echo "$line" | grep -Po '(?<=\-\-lattice\-beam=)[\d\.]+'`
  if [ -z $lat_beam ]; then # to be compatible with old version
    lat_beam=`echo "$line" | grep -Po '(?<=\-\-lat\-beam=)[\d\.]+'`
  fi
  if [ -z $lat_beam ]; then
    echo "ERROR: cannot extract lattice_beam settings in $dcddir"
    exit 1;
  fi
  echo "$lat_beam"
}
