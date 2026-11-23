#!/usr/bin/env bash
#
# The setup step list. `dot setup` and `dot upgrade` run the installers below,
# and `dot check` runs the checks for the same rows, so the health check always
# covers exactly what setup installs. Add new setup work here as a row; do not
# call installers directly from `dot`.
#
# One row per step, in setup order. Fields are separated by `|`; surrounding
# spaces are ignored.
#
#   name      Step name. Doctor prints "Checking <name>".
#   check     Read-only check. Print one short success or warn line (details
#             may add more warn lines), then return 0 when healthy, else 1.
#             Never print the action; doctor does that.
#   install   Installer run by `dot setup`. Prints its own progress.
#   upgrade   Function run by `dot upgrade`: `-` reuses the installer, `skip`
#             leaves the step to `dot setup`.
#   needs     Name of an earlier step that must not have failed in this run,
#             or `-`. A failed dependency skips this installer; the failed
#             step reports what it skipped.
#   required  `yes`: a failed check fails `dot check`. `no`: doctor warns and
#             lists the action but still passes.
#   action    Shown under "Action required" when the check fails. Doctor lists
#             each distinct action once.
#
# Platform differences stay behind platform_* functions. A backend that has no
# work for a step returns 0 from `platform_skips_step <name>`; setup, upgrade,
# and doctor then ignore that row on that platform.

DOT_STEPS=(
  "prerequisites   | check_required_tools       | platform_prepare                 | skip                     | -             | yes | Install missing tools: dot setup"
  "packages        | check_declared_packages    | platform_install_packages        | platform_update_packages | prerequisites | yes | Reconcile packages: dot upgrade"
  "runtime manager | check_runtime_manager      | platform_install_runtime_manager | -                        | -             | yes | Install the asdf runtime manager: dot setup"
  "Pi              | check_pi                   | install_pi                       | -                        | -             | yes | Reinstall or update Pi: dot upgrade"
  "shell           | platform_check_shell       | platform_install_shell           | skip                     | -             | yes | Install shell dependencies: dot setup"
  "home links      | check_managed_links        | install_home_links               | -                        | -             | yes | Repair managed links: dot apply home"
  "Pi settings     | check_pi_settings          | apply_pi_settings                | -                        | Pi            | yes | Apply shared Pi settings: dot apply home"
  "dot command     | check_dot_command          | link_dot_command                 | skip                     | -             | no  | Link the dot command: dot setup"
  "git hooks       | check_git_hooks            | configure_git_hooks              | -                        | -             | no  | Configure repository hooks: dot setup"
)

# Set by cmd_setup; stow_home archives legacy Pi skills when 1.
DOT_ARCHIVE_LEGACY_SKILLS=0

step_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

# Split a row into STEP_NAME, STEP_CHECK, STEP_INSTALL, STEP_UPGRADE,
# STEP_NEEDS, STEP_REQUIRED, and STEP_ACTION.
# shellcheck disable=SC2034 # Callers in other files read the STEP_* globals.
step_parse() {
  local name check install upgrade needs required action
  IFS='|' read -r name check install upgrade needs required action <<<"$1"
  STEP_NAME="$(step_trim "$name")"
  STEP_CHECK="$(step_trim "$check")"
  STEP_INSTALL="$(step_trim "$install")"
  STEP_UPGRADE="$(step_trim "$upgrade")"
  STEP_NEEDS="$(step_trim "$needs")"
  STEP_REQUIRED="$(step_trim "$required")"
  STEP_ACTION="$(step_trim "$action")"
  [[ "$STEP_UPGRADE" != - ]] || STEP_UPGRADE="$STEP_INSTALL"
}

# Run every step's installer (`install`) or upgrader (`upgrade`) and continue
# past failures. Sets DOT_STEP_FAILURES; returns 1 when any step failed.
run_steps() {
  local mode="$1" row fn failed='|'
  DOT_STEP_FAILURES=0

  for row in "${DOT_STEPS[@]}"; do
    step_parse "$row"
    platform_skips_step "$STEP_NAME" && continue

    fn="$STEP_INSTALL"
    [[ "$mode" != upgrade ]] || fn="$STEP_UPGRADE"
    [[ "$fn" != skip ]] || continue

    [[ "$failed" != *"|${STEP_NEEDS}|"* ]] || continue

    if ! "$fn"; then
      ((DOT_STEP_FAILURES += 1))
      failed+="${STEP_NAME}|"
    fi
  done

  (( DOT_STEP_FAILURES == 0 ))
}

install_home_links() {
  stow_home "$DOT_ARCHIVE_LEGACY_SKILLS"
}

check_required_tools() {
  local tool missing=0
  while IFS= read -r tool; do
    [[ -n "$tool" ]] || continue
    if command_exists "$tool"; then
      success "$tool is available"
    else
      warn "$tool is missing"
      missing=1
    fi
  done < <(platform_required_tools)
  (( missing == 0 ))
}

check_declared_packages() {
  local output label="Declared packages"
  if ! platform_packages_checkable; then
    skipped "Packages cannot be checked until prerequisites are installed"
    return 0
  fi
  if platform_supports_profiles; then
    label="Packages for the $(current_profile) profile"
  fi
  if output="$(platform_check_packages 2>&1)"; then
    success "$label are installed"
    return 0
  fi
  printf '%s\n' "$output" >&2
  warn "One or more declared packages are missing or outdated"
  return 1
}

check_runtime_manager() {
  if command_exists asdf; then
    success "asdf is available"
  else
    warn "asdf is not on PATH"
    return 1
  fi
}

check_pi() {
  if check_pi_install; then
    success "Pi $(pi_version) uses Node $(pi_node_version)"
  else
    warn "Pi installation is missing or broken"
    return 1
  fi
}

# shellcheck disable=SC2088 # "~/" is display text, not a path.
check_managed_links() {
  local source relative target checked=0 healthy=0
  while IFS= read -r source; do
    ((checked += 1))
    relative="${source#"${DOT_HOME_DIR}"/}"
    target="${HOME}/${relative}"

    if [[ ! -L "$target" ]]; then
      warn "~/${relative} is not a symlink"
    elif [[ ! -e "$target" ]]; then
      warn "~/${relative} is a broken symlink"
    elif [[ ! "$target" -ef "$source" ]]; then
      warn "~/${relative} points outside this repository"
    else
      ((healthy += 1))
    fi
  done < <(managed_home_files)

  if (( checked == 0 )); then
    warn "No managed files were found; restore the home/ tree from Git"
    return 1
  fi
  if (( healthy != checked )); then
    warn "$((checked - healthy)) of $checked managed links need attention"
    return 1
  fi
  success "$checked managed links are correct"
}

# shellcheck disable=SC2088 # "~/" is display text, not a path.
check_dot_command() {
  local target="${HOME}/.local/bin/dot"
  if [[ -L "$target" && "$target" -ef "${DOT_ROOT}/dot" ]]; then
    success "dot command is linked"
  else
    warn "~/.local/bin/dot does not link to this repository"
    return 1
  fi
}

check_git_hooks() {
  if [[ "$(git -C "$DOT_ROOT" config core.hooksPath 2>/dev/null)" == .githooks ]]; then
    success "Repository hooks are configured"
  else
    warn "Repository hooks are not configured"
    return 1
  fi
}
