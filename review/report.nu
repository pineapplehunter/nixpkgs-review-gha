use gha.nu *

let inputs = gha review-inputs
let pr = $env.PR_JSON | from json
let head = $pr.head.sha
let merge = $pr.merge_commit_sha

let systems = [
  x86_64-linux
  aarch64-linux
  x86_64-darwin
  aarch64-darwin
  riscv64-linux
]

gha group "generate report" {
  let reports = $systems
  | where ($"report_($it).json" | path exists)
  | wrap system
  | insert report { open $"report_($in.system).json" }

  $reports | to json | print
  $reports | to json | save reports.json

  mut nixpkgsReviewCmd = $"nixpkgs-review pr ($env.PR_NUMBER)"
  if ($inputs.extra-args-raw | is-not-empty) {
    $nixpkgsReviewCmd += $" ($inputs.extra-args-raw)"
  }

  mut report = ""
  $report += $"## `nixpkgs-review` result\n\n"
  $report += $"Generated using [`nixpkgs-review-gha`]\(https://github.com/Defelo/nixpkgs-review-gha) \([`($env.SHA | str substring ..<7)`]\(https://github.com/Defelo/nixpkgs-review-gha/commit/($env.SHA)))\n\n"
  $report += $"Command: `($nixpkgsReviewCmd)`\n"
  $report += $"Commit: [`($head)`]\(https://github.com/NixOS/nixpkgs/commit/($head)) \([subsequent changes]\(https://github.com/NixOS/nixpkgs/compare/($head)..pull/($env.PR_NUMBER)/head))\n"
  $report += $"Merge: [`($merge)`]\(https://github.com/NixOS/nixpkgs/commit/($merge))\n\n"
  $report += $"Logs: https://github.com/($env.REPO)/actions/runs/($env.RUN_ID)\n\n"

  $reports
  | where ($it.report.fetch_cmd | is-not-empty)
  | each { $"<li><details><summary><code>($in.system)</code></summary>\n\n```shell\n($in.report.fetch_cmd)\n```\n</details></li>\n" }
  | str join
  | if ($in | is-not-empty) {
    $report += $"<details><summary>Download packages from cache:</summary><ul>\n($in)</ul></details>\n\n"
  }

  $report += $reports.report.md | str join

  print $report

  $reports.report.result
  | values
  | flatten
  | all { select failed still_failing? | values | compact | flatten | is-empty }
  | let success
  | if $in { print "SUCCESS" } else { print "FAILURE" }

  $report
  | str replace -r '^.*' $"$0 for [#($env.PR_NUMBER)]\(https://github.com/NixOS/nixpkgs/pull/($env.PR_NUMBER))"
  | gha step-summary

  {
    report: $report
    success: $success
  }
} | let review

if ($env.GH_TOKEN | is-empty) {
  match $inputs.on-success {
    mark_as_ready => { "mark the PR as ready for review" }
    approve => { "approve the PR" }
    merge => { "merge the PR" }
    _ => { exit }
  } | gha error $"Cannot ($in) because no GH_TOKEN has been configured."
  exit 1
}

if $inputs.post-result {
  gha group "post comment" {
    gh pr -R NixOS/nixpkgs comment $env.PR_NUMBER -b $review.report
  }
}

if not $review.success { exit }

if $inputs.on-success == 'mark_as_ready' {
  gha group "mark pull request as ready for review" {
    gh pr -R NixOS/nixpkgs ready $env.PR_NUMBER
  }
}

if $inputs.on-success in [approve, merge] {
  gha group "approve pull request" {
    let user_id = gh api /user | from json | get id
    if $user_id != $pr.user.id {
      gh pr -R NixOS/nixpkgs review $env.PR_NUMBER --approve -b "Approved automatically following the successful run of `nixpkgs-review`."
    } else if $inputs.on-success == 'approve' {
      gha error "You cannot approve your own pull request."
      exit 1
    }
  }
}

if $inputs.on-success == 'merge' {
  gha group "merge pull request" {
    let is_committer = gh api /repos/NixOS/nixpkgs | from json | get permissions.push
    if $is_committer {
      gh pr -R NixOS/nixpkgs merge $env.PR_NUMBER --merge --match-head-commit $head
    } else {
      let current_head = gh api /repos/NixOS/nixpkgs/pulls/($env.PR_NUMBER) | from json | get head.sha
      if $current_head != $head {
        gha error $"Refusing to merge because the head branch was modified \(expected ($head), got ($current_head) instead)"
        exit 1
      }
      gh pr -R NixOS/nixpkgs comment $env.PR_NUMBER -b "@NixOS/nixpkgs-merge-bot merge"
    }
  }
}
