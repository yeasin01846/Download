#!/bin/bash
set -e

PORT=8080
WEBROOT=/opt/multidown/download
NGCONF=multidown8080
DOMAIN_OR_IP=$(curl -s ifconfig.me)

# Prepare VPS
sudo apt update
sudo apt install -y nginx php-fpm php-cli php-xml php-json php-mbstring php-curl python3 python3-pip ffmpeg git unzip
sudo pip3 install -U yt-dlp gallery-dl you-get

# Clean old config
sudo rm -rf /etc/nginx/sites-{available,enabled}/$NGCONF
sudo lsof -t -i :$PORT | xargs -r sudo kill -9

# Web directory
sudo mkdir -p $WEBROOT

# Original UI HTML + CSS
sudo tee $WEBROOT/index.php >/dev/null <<'EOPHP'
<!DOCTYPE html>
<html>
<head>
<title>Multi-Engine Pro Downloader</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link href="https://fonts.googleapis.com/css?family=Inter:400,600&display=swap" rel="stylesheet">
<style>
body { background: #1a1b1f; color: #f3f3f3; font-family: 'Inter', Arial, sans-serif; display:flex; justify-content:center; align-items:center; min-height:100vh; margin:0; }
#container { background: #22252b; padding:34px 22px; border-radius:17px; box-shadow:0 4px 32px #0008; text-align:center; width:100%; max-width:640px; }
input { width:90%; padding:10px; }
button { padding:10px; }
</style>
</head>
<body>
<div id="container">
  <h2>⚡ Multi-Engine Pro Downloader</h2>
  <input id="url" placeholder="Paste URL here"><br>
  <button onclick="dl('yt-dlp')">Download Video</button>
  <div id="results"></div>
</div>
<script>
function dl(engine){
  fetch('extract.php',{
    method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},
    body:'url='+encodeURIComponent(url.value)+'&engine='+engine
  }).then(r=>r.json()).then(d=>{
    results.innerHTML=d.items.map(i=>`<a href="download.php?u=${encodeURIComponent(i.url)}">DOWNLOAD ${i.type.toUpperCase()}</a>`).join('<br>')
  })}
</script>
</body>
</html>
EOPHP

# Updated Backend extract.php
sudo tee $WEBROOT/extract.php >/dev/null <<'EOPHP'
<?php
$url=$_POST['url'];
$cookies='/opt/multidown/cookies.txt';
$ua='Mozilla/5.0 (Windows NT 10.0; Win64; x64)';
exec("yt-dlp --cookies $cookies --user-agent '$ua' --no-playlist -J ".escapeshellarg($url),$o);
$data=json_decode(join('',$o),true);
$items=[];
if(!empty($data['formats'])){
  foreach($data['formats'] as $f){
    if(isset($f['url'])){
      $items[]=['type'=>'video','url'=>$f['url']];
      break;
    }
  }
}else if(isset($data['url'])){
  $items[]=['type'=>'video','url'=>$data['url']];
}
if(isset($data['thumbnails'][0]['url'])){
  $items[]=['type'=>'photo','url'=>$data['thumbnails'][0]['url']];
}
echo json_encode(['items'=>$items]);
EOPHP

# download.php
sudo tee $WEBROOT/download.php >/dev/null <<'EOPHP'
<?php
$url=$_GET['u'];
header('Content-Disposition: attachment; filename="downloaded.mp4"');
readfile($url);
EOPHP

# Permission
sudo chown -R www-data:www-data $WEBROOT

# Nginx Config
sudo tee /etc/nginx/sites-available/$NGCONF >/dev/null <<EOF
server {
    listen $PORT;
    root /opt/multidown;
    index index.php;

    location /download/ {
        alias $WEBROOT/;
        index index.php;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')-fpm.sock;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/$NGCONF /etc/nginx/sites-enabled/
sudo ufw allow $PORT/tcp || true
sudo systemctl restart nginx php*-fpm

echo "✅ Installation complete! Open: http://$DOMAIN_OR_IP:$PORT/download"
