#!/bin/bash
set -e

PORT=8080
WEBROOT=/opt/smartdown/download
DOMAIN_OR_IP=$(curl -s ifconfig.me)

echo "▶ Installing dependencies..."
sudo apt update
sudo apt install -y nginx php-fpm php-cli php-xml php-json php-mbstring php-curl python3 python3-pip ffmpeg git unzip

echo "▶ Installing latest yt-dlp..."
sudo pip3 install -U yt-dlp

echo "▶ Creating web root $WEBROOT ..."
sudo mkdir -p $WEBROOT

echo "▶ Writing index.php ..."
sudo tee $WEBROOT/index.php >/dev/null <<'EOPHP'
<!DOCTYPE html>
<html>
<head>
<title>Smart Universal Video Downloader</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link href="https://fonts.googleapis.com/css?family=Inter:400,600&display=swap" rel="stylesheet">
<style>
body { background: #181a1b; color: #f3f3f3; font-family: 'Inter', Arial, sans-serif; display:flex; justify-content:center; align-items:center; min-height:100vh; margin:0; }
#container { background: #23272f; padding:38px 24px 28px 24px; border-radius: 17px; min-width:340px; box-shadow:0 4px 32px #0008; text-align:center; width:100%; max-width:540px;}
h2 { color:#00e187; margin-bottom:16px; font-weight:700;}
input[type=text] { width: 90%; padding: 13px; border-radius: 7px; border: none; margin-bottom:20px; font-size:19px;}
button { background:#00e187; color:#fff; border:none; padding:12px 32px; border-radius:8px; font-size:16px; cursor:pointer; margin:3px 0; font-weight:600;}
button:disabled { background: #444; cursor:wait;}
#progress { margin:20px 0 13px 0; min-height:22px; font-size:17px;}
.media-list { text-align:left; margin: 0 auto; max-width:480px;}
.media-item { background:#21242b; border-radius:11px; padding:16px 11px 11px 11px; margin-bottom:13px; display:flex; align-items:center; }
.media-thumb { flex:0 0 112px; }
.media-thumb img, .media-thumb video { width:102px; height:62px; object-fit:cover; border-radius:8px; border:1px solid #272727;}
.media-info { flex:1; padding-left:14px;}
.media-type { font-size:13px; color:#ffe76c; padding:0 0 3px 0;}
.media-dl { margin-left:10px;}
.dl-all { margin: 25px 0 10px 0;}
@media (max-width:550px) { #container{padding:12px 3px;min-width:0;max-width:99vw;} input[type=text]{font-size:15px;} .media-thumb img, .media-thumb video {width:60px;height:39px;} .media-item{padding:7px 2px 7px 2px;} }
</style>
</head>
<body>
<div id="container">
    <h2>🔗 Smart Universal Downloader</h2>
    <input id="url" type="text" placeholder="Paste any video/photo page link (not YouTube)">
    <br>
    <button id="go" onclick="startExtract()">Extract</button>
    <div id="progress"></div>
    <div class="dl-all" id="dlAll"></div>
    <div class="media-list" id="mediaList"></div>
    <footer style="font-size:12px;color:#6b6b6b;margin-top:28px;">&copy; <span id="y"></span> Pro Downloader &bull; Powered by yt-dlp+SmartScraper</footer>
</div>
<script>
document.getElementById('y').innerText = (new Date()).getFullYear();
let mediaData = [];
function startExtract() {
    let go = document.getElementById('go');
    go.disabled = true;
    go.innerText = 'Extracting...';
    document.getElementById('progress').innerText = 'Processing... Please wait ⏳';
    document.getElementById('mediaList').innerHTML = '';
    document.getElementById('dlAll').innerHTML = '';
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
            mediaData = data.items;
            document.getElementById('progress').innerText = 'Found '+data.items.length+' media:';
            let html = '';
            data.items.forEach(function(m,i) {
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
            if(data.items.length>1){
                document.getElementById('dlAll').innerHTML = '<button onclick="downloadAllZip()">⬇ Download All as ZIP</button>';
            }
        } else {
            document.getElementById('progress').innerText = data.msg || 'Error!';
        }
        go.disabled = false; go.innerText = 'Extract';
    }).catch(e=>{
        document.getElementById('progress').innerText = 'Network/Server Error!';
        go.disabled = false; go.innerText = 'Extract';
    });
}

function downloadAllZip() {
    if(mediaData.length<1) return;
    let links = mediaData.map(m=>m.url);
    window.location = 'downloadzip.php?urls='+encodeURIComponent(JSON.stringify(links));
}
</script>
</body>
</html>
EOPHP

echo "▶ Writing extract.php ..."
sudo tee $WEBROOT/extract.php >/dev/null <<'EOPHP'
<?php
// fallback smart scraper
function smart_extract($html, $base){
    $items = [];
    // Match <img src="">
    if(preg_match_all('/<img[^>]+src=["\']([^"\'>]+)["\']/i', $html, $m)){
        foreach($m[1] as $url){
            $f = parse_url($url, PHP_URL_PATH);
            $ext = strtolower(pathinfo($f, PATHINFO_EXTENSION) ?: 'jpg');
            $u = (stripos($url,'http')===0) ? $url : $base.$url;
            $items[] = ['url'=>$u, 'type'=>'photo', 'ext'=>$ext, 'res'=>''];
        }
    }
    // Match <video src="">
    if(preg_match_all('/<video[^>]+src=["\']([^"\'>]+)["\']/i', $html, $m)){
        foreach($m[1] as $url){
            $f = parse_url($url, PHP_URL_PATH);
            $ext = strtolower(pathinfo($f, PATHINFO_EXTENSION) ?: 'mp4');
            $u = (stripos($url,'http')===0) ? $url : $base.$url;
            $items[] = ['url'=>$u, 'type'=>'video', 'ext'=>$ext, 'res'=>''];
        }
    }
    // Match <source src="">
    if(preg_match_all('/<source[^>]+src=["\']([^"\'>]+)["\']/i', $html, $m)){
        foreach($m[1] as $url){
            $f = parse_url($url, PHP_URL_PATH);
            $ext = strtolower(pathinfo($f, PATHINFO_EXTENSION) ?: 'mp4');
            $u = (stripos($url,'http')===0) ? $url : $base.$url;
            $type = (in_array($ext,['jpg','jpeg','png','webp','gif']))?'photo':'video';
            $items[] = ['url'=>$u, 'type'=>$type, 'ext'=>$ext, 'res'=>''];
        }
    }
    // og:image/meta property
    if(preg_match_all('/property=[\'"]og:image[\'"][^>]*content=[\'"]([^\'"]+)[\'"]/i', $html, $m)){
        foreach($m[1] as $url){
            $items[] = ['url'=>$url, 'type'=>'photo', 'ext'=>'jpg', 'res'=>''];
        }
    }
    return $items;
}

if($_SERVER['REQUEST_METHOD']=='POST') {
    $url = trim($_POST['url'] ?? '');
    if(!$url || preg_match('#youtube\.com|youtu\.be#i',$url)) {
        echo json_encode(['status'=>'err', 'msg'=>'Sorry! YouTube is not supported.']);
        exit;
    }
    $yt = false; $items = [];
    // ১ম ধাপ: yt-dlp দিয়ে try
    $cmd = "yt-dlp --no-playlist --dump-json ".escapeshellarg($url)." 2>/dev/null";
    exec($cmd, $out, $ret);
    $json = is_array($out) ? implode("\n", $out) : $out;
    $data = @json_decode($json,true);

    if($data && (isset($data['formats']) || isset($data['thumbnails']))) {
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
    }
    // যদি yt-dlp না পারে fallback!
    if(empty($items)){
        $html = @file_get_contents($url);
        if($html){
            $parsed = parse_url($url);
            $base = $parsed['scheme'].'://'.$parsed['host'];
            $items = smart_extract($html, $base);
        }
    }
    // Remove duplicate URLs
    $u = [];
    $items = array_filter($items, function($item) use (&$u){
        if(in_array($item['url'], $u)) return false;
        $u[] = $item['url'];
        return true;
    });

    if(empty($items)) { echo json_encode(['status'=>'err','msg'=>'No video or photo found!']); exit; }
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

echo "▶ Writing downloadzip.php ..."
sudo tee $WEBROOT/downloadzip.php >/dev/null <<'EOPHP'
<?php
if(empty($_GET['urls'])) die("No files.");
$urls = json_decode($_GET['urls'], true);
if(!$urls || !is_array($urls)) die("Invalid.");
$zipfile = sys_get_temp_dir().'/dlz_'.uniqid().'.zip';
$zip = new ZipArchive();
if($zip->open($zipfile, ZipArchive::CREATE)!==TRUE) die("Zip failed.");
foreach($urls as $i=>$url){
    if(!filter_var($url, FILTER_VALIDATE_URL)) continue;
    $c = @file_get_contents($url);
    if($c){
        $ext = pathinfo(parse_url($url, PHP_URL_PATH), PATHINFO_EXTENSION) ?: 'media';
        $zip->addFromString('media_'.($i+1).'.'.$ext, $c);
    }
}
$zip->close();
header('Content-Type: application/zip');
header('Content-Disposition: attachment; filename="media.zip"');
header('Content-Length: '.filesize($zipfile));
readfile($zipfile);
@unlink($zipfile);
exit;
EOPHP

sudo chown -R www-data:www-data $WEBROOT
sudo chmod 755 $WEBROOT
sudo chmod 644 $WEBROOT/*.php
sudo chmod 1777 /tmp

echo "▶ Creating custom nginx config for port $PORT..."
sudo tee /etc/nginx/sites-available/smartdown8080 >/dev/null <<EOF
server {
    listen $PORT default_server;
    root /opt/smartdown;
    index index.php index.html;
    server_name _;

    location /download/ {
        alias $WEBROOT/;
        index index.php index.html;
        try_files \$uri \$uri/ =404;
    }
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')-fpm.sock;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/smartdown8080 /etc/nginx/sites-enabled/smartdown8080

echo "▶ Enabling firewall for port $PORT..."
sudo ufw allow $PORT/tcp || sudo iptables -I INPUT -p tcp --dport $PORT -j ACCEPT

echo "▶ Restarting nginx/php-fpm..."
sudo systemctl restart php*-fpm
sudo systemctl restart nginx

echo
echo "✅ READY! Visit: http://$DOMAIN_OR_IP:8080/download"
