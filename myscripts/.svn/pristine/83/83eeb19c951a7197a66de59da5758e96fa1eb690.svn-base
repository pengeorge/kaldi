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
    $limit = EscapeShellArg($_GET['limit']);
}
if (!isset($_GET['start']) || empty($_GET['start'])) {
    $start = 0;
} else {
    $start = EscapeShellArg($_GET['start']);
}
function get_real_ip()
{
    $ip=false;
    if(!empty($_SERVER["HTTP_CLIENT_IP"]))
    {
        $ip = $_SERVER["HTTP_CLIENT_IP"];
    }
    if (!empty($_SERVER['HTTP_X_FORWARDED_FOR']))
    {
        $ips = explode (", ", $_SERVER['HTTP_X_FORWARDED_FOR']);
        if ($ip) { array_unshift($ips, $ip); $ip = FALSE; }
        for ($i = 0; $i < count($ips); $i++)
        {
            if (!eregi ("^(10|172\.16|192\.168)\.", $ips[$i]))
            {
                $ip = $ips[$i];
                break;
            }
        }
    }
    return ($ip ? $ip : $_SERVER['REMOTE_ADDR']);
}
$ip=get_real_ip();
//echo shell_exec("/bin/bash /home/kaldi/code/kaldi-trunk/egs/babel/bnbc/czpScripts/demo/search_online.sh --offset $start --limit $limit '$kw'");
exec("/bin/bash /home/kaldi/code/kaldi-trunk/egs/babel/bnbc/czpScripts/demo/search_online.sh --offset $start --limit $limit '$kw' $ip", $res_arr, $ret);
if ($ret != 0) {
    header("HTTP/1.0 500 Internal Server Error: $ret");
    return;
}
$output = join("\n", $res_arr);

#header('Content-type: application/json');
header('Content-type: application/json; charset=utf-8');
$t2 = gettime();
printf('{%s,"time":%.2f}', $output, $t2 - $t1);
/*
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
echo json_encode($json);*/
?>

