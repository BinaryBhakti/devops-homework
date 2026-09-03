const express = require("express");
const os = require("os");

const app = express();
// The homework requires the application to be reachable on port 8080
const PORT = process.env.PORT || 8080;

app.get("/", (req, res) => {
  res.send(`<!doctype html>
<html>
<head><meta charset="utf-8"><title>Docker Multi-Stage Build</title>
<style>
  body{font-family:system-ui,-apple-system,sans-serif;display:grid;place-items:center;
       min-height:100vh;margin:0;background:#1b1b1f;color:#f5f5f5}
  .card{background:#26262b;padding:3rem 4rem;border-radius:14px;text-align:center;
        border:1px solid #3a3a42;max-width:640px}
  h1{margin:0 0 .75rem;font-size:2rem;color:#2496ed;line-height:1.3}
  p{margin:.3rem 0;color:#a5a5b0}
  code{background:#15151a;padding:.15rem .45rem;border-radius:5px;color:#7fd1ff}
</style></head>
<body><div class="card">
  <h1>Hello World from Docker multi-stage build</h1>
  <p>Stage 1 compiled the app with the full Node image.</p>
  <p>Stage 2 ships only the production dependencies.</p>
  <p>Node <code>${process.version}</code> &middot; container <code>${os.hostname()}</code>
     &middot; port <code>${PORT}</code></p>
</div></body></html>`);
});

app.get("/health", (req, res) =>
  res.json({ status: "ok", app: "multi-stage", port: PORT })
);

app.listen(PORT, "0.0.0.0", () =>
  console.log(`Server running on port ${PORT}`)
);
