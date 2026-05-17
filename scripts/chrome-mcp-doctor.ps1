# chrome-mcp-doctor.ps1
#
# Self-diagnose which Gotcha you're hitting. Probes:
#   - Ports 12306-12310 (bridge HTTP servers, one per profile in Approach B)
#   - Native Messaging host registration (HKCU)
#   - mcp-chrome-bridge global npm install
#   - Bridge MCP initialize handshake per port (returns 200 + session id when alive)
#
# Read-only. Modifies nothing.
#
# Usage:
#   pwsh -ExecutionPolicy Bypass -File chrome-mcp-doctor.ps1
#   # or
#   powershell -ExecutionPolicy Bypass -File chrome-mcp-doctor.ps1

$ErrorActionPreference = 'Continue'

Write-Output "=== chrome-mcp doctor ==="
Write-Output ""

# --- 1. npm global install ---
Write-Output "[1] mcp-chrome-bridge npm global install"
$bridgeRoot = "$(npm root -g 2>$null)\mcp-chrome-bridge"
if (Test-Path "$bridgeRoot\package.json") {
  $bridgePkg = Get-Content "$bridgeRoot\package.json" -Raw -Encoding UTF8 | ConvertFrom-Json
  $linkType = (Get-Item $bridgeRoot -Force).LinkType
  $linkTarget = (Get-Item $bridgeRoot -Force).Target
  Write-Output "    version: $($bridgePkg.version)"
  if ($linkType) {
    Write-Output "    install type: $linkType -> $linkTarget"
    Write-Output "    (looks like a junction-linked fork install - Gotcha #5 workaround)"
  } else {
    Write-Output "    install type: standard npm copy"
  }
} else {
  Write-Output "    NOT INSTALLED - run 'npm install -g mcp-chrome-bridge'"
}
Write-Output ""

# --- 2. Native Messaging host registration ---
Write-Output "[2] Native Messaging host (HKCU)"
$nmKey = "HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.chromemcp.nativehost"
if (Test-Path $nmKey) {
  $manifestPath = (Get-ItemProperty $nmKey -Name '(default)' -ErrorAction SilentlyContinue).'(default)'
  if ($manifestPath -and (Test-Path $manifestPath)) {
    Write-Output "    OK: manifest at $manifestPath"
  } else {
    Write-Output "    REGISTRY OK but manifest missing: $manifestPath"
  }
} else {
  Write-Output "    NOT REGISTERED - bridge postinstall failed. Run 'mcp-chrome-bridge register' manually."
}
Write-Output ""

# --- 3. Port listeners ---
Write-Output "[3] Bridge HTTP listeners (ports 12306-12310)"
$activePorts = @()
foreach ($p in 12306..12310) {
  $c = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
  if ($c) {
    Write-Output "    $p : LISTEN (PID $($c.OwningProcess))"
    $activePorts += $p
  } else {
    Write-Output "    $p : not listening"
  }
}
if ($activePorts.Count -eq 0) {
  Write-Output "    WARNING: no bridge listening. Open Chrome and click extension Connect."
}
Write-Output ""

# --- 4. MCP initialize handshake per active port ---
Write-Output "[4] MCP initialize probe (per active port)"
$body = @{
  jsonrpc = '2.0'
  id = 1
  method = 'initialize'
  params = @{
    protocolVersion = '2024-11-05'
    clientInfo = @{ name = 'chrome-mcp-doctor'; version = '1.0.0' }
    capabilities = @{}
  }
} | ConvertTo-Json -Depth 10 -Compress

foreach ($p in $activePorts) {
  try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:$p/mcp" -Method POST `
      -ContentType 'application/json' `
      -Headers @{ 'Accept' = 'application/json, text/event-stream' } `
      -Body $body -TimeoutSec 5 -ErrorAction Stop
    $sid = $r.Headers['mcp-session-id']
    Write-Output "    $p : OK (status=$($r.StatusCode) sessionId=$sid)"
  } catch {
    Write-Output "    $p : FAIL ($($_.Exception.Message))"
  }
}
Write-Output ""

# --- 5. Summary ---
Write-Output "=== Summary ==="
if ($activePorts.Count -eq 0) {
  Write-Output "  No bridge is reachable. Most likely:"
  Write-Output "    - Chrome not running, OR"
  Write-Output "    - Extension not Connected (click Connect on the extension popup)"
} elseif ($activePorts.Count -eq 1 -and $activePorts[0] -eq 12306) {
  Write-Output "  Single bridge on 12306. Standard install (Gotcha #6 not in play)."
  Write-Output "  If multi-session orphans (Gotcha #5), install the patched fork - see README."
} else {
  Write-Output "  Multi-port setup detected ($($activePorts.Count) bridges)."
  Write-Output "  Approach B is active. Make sure your client config (e.g. .claude.json)"
  Write-Output "  has matching chrome-mcp-* entries for each active port."
}
