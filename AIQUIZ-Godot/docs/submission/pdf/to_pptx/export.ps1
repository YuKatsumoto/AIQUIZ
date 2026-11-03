param([string]$Pptx, [string]$OutDir = "", [string]$Pdf = "", [string]$SavePptx = "")
# Open the .pptx in PowerPoint. Optionally export every slide as a 1920x1080 PNG (visual QA),
# save the deck again through PowerPoint (-SavePptx), and save a PDF (-Pdf).
# A PowerPoint that was already running is left open.
$running = @(Get-Process -Name POWERPNT -ErrorAction SilentlyContinue).Count
$ppt = New-Object -ComObject PowerPoint.Application
$pres = $ppt.Presentations.Open($Pptx, 0, 0, 0)
$n = $pres.Slides.Count
if ($OutDir) {
  New-Item -ItemType Directory -Force $OutDir | Out-Null
  for ($i = 1; $i -le $n; $i++) {
    $pres.Slides.Item($i).Export((Join-Path $OutDir ("p{0:D2}.png" -f $i)), "PNG", 1920, 1080)
  }
}
if ($SavePptx) { $pres.SaveAs($SavePptx, 24) }
if ($Pdf) { $pres.SaveCopyAs($Pdf, 32) }
$pres.Close()
if ($running -eq 0 -and $ppt.Presentations.Count -eq 0) { $ppt.Quit() }
"done: $n slides"
