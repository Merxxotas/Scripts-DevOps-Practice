---
layout: null
title: Scripts-DevOps-Practice
---

<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Scripts-DevOps-Practice — DevOps Automation Monorepo</title>
<style>
:root {
  --bg: #ffffff;
  --fg: #1f2328;
  --muted: #57606a;
  --card: #f6f8fa;
  --border: #d0d7de;
  --accent: #0969da;
  --accent-hover: #0550ae;
  --code-bg: #f6f8fa;
}
[data-theme="dark"] {
  --bg: #0d1117;
  --fg: #c9d1d9;
  --muted: #8b949e;
  --card: #161b22;
  --border: #30363d;
  --accent: #58a6ff;
  --accent-hover: #79c0ff;
  --code-bg: #161b22;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
  background: var(--bg);
  color: var(--fg);
  line-height: 1.6;
  transition: background 0.2s, color 0.2s;
}
.container { max-width: 1100px; margin: 0 auto; padding: 0 24px; }
header {
  padding: 48px 0 24px;
  border-bottom: 1px solid var(--border);
}
header .top {
  display: flex;
  justify-content: space-between;
  align-items: center;
  flex-wrap: wrap;
  gap: 12px;
}
h1 { font-size: 2.4rem; margin: 0 0 8px; }
.tagline { color: var(--muted); font-size: 1.15rem; margin: 0 0 16px; }
.badges img { height: 20px; margin-right: 6px; }
.btn {
  display: inline-block;
  padding: 10px 18px;
  border-radius: 6px;
  background: var(--accent);
  color: #fff;
  text-decoration: none;
  font-weight: 600;
  margin-right: 8px;
  margin-top: 8px;
}
.btn:hover { background: var(--accent-hover); }
.btn.secondary {
  background: transparent;
  color: var(--accent);
  border: 1px solid var(--border);
}
.toggle {
  background: var(--card);
  border: 1px solid var(--border);
  color: var(--fg);
  padding: 8px 12px;
  border-radius: 6px;
  cursor: pointer;
  font-size: 0.9rem;
}
section { padding: 40px 0; }
h2 { font-size: 1.6rem; margin: 0 0 16px; border-bottom: 1px solid var(--border); padding-bottom: 8px; }
table {
  width: 100%;
  border-collapse: collapse;
  margin: 16px 0;
}
th, td {
  padding: 10px 12px;
  border: 1px solid var(--border);
  text-align: left;
}
th { background: var(--card); }
tr:hover { background: var(--card); }
code, pre {
  font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
  background: var(--code-bg);
  border-radius: 6px;
}
pre { padding: 16px; overflow-x: auto; border: 1px solid var(--border); }
.features {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
  gap: 16px;
  margin: 16px 0;
}
.feature {
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 16px;
}
.feature h3 { margin: 0 0 6px; font-size: 1.05rem; }
.feature p { margin: 0; color: var(--muted); font-size: 0.95rem; }
.links { display: flex; flex-wrap: wrap; gap: 8px; margin: 16px 0; }
footer {
  border-top: 1px solid var(--border);
  padding: 24px 0;
  color: var(--muted);
  font-size: 0.9rem;
  text-align: center;
}
a { color: var(--accent); }
a:hover { color: var(--accent-hover); }
</style>
</head>
<body>
<div class="container">
  <header>
    <div class="top">
      <div>
        <h1>DevOps Automation Scripts & Daemons</h1>
        <p class="tagline">A multi-language DevOps automation monorepo: 11 self-contained modules (Bash, PowerShell, Python, Go) with specs, tests, CI and documentation.</p>
      </div>
      <button class="toggle" id="themeToggle" aria-label="Toggle dark mode">🌙 Dark</button>
    </div>
    <div class="badges">
      <a href="https://github.com/Merxxotas/Scripts-DevOps-Practice/actions"><img src="https://github.com/Merxxotas/Scripts-DevOps-Practice/actions/workflows/ci-disk-monitor.yml/badge.svg" alt="CI"></a>
      <a href="https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="MIT"></a>
      <a href="https://github.com/Merxxotas/Scripts-DevOps-Practice"><img src="https://img.shields.io/github/stars/Merxxotas/Scripts-DevOps-Practice?style=social" alt="Stars"></a>
    </div>
    <div>
      <a class="btn" href="https://github.com/Merxxotas/Scripts-DevOps-Practice">View on GitHub</a>
      <a class="btn secondary" href="https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki">Full Wiki</a>
      <a class="btn secondary" href="https://github.com/Merxxotas/Scripts-DevOps-Practice/actions">CI Pipelines</a>
    </div>
  </header>

  <section>
    <h2>Modules</h2>
    <table>
      <thead><tr><th>#</th><th>Module</th><th>Tech</th><th>Docs</th></tr></thead>
      <tbody>
        <tr><td>1</td><td>Disk Usage Monitoring with Email Alert</td><td>Bash / PowerShell</td><td><a href="https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki/13-Disk-Monitor-Overview">Wiki</a></td></tr>
        <tr><td>2</td><td>Log Cleanup (files older than X days)</td><td>Bash / PowerShell</td><td><a href="https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki/05-Log-Cleanup-Overview">Wiki</a></td></tr>
        <tr><td>3</td><td>Automated Database Backup with Timestamp</td><td>Bash / PowerShell</td><td><a href="https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki/16-Database-Backup-Overview">Wiki</a></td></tr>
        <tr><td>4</td><td>Service Monitor and Auto-Restart</td><td>Bash / PowerShell</td><td><a href="https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki/22-Service-Monitor-Overview">Wiki</a></td></tr>
        <tr><td>5</td><td>CPU and Memory Usage Monitor</td><td>Bash / PowerShell / Python / Docker</td><td><a href="https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki/10-CPU-Monitor-Overview">Wiki</a></td></tr>
        <tr><td>6</td><td>Website Availability (HTTP Health Check)</td><td>Bash / PowerShell</td><td><a href="https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki/31-Website-Availability-Overview">Wiki</a></td></tr>
        <tr><td>7</td><td>Find and Kill High-CPU Processes</td><td>Bash / PowerShell</td><td><a href="https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki/25-Kill-High-CPU-Overview">Wiki</a></td></tr>
        <tr><td>8</td><td>Log Rotation and Compression</td><td>Bash / PowerShell</td><td><a href="https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki/19-Log-Rotation-Overview">Wiki</a></td></tr>
        <tr><td>9</td><td>Automated Git Deployment</td><td>Bash / PowerShell</td><td><a href="https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki/28-Git-Deployment-Overview">Wiki</a></td></tr>
        <tr><td>10</td><td>Kubernetes Pod Monitor and Restart</td><td>Bash / PowerShell</td><td><a href="https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki/34-Kubernetes-Pod-Monitor-Overview">Wiki</a></td></tr>
        <tr><td>11</td><td>Scheduling and Automation (EventOps)</td><td>Python / Go</td><td><a href="https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki/02-EventOps-Overview">Wiki</a></td></tr>
      </tbody>
    </table>
  </section>

  <section>
    <h2>Why this monorepo</h2>
    <div class="features">
      <div class="feature"><h3>Self-contained modules</h3><p>Each module ships code, tests, spec, CI workflow and docs. No cross-module code dependencies.</p></div>
      <div class="feature"><h3>Parity across platforms</h3><p>Bash and PowerShell implement the same flags, defaults, exit codes and guardrails.</p></div>
      <div class="feature"><h3>Segregated CI</h3><p>One path-filtered workflow per module. Changing module 2 never triggers module 11's pipeline.</p></div>
      <div class="feature"><h3>Safety first</h3><p>Destructive actions ship guardrails, dry-run modes and non-zero exit codes on violations.</p></div>
      <div class="feature"><h3>English only</h3><p>All code, comments, identifiers and docs are in English.</p></div>
      <div class="feature"><h3>Production standard</h3><p>Spec to implementation to tests to CI to documentation to hands-on labs.</p></div>
    </div>
  </section>

  <section>
    <h2>Quick Start</h2>
    <pre><code>git clone https://github.com/Merxxotas/Scripts-DevOps-Practice.git
