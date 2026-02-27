# GoLeM — Configuration loading (PowerShell)

# Constants
$script:SUBAGENT_DIR = Join-Path $HOME '.claude/subagents'
$script:CONFIG_DIR = Join-Path $HOME '.config/GoLeM'
$script:ZAI_BASE_URL = 'https://api.z.ai/api/anthropic'
$script:ZAI_API_TIMEOUT_MS = '3000000'
$script:DEFAULT_TIMEOUT = 3000
$script:DEFAULT_PERMISSION_MODE = 'bypassPermissions'
$script:DEFAULT_MAX_PARALLEL = 3
$script:DEFAULT_MODEL = 'glm-4.7'

# Globals set by Load-Config
$script:PERMISSION_MODE = ''
$script:MAX_PARALLEL = 0
$script:MODEL = ''
$script:OPUS_MODEL = ''
$script:SONNET_MODEL = ''
$script:HAIKU_MODEL = ''

# Globals set by Load-Credentials
$script:ZAI_API_KEY = ''

function Load-Config {
    $glmConf = Join-Path $script:CONFIG_DIR 'glm.conf'

    if (Test-Path $glmConf) {
        foreach ($line in Get-Content $glmConf) {
            if ($line -match '^\s*([A-Z_]+)=(["\x27])([^"\x27]*)\2') {
                $key = $Matches[1]
                $value = $Matches[3]
                Set-Variable -Name $key -Value $value -Scope Script -Force
            } elseif ($line -match '^\s*([A-Z_]+)=([^#\s]+)') {
                $key = $Matches[1]
                $value = $Matches[2]
                Set-Variable -Name $key -Value $value -Scope Script -Force
            }
        }
    }

    $script:MODEL = if ($script:GLM_MODEL) { $script:GLM_MODEL } else { $script:DEFAULT_MODEL }
    $script:OPUS_MODEL = if ($script:GLM_OPUS_MODEL) { $script:GLM_OPUS_MODEL } else { $script:MODEL }
    $script:SONNET_MODEL = if ($script:GLM_SONNET_MODEL) { $script:GLM_SONNET_MODEL } else { $script:MODEL }
    $script:HAIKU_MODEL = if ($script:GLM_HAIKU_MODEL) { $script:GLM_HAIKU_MODEL } else { $script:MODEL }
    $script:PERMISSION_MODE = if ($script:GLM_PERMISSION_MODE) { $script:GLM_PERMISSION_MODE } else { $script:DEFAULT_PERMISSION_MODE }
    $script:MAX_PARALLEL = if ($script:GLM_MAX_PARALLEL) { [int]$script:GLM_MAX_PARALLEL } else { $script:DEFAULT_MAX_PARALLEL }

    if (-not (Test-Path $script:SUBAGENT_DIR)) {
        New-Item -ItemType Directory -Path $script:SUBAGENT_DIR -Force | Out-Null
    }
}

function Load-Credentials {
    $zaiEnv = Join-Path $script:CONFIG_DIR 'zai_api_key'

    if (-not (Test-Path $zaiEnv)) {
        $zaiEnv = Join-Path $HOME '.config/zai/env'
    }

    if (-not (Test-Path $zaiEnv)) {
        Die $script:EXIT_USER_ERROR @(
            'Z.AI credentials not found.',
            'Run install.sh or create manually:',
            '  mkdir -p ~/.config/GoLeM',
            "  echo 'ZAI_API_KEY=\`"your-key\`"' > ~/.config/GoLeM/zai_api_key",
            '  chmod 600 ~/.config/GoLeM/zai_api_key'
        )
    }

    foreach ($line in Get-Content $zaiEnv) {
        if ($line -match '^\s*ZAI_API_KEY=(?:["\x27])([^"\x27]*)\1') {
            $script:ZAI_API_KEY = $Matches[1]
            break
        } elseif ($line -match '^\s*ZAI_API_KEY=([^#\s]+)') {
            $script:ZAI_API_KEY = $Matches[1]
            break
        }
    }

    if ([string]::IsNullOrEmpty($script:ZAI_API_KEY)) {
        Die $script:EXIT_USER_ERROR "ZAI_API_KEY is empty in $zaiEnv"
    }
}

function Check-Dependencies {
    if (-not (Get-Command 'claude' -ErrorAction SilentlyContinue)) {
        Die $script:EXIT_DEPENDENCY 'claude CLI not found in PATH'
    }
    if (-not (Get-Command 'python3' -ErrorAction SilentlyContinue)) {
        Die $script:EXIT_DEPENDENCY 'python3 not found in PATH'
    }
}
