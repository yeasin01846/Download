#!/bin/bash
set -e

PORT=8080
NGCONF=multidown8080
WEBROOT=/opt/multidown/download
DOMAIN_OR_IP=$(curl -s ifconfig.me)

# Clean old configs
sudo rm -f /etc/nginx/sites-available/$NGCONF
sudo rm -f /etc/nginx/sites-enabled/$NGCONF
sudo lsof -t -i :$PORT | xargs -r sudo kill -9

# Dependencies
sudo apt update
sudo apt install -y nginx php-fpm php-cli php-xml php-json php-mbstring php-curl python3 python3-pip ffmpeg git unzip
sudo pip3 install -U yt-dlp gallery-dl you-get

# Create web root
sudo mkdir -p $WEBROOT

# index.php
sudo tee $WEBROOT/index.php >/dev/null <<'EOPHP'
<!DOCTYPE html>
<html>
<head>
<title>Advanced Multi Downloader</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
</head>
<body>
<form id="form">
  URL: <input type="text" id="url"><br>
  Engine:
  <select id="engine">
    <option value="yt-dlp">yt-dlp</option>
    <option value="gallery-dl">gallery-dl</option>
    <option value="you-get">you-get</option>
  </select><br>
  <button type="button" onclick="download()">Download</button>
</form>
<div id="result"></div>
<script>
function download() {
  fetch('extract.php', {
    method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded'},
    body:'url='+encodeURIComponent(url.value)+'&engine='+encodeURIComponent(engine.value)
  }).then(res=>res.json()).then(data=>{
    result.innerHTML = data.items.map(i=>
      `<div><a href="download.php?u=${encodeURIComponent(i.url)}">${i.type.toUpperCase()} - Download</a></div>`
    ).join('')
  })
}
</script>
</body>
</html>
EOPHP

# extract.php
sudo tee $WEBROOT/extract.php >/dev/null <<'EOPHP'
<?php
$url=$_POST['url'];
$engine=$_POST['engine'];
$cookies='/opt/multidown/cookies.txt';
$ua='Mozilla/5.0 (Windows NT 10.0; Win64; x64)';
$proxy=''; // set if needed e.g., 'http://proxy:port'

switch($engine){
  case 'yt-dlp':
    exec("yt-dlp --no-playlist --dump-json --cookies '$cookies' --user-agent '$ua' --proxy '$proxy' ".escapeshellarg($url),$o);
    $data=json_decode(join('',$o),true);
    $items=[['type'=>'video','url'=>$data['url']??$data['formats'][0]['url']]];
    break;
  case 'gallery-dl':
    exec("gallery-dl -j --cookies '$cookies' --user-agent '$ua' ".escapeshellarg($url),$o);
    $files=json_decode(join('',$o),true)['files']??[];
    $items=array_map(fn($f)=>['type'=>'photo','url'=>$f],$files);
    break;
  case 'you-get':
    exec("you-get --json ".escapeshellarg($url),$o);
    $streams=json_decode(join('',$o),true)['streams']??[];
    $items=[['type'=>'video','url'=>array_values($streams)[0]['src'][0]]];
    break;
}
echo json_encode(['items'=>$items]);
EOPHP

# download.php
sudo tee $WEBROOT/download.php >/dev/null <<'EOPHP'
<?php
$url=$_GET['u'];
header('Content-Disposition: attachment; filename="downloaded"');
readfile($url);
EOPHP

# Permissions
sudo chown -R www-data:www-data $WEBROOT

# Nginx
sudo tee /etc/nginx/sites-available/$NGCONF >/dev/null <<EOF
server {
    listen $PORT;
    root /opt/multidown;
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
sudo systemctl restart nginx php*-fpm

# UFW
sudo ufw allow $PORT/tcp || true

# Done
echo "Done! Visit: http://$DOMAIN_OR_IP:$PORT/download"
