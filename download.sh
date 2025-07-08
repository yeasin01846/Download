#!/bin/bash

set -e

## 1. সিস্টেম আপডেট এবং দরকারি সফটওয়্যার
echo "[*] System updating..."
apt update && apt upgrade -y

echo "[*] Removing old node/npm/node_modules..."
apt remove -y nodejs libnode-dev npm || true
apt purge -y nodejs libnode-dev npm || true
apt autoremove -y
rm -rf /usr/include/node /usr/lib/node_modules /usr/bin/node /usr/bin/npm

echo "[*] Installing essentials (nginx, php, pip, ffmpeg, unzip, git, curl, wget)..."
apt install -y nginx php-fpm php-cli php-xml php-json php-mbstring php-curl python3 python3-pip ffmpeg git unzip curl wget

## 2. Node.js 20.x & npm ইনস্টল
echo "[*] Installing Node.js 20.x & npm..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs
npm install -g pm2

## 3. yt-dlp, gallery-dl, you-get
echo "[*] Installing yt-dlp, gallery-dl, you-get..."
pip3 install -U yt-dlp gallery-dl you-get

## 4. Download worker code
mkdir -p /opt/deepworker
cd /opt/deepworker

echo "[*] Writing deepworker.js..."
cat > deepworker.js <<'EOF'
const express = require("express");
const cors = require("cors");
const { exec } = require("child_process");

const app = express();
app.use(cors());
app.use(express.json());
const PORT = 5000;

// Helper: run a shell command and return output
function run(cmd) {
  return new Promise((resolve) => {
    exec(cmd, { maxBuffer: 1024 * 1024 * 30 }, (err, stdout, stderr) => {
      resolve({ stdout, stderr });
    });
  });
}

// API: yt-dlp, gallery-dl, you-get, manual
app.post("/api/extract", async (req, res) => {
  let { url, engine } = req.body;
  if (!url) return res.json({ error: "Missing url" });

  let cmd = "";
  if (engine === "yt-dlp") {
    cmd = `yt-dlp --dump-json --no-warnings "${url}"`;
  } else if (engine === "gallery-dl") {
    cmd = `gallery-dl --list-extractors && gallery-dl --list-extractors | grep -iq $(echo "${url}" | awk -F/ '{print $3}') && gallery-dl --json "${url}" || echo '{}'`;
  } else if (engine === "you-get") {
    cmd = `you-get --json "${url}"`;
  } else {
    // fallback/manual (try yt-dlp first)
    cmd = `yt-dlp --dump-json --no-warnings "${url}" || gallery-dl --json "${url}" || you-get --json "${url}"`;
  }
  let { stdout } = await run(cmd);

  // Try parse JSONs
  let out;
  try { out = JSON.parse(stdout.split("\n").filter(Boolean).pop() || "{}"); }
  catch { out = { raw: stdout }; }

  res.json(out);
});

app.listen(PORT, () => {
  console.log("Deepworker running on " + PORT);
});
EOF

echo "[*] Installing npm dependencies (puppeteer, express, cors)..."
npm install puppeteer express cors

echo "[*] Starting deepworker.js via pm2..."
pm2 start deepworker.js --name deepworker
pm2 save

## 5. Download frontend PHP
mkdir -p /opt/superdown/download
cd /opt/superdown/download

