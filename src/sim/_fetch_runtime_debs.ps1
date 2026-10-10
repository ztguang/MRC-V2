# Download Ubuntu 22.04 libs matching the prebuilt engine (OpenCV 4.6d, fmt9, spdlog1.10, yaml-cpp0.7)
$ErrorActionPreference = "Stop"
$outDir = "C:\Users\ztg\Desktop\lunwen\lunwen\sim\third_party\runtime_debs"
$extract = "C:\Users\ztg\Desktop\lunwen\lunwen\sim\godot\bin\linux-x86_64\runtime"
New-Item -ItemType Directory -Force -Path $outDir, $extract | Out-Null

# Ubuntu jammy packages from mirrors
$packages = @(
  "http://archive.ubuntu.com/ubuntu/pool/universe/o/opencv/libopencv-core4.5d_4.5.4+dfsg-9ubuntu4_amd64.deb",
  "http://archive.ubuntu.com/ubuntu/pool/universe/o/opencv/libopencv-imgproc4.5d_4.5.4+dfsg-9ubuntu4_amd64.deb",
  "http://archive.ubuntu.com/ubuntu/pool/universe/o/opencv/libopencv-imgcodecs4.5d_4.5.4+dfsg-9ubuntu4_amd64.deb",
  "http://archive.ubuntu.com/ubuntu/pool/universe/o/opencv/libopencv-highgui4.5d_4.5.4+dfsg-9ubuntu4_amd64.deb",
  "http://archive.ubuntu.com/ubuntu/pool/universe/o/opencv/libopencv-calib3d4.5d_4.5.4+dfsg-9ubuntu4_amd64.deb",
  "http://archive.ubuntu.com/ubuntu/pool/universe/o/opencv/libopencv-dnn4.5d_4.5.4+dfsg-9ubuntu4_amd64.deb",
  "http://archive.ubuntu.com/ubuntu/pool/universe/o/opencv/libopencv-features2d4.5d_4.5.4+dfsg-9ubuntu4_amd64.deb",
  "http://archive.ubuntu.com/ubuntu/pool/universe/o/opencv/libopencv-flann4.5d_4.5.4+dfsg-9ubuntu4_amd64.deb",
  "http://archive.ubuntu.com/ubuntu/pool/universe/f/fmtlib/libfmt9_9.1.0+ds1-2_amd64.deb",
  "http://archive.ubuntu.com/ubuntu/pool/universe/s/spdlog/libspdlog1.10_1.10.0+ds-1_amd64.deb",
  "http://archive.ubuntu.com/ubuntu/pool/universe/y/yaml-cpp/libyaml-cpp0.7_0.7.0+dfsg-8build1_amd64.deb",
  "http://archive.ubuntu.com/ubuntu/pool/universe/libt/libtbb/libtbb12_2021.5.0-7ubuntu2_amd64.deb"
)

# Engine wants .406 SONAME (OpenCV 4.6). Try jammy-backports / kinetic / noble names.
# Prefer packages that provide libopencv_*.so.406 if available; otherwise we may need to SONAME symlink.
$extra = @(
  "http://archive.ubuntu.com/ubuntu/pool/universe/o/opencv/libopencv-core406_4.6.0+dfsg-11_amd64.deb",
  "http://archive.ubuntu.com/ubuntu/pool/universe/o/opencv/libopencv-imgproc406_4.6.0+dfsg-11_amd64.deb",
  "http://archive.ubuntu.com/ubuntu/pool/universe/o/opencv/libopencv-imgcodecs406_4.6.0+dfsg-11_amd64.deb",
  "http://archive.ubuntu.com/ubuntu/pool/universe/o/opencv/libopencv-highgui406_4.6.0+dfsg-11_amd64.deb",
  "http://archive.ubuntu.com/ubuntu/pool/universe/o/opencv/libopencv-calib3d406_4.6.0+dfsg-11_amd64.deb",
  "http://archive.ubuntu.com/ubuntu/pool/universe/o/opencv/libopencv-dnn406_4.6.0+dfsg-11_amd64.deb",
  "http://archive.ubuntu.com/ubuntu/pool/universe/o/opencv/libopencv-features2d406_4.6.0+dfsg-11_amd64.deb",
  "http://archive.ubuntu.com/ubuntu/pool/universe/o/opencv/libopencv-flann406_4.6.0+dfsg-11_amd64.deb"
)

function Try-Download($url) {
  $name = Split-Path $url -Leaf
  $path = Join-Path $outDir $name
  if ((Test-Path $path) -and (Get-Item $path).Length -gt 1000) {
    Write-Host "exists $name"
    return $path
  }
  try {
    Write-Host "GET $url"
    Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing
    if ((Get-Item $path).Length -lt 1000) { Remove-Item $path -Force; return $null }
    return $path
  } catch {
    Write-Host "FAIL $name : $($_.Exception.Message)"
    if (Test-Path $path) { Remove-Item $path -Force }
    return $null
  }
}

$downloaded = @()
foreach ($u in ($extra + $packages)) {
  $p = Try-Download $u
  if ($p) { $downloaded += $p }
}

Write-Host "Downloaded $($downloaded.Count) packages"
# Extract with tar (Windows 10+)
$stage = Join-Path $outDir "stage"
New-Item -ItemType Directory -Force -Path $stage | Out-Null
foreach ($deb in $downloaded) {
  Write-Host "extract $deb"
  $tmp = Join-Path $stage ([IO.Path]::GetFileNameWithoutExtension($deb))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  Push-Location $tmp
  try {
    tar -xf $deb 2>$null
    if (Test-Path "data.tar.zst") { tar -xf data.tar.zst }
    elseif (Test-Path "data.tar.xz") { tar -xf data.tar.xz }
    elseif (Test-Path "data.tar.gz") { tar -xf data.tar.gz }
    elseif (Test-Path "data.tar") { tar -xf data.tar }
  } finally { Pop-Location }
}

# Copy .so files into runtime
Get-ChildItem $stage -Recurse -Include "*.so*" | ForEach-Object {
  Copy-Item $_.FullName -Destination $extract -Force
  Write-Host "copied $($_.Name)"
}
Write-Host "Runtime libs:"
Get-ChildItem $extract | Select-Object Name,Length | Format-Table
