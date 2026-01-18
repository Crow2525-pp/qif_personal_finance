#!/usr/bin/env python3
"""
Interactive Transaction Categorization Tool

Asks smart questions about uncategorized transactions to maximize categorization
impact with minimal user effort. Groups similar transactions and prioritizes
by total spend to get the most value from each answer.

Usage:
    uv run python scripts/categorize_transactions.py [--limit N] [--dry-run] [--host HOST]

Examples:
    uv run python scripts/categorize_transactions.py --host 192.168.1.103
    uv run python scripts/categorize_transactions.py --limit 10 --dry-run
"""

import os
import sys
import csv
import re
import argparse
from pathlib import Path
from dataclasses import dataclass
from typing import Optional

# Global for CLI-specified host
DB_HOST_OVERRIDE: Optional[str] = None

# Add project root to path for imports
PROJECT_ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

try:
    import psycopg2
    from psycopg2.extras import RealDictCursor
except ImportError:
    print("Error: psycopg2 not installed. Run: pip install psycopg2-binary")
    sys.exit(1)

# Paths
SEEDS_DIR = PROJECT_ROOT / "pipeline_personal_finance" / "dbt_finance" / "seeds" / "local"
CATEGORIES_FILE = SEEDS_DIR / "banking_categories.csv"
ALLOWED_CATEGORIES_FILE = SEEDS_DIR / "categories_allowed.csv"


@dataclass
class UncategorizedGroup:
    """A group of similar uncategorized transactions."""
    memo_pattern: str  # The pattern to match in banking_categories
    sample_memo: str   # Example transaction memo for display
    normalized_memo: str
    txn_count: int
    total_spend: float
    accounts: list[str]
    impact_score: float  # txn_count * total_spend for prioritization
    suggested_category: Optional[str] = None
    suggested_subcategory: Optional[str] = None
    confidence: Optional[float] = None


@dataclass
class Category:
    """A category with its subcategories."""
    name: str
    subcategories: list[str]
    display_order: int


def load_env():
    """Load environment variables from .env file."""
    env_file = PROJECT_ROOT / ".env"
    if env_file.exists():
        with open(env_file) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    os.environ.setdefault(key.strip(), value.strip())


def get_db_connection():
    """Create database connection from environment or CLI override."""
    global DB_HOST_OVERRIDE
    load_env()

    # If host was specified on command line, use it directly
    if DB_HOST_OVERRIDE:
        return psycopg2.connect(
            host=DB_HOST_OVERRIDE,
            port=os.environ.get('DAGSTER_POSTGRES_PORT', '5432'),
            database=os.environ.get('DAGSTER_POSTGRES_DB', 'personal_finance'),
            user=os.environ.get('DAGSTER_POSTGRES_USER', 'postgres'),
            password=os.environ.get('DAGSTER_POSTGRES_PASSWORD', '')
        )

    # Determine hosts to try (production server, then localhost)
    hosts_to_try = ['192.168.1.103', 'localhost']

    last_error = None
    for try_host in hosts_to_try:
        try:
            conn = psycopg2.connect(
                host=try_host,
                port=os.environ.get('DAGSTER_POSTGRES_PORT', '5432'),
                database=os.environ.get('DAGSTER_POSTGRES_DB', 'personal_finance'),
                user=os.environ.get('DAGSTER_POSTGRES_USER', 'postgres'),
                password=os.environ.get('DAGSTER_POSTGRES_PASSWORD', '')
            )
            print(f"  Connected to database at {try_host}")
            return conn
        except psycopg2.OperationalError as e:
            last_error = e
            continue

    print(f"\nError: Could not connect to database.")
    print(f"Tried hosts: {', '.join(hosts_to_try)}")
    print(f"Use --host to specify the database server address.")
    raise last_error


