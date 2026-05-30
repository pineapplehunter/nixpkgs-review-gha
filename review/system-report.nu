use gha.nu *

let system = nix config show system

gha group "generate report" {
  let dir = $"~/.cache/nixpkgs-review/pr-($env.PR_NUMBER)" | path expand
  mut report = open -r ($dir)/report.md

  if $system !~ '-linux$' {
    let sandbox = nix config show sandbox
    $report = $report | str replace -mr '^### .*$' $"${0} \(sandbox = ($sandbox))"
  }

  if ($report | is-empty) {
    $report = $"\n---\n### `($system)`\n:white_check_mark: *No rebuilds*\n"
  }

  print $report

  open ($dir)/report.json
  | insert md $report
  | insert fetch_cmd (try { open -r fetch_cmd } catch { "" })
  | let reportMd
  | save report_($system).json

  $reportMd | to json | print
}
