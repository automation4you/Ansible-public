# Define image name
$imageName = "mcr.microsoft.com/windows/servercore/iis"

# Pull the IIS Docker image from Microsoft Container Registry
Write-Host "Pulling IIS Docker image..." -ForegroundColor Cyan
try {
    docker pull $imageName
    Write-Host "IIS Docker image pulled successfully." -ForegroundColor Green
} catch {
    Write-Host "Failed to pull IIS Docker image. Error: $_" -ForegroundColor Red
    exit 1
}

# Define container and volume names
$containerName = "iis_core_container"
$websiteSourcePath = "C:\temp\test.html"  # Replace with the path to your website files on the host
$containerWebsitePath = "C:\inetpub\wwwroot"   # Default IIS web root in the container

# Prompt user for domain account information for the IIS App Pool
$domainUser = Read-Host "Enter the domain user for the IIS app pool (e.g., DOMAIN\User)"
$domainPassword = Read-Host "Enter the password for the domain user (note: password will be visible)"

# Stop and remove any existing container with the same name (optional)
try {
    if ((docker ps -a -q -f "name=$containerName") -ne $null) {
        Write-Host "Stopping existing container..." -ForegroundColor Yellow
        docker stop $containerName
        Write-Host "Removing existing container..." -ForegroundColor Yellow
        docker rm $containerName
    }
} catch {
    Write-Host "Failed to stop/remove existing container. Error: $_" -ForegroundColor Red
    exit 1
}

# Run the IIS container with gMSA security option
Write-Host "Running IIS container with gMSA credentials..." -ForegroundColor Cyan
try {
    # Use --security-opt to pass the gMSA credentialspec file to the container
    docker run -d --name $containerName -p 8080:80 --security-opt "credentialspec=file://ServiceA.json" $imageName
    Write-Host "IIS container started successfully with gMSA credentials." -ForegroundColor Green
} catch {
    Write-Host "Failed to start IIS container. Error: $_" -ForegroundColor Red
    exit 1
}

# Copy the website data into the container's IIS web root directory
Write-Host "Copying website data into the container..." -ForegroundColor Cyan
try {
    docker cp $websiteSourcePath ${containerName}:$containerWebsitePath
    Write-Host "Website data copied successfully into the container at C:\inetpub\wwwroot." -ForegroundColor Green
} catch {
    Write-Host "Failed to copy website data into the container. Error: $_" -ForegroundColor Red
    exit 1
}

# Configure the DefaultAppPool to use the domain account
Write-Host "Configuring DefaultAppPool to use the domain user $domainUser..." -ForegroundColor Cyan
try {
    docker exec $containerName powershell -Command "
        Import-Module WebAdministration
        Set-ItemProperty IIS:\AppPools\DefaultAppPool -Name processModel.identityType -Value SpecificUser
        Set-ItemProperty IIS:\AppPools\DefaultAppPool -Name processModel.userName -Value '$domainUser'
        Set-ItemProperty IIS:\AppPools\DefaultAppPool -Name processModel.password -Value '$domainPassword'
    "
    Write-Host "The 'DefaultAppPool' was successfully configured to run under the domain user '$domainUser'." -ForegroundColor Green
} catch {
    Write-Host "Failed to configure the 'DefaultAppPool' with domain user. Error: $_" -ForegroundColor Red
    exit 1
}

# Add the domain user to the IIS_IUSRS group for permissions
Write-Host "Adding domain user $domainUser to IIS_IUSRS group..." -ForegroundColor Cyan
try {
    docker exec $containerName powershell -Command "Add-LocalGroupMember -Group 'IIS_IUSRS' -Member '$domainUser'"
    Write-Host "The domain user '$domainUser' was successfully added to the 'IIS_IUSRS' group, granting necessary permissions for IIS operation." -ForegroundColor Green
} catch {
    Write-Host "Failed to add domain user '$domainUser' to IIS_IUSRS group. Error: $_" -ForegroundColor Red
    exit 1
}

# Grant Read permissions to the wwwroot directory for the domain user
Write-Host "Granting read access to wwwroot directory for domain user $domainUser..." -ForegroundColor Cyan
try {
    docker exec $containerName powershell -Command "
        icacls 'C:\inetpub\wwwroot' /grant '${domainUser}:(R,X)'
    "
    Write-Host "Read access granted to '${domainUser}' for wwwroot directory." -ForegroundColor Green
} catch {
    Write-Host "Failed to grant read access to wwwroot for '${domainUser}'. Error: $_" -ForegroundColor Red
    exit 1
}


# Start the DefaultAppPool
Write-Host "Starting the DefaultAppPool..." -ForegroundColor Cyan
try {
    docker exec $containerName powershell -Command "Start-WebAppPool 'DefaultAppPool'"
    Write-Host "The 'DefaultAppPool' was successfully started." -ForegroundColor Green
} catch {
    Write-Host "Failed to start the 'DefaultAppPool'. Error: $_" -ForegroundColor Red
    exit 1
}

# Check the App Pool State to verify if it's running
Write-Host "Verifying the App Pool state..." -ForegroundColor Cyan
try {
    $appPoolState = docker exec $containerName powershell -Command "Get-WebAppPoolState -Name 'DefaultAppPool'"
    Write-Host "Verification Output: $appPoolState" -ForegroundColor Green
} catch {
    Write-Host "Failed to verify the 'DefaultAppPool' state. Error: $_" -ForegroundColor Red
    exit 1
}

# Confirm everything is working
Write-Host "IIS container is running. You can access it at http://localhost:8080" -ForegroundColor Green
