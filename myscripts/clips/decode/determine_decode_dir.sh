# This script should not be called directly
# Check default beam settings in $decode, and determine whether we just make a symbolic link to the existing directory  or make a new one
# NOTE that this partial script may modify $decode

  if [ -z $beam_suffix ]; then
    echo 'ERROR: partial script determine_decode_dir.sh should not be called if $beam_suffix is empty.'
    exit 1
  fi
  decode_full=${decode}${beam_suffix}
  if [ -f ${decode}/.done ]; then # If decoding has been done with default beam settings
    default_beam=`get_beam $decode`
    default_lat_beam=`get_lat_beam $decode`
    if [ `echo "$default_beam != $conf_beam" | bc` -eq 1 ] || \
       [ `echo "$default_lat_beam != $conf_lat_beam" | bc` -eq 1 ]; then
      echo "*** WARNING: beam conf for $decode differs between conf file and existing decoding directory. *** "
      echo "*** beam ($conf_beam vs $default_beam), lattice_beam ($conf_lat_beam vs $default_lat_beam) ***"
      echo "*** beam settings in conf file won't be used ***"
    fi
  else
    default_beam=$conf_beam
    default_lat_beam=$conf_lat_beam
  fi
  if [ `echo "$extra_beam == $default_beam" | bc` -eq 1 ] && \
     [ `echo "$extra_lattice_beam == $default_lat_beam" | bc` -eq 1 ]; then
    ln -sf `basename $decode` $decode_full
    decode=$decode
  else
    decode=$decode_full
  fi
