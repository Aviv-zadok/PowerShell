﻿$User = "XXXXXX@XXXXXX.XXXXXX"
$Pass = "XXXXXX"
$tenant = "XXXXXX-XXXXXX-XXXXXX-XXXXXX-XXXXXXXXXXXX"
$organization = "https://dev.azure.com/XXXXXXXXXXXX/"
$Team_Project = "XXXXXX"
$pat = "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
$org = "XXXXXXXXXXXX"
$source_branch = "refs/heads/Dev"
$hex_release = "Release"
$directoryPath_todelete = "D:\Scripts\QA_Dev_Branch\"
$filePatterns = @(
    "Branch_Create_*.txt",
    "Build_completed_*.txt",
    "Build_started_*.txt"
)
############
$Target_stage = "QA"
$NewBranchName = "refs/heads/Release/Release_154"
############
$hex_new_full = $NewBranchName.Split("/")
$hex_new = $hex_new_full[3]
#$hex_new = "Release_154"
$Branch_Number = $hex_new -replace '[^\d]+', ''
$output_file = "D:\Scripts\QA_Dev_Branch\Branch_Create_"+$Branch_Number+".txt"
$output_file_Build = "D:\Scripts\QA_Dev_Branch\Build_started_"+$Branch_Number+".txt"
$output_file_Build_completed = "D:\Scripts\QA_Dev_Branch\Build_completed_"+$Branch_Number+".txt"
$policy_group = 'repo2'
$Approvers_grp_A = "[XXXXXX XXXXXX]\XXXXXXXXXXXX"
$infosec_grp = "[XXXXXX XXXXXX]\XXXXXX XXXXXX"


$DB = @('XXXXXX.XXXXXX.DB', 'XXXXXX.XXXXXX.DB.XXXXXX', 'XXXXXX.XXXXXX.DB.XXXXXX', 'repo2')



# Define the function to get the build status
function Get-BuildStatus {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Build_run_ID
    )
    #az pipelines build show --id $Build_run_ID --output table
    # Command to get the build status
    $BuildStatus = az pipelines build show --id $Build_run_ID --output json | ConvertFrom-Json

    while ($BuildStatus.status -ne "completed" -and $BuildStatus.status -ne "cancelling") {
        Start-Sleep -Seconds 3 
        $BuildStatus = az pipelines build show --id $Build_run_ID --output json | ConvertFrom-Json
        Write-Host 'status is "inProgress" cheking again in 5 secent'
    }

    return $BuildStatus
}


foreach ($pattern in $filePatterns) {
    # Get the list of files matching the current pattern
    $files = Get-ChildItem -Path $directoryPath_todelete -Filter $pattern
    
    # Loop through each file and delete it
    foreach ($file in $files) {
        Remove-Item -Path $file.FullName -Force
        Write-Host "Deleted file: $($file.FullName)"
    }
}

Write-Host "File deletion completed."

$BuildStatus_reset = "None"
$BuildResult_reset = "None"
    
$MS_List = "D:\Scripts\QA_Dev_Branch\MicroServices.txt"
$Content = Get-Content -Path $MS_List

az login -u $User -p $Pass -t $tenant 
az devops configure --defaults organization=$organization project=$Team_Project 

#### MAIN BEGIN ####

