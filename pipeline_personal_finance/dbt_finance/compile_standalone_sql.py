#!/usr/bin/env python3
"""
Compile a dbt model into a standalone SQL query with all dependencies inlined as CTEs.

This script reads the dbt manifest.json, finds all upstream dependencies for a given model,
and generates a single SQL query with nested WITH statements that can run directly on the
warehouse without relying on materialized models.

Usage:
    python compile_standalone_sql.py <model_name> [--config substitutions.json] [--output query.sql]

Example:
    python compile_standalone_sql.py fct_transactions
    python compile_standalone_sql.py fct_transactions --config overrides.json --output standalone_query.sql
"""

import json
import argparse
import re
import sys
from pathlib import Path
from typing import Dict, Set, List, Optional, Tuple
from collections import defaultdict


class DbtModelCompiler:
    """Compiles dbt models into standalone SQL queries."""

    def __init__(self, manifest_path: str = "target/manifest.json", substitutions: Optional[Dict[str, str]] = None):
        """
        Initialize the compiler.

        Args:
            manifest_path: Path to dbt manifest.json
            substitutions: Dict mapping model unique_ids to replacement table references
        """
        self.manifest_path = Path(manifest_path)
        self.substitutions = substitutions or {}
        self.manifest = self._load_manifest()

    def _load_manifest(self) -> dict:
        """Load the dbt manifest file."""
        if not self.manifest_path.exists():
            raise FileNotFoundError(
                f"Manifest not found at {self.manifest_path}. "
                "Run 'dbt compile' first to generate the manifest."
            )

        with open(self.manifest_path) as f:
            return json.load(f)

    def _find_model_by_name(self, model_name: str) -> Optional[Tuple[str, dict]]:
        """
        Find a model in the manifest by its name.

        Args:
            model_name: Name of the model (e.g., 'fct_transactions')

        Returns:
            Tuple of (unique_id, node_dict) or None if not found
        """
        for node_id, node in self.manifest['nodes'].items():
            if node.get('resource_type') == 'model':
                # Match by name or alias
                if node.get('name') == model_name or node.get('alias') == model_name:
                    return (node_id, node)
        return None

    def _get_dependencies(self, node_id: str, visited: Optional[Set[str]] = None) -> List[str]:
        """
        Get all upstream dependencies for a node in topological order.

        Args:
            node_id: Unique ID of the node
            visited: Set of already visited nodes (for cycle detection)

        Returns:
            List of node IDs in topological order (dependencies first)
        """
        if visited is None:
            visited = set()

        if node_id in visited:
            return []

        visited.add(node_id)

        node = self.manifest['nodes'].get(node_id)
        if not node:
            # Could be a source
            return []

        dependencies = []
        depends_on = node.get('depends_on', {}).get('nodes', [])

        # Recursively get dependencies
        for dep_id in depends_on:
            # Skip if it's being substituted
            if dep_id in self.substitutions:
                continue

            # Only include models, skip sources
            if dep_id.startswith('model.'):
                dep_deps = self._get_dependencies(dep_id, visited)
                dependencies.extend(dep_deps)
                if dep_id not in dependencies:
                    dependencies.append(dep_id)

        return dependencies

    def _get_table_reference(self, node_id: str) -> str:
        """
        Get the fully qualified table reference for a node.

        Args:
            node_id: Unique ID of the node

        Returns:
            Fully qualified table name (e.g., "database"."schema"."table")
        """
        node = self.manifest['nodes'].get(node_id, {})
        database = node.get('database', 'personal_finance')
        schema = node.get('schema', 'public')
        alias = node.get('alias') or node.get('name', '')

        return f'"{database}"."{schema}"."{alias}"'

    def _get_cte_name(self, node_id: str) -> str:
        """
        Generate a CTE name from a node ID.

        Args:
            node_id: Unique ID of the node (e.g., 'model.personal_finance.int_categories')

        Returns:
            CTE name (e.g., 'int_categories')
        """
        node = self.manifest['nodes'].get(node_id, {})
        return node.get('alias') or node.get('name', node_id.split('.')[-1])

    def _replace_table_refs_with_cte(self, sql: str, node_id: str, cte_map: Dict[str, str]) -> str:
        """
        Replace table references in SQL with CTE names.

        Args:
            sql: The SQL code to process
            node_id: The node being processed (for logging)
            cte_map: Mapping of table references to CTE names

        Returns:
            SQL with table references replaced by CTE names
        """
        result = sql

        # Sort by length descending to replace longer matches first
        # This prevents partial replacements of nested schemas
        sorted_refs = sorted(cte_map.items(), key=lambda x: len(x[0]), reverse=True)

        for table_ref, cte_name in sorted_refs:
            # Match the table reference followed by whitespace or end of string
            # This ensures we don't partially match table references
            pattern = re.escape(table_ref) + r'(?=\s|$)'
            result = re.sub(pattern, cte_name, result, flags=re.IGNORECASE)

        return result

    def _flatten_cte(self, sql: str, parent_cte_name: str) -> Tuple[List[Tuple[str, str]], str]:
        """
        Flatten a SQL query that contains internal WITH clauses.

        If the SQL has a WITH clause with internal CTEs, this extracts them
        and returns them separately along with the final SELECT.

        Args:
            sql: The SQL code to flatten
            parent_cte_name: Name of the parent CTE (for prefixing internal CTEs)

        Returns:
            Tuple of (list of (cte_name, cte_sql) tuples, final_select_sql)
        """
        # Check if SQL starts with WITH (case-insensitive)
        sql_stripped = sql.strip()
        if not re.match(r'^\s*WITH\s+', sql_stripped, re.IGNORECASE):
            # No internal WITH clause, return as-is
            return ([], sql)

        # Extract the WITH clause and the final SELECT
        # This is a simplified parser - it looks for the pattern:
        # WITH cte1 AS (...), cte2 AS (...) SELECT ...

        internal_ctes = []
        remaining_sql = sql_stripped

        # Remove the WITH keyword
        remaining_sql = re.sub(r'^\s*WITH\s+', '', remaining_sql, count=1, flags=re.IGNORECASE)

        # Now we need to extract CTEs one by one
        # This is challenging because CTEs can have nested parentheses
        # We'll use a simple approach: track parentheses depth

        while remaining_sql:
            # Skip comments and whitespace
            remaining_sql = re.sub(r'^\s*(--[^\n]*\n\s*)*', '', remaining_sql)

            # Match CTE name
            match = re.match(r'^\s*(\w+)\s+AS\s*\(', remaining_sql, re.IGNORECASE)
            if not match:
                # No more CTEs, the rest is the final SELECT
                break

            cte_name = match.group(1)
            remaining_sql = remaining_sql[match.end():]

            # Find the matching closing paren
            depth = 1
            pos = 0
            while pos < len(remaining_sql) and depth > 0:
                if remaining_sql[pos] == '(':
                    depth += 1
                elif remaining_sql[pos] == ')':
                    depth -= 1
                pos += 1

            if depth != 0:
                # Couldn't find matching paren, return original SQL
                return ([], sql)

            cte_sql = remaining_sql[:pos-1]
            remaining_sql = remaining_sql[pos:]

            # Skip comma if present
            remaining_sql = re.sub(r'^\s*,\s*', '', remaining_sql)

            # Recursively flatten this CTE if it also has internal WITH clauses
            prefixed_name = f"{parent_cte_name}__{cte_name}"
            nested_ctes, flattened_cte_sql = self._flatten_cte(cte_sql, prefixed_name)

            # Add nested CTEs first
            internal_ctes.extend(nested_ctes)

            # Then add this CTE
            internal_ctes.append((prefixed_name, flattened_cte_sql))

        # remaining_sql should now contain the final SELECT
        # We need to replace references to internal CTE names with prefixed names
        # This replacement needs to happen in:
        # 1. The final SELECT query
        # 2. All internal CTEs that might reference each other

        # Build a map of original names to prefixed names
        name_map = {}
        for prefixed_name, _ in internal_ctes:
            # Extract original name (after the last __)
            parts = prefixed_name.split('__')
            if len(parts) >= 2:
                original_name = parts[-1]
                name_map[original_name] = prefixed_name

        # Replace references in all internal CTEs
        updated_internal_ctes = []
        for cte_name, cte_sql in internal_ctes:
            updated_sql = cte_sql
            for original_name, prefixed_name in name_map.items():
                # Use word boundary to avoid partial matches
                updated_sql = re.sub(
                    r'\b' + re.escape(original_name) + r'\b',
                    prefixed_name,
                    updated_sql,
                    flags=re.IGNORECASE
                )
            updated_internal_ctes.append((cte_name, updated_sql))

        # Replace references in the final SELECT
        final_sql = remaining_sql
        for original_name, prefixed_name in name_map.items():
            final_sql = re.sub(
                r'\b' + re.escape(original_name) + r'\b',
                prefixed_name,
                final_sql,
                flags=re.IGNORECASE
            )

        return (updated_internal_ctes, final_sql)

    def compile_model(self, model_name: str, output_path: Optional[str] = None) -> str:
        """
        Compile a model into a standalone SQL query.

        Args:
            model_name: Name of the model to compile
            output_path: Optional path to write the output SQL file

        Returns:
            The compiled standalone SQL query
        """
        # Find the model
        result = self._find_model_by_name(model_name)
        if not result:
            raise ValueError(f"Model '{model_name}' not found in manifest")

        main_node_id, main_node = result

        # Get all dependencies in topological order
        dependencies = self._get_dependencies(main_node_id)

        print(f"Compiling model: {model_name}", file=sys.stderr)
        print(f"Found {len(dependencies)} dependencies", file=sys.stderr)

        # Build CTE map (table reference -> CTE name or substitution)
        cte_map = {}

        # First, add all substitutions to the map (even if not in dependencies)
        # This ensures substituted models are replaced everywhere they're referenced
        for sub_node_id, sub_table in self.substitutions.items():
            original_ref = self._get_table_reference(sub_node_id)
            cte_map[original_ref] = sub_table

        # Then add all dependencies
        for dep_id in dependencies:
            # Skip if already handled by substitutions
            if dep_id in self.substitutions:
                continue
            # Map the original table reference to the CTE name
            original_ref = self._get_table_reference(dep_id)
            cte_name = self._get_cte_name(dep_id)
            cte_map[original_ref] = cte_name

        # Also map the main model's own reference if it's used (for recursive CTEs)
        main_table_ref = self._get_table_reference(main_node_id)

        # Build the SQL query with CTEs
        sql_parts = []

        # Add header comment
        sql_parts.append(f"-- Standalone SQL for model: {model_name}")
        sql_parts.append(f"-- Generated by compile_standalone_sql.py")
        sql_parts.append(f"-- Dependencies: {', '.join([self._get_cte_name(d) for d in dependencies])}")
        sql_parts.append("")

        # Build WITH clause with all dependencies
        # We need to flatten any internal WITH clauses to avoid nested CTEs
        all_ctes = []

        if dependencies:
            for dep_id in dependencies:
                dep_node = self.manifest['nodes'][dep_id]
                cte_name = self._get_cte_name(dep_id)

                # Get compiled SQL for the dependency
                compiled_sql = dep_node.get('compiled_code', dep_node.get('raw_code', ''))
                if not compiled_sql:
                    print(f"Warning: No compiled code for {dep_id}", file=sys.stderr)
                    continue

                # Replace table references in this dependency's SQL
                compiled_sql = self._replace_table_refs_with_cte(compiled_sql, dep_id, cte_map)

                # Flatten any internal WITH clauses
                internal_ctes, final_sql = self._flatten_cte(compiled_sql, cte_name)

                # Add internal CTEs first
                for internal_cte_name, internal_cte_sql in internal_ctes:
                    # Replace table refs in internal CTEs too
                    internal_cte_sql = self._replace_table_refs_with_cte(internal_cte_sql, dep_id, cte_map)
                    all_ctes.append((internal_cte_name, internal_cte_sql))

                # Then add the main CTE (which now references internal CTEs by prefixed names)
                all_ctes.append((cte_name, final_sql))

        # Now write all CTEs
        if all_ctes:
            sql_parts.append("WITH")

            for i, (cte_name, cte_sql) in enumerate(all_ctes):
                # Indent the SQL
                indented_sql = '\n'.join('    ' + line for line in cte_sql.strip().split('\n'))

                # Add CTE
                sql_parts.append(f"{cte_name} AS (")
                sql_parts.append(indented_sql)
                sql_parts.append(")" + ("," if i < len(all_ctes) - 1 else ""))
                sql_parts.append("")

        # Add the main query
        main_sql = main_node.get('compiled_code', main_node.get('raw_code', ''))

        # Replace table references in the main query
        main_sql = self._replace_table_refs_with_cte(main_sql, main_node_id, cte_map)

        # Flatten the main query if it also has internal WITH clauses
        main_internal_ctes, main_final_sql = self._flatten_cte(main_sql, f"{model_name}_main")

        # If the main query has internal CTEs, add them to our CTE list
        if main_internal_ctes:
            # We already have CTEs, so we need to add more CTEs with commas
            if all_ctes:
                # Add comma to the last existing CTE
                sql_parts[-2] = sql_parts[-2].rstrip() + ","
                sql_parts.append("")

            # Add main query's internal CTEs
            for i, (cte_name, cte_sql) in enumerate(main_internal_ctes):
                # Replace table refs in these CTEs too
                cte_sql = self._replace_table_refs_with_cte(cte_sql, main_node_id, cte_map)

                # Indent the SQL
                indented_sql = '\n'.join('    ' + line for line in cte_sql.strip().split('\n'))

                # Add CTE
                sql_parts.append(f"{cte_name} AS (")
                sql_parts.append(indented_sql)
                sql_parts.append(")")  # Last one doesn't have comma
                if i < len(main_internal_ctes) - 1:
                    sql_parts[-1] += ","
                sql_parts.append("")

            # Use the flattened final SQL
            main_sql = main_final_sql

        sql_parts.append(main_sql.strip())

        # Combine all parts
        final_sql = '\n'.join(sql_parts)

        # Write to file if specified
        if output_path:
            output_file = Path(output_path)
            output_file.write_text(final_sql)
            print(f"Wrote standalone SQL to: {output_path}", file=sys.stderr)

        return final_sql


