<#
.SYNOPSIS
    Script tự động setup OpenSSH Server & Reverse Tunnel (Bulletproof - Failover 2 IP)
#>

# =======================================================================
# THÔNG SỐ CẤU HÌNH (Anh Nghĩa cần điền đầy đủ trước khi đẩy lên Gist)
# =======================================================================
$LocalIP = "192.168.1.34"         # IP LAN hiện tại của anh
$PublicIP = "113.23.122.32"       # IP Public hiện tại của anh
$RemotePort = 2222                # Port mở trên máy System

# Tự động lấy tên User hiện tại (hoặc thay bằng "Administrator" nếu cần)
$SystemUser = $env:USERNAME
$PubKeyUrl  = "https://raw.githubusercontent.com/mphanthj-bot/ssh-reverse-tunnel/main/id_ed25519.pub" # Nguồn public key trên GitHub (thay vì Gist)
$GistUrl    = "https://raw.githubusercontent.com/mphanthj-bot/ssh-reverse-tunnel/main/WinReverseSSH.ps1" # URL script dùng cho auto-elevate
$UseNSSM = $true             # Sử dụng NSSM tạo Service thay vì Scheduled Task (cần cài NSSM trước)
# =======================================================================

# 1. AUTO-ELEVATE (Ép chạy bằng quyền Admin)
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Đang yêu cầu quyền Administrator..."
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"iex (New-Object Net.WebClient).DownloadString('$GistUrl')`"" -Verb RunAs
    Exit
}

Try {
    Write-Host "[1/5] Đang kiểm tra và cài đặt OpenSSH..." -ForegroundColor Cyan
    if (!(Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*' | Where-Object State -eq 'Installed')) {
        Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 -ErrorAction SilentlyContinue | Out-Null
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue | Out-Null
    }
    Start-Service sshd -ErrorAction SilentlyContinue
    Set-Service -Name sshd -StartupType 'Automatic'

    Write-Host "[2/5] Cấu hình SSH Server & Fix lỗi Administrators Group..." -ForegroundColor Cyan
    $sshdConfig = "$env:ProgramData\ssh\sshd_config"
    if (Test-Path $sshdConfig) {
        # Sửa file config để áp dụng Public Key thay vì Password
        (Get-Content $sshdConfig) -replace '^#PubkeyAuthentication yes', 'PubkeyAuthentication yes' `
                                  -replace '^#PasswordAuthentication yes', 'PasswordAuthentication no' `
                                  -replace '^Match Group administrators', '#Match Group administrators' `
                                  -replace '^\s*AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys', '#AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys' | Set-Content $sshdConfig
        Restart-Service sshd
    }

    Write-Host "[3/5] Đang tải Public Key và thiết lập phân quyền (icacls)..." -ForegroundColor Cyan
    $sshDir = "$env:USERPROFILE\.ssh"
    if (!(Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }
    
    $authKeysPath = "$sshDir\authorized_keys"
    try {
        Invoke-WebRequest -Uri $PubKeyUrl -OutFile $authKeysPath -UseBasicParsing -ErrorAction Stop
        Write-Host "Đã tải public key từ GitHub repo." -ForegroundColor Cyan
    } catch {
        # Fallback: dùng file master.pub cạnh script (nếu URL không khả dụng)
        $masterPubPath = Join-Path $PSScriptRoot 'master.pub'
        if (Test-Path $masterPubPath) {
            $key = (Get-Content $masterPubPath -Raw).Trim()
            Set-Content $authKeysPath $key
            Write-Host "Không thể tải từ URL, dùng file master.pub cạnh script." -ForegroundColor Yellow
        } else {
            Write-Warning "Không tìm thấy file master.pub và URL cũng lỗi."
        }
    }

    # Sửa quyền siêu chặt chẽ cho file authorized_keys (Windows OpenSSH yêu cầu cái này)
    icacls $authKeysPath /inheritance:r /quiet
    icacls $authKeysPath /grant "SYSTEM:(F)" /quiet
    icacls $authKeysPath /grant "Administrators:(F)" /quiet
    icacls $authKeysPath /grant "$env:USERNAME:(F)" /quiet

    Write-Host "[4/5] Tạo cơ chế Auto-Healing Tunnel (Tự động kết nối Failover LAN/WAN)..." -ForegroundColor Cyan
    $tunnelScriptPath = "$env:ProgramData\ssh\ReverseTunnel.ps1"
    $tunnelCode = @"
while (`$true) {
    Write-Output "Dang thu ket noi qua mang LAN (Local IP)..."
    ssh -N -R ${RemotePort}:localhost:22 ${SystemUser}@${LocalIP} -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes
    
    Write-Output "Dang thu ket noi qua Internet (Public IP)..."
    ssh -N -R ${RemotePort}:localhost:22 ${SystemUser}@${PublicIP} -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes
    
    Start-Sleep -Seconds 10
}
"@
    Set-Content -Path $tunnelScriptPath -Value $tunnelCode

    Write-Host "[5/5] Đăng ký Scheduled Task chạy ngầm bằng hệ thống..." -ForegroundColor Cyan
    $taskName = "SSHTunnelService_Auto"
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$tunnelScriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -User "SYSTEM" -RunLevel Highest -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName

    Write-Host ">>> THÀNH CÔNG! HỆ THỐNG ĐÃ SẴN SÀNG <<<" -ForegroundColor Green
    Write-Host "Từ máy System, anh có thể kết nối bằng lệnh: ssh user_client@localhost -p $RemotePort" -ForegroundColor Yellow

} Catch {
    Write-Host "Đã xảy ra lỗi trong quá trình cài đặt: $($_.Exception.Message)" -ForegroundColor Red
}