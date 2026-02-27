#!/usr/bin/env pwsh
# GoLeM — Shared flag parser

# Globals set by Parse-Flags
$script:GLM_WORKDIR = '.'
$script:GLM_TIMEOUT = 0
$script:GLM_PERM_MODE = ''
$script:GLM_OPUS = ''
$script:GLM_SONNET = ''
$script:GLM_HAIKU = ''
$script:GLM_PROMPT = ''
$script:GLM_PASSTHROUGH_ARGS = @()

function Parse-Flags {
    param(
        [string]$mode,
        [string[]]$args
    )

    $script:GLM_WORKDIR = '.'
    $script:GLM_TIMEOUT = $script:DEFAULT_TIMEOUT
    $script:GLM_PERM_MODE = $script:PERMISSION_MODE
    $script:GLM_OPUS = $script:OPUS_MODEL
    $script:GLM_SONNET = $script:SONNET_MODEL
    $script:GLM_HAIKU = $script:HAIKU_MODEL
    $script:GLM_PROMPT = ''
    $script:GLM_PASSTHROUGH_ARGS = @()

    $i = 0
    while ($i -lt $args.Count) {
        $arg = $args[$i]

        switch -Regex ($arg) {
            '^(-d)$' {
                if ($i + 1 -ge $args.Count) {
                    Die $script:EXIT_USER_ERROR "Flag -d requires a value"
                }
                $dir = $args[$i + 1]
                if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
                    Die $script:EXIT_USER_ERROR "Directory not found: $dir"
                }
                $script:GLM_WORKDIR = $dir
                $i += 2
            }
            '^(-t)$' {
                if ($i + 1 -ge $args.Count) {
                    Die $script:EXIT_USER_ERROR "Flag -t requires a value"
                }
                $timeout = $args[$i + 1]
                if ($timeout -notmatch '^[0-9]+$') {
                    Die $script:EXIT_USER_ERROR "Timeout must be a number: $timeout"
                }
                $script:GLM_TIMEOUT = $timeout
                $i += 2
            }
            '^(-m|--model)$' {
                if ($i + 1 -ge $args.Count) {
                    Die $script:EXIT_USER_ERROR "Flag $arg requires a value"
                }
                $model = $args[$i + 1]
                $script:GLM_OPUS = $model
                $script:GLM_SONNET = $model
                $script:GLM_HAIKU = $model
                $i += 2
            }
            '^(--opus)$' {
                if ($i + 1 -ge $args.Count) {
                    Die $script:EXIT_USER_ERROR "Flag --opus requires a value"
                }
                $script:GLM_OPUS = $args[$i + 1]
                $i += 2
            }
            '^(--sonnet)$' {
                if ($i + 1 -ge $args.Count) {
                    Die $script:EXIT_USER_ERROR "Flag --sonnet requires a value"
                }
                $script:GLM_SONNET = $args[$i + 1]
                $i += 2
            }
            '^(--haiku)$' {
                if ($i + 1 -ge $args.Count) {
                    Die $script:EXIT_USER_ERROR "Flag --haiku requires a value"
                }
                $script:GLM_HAIKU = $args[$i + 1]
                $i += 2
            }
            '^(--unsafe)$' {
                $script:GLM_PERM_MODE = 'bypassPermissions'
                $i += 1
            }
            '^(--mode)$' {
                if ($i + 1 -ge $args.Count) {
                    Die $script:EXIT_USER_ERROR "Flag --mode requires a value"
                }
                $script:GLM_PERM_MODE = $args[$i + 1]
                $i += 2
            }
            '^(-.+)$' {
                if ($mode -eq 'session') {
                    $script:GLM_PASSTHROUGH_ARGS += $arg
                    $i += 1
                } else {
                    Die $script:EXIT_USER_ERROR "Unknown flag: $arg"
                }
            }
            default {
                if ($mode -eq 'session') {
                    $script:GLM_PASSTHROUGH_ARGS += $args[$i..($args.Count - 1)]
                    $i = $args.Count
                } else {
                    $script:GLM_PROMPT = $args[$i..($args.Count - 1)] -join ' '
                    $i = $args.Count
                }
            }
        }
    }
}