## Create Branch in repo ##
foreach ($repository in $Content) {
    $Branchs = az repos ref list --project $Team_Project --repository $repository --query "[].{id: objectId, name: name}" --output json | ConvertFrom-Json
    #az repos ref list --project $Team_Project --repository $repository --query "[].{id: objectId, name: name}" --output table
    foreach ($Branch in $Branchs) {
        #Write-Host "Repository Name: $($Branch.Name)"
        if( $Branch.name -ieq $source_branch){
            Write-Host "################"
            Write-Host    $repository
            Write-Host "################"
            $BranchList_Release = az repos ref list --filter heads/ -r $repository -p $Team_Project --output json | ConvertFrom-Json
            foreach ($obj in $BranchList_Release) {
                if( $obj.name -ieq $source_branch){
                    $ReleaseBranchID = $obj.objectId
                }
            }

            $reposlist = az repos list --project $Team_Project --query "[].{Name: name, ID: id}" --output json
            $repos = $reposlist | Out-String | ConvertFrom-Json
            $e = $ErrorActionPreference
            $ErrorActionPreference="stop"
            foreach ($repo in $repos) {
                if ( $repo.Name -ieq $repository){
                    $repository_ID = $repo.ID   
                    try {
                        $policyConfigurations_az = az repos policy list --org $organization --project $Team_Project --repository-id $repository_ID --branch $source_branch --output json
                        #az repos policy list --organization $organization --project $Team_Project --repository-id $repository_ID --branch $source_branch --output json
                        $policyConfigurations = $policyConfigurations_az | Out-String | ConvertFrom-Json
                        $jsonData_az = az repos policy list --branch $source_branch --repository-id $repository_ID --output json 
                        $jsonData = $jsonData_az | Out-String | ConvertFrom-Json
                        # Create new Branch & Policy
                        write-host "##[debug] Creating $hex_new Branch"
                        az repos ref create --name $NewBranchName -p $Team_Project -r $repository --object-id $ReleaseBranchID
                        $Crt_Branch_Exit_Code = $LASTEXITCODE
                        write-host "##[section] Finish Create $hex_new Branch" 
                        #pause
                        write-host "##[debug] Creating Policies"
                        if ( $repository -ieq $policy_group ){
                            az repos policy required-reviewer create --blocking true --enabled true --branch $NewBranchName --repository-id $repository_ID --required-reviewer-ids $Approvers_grp_A --message $Approvers_grp_A
                            az repos policy required-reviewer create --blocking true --enabled true --branch $NewBranchName --repository-id $repository_ID --required-reviewer-ids $infosec_grp --message $infosec_grp
                            az repos policy build create --blocking true --enabled true --branch $NewBranchName --repository-id $repository_ID --build-definition-id 1231 --display-name cm-roy-test --queue-on-source-update-only true --manual-queue-only false --valid-duration 1440
                        }
                        else {
                            for ($i = 0; $i -lt $jsonData.Length; $i++) {
                            $body = @($jsonData[$i]) | ConvertTo-Json -Depth 99
                            $body | Set-Content -Path C:\Temp\Branch_Policies.json
                            $jsonFilePath = "C:\Temp\Branch_Policies.json"
                            $jsonContent = Get-Content -Path $jsonFilePath -Raw
                            #$findString = "refs/heads/Dev"
                            #$replaceString = "refs/heads/Release_154"
                            $modifiedContent = $jsonContent -replace [regex]::Escape($source_branch), $NewBranchName
                            #####################################
                            Set-Content -Path $jsonFilePath -Value $modifiedContent
                            Write-Output "String replacement complete."
                            az repos policy create --config C:\Temp\Branch_Policies.json #--output none
                        }
                            
                            #########################

                            write-host "##[section] Finish Creating Policies" 
                            Write-Host "------------------------------------"
                            Write-Host "Branch '$NewBranchName' created successfully."
                            Write-Host "------------------------------------"
                            
                        }
                        Add-Content -Path $output_file -Value \"Branch in $repository created successfully.\"
                        #############################################################################################################
                        #Add Security Groups to branch
                        foreach ($DB_NAME in $DB ) {
                            if( $repository -ieq $DB_NAME){
                                $tfs_project_info = az devops project show --project $Team_Project --org $organization --output json | ConvertFrom-Json
                                $tfs_project_id = $tfs_project_info.id
                                #$tfs_project_id   
                                $repo = az repos list --query '[].{Name:name, Url:remoteUrl, ID:id}' --output json | ConvertFrom-Json
                                foreach ($repo_all in $repo) {
                                    if( $repo_all.name -ieq $repository){
                                        $repo_id = $repo_all.id
                                        #$repo_id
                                    }
                                }
                                ##########################
                                $ID = "2e9eb7ed-3c0a-47d4-87c1-0ffdd275fd87"
                                #$Name_spaces = az devops security permission namespace list --output json | ConvertFrom-Json
                                #foreach ($Name_space in $Name_spaces) {
                                #    if( $Name_space.name -ieq "Git Repositories"){
                                #        $ID = $Name_space.namespaceId
                                #    }
                                #}
                                ##########################
                                function hexify($string) {
                                    return ($string | Format-Hex -Encoding Unicode | Select-Object -Expand Bytes | ForEach-Object { '{0:x2}' -f $_ }) -join ''
                                }
                                $hexBranch = ($hex_new | ForEach-Object { hexify -string $_ }) -join "/"
                                $hexBranch2 = ($hex_release | ForEach-Object { hexify -string $_ }) -join "/"  ##
                                $token2 = "refs/heads/$hexBranch2/$hexBranch"
                                $token3="repoV2"+"/"+$tfs_project_id+"/"+$repo_id+"/"+$token2
                                $security_groups = az devops security group list --org $organization --project $Team_Project --output json | ConvertFrom-Json
                                #az devops security group list --org $organization --project $Team_Project --output table
                                $security_groups = $security_groups.PsObject.Properties.value
                                foreach ($security_group in $security_groups) {
                                    if( $security_group.principalName -ieq "[TEAM FOUNDATION]\ORG-TECH-DBA PRODUCTION TEAM"){
                                        $subject = $security_group.descriptor
                                    }
                                }
                                Write-Host "security permission"
                                az devops security permission update --id $ID --subject $subject --token $token3 --allow-bit 32900
                                #az devops security permission update --id $ID --subject $subject --token $token3 --allow-bit 4
                                #Write-Host "security permission 2"
                                #az devops security permission update --id $ID --subject $subject --token $token3 --allow-bit 32768
                                #Write-Host "security permission 3"
                                #az devops security permission update --id $ID --subject $subject --token $token3 --allow-bit 128
                            }
                        }
                    } catch {
                        Write-Host "Error creating branch: $_"
                        Write-Host "------------------------------------"
                        Write-Host "Branch '$NewBranchName' didnt created."
                        Write-Host "------------------------------------"
                        Add-Content -Path $output_file -Value \"Branch in $repository not created.\"
                    }
                }
            }
        }
    }


    if ( $Crt_Branch_Exit_Code -ieq "0" ){
        ## Triger build for the new Branch ##
        try {
            #Start-Sleep -Seconds 10
            az pipelines run --name $repository --branch $NewBranchName
            Write-Host "------------------------------------"
            Write-Host "Build '$repository' Started successfully."
            Write-Host "------------------------------------"
            Add-Content -Path $output_file_Build -Value \"Build $repository Started successfully.\"
        } catch {
            Write-Host "Error Starting Build: $_"
            Add-Content -Path $output_file_Build -Value \"Build $repository not Started. **** \"
        }
        ## Build seccess report loop ##
        #az pipelines list --output table
        $Builds = az pipelines list --output json | ConvertFrom-Json
        #$Builds = az pipelines list --output table
        foreach ($Build in $Builds) { 
            if( $Build.name -ieq $repository){
                $Build_ID = $Build.id
                #az pipelines runs list --branch $NewBranchName --pipeline-ids $Build_ID -p $Team_Project --output table
                #$Build_run = az pipelines runs list --branch $NewBranchName --pipeline-ids $Build_ID -p $Team_Project --output table
                $Build_run = az pipelines runs list --branch $NewBranchName --pipeline-ids $Build_ID -p $Team_Project --query-order Queuetimedesc --top 1 --output json | ConvertFrom-Json
                $Build_run_ID = $Build_run.id
            }
        }
        az pipelines build show --id $Build_run_ID --output table
        $BuildStatus = Get-BuildStatus -Build_run_ID $Build_run_ID
        Add-Content -Path $output_file_Build_completed -Value \"Build * $repository * Status - $Build_Status | Result - $Build_Result\"
    }
    else {
        Write-Host "Skipping Build Stage"
    }

    $BuildStatus_reset = $BuildStatus.status
    $BuildResult_reset = $BuildStatus.Result

    ## Triger Release from Build ##
    sleep 5
    if (  $BuildStatus_reset -ieq "completed" -and $BuildResult_reset -ieq "succeeded" ){
        $release_id = az pipelines release definition list --output json | ConvertFrom-Json
        #az pipelines release definition list --output table
        foreach ($obj in $release_id) {
            if( $obj.name -ieq $repository){
                $DEFINITION_ID = $obj.id
                Write-Host "The Release is:"
                $obj.name
                #$DEFINITION_ID 8
                #az pipelines runs list --branch $NewBranchName --pipeline-ids $Build_ID -p $Team_Project --output table
                #az pipelines run --name $repository --branch $NewBranchName --output table
                $Release_info = "_"+$obj.name+"="+$Build_Run_ID
                az pipelines release create --definition-name $obj.name --artifact-metadata-list "$Release_info"
                #az pipelines release create --definition-name $obj.name --artifact-metadata-list _Repo2=268164
                #Write-Host "sleep 10 sec..."
                #Start-Sleep -Seconds 10
                $RELEASE_ID_Source = az pipelines release list --source-branch $NewBranchName --org $organization --top 1 --project $Team_Project --definition-id $DEFINITION_ID --output json | ConvertFrom-Json
                #az pipelines release list --source-branch $NewBranchName --org $organization --top 1 --project $Team_Project --definition-id $DEFINITION_ID --output table
                $Status = "continue" 
                foreach ($Release in $RELEASE_ID_Source) {
                    $RELEASE_ID = $Release.id
                    #$RELEASE_ID
                    $stages = az pipelines release show --id $RELEASE_ID --query "environments[].{id: id, name: name, Status: status}" --output json | ConvertFrom-Json
                    #az pipelines release show --id $RELEASE_ID --query "environments[].{id: id, name: name, Status: status}" --output table
                    Write-Host "The Release ID is:"
                    $RELEASE_ID
                    foreach ($stage in $stages) {
                        Write-Host "The Stage is:"
                        Write-Host $stage
                        if ($stage.name -ieq $Target_stage ) {
                            $Stage_ID = $stage.id
                            Write-Host "The Release ID is:"
                            $RELEASE_ID
                            #$Stage_ID
                            $URL1 = "https://vsrm.dev.azure.com/$org/$Team_Project/_apis/release/releases/$RELEASE_ID/environments/$Stage_ID"
                            $URL2 = "?api-version=6.0-preview.6"
                            $uri = $URL1+$URL2
                            #$uri = "https://vsrm.dev.azure.com/$org/$Team_Project/_apis/release/releases/$RELEASE_ID/environments/724?api-version=6.0-preview.6"
                
                            $body = @{
                                status = "inProgress"
                            } | ConvertTo-Json
                            #Write-Host "sleep:10"
                            #sleep 10
                            Invoke-RestMethod -Uri $uri -Method patch -Headers @{Authorization=("Basic {0}" -f [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)")))} -ContentType "application/json" -Body $body
                            $Status = "Exit"  
              
                        }
                    }
                }
            }
        }
    }
    else {
        Write-Host "Skipping Release Stage"
    }
}

az logout