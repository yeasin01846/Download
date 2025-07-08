#!/bin/bash
set -e

# Customizable variables
DOWNLOADER_PORT=8081
WEBROOT=/opt/videodownloader
DOMAIN_OR_IP=$(curl -s ifconfig.me)

echo "▶ Installing dependencies (nginx, PHP, Python, yt-dlp, ffmpeg)..."
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
<title>Video Downloader</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body { background: #222; color: #f7f7f7; font-family: 'Segoe UI', Arial, sans-serif; display:flex; justify-content:center; align-items:center; height:100vh; margin:0; }
#container { background: #2a2a2a; padding: 40px 30px 30px 30px; border-radius: 18px; min-width:340px; box-shadow:0 4px 32px #0008; text-align:center; width:100%; max-width:410px;}
h2 { color:#00e187; margin-bottom:18px;}
input[type=text] { width: 90%; padding: 14px; border-radius: 7px; border: none; margin-bottom:18px; font-size:18px;}
button { background:#00e187; color:#fff; border:none; padding:14px 38px; border-radius:7px; font-size:17px; cursor:pointer; transition:0.2s; }
button:disabled { background: #444; cursor:wait;}
#progress { margin:24px 0 10px 0; min-height:22px; font-size:17px;}
#result { margin:14px 0;}
@media (max-width:480px) { #container{padding:25px 6px;min-width:0;max-width:95vw;} input[type=text]{font-size:15px;}}
</style>
</head>
<body>
<div id="container">
    <h2>⚡ Modern Video Downloader</h2>
    <input id="url" type="text" placeholder="Paste any non-YouTube video link">
    <br>
    <button id="go" onclick="startProcess()">Download</button>
    <div id="progress"></div>
    <div id="result"></div>
</div>
<script>
function startProcess() {
    let go = document.getElementById('go');
    go.disabled = true;
    go.innerText = 'Processing...';
    document.getElementById('progress').innerText = 'Processing... Please wait ⏳';
    document.getElementById('result').innerHTML = '';
    let url = document.getElementById('url').value.trim();
    if(!url) {
        document.getElementById('progress').innerText = 'Please enter a video link.';
        go.disabled = false; go.innerText = 'Download'; return;
    }
    fetch('process.php', {
        method: 'POST',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'url='+encodeURIComponent(url)
    })
    .then(res => res.json())
    .then(data => {
        if(data.status=='ok') {
            document.getElementById('progress').innerText = 'Ready! ✅';
            document.getElementById('result').innerHTML = '<a href="'+data.link+'" download><button style="background:#00bc8c;">⬇ Download Video</button></a>';
        } else {
            document.getElementById('progress').innerText = data.msg || 'Error!';
        }
        go.disabled = false; go.innerText = 'Download';
    }).catch(e=>{
        document.getElementById('progress').innerText = 'Network/Server Error!';
        go.disabled = false; go.innerText = 'Download';
    });
}
</script>
</body>
</html>
EOPHP

echo "▶ Writing process.php ..."
sudo tee $WEBROOT/process.php >/dev/null <<'EOPHP'
<?php
if($_SERVER['REQUEST_METHOD']=='POST') {
    $url = trim($_POST['url'] ?? '');
    if(!$url || preg_match('#youtube\.com|youtu\.be#i',$url)) {
        echo json_encode(['status'=>'err', 'msg'=>'Sorry! YouTube is not supported.']);
        exit;
    }
    $temp = sys_get_temp_dir();
    $file = $temp.'/vd_'.md5($url.time()).'.mp4';
    $cmd = 'yt-dlp --no-playlist --restrict-filenames -o "'.$file.'" -f "mp4" '.escapeshellarg($url).' 2>&1';
    exec($cmd, $out, $ret);
    if(file_exists($file) && filesize($file) > 100*1024) {
        $base = basename($file);
        $downloadUrl = "download.php?f=".urlencode($base);
        echo json_encode(['status'=>'ok','link'=>$downloadUrl]);
    } else {
        echo json_encode(['status'=>'err','msg'=>"Failed to process video.<br>".htmlspecialchars(implode("\n",$out))]);
    }
} else {
    echo "Nothing here!";
}
EOPHP

echo "▶ Writing download.php ..."
sudo tee $WEBROOT/download.php >/dev/null <<'EOPHP'
<?php
$f = basename($_GET['f'] ?? '');
$file = sys_get_temp_dir().'/'.$f;
if(!$f || !preg_match('/^vd_[a-z0-9]+\.mp4$/i',$f) || !file_exists($file)) {
    die("File not found.");
}
header('Content-Type: video/mp4');
header('Content-Disposition: attachment; filename="video.mp4"');
header('Content-Length: '.filesize($file));
readfile($file);
exit;
EOPHP

sudo chown -R www-data:www-data $WEBROOT
sudo chmod 755 $WEBROOT
sudo chmod 644 $WEBROOT/*.php

echo "▶ Creating Nginx site config (port $DOWNLOADER_PORT)..."
sudo tee /etc/nginx/sites-available/videodownloader >/dev/null <<EOF
server {
    listen $DOWNLOADER_PORT default_server;
    root $WEBROOT;
    index index.php index.html;
    server_name _;

    location / {
        try_files \$uri \$uri/ =404;
    }
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')-fpm.sock;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/videodownloader /etc/nginx/sites-enabled/videodownloader

# Prevent port conflict
if sudo ss -tulpn | grep ":$DOWNLOADER_PORT" ; then
    echo "Error: Port $DOWNLOADER_PORT already in use! Edit the script to change port."
    exit 1
fi

sudo nginx -t && sudo systemctl reload nginx
sudo chmod 1777 /tmp

echo
echo "✅ DONE! Access your Video Downloader at: http://$DOMAIN_OR_IP:$DOWNLOADER_PORT"
