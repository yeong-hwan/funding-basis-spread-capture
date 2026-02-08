import http from 'http';
import fs from 'fs';
import path from 'path';
import { logger } from './logger';

interface MetricsSnapshot {
  timestamp: string;
  keeper: {
    uptime: number;
    cycleCount: number;
    lastCycleTime: string;
  };
  market: {
    ethFundingRate: number;
    ethMarkPrice: number;
    ethOraclePrice: number;
    annualizedApr: number;
  };
  vault: {
    state: string;
    spotValueUsd: number;
    deltaRatioBps: number;
  };
  wallet: {
    hyperEvmBalance: string;
    arbitrumBalance: string;
  };
}

class AdminServer {
  private port: number;
  private server: http.Server | null = null;
  private startTime: Date;
  private cycleCount: number = 0;
  private lastCycleTime: string = '';
  private metrics: Partial<MetricsSnapshot> = {};

  constructor(port: number = 3000) {
    this.port = port;
    this.startTime = new Date();
  }

  updateMetrics(data: Partial<MetricsSnapshot>): void {
    this.metrics = { ...this.metrics, ...data };
    this.cycleCount++;
    this.lastCycleTime = new Date().toISOString();
  }

  private getSnapshot(): MetricsSnapshot {
    const uptime = Math.floor((Date.now() - this.startTime.getTime()) / 1000);

    return {
      timestamp: new Date().toISOString(),
      keeper: {
        uptime,
        cycleCount: this.cycleCount,
        lastCycleTime: this.lastCycleTime,
      },
      market: this.metrics.market || {
        ethFundingRate: 0,
        ethMarkPrice: 0,
        ethOraclePrice: 0,
        annualizedApr: 0,
      },
      vault: this.metrics.vault || {
        state: 'UNKNOWN',
        spotValueUsd: 0,
        deltaRatioBps: 0,
      },
      wallet: this.metrics.wallet || {
        hyperEvmBalance: '0',
        arbitrumBalance: '0',
      },
    };
  }

