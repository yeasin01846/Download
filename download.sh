#!/bin/bash
set -e

PORT=8080
NGCONF=multidown8080
WEBROOT=/opt/multidown/download
DOMAIN_OR_IP=$(curl -s ifconfig.me)

# Clean config and kill old process
sudo rm -f /etc/nginx/sites-available/$NGCONF
sudo rm -f /etc/nginx/sites-enabled/$NGCONF
sudo lsof -t -i :$PORT | xargs -r sudo kill -9

# Install dependencies
sudo apt update
sudo apt install -y nginx php-fpm php-cli php-xml php-json php-mbstring php-curl python3 python3-pip ffmpeg git unzip
sudo pip3 install -U yt-dlp gallery-dl you-get

# Setup webroot
sudo mkdir -p $WEBROOT

# index.php
sudo tee $WEBROOT/index.php >/dev/null <<'EOPHP'
<!DOCTYPE html>
<html>
<head><title>Pro Downloader</title><meta name="viewport" content="width=device-width, initial-scale=1">
<style>body{font-family:sans-serif;background:#121212;color:#eee;text-align:center;padding:30px}input,button{margin:10px;padding:10px;font-size:16px;width:90%}</style>
</head>
<body>
<h2>⚡ Multi-Engine Downloader</h2>
<input id="url" placeholder="Enter URL"><br>
<label><input type="checkbox" id="useCookies"> Use cookies.txt</label><br>
<input type="file" id="cookieFile" accept=".txt" /><br>
<select id="engine">
  <option value="yt-dlp">yt-dlp</option>
  <option value="gallery-dl">gallery-dl</option>
  <option value="you-get">you-get</option>
  <option value="manual">manual</option>
</select><br>
<button onclick="go()">Fetch Media</button>
<div id="result"></div>
<script>
function go(){
  const url=document.getElementById('url').value.trim();
  const engine=document.getElementById('engine').value;
  const useCookies=document.getElementById('useCookies').checked;
  const formData=new FormData();
  formData.append('url',url);
  formData.append('engine',engine);
  formData.append('use_cookies',useCookies);
  if(useCookies && document.getElementById('cookieFile').files.length>0){
    formData.append('cookie',document.getElementById('cookieFile').files[0]);
  }
  fetch('extract.php',{method:'POST',body:formData})
    .then(res=>res.json())
    .then(data=>{
      if(data.status==='ok'){
        result.innerHTML=data.items.map(m=>`<div><a href="download.php?u=${encodeURIComponent(m.url)}" target="_blank">${m.type.toUpperCase()} DOWNLOAD</a></div>`).join('');
      } else result.innerText=data.msg||'Error';
    });
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
$cookies_enabled=($_POST['use_cookies']==='true');
$tmp='/tmp/cookies.txt';
if($cookies_enabled && isset($_FILES['cookie'])){
  move_uploaded_file($_FILES['cookie']['tmp_name'],$tmp);
  $cookiearg="--cookies $tmp";
}else{
  $cookiearg='';
}
$ua='Mozilla/5.0 (Windows NT 10.0; Win64; x64)';
$out=[]; $data=null;

if($engine==='yt-dlp'){
  exec("yt-dlp $cookiearg --user-agent '$ua' --no-playlist -J ".escapeshellarg($url),$out);
  $data=json_decode(join("\n",$out),true);
  $items=[];
  foreach($data['formats']??[] as $f){
    if(isset($f['url'])){
      $items[]=['type'=>'video','url'=>$f['url']];
      break;
    }
  }
  if(isset($data['thumbnails'][0]['url'])){
    $items[]=['type'=>'photo','url'=>$data['thumbnails'][0]['url']];
  }
  echo json_encode(['status'=>'ok','items'=>$items]);
  exit;
}
elseif($engine==='gallery-dl'){
  exec("gallery-dl $cookiearg -j ".escapeshellarg($url),$out);
  $files=json_decode(join("\n",$out),true)['files']??[];
  $items=array_map(fn($f)=>['type'=>'photo','url'=>$f],$files);
  echo json_encode(['status'=>'ok','items'=>$items]); exit;
}
elseif($engine==='you-get'){
  exec("you-get --json ".escapeshellarg($url),$out);
  $streams=json_decode(join("\n",$out),true)['streams']??[];
  $items=[['type'=>'video','url'=>array_values($streams)[0]['src'][0]]];
  echo json_encode(['status'=>'ok','items'=>$items]); exit;
}
elseif($engine==='manual'){
  $html=@file_get_contents($url);
  preg_match_all('/<img[^>]+src=["\']([^"\']+)["\']/i',$html,$m);
  $items=array_map(fn($u)=>['type'=>'photo','url'=>$u],$m[1]);
  echo json_encode(['status'=>'ok','items'=>$items]); exit;
}
echo json_encode(['status'=>'err','msg'=>'Engine error']);
EOPHP

# download.php
sudo tee $WEBROOT/download.php >/dev/null <<'EOPHP'
<?php
$url=$_GET['u'];
if(!$url)die("Missing URL");
header('Content-Disposition: attachment; filename="downloaded.mp4"');
readfile($url);
EOPHP

# Permissions
sudo chown -R www-data:www-data $WEBROOT

# Nginx
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

echo "✅ Done! Open: http://$DOMAIN_OR_IP:$PORT/download"
