use gha.nu *

let inputs = gha review-inputs
let pushToAttic = $inputs.push-to-cache and $env.ATTIC_SERVER != '' and $env.ATTIC_CACHE != ''
let pushToCachix = $inputs.push-to-cache and $env.CACHIX_CACHE != ''

gha group "install packages" {
  [ nixpkgs-review ]
  | if $pushToAttic { $in ++ [ attic-client ] } else { }
  | if $pushToCachix { $in ++ [ cachix ] } else { }
  | each { $".#($in)" }
  | nix profile add ...$in --builders ''
}

gha group $"run nixpkgs-review ($inputs.extra-args-raw)" {
  let buildArgs = "-L"
  | if $env.USE_BUILDERS == "always" { $"($in) -j0" } else { }

  cd nixpkgs
  nixpkgs-review -- pr $env.PR_NUMBER ...[
    --no-shell
    --no-exit-status
    --no-headers
    --print-result
    --build-args=($buildArgs)
    --pr-json=($env.PR_JSON)
    ...$inputs.extra-args
  ]
}

if $pushToAttic or $pushToCachix {
  gha group "push results to cache" {
    let paths = glob ~/.cache/nixpkgs-review/pr-($env.PR_NUMBER)/results/* | path expand
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
