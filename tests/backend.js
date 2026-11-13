// Faux service pour tester les vhosts : répond ce qu'il reçoit, accepte le WebSocket, diffuse une réponse lente.
// HTTP par défaut ; HTTPS (certificat auto-signé) si TLS_KEY et TLS_CERT sont définis, comme l'image d'Obsidian.
const http = require("http");
const https = require("https");
const fs = require("fs");
const crypto = require("crypto");

const PORT = Number(process.env.PORT);
const NAME = process.env.NAME;

function handler(req, res) {
  if (req.url.startsWith("/slow")) {
    // un premier morceau tout de suite, le second 2,5 s plus tard : révèle une éventuelle mise en mémoire tampon
    res.writeHead(200, { "content-type": "text/plain" });
    res.write("premier\n");
    setTimeout(() => { res.write("deuxieme\n"); res.end(); }, 2500);
    return;
  }
  let size = 0;
  req.on("data", (c) => { size += c.length; });
  req.on("end", () => {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ backend: NAME, secure: Boolean(req.socket.encrypted), method: req.method, url: req.url, bytes: size, headers: req.headers }));
  });
}

const server = process.env.TLS_CERT
  ? https.createServer({ key: fs.readFileSync(process.env.TLS_KEY), cert: fs.readFileSync(process.env.TLS_CERT) }, handler)
  : http.createServer(handler);

// Poignée de main WebSocket (RFC 6455) : répond 101 puis garde la connexion ouverte.
server.on("upgrade", (req, socket) => {
  const key = req.headers["sec-websocket-key"] || "";
  const accept = crypto.createHash("sha1").update(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest("base64");
  socket.write(
    "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + "\r\nX-Backend: " + NAME + "\r\n\r\n"
  );
  socket.on("data", () => {});
  socket.on("error", () => {});
});

server.listen(PORT, "0.0.0.0", () => console.log(`${NAME} sur ${PORT}`));