def load_categories() -> list[Category]:
    """Load allowed categories from the local CSV file (source of truth)."""
    # Read categories from the seed CSV file directly
    categories = {}
    if ALLOWED_CATEGORIES_FILE.exists():
        with open(ALLOWED_CATEGORIES_FILE, 'r', newline='', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                cat_name = row['category']
                if cat_name != 'Uncategorized':
                    categories[cat_name] = Category(
                        name=cat_name,
                        subcategories=[],
                        display_order=int(row['display_order'])
                    )

    # Get subcategories from existing banking_categories.csv
    if CATEGORIES_FILE.exists():
        with open(CATEGORIES_FILE, 'r', newline='', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                cat = row.get('category')
                subcat = row.get('subcategory')
                if cat and subcat and cat in categories:
                    if subcat not in categories[cat].subcategories:
                        categories[cat].subcategories.append(subcat)

    # Sort subcategories
    for cat in categories.values():
        cat.subcategories.sort()

    # Return sorted by display_order
    return sorted(categories.values(), key=lambda c: c.display_order)


def get_uncategorized_groups(limit: int = 50) -> list[UncategorizedGroup]:
    """
    Get uncategorized transactions grouped by normalized memo,
    prioritized by impact (spend × count).
    """
    conn = get_db_connection()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("""
                WITH uncategorized AS (
                    SELECT
                        ft.transaction_memo,
                        ft.transaction_description,
                        ABS(ft.transaction_amount) as amount,
                        da.account_name,
                        -- Normalize memo for grouping
                        UPPER(
                            REGEXP_REPLACE(
                                REGEXP_REPLACE(
                                    REGEXP_REPLACE(
                                        REGEXP_REPLACE(
                                            COALESCE(ft.transaction_description, ft.transaction_memo),
                                            'Receipt\\s+[0-9]+', '', 'gi'
                                        ),
                                        'Date\\s+\\d{2}\\s+[A-Za-z]{3}\\s+\\d{4}', '', 'gi'
                                    ),
                                    'Card\\s+[\\dx]+', '', 'gi'
                                ),
                                '[0-9]+', '', 'g'
                            )
                        ) AS memo_norm
                    FROM reporting.fct_transactions ft
                    JOIN reporting.dim_categories dc ON ft.category_key = dc.category_key
                    JOIN reporting.dim_accounts da ON ft.account_key = da.account_key
                    WHERE dc.category = 'Uncategorized'
                        AND COALESCE(ft.transaction_description, ft.transaction_memo) IS NOT NULL
                        AND LENGTH(TRIM(COALESCE(ft.transaction_description, ft.transaction_memo))) > 2
                ),
                grouped AS (
                    SELECT
                        memo_norm,
                        MIN(COALESCE(transaction_description, transaction_memo)) AS sample_memo,
                        COUNT(*) AS txn_count,
                        SUM(amount) AS total_spend,
                        ARRAY_AGG(DISTINCT account_name) AS accounts
                    FROM uncategorized
                    WHERE memo_norm IS NOT NULL AND LENGTH(TRIM(memo_norm)) > 2
                    GROUP BY memo_norm
                ),
                -- Get suggestions from existing categorized transactions
                suggestions AS (
                    SELECT
                        UPPER(
                            REGEXP_REPLACE(
                                REGEXP_REPLACE(
                                    REGEXP_REPLACE(
                                        REGEXP_REPLACE(
                                            COALESCE(ft.transaction_description, ft.transaction_memo),
                                            'Receipt\\s+[0-9]+', '', 'gi'
                                        ),
                                        'Date\\s+\\d{2}\\s+[A-Za-z]{3}\\s+\\d{4}', '', 'gi'
                                    ),
                                    'Card\\s+[\\dx]+', '', 'gi'
                                ),
                                '[0-9]+', '', 'g'
                            )
                        ) AS memo_norm,
                        dc.category,
                        dc.subcategory,
                        COUNT(*) as support
                    FROM reporting.fct_transactions ft
                    JOIN reporting.dim_categories dc ON ft.category_key = dc.category_key
                    WHERE dc.category != 'Uncategorized'
                    GROUP BY 1, 2, 3
                ),
                ranked_suggestions AS (
                    SELECT
                        memo_norm,
                        category,
                        subcategory,
                        support,
                        SUM(support) OVER (PARTITION BY memo_norm) as total_support,
                        ROW_NUMBER() OVER (PARTITION BY memo_norm ORDER BY support DESC) as rn
                    FROM suggestions
                )
                SELECT
                    g.memo_norm,
                    g.sample_memo,
                    g.txn_count,
                    g.total_spend,
                    g.accounts,
                    g.txn_count * g.total_spend AS impact_score,
                    rs.category AS suggested_category,
                    rs.subcategory AS suggested_subcategory,
                    CASE WHEN rs.total_support > 0
                         THEN rs.support::float / rs.total_support
                         ELSE NULL END AS confidence
                FROM grouped g
                LEFT JOIN ranked_suggestions rs ON rs.memo_norm = g.memo_norm AND rs.rn = 1
                ORDER BY impact_score DESC
                LIMIT %s
            """, (limit,))

            results = []
            for row in cur.fetchall():
                # Create a pattern from the sample memo - extract key identifying parts
                pattern = extract_pattern(row['sample_memo'])

                results.append(UncategorizedGroup(
                    memo_pattern=pattern,
                    sample_memo=row['sample_memo'],
                    normalized_memo=row['memo_norm'],
                    txn_count=row['txn_count'],
                    total_spend=float(row['total_spend']),
                    accounts=row['accounts'],
                    impact_score=float(row['impact_score']),
                    suggested_category=row['suggested_category'],
                    suggested_subcategory=row['suggested_subcategory'],
                    confidence=float(row['confidence']) if row['confidence'] else None
                ))

            return results
    finally:
        conn.close()


def extract_pattern(memo: str) -> str:
    """
    Extract a matching pattern from a transaction memo.
    Removes variable parts (dates, receipt numbers, card numbers) but keeps
    the identifying merchant/description part.
    """
    if not memo:
        return ""

    # Remove common variable suffixes
    pattern = memo.strip()

    # Remove receipt numbers
    pattern = re.sub(r'\s*Receipt\s+\d+', '', pattern, flags=re.IGNORECASE)
    # Remove dates
    pattern = re.sub(r'\s*Date\s+\d{2}\s+[A-Za-z]{3}\s+\d{4}', '', pattern, flags=re.IGNORECASE)
    # Remove card numbers
    pattern = re.sub(r'\s*Card\s+[\dxX]+', '', pattern, flags=re.IGNORECASE)
    # Remove trailing numbers (often transaction refs)
    pattern = re.sub(r'\s+\d{4,}$', '', pattern)
    # Remove AU/AUS suffix
    pattern = re.sub(r'\s+(AU|AUS|AUD)\s*$', '', pattern, flags=re.IGNORECASE)

    return pattern.strip()


def display_group(group: UncategorizedGroup, index: int):
    """Display an uncategorized transaction group for user review."""
    print(f"\n{'='*60}")
    print(f"Question {index}: What category is this?")
    print(f"{'='*60}")
    print(f"  Sample: {group.sample_memo}")
    print(f"  Matches: {group.txn_count} transactions totaling ${group.total_spend:,.2f}")
    print(f"  Accounts: {', '.join(group.accounts)}")

    if group.suggested_category and group.confidence:
        confidence_pct = group.confidence * 100
        print(f"  -> Suggestion: {group.suggested_category}/{group.suggested_subcategory} ({confidence_pct:.0f}% confidence)")


def prompt_category(categories: list[Category], suggestion: Optional[str] = None) -> tuple[str, str]:
    """
    Prompt user to select a category and subcategory.
    Returns (category, subcategory) tuple.
    """
    print("\nCategories:")
    for i, cat in enumerate(categories, 1):
        marker = " ⭐" if cat.name == suggestion else ""
        print(f"  {i}. {cat.name}{marker}")
    print(f"  s. Skip this transaction")
    print(f"  q. Quit and save")

    while True:
        choice = input("\nSelect category [1-{}], s to skip, q to quit: ".format(len(categories))).strip().lower()

        if choice == 's':
            return ('SKIP', '')
        if choice == 'q':
            return ('QUIT', '')

        try:
            idx = int(choice) - 1
            if 0 <= idx < len(categories):
                selected_cat = categories[idx]
                break
        except ValueError:
            pass
        print("Invalid choice. Please try again.")

    # Prompt for subcategory
    print(f"\nSubcategories for {selected_cat.name}:")
    for i, subcat in enumerate(selected_cat.subcategories, 1):
        print(f"  {i}. {subcat}")
    print(f"  n. New subcategory")

    while True:
        choice = input(f"\nSelect subcategory [1-{len(selected_cat.subcategories)}] or 'n' for new: ").strip().lower()

        if choice == 'n':
            subcategory = input("Enter new subcategory name: ").strip()
            if subcategory:
                return (selected_cat.name, subcategory)
            print("Subcategory cannot be empty.")
            continue

        try:
            idx = int(choice) - 1
            if 0 <= idx < len(selected_cat.subcategories):
                return (selected_cat.name, selected_cat.subcategories[idx])
        except ValueError:
            pass

        # If no subcategories exist, allow any input
        if not selected_cat.subcategories:
            subcategory = input("Enter subcategory name: ").strip()
            if subcategory:
                return (selected_cat.name, subcategory)

        print("Invalid choice. Please try again.")


def prompt_store(sample_memo: str) -> str:
    """Prompt user for store/merchant name."""
    # Try to extract a sensible default
    default = extract_pattern(sample_memo).split()[0] if sample_memo else ""

    prompt = f"Store/Merchant name [{default}]: " if default else "Store/Merchant name: "
    store = input(prompt).strip()

    return store if store else default


def load_existing_mappings() -> list[dict]:
    """Load existing category mappings from CSV."""
    mappings = []
    if CATEGORIES_FILE.exists():
        with open(CATEGORIES_FILE, 'r', newline='', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            mappings = list(reader)
    return mappings


def save_mappings(mappings: list[dict]):
    """Save category mappings to CSV."""
    if not mappings:
        return

    fieldnames = [
        'transaction_description', 'transaction_type', 'sender', 'recipient',
        'account_name', 'category', 'subcategory', 'store', 'internal_indicator'
    ]

    with open(CATEGORIES_FILE, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(mappings)


def get_accounts() -> list[str]:
    """Get list of account names from database."""
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT DISTINCT account_name FROM reporting.dim_accounts ORDER BY account_name")
            return [row[0] for row in cur.fetchall()]
    finally:
        conn.close()


def add_mapping(mappings: list[dict], pattern: str, category: str, subcategory: str,
                store: str, accounts: list[str]):
    """Add new mapping entries for all relevant accounts."""
    for account in accounts:
        # Check if mapping already exists
        exists = any(
            m['transaction_description'] == pattern and
            m['account_name'] == account
            for m in mappings
        )
        if not exists:
            mappings.append({
                'transaction_description': pattern,
                'transaction_type': '',
                'sender': '',
                'recipient': '',
                'account_name': account,
                'category': category,
                'subcategory': subcategory,
                'store': store,
                'internal_indicator': 'External'
            })


def main():
    global DB_HOST_OVERRIDE

    parser = argparse.ArgumentParser(
        description='Interactive transaction categorization tool'
    )
    parser.add_argument('--limit', type=int, default=20,
                        help='Maximum number of transaction groups to process (default: 20)')
    parser.add_argument('--dry-run', action='store_true',
                        help='Preview changes without saving')
    parser.add_argument('--host', type=str, default=None,
                        help='Database host (default: tries 192.168.1.103, then localhost)')
    parser.add_argument('--test-connection', action='store_true',
                        help='Test database connection and exit')
    args = parser.parse_args()

    if args.host:
        DB_HOST_OVERRIDE = args.host

    # Test connection mode
    if args.test_connection:
        print("Testing database connection...")
        try:
            conn = get_db_connection()
            with conn.cursor() as cur:
                cur.execute("SELECT COUNT(*) FROM reporting.fct_transactions")
                count = cur.fetchone()[0]
                print(f"[OK] Connected successfully! Found {count:,} transactions.")
            conn.close()
        except Exception as e:
            print(f"[ERROR] Connection failed: {e}")
        return

    print("=" * 60)
    print("  Transaction Categorization Tool")
    print("  Prioritized by impact - answer a few questions to")
    print("  categorize many transactions!")
    print("=" * 60)

    # Load data
    print("\nLoading categories...")
    categories = load_categories()

    print("Loading uncategorized transactions...")
    groups = get_uncategorized_groups(limit=args.limit)

    if not groups:
        print("\n[OK] No uncategorized transactions found! Your data is clean.")
        return

    total_uncategorized = sum(g.txn_count for g in groups)
    total_spend = sum(g.total_spend for g in groups)
    print(f"\nFound {len(groups)} transaction groups ({total_uncategorized} transactions, ${total_spend:,.2f})")

    # Load existing mappings
    mappings = load_existing_mappings()
    print(f"Loaded {len(mappings)} existing category mappings")

    # Get all accounts for mapping
    all_accounts = get_accounts()

    # Interactive categorization loop
    categorized = 0
    transactions_categorized = 0

    for i, group in enumerate(groups, 1):
        display_group(group, i)

        result = prompt_category(categories, group.suggested_category)
        category, subcategory = result

        if category == 'QUIT':
            print("\nSaving and exiting...")
            break

        if category == 'SKIP':
            print("Skipped.")
            continue

        # Get store name
        store = prompt_store(group.sample_memo)

        # Confirm
        print(f"\n  → {group.memo_pattern}")
        print(f"    Category: {category} / {subcategory}")
        print(f"    Store: {store}")
        print(f"    Will categorize: {group.txn_count} transactions (${group.total_spend:,.2f})")

        confirm = input("  Confirm? [Y/n]: ").strip().lower()
        if confirm in ('', 'y', 'yes'):
            # Add mapping for all accounts where this appears
            add_mapping(mappings, group.memo_pattern, category, subcategory, store, all_accounts)
            categorized += 1
            transactions_categorized += group.txn_count
            print(f"  [OK] Added!")
        else:
            print("  Skipped.")

    # Summary
    print(f"\n{'='*60}")
    print(f"  Session Summary")
    print(f"{'='*60}")
    print(f"  Patterns categorized: {categorized}")
    print(f"  Transactions covered: {transactions_categorized}")

    if categorized > 0:
        if args.dry_run:
            print(f"\n  [DRY RUN] Would save {len(mappings)} mappings to:")
            print(f"  {CATEGORIES_FILE}")
        else:
            save_mappings(mappings)
            print(f"\n  [OK] Saved {len(mappings)} mappings to:")
            print(f"  {CATEGORIES_FILE}")
            print(f"\n  Next steps:")
            print(f"  1. Review changes: git diff {CATEGORIES_FILE.relative_to(PROJECT_ROOT)}")
            print(f"  2. Run dbt: cd pipeline_personal_finance/dbt_finance && dbt run")
            print(f"  3. Verify in Grafana dashboards")
    else:
        print("\n  No changes made.")


if __name__ == '__main__':
    main()
