<?php
function gettime() {
  list($usec, $sec) = explode(" ", microtime());
  return (float)$usec + (float)$sec;
}
$t1 = gettime();
setlocale(LC_CTYPE, "UTF8", "en_US.UTF-8");
if (!isset($_GET['kw']) || empty($_GET['kw'])) {
    # http_response_code(400); # only for PHP >= 5.4
    # header('X-PHP-Response-Code: 400', true, 400);
    header('HTTP/1.0 400 Bad Request');
    return;
}
$kw = EscapeShellArg($_GET['kw']);
if (!isset($_GET['limit']) || empty($_GET['limit'])) {
    $limit = -1;
} else {
    $limit = $_GET['limit'];
}
if (!isset($_GET['start']) || empty($_GET['start'])) {
    $start = 0;
} else {
    $start = $_GET['start'];
}
#header('Content-type: application/json');
header('Content-type: application/json');

$kwlist_xml = shell_exec("/bin/bash /home/kaldi/code/kaldi-trunk/egs/babel/bnbc/czpScripts/demo/search_online.v1.sh '$kw'");
//echo "ret=$ret\n";
//echo $kwlist_xml;
$t2 = gettime();
$xml = simplexml_load_string($kwlist_xml);
$t3 = gettime();
$json = array('kwslist' => array());
$curr = -1;
$count = 0;
foreach ($xml as $key => $detected_kwlist) {
    foreach ($detected_kwlist as $key2 => $kw) {
        $attr = $kw->attributes();
        if ($attr['decision'] == 'NO') {
            continue;
        }
        $curr++;
        if ($curr < $start) {
            continue;
        }
        if ($limit >= 0 && $count >= $limit) {
            goto END;
        }
        $url = preg_replace('/^BABEL_DIY_\d+_/', '', (string)$attr['file']);
        # For dev
        #$url = preg_replace('/\-[^\-_]+_\w+$/', '', $url);
        #$url = preg_replace('/-/', '_', $url); 
        #$url = "http://166.111.64.40/bnbc_audio/$url.wav";

        # For eval
        preg_match_all('/((\d{6})\d+)\-([^\-]+)\-([^_]+)_inLine/', $url, $m);
        $url = "http://166.111.64.40/video/".$m[3][0]."/".$m[2][0]."/".$m[1][0]."_".$m[4][0].".mp4";

        $item = Array('url' => $url,
                      'tbeg' => (float)$attr['tbeg'],
                      'dur' => (float)$attr['dur'],
                      'score' => (float)$attr['score']);
        $json['kwslist'][] = $item;
        $count++;
    }
}
END:
$t4 = gettime();
echo ($t2-$t1)." ".($t3-$t2)." ".($t4-$t3)."\n";
echo json_encode($json);
?>