# Minimalistic index.php UI
cat > index.php <<'EOPHP'
<!DOCTYPE html>
<html lang="en"><head>
  <meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
  <title>⚡ Multi-Engine Video Downloader</title>
  <style>
    body {background:#181a20;color:#fff;font-family:sans-serif;margin:0;}
    .box{max-width:400px;margin:100px auto;padding:32px 24px;background:#23262f;border-radius:14px;box-shadow:0 2px 8px #0002;}
    input,button{font-size:16px;padding:8px 12px;border-radius:8px;border:none;}
    input{width:80%;margin-bottom:12px;}
    button{margin:4px 2px;cursor:pointer;background:#222;color:#f3f3f3;}
    .active{background:#06c167;}
    .item{margin:12px 0;padding:8px 10px;background:#16181f;border-radius:7px;}
    .thumb{height:48px;border-radius:6px;}
    .dlbtn{background:#08b; color:#fff; padding:4px 12px; border-radius:6px;}
  </style>
</head>
<body>
<div class="box">
  <h2>⚡ <span style="color:#06c167;">Multi-Engine Downloader</span></h2>
  <input id="url" type="text" placeholder="Paste video/photo page URL" />
  <br>
  <button id="yt-dlp" class="active">yt-dlp</button>
  <button id="gallery-dl">gallery-dl</button>
  <button id="you-get">you-get</button>
  <button id="manual">Manual</button>
  <div id="results"></div>
</div>
<script>
let engine = "yt-dlp";
for(const b of ["yt-dlp","gallery-dl","you-get","manual"]) {
  document.getElementById(b).onclick = ()=>{
    engine=b;
    for(const bb of ["yt-dlp","gallery-dl","you-get","manual"])
      document.getElementById(bb).classList.remove("active");
    document.getElementById(b).classList.add("active");
    if(document.getElementById("url").value) fetchResults();
  }
}
document.getElementById("url").addEventListener("keyup", e=>{
  if(e.key==="Enter") fetchResults();
});
function fetchResults() {
  let url = document.getElementById("url").value;
  if(!url) return;
  document.getElementById("results").innerHTML = "⏳ Processing...";
  fetch("/api/extract",{
    method:"POST",headers:{"Content-Type":"application/json"},
    body:JSON.stringify({url,engine})
  })
  .then(x=>x.json())
  .then(data=>{
    if(data.error) return document.getElementById("results").innerHTML="❌ "+data.error;
    if(data.formats||data.url||data.images||data.streams) {
      let out = "";
      if(data.formats) out += data.formats.map(f=>
        `<div class="item">${f.format||f.container||""} | ${f.width||""}x${f.height||""} | ${f.filesize?Math.round(f.filesize/1024/1024)+"MB":""} <a class="dlbtn" href="${f.url||f.fragment_base_url||f.path}" target="_blank">Download</a></div>`).join("");
      if(data.url) out += `<div class="item"> <a class="dlbtn" href="${data.url}" target="_blank">Download</a></div>`;
      if(data.images) out += data.images.map(img=> `<div class="item"><img src="${img.url||img}" class="thumb"><a class="dlbtn" href="${img.url||img}" target="_blank">Download</a></div>` ).join("");
      if(data.streams) out += data.streams.map(s=> `<div class="item">${s.quality||""} <a class="dlbtn" href="${s.url||s.src}" target="_blank">Download</a></div>`).join("");
      document.getElementById("results").innerHTML = out || "No video/photo found!";
    } else if(data.raw) {
      document.getElementById("results").innerHTML = "<pre>"+data.raw+"</pre>";
    } else {
      document.getElementById("results").innerHTML = "No video/photo found!";
    }
  })
  .catch(()=>document.getElementById("results").innerHTML="❌ Failed.");
}
</script>
</body></html>
EOPHP

echo "[*] Creating nginx config..."
cat > /etc/nginx/sites-available/superdown <<'ENGINX'
server {
    listen 80;
    server_name _;
    root /opt/superdown/download;
    index index.php index.html;

    location /download {
        alias /opt/superdown/download;
        index index.php index.html;
        try_files $uri $uri/ /download/index.php?$query_string;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:5000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
    }
}
ENGINX

ln -sf /etc/nginx/sites-available/superdown /etc/nginx/sites-enabled/superdown
rm -f /etc/nginx/sites-enabled/default

echo "[*] Restarting nginx/php-fpm..."
systemctl restart php8.1-fpm || systemctl restart php8.2-fpm || systemctl restart php7.4-fpm || true
systemctl restart nginx

## 6. Firewall allow
ufw allow 80/tcp || true
ufw allow 443/tcp || true
ufw allow 5000/tcp || true

echo ""
echo "=========================="
echo "🚀 INSTALLATION COMPLETE!"
echo "Visit: http://YOUR_SERVER_IP/download"
echo "Done!"
echo "=========================="
