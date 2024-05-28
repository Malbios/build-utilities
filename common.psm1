Import-Module PowerShellForGitHub

function PrepareGitRepo() {
    git fetch
    git checkout dev
    git pull --tags
}

function PrepareUserSettings() {
    git config user.name "github-actions"
    git config user.email "github-actions@github.com"
}

function GetLocalVersion() {
    $localVersion = (npm pkg get version)

    $localVersion = $localVersion -replace "`"", ""

    return [System.Version]$localVersion
}

function GetNpmOnlineVersion($packageName) {
    $onlineVersion = (npm view $packageName version)

    return [System.Version]$onlineVersion
}

function GetRepoName() {
    return Split-Path -Leaf (git rev-parse --show-toplevel)
}

function EnsureNewVersion() {
    PrepareGitRepo

    $packageName = GetRepoName

    $localVersion = GetLocalVersion
    $onlineVersion = GetNpmOnlineVersion $packageName

    if ($localVersion -gt $onlineVersion) {
        return
    }

    Write-Host "Local version '$($localVersion)' is not higher than online version '$($onlineVersion)'."
    Write-Host "Updating package version..."

    PrepareUserSettings

    npm version minor
    git push --tags origin HEAD:dev
}

function GetLatestTag() {
    return ((git tag -l --sort=v:refname) | Select-Object -Last 1)
}

function PushNewTagTarget($tag, $newCommit) {
    PrepareUserSettings

    git push --delete origin $tag
    git tag -d $tag
    git tag $tag $newCommit
    git push --tags origin HEAD:dev
}

function EnsureLatestVersionTagPointsToLatestCommit() {
    PrepareGitRepo

    $localVersion = GetLocalVersion
    $latestTag = GetLatestTag

    $latestTagVersion = [System.Version]($latestTag.Substring(1))

    if ($localVersion -ne $latestTagVersion) {
        throw "Somehow package.json version '$($localVersion)' does not equal latest tag version '$($latestTagVersion)'."
    }

    $latestDevCommit = git log -n 1 dev --pretty=format:"%H"
    $latestTagCommit = git rev-list -n 1 $latestTag

    if ($latestDevCommit -eq $latestTagCommit) {
        return
    }

    Write-Host "Latest version tag is not on latest commit."
    Write-Host "Moving version tag to latest commit..."

    PushNewTagTarget $latestTag $latestDevCommit
}

function NewPullRequestFromDevToMain($repo, $owner) {
    Write-Host "repo: $repo"
    Write-Host "owner: $owner"

    $pullRequest = New-GitHubPullRequest -Uri "https://github.com/$($owner)/$($repo)" -Title "dev to main" -Head dev -Base main

    if (!$pullRequest) {
        throw "Pull request could not be created!"
    }

    $pullRequest

    # Write-Host "Url: $($pullRequest.url)"

    # gh pr merge $pullRequest.number --rebase --auto
}

function NewRelease($repo, $owner) {
    $latestTag = GetLatestTag

    $release = New-GitHubRelease -Uri "https://github.com/$($owner)/$($repo)" -Name $latestTag -Tag $latestTag
    if (!$release) {
        throw "Release could not be created!"
    }

    return $release
}