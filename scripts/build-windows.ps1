param(
    [string]$Version = "2.3.1",
    [string]$Runtime = "win-x64"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$project = Join-Path $repositoryRoot "Windows\TinySpectrum.Windows\TinySpectrum.Windows.csproj"
$publishDirectory = Join-Path $repositoryRoot "dist\windows\TinySpectrum-$Version-$Runtime"
$archive = Join-Path $repositoryRoot "dist\TinySpectrum-$Version-$Runtime.zip"
$distRoot = [IO.Path]::GetFullPath((Join-Path $repositoryRoot "dist")) + [IO.Path]::DirectorySeparatorChar
$resolvedPublishDirectory = [IO.Path]::GetFullPath($publishDirectory)
$resolvedArchive = [IO.Path]::GetFullPath($archive)
if (-not $resolvedPublishDirectory.StartsWith($distRoot, [StringComparison]::OrdinalIgnoreCase) -or
    -not $resolvedArchive.StartsWith($distRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Windows build outputs must stay inside the repository dist directory."
}

if (Test-Path $publishDirectory) { Remove-Item -LiteralPath $publishDirectory -Recurse -Force }
if (Test-Path $archive) { Remove-Item -LiteralPath $archive -Force }

dotnet publish $project `
    --configuration Release `
    --runtime $Runtime `
    --self-contained true `
    --output $publishDirectory `
    -p:Version=$Version `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:DebugType=None `
    -p:DebugSymbols=false

Get-ChildItem -LiteralPath $publishDirectory -Filter "*.pdb" -File | Remove-Item -Force

Compress-Archive -Path (Join-Path $publishDirectory "*") -DestinationPath $archive -CompressionLevel Optimal
Write-Output $archive
