#!/bin/bash
set -e

PORT=8080
WEBROOT=/opt/multidown/download
NGCONF=multidown8080

# IP
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

# Index PHP
sudo tee $WEBROOT/index.php >/dev/null <<'EOPHP'
<html>
<head><title>Pro Downloader</title></head>
<body>
<input id="url" placeholder="Paste URL here" style="width:90%">
<button onclick="dl('yt-dlp')">Download Video</button>
<div id="results"></div>
<script>
function dl(engine){
fetch('extract.php',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'url='+encodeURIComponent(url.value)+'&engine='+engine})
.then(r=>r.json()).then(d=>{
results.innerHTML=d.items.map(i=>`<a href="download.php?u=${encodeURIComponent(i.url)}">DOWNLOAD ${i.type.toUpperCase()}</a>`).join('<br>')
})}
</script>
</body>
</html>
EOPHP

# extract.php
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

# Firewall
sudo ufw allow $PORT/tcp || true

# Restart Services
sudo systemctl restart nginx php*-fpm

# Done
echo "✅ Installation complete! Open: http://$DOMAIN_OR_IP:$PORT/download"