  private handleRequest(req: http.IncomingMessage, res: http.ServerResponse): void {
    const url = req.url || '/';

    // CORS
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET');

    if (url === '/health') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'ok', timestamp: new Date().toISOString() }));
      return;
    }

    if (url === '/metrics') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(this.getSnapshot(), null, 2));
      return;
    }

    if (url === '/logs') {
      const logsDir = path.resolve(__dirname, '../logs');
      const date = new Date().toISOString().split('T')[0];
      const logFile = path.join(logsDir, `keeper-${date}.log`);

      if (fs.existsSync(logFile)) {
        const logs = fs.readFileSync(logFile, 'utf-8').split('\n').slice(-100).join('\n');
        res.writeHead(200, { 'Content-Type': 'text/plain' });
        res.end(logs);
      } else {
        res.writeHead(404);
        res.end('No logs found');
      }
      return;
    }

    if (url === '/' || url === '/dashboard') {
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.end(this.getDashboardHtml());
      return;
    }

    res.writeHead(404);
    res.end('Not Found');
  }

  private getDashboardHtml(): string {
    return `
<!DOCTYPE html>
<html>
<head>
  <title>Delta Neutral Keeper - Admin</title>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="30">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: 'SF Mono', Monaco, monospace;
      background: #0a0a0a;
      color: #e0e0e0;
      padding: 20px;
    }
    h1 { color: #00ff88; margin-bottom: 20px; }
    h2 { color: #00aaff; margin: 20px 0 10px; font-size: 14px; }
    .card {
      background: #1a1a1a;
      border: 1px solid #333;
      border-radius: 8px;
      padding: 15px;
      margin-bottom: 15px;
    }
    .metric {
      display: flex;
      justify-content: space-between;
      padding: 8px 0;
      border-bottom: 1px solid #222;
    }
    .metric:last-child { border-bottom: none; }
    .label { color: #888; }
    .value { color: #fff; font-weight: bold; }
    .value.positive { color: #00ff88; }
    .value.negative { color: #ff4444; }
    .status {
      display: inline-block;
      padding: 4px 8px;
      border-radius: 4px;
      font-size: 12px;
    }
    .status.ok { background: #00ff8833; color: #00ff88; }
    .status.warn { background: #ffaa0033; color: #ffaa00; }
    .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; }
    @media (max-width: 600px) { .grid { grid-template-columns: 1fr; } }
    .logs {
      background: #111;
      padding: 10px;
      border-radius: 4px;
      font-size: 11px;
      max-height: 200px;
      overflow-y: auto;
      white-space: pre-wrap;
    }
    .refresh { color: #666; font-size: 12px; margin-top: 20px; }
  </style>
</head>
<body>
  <h1>🏦 Delta Neutral Keeper</h1>

  <div class="grid">
    <div class="card">
      <h2>📊 MARKET DATA (ETH)</h2>
      <div id="market">Loading...</div>
    </div>

    <div class="card">
      <h2>🏛️ VAULT STATUS</h2>
      <div id="vault">Loading...</div>
    </div>
  </div>

  <div class="card">
    <h2>⚙️ KEEPER STATUS</h2>
    <div id="keeper">Loading...</div>
  </div>

  <div class="card">
    <h2>📝 RECENT LOGS</h2>
    <div id="logs" class="logs">Loading...</div>
  </div>

  <p class="refresh">Auto-refresh every 30 seconds | <a href="/metrics" style="color:#00aaff">JSON API</a></p>

  <script>
    async function fetchData() {
      try {
        const res = await fetch('/metrics');
        const data = await res.json();

        document.getElementById('market').innerHTML = \`
          <div class="metric"><span class="label">Funding Rate</span><span class="value positive">\${(data.market.ethFundingRate * 100).toFixed(4)}%</span></div>
          <div class="metric"><span class="label">Annualized APR</span><span class="value positive">\${data.market.annualizedApr.toFixed(1)}%</span></div>
          <div class="metric"><span class="label">Mark Price</span><span class="value">$\${data.market.ethMarkPrice.toFixed(2)}</span></div>
          <div class="metric"><span class="label">Oracle Price</span><span class="value">$\${data.market.ethOraclePrice.toFixed(2)}</span></div>
        \`;

        document.getElementById('vault').innerHTML = \`
          <div class="metric"><span class="label">State</span><span class="status ok">\${data.vault.state}</span></div>
          <div class="metric"><span class="label">Spot Value</span><span class="value">$\${data.vault.spotValueUsd.toLocaleString()}</span></div>
          <div class="metric"><span class="label">Delta Ratio</span><span class="value">\${(data.vault.deltaRatioBps / 100).toFixed(1)}%</span></div>
        \`;

        document.getElementById('keeper').innerHTML = \`
          <div class="metric"><span class="label">Uptime</span><span class="value">\${Math.floor(data.keeper.uptime / 60)}m \${data.keeper.uptime % 60}s</span></div>
          <div class="metric"><span class="label">Cycles</span><span class="value">\${data.keeper.cycleCount}</span></div>
          <div class="metric"><span class="label">Last Cycle</span><span class="value">\${data.keeper.lastCycleTime || 'N/A'}</span></div>
          <div class="metric"><span class="label">HyperEVM Balance</span><span class="value">\${data.wallet.hyperEvmBalance} HYPE</span></div>
          <div class="metric"><span class="label">Arbitrum Balance</span><span class="value">\${data.wallet.arbitrumBalance} ETH</span></div>
        \`;

        const logsRes = await fetch('/logs');
        const logs = await logsRes.text();
        document.getElementById('logs').textContent = logs;

      } catch (e) {
        console.error('Fetch error:', e);
      }
    }

    fetchData();
    setInterval(fetchData, 30000);
  </script>
</body>
</html>
    `;
  }

  start(): void {
    this.server = http.createServer((req, res) => this.handleRequest(req, res));
    this.server.listen(this.port, () => {
      logger.info('Admin', `Admin server started on http://localhost:${this.port}`);
    });
  }

  stop(): void {
    if (this.server) {
      this.server.close();
      logger.info('Admin', 'Admin server stopped');
    }
  }
}

export const adminServer = new AdminServer(3000);
