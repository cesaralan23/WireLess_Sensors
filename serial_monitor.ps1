param(
  [string]$Port = 'COM5',
  [int]$Baud = 115200
)

$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, 'None', 8, 'One'
$sp.ReadTimeout = 500
try {
  $sp.Open()
  # breve pulso DTR/RTS para resetear ESP32 y arrancar logs
  $sp.DtrEnable = $true
  Start-Sleep -Milliseconds 50
  $sp.DtrEnable = $false
  $sp.RtsEnable = $true
  Start-Sleep -Milliseconds 50
  $sp.RtsEnable = $false
  Write-Host "[Serial] Abierto $Port a $Baud"
} catch {
  Write-Host "[Serial] ERROR: no se pudo abrir $Port - $($_.Exception.Message)"
  if ($sp -and $sp.IsOpen) { $sp.Close() }
  exit 1
}

try {
  while ($true) {
    try {
      $data = $sp.ReadExisting()
      if ($data.Length -gt 0) {
        Write-Host $data -NoNewline
      }
      Start-Sleep -Milliseconds 50
    } catch {
      Start-Sleep -Milliseconds 100
    }
  }
} finally {
  if ($sp.IsOpen) { $sp.Close() }
}