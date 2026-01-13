{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['account_name'], 'unique': false},
      {'columns': ['category','subcategory','store'], 'unique': false}
    ]
  )
}}

-- Export-ready suggestions for banking_categories.csv
-- Outputs both structured fields and a single csv_row for easy copy/paste

WITH
  ft AS (
    SELECT * FROM {{ ref('fct_transactions') }}
  ),
  dc AS (
    SELECT * FROM {{ ref('dim_categories') }}
  ),
  da AS (
    SELECT * FROM {{ ref('dim_accounts') }}
  ),

  -- Uncategorized side
  uncat_base AS (
    SELECT
      ft.account_key,
      COALESCE(ft.transaction_description, ft.transaction_memo) AS text_raw,
      ft.transaction_memo AS sample_memo
    FROM ft
    JOIN dc ON ft.category_key = dc.category_key
    WHERE dc.category = 'Uncategorized'
      AND COALESCE(ft.transaction_description, ft.transaction_memo) IS NOT NULL
      AND LENGTH(TRIM(COALESCE(ft.transaction_description, ft.transaction_memo))) > 1
  ),

  uncat_norm AS (
    SELECT
      account_key,
      UPPER(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            REGEXP_REPLACE(
              REGEXP_REPLACE(text_raw, 'Receipt\\s+[0-9]+', ' ', 'gi'),
              'Date\\s+\\d{2}\\s+[A-Za-z]{3}\\s+\\d{4}', ' ', 'gi'
            ),
            'Card\\s+[\\dx]+', ' ', 'gi'
          ),
          '[^A-Za-z]+' , ' ', 'g'
        )
      ) AS memo_norm,
      MIN(sample_memo) AS sample_memo
    FROM uncat_base
    GROUP BY 1,2
  ),

  -- Categorized side (training base)
  cat_base AS (
    SELECT
      UPPER(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            REGEXP_REPLACE(
              REGEXP_REPLACE(COALESCE(ft.transaction_description, ft.transaction_memo), 'Receipt\\s+[0-9]+', ' ', 'gi'),
              'Date\\s+\\d{2}\\s+[A-Za-z]{3}\\s+\\d{4}', ' ', 'gi'
            ),
            'Card\\s+[\\dx]+', ' ', 'gi'
          ),
          '[^A-Za-z]+' , ' ', 'g'
        )
      ) AS memo_norm,
      dc.category,
      dc.subcategory,
      dc.store,
      dc.internal_indicator,
      COUNT(*) AS support_count
    FROM ft
    JOIN dc ON ft.category_key = dc.category_key
    WHERE dc.category <> 'Uncategorized'
      AND COALESCE(ft.transaction_description, ft.transaction_memo) IS NOT NULL
      AND LENGTH(TRIM(COALESCE(ft.transaction_description, ft.transaction_memo))) > 1
    GROUP BY 1,2,3,4,5
  ),

  cat_totals AS (
    SELECT memo_norm, SUM(support_count) AS total_support
    FROM cat_base
    GROUP BY 1
  ),

  cat_ranked AS (
    SELECT
      cb.*,
      ct.total_support,
      (cb.support_count::numeric / NULLIF(ct.total_support, 0)) AS confidence,
      ROW_NUMBER() OVER (
        PARTITION BY cb.memo_norm
        ORDER BY cb.support_count DESC, cb.category, cb.subcategory, cb.store
      ) AS rnk
    FROM cat_base cb
    JOIN cat_totals ct ON ct.memo_norm = cb.memo_norm
  ),

  cat_best AS (
    SELECT * FROM cat_ranked WHERE rnk = 1
  ),

  -- Exact memo_norm matches
  exact_matches AS (
    SELECT
      u.account_key,
      u.memo_norm,
      u.sample_memo,
      b.category, b.subcategory, b.store, b.internal_indicator,
      b.support_count, b.total_support,
      NULL::numeric AS jaccard,
      b.confidence
    FROM uncat_norm u
    JOIN cat_best b ON b.memo_norm = u.memo_norm
  ),

  -- Token-based fuzzy matching
  stopwords AS (
    SELECT unnest(ARRAY[
      'THE','TO','FROM','PAYMENT','TRANSFER','DEBIT','CREDIT','CARD','DATE','RECEIPT','IN','OF','AND','AT','ONLINE','PURCHASE','DIRECT','ORDER','AUTOPAY','MONTHLY','SERVICE','FEE','INTEREST','BANK','TRANSACTION','VISA','EFTPOS','WITHDRAWAL','NETT','ADVANCE'
    ]) AS sw
  ),

  un_tokens AS (
    SELECT u.memo_norm AS un_memo_norm, tok AS token
    FROM (SELECT DISTINCT memo_norm FROM uncat_norm) u
    {% if target.type == 'duckdb' %}
    CROSS JOIN UNNEST(regexp_split_to_array(u.memo_norm, '\\s+')) AS tok(tok)
    {% else %}
    CROSS JOIN LATERAL regexp_split_to_table(u.memo_norm, '\\s+') AS tok
    {% endif %}
    WHERE length(tok) >= 3 AND tok ~ '[A-Z]+' AND tok NOT IN (SELECT sw FROM stopwords)
  ),

  ca_tokens AS (
    SELECT c.memo_norm AS ca_memo_norm, tok AS token
    FROM (SELECT DISTINCT memo_norm FROM cat_base) c
    {% if target.type == 'duckdb' %}
    CROSS JOIN UNNEST(regexp_split_to_array(c.memo_norm, '\\s+')) AS tok(tok)
    {% else %}
    CROSS JOIN LATERAL regexp_split_to_table(c.memo_norm, '\\s+') AS tok
    {% endif %}
    WHERE length(tok) >= 3 AND tok ~ '[A-Z]+' AND tok NOT IN (SELECT sw FROM stopwords)
  ),

  un_sizes AS (
    SELECT un_memo_norm, COUNT(DISTINCT token) AS un_sz
    FROM un_tokens
    GROUP BY 1
  ),

  ca_sizes AS (
    SELECT ca_memo_norm, COUNT(DISTINCT token) AS ca_sz
    FROM ca_tokens
    GROUP BY 1
  ),

  pair_overlap AS (
    SELECT u.un_memo_norm, c.ca_memo_norm, COUNT(DISTINCT u.token) AS overlap
    FROM un_tokens u
    JOIN ca_tokens c ON c.token = u.token
    GROUP BY 1,2
  ),

  pair_scored AS (
    SELECT
      p.un_memo_norm,
      p.ca_memo_norm,
      p.overlap,
      us.un_sz,
      cs.ca_sz,
      (p.overlap::numeric / NULLIF(us.un_sz + cs.ca_sz - p.overlap, 0)) AS jaccard,
      ROW_NUMBER() OVER (
        PARTITION BY p.un_memo_norm
        ORDER BY (p.overlap::numeric / NULLIF(us.un_sz + cs.ca_sz - p.overlap, 0)) DESC NULLS LAST, p.overlap DESC
      ) AS rnk
    FROM pair_overlap p
    JOIN un_sizes us ON us.un_memo_norm = p.un_memo_norm
    JOIN ca_sizes cs ON cs.ca_memo_norm = p.ca_memo_norm
  ),

  fuzzy_best AS (
    SELECT un_memo_norm, ca_memo_norm, overlap, un_sz, ca_sz, jaccard
    FROM pair_scored
    WHERE rnk = 1 AND COALESCE(jaccard, 0) >= 0.2
  ),

  fuzzy_matches AS (
    SELECT
      u.account_key,
      u.memo_norm,
      u.sample_memo,
      b.category, b.subcategory, b.store, b.internal_indicator,
      b.support_count, b.total_support,
      f.jaccard,
      b.confidence
    FROM uncat_norm u
    JOIN fuzzy_best f ON f.un_memo_norm = u.memo_norm
    JOIN cat_best b ON b.memo_norm = f.ca_memo_norm
    LEFT JOIN exact_matches e ON e.memo_norm = u.memo_norm AND e.account_key = u.account_key
    WHERE e.memo_norm IS NULL
  ),

  combined AS (
    SELECT * FROM exact_matches
    UNION ALL
    SELECT * FROM fuzzy_matches
  )

