const express = require('express');
const os = require('os');

const app = express();

const PORT = process.env.PORT || 3000;
const APP_VERSION = process.env.APP_VERSION || 'dev';
const BANNER_MESSAGE = process.env.BANNER_MESSAGE || 'Hello from Azure Arc!';

app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    version: APP_VERSION,
    timestamp: new Date().toISOString()
  });
});

app.get('/', (req, res) => {
  const hostname = os.hostname();
  res.send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Azure Arc Demo</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Segoe UI', system-ui, sans-serif;
      background: #f4f4f4;
      color: #333;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
    }
    .card {
      background: #fff;
      border-radius: 8px;
      box-shadow: 0 2px 16px rgba(0,0,0,0.10);
      padding: 48px 56px;
      max-width: 640px;
      width: 100%;
      text-align: center;
    }
    .banner {
      font-size: 2.4rem;
      font-weight: 700;
      color: #0078d4;
      margin-bottom: 24px;
      line-height: 1.2;
    }
    .meta {
      display: flex;
      flex-direction: column;
      gap: 10px;
      margin: 24px 0;
    }
    .meta-row {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 8px 12px;
      background: #f0f6ff;
      border-radius: 4px;
      font-size: 0.95rem;
    }
    .meta-label { color: #555; font-weight: 500; }
    .meta-value { color: #0078d4; font-family: monospace; font-size: 0.9rem; }
    .arc-note {
      margin-top: 28px;
      padding: 14px 20px;
      background: #e6f2ff;
      border-left: 4px solid #0078d4;
      border-radius: 4px;
      font-size: 0.95rem;
      color: #004578;
      text-align: left;
    }
    footer {
      margin-top: 40px;
      font-size: 0.8rem;
      color: #999;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="banner">${BANNER_MESSAGE}</div>
    <div class="meta">
      <div class="meta-row">
        <span class="meta-label">Version</span>
        <span class="meta-value">${APP_VERSION}</span>
      </div>
      <div class="meta-row">
        <span class="meta-label">Hostname</span>
        <span class="meta-value">${hostname}</span>
      </div>
    </div>
    <div class="arc-note">
      &#9989; Running on-premises via <strong>Azure Arc</strong> — managed from the cloud, deployed by Flux GitOps.
    </div>
  </div>
  <footer>Deployed via Azure Arc + Flux GitOps</footer>
</body>
</html>`);
});

app.listen(PORT, () => {
  console.log(`arc-demo-app v${APP_VERSION} listening on port ${PORT}`);
});
