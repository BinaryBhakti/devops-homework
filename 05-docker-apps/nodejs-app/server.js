const express = require("express");
const os = require("os");

const app = express();
const PORT = process.env.PORT || 3000;

app.get("/", (req, res) => {
  res.send(`<!doctype html>
<html>
<head><meta charset="utf-8"><title>Node.js Hello World</title>
<style>
  body{font-family:system-ui,-apple-system,sans-serif;display:grid;place-items:center;
       min-height:100vh;margin:0;background:#1b1b1f;color:#f5f5f5}
  .card{background:#26262b;padding:3rem 4rem;border-radius:14px;text-align:center;
        border:1px solid #3a3a42}
  h1{margin:0 0 .5rem;font-size:2.5rem;color:#68a063}
  p{margin:.25rem 0;color:#a5a5b0}
  code{background:#15151a;padding:.15rem .45rem;border-radius:5px;color:#8fd18f}
</style></head>
<body><div class="card">
  <h1>Hello World</h1>
  <p>Node.js + Express running in Docker</p>
  <p>Node <code>${process.version}</code> &middot; container <code>${os.hostname()}</code></p>
</div></body></html>`);
});

app.get("/health", (req, res) => res.json({ status: "ok", app: "nodejs" }));

app.listen(PORT, "0.0.0.0", () =>
  console.log(`Node.js Hello World listening on port ${PORT}`)
);
