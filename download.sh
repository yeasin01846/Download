#!/bin/bash
set -e

PORT=8080
NGCONF=multidown8080
WEBROOT=/opt/multidown/download
DOMAIN_OR_IP=$(curl -s ifconfig.me)

# --- Auto clean old nginx config & port usage ---
echo "▶ Cleaning up old nginx config for port $PORT..."
sudo rm -f /etc/nginx/sites-available/$NGCONF
sudo rm -f /etc/nginx/sites-enabled/$NGCONF
for f in /etc/nginx/sites-available/*; do
    if grep -q "listen $PORT" "$f"; then
        name=$(basename "$f")
        echo " -- Removing old $name (port $PORT) ..."
        sudo rm -f "/etc/nginx/sites-available/$name"
        sudo rm -f "/etc/nginx/sites-enabled/$name"
    fi
done
if sudo lsof -i :$PORT | grep LISTEN; then
    pid=$(sudo lsof -t -i :$PORT)
    echo " -- Killing process on port $PORT: $pid"
    sudo kill -9 $pid
fi
echo "▶ Old configs cleaned. Proceeding with new install ..."

echo "▶ Installing dependencies..."
sudo apt update
sudo apt install -y nginx php-fpm php-cli php-xml php-json php-mbstring php-curl python3 python3-pip ffmpeg git unzip
sudo pip3 install -U yt-dlp gallery-dl you-get

echo "▶ Creating web root $WEBROOT ..."
sudo mkdir -p $WEBROOT

echo "▶ Writing index.php ..."
sudo tee $WEBROOT/index.php >/dev/null <<'EOPHP'
<!DOCTYPE html>
<html>
<head>
<title>Multi-Engine Pro Downloader</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link href="https://fonts.googleapis.com/css?family=Inter:400,600&display=swap" rel="stylesheet">
<style>
body { background: #1a1b1f; color: #f3f3f3; font-family: 'Inter', Arial, sans-serif; display:flex; justify-content:center; align-items:center; min-height:100vh; margin:0; }
#container { background: #22252b; padding:34px 22px 22px 22px; border-radius: 17px; min-width:340px; box-shadow:0 4px 32px #0008; text-align:center; width:100%; max-width:640px;}
h2 { color:#00e187; margin-bottom:16px; font-weight:700;}
input[type=text] { width: 94%; padding: 13px; border-radius: 7px; border: none; margin-bottom:20px; font-size:19px;}
.engine-btn {display:inline-block; background:#222; color:#fff; font-weight:700; border:2px solid #00e187; border-radius:8px; margin:4px 6px 14px 6px; padding:13px 30px; cursor:pointer; font-size:18px; transition:.2s;}
.engine-btn:hover,.engine-btn.active{background:#00e187;color:#111;}
button:disabled { background: #444; cursor:wait;}
#progress { margin:18px 0 13px 0; min-height:22px; font-size:17px;}
.media-list { text-align:left; margin: 0 auto; max-width:580px;}
.media-item { background:#1d1f25; border-radius:11px; padding:13px 7px 11px 7px; margin-bottom:13px; }
.media-header {display:flex;align-items:center;}
.media-thumb img, .media-thumb video { width:102px; height:62px; object-fit:cover; border-radius:8px; border:1px solid #272727;}
.media-info { flex:1; padding-left:14px;}
.media-type { font-size:13px; color:#ffe76c; padding:0 0 3px 0;}
.format-table { width:100%; border-collapse:collapse; margin-top:7px;}
.format-table th, .format-table td { padding:4px 8px; font-size:14px; text-align:left;}
.format-table th { background:#222; color:#9fffa6;}
.format-table tr:nth-child(even){background:#252730;}
.format-table td {color:#c7ffdc;}
.format-dl-btn{margin-left:7px;}
@media (max-width:640px) { #container{padding:11px 1vw;min-width:0;max-width:99vw;} input[type=text]{font-size:15px;} .media-list{max-width:99vw;} }
</style>
</head>
<body>
<div id="container">
    <h2>⚡ Multi-Engine Downloader</h2>
    <input id="url" type="text" placeholder="Paste any video/photo link (not YouTube)">
    <br>
    <div id="engines" style="margin-top:5px; margin-bottom:13px;"></div>
    <div id="progress"></div>
    <div class="media-list" id="mediaList"></div>
</div>
<script>
let url = '';
const engines = [
    {id:'yt-dlp', name:'yt-dlp', desc:'Ultimate Video Engine'},
    {id:'gallery-dl', name:'gallery-dl', desc:'Album/Photo Pro'},
    {id:'you-get', name:'you-get', desc:'Simple Video Grabber'},
    {id:'manual', name:'Manual', desc:'HTML Scraper'}
];
window.onload = function(){
    let html = '';
    engines.forEach(e=>{
        html += '<span class="engine-btn" id="ebtn_'+e.id+'" onclick="extractEngine(\''+e.id+'\')">'+e.name+'</span>';
    });
    document.getElementById('engines').innerHTML = html;
};
function setActive(id){
    engines.forEach(e=>{
        let b = document.getElementById('ebtn_'+e.id);
        if(b) b.classList.remove('active');
    });
    let btn = document.getElementById('ebtn_'+id);
    if(btn) btn.classList.add('active');
}
function extractEngine(engine){
    setActive(engine);
    url = document.getElementById('url').value.trim();
    if(!url) {
        document.getElementById('progress').innerText = 'Please enter a URL.';
        return;
    }
    document.getElementById('progress').innerText = 'Processing with '+engine+'...';
    document.getElementById('mediaList').innerHTML = '';
    fetch('extract.php', {
        method: 'POST',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'url='+encodeURIComponent(url)+'&engine='+encodeURIComponent(engine)
    })
    .then(res => res.json())
    .then(data => {
        if(data.status=='ok') {
            document.getElementById('progress').innerText = 'Found '+data.items.length+' media:';
            let html = '';
            data.items.forEach(function(m,i) {
                html += '<div class="media-item">';
                html += '<div class="media-header" style="display:flex;align-items:center;">';
                if(m.thumb){
                    html += '<img src="'+m.thumb+'" />';
                } else if(m.type==='video' && m.formats && m.formats.length>0){
                    html += '<video src="'+m.formats[0].url+'" controls preload="none"></video>';
                } else if(m.type==='photo'){
                    html += '<img src="'+m.url+'" />';
                }
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
    }).catch(e=>{
        document.getElementById('progress').innerText = 'Network/Server Error!';
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

function parse_yt_dlp($data) {
    $items = [];
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
        usort($fmtarr, function($a,$b){ return intval($b['res']) - intval($a['res']); });
        $items[] = [
            'type'=>'video',
            'formats'=>$fmtarr,
            'thumb'=>isset($data['thumbnail'])?$data['thumbnail']:null,
            'title'=>$data['title']??null
        ];
    }
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
    return $items;
}

function parse_gallery_dl($data){
    $items = [];
    if(isset($data['files']) && is_array($data['files'])){
        foreach($data['files'] as $f){
            $items[] = [
                'type'=> (in_array(strtolower(pathinfo($f,PATHINFO_EXTENSION)),['jpg','jpeg','png','webp','gif'])) ? 'photo' : 'video',
                'url'=> $f
            ];
        }
    }
    return $items;
}

function parse_youget($data){
    $items = [];
    if(isset($data['streams']) && is_array($data['streams'])){
        foreach($data['streams'] as $sid=>$s){
            if(isset($s['src']) && is_array($s['src'])){
                foreach($s['src'] as $u){
                    $items[] = [
                        'type'=>'video',
                        'formats'=>[[
                            'url'=>$u,
                            'ext'=> $s['container'] ?? 'mp4',
                            'res'=> $s['quality']??'-',
                            'size'=> '-',
                            'vcodec'=> $sid
                        ]],
                        'thumb'=>null,
                        'title'=>null
                    ];
                }
            }
        }
    }
    if(isset($data['images']) && is_array($data['images'])){
        foreach($data['images'] as $img){
            $items[] = [
                'type'=>'photo',
                'url'=>$img
            ];
        }
    }
    return $items;
}

// fallback: manual html scraper
function parse_manual($url){
    $items = [];
    $html = @file_get_contents($url);
    if($html){
        if(preg_match_all('/<img[^>]+src=["\']([^"\'>]+)["\']/i', $html, $m)){
            foreach($m[1] as $img){
                $imgurl = (stripos($img,'http')===0) ? $img : $url.$img;
                $items[] = ['type'=>'photo','url'=>$imgurl];
            }
        }
        if(preg_match_all('/<video[^>]+src=["\']([^"\'>]+)["\']/i', $html, $m)){
            foreach($m[1] as $v){
                $vidurl = (stripos($v,'http')===0) ? $v : $url.$v;
                $items[] = ['type'=>'video','formats'=>[['url'=>$vidurl,'ext'=>'mp4','res'=>'-','size'=>'-','vcodec'=>'']] ];
            }
        }
    }
    return $items;
}

$url = trim($_POST['url'] ?? '');
$engine = trim($_POST['engine'] ?? 'yt-dlp');

if(!$url || preg_match('#youtube\.com|youtu\.be#i',$url)) {
    echo json_encode(['status'=>'err', 'msg'=>'Sorry! YouTube is not supported.']);
    exit;
}
$out = []; $data = null;

if($engine==='yt-dlp'){
    exec("yt-dlp --no-playlist --dump-json ".escapeshellarg($url)." 2>/dev/null", $out, $ret);
    $data = @json_decode(is_array($out)?implode("\n",$out):$out,true);
    $items = $data?parse_yt_dlp($data):[];
} else if($engine==='gallery-dl'){
    exec("gallery-dl -j ".escapeshellarg($url)." 2>/dev/null", $out, $ret);
    $data = @json_decode(is_array($out)?implode("\n",$out):$out,true);
    $items = $data?parse_gallery_dl($data):[];
} else if($engine==='you-get'){
    exec("you-get --json ".escapeshellarg($url)." 2>/dev/null", $out, $ret);
    $data = @json_decode(is_array($out)?implode("\n",$out):$out,true);
    $items = $data?parse_youget($data):[];
} else if($engine==='manual'){
    $items = parse_manual($url);
} else $items = [];

if(empty($items)) { echo json_encode(['status'=>'err','msg'=>'No video/photo found!']); exit; }
echo json_encode(['status'=>'ok','items'=>$items]);
exit;
?>
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
sudo tee /etc/nginx/sites-available/$NGCONF >/dev/null <<EOF
server {
    listen $PORT default_server;
    root /opt/multidown;
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

sudo ln -sf /etc/nginx/sites-available/$NGCONF /etc/nginx/sites-enabled/$NGCONF

echo "▶ Enabling firewall for port $PORT..."
sudo ufw allow $PORT/tcp || sudo iptables -I INPUT -p tcp --dport $PORT -j ACCEPT

echo "▶ Restarting nginx/php-fpm..."
sudo systemctl restart php*-fpm
sudo systemctl restart nginx

echo
echo "✅ READY! Visit: http://$DOMAIN_OR_IP:8080/download"
