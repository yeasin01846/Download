#!/bin/bash
set -e

PORT=8080
WEBROOT=/opt/superdown/download
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
<title>Pro Smart Video/Photo Downloader</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link href="https://fonts.googleapis.com/css?family=Inter:400,600&display=swap" rel="stylesheet">
<style>
body { background: #181a1b; color: #f3f3f3; font-family: 'Inter', Arial, sans-serif; display:flex; justify-content:center; align-items:center; min-height:100vh; margin:0; }
#container { background: #23272f; padding:38px 24px 28px 24px; border-radius: 17px; min-width:340px; box-shadow:0 4px 32px #0008; text-align:center; width:100%; max-width:620px;}
h2 { color:#00e187; margin-bottom:16px; font-weight:700;}
input[type=text] { width: 93%; padding: 13px; border-radius: 7px; border: none; margin-bottom:20px; font-size:19px;}
button { background:#00e187; color:#fff; border:none; padding:11px 30px; border-radius:8px; font-size:16px; cursor:pointer; margin:3px 0; font-weight:600;}
button:disabled { background: #444; cursor:wait;}
#progress { margin:20px 0 13px 0; min-height:22px; font-size:17px;}
.media-list { text-align:left; margin: 0 auto; max-width:570px;}
.media-item { background:#21242b; border-radius:11px; padding:15px 7px 11px 7px; margin-bottom:13px; }
.media-header {display:flex;align-items:center;}
.media-thumb { flex:0 0 112px; }
.media-thumb img, .media-thumb video { width:102px; height:62px; object-fit:cover; border-radius:8px; border:1px solid #272727;}
.media-info { flex:1; padding-left:14px;}
.media-type { font-size:13px; color:#ffe76c; padding:0 0 3px 0;}
.format-table { width:100%; border-collapse:collapse; margin-top:7px;}
.format-table th, .format-table td { padding:4px 8px; font-size:14px; text-align:left;}
.format-table th { background:#222; color:#9fffa6;}
.format-table tr:nth-child(even){background:#252730;}
.format-table td {color:#c7ffdc;}
.format-dl-btn{margin-left:7px;}
@media (max-width:640px) { #container{padding:12px 3px;min-width:0;max-width:99vw;} input[type=text]{font-size:15px;} .media-list{max-width:98vw;} }
</style>
</head>
<body>
<div id="container">
    <h2>🦾 Super Smart Downloader</h2>
    <input id="url" type="text" placeholder="Paste any video/photo link (not YouTube)">
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
            data.items.forEach(function(m,i) {
                html += '<div class="media-item">';
                html += '<div class="media-header" style="display:flex;align-items:center;">';
                html += '<div class="media-thumb">';
                if(m.thumb){
                    html += '<img src="'+m.thumb+'" />';
                } else if(m.type==='video' && m.formats && m.formats.length>0){
                    html += '<video src="'+m.formats[0].url+'" controls preload="none"></video>';
                } else if(m.type==='photo'){
                    html += '<img src="'+m.url+'" />';
                }
                html += '</div>';
                html += '<div class="media-info">';
                html += '<div class="media-type">'+(m.type==='video'?'[VIDEO]':'[PHOTO]')+'</div>';
                html += '<div style="font-size:13px;word-break:break-all">'+(m.title?m.title:'')+'</div>';
                html += '</div></div>';
                if(m.type==='video' && m.formats && m.formats.length>0){
                    html += '<table class="format-table"><tr><th>Format</th><th>Res</th><th>Size</th><th>Codec</th><th></th></tr>';
                    m.formats.forEach(function(fmt){
                        html += '<tr>';
                        html += '<td>'+fmt.ext.toUpperCase()+'</td>';
                        html += '<td>'+fmt.res+'</td>';
                        html += '<td>'+fmt.size+'</td>';
                        html += '<td>'+(fmt.vcodec||'')+'</td>';
                        html += '<td><a href="download.php?u='+encodeURIComponent(fmt.url)+'" download><button class="format-dl-btn">Download</button></a></td>';
                        html += '</tr>';
                    });
                    html += '</table>';
                } else if(m.type==='photo'){
                    html += '<div style="margin-top:7px;"><a href="download.php?u='+encodeURIComponent(m.url)+'" download><button>Download Photo</button></a></div>';
                }
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
function fsize($bytes){
    if(!$bytes||$bytes<1) return "-";
    $sz = ['B','KB','MB','GB','TB'];
    $f = floor(log($bytes,1024));
    return round($bytes/pow(1024,$f),($f>1)?2:0).$sz[$f];
}
if($_SERVER['REQUEST_METHOD']=='POST') {
    $url = trim($_POST['url'] ?? '');
    if(!$url || preg_match('#youtube\.com|youtu\.be#i',$url)) {
        echo json_encode(['status'=>'err', 'msg'=>'Sorry! YouTube is not supported.']);
        exit;
    }
    $items = [];
    $cmd = "yt-dlp --no-playlist --dump-json ".escapeshellarg($url)." 2>/dev/null";
    exec($cmd, $out, $ret);
    $json = is_array($out) ? implode("\n", $out) : $out;
    $data = @json_decode($json,true);

    if($data && (isset($data['formats']) || isset($data['thumbnails']))) {
        // For Video: list all formats (resolution, size, ext, codec)
        if(isset($data['formats']) && is_array($data['formats'])){
            $fmtarr = [];
            foreach($data['formats'] as $fmt){
                if(!isset($fmt['url'])) continue;
                $ext = $fmt['ext'] ?? 'mp4';
                $size = (isset($fmt['filesize'])&&$fmt['filesize']) ? fsize($fmt['filesize']) : ((isset($fmt['filesize_approx'])&&$fmt['filesize_approx'])?fsize($fmt['filesize_approx']):'-');
                $res = (isset($fmt['height'])?$fmt['height'].'p':'');
                $vcodec = $fmt['vcodec'] ?? '';
                $fmtarr[] = [
                    'url'=>$fmt['url'],
                    'ext'=>$ext,
                    'res'=>$res,
                    'size'=>$size,
                    'vcodec'=>$vcodec
                ];
            }
            // High-res first
            usort($fmtarr, function($a,$b){
                return intval($b['res']) - intval($a['res']);
            });
            $items[] = [
                'type'=>'video',
                'formats'=>$fmtarr,
                'thumb'=>isset($data['thumbnail'])?$data['thumbnail']:null,
                'title'=>$data['title']??null
            ];
        }
        // Thumbnails as photos
        if(isset($data['thumbnails']) && is_array($data['thumbnails'])){
            foreach($data['thumbnails'] as $t){
                if(isset($t['url'])){
                    $items[] = [
                        'type'=>'photo',
                        'url'=>$t['url']
                    ];
                }
            }
        }
    }
    // fallback for photo/video if yt-dlp fails (simple html dom parse)
    if(empty($items)){
        $html = @file_get_contents($url);
        if($html){
            // Try to get <img>
            if(preg_match_all('/<img[^>]+src=["\']([^"\'>]+)["\']/i', $html, $m)){
                foreach($m[1] as $img){
                    $imgurl = (stripos($img,'http')===0) ? $img : $url.$img;
                    $items[] = ['type'=>'photo','url'=>$imgurl];
                }
            }
            // Try to get <video>
            if(preg_match_all('/<video[^>]+src=["\']([^"\'>]+)["\']/i', $html, $m)){
                foreach($m[1] as $v){
                    $vidurl = (stripos($v,'http')===0) ? $v : $url.$v;
                    $items[] = ['type'=>'video','formats'=>[['url'=>$vidurl,'ext'=>'mp4','res'=>'-','size'=>'-','vcodec'=>'']] ];
                }
            }
        }
    }
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

sudo chown -R www-data:www-data $WEBROOT
sudo chmod 755 $WEBROOT
sudo chmod 644 $WEBROOT/*.php
sudo chmod 1777 /tmp

echo "▶ Creating custom nginx config for port $PORT..."
sudo tee /etc/nginx/sites-available/superdown8080 >/dev/null <<EOF
server {
    listen $PORT default_server;
    root /opt/superdown;
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

sudo ln -sf /etc/nginx/sites-available/superdown8080 /etc/nginx/sites-enabled/superdown8080

echo "▶ Enabling firewall for port $PORT..."
sudo ufw allow $PORT/tcp || sudo iptables -I INPUT -p tcp --dport $PORT -j ACCEPT

echo "▶ Restarting nginx/php-fpm..."
sudo systemctl restart php*-fpm
sudo systemctl restart nginx

echo
echo "✅ READY! Visit: http://$DOMAIN_OR_IP:8080/download"