def load_substitutions(config_path: str) -> Dict[str, str]:
    """
    Load substitutions from a JSON config file.

    The config file should have this structure:
    {
        "substitutions": {
            "model_name": "replacement_table_reference",
            "int_categories": "custom_schema.my_categories"
        }
    }

    Or you can use full unique IDs:
    {
        "substitutions": {
            "model.personal_finance.int_categories": "custom_schema.my_categories"
        }
    }
    """
    config_file = Path(config_path)
    if not config_file.exists():
        raise FileNotFoundError(f"Config file not found: {config_path}")

    with open(config_file) as f:
        config = json.load(f)

    return config.get('substitutions', {})


def main():
    parser = argparse.ArgumentParser(
        description="Compile a dbt model into a standalone SQL query with inline CTEs"
    )
    parser.add_argument(
        "model_name",
        help="Name of the dbt model to compile (e.g., 'fct_transactions')"
    )
    parser.add_argument(
        "--manifest",
        default="target/manifest.json",
        help="Path to dbt manifest.json (default: target/manifest.json)"
    )
    parser.add_argument(
        "--config",
        help="Path to JSON config file with substitutions"
    )
    parser.add_argument(
        "--output",
        help="Path to write the output SQL file (default: print to stdout)"
    )

    args = parser.parse_args()

    # Load substitutions if config provided
    substitutions = {}
    if args.config:
        substitutions = load_substitutions(args.config)
        print(f"Loaded {len(substitutions)} substitutions from config", file=sys.stderr)

    # Create compiler and compile the model
    compiler = DbtModelCompiler(
        manifest_path=args.manifest,
        substitutions=substitutions
    )

    try:
        sql = compiler.compile_model(args.model_name, args.output)

        # Print to stdout if no output file specified
        if not args.output:
            print(sql)

        print(f"\nSuccess! Compiled {args.model_name}", file=sys.stderr)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
