export def "gha group" [name: string, block: closure] {
  print $"::group::($name)"
  let result = do $block
  print "::endgroup::"
  $result
}

export def "gha error" [msg: string] {
  print $"::error::($msg)"
}

export def "gha output" [name: string] {
  $"($name)=($in)\n" | save -ra $env.GITHUB_OUTPUT
}

export def "gha step-summary" [] {
  save -ra $env.GITHUB_STEP_SUMMARY
}

export def "gha review-inputs" [] {
  $env.INPUTS
  | from json
  | upsert extra-args { default "" }
  | update cells -c [
    x86_64-linux
    aarch64-linux
    riscv64-linux
    push-to-cache
    upterm
    post-result
  ] { $in == "true" }
  | update pr { into int }
  | insert extra-args-raw { $in.extra-args }
  | update extra-args { $"[($in)]" | from nuon }
}
