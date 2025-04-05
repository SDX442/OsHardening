#!/bin/bash

# Variables
WINDOWS_IP="20.21.130.136"
WINDOWS_USER="saad"
WINDOWS_PASS="TEST123@@ttTEST"
LOCAL_DIR="./hardening_output"
LOCAL_AUDIT_REPORT="$LOCAL_DIR/HardeningKittyAuditReport.csv"
LOCAL_HARDEN_LOG="$LOCAL_DIR/HardeningKittyHardenLog.txt"
LOCAL_LOG="$LOCAL_DIR/HardeningKittyExecutionLog.txt"
LOCAL_ERROR="$LOCAL_DIR/HardeningKittyError.log"
REMOTE_AUDIT_LOG="C:\\Users\\saad\\Documents\\HardeningKittyLog.txt"
REMOTE_HARDEN_REPORT="C:\\Users\\saad\\Documents\\HardeningKittyReport.csv"


mkdir -p "$LOCAL_DIR"

# Function to perform audit
run_audit() {
    echo "Starting the Audit Process..." | tee -a "$LOCAL_LOG"

    evil-winrm -i "$WINDOWS_IP" -u "$WINDOWS_USER" -p "$WINDOWS_PASS" << EOF | tee >(sed -n '/^PS /!p' > 
"$LOCAL_LOG") > >(sed -n '/^PS /!p' | grep -i 'csv,' > "$LOCAL_AUDIT_REPORT")
\$ProgressPreference = "SilentlyContinue"

# Function to install HardeningKitty
Function InstallHardeningKitty {
    try {
        \$Version = (((Invoke-WebRequest 
"https://api.github.com/repos/scipag/HardeningKitty/releases/latest" -UseBasicParsing) | 
ConvertFrom-Json).Name).SubString(2)
        \$DownloadLink = ((Invoke-WebRequest 
"https://api.github.com/repos/scipag/HardeningKitty/releases/latest" -UseBasicParsing) | 
ConvertFrom-Json).zipball_url
        Invoke-WebRequest \$DownloadLink -OutFile "HardeningKitty\$Version.zip"
        Expand-Archive -Path "HardeningKitty\$Version.zip" -DestinationPath "HardeningKitty\$Version" 
-Force
        \$Folder = Get-ChildItem "HardeningKitty\$Version" | Select-Object -ExpandProperty Name
        Move-Item "HardeningKitty\$Version\\\$Folder\\*" "HardeningKitty\$Version\\" -Force
        Remove-Item "HardeningKitty\$Version\\\$Folder" -Recurse
        New-Item -Path \$Env:ProgramFiles\\WindowsPowerShell\\Modules\\HardeningKitty\\\$Version 
-ItemType Directory -Force
        Copy-Item -Path "HardeningKitty\$Version\\*" -Destination 
\$Env:ProgramFiles\\WindowsPowerShell\\Modules\\HardeningKitty\\\$Version -Recurse
        Import-Module 
"\$Env:ProgramFiles\\WindowsPowerShell\\Modules\\HardeningKitty\\\$Version\\HardeningKitty.psm1"
    } catch {
        Write-Host "Error installing HardeningKitty: \$_"
        exit 1
    }
}

# Install HardeningKitty
InstallHardeningKitty

# Run the audit
\$Output = Invoke-HardeningKitty -Mode Audit -Log -Report
Write-Output \$Output
EOF

    if [ -f "$LOCAL_AUDIT_REPORT" ] && [ -f "$LOCAL_LOG" ]; then
        echo "Audit completed successfully."
        echo "Report saved locally at: $LOCAL_AUDIT_REPORT"
        echo "Log saved locally at: $LOCAL_LOG"
    else
        echo "Error: Failed to save the report or log locally. Check $LOCAL_ERROR for details."
        exit 1
    fi
}

# Function to perform hardening
run_harden() {
    echo "Starting the HardeningKitty Hardening Process..." | tee -a "$LOCAL_LOG"

    evil-winrm -i "$WINDOWS_IP" -u "$WINDOWS_USER" -p "$WINDOWS_PASS" << EOF | tee -a 
"$LOCAL_HARDEN_LOG" 2>> "$LOCAL_ERROR"
\$ProgressPreference = "SilentlyContinue"

try {
    Import-Module HardeningKitty
    Invoke-HardeningKitty -Mode HailMary -Log -Report -FileFindingList ".\\HardeningKittyReport.csv" 
-SkipRestorePoint
    Write-Host "Hardening completed successfully!"
} catch {
    Write-Host "Error during hardening: \$_"
    exit 1
}
EOF

    if [ $? -eq 0 ]; then
        echo "Hardening completed successfully."
        echo "Harden log saved locally at: $LOCAL_HARDEN_LOG"
    else
        echo "Error: Hardening process failed. Check $LOCAL_ERROR for details."
        exit 1
    fi
}

# Main script logic
if [ "$1" == "audit" ]; then
    run_audit
elif [ "$1" == "harden" ]; then
    run_harden
else
    echo "Usage: $0 {audit|harden}"
    exit 1
fi
