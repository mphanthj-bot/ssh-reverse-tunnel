# =====================================================================
#  CHẠY FILE NÀY TRÊN MÁY CON - CHỈ CẦN 1 LẦN
#  Right-click -> "Run as administrator"
#  Script tự làm hết: cài OpenSSH Server, mở firewall, cài public key,
#  set đúng quyền (ACL). Không cần biết máy đang là Win10 hay Win11.
# =====================================================================

$ErrorActionPreference = "Stop"

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    Write-Host "LỖI: Phải chạy bằng quyền Administrator." -ForegroundColor Red
    Write-Host "Chuột phải vào file -> Run as administrator." -ForegroundColor Red
    Read-Host "Nhấn Enter để thoát"
    exit 1
}

Write-Host "=== Bắt đầu cài đặt SSH Server tự động ===" -ForegroundColor Cyan

# --- 1. Cài OpenSSH Server (tính năng có sẵn trong Windows, không cần internet ngoài) ---
$sshdCapability = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
if ($sshdCapability.State -ne 'Installed') {
    Write-Host "Đang cài OpenSSH Server..." -ForegroundColor Cyan
    Add-WindowsCapability -Online -Name $sshdCapability.Name
} else {
    Write-Host "OpenSSH Server đã được cài sẵn." -ForegroundColor Yellow
}

# --- 2. Khởi động service và đặt auto-start khi khởi động máy ---
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
Write-Host "Đã bật service sshd, tự khởi động cùng Windows." -ForegroundColor Green

# --- 3. Mở firewall cho port 22 (bỏ qua nếu rule đã tồn tại) ---
if (-not (Get-NetFirewallRule -Name sshd -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
    Write-Host "Đã mở firewall port 22." -ForegroundColor Green
} else {
    Write-Host "Firewall rule đã tồn tại, bỏ qua." -ForegroundColor Yellow
}

# --- 4. Cài public key của máy chủ vào đúng vị trí ---
#     Vì tài khoản admin dùng file administrators_authorized_keys riêng (không phải ~/.ssh)
$publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG1HH+yVeq0znw4Lch7gnFoN55hHLnlfC+maNyf0cDDs control-server-MRKENT"

$adminKeyFile = "$env:ProgramData\ssh\administrators_authorized_keys"
if (-not (Test-Path "$env:ProgramData\ssh")) {
    New-Item -ItemType Directory -Path "$env:ProgramData\ssh" -Force | Out-Null
}

if ((Test-Path $adminKeyFile) -and (Get-Content $adminKeyFile -Raw) -match [regex]::Escape($publicKey)) {
    Write-Host "Public key đã có sẵn, bỏ qua." -ForegroundColor Yellow
} else {
    Add-Content -Path $adminKeyFile -Value $publicKey
    Write-Host "Đã thêm public key của máy chủ vào $adminKeyFile" -ForegroundColor Green
}

# --- 5. Set đúng ACL (bắt buộc, nếu sai quyền SSH sẽ từ chối key) ---
icacls $adminKeyFile /inheritance:r | Out-Null
icacls $adminKeyFile /grant "Administrators:F" | Out-Null
icacls $adminKeyFile /grant "SYSTEM:F" | Out-Null
Write-Host "Đã thiết lập đúng quyền (ACL) cho file key." -ForegroundColor Green

Write-Host ""
Write-Host "=== HOÀN TẤT ===" -ForegroundColor Green
Write-Host "Máy này ($env:COMPUTERNAME) đã sẵn sàng nhận kết nối SSH từ máy chủ." -ForegroundColor Green
Write-Host "IP máy này:" -ForegroundColor Cyan
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '169.*' -and $_.IPAddress -ne '127.0.0.1' } | Select-Object IPAddress, InterfaceAlias

Read-Host "Nhấn Enter để đóng cửa sổ"
