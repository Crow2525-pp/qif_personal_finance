#!/bin/sh
set -eu

if [ -n "${DAGSTER_HOME:-}" ]; then
  mkdir -p "$DAGSTER_HOME"
fi

if [ -n "${DAGSTER_APP:-}" ]; then
  SEED_DIR="${DAGSTER_APP}/data_projects/qif_personal_finance/pipeline_personal_finance/dbt_finance/seeds"
  TEMPLATE_DIR="${DAGSTER_APP}/data_projects/qif_personal_finance/pipeline_personal_finance/dbt_finance/seed_templates"
  QIF_DIR="${DAGSTER_APP}/data_projects/qif_personal_finance/pipeline_personal_finance/qif_files"

  mkdir -p "$SEED_DIR"
  mkdir -p "$QIF_DIR"

  if [ -d "$TEMPLATE_DIR" ]; then
    for template in "$TEMPLATE_DIR"/*.template.csv; do
      [ -e "$template" ] || continue
      filename="$(basename "$template" .template.csv).csv"
      target="${SEED_DIR}/${filename}"
      if [ ! -f "$target" ]; then
        cp "$template" "$target"
      fi
    done
  fi
fi

exec "$@"
