use gha.nu *

let inputs = gha review-inputs

gha group "display inputs" {
  $inputs | to json | print
}

gha group "get pr" {
  mut pr = {}
  loop {
    $pr = ^gh api $"/repos/NixOS/nixpkgs/pulls/($env.PR_NUMBER)" | from json
    if $pr.mergeable_state != "unknown" or $pr.merged { break }
    print "mergeable state not known yet, retrying..."
    sleep 2sec
  }

  $pr | to json | print

  if not ($pr.merged or $pr.mergeable) {
    gha error "PR is not mergeable"
  }

  $pr | to json -r | gha output pr
}
