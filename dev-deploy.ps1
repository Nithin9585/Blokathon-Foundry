# Start Anvil in the background
$anvilProcess = Start-Process -FilePath "anvil" -PassThru -NoNewWindow

Write-Host "Waiting for Anvil to start..."
Start-Sleep -Seconds 5

# Deploy contracts to local Anvil node
Write-Host "Deploying contracts..."
forge script script/DeployMockGardenSystem.s.sol:DeployMockGardenSystem --rpc-url http://127.0.0.1:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Keep script running to keep Anvil alive (optional, or user can run anvil separately)
Write-Host "Deployment complete. Anvil is running (PID: $($anvilProcess.Id)). Press Ctrl+C to stop."
try {
    while ($true) {
        Start-Sleep -Seconds 1
        if ($anvilProcess.HasExited) {
            Write-Host "Anvil stopped unexpectedly."
            break
        }
    }
} finally {
    Stop-Process -Id $anvilProcess.Id -ErrorAction SilentlyContinue
}
