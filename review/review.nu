use gha.nu *

let inputs = gha review-inputs
let pushToAttic = $inputs.push-to-cache and $env.ATTIC_SERVER != '' and $env.ATTIC_CACHE != ''
let pushToCachix = $inputs.push-to-cache and $env.CACHIX_CACHE != ''
let pr = $env.PR_JSON | from json
let base = $pr.base.sha
let merge = $pr.merge_commit_sha
let jobsArg = if $env.USE_BUILDERS == "always" { "-j0" } else { "" }
let system = nix config show system

gha group "install packages" {
  [ nixpkgs-review, generate-markdown-report ]
  | if $pushToAttic { $in ++ [ attic-client ] } else { }
  | if $pushToCachix { $in ++ [ cachix ] } else { }
  | each { $".#($in)" }
  | nix profile add ...$in --builders ''
}

gha group $"run nixpkgs-review ($inputs.extra-args-raw)" {
  cd nixpkgs
  nixpkgs-review -- pr $env.PR_NUMBER ...[
    --no-shell
    --no-exit-status
    --no-headers
    --print-result
    --build-args=($"-L ($jobsArg)")
    --pr-json=($env.PR_JSON)
    ...$inputs.extra-args
  ]
}

let reviewDir = $"~/.cache/nixpkgs-review/pr-($env.PR_NUMBER)" | path expand
let reportJson = $"($reviewDir)/report.json"
let reportMd = $"($reviewDir)/report.md"

let report = open $reportJson
let result = $report.result | get $system
mut rebuildReport = false

if $env.IDENTIFY_UNSUPPORTED_PACKAGES == '1' {
  $rebuildReport = true
  gha group "identify unsupported packages" {
    cd nixpkgs
    if ($result.failed | is-empty) { return $result }

    git fetch origin $merge
    git switch -d $merge

    nix config show --json | save -r ../nix-config.json
    nix derivation show --recursive -f. ...$result.failed.name | save -r ../drv-graph.json
    let buildSupport = nix-instantiate ...[
      --eval --strict --json ("../drv-build-support.nix" | path expand)
      --argstr configPath ("../nix-config.json" | path expand)
      --argstr drvGraphPath ("../drv-graph.json" | path expand)
    ] | from json

    $result.failed
    | insert drv { nix eval -f. $"($in.name).drvPath" --raw | path basename }
    | where {|pkg| $buildSupport | get $pkg.drv | not $in.supported }
    | select name aliases
    | let unsupported
    | get name
    | let unsupportedNames

    $result
    | update failed { where name not-in $unsupportedNames }
    | insert unsupported $unsupported
  }
} else { $result } | let result

if $env.IDENTIFY_STILL_FAILING_PACKAGES == '1' {
  $rebuildReport = true
  gha group "identify still failing packages" {
    cd nixpkgs
    if ($result.failed | is-empty) { return $result }

    git fetch origin $base
    git switch -d $base

    $result.failed
    | insert path { try { nix eval -f. $"($in.name).outPath" --raw } }
    | where path != null
    | let candidates

    if ($candidates | is-not-empty) {
      try { nix build --keep-going -L $jobsArg -f. ...$candidates.name }
    }

    $candidates
    | where { nix store verify --no-contents --no-trust $in.path | complete | $in.exit_code != 0 }
    | select name aliases
    | let stillFailing
    | get name
    | let stillFailingNames

    $result
    | update failed { where name not-in $stillFailingNames }
    | insert still_failing $stillFailing
  }
} else { $result } | let result

let report = $report | update result ($report.result | update $system $result)
if $rebuildReport {
  $report | save -f $reportJson
  generate-markdown-report $reportJson $base | save -f $reportMd
}

if $pushToAttic or $pushToCachix {
  gha group "push results to cache" {
    let paths = glob $"($reviewDir)/results/*" | path expand
    if ($paths | is-empty) { return }

    let cache = if $pushToAttic {
      attic login default $env.ATTIC_SERVER $env.ATTIC_TOKEN
      try {
        attic cache info $env.ATTIC_CACHE
      } catch {
        gha error "attic returned an error"
        return
      }
      $paths | str join "\n" | attic push --stdin $env.ATTIC_CACHE
      http get -H { Authorization: $"Bearer ($env.ATTIC_TOKEN)" } $"($env.ATTIC_SERVER)_api/v1/cache-config/nixpkgs"
      | select substituter_endpoint public_key is_public
    } else if $pushToCachix {
      with-env { CACHIX_SIGNING_KEY: ($env.CACHIX_SIGNING_KEY | default -e null) } {
        $paths | str join "\n" | cachix push $env.CACHIX_CACHE
        http get -H { Authorization: $"Bearer ($env.ATTIC_TOKEN)" } $"https://app.cachix.org/api/v1/cache/($env.CACHIX_CACHE)"
        | select uri publicSigningKeys isPublic
        | update publicSigningKeys { first }
        | rename substituter_endpoint public_key is_public
      }
    }

    if not $cache.is_public { return }

    $cache | to json | print

    let binaryCaches = [
      "https://cache.nixos.org/"
      $cache.substituter_endpoint
    ]
    let publicKeys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      $cache.public_key
    ]

    [
      $"nix-store -r"
      $"--option binary-caches '($binaryCaches | str join ' ')'"
      $"--option trusted-public-keys '($publicKeys | each { $'(char lf)    ($in)' } | str join)\n  '"
      ...$paths
    ]
    | str join " \\\n  "
    | let fetch_cmd
    | save -r fetch_cmd

    print $fetch_cmd
  }
}
