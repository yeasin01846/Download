#!/bin/bash
set -e

WEBROOT=/var/www/html/download
DOMAIN_OR_IP=$(curl -s ifconfig.me)

echo "▶ Installing dependencies..."
sudo apt update
sudo apt install -y nginx php-fpm php-cli php-xml php-json php-mbstring php-curl python3 python3-pip ffmpeg git unzip

echo "▶ Installing yt-dlp..."
sudo pip3 install -U yt-dlp

echo "▶ Creating web root $WEBROOT ..."
sudo mkdir -p $WEBROOT

echo "▶ Writing index.php ..."
sudo tee $WEBROOT/index.php >/dev/null <<'EOPHP'
<!DOCTYPE html>
<html>
<head>
<title>Pro Media Extractor</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body { background: #181a1b; color: #f3f3f3; font-family: 'Segoe UI', Arial, sans-serif; display:flex; justify-content:center; align-items:center; min-height:100vh; margin:0; }
#container { background: #23272f; padding:38px 24px 28px 24px; border-radius: 17px; min-width:340px; box-shadow:0 4px 32px #0008; text-align:center; width:100%; max-width:480px;}
h2 { color:#00e187; margin-bottom:18px;}
input[type=text] { width: 92%; padding: 13px; border-radius: 7px; border: none; margin-bottom:20px; font-size:18px;}
button { background:#00e187; color:#fff; border:none; padding:12px 30px; border-radius:7px; font-size:16px; cursor:pointer; margin:3px 0;}
button:disabled { background: #444; cursor:wait;}
#progress { margin:20px 0 13px 0; min-height:22px; font-size:17px;}
.media-list { text-align:left; margin: 0 auto; max-width:420px;}
.media-item { background:#22252b; border-radius:9px; padding:14px 10px 10px 10px; margin-bottom:13px; display:flex; align-items:center; }
.media-thumb { flex:0 0 100px; }
.media-thumb img, .media-thumb video { width:90px; height:60px; object-fit:cover; border-radius:7px; border:1px solid #2c2c2c;}
.media-info { flex:1; padding-left:13px;}
.media-type { font-size:13px; color:#e8e860; padding:0 0 3px 0;}
.media-dl { margin-left:10px;}
@media (max-width:500px) { #container{padding:18px 4px;min-width:0;max-width:99vw;} input[type=text]{font-size:14px;} .media-thumb img, .media-thumb video {width:66px;height:44px;} .media-item{padding:7px 2px 7px 2px;} }
</style>
</head>
<body>
<div id="container">
    <h2>🔎 Pro Media Extractor</h2>
    <input id="url" type="text" placeholder="Paste any page/video link (not YouTube)">
    <br>
    <button id="go" onclick="startExtract()">Extract</button>
    <div id="progress"></div>
    <div class="media-list" id="mediaList"></div>
</div>
<script>
function startExtract() {
    let go = document.getElementById('go');
    go.disabled = true;
    go.innerText = 'Extracting...';
    document.getElementById('progress').innerText = 'Processing... Please wait ⏳';
    document.getElementById('mediaList').innerHTML = '';
    let url = document.getElementById('url').value.trim();
    if(!url) {
        document.getElementById('progress').innerText = 'Please enter a URL.';
        go.disabled = false; go.innerText = 'Extract'; return;
    }
    fetch('extract.php', {
        method: 'POST',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'url='+encodeURIComponent(url)
    })
    .then(res => res.json())
    .then(data => {
        if(data.status=='ok') {
            document.getElementById('progress').innerText = 'Found '+data.items.length+' media:';
            let html = '';
            data.items.forEach(function(m) {
                html += '<div class="media-item">';
                html += '<div class="media-thumb">';
                if(m.type==='video'){
                    html += '<video src="'+m.url+'" controls preload="none"></video>';
                } else {
                    html += '<img src="'+m.url+'" />';
                }
                html += '</div>';
                html += '<div class="media-info">';
                html += '<div class="media-type">'+(m.type==='video'?'[VIDEO]':'[PHOTO]')+'</div>';
                html += '<div style="font-size:13px;word-break:break-all">'+m.ext.toUpperCase()+' | '+(m.res||'')+'</div>';
                html += '</div>';
                html += '<div class="media-dl"><a href="download.php?u='+encodeURIComponent(m.url)+'" download><button>Download</button></a></div>';
                html += '</div>';
            });
            document.getElementById('mediaList').innerHTML = html;
        } else {
            document.getElementById('progress').innerText = data.msg || 'Error!';
        }
        go.disabled = false; go.innerText = 'Extract';
    }).catch(e=>{
        document.getElementById('progress').innerText = 'Network/Server Error!';
        go.disabled = false; go.innerText = 'Extract';
    });
}
</script>
</body>
</html>
EOPHP

echo "▶ Writing extract.php ..."
sudo tee $WEBROOT/extract.php >/dev/null <<'EOPHP'
<?php
if($_SERVER['REQUEST_METHOD']=='POST') {
    $url = trim($_POST['url'] ?? '');
    if(!$url || preg_match('#youtube\.com|youtu\.be#i',$url)) {
        echo json_encode(['status'=>'err', 'msg'=>'Sorry! YouTube is not supported.']);
        exit;
    }
    // yt-dlp json fetch
    $cmd = "yt-dlp --no-playlist --dump-json ".escapeshellarg($url)." 2>/dev/null";
    exec($cmd, $out, $ret);
    $json = is_array($out) ? implode("\n", $out) : $out;
    $data = @json_decode($json,true);
    if(!$data) { echo json_encode(['status'=>'err','msg'=>'Failed to extract media.']); exit; }

    $items = [];
    // ছবি (thumbnails)
    if(isset($data['thumbnails']) && is_array($data['thumbnails'])){
        foreach($data['thumbnails'] as $t){
            if(isset($t['url'])){
                $items[] = [
                    'url'=>$t['url'],
                    'type'=>'photo',
                    'ext'=>'jpg',
                    'res'=>isset($t['resolution'])?$t['resolution']:'',
                ];
            }
        }
    }
    // ভিডিও (formats)
    if(isset($data['formats']) && is_array($data['formats'])){
        foreach($data['formats'] as $fmt){
            if(!isset($fmt['url'])) continue;
            $ext = $fmt['ext'] ?? 'mp4';
            $type = ($ext=='jpg'||$ext=='png'||$ext=='webp') ? 'photo' : 'video';
            $items[] = [
                'url'=>$fmt['url'],
                'type'=>$type,
                'ext'=>$ext,
                'res'=>(isset($fmt['height'])?$fmt['height'].'p':''),
            ];
        }
    }
    // Remove duplicate URLs
    $u = [];
    $items = array_filter($items, function($item) use (&$u){
        if(in_array($item['url'], $u)) return false;
        $u[] = $item['url'];
        return true;
    });

    if(empty($items)) { echo json_encode(['status'=>'err','msg'=>'No photo or video found.']); exit; }
    echo json_encode(['status'=>'ok','items'=>$items]);
    exit;
} else {
    echo "Nothing here!";
}
EOPHP

echo "▶ Writing download.php ..."
sudo tee $WEBROOT/download.php >/dev/null <<'EOPHP'
<?php
$url = $_GET['u'] ?? '';
if(!$url || !filter_var($url, FILTER_VALIDATE_URL)) die("Invalid.");
$ext = pathinfo(parse_url($url, PHP_URL_PATH), PATHINFO_EXTENSION) ?: 'media';
header('Content-Type: application/octet-stream');
header('Content-Disposition: attachment; filename="downloaded.'.$ext.'"');
readfile($url);
exit;
EOPHP

sudo chown -R www-data:www-data $WEBROOT
sudo chmod 755 $WEBROOT
sudo chmod 644 $WEBROOT/*.php
sudo chmod 1777 /tmp

echo "▶ Restarting nginx/php-fpm..."
sudo systemctl restart php*-fpm
sudo systemctl restart nginx

echo
echo "✅ DONE! Visit: http://$DOMAIN_OR_IP/download"
