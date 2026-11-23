#!/usr/bin/env bash
#
# Health check. Runs the check of every row in scripts/lib/steps.sh, so it
# covers exactly what `dot setup` installs.

run_doctor() {
  local mode="${1:-standalone}"
  local failures=0
  local warnings=0
  local row action
  local actions=()

  for row in "${DOT_STEPS[@]}"; do
    step_parse "$row"
    platform_skips_step "$STEP_NAME" && continue

    info "Checking $STEP_NAME"
    "$STEP_CHECK" && continue

    if [[ "$STEP_REQUIRED" == yes ]]; then
      ((failures += 1))
    else
      ((warnings += 1))
    fi
    for action in ${actions[@]+"${actions[@]}"}; do
      [[ "$action" != "$STEP_ACTION" ]] || continue 2
    done
    actions+=("$STEP_ACTION")
  done

  if (( failures > 0 )); then
    if [[ "$mode" == "standalone" ]]; then
      print_summary "$failures health check(s) failed; the setup needs attention"
      print_action_required "${actions[@]}"
    else
      warn "$failures health check(s) failed"
    fi
    return 1
  fi

  if (( warnings > 0 )); then
    if [[ "$mode" == "standalone" ]]; then
      print_summary "Required checks passed; $warnings optional check(s) need attention"
      print_action_required "${actions[@]}"
    else
      warn "Required checks passed; $warnings optional check(s) need attention"
    fi
    return 0
  fi

  if [[ "$mode" == "standalone" ]]; then
    print_summary "All checks passed; no action is required"
  else
    success "All health checks passed"
  fi
}