SELECT
  -- Structured fields matching seeds/banking_categories.csv
  c.sample_memo                                AS transaction_description,
  CAST(NULL AS TEXT)                           AS transaction_type,
  CAST(NULL AS TEXT)                           AS sender,
  CAST(NULL AS TEXT)                           AS recipient,
  da.account_name                              AS account_name,
  c.category                                   AS category,
  c.subcategory                                AS subcategory,
  c.store                                      AS store,
  COALESCE(c.internal_indicator, 'External')   AS internal_indicator,

  -- Review/debug fields
  c.support_count,
  c.total_support,
  c.confidence,
  c.jaccard,
  c.memo_norm,

  -- Single ready-to-paste CSV cell
  concat_ws(',',
    '"' || replace(c.sample_memo, '"', '""') || '"',
    '""',
    '""',
    '""',
    '"' || replace(da.account_name, '"', '""') || '"',
    '"' || replace(c.category, '"', '""') || '"',
    '"' || replace(c.subcategory, '"', '""') || '"',
    '"' || replace(c.store, '"', '""') || '"',
    '"' || replace(COALESCE(c.internal_indicator, 'External'), '"', '""') || '"'
  ) AS csv_row

FROM combined c
JOIN da ON da.account_key = c.account_key
ORDER BY (c.jaccard IS NULL) ASC, c.jaccard DESC NULLS LAST, da.account_name, c.sample_memo