cd Scripts-DevOps-Practice/1-Disk-Usage-Monitoring-with-Email-Alert
chmod +x disk_monitor.sh
./disk_monitor.sh --help</code></pre>
  </section>

  <section>
    <h2>Links</h2>
    <div class="links">
      <a class="btn secondary" href="https://github.com/Merxxotas/Scripts-DevOps-Practice/wiki">Full Wiki</a>
      <a class="btn secondary" href="https://github.com/Merxxotas/Scripts-DevOps-Practice">Source Code</a>
      <a class="btn secondary" href="https://github.com/Merxxotas/Scripts-DevOps-Practice/actions">CI Pipelines</a>
      <a class="btn secondary" href="https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/CONTRIBUTING.md">Contributing</a>
      <a class="btn secondary" href="https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/SECURITY.md">Security</a>
      <a class="btn secondary" href="https://github.com/Merxxotas/Scripts-DevOps-Practice/blob/main/LICENSE">License (MIT)</a>
    </div>
  </section>

  <footer>
    Maintained by Brayan Marin Guirales &middot; Licensed under MIT
  </footer>
</div>
<script>
(function() {
  const root = document.documentElement;
  const btn = document.getElementById('themeToggle');
  const saved = localStorage.getItem('theme');
  const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
  let theme = saved || (prefersDark ? 'dark' : 'light');
  function apply(t) {
    root.setAttribute('data-theme', t);
    btn.textContent = t === 'dark' ? '☀️ Light' : '🌙 Dark';
    localStorage.setItem('theme', t);
  }
  apply(theme);
  btn.addEventListener('click', function() { apply(theme === 'dark' ? 'light' : 'dark'); theme = root.getAttribute('data-theme'); });
})();
</script>
</body>
</html>
