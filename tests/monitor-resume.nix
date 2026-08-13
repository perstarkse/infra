{pkgs, ...}: let
  mockDdcutil = pkgs.writeShellScript "mock-ddcutil" ''
    set -euo pipefail
    printf '%s\n' "$*" >> "$DDC_LOG"
    if [[ " $* " == *" setvcp "* ]]; then
      if [[ " $* " == *" 01 "* ]]; then
        echo on > "$DDC_STATE"
      elif [[ " $* " == *" 05 "* ]]; then
        if [[ -n "''${DDC_OFF_SLEEP:-}" ]]; then
          sleep "$DDC_OFF_SLEEP"
        fi
        echo off > "$DDC_STATE"
      fi
      exit 0
    fi
    if [[ " $* " == *" getvcp "* ]]; then
      state=$(cat "$DDC_STATE" 2>/dev/null || echo off)
      if [[ "$state" == on ]]; then
        echo "VCP code 0xD6 (Power mode): DPM: On     (sl=0x01)"
      else
        echo "VCP code 0xD6 (Power mode): DPM: Off    (sl=0x05)"
      fi
      exit 0
    fi
    exit 0
  '';

  mockLogger = pkgs.writeShellScript "mock-logger" ''
    shift
    shift
    printf '%s\n' "$*" >> "$LOGGER_LOG"
  '';

  mockMonitorPower = pkgs.writeShellScript "mock-monitor-power" ''
    set -euo pipefail
    printf '%s\n' "$*" >> "$POWER_LOG"
    case "$1" in
      on) echo on > "$DDC_STATE" ;;
      off) echo off > "$DDC_STATE" ;;
      *) exit 2 ;;
    esac
  '';
in {
  monitor-resume-classification =
    pkgs.runCommand "monitor-resume-classification" {
      nativeBuildInputs = [pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gawk pkgs.python3];
      resumeSrc = ../modules/system/ddcutil/scripts/resume.sh;
      inputSrc = ../modules/system/ddcutil/scripts/physical-input.py;
      inputTest = ./monitor-physical-input.py;
    } ''
      set -euo pipefail

      work="$PWD/work"
      mkdir -p "$work"
      resume_bin="$work/monitor-resume"

      ${pkgs.gnused}/bin/sed \
        -e "s|^#!/usr/bin/env bash|#!${pkgs.bash}/bin/bash|" \
        -e "s#@DISPLAY_NUM@#1#g" \
        -e "s#@MAX_ATTEMPTS@#8#g" \
        -e "s#@RETRY_INTERVAL@#0.05#g" \
        -e "s#@MKDIR@#${pkgs.coreutils}/bin/mkdir#g" \
        -e "s#@DIRNAME@#${pkgs.coreutils}/bin/dirname#g" \
        -e "s#@GREP@#${pkgs.gnugrep}/bin/grep#g" \
        -e "s#@SLEEP@#${pkgs.coreutils}/bin/sleep#g" \
        -e "s#@LOGGER@#${mockLogger}#g" \
        -e "s#@SEQ@#${pkgs.coreutils}/bin/seq#g" \
        -e "s#@DDCUTIL@#${mockDdcutil}#g" \
        "$resumeSrc" > "$resume_bin"
      chmod +x "$resume_bin"

      reset_case() {
        : > "$work/ddc.log"
        : > "$work/logger.log"
        echo off > "$work/d6"
        rm -f "$work/policy"
      }

      assert_no_on() {
        if ${pkgs.gnugrep}/bin/grep -q 'setvcp --noverify D6 01' "$work/ddc.log"; then
          echo "FAIL $1: sent D6 01 (on)" >&2
          cat "$work/ddc.log" >&2
          cat "$work/logger.log" >&2
          exit 1
        fi
      }

      assert_off() {
        if ! ${pkgs.gnugrep}/bin/grep -q 'setvcp --noverify D6 05' "$work/ddc.log"; then
          echo "FAIL $1: did not send D6 05 (off)" >&2
          cat "$work/ddc.log" >&2
          cat "$work/logger.log" >&2
          exit 1
        fi
      }

      assert_on() {
        if ! ${pkgs.gnugrep}/bin/grep -q 'setvcp --noverify D6 01' "$work/ddc.log"; then
          echo "FAIL $1: did not send D6 01 (on)" >&2
          cat "$work/ddc.log" >&2
          cat "$work/logger.log" >&2
          exit 1
        fi
      }

      export DDC_LOG="$work/ddc.log"
      export DDC_STATE="$work/d6"
      export LOGGER_LOG="$work/logger.log"
      export MONITOR_POWER_POLICY="$work/policy"

      reset_case
      "$resume_bin"
      assert_no_on "resume-default"
      assert_off "resume-default"
      ${pkgs.gnugrep}/bin/grep -q 'display off after resume (until physical input)' "$work/logger.log"
      ${pkgs.gnugrep}/bin/grep -qx 'off-until-input' "$work/policy"

      reset_case
      printf 'on\n' > "$work/policy"
      "$resume_bin"
      assert_on "resume-physical"
      if ${pkgs.gnugrep}/bin/grep -q 'setvcp --noverify D6 05' "$work/ddc.log"; then
        echo "FAIL resume-physical: sent D6 05 (off)" >&2
        cat "$work/ddc.log" >&2
        exit 1
      fi
      ${pkgs.gnugrep}/bin/grep -q 'display on (physical input)' "$work/logger.log"

      reset_case
      export DDC_OFF_SLEEP=0.2
      (
        ${pkgs.coreutils}/bin/sleep 0.05
        printf 'on\n' > "$work/policy"
      ) &
      "$resume_bin"
      wait || true
      unset DDC_OFF_SLEEP
      assert_on "resume-input-during-off"
      ${pkgs.gnugrep}/bin/grep -q 'physical input during resume' "$work/logger.log"

      reset_case
      "$resume_bin" keep-awake
      assert_no_on "keep-awake-default"
      assert_off "keep-awake-default"
      ${pkgs.gnugrep}/bin/grep -q 'display off after keep-awake (until physical input)' "$work/logger.log"

      reset_case
      printf 'on\n' > "$work/policy"
      "$resume_bin" keep-awake
      assert_on "keep-awake-physical"
      if ${pkgs.gnugrep}/bin/grep -q 'setvcp --noverify D6 05' "$work/ddc.log"; then
        echo "FAIL keep-awake-physical: sent D6 05 (off)" >&2
        cat "$work/ddc.log" >&2
        exit 1
      fi

      export POWER_LOG="$work/power.log"
      export MONITOR_POWER_BIN="${mockMonitorPower}"
      : > "$work/power.log"
      echo off > "$work/d6"
      printf 'off-until-input\n' > "$work/policy"
      ${pkgs.python3}/bin/python3 "$inputTest" "$inputSrc"

      touch "$out"
    '';
}
